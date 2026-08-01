import asyncio
from pathlib import Path

from watchfiles import awatch

from ia_agent.events.bus import EventBus
from ia_agent.library import folders
from ia_agent.library.counts import LibraryCounts
from ia_agent.logging import logger


async def watch_library(bus: EventBus, counts: LibraryCounts) -> None:
    """Recomputes and broadcasts exactly the `(folder, root)` pairs a batch of
    filesystem changes touched. Unlike `config/watcher.py`'s deliberately
    non-recursive watch of `IA_DIR`'s top level, this one watches the seven
    known stage directories recursively — that churn is exactly what the
    Library screen needs to reflect — but by passing those seven paths
    explicitly rather than `IA_DIR` itself, `.thumbs`/`.Trash-0`/`config.env`
    changes never wake it."""
    paths = []
    for folder in folders.FOLDERS.values():
        folder.path.mkdir(parents=True, exist_ok=True)
        paths.append(str(folder.path))

    async for changes in awatch(*paths):
        touched: set[tuple[str, str | None]] = set()
        for _change, raw_path in changes:
            resolved = folders.resolve(Path(raw_path))
            if resolved is not None:
                touched.add(resolved)
        if not touched:
            continue
        results = await asyncio.gather(
            *(asyncio.to_thread(counts.touch, folder_name, root) for folder_name, root in touched)
        )
        logger.debug(f"library changed: {results}")
        await bus.publish("library.changes", {"changes": results})
