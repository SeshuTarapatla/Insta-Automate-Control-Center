"""The read-only dependency panel (PLAN CP 2.3).

Everything the pipeline needs but the agent does not supervise: the cluster, the
database, Prefect, the pods, the phone, the network, Syncthing and disk. Checks are
independent, run concurrently, and each is individually timed out — one hung check
must not stall the panel, and a failure has to name itself rather than turning the
whole request into a 500.
"""
import asyncio
import shutil
import time
from dataclasses import dataclass, field
from enum import StrEnum

import psutil

from ia_agent.integrations import kube, postgres, prefect
from ia_agent.logging import logger
from ia_agent.services.selftest import adb_device_present
from ia_agent.vars import IA_DIR

CHECK_TIMEOUT = 10.0
CACHE_TTL = 5.0

# Free space on the IA_DIR volume. 7.5k images and growing, plus Postgres and the
# k3s image store share this disk.
DISK_WARN_GB = 25.0
DISK_FAIL_GB = 8.0


class Level(StrEnum):
    OK = "ok"
    WARN = "warn"
    FAIL = "fail"


class Group(StrEnum):
    CLUSTER = "cluster"
    PIPELINE = "pipeline"
    HOST = "host"


@dataclass
class Dependency:
    key: str
    label: str
    group: Group
    level: Level
    detail: str
    metrics: dict = field(default_factory=dict)
    latency_ms: float = 0.0

    def as_dict(self) -> dict:
        return {
            "key": self.key,
            "label": self.label,
            "group": self.group,
            "level": self.level,
            "ok": self.level != Level.FAIL,
            "detail": self.detail,
            "metrics": self.metrics,
            "latency_ms": round(self.latency_ms, 1),
        }


# ------------------------------------------------------------------- checks


async def _k3s() -> tuple[Level, str, dict]:
    version = await asyncio.to_thread(kube.server_version)
    return Level.OK, f"k3s API reachable — {version}", {"version": version}


async def _postgres() -> tuple[Level, str, dict]:
    info = await asyncio.to_thread(postgres.check)
    return (
        Level.OK,
        f"{info['database']} on PostgreSQL {info['version']} — "
        f"{info['tables']} tables, {info['size']}",
        info,
    )


async def _prefect_server() -> tuple[Level, str, dict]:
    if not await prefect.health():
        return Level.FAIL, "Prefect API did not report healthy", {}
    version = await prefect.version()
    return Level.OK, f"Prefect server healthy — {version}", {"version": version}


async def _prefect_pool() -> tuple[Level, str, dict]:
    pool = await prefect.work_pool()
    if pool is None:
        return Level.FAIL, f"work pool {prefect.WORK_POOL} does not exist", {}

    found = await prefect.workers()
    online = [worker for worker in found if (worker.get("status") or "").upper() == "ONLINE"]
    metrics = {
        "pool": pool.get("name"),
        "paused": pool.get("is_paused"),
        "workers": len(found),
        "online": len(online),
        "worker_names": [worker.get("name") for worker in online],
    }

    if pool.get("is_paused"):
        return Level.FAIL, f"{pool.get('name')} is paused — nothing will be picked up", metrics
    if not online:
        # The pool existing is not the same as the pool being served; a deployment
        # submitted to an unattended pool sits in Pending forever.
        return Level.FAIL, f"{pool.get('name')} has no ONLINE worker polling it", metrics
    return Level.OK, f"{pool.get('name')} served by {len(online)} worker(s)", metrics


def _pod_check(deployment: str, label: str):
    async def check() -> tuple[Level, str, dict]:
        found = await asyncio.to_thread(kube.pods, deployment)
        if not found:
            return Level.FAIL, f"no {deployment} pod found in {kube.NAMESPACE}", {"pods": []}

        metrics = {"pods": found, "restarts": sum(pod["restarts"] for pod in found)}
        unhealthy = [pod for pod in found if pod["phase"] != "Running" or not pod["ready"]]
        if unhealthy:
            names = ", ".join(f"{pod['name']} {pod['phase']}" for pod in unhealthy)
            return Level.FAIL, f"{label}: {names}", metrics

        restarts = metrics["restarts"]
        detail = f"{len(found)} pod(s) Running, {restarts} restart(s)"
        # A running pod with a high restart count is the shape of a crash loop that
        # happens to be up right now — worth a colour, not an alarm.
        return (Level.WARN if restarts >= 10 else Level.OK), detail, metrics

    return check


