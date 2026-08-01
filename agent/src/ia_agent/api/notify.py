from typing import Any

from fastapi import APIRouter, HTTPException

from ia_agent.notifications import NotificationStore


def create_notify_router(store: NotificationStore) -> APIRouter:
    router = APIRouter(prefix="/api/notify")

    @router.post("")
    async def post_notify(payload: dict[str, Any]) -> dict:
        entry = await store.add(payload)
        targets = await store.publish(entry)
        return {"delivered": targets > 0, "targets": targets, "id": entry["id"]}

    @router.get("")
    async def list_notifications(since: int | None = None, unread_only: bool = False) -> list[dict]:
        return store.tail(since, unread_only)

    @router.post("/{notification_id}/read")
    async def read_one(notification_id: str) -> dict:
        if not store.mark_read(notification_id):
            raise HTTPException(status_code=404, detail="unknown notification")
        return {"read": notification_id}

    @router.post("/read-all")
    async def read_all() -> dict:
        return {"marked": store.mark_all_read()}

    return router
