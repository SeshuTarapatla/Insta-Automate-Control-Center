import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI

from ia_agent.api.health import router as health_router
from ia_agent.api.ws import create_ws_router
from ia_agent.auth import BearerAuthMiddleware, load_or_create_token
from ia_agent.config.watcher import watch_config
from ia_agent.events.bus import EventBus
from ia_agent.logging import logger


def create_app() -> FastAPI:
    token = load_or_create_token()
    bus = EventBus()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        watcher_task = asyncio.create_task(watch_config(bus))
        yield
        watcher_task.cancel()
        try:
            await watcher_task
        except asyncio.CancelledError:
            pass
        except Exception:
            logger.exception("config watcher failed")

    app = FastAPI(title="ia-agent", lifespan=lifespan)
    app.add_middleware(BearerAuthMiddleware, token=token)
    app.include_router(health_router)
    app.include_router(create_ws_router(bus, token))
    return app
