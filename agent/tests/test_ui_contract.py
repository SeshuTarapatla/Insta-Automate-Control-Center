"""The contract the Services UI parses (CP 2.4).

test_e2e.py already proves the endpoints *behave*; this proves their payloads
still have the shape `app/lib/core/service_models.dart` and
`dependency_models.dart` decode. That distinction matters because Dart's casts
are unforgiving in a way Python's are not: `json['pid'] as int?` throws on a
float, `as bool?` throws on 0/1, and a renamed key is a crash in the pane rather
than a missing value. None of that shows up in a Python-side test that reads the
same dict by name.

The rules below are transcribed from the Dart models. Keep them in step: if a
field is added there, add it here, and if the agent renames one, this fails
before the app does.

Real services are never touched — a dummy registry plus one deliberately foreign
process on a spare port, which is the only way to exercise the external/takeover
shape the panes actually show today.
"""
import asyncio
import json
import subprocess
import sys
import threading
import time
from pathlib import Path

import httpx
import uvicorn
import websockets

import ia_agent.app as app_module
from ia_agent.dependencies import Group, Level
from ia_agent.services import settings
from ia_agent.services.spec import (
    HealthProbe,
    ProbeKind,
    ServiceOrigin,
    ServiceSpec,
    ServiceState,
    TestOutcome,
)
from ia_agent.vars import TOKEN_PATH

HERE = Path(__file__).parent
PORT = 8790
DUMMY_PORT = 19820
FOREIGN_PORT = 19821
OK = []

settings.SERVICE_SETTINGS_PATH = HERE / ".test-services-ui.json"
settings.SERVICE_SETTINGS_PATH.unlink(missing_ok=True)


# Terminal chunks are quoted in failure details, and they carry box-drawing and
# ANSI bytes that a cp1252 console cannot encode — without this a *failing*
# check dies with a UnicodeEncodeError instead of reporting the failure.
sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


# ------------------------------------------------------------------ contract

# (key, accepted python types, may be null). `int` excludes bool explicitly —
# Dart will not accept `true` where it casts an int, and Python would.
STATUS_FIELDS = [
    ("name", str, False),
    ("label", str, False),
    ("description", str, True),
    ("state", str, False),
    ("origin", str, False),
    ("pid", int, True),
    ("uptime_s", (int, float), True),
    ("restart_count", int, True),
    ("exit_code", int, True),
    ("error", str, True),
    ("has_test", bool, True),
    ("self_heal", bool, True),
    ("autostart", bool, True),
    ("terminal_available", bool, True),
    ("can_takeover", bool, True),
    ("port", int, True),
    ("log_seq", int, True),
]
PROBE_FIELDS = [("ok", bool, False), ("latency_ms", (int, float), False),
                ("detail", str, False), ("at", (int, float), False)]
TEST_FIELDS = [("ok", bool, False), ("summary", str, False), ("metrics", dict, True),
               ("duration_ms", (int, float), False), ("at", (int, float), False)]
PROCESS_FIELDS = [("pid", int, False), ("name", str, True), ("cmdline", str, True)]
CHUNK_FIELDS = [("seq", int, False), ("data", str, False)]
DEPENDENCY_FIELDS = [("key", str, False), ("label", str, False), ("group", str, False),
                     ("level", str, False), ("detail", str, False), ("metrics", dict, True),
                     ("latency_ms", (int, float), True)]

# The enum names the Dart side matches on. A value outside these falls back to a
# default there rather than throwing, so a silent mismatch would go unnoticed in
# the UI — hence checking the sets directly.
DART_STATES = {"stopped", "starting", "running", "unhealthy", "backoff", "failed"}
DART_ORIGINS = {"none", "supervised", "adopted", "external"}
DART_LEVELS = {"ok", "warn", "fail"}
DART_GROUPS = {"cluster", "pipeline", "host"}


