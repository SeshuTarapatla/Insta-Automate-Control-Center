import asyncio
import json
import subprocess
import sys
import time
from pathlib import Path

import psutil

from ia_agent.events.bus import EventBus
from ia_agent.services.spec import (
    HealthProbe,
    ProbeKind,
    RestartPolicy,
    ServiceOrigin,
    ServiceSpec,
    ServiceState,
)
from ia_agent.services.supervisor import Supervisor

HERE = Path(__file__).parent
DUMMY = HERE / "dummy_service.py"
OK = []


def check(label, condition, detail=""):
    mark = "PASS" if condition else "FAIL"
    OK.append(bool(condition))
    print(f"  [{mark}] {label} {detail}")


def spec(name, port, die_after=0, **kwargs):
    cmd = [sys.executable, str(DUMMY), str(port)]
    if die_after:
        cmd.append(str(die_after))
    return ServiceSpec(
        name=name,
        label=name,
        cmd=cmd,
        probe=HealthProbe(kind=ProbeKind.TCP, port=port, timeout=1.0),
        probe_interval=kwargs.pop("probe_interval", 0.5),
        start_grace=kwargs.pop("start_grace", 3.0),
        **kwargs,
    )


async def pump(sup, seconds):
    """Drive the supervisor's tick loop by hand instead of starting its task, so the
    test controls time rather than racing it."""
    deadline = time.time() + seconds
    while time.time() < deadline:
        for service in sup.services.values():
            await service.tick()
        await asyncio.sleep(0.1)


