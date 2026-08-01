import asyncio

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from ia_agent.auth import is_authorized
from ia_agent.events.bus import EventBus
from ia_agent.pairing import PairingStore


def create_ws_router(bus: EventBus, token: str, pairing_store: PairingStore) -> APIRouter:
    router = APIRouter()

    @router.websocket("/ws")
    async def ws(websocket: WebSocket) -> None:
        # BaseHTTPMiddleware (auth.py) only wraps the http scope, not websocket,
        # so the bearer check has to happen here instead.
        auth_header = websocket.headers.get("authorization", "")
        credential = auth_header.removeprefix("Bearer ") if auth_header else websocket.query_params.get("token", "")
        if not is_authorized(credential, token, pairing_store):
            await websocket.close(code=4401)
            return

        await websocket.accept()
        queue = bus.subscribe()
        try:
            while True:
                receive_task = asyncio.ensure_future(websocket.receive())
                send_task = asyncio.ensure_future(queue.get())
                done, pending = await asyncio.wait(
                    {receive_task, send_task}, return_when=asyncio.FIRST_COMPLETED
                )
                for task in pending:
                    task.cancel()

                if receive_task in done:
                    message = receive_task.result()
                    if message.get("type") == "websocket.disconnect":
                        break
                if send_task in done:
                    await websocket.send_json(send_task.result())
        except WebSocketDisconnect:
            pass
        finally:
            bus.unsubscribe(queue)

    return router