def violations(payload: dict, fields, where: str) -> list[str]:
    problems = []
    for key, kinds, nullable in fields:
        if key not in payload:
            problems.append(f"{where}.{key} missing")
            continue
        value = payload[key]
        if value is None:
            if not nullable:
                problems.append(f"{where}.{key} is null")
            continue
        if kinds is int and isinstance(value, bool):
            problems.append(f"{where}.{key} is a bool where Dart casts an int")
            continue
        if not isinstance(value, kinds):
            problems.append(f"{where}.{key} is {type(value).__name__}, expected {kinds}")
    return problems


def status_violations(status: dict, where: str) -> list[str]:
    problems = violations(status, STATUS_FIELDS, where)

    if status.get("state") not in DART_STATES:
        problems.append(f"{where}.state = {status.get('state')!r} is unknown to the UI")
    if status.get("origin") not in DART_ORIGINS:
        problems.append(f"{where}.origin = {status.get('origin')!r} is unknown to the UI")

    cmd = status.get("cmd")
    if not isinstance(cmd, list) or not all(isinstance(part, str) for part in cmd):
        problems.append(f"{where}.cmd is not a list of strings")

    for key, fields in (("probe", PROBE_FIELDS), ("last_test", TEST_FIELDS),
                        ("external", PROCESS_FIELDS), ("port_owner", PROCESS_FIELDS)):
        if status.get(key) is not None:
            problems += violations(status[key], fields, f"{where}.{key}")
    return problems


async def dummy_test() -> TestOutcome:
    return TestOutcome(ok=True, summary="dummy test ran", metrics={"widgets": 3}, at=time.time())


app_module.build_specs = lambda: [
    ServiceSpec(
        name="dummy",
        label="Dummy",
        description="Stand-in for a supervised service.",
        cmd=[sys.executable, str(HERE / "dummy_service.py"), str(DUMMY_PORT)],
        probe=HealthProbe(kind=ProbeKind.TCP, port=DUMMY_PORT, timeout=1.0),
        probe_interval=0.5,
        start_grace=3.0,
        self_test=dummy_test,
    ),
    ServiceSpec(
        name="foreign",
        label="Foreign",
        description="Never started here — something else owns its port.",
        cmd=[sys.executable, str(HERE / "dummy_service.py"), str(FOREIGN_PORT)],
        probe=HealthProbe(kind=ProbeKind.TCP, port=FOREIGN_PORT, timeout=1.0),
        probe_interval=0.5,
    ),
]

app = app_module.create_app()
token = TOKEN_PATH.read_text().strip()
headers = {"Authorization": f"Bearer {token}"}
server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=PORT, log_level="error"))
threading.Thread(target=server.run, daemon=True).start()


