from watchfiles import Change, awatch

from ia_agent.config import env_file
from ia_agent.events.bus import EventBus
from ia_agent.logging import logger
from ia_agent.vars import CONFIG_PATH, IA_DIR


def _is_config_change(change: Change, path: str) -> bool:
    return path == str(CONFIG_PATH)


async def watch_config(bus: EventBus) -> None:
    """Broadcasts config.env's parsed contents on config.changed whenever the file
    changes on disk — external edits from Syncthing, the mobile app, or a manual
    edit, not just writes made through this agent. IA_DIR holds thousands of
    scan/scrape images churning constantly, so watch only its top level
    (non-recursive) rather than the whole tree."""
    async for _changes in awatch(IA_DIR, watch_filter=_is_config_change, recursive=False):
        data = env_file.load(CONFIG_PATH)
        if data is None:
            continue
        logger.info("config.env changed on disk")
        await bus.publish(
            "config.changed",
            {"switches": data.switches, "entity_queue": data.entity_queue, "limits": data.limits},
        )
