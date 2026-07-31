from pathlib import Path

from fastapi import APIRouter, HTTPException

from ia_agent.config import env_file
from ia_agent.vars import CONFIG_PATH, ENTITY_DIR, FOLLOW_QUEUE_DIR, SCRAPE_QUEUE_DIR

router = APIRouter(prefix="/api")


def _jpeg_count(directory: Path) -> int:
    if not directory.is_dir():
        return 0
    return sum(1 for _ in directory.glob("*.jpg"))


def _sort_key(name: str) -> float:
    """Mirrors Queue.Order.DATE in insta_automate.controllers.queue: prefer the
    entity page image's mtime, fall back to the stage folder's own."""
    entity_image = ENTITY_DIR / f"{name}.jpg"
    if entity_image.exists():
        return entity_image.lstat().st_mtime

    for directory in (SCRAPE_QUEUE_DIR, FOLLOW_QUEUE_DIR):
        folder = directory / name
        if folder.is_dir():
            return folder.lstat().st_mtime
    return 0.0


@router.get("/queue")
async def get_queue() -> dict:
    """The single ENTITY_QUEUE priority list (D8), resolved against both stage
    directories so the UI can show what each queued entity actually has waiting.

    Entities not named in ENTITY_QUEUE still run — the flows process them after
    the listed ones, oldest first — so they are returned too, in that same order.
    """
    data = env_file.load(CONFIG_PATH)
    if data is None:
        raise HTTPException(status_code=404, detail="config.env not found")

    present: set[str] = set()
    for directory in (SCRAPE_QUEUE_DIR, FOLLOW_QUEUE_DIR):
        if directory.is_dir():
            present.update(folder.name for folder in directory.iterdir() if folder.is_dir())

    queued = data.entity_queue
    unqueued = sorted(present - set(queued), key=_sort_key)

    def entry(name: str, is_queued: bool) -> dict:
        return {
            "name": name,
            "queued": is_queued,
            "scrape_count": _jpeg_count(SCRAPE_QUEUE_DIR / name),
            "follow_count": _jpeg_count(FOLLOW_QUEUE_DIR / name),
            # Queue.add() refuses an entity with no entities/<id>.jpg, so the UI
            # can grey out anything that would be rejected by the pipeline.
            "has_entity_image": (ENTITY_DIR / f"{name}.jpg").exists(),
        }

    return {
        "queued": [entry(name, True) for name in queued],
        "unqueued": [entry(name, False) for name in unqueued],
    }