async def main():
    # Launched outside the supervisor on purpose: "external" is the state every
    # real service is in today, so it is the state the panes must render.
    foreign = subprocess.Popen(
        [sys.executable, str(HERE / "dummy_service.py"), str(FOREIGN_PORT)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        async with httpx.AsyncClient(base_url=f"http://127.0.0.1:{PORT}", headers=headers) as client:
            for _ in range(50):
                try:
                    await client.get("/api/health")
                    break
                except httpx.HTTPError:
                    await asyncio.sleep(0.2)

            print("\n1. the agent's enums are the UI's enums")
            check("ServiceState values match", {s.value for s in ServiceState} == DART_STATES,
                  str(sorted({s.value for s in ServiceState} ^ DART_STATES)))
            check("ServiceOrigin values match", {o.value for o in ServiceOrigin} == DART_ORIGINS,
                  str(sorted({o.value for o in ServiceOrigin} ^ DART_ORIGINS)))
            check("dependency Level values match", {level.value for level in Level} == DART_LEVELS)
            check("dependency Group values match", {group.value for group in Group} == DART_GROUPS)

            print("\n2. GET /api/services — the list the page opens on")
            listed = (await client.get("/api/services")).json()
            check("returns a list", isinstance(listed, list), str(type(listed).__name__))
            problems = [p for status in listed for p in status_violations(status, status["name"])]
            check("every service decodes", not problems, "; ".join(problems[:3]))

            print("\n3. an action's response is a full status, not an acknowledgement")
            started = (await client.post("/api/services/dummy/start")).json()
            check("start returns a decodable status", not status_violations(started, "start"),
                  "; ".join(status_violations(started, "start")[:3]))
            check("supervised means a terminal", started["terminal_available"] is True)

            for _ in range(40):
                running = (await client.get("/api/services/dummy")).json()
                if running["state"] == "running":
                    break
                await asyncio.sleep(0.25)
            check("reaches running", running["state"] == "running", running["state"])
            check("probe rides along", not violations(running["probe"] or {}, PROBE_FIELDS, "probe"))
            check("uptime is a number the UI can grow", isinstance(running["uptime_s"], (int, float)))

            print("\n4. terminal replay is what an emulator can be fed")
            logs = (await client.get("/api/services/dummy/logs")).json()
            check("names itself", logs.get("name") == "dummy")
            check("declares availability", isinstance(logs.get("terminal_available"), bool))
            chunk_problems = [p for chunk in logs["chunks"]
                              for p in violations(chunk, CHUNK_FIELDS, "chunk")]
            check("chunks decode", logs["chunks"] and not chunk_problems, "; ".join(chunk_problems[:3]))
            seqs = [chunk["seq"] for chunk in logs["chunks"]]
            check("seq is strictly increasing", seqs == sorted(set(seqs)))

            print("\n5. WS frames continue the replay with no gap (they may overlap it)")
            # The ring is written by the reader thread the instant the process
            # prints, while the WS batch for those same chunks is published on
            # the next supervisor tick — up to 250 ms later. So a client that
            # replays and *then* subscribes legitimately receives chunks it
            # already has, and the overlap is not a bug to fix at the agent: it
            # is why the pane keys on `seq` and drops anything already rendered.
            # What must never happen is a gap.
            async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws?token={token}") as ws:
                replay = (await client.get("/api/services/dummy/logs")).json()["chunks"]
                before = replay[-1]["seq"]
                live, deadline = [], asyncio.get_running_loop().time() + 12
                while asyncio.get_running_loop().time() < deadline and len(live) < 3:
                    try:
                        frame = json.loads(await asyncio.wait_for(ws.recv(), timeout=6))
                    except asyncio.TimeoutError:
                        break
                    if frame["channel"] == "services.logs.dummy":
                        live.extend(frame["data"])

            check("live chunks arrived", bool(live), f"{len(live)} chunks")
            check("live chunks decode",
                  not [p for chunk in live for p in violations(chunk, CHUNK_FIELDS, "live")])
            live_seqs = [chunk["seq"] for chunk in live]
            check("live seq is strictly increasing", live_seqs == sorted(set(live_seqs)),
                  str(live_seqs))
            check("no gap between the replay and the live stream", live_seqs[0] <= before + 1,
                  f"live starts at {live_seqs[0]}, replay ended at {before}")
            covered = {chunk["seq"] for chunk in replay} | set(live_seqs)
            check("together they cover every sequence number",
                  covered == set(range(min(covered), max(covered) + 1)),
                  f"{len(covered)} of {max(covered) - min(covered) + 1}")

            print("\n6. a reconnect recovers exactly what it missed")
            recovered = (await client.get(f"/api/services/dummy/logs?since={before}")).json()
            recovered_seqs = {chunk["seq"] for chunk in recovered["chunks"]}
            check("since= excludes what the client already had",
                  all(seq > before for seq in recovered_seqs))
            check("since= includes everything seen live after the cursor",
                  {seq for seq in live_seqs if seq > before} <= recovered_seqs,
                  f"missing {sorted({s for s in live_seqs if s > before} - recovered_seqs)}")

            print("\n7. resize reaches the child, not just the endpoint")
            # The pane measures its own grid and pushes it here. If this stops
            # working the symptom is subtle — full-width output wraps at the
            # spawn width and the terminal fills with broken lines.
            sized = await client.post("/api/services/dummy/resize", json={"rows": 24, "cols": 173})
            check("resize accepted", sized.status_code == 200, str(sized.status_code))
            cursor = (await client.get("/api/services/dummy/logs")).json()["chunks"][-1]["seq"]
            text = ""
            for _ in range(16):
                await asyncio.sleep(0.5)
                text = "".join(
                    chunk["data"]
                    for chunk in (await client.get(f"/api/services/dummy/logs?since={cursor}")).json()["chunks"]
                )
                if "size=173x24" in text:
                    break
            check("the child's console is now 173x24", "size=173x24" in text, repr(text[-60:]))

            print("\n8. the Test button's payload")
            outcome = (await client.post("/api/services/dummy/test")).json()
            check("outcome decodes", not violations(outcome, TEST_FIELDS, "test"),
                  "; ".join(violations(outcome, TEST_FIELDS, "test")))
            check("metrics are renderable as chips", outcome["metrics"] == {"widgets": 3})
            after = (await client.get("/api/services/dummy")).json()
            check("last_test lands in the status", not status_violations(after, "after-test"))

            print("\n9. external — what every real service looks like today")
            for _ in range(40):
                stranger = (await client.get("/api/services/foreign")).json()
                if stranger["origin"] == "external":
                    break
                await asyncio.sleep(0.25)
            check("detected as external", stranger["origin"] == "external", stranger["origin"])
            check("external status decodes", not status_violations(stranger, "foreign"),
                  "; ".join(status_violations(stranger, "foreign")[:3]))
            check("offers takeover", stranger["can_takeover"] is True)
            check("declares no terminal", stranger["terminal_available"] is False)
            check("names what takeover would kill", stranger["external"] is not None)
            check("names the port owner separately", stranger["port_owner"] is not None)
            # Its ring holds the agent's own note about finding the port taken,
            # and nothing the process printed — which is why the pane explains
            # the situation instead of rendering one dim line as a "terminal".
            ring = (await client.get("/api/services/foreign/logs")).json()
            check("no captured output", ring["terminal_available"] is False)
            check("ring holds agent notes only",
                  all(chunk["data"].startswith("\x1b[2m── ") for chunk in ring["chunks"]),
                  repr("".join(c["data"] for c in ring["chunks"])[:70]))

            print("\n10. errors carry a sentence the UI can show")
            refused = await client.post("/api/services/foreign/start")
            check("409 on starting over an external process", refused.status_code == 409,
                  str(refused.status_code))
            detail = refused.json().get("detail")
            check("detail is a string", isinstance(detail, str), repr(detail))
            check("detail explains the fix", detail and "takeover" in detail, repr(detail))
            unknown = await client.get("/api/services/nope")
            check("404 for an unknown service", unknown.status_code == 404)

            print("\n11. stop leaves a status the pane can still explain")
            stopped = (await client.post("/api/services/dummy/stop")).json()
            check("stop decodes", not status_violations(stopped, "stop"),
                  "; ".join(status_violations(stopped, "stop")[:3]))
            check("pid cleared", stopped["pid"] is None)
            check("no live terminal once stopped", stopped["terminal_available"] is False)
            kept = (await client.get("/api/services/dummy/logs")).json()["chunks"]
            check("but the output is kept to read", bool(kept), f"{len(kept)} chunks")

            print("\n12. GET /api/dependencies (live, read-only)")
            snapshot = (await client.get("/api/dependencies", timeout=40)).json()
            items = snapshot["dependencies"]
            check("returns the ten checks", len(items) == 10, str(len(items)))
            dep_problems = [p for item in items for p in violations(item, DEPENDENCY_FIELDS, item["key"])]
            check("every dependency decodes", not dep_problems, "; ".join(dep_problems[:3]))
            check("levels are known to the UI", {item["level"] for item in items} <= DART_LEVELS,
                  str(sorted({item["level"] for item in items})))
            check("groups are known to the UI", {item["group"] for item in items} <= DART_GROUPS,
                  str(sorted({item["group"] for item in items})))
            summary = snapshot["summary"]
            check("summary counts are ints",
                  all(isinstance(summary[key], int) for key in ("ok", "warn", "fail")))
            check("summary adds up", sum(summary.values()) == len(items), str(summary))
    finally:
        foreign.terminate()
        settings.SERVICE_SETTINGS_PATH.unlink(missing_ok=True)

    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
