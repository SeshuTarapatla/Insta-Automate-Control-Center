"""End-to-end: real FastAPI app + real WS, but a dummy registry so the live
pipeline's services are never touched."""
import asyncio
import json
import sys
import threading
from pathlib import Path

import httpx
import uvicorn
import websockets

import ia_agent.app as app_module
from ia_agent.services.spec import HealthProbe, ProbeKind, ServiceSpec
from ia_agent.vars import TOKEN_PATH

HERE = Path(__file__).parent
PORT = 8789
OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


app_module.build_specs = lambda: [
    ServiceSpec(
        name="dummy",
        label="Dummy",
        cmd=[sys.executable, str(HERE / "dummy_service.py"), "19810"],
        probe=HealthProbe(kind=ProbeKind.TCP, port=19810, timeout=1.0),
        probe_interval=0.5,
        start_grace=3.0,
    )
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
        check("starts stopped", status["state"] == "stopped", status["state"])

        print("\n2. WS receives status + log frames driven by REST actions")
        async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws?token={token}") as ws:
            response = await client.post("/api/services/dummy/start")
            check("start returns 200", response.status_code == 200, str(response.status_code))

            # Collect until both channels have shown up or the overall deadline
            # passes. The per-recv timeout is generous on purpose: a short one turns
            # a loaded machine into a spurious failure rather than a real one.
            frames, deadline = [], asyncio.get_running_loop().time() + 20
            while asyncio.get_running_loop().time() < deadline:
                try:
                    frames.append(json.loads(await asyncio.wait_for(ws.recv(), timeout=6)))
                except asyncio.TimeoutError:
                    break
                if any(f["channel"] == "services.status" and f["data"]["state"] == "running"
                       for f in frames) and any(f["channel"] == "services.logs.dummy" for f in frames):
                    break

            channels = {f["channel"] for f in frames}
            check("services.status frame", "services.status" in channels, str(sorted(channels)))
            check("services.logs.dummy frame", "services.logs.dummy" in channels)
            running = [f for f in frames if f["channel"] == "services.status"
                       and f["data"]["state"] == "running"]
            check("status frame reports running", bool(running))
            log_frames = [f for f in frames if f["channel"] == "services.logs.dummy"]
            check("log frames are batched lists", isinstance(log_frames[0]["data"], list))
            check("log line content", any("dummy listening" in entry["line"]
                                          for f in log_frames for entry in f["data"]))

        print("\n3. REST log replay with a cursor")
        logs = (await client.get("/api/services/dummy/logs?tail=100")).json()
        check("stdout_available true when supervised", logs["stdout_available"] is True)
        check("lines returned", len(logs["lines"]) > 0, str(len(logs["lines"])))
        last = logs["lines"][-1]["seq"]
        await asyncio.sleep(2)
        newer = (await client.get(f"/api/services/dummy/logs?since={last}")).json()
        check("since returns only newer lines",
              all(entry["seq"] > last for entry in newer["lines"]) and newer["lines"],
              f"{len(newer['lines'])} new")

        print("\n4. start twice is a 409, not a second process")
        conflict = await client.post("/api/services/dummy/start")
        check("409 on double start", conflict.status_code == 409, conflict.text[:80])

        print("\n5. restart bumps the count and changes the pid")
        before = (await client.get("/api/services/dummy")).json()
        after = (await client.post("/api/services/dummy/restart")).json()
        check("pid changed", before["pid"] != after["pid"], f"{before['pid']} -> {after['pid']}")
        check("restart_count bumped", after["restart_count"] == before["restart_count"] + 1)

        print("\n6. stop")
        stopped = (await client.post("/api/services/dummy/stop")).json()
        check("state stopped", stopped["state"] == "stopped", stopped["state"])
        check("pid cleared", stopped["pid"] is None)

    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
