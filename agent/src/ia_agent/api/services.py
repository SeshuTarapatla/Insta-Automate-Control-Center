import asyncio

from fastapi import APIRouter, HTTPException

from ia_agent.services.supervisor import ServiceError, Supervisor


def create_services_router(supervisor: Supervisor) -> APIRouter:
    router = APIRouter(prefix="/api")

    def _service(name: str):
        try:
            return supervisor.get(name)
        except KeyError:
            raise HTTPException(status_code=404, detail=f"unknown service: {name}")

    @router.get("/services")
    async def list_services() -> list[dict]:
        return supervisor.statuses()

    @router.get("/services/{name}")
    async def get_service(name: str) -> dict:
        return _service(name).status()

    @router.get("/services/{name}/logs")
    async def get_logs(name: str, tail: int = 500, since: int | None = None) -> dict:
        service = _service(name)
        return {
            "name": name,
            "stdout_available": service.status()["stdout_available"],
            "lines": service.ring.tail(tail, since),
        }

    @router.post("/services/{name}/{action}")
    async def act(name: str, action: str) -> dict:
        service = _service(name)
        handler = {
            "start": service.start,
            "stop": service.stop,
            "restart": service.restart,
            "takeover": service.takeover,
        }.get(action)
        if handler is None:
            raise HTTPException(status_code=404, detail=f"unknown action: {action}")

        try:
            # start/stop kill process trees and wait on them — off the event loop so
            # a slow terminate can't stall probes or the WS fan-out.
            await asyncio.to_thread(handler)
        except ServiceError as error:
            raise HTTPException(status_code=409, detail=str(error))

        return service.status()

    return router
