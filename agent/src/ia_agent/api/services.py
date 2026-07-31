import asyncio

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from ia_agent.services.supervisor import ServiceError, Supervisor


class ServiceSettings(BaseModel):
    self_heal: bool | None = None
    autostart: bool | None = None


class TerminalSize(BaseModel):
    rows: int = Field(ge=1, le=500)
    cols: int = Field(ge=20, le=1000)


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

    @router.patch("/services/{name}")
    async def configure(name: str, settings: ServiceSettings) -> dict:
        service = _service(name)
        service.configure(self_heal=settings.self_heal, autostart=settings.autostart)
        return service.status()

    @router.get("/services/{name}/logs")
    async def get_logs(name: str, since: int | None = None) -> dict:
        """Raw terminal chunks, replayable from a cursor. The whole ring is returned
        when there is no cursor — a terminal emulator has to replay from the start of
        what it has to reconstruct the screen, unlike a log list that can show a tail."""
        service = _service(name)
        return {
            "name": name,
            "terminal_available": service.status()["terminal_available"],
            "chunks": service.ring.tail(since),
        }

    @router.post("/services/{name}/resize")
    async def resize(name: str, size: TerminalSize) -> dict:
        service = _service(name)
        service.resize(size.rows, size.cols)
        return {"rows": size.rows, "cols": size.cols}

    @router.post("/services/{name}/test")
    async def run_test(name: str) -> dict:
        service = _service(name)
        try:
            outcome = await service.run_test()
        except ServiceError as error:
            raise HTTPException(status_code=409, detail=str(error))
        # 200 whether it passed or failed — a failing test is a valid answer, not a
        # transport error, and the UI needs the metrics either way.
        return outcome.as_dict()

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
