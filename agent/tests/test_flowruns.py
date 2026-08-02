"""Flow-run log aggregation (CP 4.1) — active-run discovery (heartbeat-driven,
falling back to a direct Prefect query), per-run log polling with task-name
resolution, the scheduler pod's container log merged into whichever runs are
active when a line is observed, ring replay by `seq`, and eviction.

Prefect and the k3s cluster are never touched: every function in
`ia_agent.integrations.prefect` and `ia_agent.integrations.kube` that
`FlowRunTailer` calls is monkeypatched at module scope before anything runs,
exactly like `test_scheduler.py` does for `build_specs`. The fakes are pure
functions of their arguments (a canned row list filtered by the `after`/
`since_time` cursor) rather than stateful counters, so the live app's
background tick — which fires every `TICK` second for the whole test — always
converges to the same answer no matter how many times it runs.
"""
import asyncio
import json
import sys
import threading
import time

import httpx
import uvicorn
import websockets

import ia_agent.integrations.kube as kube
import ia_agent.integrations.prefect as prefect
from ia_agent.events.bus import EventBus
from ia_agent.flowruns import FLOWS, FlowRunTailer, Ring, parse_ts
from ia_agent.scheduler import SchedulerMirror

OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


# ------------------------------------------------------------------- fixtures

DEPLOYMENT_IDS = {flow: f"dep-{flow}" for flow in FLOWS}
ACTIVE_RUN_ID = "run-active-1"
OLD_RUN_ID = "run-completed-1"

RUN_LOGS = [
    {"id": "log-1", "timestamp": "2026-08-01T10:00:00.000000Z", "message": "started", "level": 20, "task_run_id": None},
    {"id": "log-2", "timestamp": "2026-08-01T10:00:01.000000Z", "message": "step one", "level": 20, "task_run_id": "task-1"},
    {"id": "log-3", "timestamp": "2026-08-01T10:00:01.000000Z", "message": "step one (same tick)", "level": 20, "task_run_id": "task-1"},
    {"id": "log-4", "timestamp": "2026-08-01T10:00:02.000000Z", "message": "warning raised", "level": 30, "task_run_id": None},
]

POD_LINES = [
    # A tagged, single-line record for the run under test.
    ("2026-08-01T10:00:00.500000000Z",
     "[2026-08-01] 10:00:00 INFO     [entity-scrape] triggering run          prefect.py:100"),
    # A tagged record whose message wraps onto a plain continuation line with
    # no prefix of its own - my_modules.logger's RichHandler behavior
    # (D30/D60) that `_poll_scheduler_pod` has to reassemble.
    ("2026-08-01T10:00:01.500000000Z",
     "[2026-08-01] 10:00:01 INFO     [entity-scrape] gate ok,          prefect.py:101"),
    ("2026-08-01T10:00:01.600000000Z", "proceeding"),
    # Tagged for a *different* flow - must never land in entity-scrape's ring.
    ("2026-08-01T10:00:01.700000000Z",
     "[2026-08-01] 10:00:01 INFO     [entity-classify] unrelated line   prefect.py:200"),
    # No flow tag at all (startup banner, telegram-keepalive) - dropped.
    ("2026-08-01T10:00:01.800000000Z",
     "[2026-08-01] 10:00:01 INFO     Insta Automate Scheduler and Trigerrer started!  prefect.py:457"),
]


async def fake_deployment_id(flow, deployment=None):
    return DEPLOYMENT_IDS.get(flow)


async def fake_flow_run(flow_run_id):
    if flow_run_id == ACTIVE_RUN_ID:
        return {
            "id": ACTIVE_RUN_ID, "deployment_id": DEPLOYMENT_IDS["entity-scrape"],
            "state_type": "RUNNING", "start_time": "2026-08-01T09:59:59.000000Z",
            "end_time": None, "total_run_time": 0.0,
        }
    if flow_run_id == OLD_RUN_ID:
        return {
            "id": OLD_RUN_ID, "deployment_id": DEPLOYMENT_IDS["entity-scan"],
            "state_type": "COMPLETED", "start_time": "2026-08-01T08:00:00.000000Z",
            "end_time": "2026-08-01T08:05:00.000000Z", "total_run_time": 300.0,
        }
    return None


async def fake_flow_runs_filter(deployment_ids=None, state_types=None, limit=10):
    if state_types == ["RUNNING"]:
        return [{"id": ACTIVE_RUN_ID, "deployment_id": DEPLOYMENT_IDS["entity-scrape"]}]
    # unfiltered listing: one active, one completed
    return [
        {
            "id": ACTIVE_RUN_ID, "deployment_id": DEPLOYMENT_IDS["entity-scrape"],
            "state_type": "RUNNING", "start_time": "2026-08-01T09:59:59.000000Z",
            "end_time": None, "total_run_time": 0.0,
        },
        {
            "id": OLD_RUN_ID, "deployment_id": DEPLOYMENT_IDS["entity-scan"],
            "state_type": "COMPLETED", "start_time": "2026-08-01T08:00:00.000000Z",
            "end_time": "2026-08-01T08:05:00.000000Z", "total_run_time": 300.0,
        },
    ]


