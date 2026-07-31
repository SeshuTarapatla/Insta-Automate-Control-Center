"""Dependency-panel logic, with the cluster faked out.

The live cluster is green, so its failure paths cannot be exercised against it
without breaking the user's pipeline. These are the cases the panel actually exists
for — a paused pool, an unattended pool, a crash-looping pod, a hung check — driven
with fakes so they can be asserted without taking anything down."""
import asyncio
import sys
import time
import types

from ia_agent import dependencies as deps
from ia_agent.dependencies import Group, Level
from ia_agent.integrations import kube

OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


def fake_pod(name, hashed=True):
    return types.SimpleNamespace(
        metadata=types.SimpleNamespace(
            name=name, labels={"pod-template-hash": "abc123"} if hashed else {}
        )
    )


async def main():
    print("\n1. deployment name is derived exactly, not by prefix")
    check("scheduler pod maps to its deployment",
          kube._deployment_of(fake_pod("insta-automate-5465cb5db5-f9dln")) == "insta-automate")
    check("worker pod does not collide with it",
          kube._deployment_of(fake_pod("insta-automate-worker-5c6df748d7-g27zv"))
          == "insta-automate-worker")
    check("a bare pod name is left alone",
          kube._deployment_of(fake_pod("standalone", hashed=False)) == "standalone")

    print("\n2. a check that raises becomes a FAIL naming itself, not a 500")
    async def boom():
        raise RuntimeError("cluster unreachable")

    result = await deps._run_one("x", "X", Group.CLUSTER, boom)
    check("level is fail", result.level == Level.FAIL)
    check("exception surfaced", "RuntimeError: cluster unreachable" in result.detail, result.detail)
    check("still reports as a dependency", result.as_dict()["ok"] is False)

    print("\n3. a hung check is timed out, not waited on")
    async def hang():
        await asyncio.sleep(30)

    deps.CHECK_TIMEOUT = 0.3
    started = time.perf_counter()
    result = await deps._run_one("slow", "Slow", Group.HOST, hang)
    elapsed = time.perf_counter() - started
    check("times out", result.level == Level.FAIL and "timed out" in result.detail, result.detail)
    check("returns promptly", elapsed < 3, f"{elapsed:.1f}s")
    deps.CHECK_TIMEOUT = 10.0

    print("\n4. pods: missing, unhealthy, and crash-looping")
    original = kube.pods
    try:
        kube.pods = lambda deployment: []
        level, detail, _ = await deps._pod_check("dep", "dep")()
        check("no pod at all is a FAIL", level == Level.FAIL, detail)

        kube.pods = lambda deployment: [
            {"name": "dep-1", "phase": "CrashLoopBackOff", "ready": False, "restarts": 4,
             "started_at": None}
        ]
        level, detail, _ = await deps._pod_check("dep", "dep")()
        check("not Running is a FAIL", level == Level.FAIL, detail)

        kube.pods = lambda deployment: [
            {"name": "dep-1", "phase": "Running", "ready": True, "restarts": 201,
             "started_at": None}
        ]
        level, detail, metrics = await deps._pod_check("dep", "dep")()
        check("running but heavily restarted is a WARN", level == Level.WARN, detail)
        check("restart count reported", metrics["restarts"] == 201)

        kube.pods = lambda deployment: [
            {"name": "dep-1", "phase": "Running", "ready": True, "restarts": 0,
             "started_at": None}
        ]
        level, _, _ = await deps._pod_check("dep", "dep")()
        check("healthy pod is OK", level == Level.OK)
    finally:
        kube.pods = original

    print("\n5. work pool: missing, paused, and unattended")
    prefect = deps.prefect
    saved = (prefect.work_pool, prefect.workers)
    try:
        async def no_pool(name=None):
            return None
        prefect.work_pool = no_pool
        level, detail, _ = await deps._prefect_pool()
        check("missing pool is a FAIL", level == Level.FAIL, detail)

        async def paused(name=None):
            return {"name": "insta-automate-pool", "is_paused": True}
        async def one_worker(name=None):
            return [{"name": "w1", "status": "ONLINE"}]
        prefect.work_pool, prefect.workers = paused, one_worker
        level, detail, _ = await deps._prefect_pool()
        check("paused pool is a FAIL", level == Level.FAIL, detail)
        check("says what paused means", "nothing will be picked up" in detail, detail)

        async def live(name=None):
            return {"name": "insta-automate-pool", "is_paused": False}
        async def offline(name=None):
            return [{"name": "w1", "status": "OFFLINE"}]
        prefect.work_pool, prefect.workers = live, offline
        level, detail, metrics = await deps._prefect_pool()
        # The failure a plain "does the pool exist" check misses entirely.
        check("pool with no ONLINE worker is a FAIL", level == Level.FAIL, detail)
        check("online count reported", metrics["online"] == 0)

        prefect.workers = one_worker
        level, detail, _ = await deps._prefect_pool()
        check("served pool is OK", level == Level.OK, detail)
    finally:
        prefect.work_pool, prefect.workers = saved

    print("\n6. disk thresholds")
    import shutil
    original_usage = shutil.disk_usage
    try:
        def usage(gb):
            return lambda path: types.SimpleNamespace(
                total=500 * 1024**3, used=0, free=int(gb * 1024**3)
            )
        shutil.disk_usage = usage(100)
        level, _, metrics = await deps._disk()
        check("plenty of space is OK", level == Level.OK, str(metrics))
        shutil.disk_usage = usage(20)
        level, _, _ = await deps._disk()
        check("under 25 GB warns", level == Level.WARN)
        shutil.disk_usage = usage(3)
        level, _, _ = await deps._disk()
        check("under 8 GB fails", level == Level.FAIL)
    finally:
        shutil.disk_usage = original_usage

    print("\n7. snapshot caches, and refresh forces")
    deps._cache = None
    first = await deps.snapshot()
    started = time.perf_counter()
    second = await deps.snapshot()
    cached_ms = (time.perf_counter() - started) * 1000
    check("cache hit is instant", cached_ms < 20, f"{cached_ms:.1f} ms")
    check("same payload returned", first is second)
    check("every check reported", len(first) == len(deps.CHECKS), f"{len(first)}")
    check("summary levels are valid",
          all(item["level"] in ("ok", "warn", "fail") for item in first))

    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
