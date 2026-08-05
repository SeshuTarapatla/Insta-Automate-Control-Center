"""Scheduler mirror (CP 3.4) — the agent-side receiving half of the pipeline
pod's heartbeat.

Nothing on the pipeline side sends real heartbeats yet (see CLAUDE.md) - this
proves the store, the per-flow command queue, staleness detection, and the
`flows.state` broadcast all behave against synthetic heartbeats shaped like
ARCHITECTURE §4.3.

Real services are never touched: `build_specs` is monkeypatched to an empty
list before `create_app()` runs, exactly like test_ui_contract.py, so this
test's own throwaway Supervisor never adopts or probes the three real
services a production agent may already be supervising.
"""
import asyncio
import json
import sys
import threading
import time

import httpx
import uvicorn
import websockets

import ia_agent.app as app_module
from ia_agent.events.bus import EventBus
from ia_agent.scheduler import STALE_AFTER, SchedulerMirror
from ia_agent.vars import TOKEN_PATH

PORT = 8791
OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


def sample_state(flow="entity-scrape", phase="waiting"):
    return {
        "flow": flow,
        "switch": True,
        "phase": phase,
        "next_trigger_at": "2026-07-31T22:40:00+05:30",
        "gate": {"ok": True, "reason": None, "detail": None},
        "today": {"scraped": 42, "limit": 300},
        "last_run": {"id": "abc123", "state": "COMPLETED", "duration_s": 214},
    }


async def store_checks() -> None:
    print("\n1. heartbeat records state and returns queued commands")
    bus = EventBus()
    mirror = SchedulerMirror(bus)
    check("no commands before any are queued", mirror.heartbeat(sample_state()) == [])
    mirror.queue_command("entity-scrape", "skip_wait")
    mirror.queue_command("entity-scrape", "run_now")
    drained = [c["command"] for c in mirror.heartbeat(sample_state())]
    check("both queued commands are returned, in order", drained == ["skip_wait", "run_now"], str(drained))
    check("commands are cleared once drained", mirror.heartbeat(sample_state()) == [])

    print("\n2. commands are scoped per flow")
    mirror.queue_command("entity-follow", "pause")
    check("entity-scrape gets nothing meant for entity-follow",
          mirror.heartbeat(sample_state("entity-scrape")) == [])
    follow_commands = [c["command"] for c in mirror.heartbeat(sample_state("entity-follow"))]
    check("entity-follow gets its own command", follow_commands == ["pause"], str(follow_commands))

    print("\n3. online flips to offline after STALE_AFTER with no heartbeat")
    mirror._last_heartbeat_at = time.time() - (STALE_AFTER + 1)
    check("stale heartbeat reads offline", mirror.online() is False)
    mirror.heartbeat(sample_state())
    check("a fresh heartbeat reads online again", mirror.online() is True)
    check("a mirror with no heartbeat ever is offline", SchedulerMirror(bus).online() is False)

    print("\n4. flows.state only broadcasts when the snapshot signature changes")
    published = []

    async def capture(channel, data):
        published.append((channel, data))

    bus.publish = capture
    mirror._signature = None
    await mirror.broadcast_if_changed()
    check("first broadcast always fires", len(published) == 1)
    await mirror.broadcast_if_changed()
    check("an unchanged snapshot does not re-broadcast", len(published) == 1, str(len(published)))
    mirror.heartbeat(sample_state(phase="triggering"))
    await mirror.broadcast_if_changed()
    check("a phase change re-broadcasts", len(published) == 2)
    check("every broadcast is on flows.state", all(c == "flows.state" for c, _ in published))
    check("the payload is the full snapshot shape",
          "online" in published[-1][1] and "flows" in published[-1][1])


# ------------------------------------------------------------------ live app

app_module.build_specs = lambda: []
app = app_module.create_app()
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

        print("\n5. GET /api/scheduler before any heartbeat")
        empty = (await client.get("/api/scheduler")).json()
        check("starts offline", empty["online"] is False)
        check("starts with no flows", empty["flows"] == {})

        print("\n6. POST /api/scheduler/heartbeat")
        posted = (await client.post("/api/scheduler/heartbeat", json=sample_state())).json()
        check("returns an empty command list with nothing queued", posted == {"commands": []})

        snapshot = (await client.get("/api/scheduler")).json()
        check("now online", snapshot["online"] is True)
        check("the flow is stored under its own name", "entity-scrape" in snapshot["flows"])
        check("the stored state round-trips", snapshot["flows"]["entity-scrape"]["phase"] == "waiting")

        print("\n7. POST /api/scheduler/{flow}/command")
        rejected = await client.post("/api/scheduler/entity-scrape/command", json={"command": "nonsense"})
        check("an unknown command is a 400", rejected.status_code == 400, str(rejected.status_code))

        queued = (await client.post(
            "/api/scheduler/entity-scrape/command", json={"command": "skip_wait"}
        )).json()
        check("a known command is accepted", queued == {
            "queued": True, "flow": "entity-scrape", "command": "skip_wait"
        }, str(queued))

        reduce_queued = (await client.post(
            "/api/scheduler/entity-follow/command", json={"command": "reduce_reserve"}
        )).json()
        check("reduce_reserve is a known command too", reduce_queued == {
            "queued": True, "flow": "entity-follow", "command": "reduce_reserve"
        }, str(reduce_queued))

        unblock_queued = (await client.post(
            "/api/scheduler/entity-follow/command", json={"command": "reduce_reserve_unblock_scrape"}
        )).json()
        check("reduce_reserve_unblock_scrape is a known command too", unblock_queued == {
            "queued": True, "flow": "entity-follow", "command": "reduce_reserve_unblock_scrape"
        }, str(unblock_queued))

        drained = (await client.post("/api/scheduler/heartbeat", json=sample_state())).json()
        check("the next heartbeat drains it", drained["commands"] and drained["commands"][0]["command"] == "skip_wait",
              str(drained))

        print("\n8. flows.state reaches a subscriber over /ws")
        async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws?token={token}") as ws:
            await client.post(
                "/api/scheduler/heartbeat", json=sample_state(phase="triggering")
            )
            frame = None
            deadline = asyncio.get_running_loop().time() + 6
            while asyncio.get_running_loop().time() < deadline:
                try:
                    frame = json.loads(await asyncio.wait_for(ws.recv(), timeout=2))
                except asyncio.TimeoutError:
                    continue
                if frame.get("channel") == "flows.state":
                    break
                frame = None
            check("a flows.state frame arrives", frame is not None)
            if frame:
                check("carries the new phase",
                      frame["data"]["flows"]["entity-scrape"]["phase"] == "triggering", str(frame))


async def main() -> int:
    await store_checks()
    await live_checks()
    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