async def fake_run_logs(flow_run_id, after=None, limit=500):
    if flow_run_id != ACTIVE_RUN_ID:
        return []
    if after is None:
        return list(RUN_LOGS)
    return [row for row in RUN_LOGS if row["timestamp"] > after]


TASK_NAME_CALLS = []


async def fake_task_run_name(task_run_id):
    TASK_NAME_CALLS.append(task_run_id)
    return {"task-1": "gender_classify-0aa"}.get(task_run_id)


def fake_pod_logs(deployment, since_seconds=None, tail_lines=200):
    """Real k8s `since_seconds` is a coarse relative window, so a re-poll
    legitimately returns overlap — the fixture always hands back the full
    canned list, same as `tail_lines` would with no cursor at all, to prove
    `FlowRunTailer` does its own dedup against the exact parsed timestamp
    rather than trusting the k8s-side window."""
    return list(POD_LINES)


prefect.deployment_id = fake_deployment_id
prefect.flow_run = fake_flow_run
prefect.flow_runs_filter = fake_flow_runs_filter
prefect.run_logs = fake_run_logs
prefect.task_run_name = fake_task_run_name
kube.pod_logs = fake_pod_logs


def sample_state(flow="entity-scrape", phase="running", run_id=ACTIVE_RUN_ID):
    return {
        "flow": flow, "switch": True, "phase": phase,
        "next_trigger_at": None,
        "gate": {"ok": True, "reason": None, "detail": None},
        "today": None,
        "last_run": {"id": run_id, "state": "RUNNING", "duration_s": None},
    }


# ---------------------------------------------------------------- unit checks

async def ring_checks() -> None:
    print("\n1. Ring assigns monotonic seq and replays from a cursor")
    ring = Ring()
    first = ring.append(ts=1.0, source="flow", level="INFO", task=None, message="a")
    second = ring.append(ts=2.0, source="flow", level="INFO", task=None, message="b")
    check("seq starts at 1 and increments", first["seq"] == 1 and second["seq"] == 2)
    check("tail(None) returns everything", len(ring.tail(None)) == 2)
    check("tail(since) returns only newer entries", [e["seq"] for e in ring.tail(1)] == [2])


async def discovery_checks() -> None:
    print("\n2. active-run discovery prefers the heartbeat, falls back to the API")
    bus = EventBus()
    mirror = SchedulerMirror(bus)
    tailer = FlowRunTailer(bus, mirror)

    mirror.heartbeat(sample_state())
    active = await tailer._discover_active()
    check("heartbeat path finds the running flow", active == {"entity-scrape": ACTIVE_RUN_ID}, str(active))

    empty_mirror = SchedulerMirror(bus)
    empty_tailer = FlowRunTailer(bus, empty_mirror)
    active = await empty_tailer._discover_active()
    check("no heartbeat ever -> falls back to the API", active == {"entity-scrape": ACTIVE_RUN_ID}, str(active))

    print("\n3. ensure_tracked creates a ring seeded at the run's start_time")
    await tailer._ensure_tracked("entity-scrape", ACTIVE_RUN_ID)
    tracked = tailer.run(ACTIVE_RUN_ID)
    check("run is now tracked", tracked is not None)
    check("cursor seeded from Prefect's start_time", tracked.cursor == "2026-08-01T09:59:59.000000Z")
    check("starts active", tracked.active is True)

    print("\n4. re-discovering an already-tracked run just refreshes its flags, no duplicate")
    await tailer._ensure_tracked("entity-scrape", ACTIVE_RUN_ID)
    check("still exactly one tracked run", len(tailer.known_runs()) == 1)


