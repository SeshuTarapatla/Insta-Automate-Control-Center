from dataclasses import dataclass, field
from enum import StrEnum
from pathlib import Path


class ServiceState(StrEnum):
    STOPPED = "stopped"
    STARTING = "starting"  # spawned, still inside start_grace with a failing probe
    RUNNING = "running"  # alive and the probe passes
    UNHEALTHY = "unhealthy"  # alive but the probe fails
    BACKOFF = "backoff"  # exited, waiting out the restart delay
    FAILED = "failed"  # exited and will not be restarted


class ServiceOrigin(StrEnum):
    """Who owns the running process. This is the distinction that lets the agent
    restart without killing a scrape that is halfway through (PLAN CP 2.1)."""

    NONE = "none"
    SUPERVISED = "supervised"  # we spawned it this run, so stdout is captured
    ADOPTED = "adopted"  # our PID file from a previous run is still alive; no stdout
    EXTERNAL = "external"  # the port is held by a process we never started


class RestartPolicy(StrEnum):
    ALWAYS = "always"
    ON_FAILURE = "on-failure"  # only when the exit code is non-zero
    NEVER = "never"


class ProbeKind(StrEnum):
    TCP = "tcp"
    HTTP = "http"


@dataclass(frozen=True)
class HealthProbe:
    kind: ProbeKind
    port: int
    host: str = "127.0.0.1"
    path: str = "/"  # HTTP only
    expect_status: int = 200
    timeout: float = 2.0


@dataclass(frozen=True)
class ServiceSpec:
    name: str
    label: str
    cmd: list[str]
    probe: HealthProbe
    description: str = ""
    cwd: Path | None = None
    env: dict[str, str] = field(default_factory=dict)
    autostart: bool = False
    restart: RestartPolicy = RestartPolicy.ALWAYS
    backoff_initial: float = 1.0
    backoff_max: float = 60.0
    probe_interval: float = 5.0
    # A probe failure this soon after spawning reads as STARTING, not UNHEALTHY —
    # vl-server needs to load a 4B model before it answers anything.
    start_grace: float = 30.0
    # Seconds a live-but-unhealthy process is tolerated before it is restarted.
    # 0 disables it: a wedged process stays red until a human presses Restart,
    # which is what the Phase 2 test expects.
    unhealthy_grace: float = 0.0
    # How long a service must stay healthy before the restart backoff resets.
    healthy_reset_after: float = 60.0
