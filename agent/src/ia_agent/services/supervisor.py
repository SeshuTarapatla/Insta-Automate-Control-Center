import asyncio
import json
import os
import threading
import time

import psutil
from winpty import PtyProcess

from ia_agent.events.bus import EventBus
from ia_agent.logging import logger
from ia_agent.services import settings
from ia_agent.services.logs import LogRing
from ia_agent.services.probes import ProbeResult, run_probe
from ia_agent.services import selftest
from ia_agent.services.spec import ServiceOrigin, ServiceSpec, ServiceState, TestOutcome
from ia_agent.vars import SERVICE_RUN_DIR

TICK = 0.25  # terminal-flush granularity; probes run on the spec's own interval
STOP_GRACE = 5.0  # seconds a terminate() gets before the tree is killed
READ_SIZE = 8192


class ServiceError(Exception):
    """Raised for operator errors (start an already-running service, take over
    nothing) — surfaced to the API as a 409 rather than a 500."""


class ManagedService:
    def __init__(self, spec: ServiceSpec, bus: EventBus) -> None:
        self.spec = spec
        self.ring = LogRing(spec.name)
        self._bus = bus

        stored = settings.get(spec.name)
        self.self_heal: bool = stored.get("self_heal", spec.self_heal)
        self.autostart: bool = stored.get("autostart", spec.autostart)

        self.state = ServiceState.STOPPED
        self.origin = ServiceOrigin.NONE
        self.restart_count = 0
        self.exit_code: int | None = None
        self.probe: ProbeResult | None = None
        self.last_test: TestOutcome | None = None
        self.error: str | None = None

        self._proc: PtyProcess | None = None
        self._adopted: psutil.Process | None = None
        self._external: psutil.Process | None = None
        self._external_owner: psutil.Process | None = None
        self._started_at: float | None = None
        self._healthy_since: float | None = None
        self._desired = False
        self._backoff = spec.backoff_initial
        self._retry_at = 0.0
        self._unhealthy_since: float | None = None
        self._last_probe_at = 0.0
        self._reader: threading.Thread | None = None
        self._pending: list[dict] = []
        self._pending_lock = threading.Lock()
        self._signature: tuple | None = None
        self._rows, self._cols = spec.rows, spec.cols
        # Actions arrive on a worker thread (the API offloads them so a slow kill
        # cannot stall the loop) while tick() runs on the event loop. Without this,
        # a tick landing mid-spawn sees origin=NONE with a live port and concludes
        # the process it is itself starting belongs to somebody else (D9).
        # Re-entrant because restart() is stop() + start().
        self._lock = threading.RLock()

    # ------------------------------------------------------------------ state

    @property
    def pid(self) -> int | None:
        if self._proc is not None:
            return self._proc.pid
        for process in (self._adopted, self._external):
            if process is not None:
                return process.pid
        return None

    @property
    def _alive(self) -> bool:
        return self.origin in (ServiceOrigin.SUPERVISED, ServiceOrigin.ADOPTED)

    def status(self) -> dict:
        return {
            "name": self.spec.name,
            "label": self.spec.label,
            "description": self.spec.description,
            "state": self.state,
            "origin": self.origin,
            "pid": self.pid,
            "uptime_s": round(time.time() - self._started_at, 1) if self._started_at else None,
            "restart_count": self.restart_count,
            "exit_code": self.exit_code,
            "error": self.error,
            "probe": self.probe.as_dict() if self.probe else None,
            "has_test": self.spec.self_test is not None,
            "last_test": self.last_test.as_dict() if self.last_test else None,
            "self_heal": self.self_heal,
            "autostart": self.autostart,
            # Adopted and external processes were spawned without our pseudo-console,
            # so the terminal is empty by nature rather than by failure — the UI says
            # so instead of showing a blank pane.
            "terminal_available": self.origin == ServiceOrigin.SUPERVISED,
            "can_takeover": self.origin == ServiceOrigin.EXTERNAL,
            # `external` is what takeover would kill; `port_owner` is what actually
            # holds the socket, which is often a descendant of it (D11).
            "external": _describe(self._external),
            "port_owner": _describe(self._external_owner),
            "cmd": self.spec.cmd,
            "port": self.spec.probe.port,
            "log_seq": self.ring.seq,
        }

    def _signature_of(self, status: dict) -> tuple:
        return (
            status["state"],
            status["origin"],
            status["pid"],
            status["restart_count"],
            status["exit_code"],
            status["self_heal"],
            status["autostart"],
            bool(self.probe and self.probe.ok),
        )

    async def _broadcast_if_changed(self) -> None:
        status = self.status()
        signature = self._signature_of(status)
        if signature != self._signature:
            self._signature = signature
            await self._bus.publish("services.status", status)

    def configure(self, *, self_heal: bool | None = None, autostart: bool | None = None) -> None:
        with self._lock:
            changes: dict[str, bool] = {}
            if self_heal is not None and self_heal != self.self_heal:
                self.self_heal = changes["self_heal"] = self_heal
                self.ring.note(f"self-heal turned {'on' if self_heal else 'off'}")
                # Turning it on should rescue a service that already gave up, rather
                # than waiting for the next crash to prove the switch works.
                if self_heal and self.state == ServiceState.FAILED:
                    self._desired = True
                    self._backoff = self.spec.backoff_initial
                    self._retry_at = 0.0
                    self.state = ServiceState.BACKOFF
            if autostart is not None and autostart != self.autostart:
                self.autostart = changes["autostart"] = autostart
            if changes:
                settings.update(self.spec.name, **changes)

    async def run_test(self) -> TestOutcome:
        """The Test button. Unlike a probe this may do real work — an inference, a
        shell command — so it never runs on the tick loop, only when asked."""
        if self.spec.self_test is None:
            raise ServiceError(f"{self.spec.name} has no functional test")
        if not self._alive and self.origin != ServiceOrigin.EXTERNAL:
            raise ServiceError(f"{self.spec.name} is not running")

        self.ring.note("running functional test")
        outcome = await selftest.run(self.spec.self_test, self.spec.name)
        self.last_test = outcome
        self.ring.note(
            f"test {'passed' if outcome.ok else 'FAILED'}: {outcome.summary}"
        )
        logger.info(f"{self.spec.name}: test {'ok' if outcome.ok else 'failed'} — {outcome.summary}")
        await self._bus.publish("services.status", self.status())
        return outcome

    # ----------------------------------------------------------------- spawn

    def _pid_file(self):
        return SERVICE_RUN_DIR / f"{self.spec.name}.json"

    def _write_pid_file(self, process: psutil.Process) -> None:
        SERVICE_RUN_DIR.mkdir(parents=True, exist_ok=True)
        self._pid_file().write_text(
            json.dumps(
                {
                    "pid": process.pid,
                    # Guards against PID reuse: a recycled PID will not have the
                    # same creation timestamp, so it can never be mistaken for ours.
                    "create_time": process.create_time(),
                    "started_at": self._started_at,
                    "cmd": self.spec.cmd,
                }
            )
        )

    def _clear_pid_file(self) -> None:
        self._pid_file().unlink(missing_ok=True)

    def _pump(self, proc: PtyProcess) -> None:
        """Drain the pseudo-console until it closes. Everything is kept verbatim —
        colour, cursor moves, carriage returns — because the UI renders it in a real
        terminal emulator rather than a list of strings."""
        while True:
            try:
                data = proc.read(READ_SIZE)
            except EOFError:
                break
            except OSError:
                break
            if not data:
                if not proc.isalive():
                    break
                time.sleep(0.02)
                continue
            entry = self.ring.append(data)
            with self._pending_lock:
                self._pending.append(entry)

    def _spawn(self) -> None:
        env = {**os.environ, **self.spec.env}
        logger.info(f"{self.spec.name}: starting — {' '.join(self.spec.cmd)}")
        self.ring.note(f"starting: {' '.join(self.spec.cmd)}")

        # Claim ownership before the blocking spawn, not after: on Windows the call
        # takes long enough for the service to bind its port while this thread is
        # still inside it (D9).
        self.origin = ServiceOrigin.SUPERVISED
        self.state = ServiceState.STARTING
        self._started_at = time.time()
        try:
            self._proc = PtyProcess.spawn(
                self.spec.cmd,
                cwd=str(self.spec.cwd) if self.spec.cwd else None,
                env=env,
                dimensions=(self._rows, self._cols),
            )
        except Exception as error:  # pywinpty raises bare OSError/RuntimeError
            self.error = str(error)
            self.state = ServiceState.FAILED
            self.origin = ServiceOrigin.NONE
            self._started_at = None
            self._proc = None
            self.ring.note(f"failed to start: {error}")
            logger.error(f"{self.spec.name}: spawn failed — {error}")
            return

        self.error = None
        self.exit_code = None
        self._healthy_since = None
        self._unhealthy_since = None
        self._external = None
        self._external_owner = None
        self._adopted = None

        self._reader = threading.Thread(target=self._pump, args=(self._proc,), daemon=True)
        self._reader.start()

        try:
            self._write_pid_file(psutil.Process(self._proc.pid))
        except psutil.Error:
            pass  # exited within milliseconds; the reap in tick() will report it

    def _on_exit(self, code: int | None) -> None:
        self.exit_code = code
        self._proc = None
        self._adopted = None
        self._started_at = None
        self._healthy_since = None
        self.origin = ServiceOrigin.NONE
        self.probe = None
        self._clear_pid_file()
        self.ring.note(f"process exited with code {code}")
        logger.warning(f"{self.spec.name}: exited with code {code}")

        # A core service exiting is a failure whatever the code says — none of these
        # are meant to return. So self-heal alone decides, with no exit-code nuance.
        if self._desired and self.self_heal:
            self.state = ServiceState.BACKOFF
            self._retry_at = time.time() + self._backoff
            self.ring.note(f"self-heal: restarting in {self._backoff:.0f}s")
            self._backoff = min(self._backoff * 2, self.spec.backoff_max)
        else:
            self._desired = False
            self.state = ServiceState.FAILED
            if not self.self_heal:
                self.ring.note("self-heal is off — leaving it stopped")

    # ------------------------------------------------------------------ kill

    def _kill_tree(self, process: psutil.Process) -> None:
        """Children first: vl-server is a Python launcher whose real work is a
        llama-server.exe child, and killing only the parent would orphan it on the
        port — which is exactly the state that later looks like a foreign owner."""
        try:
            children = process.children(recursive=True)
        except psutil.Error:
            children = []

        for victim in [*children, process]:
            try:
                victim.terminate()
            except psutil.Error:
                pass

        _, alive = psutil.wait_procs([*children, process], timeout=STOP_GRACE)
        for victim in alive:
            try:
                victim.kill()
            except psutil.Error:
                pass

    # --------------------------------------------------------------- actions

    def start(self) -> None:
        with self._lock:
            if self._alive:
                raise ServiceError(f"{self.spec.name} is already running")
            if self.origin == ServiceOrigin.EXTERNAL:
                owner = self._external_owner.pid if self._external_owner else self.pid
                raise ServiceError(
                    f"port {self.spec.probe.port} is held by an external process "
                    f"(pid {owner}); use takeover to replace it"
                )
            self._desired = True
            self._backoff = self.spec.backoff_initial
            self._retry_at = 0.0
            self._spawn()

    def stop(self) -> None:
        with self._lock:
            self._stop_locked()

    def _stop_locked(self) -> None:
        self._desired = False
        try:
            target = psutil.Process(self._proc.pid) if self._proc else self._adopted
            if target is not None:
                logger.info(f"{self.spec.name}: stopping pid {target.pid}")
                self.ring.note(f"stopping pid {target.pid}")
                self._kill_tree(target)
        except psutil.Error:
            pass  # already gone — the teardown below still has to run

        if self._proc is not None:
            try:
                self._proc.close(force=True)
            except Exception:
                pass
        self._proc = None
        self._adopted = None
        self._started_at = None
        self._healthy_since = None
        self.origin = ServiceOrigin.NONE
        self.state = ServiceState.STOPPED
        self.probe = None
        self._clear_pid_file()

    def restart(self) -> None:
        with self._lock:
            if self._alive:
                self._stop_locked()
            self.restart_count += 1
            self.start()

    def takeover(self) -> None:
        with self._lock:
            if self.origin != ServiceOrigin.EXTERNAL or self._external is None:
                raise ServiceError(f"{self.spec.name} has no external process to take over")
            logger.info(f"{self.spec.name}: taking over pid {self._external.pid}")
            self.ring.note(f"taking over external pid {self._external.pid}")
            try:
                self._kill_tree(self._external)
            except psutil.NoSuchProcess:
                pass
            self._external = None
            self._external_owner = None
            self.origin = ServiceOrigin.NONE
            self.start()

    def resize(self, rows: int, cols: int) -> None:
        """Keep the pseudo-console the same shape as the terminal on screen —
        without this, anything that draws to the full width wraps at the wrong
        column and the pane fills with broken lines."""
        with self._lock:
            self._rows, self._cols = rows, cols
            if self._proc is not None:
                try:
                    self._proc.setwinsize(rows, cols)
                except Exception as error:
                    logger.debug(f"{self.spec.name}: resize failed — {error}")

    # -------------------------------------------------------------- adoption

    def adopt(self) -> None:
        """Called once at agent start. A live PID file means a previous agent run
        left this service running; adopting it is what allows the agent to restart
        mid-scrape without taking the pipeline down with it (D10)."""
        path = self._pid_file()
        if not path.exists():
            return
        try:
            record = json.loads(path.read_text())
            process = psutil.Process(record["pid"])
            if abs(process.create_time() - record["create_time"]) > 1.0:
                raise psutil.NoSuchProcess(record["pid"])
        except (psutil.Error, json.JSONDecodeError, KeyError, OSError):
            path.unlink(missing_ok=True)
            return

        self._adopted = process
        self.origin = ServiceOrigin.ADOPTED
        self.state = ServiceState.RUNNING
        self._desired = True
        self._started_at = record.get("started_at") or process.create_time()
        self.ring.note(
            f"adopted running pid {process.pid} from a previous agent run — "
            "its console belonged to that process, so there is no output to show "
            "until it is restarted"
        )
        logger.info(f"{self.spec.name}: adopted pid {process.pid}")

    def detect_external(self) -> None:
        """Only meaningful when nothing of ours is running: whoever holds the port
        is someone else's process, and the UI offers to take it over.

        The process holding the socket is often a *descendant* of what a human would
        call the service: uv venv pythons and console-script .exe files are
        trampolines that re-exec the managed interpreter, and vl-server's launcher
        supervises llama-server.exe. So the port owner identifies the service, but
        `_service_root` is what takeover has to kill (D11)."""
        owner = _port_owner(self.spec.probe.port)
        if owner is None:
            return
        root = _service_root(owner)
        if self._external is None or self._external.pid != root.pid:
            described = _describe(root)
            self.ring.note(
                f"port {self.spec.probe.port} held by external pid {owner.pid}, "
                f"owned by {described['cmdline'] if described else root.pid}"
            )
            logger.info(f"{self.spec.name}: external root pid {root.pid} (port owner {owner.pid})")
        self._external = root
        self._external_owner = owner
        self.origin = ServiceOrigin.EXTERNAL
        self.state = ServiceState.RUNNING
        self._started_at = root.create_time()

    # ------------------------------------------------------------------ tick

    async def _flush_terminal(self) -> None:
        with self._pending_lock:
            if not self._pending:
                return
            batch, self._pending = self._pending, []
        await self._bus.publish(f"services.logs.{self.spec.name}", batch)

    async def tick(self) -> None:
        await self._flush_terminal()

        now = time.time()
        if now - self._last_probe_at < self.spec.probe_interval:
            return

        # An operator action is mid-flight on a worker thread; its own state is
        # authoritative until it finishes, so skip this round rather than race it.
        # The lock is held across the probe await deliberately: a probe is bounded
        # by its timeout, and letting an action interleave with the result being
        # applied is what produced a stale verdict in the first place (D9).
        if not self._lock.acquire(blocking=False):
            return
        try:
            self._last_probe_at = now

            # 1. reap anything of ours that died
            if self.origin == ServiceOrigin.SUPERVISED and self._proc is not None:
                if not self._proc.isalive():
                    self._on_exit(_exit_status(self._proc))
            elif self.origin == ServiceOrigin.ADOPTED and self._adopted is not None:
                if not self._adopted.is_running():
                    self._on_exit(None)

            if self._alive:
                await self._probe_alive(now)
            else:
                await self._probe_idle(now)
        finally:
            self._lock.release()

        await self._broadcast_if_changed()

    async def _probe_alive(self, now: float) -> None:
        self.probe = await run_probe(self.spec.probe, self.spec.probe_extra)
        if self.probe.ok:
            self.state = ServiceState.RUNNING
            self._unhealthy_since = None
            if self._healthy_since is None:
                self._healthy_since = now
            elif now - self._healthy_since >= self.spec.healthy_reset_after:
                self._backoff = self.spec.backoff_initial
            return

        self._healthy_since = None
        within_grace = self._started_at is not None and now - self._started_at < self.spec.start_grace
        self.state = ServiceState.STARTING if within_grace else ServiceState.UNHEALTHY
        if within_grace:
            return

        # Wedged rather than crashed: still holding the port, answering nothing.
        # A crash-only policy never notices this, which is why self-heal covers it.
        if self._unhealthy_since is None:
            self._unhealthy_since = now
        elif (
            self.self_heal
            and self.spec.unhealthy_grace > 0
            and now - self._unhealthy_since >= self.spec.unhealthy_grace
        ):
            self.ring.note(
                f"self-heal: probe failing for {self.spec.unhealthy_grace:.0f}s "
                "while the process is still alive — restarting"
            )
            self._unhealthy_since = None
            self.restart()

    async def _probe_idle(self, now: float) -> None:
        self.probe = await run_probe(self.spec.probe, self.spec.probe_extra)
        if self.probe.ok:
            self.detect_external()
            return

        if self.origin == ServiceOrigin.EXTERNAL:
            self.ring.note("external process is gone")
            self._external = None
            self._external_owner = None
            self._started_at = None
            self.origin = ServiceOrigin.NONE
            self.state = ServiceState.STOPPED

        if self._desired and self.self_heal and now >= self._retry_at:
            self.restart_count += 1
            self._spawn()


