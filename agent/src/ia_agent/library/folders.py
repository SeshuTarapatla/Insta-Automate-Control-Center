"""The seven `IA_DIR` pipeline stage directories the Library screen browses
(ARCHITECTURE §1.1, PLAN CP 5.1). `entities/` holds `<id>.jpg` files directly;
every other folder holds one subdirectory per entity root, each full of that
entity's images for that stage. `.thumbs` (the mobile app's own thumbnail
cache) and `.Trash-0` (send2trash's trash, relevant from CP 5.2 on) are
deliberately not library folders — nothing here watches or lists them.
"""
from dataclasses import dataclass
from pathlib import Path

from ia_agent.vars import (
    ENTITY_DIR,
    FOLLOW_QUEUE_DIR,
    GENDER_INVALID_DIR,
    GENDER_VALID_DIR,
    IA_DIR,
    SCANNED_DIR,
    SCRAPE_QUEUE_DIR,
    SCRAPED_DIR,
)


@dataclass(frozen=True)
class LibraryFolder:
    name: str
    path: Path
    flat: bool  # True only for "entities" — files live directly under it


FOLDERS: dict[str, LibraryFolder] = {
    folder.name: folder
    for folder in (
        LibraryFolder("entities", ENTITY_DIR, flat=True),
        LibraryFolder("scanned", SCANNED_DIR, flat=False),
        LibraryFolder("gender_valid", GENDER_VALID_DIR, flat=False),
        LibraryFolder("gender_invalid", GENDER_INVALID_DIR, flat=False),
        LibraryFolder("scrape_queued", SCRAPE_QUEUE_DIR, flat=False),
        LibraryFolder("scraped", SCRAPED_DIR, flat=False),
        LibraryFolder("follow_queued", FOLLOW_QUEUE_DIR, flat=False),
    )
}


def resolve(path: Path) -> tuple[str, str | None] | None:
    """Maps an absolute filesystem path back to the `(folder, root)` it
    belongs to, for the watcher to know what to recompute. `None` for
    anything outside a known folder (`.thumbs`, `.Trash-0`, `config.env`,
    a folder just created that isn't one of the seven)."""
    try:
        rel = path.resolve().relative_to(IA_DIR.resolve())
    except ValueError:
        return None
    parts = rel.parts
    if not parts or parts[0] not in FOLDERS:
        return None
    folder = FOLDERS[parts[0]]
    if folder.flat:
        return folder.name, None
    if len(parts) < 2:
        return None
    return folder.name, parts[1]
