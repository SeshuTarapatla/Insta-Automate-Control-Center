"""Content-addressed image cache for flow events (CP 4.2, ARCHITECTURE §5).

`entity_classify` unlinks public profiles and `entity_follow` unlinks right
after acting, so a `FlowEvent`'s `image` path can be gone by the time
anything downstream would read it — the cache exists to read the bytes once,
at event-arrival time, before that race is lost. Keyed by the sha256 of the
bytes rather than the source path: two events pointing at files with
identical content (a duplicate scan hit, say) share one cached copy, and the
key stays valid forever even though the source path does not.
"""
import hashlib
import threading
from pathlib import Path

from PIL import Image

from ia_agent.vars import IA_DIR, IMAGE_CACHE_DIR

_lock = threading.Lock()


def _original_path(key: str) -> Path:
    return IMAGE_CACHE_DIR / f"{key}.jpg"


def _thumb_path(key: str, width: int) -> Path:
    return IMAGE_CACHE_DIR / "thumbs" / f"{key}_{width}.jpg"


def cache(rel_path: str) -> str | None:
    """Reads `IA_DIR/rel_path` and stores it under its content hash. Returns
    `None` if the file is already gone — a race the caller should treat as
    normal (a slow event delivery, or a caller that just lost the race), not
    as an error worth raising over."""
    try:
        data = (IA_DIR / rel_path).read_bytes()
    except OSError:
        return None
    key = hashlib.sha256(data).hexdigest()
    with _lock:
        target = _original_path(key)
        if not target.exists():
            IMAGE_CACHE_DIR.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    return key


def original(key: str) -> Path | None:
    path = _original_path(key)
    return path if path.exists() else None


def thumbnail(key: str, width: int) -> Path | None:
    """Generated lazily on first request for a given width and cached
    alongside the original — most keys are never viewed at every width the UI
    might ask for, so there is no reason to pre-render one."""
    source = original(key)
    if source is None:
        return None
    thumb_path = _thumb_path(key, width)
    with _lock:
        if thumb_path.exists():
            return thumb_path
        thumb_path.parent.mkdir(parents=True, exist_ok=True)
        with Image.open(source) as img:
            img = img.convert("RGB")
            height = max(1, round(img.height * (width / img.width)))
            img.resize((width, height), Image.LANCZOS).save(thumb_path, "JPEG", quality=85)
    return thumb_path
