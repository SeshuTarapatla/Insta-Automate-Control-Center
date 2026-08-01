import asyncio

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from ia_agent import images

MIN_WIDTH = 16
MAX_WIDTH = 2000


def create_images_router() -> APIRouter:
    router = APIRouter(prefix="/api/images")

    @router.get("/{key}")
    async def get_image(key: str) -> FileResponse:
        path = images.original(key)
        if path is None:
            raise HTTPException(status_code=404, detail=f"unknown image: {key}")
        return FileResponse(path, media_type="image/jpeg")

    @router.get("/{key}/thumb")
    async def get_thumbnail(key: str, w: int = 320) -> FileResponse:
        width = max(MIN_WIDTH, min(w, MAX_WIDTH))
        path = await asyncio.to_thread(images.thumbnail, key, width)
        if path is None:
            raise HTTPException(status_code=404, detail=f"unknown image: {key}")
        return FileResponse(path, media_type="image/jpeg")

    return router
