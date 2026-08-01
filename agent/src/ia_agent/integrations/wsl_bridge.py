"""Read/control access to wsl-bridge's scrcpy control plane (CP 4.5).
wsl-bridge itself is not modified — ARCHITECTURE §8."""
import httpx

BASE_URL = "http://127.0.0.1:8000"


async def bridge_healthy() -> bool:
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=5) as client:
        response = await client.get("/")
        return response.json() is True


async def scrcpy_status() -> bool:
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=5) as client:
        response = await client.get("/scrcpy/")
        return response.json() is True


async def scrcpy_start(serial: str) -> dict:
    """`POST /scrcpy/start` calls `stop()` on the way in (wsl_bridge's own
    scrcpy.py) — cycling an already-running mirror throws a new window on
    screen, so the caller should check `scrcpy_status()` first if that
    matters (the REST layer here does)."""
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=15) as client:
        response = await client.post("/scrcpy/start", params={"serial": serial})
        response.raise_for_status()
        return response.json()


async def scrcpy_stop() -> None:
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=10) as client:
        await client.post("/scrcpy/stop")
