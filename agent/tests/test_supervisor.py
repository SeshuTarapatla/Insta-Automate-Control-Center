import asyncio
import json
import subprocess
import sys
import time
from pathlib import Path

import psutil

from ia_agent.events.bus import EventBus
from ia_agent.services import settings
from ia_agent.services.logs import render_plain
from ia_agent.services.spec import (
    HealthProbe,
    ProbeKind,
    ServiceOrigin,
    ServiceSpec,
    ServiceState,
)
from ia_agent.services.supervisor import Supervisor

HERE = Path(__file__).parent
DUMMY = HERE / "dummy_service.py"
OK = []

# Keep the switches these tests flip out of the real services.json.
settings.SERVICE_SETTINGS_PATH = HERE / ".test-services.json"
settings.SERVICE_SETTINGS_PATH.unlink(missing_ok=True)


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


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
        unhealthy_grace=kwargs.pop("unhealthy_grace", 0.0),
        **kwargs,
    )


def text_of(service):
    return "".join(chunk["data"] for chunk in service.ring.tail())


async def pump(sup, seconds):
    """Drive the tick loop by hand instead of starting its task, so the test
    controls time rather than racing it."""
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

    print("\n1. spawn into a ConPTY, probe, capture the terminal verbatim")
    sup = Supervisor([spec("t-basic", 19801)], bus)
    svc = sup.get("t-basic")
    svc.start()
    ok = await until(sup, lambda: svc.state == ServiceState.RUNNING)
    check("reaches RUNNING", ok, f"state={svc.state}")
    check("origin is supervised", svc.origin == ServiceOrigin.SUPERVISED)
    check("probe latency recorded", svc.probe and svc.probe.ok, svc.probe.detail if svc.probe else "")
    await pump(sup, 1.0)
    output = text_of(svc)
    check("child sees a real tty", "isatty=True" in output)
    check("stdout captured", "dummy listening" in output)
    check("stderr captured (pty merges both)", "a line on stderr" in output)
    check("ANSI colour preserved", "\x1b[32m" in output)
    check("carriage returns preserved", "\rloading 3/3" in output)
    check("terminal flagged available", svc.status()["terminal_available"] is True)
    check("pid file written", svc._pid_file().exists())
    check("status has uptime", svc.status()["uptime_s"] is not None)

    print("\n2. broadcast on services.status and services.logs.<name>")
    channels = set()
    while not events.empty():
        channels.add(events.get_nowait()["channel"])
    check("terminal channel broadcast", "services.logs.t-basic" in channels, str(sorted(channels)))
    check("status channel broadcast", "services.status" in channels)

    print("\n3. the on-disk copy is flattened for reading")
    check("render_plain strips ANSI", render_plain("\x1b[32mgreen\x1b[0m") == "green")
    check("render_plain keeps last CR frame", render_plain("loading 1/3\rloading 3/3") == "loading 3/3")

    print("\n4. stop kills the tree and clears the pid file")
    pid = svc.pid
    svc.stop()
    check("state STOPPED", svc.state == ServiceState.STOPPED)
    check("process gone", not psutil.pid_exists(pid) or not psutil.Process(pid).is_running())
    check("pid file cleared", not svc._pid_file().exists())
    await pump(sup, 1)
    check("stays stopped after a manual stop", svc.state == ServiceState.STOPPED)

    print("\n5. crash -> backoff -> self-heal restart")
    sup2 = Supervisor([spec("t-crash", 19802, die_after=2, backoff_initial=1.0)], bus)
    crash = sup2.get("t-crash")
    check("self_heal defaults on", crash.self_heal is True)
    crash.start()
    saw_backoff = await until(sup2, lambda: crash.state == ServiceState.BACKOFF, timeout=15)
    check("enters BACKOFF after exit", saw_backoff, f"exit_code={crash.exit_code}")
    check("exit code recorded", crash.exit_code == 3, f"got {crash.exit_code}")
    back = await until(sup2, lambda: crash.state == ServiceState.RUNNING, timeout=15)
    check("self-heals automatically", back, f"restart_count={crash.restart_count}")
    check("restart_count incremented", crash.restart_count >= 1)
    check("self-heal narrated in the terminal", "self-heal: restarting" in text_of(crash))
    crash.stop()

    print("\n6. self-heal off leaves it FAILED")
    sup3 = Supervisor([spec("t-noheal", 19803, die_after=1, self_heal=False)], bus)
    noheal = sup3.get("t-noheal")
    check("self_heal off from spec", noheal.self_heal is False)
    noheal.start()
    failed = await until(sup3, lambda: noheal.state == ServiceState.FAILED, timeout=15)
    check("state FAILED", failed, f"state={noheal.state}")
    check("no restart attempted", noheal.restart_count == 0)
    check("reason narrated", "self-heal is off" in text_of(noheal))
    await pump(sup3, 2)
    check("stays FAILED", noheal.state == ServiceState.FAILED)

    print("\n7. flipping self-heal on rescues a FAILED service")
    noheal.configure(self_heal=True)
    check("switch applied", noheal.self_heal is True)
    check("switch persisted", settings.get("t-noheal").get("self_heal") is True)
    revived = await until(sup3, lambda: noheal.state == ServiceState.RUNNING, timeout=20)
    check("came back without an explicit start", revived, f"state={noheal.state}")
    noheal.stop()

    print("\n8. unhealthy: alive but the probe fails")
    sup4 = Supervisor([spec("t-unhealthy", 19804, start_grace=1.0)], bus)
    unhealthy = sup4.get("t-unhealthy")
    # keep the process alive but point the probe where nothing listens
    object.__setattr__(unhealthy.spec.probe, "port", 19899)
    unhealthy.start()
    got = await until(sup4, lambda: unhealthy.state == ServiceState.UNHEALTHY, timeout=15)
    check("state UNHEALTHY while alive", got, f"state={unhealthy.state}")
    check("process still alive", unhealthy.pid and psutil.pid_exists(unhealthy.pid))
    check("unhealthy_grace 0 means no restart", unhealthy.restart_count == 0)
    unhealthy.stop()

    print("\n9. self-heal restarts a wedged (alive but unhealthy) process")
    sup5 = Supervisor(
        [spec("t-wedged", 19808, start_grace=1.0, unhealthy_grace=1.0, probe_interval=0.4)], bus
    )
    wedged = sup5.get("t-wedged")
    object.__setattr__(wedged.spec.probe, "port", 19898)
    wedged.start()
    healed = await until(sup5, lambda: wedged.restart_count >= 1, timeout=20)
    check("wedged process restarted", healed, f"restarts={wedged.restart_count}")
    check("wedge narrated", "while the process is still alive" in text_of(wedged))
    wedged.stop()

    print("\n10. adoption across an agent restart")
    sup6 = Supervisor([spec("t-adopt", 19805)], bus)
    adopt_svc = sup6.get("t-adopt")
    adopt_svc.start()
    await until(sup6, lambda: adopt_svc.state == ServiceState.RUNNING)
    original_pid = adopt_svc.pid
    del sup6  # the agent process goes away without stopping the service

    sup7 = Supervisor([spec("t-adopt", 19805)], bus)
    await sup7.start()
    adopted = sup7.get("t-adopt")
    check("adopted, not respawned", adopted.pid == original_pid, f"{adopted.pid} vs {original_pid}")
    check("origin is adopted", adopted.origin == ServiceOrigin.ADOPTED)
    check("terminal flagged unavailable", adopted.status()["terminal_available"] is False)
    await until(sup7, lambda: adopted.state == ServiceState.RUNNING)
    check("adopted service probes RUNNING", adopted.state == ServiceState.RUNNING)
    await sup7.shutdown()
    check("shutdown leaves it running", psutil.pid_exists(original_pid))
    adopted.stop()

    print("\n11. stale pid file (dead pid) is discarded, not adopted")
    sup8 = Supervisor([spec("t-stale", 19806)], bus)
    stale = sup8.get("t-stale")
    stale._pid_file().parent.mkdir(parents=True, exist_ok=True)
    stale._pid_file().write_text(
        json.dumps({"pid": 999999, "create_time": 0, "started_at": 0, "cmd": []})
    )
    stale.adopt()
    check("stale pid file ignored", stale.origin == ServiceOrigin.NONE, f"origin={stale.origin}")
    check("stale pid file removed", not stale._pid_file().exists())

    print("\n12. external ownership + takeover")
    foreign = subprocess.Popen(
        [sys.executable, str(DUMMY), "19807"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(1.5)
    sup9 = Supervisor([spec("t-external", 19807)], bus)
    await sup9.start()
    ext = sup9.get("t-external")
    check("detected as external", ext.origin == ServiceOrigin.EXTERNAL, f"origin={ext.origin}")
    # uv venv pythons are trampolines: the pid that binds the port is a descendant
    # of the one we spawned, so the owner is either foreign.pid or below it.
    lineage = {foreign.pid, *(child.pid for child in psutil.Process(foreign.pid).children(True))}
    check("reports the port-owning pid", ext.status()["port_owner"]["pid"] in lineage)
    check("kill target carries a cmdline",
          "dummy_service" in (ext.status()["external"]["cmdline"] or ""))
    check("offers takeover", ext.status()["can_takeover"] is True)
    try:
        ext.start()
        check("start refused while external", False)
    except Exception as error:
        check("start refused while external", "takeover" in str(error), str(error))
    ext.takeover()
    await until(sup9, lambda: ext.state == ServiceState.RUNNING)
    check("takeover killed the foreign process", foreign.poll() is not None)
    check("takeover now supervised", ext.origin == ServiceOrigin.SUPERVISED)
    check("takeover pid differs", ext.pid != foreign.pid)
    ext.stop()
    await sup9.shutdown()

    settings.SERVICE_SETTINGS_PATH.unlink(missing_ok=True)
    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
