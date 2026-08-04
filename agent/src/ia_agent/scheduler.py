"""In-memory mirror of the pipeline pod's scheduler state (CP 3.4).

The pod cannot accept inbound connections, so it drives the exchange: it
POSTs its per-flow state to `/api/scheduler/heartbeat` roughly every 2s
(`insta_automate.controllers.agent.AgentClient.heartbeat`, Insta-Automate
CP 3.3) and the response body carries back any commands queued for that
flow (ARCHITECTURE §4.4) - one endpoint, bidirectional, no inbound
networking, no polling files.

Nothing calls that client method from the scheduler's trigger loops yet -
this is the receiving half only. `flows.state` will publish nothing but
`online: false` until a later checkpoint wires `Prefect.serve()` up to send
real heartbeats.
"""
import asyncio
import threading
import time
from typing import Any

from ia_agent.events.bus import EventBus

STALE_AFTER = 15.0  # no heartbeat this long -> the scheduler reads offline
WATCHDOG_TICK = 3.0

KNOWN_COMMANDS = {
    "run_now", "force_run", "skip_wait", "pause", "resume", "reload_config", "reduce_reserve",
}


class SchedulerMirror:
    def __init__(self, bus: EventBus) -> None:
        self._bus = bus
        self._lock = threading.RLock()
        self._flows: dict[str, dict[str, Any]] = {}
        self._commands: dict[str, list[dict[str, Any]]] = {}
        self._last_heartbeat_at: float | None = None
        self._signature: tuple | None = None
        self._task: asyncio.Task | None = None

    # ------------------------------------------------------------------ API

    def heartbeat(self, state: dict[str, Any]) -> list[dict[str, Any]]:
        """Record one flow's state block and hand back (clearing) whatever
        commands were queued for it since its last heartbeat."""
        flow = state.get("flow")
        with self._lock:
            self._last_heartbeat_at = time.time()
            if not flow:
                return []
            self._flows[flow] = state
            return self._commands.pop(flow, [])

    def queue_command(self, flow: str, command: str) -> None:
        with self._lock:
            self._commands.setdefault(flow, []).append(
                {"command": command, "queued_at": time.time()}
            )

    def online(self) -> bool:
        with self._lock:
            return (
                self._last_heartbeat_at is not None
                and time.time() - self._last_heartbeat_at < STALE_AFTER
            )

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            return {
                "online": self.online(),
                "last_heartbeat_at": self._last_heartbeat_at,
                "flows": dict(self._flows),
            }

    # ----------------------------------------------------------------- tick

    def _signature_of(self, snapshot: dict[str, Any]) -> tuple:
        return (
            snapshot["online"],
            tuple(
                (name, flow.get("switch"), flow.get("phase"), flow.get("next_trigger_at"))
                for name, flow in sorted(snapshot["flows"].items())
            ),
        )

    async def broadcast_if_changed(self) -> None:
        snapshot = self.snapshot()
        signature = self._signature_of(snapshot)
        if signature != self._signature:
            self._signature = signature
            await self._bus.publish("flows.state", snapshot)

    async def _watchdog(self) -> None:
        """Nothing else re-checks staleness once heartbeats stop arriving -
        without this loop, a scheduler that goes silent would leave the UI
        showing its last-known state forever instead of flipping to
        offline."""
        while True:
            await self.broadcast_if_changed()
            await asyncio.sleep(WATCHDOG_TICK)

    async def start(self) -> None:
        self._task = asyncio.create_task(self._watchdog())

    async def shutdown(self) -> None:
        if self._task is None:
            return
        self._task.cancel()
        try:
            await self._task
        except asyncio.CancelledError:
            pass
