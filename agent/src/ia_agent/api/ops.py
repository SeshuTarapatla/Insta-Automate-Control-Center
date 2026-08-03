import secrets

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ia_agent.ops.jobs import OpsError, OpsJobStore


class StartJob(BaseModel):
    kind: str


def create_ops_router(store: OpsJobStore, desktop_token: str) -> APIRouter:
    router = APIRouter(prefix="/api/ops")

    def _require_desktop(request: Request) -> None:
        # Same reasoning as pair.py's device-management routes (D51): these
        # jobs can uninstall the live release or restore the database, which
        # is not something a paired phone should be able to trigger.
        scheme, _, credential = request.headers.get("authorization", "").partition(" ")
        if scheme.lower() != "bearer" or not secrets.compare_digest(credential, desktop_token):
            raise HTTPException(status_code=401, detail="desktop token required")

    @router.get("/specs")
    async def list_specs() -> list[dict]:
        return store.specs()

    @router.get("/jobs")
    async def list_jobs(limit: int = 50) -> list[dict]:
        return store.list_jobs(limit)

    @router.get("/jobs/{job_id}")
    async def get_job(job_id: str) -> dict:
        job = store.get_job(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"unknown job: {job_id}")
        return job

    @router.get("/jobs/{job_id}/logs")
    async def get_logs(job_id: str, since: int | None = None) -> dict:
        if store.get_job(job_id) is None:
            raise HTTPException(status_code=404, detail=f"unknown job: {job_id}")
        return {"job_id": job_id, "entries": store.get_logs(job_id, since)}

    @router.post("/jobs")
    async def start_job(body: StartJob, request: Request) -> dict:
        _require_desktop(request)
        try:
            return await store.start(body.kind)
        except OpsError as error:
            status = 404 if "unknown job" in str(error) else 409
            raise HTTPException(status_code=status, detail=str(error))

    return router
