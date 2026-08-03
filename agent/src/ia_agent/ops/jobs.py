"""One-shot ops jobs (PLAN CP 7.1) — build/deploy/backup/restore/helm/kubectl
actions run as real subprocesses with streamed output, replacing the manual
shell commands DECISIONS.md's D38/D55/D59/D68 show have repeatedly gone wrong
(forgotten `GIT_BRANCH`, a worker restart that silently orphans the work pool).

Unlike `services/host.py`'s ConPTY-backed long-lived terminal — built for an
interactive, resizable, indefinitely-running process, adopted across an agent
restart — an ops job is a one-shot command with a start and an end. Plain
pipe capture via `asyncio.create_subprocess_exec` is the right level of
complexity here: no detached host process, no pty, no separate reader thread
(nothing here blocks the event loop, so everything just runs as a task).
"""
import asyncio
import json
import os
import shutil
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from ia_agent.events.bus import EventBus
from ia_agent.logging import logger
from ia_agent.vars import (
    HELMCHARTS_DIR,
    IA_OPS_GIT_BRANCH,
    INSTA_AUTOMATE_DIR,
    OPS_JOBS_DIR,
    OPS_JOBS_KEEP,
    PREFECT_K3S_DIR,
)

IA_EXE = INSTA_AUTOMATE_DIR / ".venv" / "Scripts" / "ia.exe"
PREFECT_K3S_EXE = PREFECT_K3S_DIR / ".venv" / "Scripts" / "prefect-k3s.exe"
KUBECTL = shutil.which("kubectl") or "kubectl"
HELM = shutil.which("helm") or "helm"


class OpsError(Exception):
    """Operator errors (unknown job kind, one already running) — surfaced to
    the API as 404/409 rather than 500, matching `ServiceError`'s precedent
    in `services/supervisor.py`."""


@dataclass(frozen=True)
class Step:
    label: str
    argv: list[str]
    display_argv: list[str]  # secrets redacted — the only version ever logged
    cwd: Path | None = None
    env: dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class JobSpec:
    id: str
    label: str
    description: str
    confirm: bool
    consequence: str | None
    build_steps: Callable[[str, str], list[Step]]  # (token, git_branch) -> steps


def _prepend_path(venv_scripts: Path) -> str:
    """Mirrors what activating a venv does to PATH. Needed because some CLIs
    in this dependency graph (`prefect-k3s reset-pool`, confirmed live —
    `FileNotFoundError: [WinError 2]`) shell out to a bare command name
    (`prefect`) that only resolves because it happens to live in the same
    venv Scripts directory as the CLI itself — true in an activated shell,
    not true when this job invokes the exe by its full path directly,
    since the agent's own inherited PATH has no reason to include a
    project-specific venv's Scripts folder."""
    return f"{venv_scripts}{os.pathsep}{os.environ.get('PATH', '')}"


def _ia_step(label: str, *args: str, git_branch: str) -> Step:
    argv = [str(IA_EXE), *args]
    return Step(label=label, argv=argv, display_argv=argv, cwd=INSTA_AUTOMATE_DIR,
                env={"GIT_BRANCH": git_branch, "PATH": _prepend_path(IA_EXE.parent)})


def _prefect_k3s_step(label: str, *args: str) -> Step:
    argv = [str(PREFECT_K3S_EXE), *args]
    return Step(label=label, argv=argv, display_argv=argv, cwd=PREFECT_K3S_DIR,
                env={"PATH": _prepend_path(PREFECT_K3S_EXE.parent)})


def _kubectl_step(label: str, *args: str) -> Step:
    argv = [KUBECTL, *args]
    return Step(label=label, argv=argv, display_argv=argv)


def _helm_upgrade_step(token: str, git_branch: str) -> Step:
    base = [HELM, "upgrade", "--install", "insta-automate", "."]
    real = [*base, "--set", f"agent.token={token}", "--set", f"gitBranch={git_branch}"]
    display = [*base, "--set", "agent.token=***", "--set", f"gitBranch={git_branch}"]
    return Step(label="helm upgrade --install", argv=real, display_argv=display, cwd=HELMCHARTS_DIR)


def _helm_uninstall_step() -> Step:
    argv = [HELM, "uninstall", "insta-automate"]
    return Step(label="helm uninstall", argv=argv, display_argv=argv, cwd=HELMCHARTS_DIR)


