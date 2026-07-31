from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ia_agent.scheduler import KNOWN_COMMANDS, SchedulerMirror


class CommandRequest(BaseModel):
    command: str


def create_scheduler_router(mirror: SchedulerMirror) -> APIRouter:
    router = APIRouter(prefix="/api/scheduler")

    @router.get("")
    async def get_scheduler() -> dict:
        return mirror.snapshot()

    @router.post("/heartbeat")
    async def heartbeat(state: dict[str, Any]) -> dict:
        """The pod cannot accept inbound connections, so it drives the
        exchange: it posts its state here and the response carries back
        whatever commands were queued for that flow (ARCHITECTURE §4.4)."""
        commands = mirror.heartbeat(state)
        await mirror.broadcast_if_changed()
        return {"commands": commands}

    @router.post("/{flow}/command")
    async def queue_command(flow: str, body: CommandRequest) -> dict:
        if body.command not in KNOWN_COMMANDS:
            raise HTTPException(
                status_code=400, detail=f"unknown command: {body.command}"
            )
        mirror.queue_command(flow, body.command)
        return {"queued": True, "flow": flow, "command": body.command}

    return router
