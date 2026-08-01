from typing import Any

from fastapi import APIRouter

from ia_agent.events.store import EventStore


def create_events_router(store: EventStore) -> APIRouter:
    router = APIRouter(prefix="/api/events")

    @router.post("")
    async def post_event(event: dict[str, Any]) -> dict:
        entry = await store.record(event)
        return {"id": entry["id"], "seq": entry["seq"], "image_key": entry["image_key"]}

    @router.get("")
    async def list_events(since: int | None = None) -> list[dict]:
        return store.tail(since)

    return router