JOB_SPECS: dict[str, JobSpec] = {
    "build": JobSpec(
        id="build", label="Build image",
        description="ia build — rebuild the Docker image from the checked-out branch.",
        confirm=False, consequence=None,
        build_steps=lambda token, branch: [_ia_step("ia build", "build", git_branch=branch)],
    ),
    "deploy": JobSpec(
        id="deploy", label="Deploy flows",
        description="ia prefect deploy — register all five flows against the work pool.",
        confirm=False, consequence=None,
        build_steps=lambda token, branch: [
            _ia_step("ia prefect deploy", "prefect", "deploy", git_branch=branch)
        ],
    ),
    "db_backup": JobSpec(
        id="db_backup", label="DB backup",
        description="ia db backup — snapshot Postgres to the Telegram backup channel.",
        confirm=False, consequence=None,
        build_steps=lambda token, branch: [_ia_step("ia db backup", "db", "backup", git_branch=branch)],
    ),
    "db_restore": JobSpec(
        id="db_restore", label="DB restore",
        description="ia db restore — replace Postgres with the last Telegram backup.",
        confirm=True,
        consequence="This replaces the live database with the last Telegram backup. Any data written since that backup is lost.",
        build_steps=lambda token, branch: [_ia_step("ia db restore", "db", "restore", git_branch=branch)],
    ),
    "purge": JobSpec(
        id="purge", label="Purge stale flow runs",
        description="prefect-k3s purge — cancel and delete every non-completed flow run.",
        confirm=True,
        consequence="Every flow run not already Completed is cancelled and deleted. This cannot be undone.",
        build_steps=lambda token, branch: [_prefect_k3s_step("prefect-k3s purge", "purge")],
    ),
    "reset_pool": JobSpec(
        id="reset_pool", label="Reset work pool",
        description="prefect-k3s reset-pool — clear stale worker registrations without touching scheduled runs.",
        confirm=False, consequence=None,
        build_steps=lambda token, branch: [_prefect_k3s_step("prefect-k3s reset-pool", "reset-pool")],
    ),
    "helm_upgrade": JobSpec(
        id="helm_upgrade", label="Helm upgrade",
        description="helm upgrade --install — deploy the chart, reinstalling if the release was removed.",
        confirm=False, consequence=None,
        build_steps=lambda token, branch: [_helm_upgrade_step(token, branch)],
    ),
    "helm_uninstall": JobSpec(
        id="helm_uninstall", label="Helm uninstall",
        description="helm uninstall — removes both pods entirely. This is the last resort D68 needed.",
        confirm=True,
        consequence="Removes the insta-automate Helm release — both pods, gone. Nothing will scrape, follow, or trigger until Helm upgrade is run again.",
        build_steps=lambda token, branch: [_helm_uninstall_step()],
    ),
    "restart_scheduler": JobSpec(
        id="restart_scheduler", label="Restart scheduler",
        description="kubectl rollout restart deployment/insta-automate.",
        confirm=True,
        consequence="Restarts the scheduler pod. All five trigger loops restart; a flow mid-wait loses its countdown until the next tick.",
        build_steps=lambda token, branch: [
            _kubectl_step("kubectl rollout restart", "rollout", "restart", "deployment/insta-automate"),
            _kubectl_step("kubectl rollout status", "rollout", "status", "deployment/insta-automate", "--timeout=180s"),
        ],
    ),
    "restart_worker": JobSpec(
        id="restart_worker", label="Restart worker",
        description="Restart the worker pod, then re-deploy flows — D38's work-pool-orphaning init container makes the second step mandatory, not optional.",
        confirm=True,
        consequence="Restarts the worker pod. Its init container resets the Prefect work pool, so this job automatically re-runs ia prefect deploy afterward to fix that.",
        build_steps=lambda token, branch: [
            _kubectl_step("kubectl rollout restart", "rollout", "restart", "deployment/insta-automate-worker"),
            _kubectl_step("kubectl rollout status", "rollout", "status", "deployment/insta-automate-worker", "--timeout=180s"),
            _ia_step(
                "ia prefect deploy (re-registering after the worker's init container reset the pool)",
                "prefect", "deploy", git_branch=branch,
            ),
        ],
    ),
}


