import asyncio

from fastapi import APIRouter, HTTPException

from ia_agent import window
from ia_agent.integrations import wsl_bridge
from ia_agent.vars import ANDROID_SERIAL

# The window doesn't exist the instant the process does - give it a moment
# to actually appear before giving up on the snap. Best-effort: a start that
# succeeds but never gets snapped is still a successful start.
_SNAP_ATTEMPTS = 20
_SNAP_INTERVAL = 0.25


def create_device_router() -> APIRouter:
    router = APIRouter(prefix="/api/device")

    @router.get("")
    async def get_device() -> dict:
        try:
            bridge_reachable = await wsl_bridge.bridge_healthy()
        except Exception:
            bridge_reachable = False
        mirroring = False
        if bridge_reachable:
            try:
                mirroring = await wsl_bridge.scrcpy_status()
            except Exception:
                mirroring = False
        return {
            "serial": ANDROID_SERIAL or None,
            "bridge_reachable": bridge_reachable,
            "mirroring": mirroring,
        }

    @router.post("/scrcpy/start")
    async def start_scrcpy() -> dict:
        if not ANDROID_SERIAL:
            raise HTTPException(status_code=409, detail="ANDROID_SERIAL is not set")
        try:
            if await wsl_bridge.scrcpy_status():
                # start() calls stop() on the way in - cycling an existing
                # mirror would throw a new window on screen for no reason.
                return {"status": "already mirroring", "pid": None, "snapped": False}
            result = await wsl_bridge.scrcpy_start(ANDROID_SERIAL)
        except Exception as error:
            raise HTTPException(status_code=502, detail=f"wsl-bridge call failed: {error}")

        pid = result.get("pid")
        snapped = False
        if pid:
            for _ in range(_SNAP_ATTEMPTS):
                await asyncio.sleep(_SNAP_INTERVAL)
                snapped = await asyncio.to_thread(window.snap_to_known_position, pid)
                if snapped:
                    break
        return {**result, "snapped": snapped}

    @router.post("/scrcpy/stop")
    async def stop_scrcpy() -> dict:
        try:
            await wsl_bridge.scrcpy_stop()
        except Exception as error:
            raise HTTPException(status_code=502, detail=f"wsl-bridge call failed: {error}")
        return {"status": "stopped"}

    return router
