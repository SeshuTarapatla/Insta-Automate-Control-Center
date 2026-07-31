from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from enum import StrEnum
from pathlib import Path

# Runs after the port probe passes, to answer "is it actually serving *this*
# pipeline" rather than "is something listening" — adb with no phone attached is
# the case that motivates it. Returns (ok, detail).
ExtraProbe = Callable[[], Awaitable[tuple[bool, str]]]

# The functional test behind the UI's Test button. Cheap probes run every few
# seconds; this runs only when asked, and may do real work.
SelfTest = Callable[[], Awaitable["TestOutcome"]]


class ServiceState(StrEnum):
    STOPPED = "stopped"
    STARTING = "starting"  # spawned, still inside start_grace with a failing probe
    RUNNING = "running"  # alive and the probe passes
    UNHEALTHY = "unhealthy"  # alive but the probe fails
    BACKOFF = "backoff"  # exited, waiting out the self-heal delay
    FAILED = "failed"  # exited and will not be restarted


class ServiceOrigin(StrEnum):
    """Who owns the running process. This is the distinction that lets the agent
    restart without killing a running scrape (PLAN CP 2.1)."""

    NONE = "none"
    SUPERVISED = "supervised"  # we spawned it this run, so its terminal is captured
    ADOPTED = "adopted"  # our PID file from a previous run is still alive; no output
    EXTERNAL = "external"  # the port is held by a process we never started


class ProbeKind(StrEnum):
    TCP = "tcp"
    HTTP = "http"


@dataclass(frozen=True)
class TestOutcome:
    """Result of a functional test. `metrics` is what makes the difference between
    'the port is open' and 'classification runs at 0.2 s/img instead of 12'."""

    ok: bool
    summary: str
    metrics: dict = field(default_factory=dict)
    duration_ms: float = 0.0
    at: float = 0.0

    def as_dict(self) -> dict:
        return {
            "ok": self.ok,
            "summary": self.summary,
            "metrics": self.metrics,
            "duration_ms": round(self.duration_ms, 1),
            "at": self.at,
        }


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
    probe_extra: ExtraProbe | None = None
    self_test: SelfTest | None = None

    # Defaults only. Both are overridden per service at runtime from services.json,
    # so the switches in the UI survive an agent restart (D12).
    autostart: bool = False
    self_heal: bool = True

    backoff_initial: float = 1.0
    backoff_max: float = 60.0
    probe_interval: float = 5.0
    # A probe failure this soon after spawning reads as STARTING, not UNHEALTHY —
    # vl-server needs to load a 4B model before it answers anything.
    start_grace: float = 30.0
    # Seconds a live-but-unhealthy process is tolerated before self-heal restarts it.
    # This covers wedging, which is the failure a crash-only policy misses: a service
    # can hold its port while answering nothing. 0 disables it for this service.
    unhealthy_grace: float = 60.0
    # How long a service must stay healthy before the self-heal backoff resets.
    healthy_reset_after: float = 60.0
    # ConPTY grid the service is spawned into. The UI resizes it to match the
    # on-screen terminal; this is only what it starts as.
    rows: int = 40
    cols: int = 140
