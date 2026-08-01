import asyncio
from typing import Any


class EventBus:
    """In-process pub/sub for the single /ws endpoint. Every connected client
    currently receives every published event tagged with its channel; per-client
    channel filtering can be added once there is more than one channel competing
    for bandwidth."""

    def __init__(self) -> None:
        self._queues: set[asyncio.Queue] = set()

    def subscribe(self) -> asyncio.Queue:
        queue: asyncio.Queue = asyncio.Queue()
        self._queues.add(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue) -> None:
        self._queues.discard(queue)

    def subscriber_count(self) -> int:
        return len(self._queues)

    async def publish(self, channel: str, data: Any) -> None:
        message = {"channel": channel, "data": data}
        for queue in list(self._queues):
            await queue.put(message)
