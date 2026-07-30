from fastapi import FastAPI

from ia_agent.api.health import router as health_router
from ia_agent.auth import BearerAuthMiddleware, load_or_create_token


def create_app() -> FastAPI:
    token = load_or_create_token()

    app = FastAPI(title="ia-agent")
    app.add_middleware(BearerAuthMiddleware, token=token)
    app.include_router(health_router)
    return app
