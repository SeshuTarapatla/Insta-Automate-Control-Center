import secrets
from typing import Any

from fastapi import APIRouter, HTTPException, Request

from ia_agent.pairing import PairingStore


def create_pairing_router(store: PairingStore, desktop_token: str) -> APIRouter:
    router = APIRouter(prefix="/api/pair")

    def _require_desktop(request: Request) -> None:
        """Minting a code, listing paired phones, and revoking one are all
        desktop-console actions — `auth.py`'s bearer check treats desktop and
        device tokens as equally valid everywhere else, but a paired phone
        has no business enumerating or kicking off *other* phones."""
        _, _, credential = request.headers.get("authorization", "").partition(" ")
        if not secrets.compare_digest(credential, desktop_token):
            raise HTTPException(status_code=401, detail="desktop token required")

    @router.post("/start")
    async def start(request: Request) -> dict:
        _require_desktop(request)
        return store.start()

    @router.post("/claim")
    async def claim(payload: dict[str, Any]) -> dict:
        # Reachable with no bearer token at all (auth.py's UNAUTHENTICATED_PATHS)
        # - the code and its TTL are the only proof of proximity here.
        result = store.claim(str(payload.get("code", "")), str(payload.get("device_name", "")))
        if result is None:
            raise HTTPException(status_code=400, detail="invalid or expired code")
        return result

    @router.get("/devices")
    async def devices(request: Request) -> list[dict]:
        _require_desktop(request)
        return store.devices()

    @router.delete("/devices/{device_id}")
    async def revoke(device_id: str, request: Request) -> dict:
        _require_desktop(request)
        if not store.revoke(device_id):
            raise HTTPException(status_code=404, detail="unknown device")
        return {"revoked": device_id}

    return router
