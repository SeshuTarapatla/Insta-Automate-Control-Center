import asyncio
from typing import Any


class EventBus:
    """In-process pub/sub for the single /ws endpoint. Every connected client
    currently receives every published event tagged with its channel; per-client
    channel filtering can be added once there is more than one channel competing
    for bandwidth.

    Each subscriber is tagged with the device id that authenticated its
    connection, or `None` for the desktop — this is what lets a notification's
    `targets` count mean "reached a phone" rather than "someone, possibly just
    the desktop, is connected" (see `notifications.py::publish`)."""

    def __init__(self) -> None:
        self._queues: dict[asyncio.Queue, str | None] = {}

    def subscribe(self, device_id: str | None = None) -> asyncio.Queue:
        queue: asyncio.Queue = asyncio.Queue()
        self._queues[queue] = device_id
        return queue

    def unsubscribe(self, queue: asyncio.Queue) -> None:
        self._queues.pop(queue, None)

    def subscriber_count(self, devices_only: bool = False) -> int:
        if not devices_only:
            return len(self._queues)
        return sum(1 for device_id in self._queues.values() if device_id is not None)

    def device_ids(self) -> set[str]:
        return {device_id for device_id in self._queues.values() if device_id is not None}

    async def publish(self, channel: str, data: Any) -> None:
        message = {"channel": channel, "data": data}
        for queue in list(self._queues):
            await queue.put(message)
