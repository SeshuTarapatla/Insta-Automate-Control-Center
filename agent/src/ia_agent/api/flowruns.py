import logging

from fastapi import APIRouter, HTTPException

from ia_agent.flowruns import FlowRunTailer, parse_ts
from ia_agent.integrations import prefect


def _summary(run: dict, flow: str | None, active: bool) -> dict:
    return {
        "id": run["id"],
        "flow": flow,
        "state": run.get("state_type"),
        "start_time": run.get("start_time"),
        "end_time": run.get("end_time"),
        "duration_s": run.get("total_run_time"),
        "active": active,
    }


def create_flowruns_router(tailer: FlowRunTailer) -> APIRouter:
    router = APIRouter(prefix="/api/flow-runs")

    @router.get("")
    async def list_flow_runs(limit: int = 20) -> list[dict]:
        ids = await tailer.deployment_ids()
        if not ids:
            return []
        by_deployment_id = {v: k for k, v in ids.items()}
        runs = await prefect.flow_runs_filter(deployment_ids=list(ids.values()), limit=limit)
        result = []
        for run in runs:
            flow = by_deployment_id.get(run.get("deployment_id"))
            tracked = tailer.run(run["id"])
            result.append(_summary(run, flow, bool(tracked and tracked.active)))
        return result

    @router.get("/{run_id}")
    async def get_flow_run(run_id: str) -> dict:
        info = await prefect.flow_run(run_id)
        if info is None:
            raise HTTPException(status_code=404, detail=f"unknown flow run: {run_id}")
        tracked = tailer.run(run_id)
        flow = tracked.flow if tracked else None
        return _summary(info, flow, bool(tracked and tracked.active))

    @router.get("/{run_id}/logs")
    async def get_flow_run_logs(run_id: str, since: int | None = None) -> dict:
        """Replay from the ring when this run is (or was recently) tailed —
        `live: true` means new entries keep arriving on `flowrun.logs`. A run
        this agent never tailed (predates it, or was never active while this
        agent was up) gets a one-shot fetch straight from Prefect instead:
        real logs, but `live: false` since nothing will poll it further."""
        tracked = tailer.run(run_id)
        if tracked is not None:
            return {
                "flow_run_id": run_id, "flow": tracked.flow,
                "live": True, "entries": tracked.ring.tail(since),
            }
        rows = await prefect.run_logs(run_id)
        if not rows and await prefect.flow_run(run_id) is None:
            raise HTTPException(status_code=404, detail=f"unknown flow run: {run_id}")
        entries = [
            {
                "seq": index + 1, "ts": parse_ts(row["timestamp"]), "source": "flow",
                "level": logging.getLevelName(row.get("level", 20)),
                "task": None, "message": row["message"],
            }
            for index, row in enumerate(rows)
        ]
        return {"flow_run_id": run_id, "flow": None, "live": False, "entries": entries}

    @router.post("/{run_id}/cancel")
    async def cancel_flow_run(run_id: str) -> dict:
        """Stop a run in progress - the only way to do this today short of
        uninstalling the whole release (D69). Not immediate: this sets
        CANCELLING, which Prefect's own cancellation monitoring then
        carries through to actually tearing the run's infrastructure down;
        the scheduler's own trigger loop notices the terminal state on its
        next `wait_for_flow_run` poll same as any other run ending."""
        info = await prefect.flow_run(run_id)
        if info is None:
            raise HTTPException(status_code=404, detail=f"unknown flow run: {run_id}")
        ok = await prefect.cancel_flow_run(run_id)
        if not ok:
            raise HTTPException(status_code=502, detail="prefect refused the cancel request")
        return {"status": "cancelling"}

    return router
