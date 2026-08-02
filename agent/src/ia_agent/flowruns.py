"""Flow-run log aggregation (CP 4.1, ARCHITECTURE §5.2).

Prefect exposes no log stream, so this polls `POST /api/logs/filter` per
active flow run (~1s) and separately tails the scheduler pod's own container
log via the k8s API — that's where trigger decisions and gate reasons print,
not inside any flow run. The two are merged by writing scheduler-pod lines
into the ring of every run that is active *when the line is observed*: seq is
assigned in append order (D18's precedent — the ring's own write order is the
source of truth, not wall-clock time), so replay-by-seq stays correct even
though a scheduler line and a flow line polled in the same tick have no
guaranteed timestamp relationship.

Active-run discovery prefers the scheduler heartbeat (`phase == "running"` ->
its `last_run.id` is the run in progress) and falls back to asking Prefect
directly for RUNNING flow runs among the five deployments — needed right
after an agent restart, before any heartbeat has arrived, or while the
scheduler mirror is offline.
"""
import asyncio
import logging
import re
import threading
import time
from datetime import datetime
from typing import Any

from ia_agent.events.bus import EventBus
from ia_agent.integrations import kube, prefect
from ia_agent.scheduler import SchedulerMirror

TICK = 1.0
MAX_ENTRIES = 4000  # per-run ring cap
RETENTION_RUNS = 20  # tracked rings kept for replay before the oldest is dropped
FINISHED_GRACE = 5.0  # seconds a just-finished run is still polled, to catch trailing logs

FLOWS = ["entity-ingest", "entity-scan", "entity-classify", "entity-scrape", "entity-follow"]
SCHEDULER_POD_DEPLOYMENT = "insta-automate"  # runs `ia prefect serve` — the trigger loops

# `my_modules.logger`'s RichHandler renders one column layout per record:
# `[date] time LEVEL   message...   file.py:line`, right-justifying the
# source column onto the *first* physical line and wrapping any message text
# that doesn't fit onto plain continuation lines with none of the above -
# `kube.pod_logs`'s own docstring already flags this as an unhandled gap.
# `_RICH_LINE` recognizes a record's first line and captures its level; a
# line that doesn't match is a continuation of whatever's pending.
_RICH_LINE = re.compile(r"^\[\d{4}-\d{2}-\d{2}\]\s+\d{2}:\d{2}:\d{2}\s+(\w+)\s+(.*)$")
_TRAILING_SOURCE = re.compile(r"\s{2,}\S+\.py:\d+\s*$")
# Set by `controllers.prefect`'s `_FlowTagFilter` (Insta-Automate, D60) on
# every record logged from within a trigger loop's own task context - the
# only way to attribute a scheduler-pod line to one specific flow, since all
# five loops share one process/one stdout stream.
_FLOW_TAG = re.compile(r"^\[(entity-[a-z]+)\]\s*")


def parse_ts(value: str) -> float:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


