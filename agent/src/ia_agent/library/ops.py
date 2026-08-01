"""Library mutations (PLAN CP 5.2): promote a reviewed batch ("apply") or throw
specific images away outright ("delete"). Both go through `send2trash` for the
half that's discarded — never a hard delete — mirroring the pipeline's own
`insta_automate.utils.move`/`rm_empty_subdirs`, which already uses `send2trash`
for exactly the same "a mistake should be recoverable" reason. Promotions use
`shutil.move`, matching the pipeline's own `utils.move` for the moved half too.

`apply`'s "the rest" is read fresh from disk rather than trusted from the
caller — the same directory `GET /api/library/images` would list right now —
so a stale client-side selection (a file that arrived or left mid-review)
can't send something CP 5.1 never told it about.
"""
from pathlib import Path
from shutil import move as _move

from send2trash import send2trash

from ia_agent.library import folders, settings


class LibraryOpError(Exception):
    pass


def _entity_dir(folder: folders.LibraryFolder, entity: str | None) -> Path:
    if folder.flat:
        if entity is not None:
            raise LibraryOpError(f"{folder.name} has no entities")
        return folder.path
    if not entity:
        raise LibraryOpError(f"{folder.name} requires an entity")
    return folder.path / entity


def _list_files(directory: Path) -> set[str]:
    try:
        return {entry.name for entry in directory.iterdir() if entry.is_file()}
    except OSError:
        return set()


def apply(folder_name: str, entity: str | None, selected: list[str]) -> dict:
    """Moves `selected` (filenames, not paths — they live in the one
    `folder_name`/`entity` directory the caller is reviewing) into that
    folder's configured target; every other file currently in that directory
    is trashed. Identity-mapped folders (the default for anything without a
    real promotion) leave `selected` in place and just trash the rest — a
    "keep these, discard the rest" cull with no destination change."""
    source = folders.FOLDERS.get(folder_name)
    if source is None:
        raise LibraryOpError(f"unknown folder: {folder_name}")
    directory = _entity_dir(source, entity)

    present = _list_files(directory)
    selected_names = {Path(name).name for name in selected}
    unknown = selected_names - present
    if unknown:
        raise LibraryOpError(f"not present in {folder_name}: {', '.join(sorted(unknown))}")

    target_name = settings.move_target(folder_name)
    target = folders.FOLDERS[target_name]
    # Identity mapping never needs a destination — resolved lazily so a
    # shape mismatch (promoting a flat folder into a per-entity one, say)
    # only matters when a real move is about to happen.
    dest_dir = directory if target_name == folder_name else _entity_dir(target, entity)

    moved: list[str] = []
    trashed: list[str] = []
    errors: list[str] = []

    for name in sorted(present):
        src = directory / name
        if name in selected_names:
            if target_name == folder_name:
                moved.append(name)
                continue
            try:
                dest_dir.mkdir(parents=True, exist_ok=True)
                _move(str(src), str(dest_dir / name))
                moved.append(name)
            except OSError as error:
                errors.append(f"{name}: {error}")
        else:
            try:
                send2trash(str(src))
                trashed.append(name)
            except OSError as error:
                errors.append(f"{name}: {error}")

    return {
        "folder": folder_name,
        "entity": entity,
        "target": target_name,
        "moved": moved,
        "trashed": trashed,
        "errors": errors,
    }


def delete(paths: list[str]) -> dict:
    """Trashes an explicit list of `IA_DIR`-relative paths (as returned by
    `GET /api/library/images`), regardless of which folder/entity each one is
    in — unlike `apply`, this never touches anything the caller didn't name."""
    deleted: list[str] = []
    errors: list[str] = []
    for rel in paths:
        resolved = folders.resolve(folders.IA_DIR / rel)
        if resolved is None:
            errors.append(f"not a library path: {rel}")
            continue
        abs_path = folders.IA_DIR / rel
        if not abs_path.is_file():
            errors.append(f"not found: {rel}")
            continue
        try:
            send2trash(str(abs_path))
            deleted.append(rel)
        except OSError as error:
            errors.append(f"{rel}: {error}")
    return {"deleted": deleted, "errors": errors}
