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
