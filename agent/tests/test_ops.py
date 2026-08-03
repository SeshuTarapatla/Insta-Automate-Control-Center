"""Ops jobs (PLAN CP 7.1).

Section 1 checks the real `JOB_SPECS` registry statically — ids, confirm
flags, secret redaction — without ever executing a real command. Section 2
replaces the registry with synthetic Python-subprocess jobs and drives
`OpsJobStore` directly: sequencing, failure short-circuiting, the
one-job-at-a-time lock, and disk persistence (including reconciling a job
left "running" by a simulated agent crash). Section 3 does the same over
live REST + WS, plus desktop-only enforcement on `POST /api/ops/jobs`. No
real `ia`/`helm`/`kubectl`/`prefect-k3s` binary is ever invoked — that would
mean genuinely building an image or touching the live cluster from a test.
"""
import asyncio
import json
import shutil
import sys
import tempfile
import threading
import time
from pathlib import Path

import httpx
import uvicorn
import websockets

OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


SCRATCH = Path(tempfile.mkdtemp(prefix="ia-agent-test-ops-"))

import ia_agent.ops.jobs as jobs_module  # noqa: E402
from ia_agent.ops.jobs import JOB_SPECS, JobSpec, OpsError, OpsJobStore, Step  # noqa: E402

jobs_module.OPS_JOBS_DIR = SCRATCH / "ops_jobs"


def echo_step(*lines: str, exit_code: int = 0) -> Step:
    body = "; ".join(f"print({line!r})" for line in lines)
    if exit_code:
        body += f"; import sys; sys.exit({exit_code})"
    argv = [sys.executable, "-c", body]
    return Step(label="echo", argv=argv, display_argv=argv)


def registry_checks() -> None:
    print("\n1. the real JOB_SPECS registry is well-formed")
    expected = {
        "build", "deploy", "db_backup", "db_restore", "purge", "reset_pool",
        "helm_upgrade", "helm_uninstall", "restart_scheduler", "restart_worker",
    }
    check("every planned job kind exists", set(JOB_SPECS) == expected, str(set(JOB_SPECS)))

    confirm_expected = {"db_restore", "purge", "helm_uninstall", "restart_scheduler", "restart_worker"}
    confirm_actual = {k for k, s in JOB_SPECS.items() if s.confirm}
    check("confirm is set on exactly the consequential jobs", confirm_actual == confirm_expected, str(confirm_actual))
    check("every confirm=True job has a consequence string",
          all(s.consequence for s in JOB_SPECS.values() if s.confirm))
    check("no non-confirm job has a leftover consequence string",
          all(s.consequence is None for s in JOB_SPECS.values() if not s.confirm))

    print("\n2. helm upgrade's token never appears outside the real argv")
    step = JOB_SPECS["helm_upgrade"].build_steps("super-secret-token", "feat/control-center")[0]
    check("the real argv carries the token (it has to, to actually authenticate)",
          "agent.token=super-secret-token" in " ".join(step.argv))
    check("the display argv redacts it", "super-secret-token" not in " ".join(step.display_argv))
    check("the branch is not treated as a secret", "feat/control-center" in " ".join(step.display_argv))

    print("\n3. build/deploy/helm-upgrade steps carry GIT_BRANCH; purge/reset-pool/backup don't need it")
    build_step = JOB_SPECS["build"].build_steps("t", "my-branch")[0]
    check("build sets GIT_BRANCH", build_step.env.get("GIT_BRANCH") == "my-branch")
    deploy_step = JOB_SPECS["deploy"].build_steps("t", "my-branch")[0]
    check("deploy sets GIT_BRANCH", deploy_step.env.get("GIT_BRANCH") == "my-branch")
    purge_step = JOB_SPECS["purge"].build_steps("t", "my-branch")[0]
    check("purge carries no GIT_BRANCH override", "GIT_BRANCH" not in purge_step.env)

    print("\n3b. ia/prefect-k3s steps prepend their own venv's Scripts dir to PATH")
    check("build step's PATH starts with the ia venv Scripts dir",
          build_step.env.get("PATH", "").split(";" if ";" in build_step.env.get("PATH", "") else ":")[0]
          == str(jobs_module.IA_EXE.parent), build_step.env.get("PATH"))
    reset_pool_step = JOB_SPECS["reset_pool"].build_steps("t", "b")[0]
    check("reset-pool step's PATH starts with the prefect-k3s venv Scripts dir — the real "
          "'FileNotFoundError: [WinError 2]' fix, found live: reset-pool shells out to a bare "
          "'prefect' command that only resolves when that dir is on PATH",
          reset_pool_step.env.get("PATH", "").split(";" if ";" in reset_pool_step.env.get("PATH", "") else ":")[0]
          == str(jobs_module.PREFECT_K3S_EXE.parent), reset_pool_step.env.get("PATH"))

    print("\n4. restart_worker is the documented three-step composite (D38's fix, not optional)")
    worker_steps = JOB_SPECS["restart_worker"].build_steps("t", "b")
    check("three steps: restart, wait, redeploy", len(worker_steps) == 3, str([s.label for s in worker_steps]))
    check("the last step is the deploy that undoes D38's pool reset",
          "prefect deploy" in worker_steps[-1].label, worker_steps[-1].label)


