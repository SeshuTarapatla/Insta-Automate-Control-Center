"""Flow-event replay ring (CP 4.2, ARCHITECTURE §5).

Events arrive from the pipeline's `emit()` calls (fire-and-forget, 1 s
timeout, failures swallowed on that side — CP 4.3 wires the call sites, none
exist yet). Accepted as a loose dict rather than a strict pydantic model, the
same choice `SchedulerMirror.heartbeat` made (D26/D27's precedent): a
validation error here would be a dropped event the pipeline can never learn
about, since it isn't listening for a response beyond 2xx/timeout.
"""
import asyncio
import threading
import time
import uuid
from typing import Any

from ia_agent import images
from ia_agent.events.bus import EventBus

MAX_EVENTS = 5000


class EventStore:
    def __init__(self, bus: EventBus) -> None:
        self._bus = bus
        self._lock = threading.Lock()
        self._events: list[dict[str, Any]] = []
        self._seq = 0

    async def record(self, event: dict[str, Any]) -> dict[str, Any]:
        image_rel = event.get("image")
        image_key = await asyncio.to_thread(images.cache, image_rel) if image_rel else None
        with self._lock:
            self._seq += 1
            entry = {
                **event,
                "seq": self._seq,
                "id": event.get("id") or str(uuid.uuid4()),
                "ts": event.get("ts") or time.time(),
                "image_key": image_key,
            }
            self._events.append(entry)
            if len(self._events) > MAX_EVENTS:
                self._events.pop(0)
        await self._bus.publish("flow.events", entry)
        return entry

    def tail(self, since: int | None = None) -> list[dict[str, Any]]:
        with self._lock:
            events = list(self._events)
        if since is None:
            return events
        return [event for event in events if event["seq"] > since]