def _exit_status(proc: PtyProcess) -> int | None:
    try:
        proc.wait()
    except Exception:
        pass
    return proc.exitstatus


# Processes that host a service but are not part of it. Walking up the parent chain
# stops here, which is what separates "the service" from "the terminal it was
# launched from".
SESSION_HOSTS = {
    "explorer.exe", "cmd.exe", "powershell.exe", "pwsh.exe", "windowsterminal.exe",
    "wt.exe", "openconsole.exe", "conhost.exe", "services.exe", "svchost.exe",
    "wininit.exe", "winlogon.exe", "code.exe", "bash.exe", "sh.exe",
}
MAX_ANCESTRY = 6


def _own_lineage() -> set[int]:
    """Us and everything above us. The takeover walk must never climb into this —
    killing our own parent would take the agent down with the service."""
    lineage = {os.getpid()}
    try:
        for ancestor in psutil.Process().parents():
            lineage.add(ancestor.pid)
    except psutil.Error:
        pass
    return lineage


def _service_root(owner: psutil.Process) -> psutil.Process:
    """Resolve the process holding the port to the outermost process that is still
    part of the same service.

    This is not cosmetic. vl-server's launcher (start_vl_server.py) runs its own
    restart loop around llama-server.exe, so killing only the port holder would have
    the launcher bring it straight back and fight the takeover. psutil.parent()
    already rejects a recycled PPID by comparing creation times, so the walk cannot
    climb into an unrelated process that inherited the id."""
    forbidden = _own_lineage()
    root = owner
    for _ in range(MAX_ANCESTRY):
        try:
            parent = root.parent()
        except psutil.Error:
            break
        if parent is None or parent.pid in forbidden or parent.pid <= 4:
            break
        try:
            if parent.name().lower() in SESSION_HOSTS:
                break
        except psutil.Error:
            break
        root = parent
    return root


