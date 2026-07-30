import secrets

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from ia_agent.logging import logger
from ia_agent.vars import AGENT_DATA_DIR, TOKEN_PATH


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


class BearerAuthMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, token: str):
        super().__init__(app)
        self._token = token

    async def dispatch(self, request: Request, call_next):
        scheme, _, credential = request.headers.get("authorization", "").partition(" ")
        if scheme.lower() != "bearer" or credential != self._token:
            return JSONResponse({"detail": "unauthorized"}, status_code=401)
        return await call_next(request)