async def store_checks() -> None:
    from ia_agent.events.bus import EventBus

    print("\n5. a successful single-step job runs to completion, streaming lines with a monotonic seq")
    jobs_module.JOB_SPECS.clear()
    jobs_module.JOB_SPECS["ok"] = JobSpec(
        id="ok", label="OK job", description="", confirm=False, consequence=None,
        build_steps=lambda t, b: [echo_step("line one", "line two")],
    )
    jobs_module.JOB_SPECS["boom"] = JobSpec(
        id="boom", label="Boom job", description="", confirm=True, consequence="it fails on purpose",
        build_steps=lambda t, b: [echo_step("before the crash", exit_code=3), echo_step("never runs")],
    )
    jobs_module.JOB_SPECS["multi"] = JobSpec(
        id="multi", label="Multi-step job", description="", confirm=False, consequence=None,
        build_steps=lambda t, b: [echo_step("step one"), echo_step("step two")],
    )

    bus = EventBus()
    subscriber = bus.subscribe()
    store = OpsJobStore(bus, token="test-token")

    meta = await store.start("ok")
    check("start() returns the running job immediately", meta["status"] == "running")
    for _ in range(50):
        if store.get_job(meta["id"])["status"] != "running":
            break
        await asyncio.sleep(0.05)
    finished = store.get_job(meta["id"])
    check("job completed successfully", finished["status"] == "succeeded" and finished["exit_code"] == 0, str(finished))
    logs = store.get_logs(meta["id"])
    check("seq is monotonic starting at 1", [e["seq"] for e in logs] == list(range(1, len(logs) + 1)), str(logs))
    check("both lines were captured in order",
          [e["text"] for e in logs if e["kind"] == "line"] == ["line one", "line two"], str(logs))

    print("\n6. a failing step stops the job and never runs the next step")
    meta = await store.start("boom")
    for _ in range(50):
        if store.get_job(meta["id"])["status"] != "running":
            break
        await asyncio.sleep(0.05)
    finished = store.get_job(meta["id"])
    check("job failed with the real exit code", finished["status"] == "failed" and finished["exit_code"] == 3, str(finished))
    logs = store.get_logs(meta["id"])
    check("the first step's output is present", any(e["text"] == "before the crash" for e in logs))
    check("the second step never ran", not any(e["text"] == "never runs" for e in logs))
    check("an error line was emitted", any(e["kind"] == "error" for e in logs), str(logs))

    print("\n7. a multi-step job runs every step, in order, before completing")
    multi_meta = await store.start("multi")
    for _ in range(50):
        if store.get_job(multi_meta["id"])["status"] != "running":
            break
        await asyncio.sleep(0.05)
    multi_logs = store.get_logs(multi_meta["id"])
    check("both steps' output present in order",
          [e["text"] for e in multi_logs if e["kind"] == "line"] == ["step one", "step two"], str(multi_logs))

    print("\n8. only one job runs at a time")
    jobs_module.JOB_SPECS["slow"] = JobSpec(
        id="slow", label="Slow job", description="", confirm=False, consequence=None,
        build_steps=lambda t, b: [Step(
            label="sleep", argv=[sys.executable, "-c", "import time; time.sleep(1); print('done')"],
            display_argv=[sys.executable, "-c", "..."],
        )],
    )
    slow_meta = await store.start("slow")
    try:
        await store.start("ok")
        check("starting a second job while one runs raises", False)
    except OpsError as error:
        check("starting a second job while one runs raises OpsError", True, str(error))

    for _ in range(60):
        if store.get_job(slow_meta["id"])["status"] != "running":
            break
        await asyncio.sleep(0.05)
    check("the slow job eventually finishes", store.get_job(slow_meta["id"])["status"] == "succeeded")

    reopened = await store.start("ok")
    for _ in range(50):
        if store.get_job(reopened["id"])["status"] != "running":
            break
        await asyncio.sleep(0.05)
    check("a follow-up job starts and completes once the previous one finishes",
          store.get_job(reopened["id"])["status"] == "succeeded")

    try:
        await store.start("nonexistent-kind")
        check("starting an unknown kind raises", False)
    except OpsError as error:
        check("starting an unknown kind raises OpsError", True, str(error))

    print("\n9. ops.jobs and ops.logs.{id} were published on the bus for a real run")
    frames = []
    while not subscriber.empty():
        frames.append(subscriber.get_nowait())
    check("status transitions were published on ops.jobs", any(f["channel"] == "ops.jobs" for f in frames))
    log_channels = {f["channel"] for f in frames if f["channel"].startswith("ops.logs.")}
    check("per-job log channels were published", len(log_channels) >= 4, str(log_channels))

    print("\n10. history persists to disk and survives a fresh OpsJobStore over the same directory")
    reloaded = OpsJobStore(bus, token="test-token")
    check("every completed job reappears", len(reloaded.list_jobs(limit=100)) == len(store.list_jobs(limit=100)),
          str((len(reloaded.list_jobs(limit=100)), len(store.list_jobs(limit=100)))))
    check("newest job is first", reloaded.list_jobs()[0]["id"] == store.list_jobs()[0]["id"])
    persisted_logs = reloaded.get_logs(multi_meta["id"])
    check("a completed job's log survives on disk",
          [e["text"] for e in persisted_logs if e["kind"] == "line"] == ["step one", "step two"],
          str(persisted_logs))

    print("\n11. a job left 'running' by a simulated crash is reconciled to 'interrupted' on load")
    crashed_id = "crashed-job-id"
    crashed_dir = jobs_module.OPS_JOBS_DIR / crashed_id
    crashed_dir.mkdir(parents=True, exist_ok=True)
    (crashed_dir / "meta.json").write_text(json.dumps({
        "id": crashed_id, "kind": "ok", "label": "OK job", "status": "running",
        "started_at": time.time(), "ended_at": None, "exit_code": None,
        "current_step": 0, "steps": ["echo"],
    }))
    recovered = OpsJobStore(bus, token="test-token")
    recovered_meta = recovered.get_job(crashed_id)
    check("the stale job is marked interrupted, not left running",
          recovered_meta is not None and recovered_meta["status"] == "interrupted", str(recovered_meta))

    print("\n12. OPS_JOBS_KEEP pruning drops the oldest job directories")
    jobs_module.OPS_JOBS_KEEP = 3
    pruned_store = OpsJobStore(EventBus(), token="test-token")
    for _ in range(5):
        m = await pruned_store.start("ok")
        for _ in range(50):
            if pruned_store.get_job(m["id"])["status"] != "running":
                break
            await asyncio.sleep(0.05)
    check("history caps at OPS_JOBS_KEEP", len(pruned_store.list_jobs(limit=100)) == 3,
          str(len(pruned_store.list_jobs(limit=100))))


