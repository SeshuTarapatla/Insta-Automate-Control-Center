import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI

from ia_agent.api.config import router as config_router
from ia_agent.api.dependencies import router as dependencies_router
from ia_agent.api.events import create_events_router
from ia_agent.api.flowruns import create_flowruns_router
from ia_agent.api.health import router as health_router
from ia_agent.api.images import create_images_router
from ia_agent.api.queue import router as queue_router
from ia_agent.api.scheduler import create_scheduler_router
from ia_agent.api.services import create_services_router
from ia_agent.api.ws import create_ws_router
from ia_agent.auth import BearerAuthMiddleware, load_or_create_token
from ia_agent.config.watcher import watch_config
from ia_agent.events.bus import EventBus
from ia_agent.events.store import EventStore
from ia_agent.flowruns import FlowRunTailer
from ia_agent.logging import logger
from ia_agent.scheduler import SchedulerMirror
from ia_agent.services.registry import build_specs
from ia_agent.services.supervisor import Supervisor


def create_app() -> FastAPI:
    token = load_or_create_token()
    bus = EventBus()
    supervisor = Supervisor(build_specs(), bus)
    scheduler_mirror = SchedulerMirror(bus)
    flowrun_tailer = FlowRunTailer(bus, scheduler_mirror)
    event_store = EventStore(bus)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        watcher_task = asyncio.create_task(watch_config(bus))
        await supervisor.start()
        await scheduler_mirror.start()
        await flowrun_tailer.start()
        yield
        await flowrun_tailer.shutdown()
        await scheduler_mirror.shutdown()
        await supervisor.shutdown()
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
    app.include_router(config_router)
    app.include_router(queue_router)
    app.include_router(dependencies_router)
    app.include_router(create_services_router(supervisor))
    app.include_router(create_scheduler_router(scheduler_mirror))
    app.include_router(create_flowruns_router(flowrun_tailer))
    app.include_router(create_events_router(event_store))
    app.include_router(create_images_router())
    app.include_router(create_ws_router(bus, token))
    return app