class OpsJobStore:
    """One job at a time — these mutate shared cluster/image state, and
    running two concurrently is exactly the kind of thing that caused
    D38/D55's chaining incidents. History persists to disk (D50's reasoning:
    a destructive action's outcome must survive an agent restart)."""

    def __init__(self, bus: EventBus, token: str) -> None:
        self._bus = bus
        self._token = token
        self._current: dict | None = None
        self._current_ring: list[dict] = []
        self._current_seq = 0
        self._task: asyncio.Task | None = None
        self._history: list[dict] = self._load_history()

    # ------------------------------------------------------------ persistence

    def _job_dir(self, job_id: str) -> Path:
        return OPS_JOBS_DIR / job_id

    def _load_history(self) -> list[dict]:
        if not OPS_JOBS_DIR.exists():
            return []
        metas = []
        for entry in OPS_JOBS_DIR.iterdir():
            if not entry.is_dir():
                continue
            try:
                meta = json.loads((entry / "meta.json").read_text())
            except (OSError, json.JSONDecodeError):
                continue
            if meta.get("status") == "running":
                # The agent restarted mid-job — the subprocess died with it,
                # there is nothing left to resume or wait on.
                meta["status"] = "interrupted"
                meta["ended_at"] = meta.get("started_at")
                self._write_meta(meta)
            metas.append(meta)
        metas.sort(key=lambda m: m["started_at"], reverse=True)
        stale, metas = metas[OPS_JOBS_KEEP:], metas[:OPS_JOBS_KEEP]
        for meta in stale:
            shutil.rmtree(self._job_dir(meta["id"]), ignore_errors=True)
        return metas

    def _write_meta(self, meta: dict) -> None:
        job_dir = self._job_dir(meta["id"])
        job_dir.mkdir(parents=True, exist_ok=True)
        temp = job_dir / "meta.json.tmp"
        temp.write_text(json.dumps(meta, indent=2))
        temp.replace(job_dir / "meta.json")

    def _append_log(self, job_id: str, entry: dict) -> None:
        job_dir = self._job_dir(job_id)
        job_dir.mkdir(parents=True, exist_ok=True)
        with (job_dir / "log.jsonl").open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry) + "\n")

    def _read_log(self, job_id: str, since: int | None) -> list[dict]:
        path = self._job_dir(job_id) / "log.jsonl"
        if not path.exists():
            return []
        entries = []
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue
        if since is not None:
            entries = [e for e in entries if e["seq"] > since]
        return entries

    # ------------------------------------------------------------------- API

    def specs(self) -> list[dict]:
        return [
            {"id": s.id, "label": s.label, "description": s.description,
             "confirm": s.confirm, "consequence": s.consequence}
            for s in JOB_SPECS.values()
        ]

    def list_jobs(self, limit: int = 50) -> list[dict]:
        jobs = ([self._current] if self._current else []) + self._history
        return jobs[:limit]

    def get_job(self, job_id: str) -> dict | None:
        if self._current and self._current["id"] == job_id:
            return self._current
        return next((m for m in self._history if m["id"] == job_id), None)

    def get_logs(self, job_id: str, since: int | None = None) -> list[dict]:
        if self._current and self._current["id"] == job_id:
            if since is None:
                return list(self._current_ring)
            return [e for e in self._current_ring if e["seq"] > since]
        return self._read_log(job_id, since)

    async def start(self, kind: str) -> dict:
        spec = JOB_SPECS.get(kind)
        if spec is None:
            raise OpsError(f"unknown job: {kind}")
        if self._current is not None:
            raise OpsError(f"a job is already running: {self._current['kind']}")

        steps = spec.build_steps(self._token, IA_OPS_GIT_BRANCH)
        job_id = str(uuid.uuid4())
        meta = {
            "id": job_id, "kind": spec.id, "label": spec.label,
            "status": "running", "started_at": time.time(), "ended_at": None,
            "exit_code": None, "current_step": 0, "steps": [s.label for s in steps],
        }
        # No `await` between the running-job check above and this assignment,
        # so nothing else on this single-threaded event loop can interleave —
        # the one-job-at-a-time guarantee needs no separate lock.
        self._current = meta
        self._current_ring = []
        self._current_seq = 0
        self._write_meta(meta)
        await self._publish_status()
        self._task = asyncio.create_task(self._run(job_id, steps))
        return meta

    # ------------------------------------------------------------- execution

    async def _emit(self, job_id: str, kind: str, text: str) -> None:
        self._current_seq += 1
        entry = {"seq": self._current_seq, "ts": time.time(), "kind": kind, "text": text}
        self._current_ring.append(entry)
        self._append_log(job_id, entry)
        await self._bus.publish(f"ops.logs.{job_id}", [entry])

    async def _publish_status(self) -> None:
        await self._bus.publish("ops.jobs", self._current)

    async def _run(self, job_id: str, steps: list[Step]) -> None:
        exit_code = 0
        try:
            for index, step in enumerate(steps):
                self._current["current_step"] = index
                await self._publish_status()
                await self._emit(job_id, "step", f"$ {' '.join(step.display_argv)}")
                process = await asyncio.create_subprocess_exec(
                    *step.argv,
                    cwd=str(step.cwd) if step.cwd else None,
                    env={**os.environ, **step.env},
                    stdin=asyncio.subprocess.DEVNULL,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.STDOUT,
                )
                assert process.stdout is not None
                async for raw_line in process.stdout:
                    line = raw_line.decode(errors="replace").rstrip("\r\n")
                    if line:
                        await self._emit(job_id, "line", line)
                exit_code = await process.wait()
                if exit_code != 0:
                    await self._emit(job_id, "error", f"'{step.label}' exited {exit_code}")
                    break
        except Exception as error:
            logger.exception(f"ops job {job_id} crashed")
            await self._emit(job_id, "error", f"agent error: {error}")
            exit_code = exit_code or 1
        finally:
            self._current["status"] = "succeeded" if exit_code == 0 else "failed"
            self._current["ended_at"] = time.time()
            self._current["exit_code"] = exit_code
            self._write_meta(self._current)
            await self._publish_status()
            self._history.insert(0, self._current)
            dropped, self._history = self._history[OPS_JOBS_KEEP:], self._history[:OPS_JOBS_KEEP]
            for meta in dropped:
                shutil.rmtree(self._job_dir(meta["id"]), ignore_errors=True)
            self._current = None
            self._current_ring = []
            self._task = None
