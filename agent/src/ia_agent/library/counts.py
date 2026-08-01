"""Cached per-folder / per-entity file counts (PLAN CP 5.1). `IA_DIR` holds
thousands of files across ~120 entity subdirectories, so nothing here ever
walks the whole tree per request: `seed()` does one `os.scandir` per
top-level folder plus one more per entity root (~120 calls today, not a
per-file stat), and `touch()` — driven by `library/watcher.py` — recomputes
exactly the one `(folder, root)` pair a filesystem change touched.

Recompute-on-touch, not delta-tracking: a watcher batch that coalesces or
drops an event can never leave a count wrong, since the next touch of that
pair reads the real directory again rather than trusting an accumulated
+1/-1. A root that recomputes to 0 files is dropped rather than kept as an
empty tile — an entity that's been fully drained from a stage isn't
interesting to show there any more.
"""
import os
import threading
from pathlib import Path

from ia_agent.library import folders
from ia_agent.library.folders import LibraryFolder


def _count_files(path: Path) -> int:
    try:
        with os.scandir(path) as entries:
            return sum(1 for entry in entries if entry.is_file())
    except OSError:
        return 0


def _count_entities(path: Path) -> dict[str, int]:
    result: dict[str, int] = {}
    try:
        with os.scandir(path) as entries:
            roots = [entry.name for entry in entries if entry.is_dir()]
    except OSError:
        return result
    for root in roots:
        count = _count_files(path / root)
        if count:
            result[root] = count
    return result


class LibraryCounts:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._flat_totals: dict[str, int] = {}
        self._entities: dict[str, dict[str, int]] = {}

    def seed(self) -> None:
        """Blocking — call via `asyncio.to_thread` from startup."""
        for folder in folders.FOLDERS.values():
            if folder.flat:
                total = _count_files(folder.path)
                with self._lock:
                    self._flat_totals[folder.name] = total
            else:
                entities = _count_entities(folder.path)
                with self._lock:
                    self._entities[folder.name] = entities

    def touch(self, folder_name: str, root: str | None) -> dict:
        """Recomputes one `(folder, root)` pair and returns the fresh
        `{folder, root, count}` for the caller to publish."""
        folder = folders.FOLDERS.get(folder_name)
        if folder is None:
            return {"folder": folder_name, "root": root, "count": 0}
        if folder.flat:
            count = _count_files(folder.path)
            with self._lock:
                self._flat_totals[folder.name] = count
            return {"folder": folder.name, "root": None, "count": count}
        if root is None:
            entities = _count_entities(folder.path)
            with self._lock:
                self._entities[folder.name] = entities
            return {"folder": folder.name, "root": None, "count": sum(entities.values())}
        count = _count_files(folder.path / root)
        with self._lock:
            bucket = self._entities.setdefault(folder.name, {})
            if count:
                bucket[root] = count
            else:
                bucket.pop(root, None)
        return {"folder": folder.name, "root": root, "count": count}

    def folders(self) -> list[dict]:
        with self._lock:
            flat_totals = dict(self._flat_totals)
            entities = {name: dict(roots) for name, roots in self._entities.items()}
        result = []
        for folder in folders.FOLDERS.values():
            if folder.flat:
                result.append(
                    {"name": folder.name, "flat": True, "total": flat_totals.get(folder.name, 0), "entities": 0}
                )
            else:
                roots = entities.get(folder.name, {})
                result.append(
                    {
                        "name": folder.name,
                        "flat": False,
                        "total": sum(roots.values()),
                        "entities": len(roots),
                    }
                )
        return result

    def entities(self, folder_name: str) -> list[dict]:
        folder = _require_non_flat(folder_name)
        with self._lock:
            roots = dict(self._entities.get(folder.name, {}))
        return [{"root": root, "count": roots[root]} for root in sorted(roots)]

    def count_for(self, folder_name: str, root: str) -> int:
        """Current file count for one `(folder, root)` pair, 0 if the folder
        is unknown or the root has nothing there — CP 5.4's entity view reads
        this directly rather than through `entities()`'s full-list shape."""
        with self._lock:
            return self._entities.get(folder_name, {}).get(root, 0)


def _require_non_flat(folder_name: str) -> LibraryFolder:
    folder = folders.FOLDERS.get(folder_name)
    if folder is None:
        raise KeyError(f"unknown folder: {folder_name}")
    if folder.flat:
        raise ValueError(f"{folder_name} has no entities to drill into")
    return folder