async def poll_run_checks() -> None:
    print("\n5. polling a run appends new rows, dedupes the same-timestamp boundary, resolves task names")
    bus = EventBus()
    mirror = SchedulerMirror(bus)
    tailer = FlowRunTailer(bus, mirror)
    await tailer._ensure_tracked("entity-scrape", ACTIVE_RUN_ID)
    tracked = tailer.run(ACTIVE_RUN_ID)
    tracked.cursor = None  # force the full canned log to be read from the top

    published = []

    async def capture(channel, data):
        published.append((channel, data))

    bus.publish = capture
    await tailer._poll_run(tracked)
    messages = [e["message"] for e in tracked.ring.tail(None)]
    check("all four rows land, in order", messages == [row["message"] for row in RUN_LOGS], str(messages))
    check("the two same-timestamp rows both survive (id-deduped, not ts-deduped)",
          "step one" in messages and "step one (same tick)" in messages)
    check("level 20 became INFO and 30 became WARNING",
          [e["level"] for e in tracked.ring.tail(None)] == ["INFO", "INFO", "INFO", "WARNING"])
    check("the task_run_id resolved to a real name", tracked.ring.tail(None)[1]["task"] == "gender_classify-0aa")
    check("every new row was published on flowrun.logs",
          all(c == "flowrun.logs" for c, _ in published) and len(published) == 4)
    check("published entries carry the flow run id", published[0][1]["flow_run_id"] == ACTIVE_RUN_ID)

    print("\n6. a second poll with the advanced cursor finds nothing new")
    published.clear()
    await tailer._poll_run(tracked)
    check("no duplicate entries appended", len(tracked.ring.tail(None)) == 4)
    check("nothing re-published", published == [])

    print("\n7. task name resolution is cached, not re-fetched per row")
    check("only resolved once despite two rows sharing task-1", TASK_NAME_CALLS.count("task-1") == 1,
          str(TASK_NAME_CALLS))


async def scheduler_pod_checks() -> None:
    print("\n8. scheduler pod lines are routed by flow tag, joined across wraps, untagged dropped (D60)")
    bus = EventBus()
    mirror = SchedulerMirror(bus)
    tailer = FlowRunTailer(bus, mirror)
    await tailer._ensure_tracked("entity-scrape", ACTIVE_RUN_ID)
    classify_run_id = "run-classify-1"
    await tailer._ensure_tracked("entity-classify", classify_run_id)

    await tailer._poll_scheduler_pod(active_run_ids={ACTIVE_RUN_ID, classify_run_id})
    tracked = tailer.run(ACTIVE_RUN_ID)
    scheduler_entries = [e for e in tracked.ring.tail(None) if e["source"] == "scheduler"]
    check("only entity-scrape's two tagged lines landed in its own ring",
          len(scheduler_entries) == 2, str(scheduler_entries))
    check("the wrapped continuation was joined onto the record it belongs to",
          any(e["message"] == "gate ok, proceeding" for e in scheduler_entries), str(scheduler_entries))
    check("the flow tag itself was stripped from the displayed message",
          all(not e["message"].startswith("[entity-") for e in scheduler_entries), str(scheduler_entries))

    classify_tracked = tailer.run(classify_run_id)
    classify_entries = [e for e in classify_tracked.ring.tail(None) if e["source"] == "scheduler"]
    check("entity-classify's tagged line landed only in its own ring, not entity-scrape's",
          len(classify_entries) == 1 and classify_entries[0]["message"] == "unrelated line",
          str(classify_entries))

    check("cursor advanced to the last line's parsed timestamp",
          tailer._scheduler_cursor == parse_ts(POD_LINES[-1][0]))

    print("\n9. once nothing is active, new pod lines are not appended anywhere (cursor still advances)")
    tracked.active = False
    before = len(tracked.ring.tail(None))
    await tailer._poll_scheduler_pod(active_run_ids=set())
    check("no growth with no active runs", len(tracked.ring.tail(None)) == before)


async def eviction_checks() -> None:
    print("\n10. eviction drops the oldest *inactive* run once retention is exceeded, never an active one")
    import ia_agent.flowruns as flowruns_module
    original_retention = flowruns_module.RETENTION_RUNS
    flowruns_module.RETENTION_RUNS = 2
    try:
        bus = EventBus()
        mirror = SchedulerMirror(bus)
        tailer = FlowRunTailer(bus, mirror)
        await tailer._ensure_tracked("entity-scan", "run-a")
        await tailer._ensure_tracked("entity-scan", "run-b")
        tailer.run("run-a").active = False
        tailer.run("run-b").active = False
        await tailer._ensure_tracked("entity-scan", "run-c")  # still active
        tailer._evict()
        ids = {t.run_id for t in tailer.known_runs()}
        check("the oldest inactive run was dropped", "run-a" not in ids, str(ids))
        check("the still-active run survives eviction", "run-c" in ids, str(ids))
    finally:
        flowruns_module.RETENTION_RUNS = original_retention


# ------------------------------------------------------------------ live app

import ia_agent.app as app_module  # noqa: E402

app_module.build_specs = lambda: []
PORT = 8792
app = app_module.create_app()
from ia_agent.vars import TOKEN_PATH  # noqa: E402

token = TOKEN_PATH.read_text().strip()
headers = {"Authorization": f"Bearer {token}"}
server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=PORT, log_level="error"))
threading.Thread(target=server.run, daemon=True).start()


