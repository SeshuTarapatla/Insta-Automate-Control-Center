"""End-to-end: real FastAPI app + real WS, but a dummy registry so the live
pipeline's services are never touched."""
import asyncio
import json
import sys
import threading
import time
from pathlib import Path

import httpx
import uvicorn
import websockets

import ia_agent.app as app_module
from ia_agent.services import settings
from ia_agent.services.spec import HealthProbe, ProbeKind, ServiceSpec, TestOutcome
from ia_agent.vars import TOKEN_PATH

HERE = Path(__file__).parent
PORT = 8789
OK = []

settings.SERVICE_SETTINGS_PATH = HERE / ".test-services-e2e.json"
settings.SERVICE_SETTINGS_PATH.unlink(missing_ok=True)


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


async def dummy_test() -> TestOutcome:
    return TestOutcome(ok=True, summary="dummy test ran", metrics={"widgets": 3}, at=time.time())


app_module.build_specs = lambda: [
    ServiceSpec(
        name="dummy",
        label="Dummy",
        cmd=[sys.executable, str(HERE / "dummy_service.py"), "19810"],
        probe=HealthProbe(kind=ProbeKind.TCP, port=19810, timeout=1.0),
        probe_interval=0.5,
        start_grace=3.0,
        self_test=dummy_test,
    ),
    ServiceSpec(
        name="untestable",
        label="Untestable",
        cmd=[sys.executable, "-c", "import time; time.sleep(60)"],
        probe=HealthProbe(kind=ProbeKind.TCP, port=19811, timeout=1.0),
        probe_interval=0.5,
    ),
]

app = app_module.create_app()
token = TOKEN_PATH.read_text().strip()
headers = {"Authorization": f"Bearer {token}"}
server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=PORT, log_level="error"))
threading.Thread(target=server.run, daemon=True).start()


async def main():
    async with httpx.AsyncClient(base_url=f"http://127.0.0.1:{PORT}", headers=headers) as client:
        for _ in range(50):
            try:
                await client.get("/api/health")
                break
            except httpx.HTTPError:
                await asyncio.sleep(0.2)

        print("\n1. initial state")
        status = (await client.get("/api/services")).json()[0]
        check("service listed", status["name"] == "dummy")
        check("has_test advertised", status["has_test"] is True)
        check("no test result yet", status["last_test"] is None)
        check("starts stopped", status["state"] == "stopped", status["state"])
        check("self_heal on by default", status["self_heal"] is True)
        check("autostart off by default", status["autostart"] is False)

        print("\n2. WS receives status + terminal frames driven by REST actions")
        async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws?token={token}") as ws:
            response = await client.post("/api/services/dummy/start")
            check("start returns 200", response.status_code == 200, str(response.status_code))

            # Collect until both channels have shown up or the overall deadline
            # passes. The per-recv timeout is generous on purpose: a short one turns
            # a loaded machine into a spurious failure rather than a real one.
            # Wait for the *content*, not merely for a frame on the channel: the
            # first terminal frame is usually ConPTY's handshake preamble
            # (\x1b[1t\x1b[c...) with none of the service's own output in it yet.
            def streamed_text():
                return "".join(
                    chunk["data"]
                    for f in frames
                    if f["channel"] == "services.logs.dummy"
                    for chunk in f["data"]
                )

            frames, deadline = [], asyncio.get_running_loop().time() + 20
            while asyncio.get_running_loop().time() < deadline:
                try:
                    frames.append(json.loads(await asyncio.wait_for(ws.recv(), timeout=6)))
                except asyncio.TimeoutError:
                    break
                running = any(f["channel"] == "services.status" and f["data"]["state"] == "running"
                              for f in frames)
                if running and "dummy listening" in streamed_text():
                    break

            channels = {f["channel"] for f in frames}
            check("services.status frame", "services.status" in channels, str(sorted(channels)))
            check("services.logs.dummy frame", "services.logs.dummy" in channels)
            check("status frame reports running",
                  any(f["channel"] == "services.status" and f["data"]["state"] == "running"
                      for f in frames))
            terminal = [f for f in frames if f["channel"] == "services.logs.dummy"]
            check("terminal frames are batched lists", isinstance(terminal[0]["data"], list))
            streamed = streamed_text()
            check("terminal content streamed", "dummy listening" in streamed)
            check("ANSI survives the websocket", "\x1b[32m" in streamed)
            check("child had a real tty", "isatty=True" in streamed)

        print("\n3. terminal replay with a cursor")
        logs = (await client.get("/api/services/dummy/logs")).json()
        check("terminal_available when supervised", logs["terminal_available"] is True)
        check("chunks returned", len(logs["chunks"]) > 0, str(len(logs["chunks"])))
        last = logs["chunks"][-1]["seq"]
        await asyncio.sleep(2)
        newer = (await client.get(f"/api/services/dummy/logs?since={last}")).json()
        check("since returns only newer chunks",
              bool(newer["chunks"]) and all(c["seq"] > last for c in newer["chunks"]),
              f"{len(newer['chunks'])} new")

        print("\n4. terminal resize is accepted")
        resized = await client.post("/api/services/dummy/resize", json={"rows": 50, "cols": 200})
        check("resize 200", resized.status_code == 200, resized.text[:80])
        bad = await client.post("/api/services/dummy/resize", json={"rows": 0, "cols": 200})
        check("rejects a nonsense size", bad.status_code == 422, str(bad.status_code))

        print("\n5. self-heal switch over REST")
        off = (await client.patch("/api/services/dummy", json={"self_heal": False})).json()
        check("switch reported off", off["self_heal"] is False)
        check("switch persisted to disk", settings.get("dummy").get("self_heal") is False)
        back_on = (await client.patch("/api/services/dummy", json={"self_heal": True})).json()
        check("switch reported on", back_on["self_heal"] is True)

        print("\n6. functional test over REST")
        result = (await client.post("/api/services/dummy/test")).json()
        check("test ran", result["ok"] is True, str(result)[:70])
        check("metrics returned", result["metrics"] == {"widgets": 3})
        after_test = (await client.get("/api/services/dummy")).json()
        check("last_test lands in status", after_test["last_test"]["ok"] is True)
        replay = (await client.get("/api/services/dummy/logs")).json()["chunks"]
        check("test narrated into the terminal",
              "test passed" in "".join(chunk["data"] for chunk in replay))
        no_test = await client.post("/api/services/untestable/test")
        check("409 when a service has no test", no_test.status_code == 409, no_test.text[:70])

        print("\n7. start twice is a 409, not a second process")
        conflict = await client.post("/api/services/dummy/start")
        check("409 on double start", conflict.status_code == 409, conflict.text[:80])

        print("\n8. restart bumps the count and changes the pid")
        before = (await client.get("/api/services/dummy")).json()
        after = (await client.post("/api/services/dummy/restart")).json()
        check("pid changed", before["pid"] != after["pid"], f"{before['pid']} -> {after['pid']}")
        check("restart_count bumped", after["restart_count"] == before["restart_count"] + 1)

        print("\n9. stop")
        stopped = (await client.post("/api/services/dummy/stop")).json()
        check("state stopped", stopped["state"] == "stopped", stopped["state"])
        check("pid cleared", stopped["pid"] is None)

    settings.SERVICE_SETTINGS_PATH.unlink(missing_ok=True)
    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