def _describe(process: psutil.Process | None) -> dict | None:
    if process is None:
        return None
    try:
        return {
            "pid": process.pid,
            "name": process.name(),
            "cmdline": " ".join(process.cmdline()) or process.name(),
        }
    except psutil.Error:
        return {"pid": process.pid, "name": None, "cmdline": None}


def _port_owner(port: int) -> psutil.Process | None:
    try:
        connections = psutil.net_connections(kind="inet")
    except (psutil.AccessDenied, OSError):
        return None

    for connection in connections:
        if connection.status != psutil.CONN_LISTEN or connection.pid is None:
            continue
        if connection.laddr.port != port:
            continue
        try:
            return psutil.Process(connection.pid)
        except psutil.Error:
            return None
    return None


class Supervisor:
    def __init__(self, specs: list[ServiceSpec], bus: EventBus) -> None:
        self.services = {spec.name: ManagedService(spec, bus) for spec in specs}
        self._task: asyncio.Task | None = None

    def get(self, name: str) -> ManagedService:
        service = self.services.get(name)
        if service is None:
            raise KeyError(name)
        return service

    def statuses(self) -> list[dict]:
        return [service.status() for service in self.services.values()]

    async def start(self) -> None:
        for service in self.services.values():
            service.adopt()
            if service.origin == ServiceOrigin.NONE:
                # An unadopted service may still be up from before the agent ever
                # ran (the wt.exe shortcut, a manual launch) — find that out before
                # autostart decides to spawn a second copy onto a busy port.
                service.probe = await run_probe(service.spec.probe, service.spec.probe_extra)
                if service.probe.ok:
                    service.detect_external()

            if service.autostart and service.origin == ServiceOrigin.NONE:
                try:
                    service.start()
                except ServiceError as error:
                    logger.warning(f"{service.spec.name}: autostart skipped — {error}")

        self._task = asyncio.create_task(self._run())

    async def _run(self) -> None:
        while True:
            for service in self.services.values():
                try:
                    await service.tick()
                except Exception:
                    logger.exception(f"{service.spec.name}: supervisor tick failed")
            await asyncio.sleep(TICK)

    async def shutdown(self) -> None:
        """Supervised processes are deliberately left running: their PID files are
        what the next agent run adopts. Stopping a service is an explicit action,
        never a side effect of the agent restarting (D10)."""
        if self._task is None:
            return
        self._task.cancel()
        try:
            await self._task
        except asyncio.CancelledError:
            pass
