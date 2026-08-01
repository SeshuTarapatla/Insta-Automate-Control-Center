"""Read-only Prefect REST access. Talks to the API over httpx rather than importing
the `prefect` package — the agent only needs a handful of endpoints, and the client
library would drag in its own settings, logging and version coupling."""
import httpx

BASE_URL = "http://localhost:4200/api"
WORK_POOL = "insta-automate-pool"


async def health() -> bool:
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=5) as client:
        response = await client.get("/health")
        return response.status_code == 200 and response.json() is True


async def version() -> str | None:
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=5) as client:
        response = await client.get("/admin/version")
        if response.status_code != 200:
            return None
        return response.json()


async def work_pool(name: str = WORK_POOL) -> dict | None:
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=5) as client:
        response = await client.get(f"/work_pools/{name}")
        if response.status_code == 404:
            return None
        response.raise_for_status()
        return response.json()


async def workers(name: str = WORK_POOL) -> list[dict]:
    """A work pool that exists and is unpaused still runs nothing if no worker is
    polling it — which is the failure this check exists to catch."""
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=5) as client:
        response = await client.post(f"/work_pools/{name}/workers/filter", json={})
        if response.status_code != 200:
            return []
        return response.json()


async def deployment_id(flow: str, deployment: str | None = None) -> str | None:
    """Resolve a `<flow>/<deployment>` name to its id — the fallback discovery
    path (CP 4.1) needs ids, since `flow_runs/filter` cannot filter by name."""
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=5) as client:
        response = await client.get(f"/deployments/name/{flow}/{deployment or flow}")
        if response.status_code == 404:
            return None
        response.raise_for_status()
        return response.json()["id"]


async def flow_run(flow_run_id: str) -> dict | None:
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=5) as client:
        response = await client.get(f"/flow_runs/{flow_run_id}")
        if response.status_code == 404:
            return None
        response.raise_for_status()
        return response.json()


async def flow_runs_filter(
    deployment_ids: list[str] | None = None,
    state_types: list[str] | None = None,
    limit: int = 10,
) -> list[dict]:
    """Fallback active-run discovery (CP 4.1, ARCHITECTURE §5.2) for when the
    scheduler mirror has nothing — offline, or a heartbeat hasn't landed yet
    since a phase flipped to `running`."""
    body: dict = {"sort": "START_TIME_DESC", "limit": limit}
    flow_runs: dict = {}
    if deployment_ids:
        flow_runs["deployment_id"] = {"any_": deployment_ids}
    if state_types:
        flow_runs["state"] = {"type": {"any_": state_types}}
    if flow_runs:
        body["flow_runs"] = flow_runs
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=5) as client:
        response = await client.post("/flow_runs/filter", json=body)
        response.raise_for_status()
        return response.json()


async def run_logs(flow_run_id: str, after: str | None = None, limit: int = 500) -> list[dict]:
    """Every log row for one flow run, ascending by timestamp. `after` is the
    Prefect log `timestamp` (RFC3339) of the last row already consumed —
    `after_` is strict-greater-than, so the caller dedupes at the boundary by
    `id` rather than trusting no timestamp ever repeats (two rows in the same
    tick can share a timestamp)."""
    logs: dict = {"flow_run_id": {"any_": [flow_run_id]}}
    if after:
        logs["timestamp"] = {"after_": after}
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=5) as client:
        response = await client.post(
            "/logs/filter", json={"logs": logs, "sort": "TIMESTAMP_ASC", "limit": limit}
        )
        response.raise_for_status()
        return response.json()


async def task_run_name(task_run_id: str) -> str | None:
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=5) as client:
        response = await client.get(f"/task_runs/{task_run_id}")
        if response.status_code != 200:
            return None
        return response.json().get("name")
