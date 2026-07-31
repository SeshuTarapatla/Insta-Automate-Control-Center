import json
import threading

from ia_agent.logging import logger
from ia_agent.vars import SERVICE_SETTINGS_PATH

# Deliberately not in config.env. That file is IA_DIR-relative, Syncthing-replicated
# to the phone and read live by the flows inside the pods; which Windows processes
# this machine supervises is none of the pipeline's business and would be actively
# wrong to sync. See DECISIONS D12.

_lock = threading.Lock()


def load() -> dict[str, dict]:
    if not SERVICE_SETTINGS_PATH.exists():
        return {}
    try:
        return json.loads(SERVICE_SETTINGS_PATH.read_text())
    except (json.JSONDecodeError, OSError) as error:
        logger.warning(f"unreadable service settings, falling back to spec defaults — {error}")
        return {}


def get(name: str) -> dict:
    return load().get(name, {})


def update(name: str, **values) -> dict:
    with _lock:
        data = load()
        entry = {**data.get(name, {}), **values}
        data[name] = entry
        SERVICE_SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
        temp = SERVICE_SETTINGS_PATH.with_suffix(".tmp")
        temp.write_text(json.dumps(data, indent=2))
        temp.replace(SERVICE_SETTINGS_PATH)
        return entry