async def until(sup, predicate, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        for service in sup.services.values():
            await service.tick()
        if predicate():
            return True
        await asyncio.sleep(0.1)
    return False


async def main():
    bus = EventBus()
    events = bus.subscribe()

    print("\n1. spawn, probe, capture stdout+stderr")
    sup = Supervisor([spec("t-basic", 19801)], bus)
    svc = sup.get("t-basic")
    svc.start()
    ok = await until(sup, lambda: svc.state == ServiceState.RUNNING)
    check("reaches RUNNING", ok, f"state={svc.state}")
    check("origin is supervised", svc.origin == ServiceOrigin.SUPERVISED)
    check("probe latency recorded", svc.probe and svc.probe.ok, svc.probe.detail if svc.probe else "")
    lines = [entry["line"] for entry in svc.ring.tail()]
    check("stdout captured", any("dummy listening" in line for line in lines))
    check("stderr captured", any(entry["stream"] == "stderr" for entry in svc.ring.tail()))
    check("pid file written", (svc._pid_file()).exists())
    check("status has uptime", svc.status()["uptime_s"] is not None)

    print("\n2. log broadcast on services.logs.<name>")
    await pump(sup, 1.5)
    channels = set()
    while not events.empty():
        channels.add(events.get_nowait()["channel"])
    check("log channel broadcast", "services.logs.t-basic" in channels, str(sorted(channels)))
    check("status channel broadcast", "services.status" in channels)

    print("\n3. stop kills the tree and clears the pid file")
    pid = svc.pid
    svc.stop()
    check("state STOPPED", svc.state == ServiceState.STOPPED)
    check("process gone", not psutil.pid_exists(pid) or not psutil.Process(pid).is_running())
    check("pid file cleared", not svc._pid_file().exists())
    await pump(sup, 1)
    check("stays stopped (no auto-respawn after manual stop)", svc.state == ServiceState.STOPPED)

    print("\n4. crash -> backoff -> automatic restart")
    sup2 = Supervisor([spec("t-crash", 19802, die_after=2, backoff_initial=1.0)], bus)
    crash = sup2.get("t-crash")
    crash.start()
    saw_backoff = await until(sup2, lambda: crash.state == ServiceState.BACKOFF, timeout=15)
    check("enters BACKOFF after exit", saw_backoff, f"exit_code={crash.exit_code}")
    check("exit code recorded", crash.exit_code == 3, f"got {crash.exit_code}")
    back = await until(sup2, lambda: crash.state == ServiceState.RUNNING, timeout=15)
    check("restarts automatically", back, f"restart_count={crash.restart_count}")
    check("restart_count incremented", crash.restart_count >= 1)
    crash.stop()

    print("\n5. restart policy NEVER leaves it FAILED")
    sup3 = Supervisor([spec("t-never", 19803, die_after=1, restart=RestartPolicy.NEVER)], bus)
    never = sup3.get("t-never")
    never.start()
    failed = await until(sup3, lambda: never.state == ServiceState.FAILED, timeout=15)
    check("state FAILED", failed, f"state={never.state}")

    print("\n6. unhealthy: alive but the probe fails")
    sup4 = Supervisor([spec("t-unhealthy", 19804, start_grace=1.0)], bus)
    unhealthy = sup4.get("t-unhealthy")
    # point the probe at a port nothing listens on while the process stays alive
    object.__setattr__(unhealthy.spec.probe, "port", 19899)
    unhealthy.start()
    got = await until(sup4, lambda: unhealthy.state == ServiceState.UNHEALTHY, timeout=15)
    check("state UNHEALTHY while alive", got, f"state={unhealthy.state}")
    check("process still alive", unhealthy.pid and psutil.pid_exists(unhealthy.pid))
    check("no restart on unhealthy (grace 0)", unhealthy.restart_count == 0)
    unhealthy.stop()

    print("\n7. adoption across an agent restart")
    sup5 = Supervisor([spec("t-adopt", 19805)], bus)
    adopt_svc = sup5.get("t-adopt")
    adopt_svc.start()
    await until(sup5, lambda: adopt_svc.state == ServiceState.RUNNING)
    original_pid = adopt_svc.pid
    del sup5  # simulate the agent process going away without stopping the service

    sup6 = Supervisor([spec("t-adopt", 19805)], bus)
    await sup6.start()
    adopted = sup6.get("t-adopt")
    check("adopted, not respawned", adopted.pid == original_pid, f"{adopted.pid} vs {original_pid}")
    check("origin is adopted", adopted.origin == ServiceOrigin.ADOPTED)
    check("stdout flagged unavailable", adopted.status()["stdout_available"] is False)
    await until(sup6, lambda: adopted.state == ServiceState.RUNNING)
    check("adopted service probes RUNNING", adopted.state == ServiceState.RUNNING)
    await sup6.shutdown()
    check("shutdown leaves it running", psutil.pid_exists(original_pid))
    adopted.stop()

    print("\n8. stale pid file (dead pid) is discarded, not adopted")
    sup7 = Supervisor([spec("t-stale", 19806)], bus)
    stale = sup7.get("t-stale")
    stale._pid_file().parent.mkdir(parents=True, exist_ok=True)
    stale._pid_file().write_text(
        json.dumps({"pid": 999999, "create_time": 0, "started_at": 0, "cmd": []})
    )
    stale.adopt()
    check("stale pid file ignored", stale.origin == ServiceOrigin.NONE, f"origin={stale.origin}")
    check("stale pid file removed", not stale._pid_file().exists())

    print("\n9. external ownership + takeover")
    foreign = subprocess.Popen([sys.executable, str(DUMMY), "19807"])
    time.sleep(1.5)
    sup8 = Supervisor([spec("t-external", 19807)], bus)
    await sup8.start()
    ext = sup8.get("t-external")
    check("detected as external", ext.origin == ServiceOrigin.EXTERNAL, f"origin={ext.origin}")
    # uv venv pythons are trampolines: the pid that binds the port is a descendant
    # of the one we spawned, so the owner is either foreign.pid or below it.
    lineage = {foreign.pid, *(child.pid for child in psutil.Process(foreign.pid).children(True))}
    check("reports the port-owning pid", ext.pid in lineage, f"{ext.pid} in {sorted(lineage)}")
    check("external carries a cmdline", "dummy_service" in (ext.status()["external"]["cmdline"] or ""))
    check("offers takeover", ext.status()["can_takeover"] is True)
    try:
        ext.start()
        check("start refused while external", False)
    except Exception as error:
        check("start refused while external", "takeover" in str(error), str(error))
    ext.takeover()
    await until(sup8, lambda: ext.state == ServiceState.RUNNING)
    check("takeover killed the foreign process", foreign.poll() is not None)
    check("takeover now supervised", ext.origin == ServiceOrigin.SUPERVISED)
    check("takeover pid differs", ext.pid != foreign.pid)
    ext.stop()
    await sup8.shutdown()

    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
