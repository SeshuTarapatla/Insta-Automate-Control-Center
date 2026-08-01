"""Per-folder Library "apply" move targets (PLAN CP 5.2), persisted the same way
`services/settings.py` persists self-heal/autostart — machine-local JSON, never
`config.env` (D12's reasoning applies again: which folder curation promotes into
is a desktop-app concern, not something the pipeline reads).

Defaults encode the two real human-review steps ARCHITECTURE §1.1 documents
(`gender_valid → scrape_queued`, `scraped → follow_queued`) rather than the
mobile app's identity-everywhere default (checked against `ia_manager`'s
`SettingsProvider._folderMappings`) — this app already knows the real pipeline
shape, so there is no reason to make a user configure what is already known.
Every other folder defaults to itself: "apply" then
means "keep the selected images, discard the rest" with no promotion, which is
still a useful action (see `library/ops.py`).
"""
import json
import threading

from ia_agent.library import folders
from ia_agent.logging import logger
from ia_agent.vars import LIBRARY_SETTINGS_PATH

_lock = threading.Lock()

_DEFAULT_TARGETS = {
    "gender_valid": "scrape_queued",
    "scraped": "follow_queued",
}


def _defaults() -> dict[str, str]:
    # `folders.FOLDERS` looked up dynamically, not imported by name — tests
    # rebind the whole dict to a scratch taxonomy (see test_library.py), and a
    # name-bound import here would keep pointing at the real one.
    return {name: _DEFAULT_TARGETS.get(name, name) for name in folders.FOLDERS}


def load() -> dict[str, str]:
    defaults = _defaults()
    if not LIBRARY_SETTINGS_PATH.exists():
        return defaults
    try:
        saved = json.loads(LIBRARY_SETTINGS_PATH.read_text())
    except (json.JSONDecodeError, OSError) as error:
        logger.warning(f"unreadable library settings, falling back to defaults — {error}")
        return defaults
    targets = saved.get("move_targets", {})
    return {
        **defaults,
        **{
            name: target
            for name, target in targets.items()
            if name in folders.FOLDERS and target in folders.FOLDERS
        },
    }


def move_target(folder_name: str) -> str:
    return load().get(folder_name, folder_name)


def set_move_target(folder_name: str, target_name: str) -> dict[str, str]:
    if folder_name not in folders.FOLDERS:
        raise KeyError(f"unknown folder: {folder_name}")
    if target_name not in folders.FOLDERS:
        raise KeyError(f"unknown folder: {target_name}")
    with _lock:
        data: dict = {}
        if LIBRARY_SETTINGS_PATH.exists():
            try:
                data = json.loads(LIBRARY_SETTINGS_PATH.read_text())
            except (json.JSONDecodeError, OSError):
                data = {}
        targets = data.get("move_targets", {})
        targets[folder_name] = target_name
        data["move_targets"] = targets
        LIBRARY_SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
        temp = LIBRARY_SETTINGS_PATH.with_suffix(".tmp")
        temp.write_text(json.dumps(data, indent=2))
        temp.replace(LIBRARY_SETTINGS_PATH)
    return load()