async def live_checks() -> None:
    async with httpx.AsyncClient(base_url=f"http://127.0.0.1:{PORT}", headers=headers) as client:
        for _ in range(50):
            try:
                await client.get("/api/health")
                break
            except httpx.HTTPError:
                await asyncio.sleep(0.2)

        # Let the background tailer's own loop discover + poll at least once.
        await asyncio.sleep(2.5)

        print("\n11. GET /api/flow-runs lists both runs with the active one flagged")
        runs = (await client.get("/api/flow-runs")).json()
        by_id = {r["id"]: r for r in runs}
        check("both canned runs are listed", {ACTIVE_RUN_ID, OLD_RUN_ID} <= set(by_id), str(by_id.keys()))
        check("the active run is flagged active with its flow name",
              by_id[ACTIVE_RUN_ID]["active"] is True and by_id[ACTIVE_RUN_ID]["flow"] == "entity-scrape",
              str(by_id[ACTIVE_RUN_ID]))
        check("the completed run is not flagged active", by_id[OLD_RUN_ID]["active"] is False)

        print("\n12. GET /api/flow-runs/{id} for the active run")
        detail = (await client.get(f"/api/flow-runs/{ACTIVE_RUN_ID}")).json()
        check("detail matches the listing shape", detail["id"] == ACTIVE_RUN_ID and detail["flow"] == "entity-scrape",
              str(detail))

        print("\n13. GET /api/flow-runs/{id} for an unknown id is a 404")
        missing = await client.get("/api/flow-runs/does-not-exist")
        check("unknown run id 404s", missing.status_code == 404, str(missing.status_code))

        print("\n14. GET /api/flow-runs/{id}/logs replays the tailed ring, live: true")
        logs = (await client.get(f"/api/flow-runs/{ACTIVE_RUN_ID}/logs")).json()
        check("live is true for a tailed run", logs["live"] is True)
        check("entries include the canned flow rows", any(e["message"] == "started" for e in logs["entries"]),
              str(logs["entries"])[:300])
        check("entries include a scheduler-sourced line merged in",
              any(e["source"] == "scheduler" for e in logs["entries"]), str(logs["entries"])[:300])

        print("\n15. since= only returns entries newer than the given seq")
        all_entries = logs["entries"]
        cursor = all_entries[0]["seq"]
        replay = (await client.get(f"/api/flow-runs/{ACTIVE_RUN_ID}/logs?since={cursor}")).json()
        check("since= trims the head", len(replay["entries"]) == len(all_entries) - 1, str(len(replay["entries"])))

        print("\n16. a run this agent never tailed gets a one-shot fetch, live: false")
        never_tailed = "run-never-tailed"

        async def one_shot_flow_run(flow_run_id):
            return {"id": never_tailed} if flow_run_id == never_tailed else await fake_flow_run(flow_run_id)

        async def one_shot_run_logs(flow_run_id, after=None, limit=500):
            if flow_run_id == never_tailed:
                return [RUN_LOGS[0]]
            return await fake_run_logs(flow_run_id, after=after, limit=limit)

        prefect.flow_run = one_shot_flow_run
        prefect.run_logs = one_shot_run_logs
        one_shot = (await client.get(f"/api/flow-runs/{never_tailed}/logs")).json()
        check("live is false for an untailed run", one_shot["live"] is False)
        check("the one-shot fetch still returns real log content",
              one_shot["entries"] and one_shot["entries"][0]["message"] == "started", str(one_shot["entries"]))
        prefect.flow_run = fake_flow_run
        prefect.run_logs = fake_run_logs

        print("\n17. flowrun.logs reaches a WS subscriber for a fresh row appended live")
        tailer = app_module  # unused placeholder to keep flake happy about ordering
        async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws?token={token}") as ws:
            # Force one more distinguishable row past what's already been polled.
            extra_row = {
                "id": "log-extra", "timestamp": "2026-08-01T10:00:03.000000Z",
                "message": "extra live row", "level": 20, "task_run_id": None,
            }
            RUN_LOGS.append(extra_row)
            frame = None
            deadline = asyncio.get_running_loop().time() + 6
            while asyncio.get_running_loop().time() < deadline:
                try:
                    frame = json.loads(await asyncio.wait_for(ws.recv(), timeout=2))
                except asyncio.TimeoutError:
                    continue
                if frame.get("channel") == "flowrun.logs" and frame["data"].get("message") == "extra live row":
                    break
                frame = None
            check("the new row arrives live over the socket", frame is not None)
            if frame:
                check("tagged with its flow run id", frame["data"]["flow_run_id"] == ACTIVE_RUN_ID, str(frame))


async def main() -> int:
    await ring_checks()
    await discovery_checks()
    await poll_run_checks()
    await scheduler_pod_checks()
    await eviction_checks()
    await live_checks()
    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