async def _adb() -> tuple[Level, str, dict]:
    ok, detail = await adb_device_present()
    return (Level.OK if ok else Level.FAIL), detail, {}


async def _internet() -> tuple[Level, str, dict]:
    def probe() -> bool:
        from my_modules.inet import Internet

        return Internet().is_active

    return (Level.OK, "reachable", {}) if await asyncio.to_thread(probe) else (
        Level.FAIL, "no route to 1.1.1.1:80", {}
    )


async def _syncthing() -> tuple[Level, str, dict]:
    def find() -> list[int]:
        pids = []
        for process in psutil.process_iter(["name"]):
            name = (process.info.get("name") or "").lower()
            if "syncthing" in name:
                pids.append(process.pid)
        return pids

    pids = await asyncio.to_thread(find)
    if not pids:
        # Not fatal to the pipeline — it is how the phone stays in step, so its
        # absence means stale images on the phone, not a broken run.
        return Level.WARN, "not running — the phone will not see new images", {"pids": []}
    return Level.OK, f"running (pid {', '.join(map(str, pids))})", {"pids": pids}


async def _disk() -> tuple[Level, str, dict]:
    usage = await asyncio.to_thread(shutil.disk_usage, str(IA_DIR))
    free_gb = usage.free / 1024**3
    metrics = {
        "free_gb": round(free_gb, 1),
        "total_gb": round(usage.total / 1024**3, 1),
        "path": str(IA_DIR),
    }
    detail = f"{free_gb:.0f} GB free of {metrics['total_gb']:.0f} GB on {IA_DIR.drive or IA_DIR}"
    if free_gb < DISK_FAIL_GB:
        return Level.FAIL, detail, metrics
    if free_gb < DISK_WARN_GB:
        return Level.WARN, detail, metrics
    return Level.OK, detail, metrics


CHECKS: list[tuple[str, str, Group, object]] = [
    ("k3s", "k3s cluster", Group.CLUSTER, _k3s),
    ("postgres", "PostgreSQL", Group.CLUSTER, _postgres),
    ("prefect-server", "Prefect server", Group.CLUSTER, _prefect_server),
    ("prefect-pool", "Work pool", Group.CLUSTER, _prefect_pool),
    # server.yaml runs `ia prefect serve` — the trigger loops. worker.yaml runs the
    # Prefect worker that actually executes flow runs. Roles are easy to swap by
    # mistake: the *worker* deployment is not the scheduler.
    ("pod-scheduler", "Scheduler pod", Group.PIPELINE,
     _pod_check("insta-automate", "scheduler pod")),
    ("pod-worker", "Worker pod", Group.PIPELINE,
     _pod_check("insta-automate-worker", "worker pod")),
    ("adb-device", "Phone", Group.PIPELINE, _adb),
    ("internet", "Internet", Group.HOST, _internet),
    ("syncthing", "Syncthing", Group.HOST, _syncthing),
    ("disk", "IA_DIR volume", Group.HOST, _disk),
]


async def _run_one(key: str, label: str, group: Group, check) -> Dependency:
    started = time.perf_counter()
    try:
        level, detail, metrics = await asyncio.wait_for(check(), timeout=CHECK_TIMEOUT)
    except asyncio.TimeoutError:
        level, detail, metrics = Level.FAIL, f"timed out after {CHECK_TIMEOUT:.0f}s", {}
    except Exception as error:
        logger.debug(f"dependency {key} failed", exc_info=True)
        level, detail, metrics = Level.FAIL, f"{type(error).__name__}: {error}", {}
        # A dead cluster invalidates cached clients: k3s hands out a new certificate
        # when it restarts, so a stale client would keep failing after recovery.
        if key in ("k3s", "postgres"):
            kube.reset()
            postgres.reset()

    return Dependency(
        key=key,
        label=label,
        group=group,
        level=level,
        detail=detail,
        metrics=metrics,
        latency_ms=(time.perf_counter() - started) * 1000,
    )


_cache: tuple[float, list[dict]] | None = None
_cache_lock = asyncio.Lock()


async def snapshot(force: bool = False) -> list[dict]:
    """All checks concurrently. Cached briefly because the panel polls and several
    of these open sockets to the cluster."""
    global _cache
    async with _cache_lock:
        if not force and _cache and time.time() - _cache[0] < CACHE_TTL:
            return _cache[1]

        results = await asyncio.gather(
            *(_run_one(key, label, group, check) for key, label, group, check in CHECKS)
        )
        payload = [dependency.as_dict() for dependency in results]
        _cache = (time.time(), payload)
        return payload