registry_checks()
asyncio.run(store_checks())

# ------------------------------------------------------------------ live app

import ia_agent.app as app_module  # noqa: E402
import ia_agent.library.folders as folders  # noqa: E402
from ia_agent.library.folders import LibraryFolder  # noqa: E402

FAKE_IA_DIR = SCRATCH / "ia_dir"
FAKE_IA_DIR.mkdir(parents=True, exist_ok=True)
(FAKE_IA_DIR / "entities").mkdir(exist_ok=True)
# A fresh directory, distinct from the store-level section's above — that
# section's leftover job history would otherwise make "starts empty" false.
jobs_module.OPS_JOBS_DIR = SCRATCH / "ops_jobs_live"
app_module.build_specs = lambda: []
folders.IA_DIR = FAKE_IA_DIR
folders.FOLDERS = {"entities": LibraryFolder("entities", FAKE_IA_DIR / "entities", flat=True)}

jobs_module.JOB_SPECS["_test_echo"] = JobSpec(
    id="_test_echo", label="Test echo", description="", confirm=False, consequence=None,
    build_steps=lambda t, b: [echo_step("hello from the live app")],
)
jobs_module.JOB_SPECS["_test_slow"] = JobSpec(
    id="_test_slow", label="Test slow", description="", confirm=True, consequence="slow on purpose",
    build_steps=lambda t, b: [Step(
        label="sleep", argv=[sys.executable, "-c", "import time; time.sleep(1.5); print('done')"],
        display_argv=[sys.executable, "-c", "..."],
    )],
)

