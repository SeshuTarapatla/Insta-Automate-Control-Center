from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ia_agent.config import env_file
from ia_agent.vars import CONFIG_PATH, ENTITY_DIR, FOLLOW_QUEUE_DIR, SCRAPE_QUEUE_DIR

router = APIRouter(prefix="/api")


def _clean_name(name: str) -> str:
    """Entity names become directory/file-name components (`entities/<name>.jpg`,
    `scrape_queued/<name>/...`), so no path separators — mirrors the pipeline's
    own `Queue.add()`/`Queue.remove()`, which trust `ENTITY_QUEUE` entries to
    already be bare names."""
    name = name.strip()
    if not name or "/" in name or "\\" in name or name in (".", ".."):
        raise HTTPException(status_code=422, detail=f"not a valid entity name: {name!r}")
    return name


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


class QueueAddRequest(BaseModel):
    name: str


class QueueRemoveRequest(BaseModel):
    name: str
    force: bool = False


class QueueReorderRequest(BaseModel):
    order: list[str]


@router.post("/queue/add")
async def add_to_queue(body: QueueAddRequest) -> dict:
    """Mirrors `Queue.add()`: refuses an entity with no `entities/<id>.jpg` (D8) —
    the pipeline would reject it too, silently, so the UI should hear about it now."""
    name = _clean_name(body.name)
    async with env_file.WRITE_LOCK:
        data = env_file.load(CONFIG_PATH)
        if data is None:
            raise HTTPException(status_code=404, detail="config.env not found")
        if not (ENTITY_DIR / f"{name}.jpg").exists():
            raise HTTPException(status_code=422, detail=f"no entities/{name}.jpg — add the entity first")
        if name in data.entity_queue:
            raise HTTPException(status_code=409, detail=f"{name} is already queued")
        env_file.save(CONFIG_PATH, data, entity_queue=[*data.entity_queue, name])
    return await get_queue()


@router.post("/queue/remove")
async def remove_from_queue(body: QueueRemoveRequest) -> dict:
    """Mirrors `Queue.remove()`'s default `check=True`: an entity with jpegs still
    waiting in either stage directory stays queued unless `force` overrides it —
    dropping it from the priority list wouldn't stop the pipeline from working
    through its backlog, just from doing so first."""
    name = _clean_name(body.name)
    async with env_file.WRITE_LOCK:
        data = env_file.load(CONFIG_PATH)
        if data is None:
            raise HTTPException(status_code=404, detail="config.env not found")
        if name not in data.entity_queue:
            raise HTTPException(status_code=404, detail=f"{name} is not queued")
        if not body.force:
            pending = _jpeg_count(SCRAPE_QUEUE_DIR / name) + _jpeg_count(FOLLOW_QUEUE_DIR / name)
            if pending:
                raise HTTPException(
                    status_code=409,
                    detail=f"{name} still has {pending} queued image(s) — pass force to remove anyway",
                )
        env_file.save(CONFIG_PATH, data, entity_queue=[n for n in data.entity_queue if n != name])
    return await get_queue()


@router.post("/queue/reorder")
async def reorder_queue(body: QueueReorderRequest) -> dict:
    """Replaces the queued ordering wholesale — `order` must be exactly a
    permutation of the currently queued names, since a partial or foreign list
    would silently drop or fabricate queue membership rather than reorder it."""
    async with env_file.WRITE_LOCK:
        data = env_file.load(CONFIG_PATH)
        if data is None:
            raise HTTPException(status_code=404, detail="config.env not found")
        if sorted(body.order) != sorted(data.entity_queue):
            raise HTTPException(
                status_code=422,
                detail="order must be exactly a permutation of the currently queued entities",
            )
        env_file.save(CONFIG_PATH, data, entity_queue=body.order)
    return await get_queue()
