import secrets

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from ia_agent.logging import logger
from ia_agent.pairing import PairingStore
from ia_agent.vars import AGENT_DATA_DIR, TOKEN_PATH

# The phone claiming a pairing code has, by definition, no token yet — the
# code itself (short TTL, single-use, see pairing.py) is its only proof of
# proximity, so this one endpoint is reachable with no bearer at all (§7).
UNAUTHENTICATED_PATHS = {"/api/pair/claim"}


def load_or_create_token() -> str:
    """Same-machine trust: the Flutter app reads this file directly (see
    ARCHITECTURE.md §3.3), so the token only needs to survive on disk, not be memorable."""
    if TOKEN_PATH.exists():
        token = TOKEN_PATH.read_text().strip()
        if token:
            return token

    AGENT_DATA_DIR.mkdir(parents=True, exist_ok=True)
    token = secrets.token_urlsafe(32)
    TOKEN_PATH.write_text(token)
    logger.info(f"generated new desktop token at {TOKEN_PATH}")
    return token


def is_authorized(credential: str, token: str, pairing_store: PairingStore) -> bool:
    """The desktop/service token (today, one and the same — see CLAUDE.md's
    D26 note) or any currently-paired, non-revoked device token (§3.3's
    three token classes)."""
    return secrets.compare_digest(credential, token) or pairing_store.authenticate(credential) is not None


class BearerAuthMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, token: str, pairing_store: PairingStore):
        super().__init__(app)
        self._token = token
        self._pairing_store = pairing_store

    async def dispatch(self, request: Request, call_next):
        if request.url.path in UNAUTHENTICATED_PATHS:
            return await call_next(request)
        scheme, _, credential = request.headers.get("authorization", "").partition(" ")
        if scheme.lower() != "bearer" or not is_authorized(credential, self._token, self._pairing_store):
            return JSONResponse({"detail": "unauthorized"}, status_code=401)
        return await call_next(request)