PORT = 8799
app = app_module.create_app()
from ia_agent.vars import TOKEN_PATH  # noqa: E402

token = TOKEN_PATH.read_text().strip()
headers = {"Authorization": f"Bearer {token}"}
server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=PORT, log_level="error"))
threading.Thread(target=server.run, daemon=True).start()


async def live_checks() -> None:
    async with httpx.AsyncClient(base_url=f"http://127.0.0.1:{PORT}", headers=headers) as client:
        for _ in range(50):
            try:
                await client.get("/api/health")
                break
            except httpx.HTTPError:
                await asyncio.sleep(0.2)

        print("\n13. GET /api/ops/specs lists the real registry, including the test-only entries")
        specs = (await client.get("/api/ops/specs")).json()
        check("_test_echo is present", any(s["id"] == "_test_echo" for s in specs), str([s["id"] for s in specs]))

        print("\n14. GET /api/ops/jobs starts empty")
        listed = (await client.get("/api/ops/jobs")).json()
        check("no jobs yet", listed == [], str(listed))

        print("\n15. a paired device cannot POST /api/ops/jobs — desktop-only, same precedent as pair.py's D51")
        started = (await client.post("/api/pair/start", headers=headers)).json()
        claimed = await client.post("/api/pair/claim", json={"code": started["code"], "device_name": "test phone"})
        device_token = claimed.json()["token"]
        device_headers = {"Authorization": f"Bearer {device_token}"}
        denied = await client.post("/api/ops/jobs", json={"kind": "_test_echo"}, headers=device_headers)
        check("device token gets 401 on POST", denied.status_code == 401, str(denied.status_code))
        allowed_read = await client.get("/api/ops/jobs", headers=device_headers)
        check("device token can still read job history", allowed_read.status_code == 200)

        print("\n16. POST /api/ops/jobs starts a real job and streams its output over WS")
        async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws?token={token}") as ws:
            posted = await client.post("/api/ops/jobs", json={"kind": "_test_echo"})
            check("200 with a running job", posted.status_code == 200 and posted.json()["status"] == "running", posted.text)
            job_id = posted.json()["id"]

            saw_status, saw_log = False, False
            deadline = asyncio.get_running_loop().time() + 5
            while asyncio.get_running_loop().time() < deadline and not (saw_status and saw_log):
                try:
                    frame = json.loads(await asyncio.wait_for(ws.recv(), timeout=1))
                except asyncio.TimeoutError:
                    continue
                if frame.get("channel") == "ops.jobs":
                    saw_status = True
                if frame.get("channel") == f"ops.logs.{job_id}":
                    saw_log = True
            check("ops.jobs status frame arrived", saw_status)
            check("ops.logs.{id} frame arrived", saw_log)

        for _ in range(50):
            if (await client.get(f"/api/ops/jobs/{job_id}")).json()["status"] != "running":
                break
            await asyncio.sleep(0.1)
        finished = (await client.get(f"/api/ops/jobs/{job_id}")).json()
        check("job succeeded", finished["status"] == "succeeded" and finished["exit_code"] == 0, str(finished))

        print("\n17. GET /api/ops/jobs/{id}/logs?since= replays only what's new")
        full = (await client.get(f"/api/ops/jobs/{job_id}/logs")).json()["entries"]
        check("the echoed line is present", any(e["text"] == "hello from the live app" for e in full), str(full))
        partial = (await client.get(f"/api/ops/jobs/{job_id}/logs", params={"since": full[0]["seq"]})).json()["entries"]
        check("since= excludes the first entry", all(e["seq"] > full[0]["seq"] for e in partial), str(partial))

        print("\n18. an unknown job id is a 404, an unknown kind is a 404, a concurrent start is a 409")
        check("unknown job 404", (await client.get("/api/ops/jobs/does-not-exist")).status_code == 404)
        check("unknown kind 404", (await client.post("/api/ops/jobs", json={"kind": "does-not-exist"})).status_code == 404)
        await client.post("/api/ops/jobs", json={"kind": "_test_slow"})
        conflict = await client.post("/api/ops/jobs", json={"kind": "_test_echo"})
        check("starting while one runs is a 409", conflict.status_code == 409, str(conflict.status_code))


async def main() -> int:
    await live_checks()
    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    shutil.rmtree(SCRATCH, ignore_errors=True)
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
