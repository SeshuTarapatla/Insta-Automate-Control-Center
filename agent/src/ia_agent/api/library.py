import asyncio
import os

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

from ia_agent import images
from ia_agent.library import entity_view, folders, ops, settings
from ia_agent.library.counts import LibraryCounts

MIN_WIDTH = 16
MAX_WIDTH = 2000
MAX_LIMIT = 500


class ApplyRequest(BaseModel):
    folder: str
    entity: str | None = None
    selected: list[str]


class DeleteRequest(BaseModel):
    paths: list[str]


class MoveRequest(BaseModel):
    moves: list[dict[str, str]]


class MoveTargetRequest(BaseModel):
    target: str


def _folder_or_404(name: str) -> folders.LibraryFolder:
    folder = folders.FOLDERS.get(name)
    if folder is None:
        raise HTTPException(status_code=404, detail=f"unknown folder: {name}")
    return folder


def _rel_path_or_400(path: str) -> str:
    """`path` must resolve to somewhere inside one of the seven known library
    folders — the same guard `folders.resolve()` gives the watcher, reused
    here against path traversal (`../../config.env` and friends)."""
    if folders.resolve(folders.IA_DIR / path) is None:
        raise HTTPException(status_code=400, detail=f"not a library path: {path}")
    return path


def create_library_router(counts: LibraryCounts) -> APIRouter:
    router = APIRouter(prefix="/api/library")

    @router.get("/folders")
    async def get_folders() -> list[dict]:
        return counts.folders()

    @router.get("/entities")
    async def get_entities(folder: str) -> list[dict]:
        target = _folder_or_404(folder)
        if target.flat:
            raise HTTPException(status_code=400, detail=f"{folder} has no entities to drill into")
        return counts.entities(folder)

    @router.get("/images")
    async def get_images(folder: str, entity: str | None = None, offset: int = 0, limit: int = 100) -> dict:
        target = _folder_or_404(folder)
        if target.flat:
            directory = target.path
        else:
            if not entity:
                raise HTTPException(status_code=400, detail=f"{folder} requires an entity")
            directory = target.path / entity

        def scan() -> list[str]:
            try:
                with os.scandir(directory) as entries:
                    return sorted(entry.name for entry in entries if entry.is_file())
            except OSError:
                return []

        names = await asyncio.to_thread(scan)
        offset = max(0, offset)
        limit = max(1, min(limit, MAX_LIMIT))
        page = names[offset : offset + limit]
        rel_dir = directory.relative_to(folders.IA_DIR).as_posix()
        return {
            "total": len(names),
            "offset": offset,
            "images": [{"name": name, "path": f"{rel_dir}/{name}"} for name in page],
        }

    @router.get("/image")
    async def get_image(path: str) -> FileResponse:
        rel = _rel_path_or_400(path)
        key = await asyncio.to_thread(images.cache, rel)
        if key is None:
            raise HTTPException(status_code=404, detail=f"not found: {path}")
        original = images.original(key)
        return FileResponse(original, media_type="image/jpeg")

    @router.get("/image/thumb")
    async def get_image_thumb(path: str, w: int = 320) -> FileResponse:
        rel = _rel_path_or_400(path)
        key = await asyncio.to_thread(images.cache, rel)
        if key is None:
            raise HTTPException(status_code=404, detail=f"not found: {path}")
        width = max(MIN_WIDTH, min(w, MAX_WIDTH))
        thumb = await asyncio.to_thread(images.thumbnail, key, width)
        if thumb is None:
            raise HTTPException(status_code=404, detail=f"not found: {path}")
        return FileResponse(thumb, media_type="image/jpeg")

    @router.get("/entity/{root}/yield")
    async def get_entity_yield(root: str) -> dict:
        """CP 5.4 — one entity's funnel across every stage. 404 when `root`
        isn't a known `Entity.id`, same as any other not-found path here."""
        result = await asyncio.to_thread(entity_view.fetch, root)
        if result is None:
            raise HTTPException(status_code=404, detail=f"unknown entity: {root}")
        return result

    @router.get("/move-targets")
    async def get_move_targets() -> dict:
        return settings.load()

    @router.patch("/move-targets/{folder}")
    async def set_move_target(folder: str, body: MoveTargetRequest) -> dict:
        try:
            return await asyncio.to_thread(settings.set_move_target, folder, body.target)
        except KeyError as error:
            raise HTTPException(status_code=404, detail=str(error))

    @router.post("/apply")
    async def apply_library(body: ApplyRequest) -> dict:
        try:
            return await asyncio.to_thread(ops.apply, body.folder, body.entity, body.selected)
        except ops.LibraryOpError as error:
            raise HTTPException(status_code=400, detail=str(error))

    @router.post("/move")
    async def move_library(body: MoveRequest) -> dict:
        return await asyncio.to_thread(ops.move, body.moves)

    @router.post("/delete")
    async def delete_library(body: DeleteRequest) -> dict:
        return await asyncio.to_thread(ops.delete, body.paths)

    return router