class Ring:
    """Structured log entries for one flow run (or None, for a source with no
    single run — kept generic so the same class serves both)."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._entries: list[dict[str, Any]] = []
        self._seq = 0

    def append(self, *, ts: float, source: str, level: str, task: str | None, message: str) -> dict:
        with self._lock:
            self._seq += 1
            entry = {
                "seq": self._seq, "ts": ts, "source": source,
                "level": level, "task": task, "message": message,
            }
            self._entries.append(entry)
            if len(self._entries) > MAX_ENTRIES:
                self._entries.pop(0)
            return entry

    def tail(self, since: int | None = None) -> list[dict]:
        with self._lock:
            entries = list(self._entries)
        if since is None:
            return entries
        return [entry for entry in entries if entry["seq"] > since]


class _TrackedRun:
    def __init__(self, flow: str, run_id: str, start_time: str | None) -> None:
        self.flow = flow
        self.run_id = run_id
        self.ring = Ring()
        self.cursor: str | None = start_time
        self.seen_at_cursor: set[str] = set()
        self.active = True
        self.finished_at: float | None = None


class FlowRunTailer:
    def __init__(self, bus: EventBus, scheduler_mirror: SchedulerMirror) -> None:
        self._bus = bus
        self._mirror = scheduler_mirror
        self._lock = threading.Lock()
        self._runs: dict[str, _TrackedRun] = {}
        self._run_order: list[str] = []  # oldest-first, for LRU eviction
        self._deployment_ids: dict[str, str] = {}
        self._task_names: dict[str, str | None] = {}
        self._scheduler_cursor: float | None = None
        self._scheduler_pending: dict[str, str] | None = None  # {"level", "message"} - a record still being joined
        self._task: asyncio.Task | None = None

    # ------------------------------------------------------------- lifecycle

    async def start(self) -> None:
        self._task = asyncio.create_task(self._loop())

    async def shutdown(self) -> None:
        if self._task is None:
            return
        self._task.cancel()
        try:
            await self._task
        except asyncio.CancelledError:
            pass

    async def _loop(self) -> None:
        while True:
            try:
                await self._tick()
            except Exception:
                from ia_agent.logging import logger
                logger.exception("flow-run log tailer tick failed")
            await asyncio.sleep(TICK)

    # ---------------------------------------------------------- run lookup

    def run(self, run_id: str) -> _TrackedRun | None:
        with self._lock:
            return self._runs.get(run_id)

    def known_runs(self) -> list[_TrackedRun]:
        with self._lock:
            return [self._runs[rid] for rid in self._run_order]

    # ----------------------------------------------------------------- tick

    async def _tick(self) -> None:
        active = await self._discover_active()
        active_run_ids = set(active.values())

        for flow, run_id in active.items():
            await self._ensure_tracked(flow, run_id)

        for tracked in self.known_runs():
            still_active = tracked.run_id in active_run_ids
            if tracked.active and not still_active:
                tracked.active = False
                tracked.finished_at = time.time()
            if tracked.active or (
                tracked.finished_at is not None and time.time() - tracked.finished_at < FINISHED_GRACE
            ):
                await self._poll_run(tracked)

        await self._poll_scheduler_pod(active_run_ids)
        self._evict()

    async def _discover_active(self) -> dict[str, str]:
        snapshot = self._mirror.snapshot()
        found = {}
        for flow, state in snapshot.get("flows", {}).items():
            if state.get("phase") != "running":
                continue
            last_run = state.get("last_run") or {}
            if last_run.get("id"):
                found[flow] = last_run["id"]
        if snapshot.get("online") and found:
            return found
        return await self._discover_active_via_api()

    async def deployment_ids(self) -> dict[str, str]:
        """Resolved once per flow, then cached — used both by fallback
        discovery and by the REST listing endpoint, which needs ids to ask
        Prefect for recent runs across all five deployments at once."""
        for flow in FLOWS:
            if flow not in self._deployment_ids:
                resolved = await prefect.deployment_id(flow)
                if resolved:
                    self._deployment_ids[flow] = resolved
        return dict(self._deployment_ids)

    async def _discover_active_via_api(self) -> dict[str, str]:
        ids = await self.deployment_ids()
        if not ids:
            return {}
        by_deployment_id = {v: k for k, v in ids.items()}
        runs = await prefect.flow_runs_filter(
            deployment_ids=list(ids.values()), state_types=["RUNNING"], limit=len(ids)
        )
        found = {}
        for run in runs:
            flow = by_deployment_id.get(run.get("deployment_id"))
            if flow and flow not in found:
                found[flow] = run["id"]
        return found

    async def _ensure_tracked(self, flow: str, run_id: str) -> None:
        with self._lock:
            existing = self._runs.get(run_id)
            if existing is not None:
                existing.active = True
                existing.finished_at = None
                return
        info = await prefect.flow_run(run_id)
        start_time = (info or {}).get("start_time") or (info or {}).get("expected_start_time")
        tracked = _TrackedRun(flow, run_id, start_time)
        with self._lock:
            self._runs[run_id] = tracked
            self._run_order.append(run_id)

    async def _poll_run(self, tracked: _TrackedRun) -> None:
        rows = await prefect.run_logs(tracked.run_id, after=tracked.cursor)
        new_rows = [row for row in rows if row["id"] not in tracked.seen_at_cursor]
        if not new_rows:
            return
        for row in new_rows:
            task = None
            task_run_id = row.get("task_run_id")
            if task_run_id:
                task = await self._task_name(task_run_id)
            entry = tracked.ring.append(
                ts=parse_ts(row["timestamp"]),
                source="flow",
                level=logging.getLevelName(row.get("level", 20)),
                task=task,
                message=row["message"],
            )
            await self._bus.publish(
                "flowrun.logs", {"flow_run_id": tracked.run_id, "flow": tracked.flow, **entry}
            )
        last_ts = new_rows[-1]["timestamp"]
        tracked.cursor = last_ts
        tracked.seen_at_cursor = {row["id"] for row in new_rows if row["timestamp"] == last_ts}

    async def _task_name(self, task_run_id: str) -> str | None:
        if task_run_id not in self._task_names:
            self._task_names[task_run_id] = await prefect.task_run_name(task_run_id)
        return self._task_names[task_run_id]

    async def _poll_scheduler_pod(self, active_run_ids: set[str]) -> None:
        since_seconds = None
        if self._scheduler_cursor is not None:
            since_seconds = int(time.time() - self._scheduler_cursor) + 2
        raw_lines = await asyncio.to_thread(
            kube.pod_logs, SCHEDULER_POD_DEPLOYMENT, since_seconds
        )
        if not raw_lines:
            return
        # since_seconds is a coarse relative window (D30's kube.pod_logs), so
        # the boundary overlaps what was already consumed - re-filter by the
        # exact parsed timestamp against the cursor rather than trusting it.
        parsed = [(ts, parse_ts(ts), text) for ts, text in raw_lines]
        if self._scheduler_cursor is not None:
            parsed = [row for row in parsed if row[1] > self._scheduler_cursor]
        if not parsed:
            return
        self._scheduler_cursor = parsed[-1][1]

        for _, _, text in parsed:
            if not text.strip():
                continue
            start = _RICH_LINE.match(text)
            if start:
                await self._flush_scheduler_pending(active_run_ids)
                level, rest = start.group(1), start.group(2)
                self._scheduler_pending = {"level": level, "message": _TRAILING_SOURCE.sub("", rest).rstrip()}
            elif self._scheduler_pending is not None:
                # A wrapped continuation of the pending record - joined
                # rather than shown as its own disconnected fragment
                # (previously: "Triggering:" / "Deployment(...)" / "- attempt
                # 1" as three separate log rows for one logical message).
                continuation = _TRAILING_SOURCE.sub("", text).strip()
                if continuation:
                    self._scheduler_pending["message"] += " " + continuation
            # else: a continuation line with nothing pending to attach to
            # (e.g. right after an agent restart mid-message) - dropped.

        # Flushed at the end of every tick rather than held for a future
        # continuation that might still be coming - keeps the console
        # current. The rare cost is a message that straddles exactly a poll
        # boundary losing its still-in-flight tail, not a wrong-flow mix-up.
        await self._flush_scheduler_pending(active_run_ids)

    async def _flush_scheduler_pending(self, active_run_ids: set[str]) -> None:
        pending = self._scheduler_pending
        if pending is None:
            return
        self._scheduler_pending = None
        message = pending["message"].strip()
        if not message:
            return
        tagged = _FLOW_TAG.match(message)
        if not tagged:
            # No consumer for a flow-agnostic scheduler stream today (the
            # startup banner, telegram-keepalive) - dropped rather than
            # broadcast to every active run, which is the noise this whole
            # rewrite exists to remove.
            return
        flow = tagged.group(1)
        message = message[tagged.end():]
        targets = [
            tracked for tracked in self.known_runs()
            if tracked.flow == flow and tracked.run_id in active_run_ids
        ]
        for tracked in targets:
            entry = tracked.ring.append(
                ts=time.time(), source="scheduler", level=pending["level"], task=None, message=message
            )
            await self._bus.publish(
                "flowrun.logs", {"flow_run_id": tracked.run_id, "flow": tracked.flow, **entry}
            )

    def _evict(self) -> None:
        with self._lock:
            while len(self._run_order) > RETENTION_RUNS:
                victim = next((rid for rid in self._run_order if not self._runs[rid].active), None)
                if victim is None:
                    break
                self._run_order.remove(victim)
                del self._runs[victim]
