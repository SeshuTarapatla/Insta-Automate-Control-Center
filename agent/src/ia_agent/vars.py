import os
import re
from pathlib import Path

HOST = "0.0.0.0"
PORT = 8787

INSTA_AUTOMATE_DIR = Path(r"D:\Coding\Insta-Automate")


def _android_serial() -> str:
    """The phone the pipeline drives. Read from Insta-Automate's own .env rather
    than duplicated here — a serial in two places is a serial that will disagree."""
    from_env = os.environ.get("ANDROID_SERIAL")
    if from_env:
        return from_env
    try:
        text = (INSTA_AUTOMATE_DIR / ".env").read_text()
    except OSError:
        return ""
    match = re.search(r"^\s*ANDROID_SERIAL\s*=\s*['\"]?([^'\"\r\n]+)", text, re.MULTILINE)
    return match.group(1).strip() if match else ""


ANDROID_SERIAL = _android_serial()

IA_DIR = Path(os.environ.get("IA_DIR", r"C:\Users\seshu\Pictures\insta-automate"))
CONFIG_PATH = IA_DIR / "config.env"

# Mirrors insta_automate.vars — the two directories ENTITY_QUEUE orders (see D8)
# plus the entity page images the queue's names refer to.
ENTITY_DIR = IA_DIR / "entities"
SCRAPE_QUEUE_DIR = IA_DIR / "scrape_queued"
FOLLOW_QUEUE_DIR = IA_DIR / "follow_queued"

AGENT_DATA_DIR = Path(os.environ["LOCALAPPDATA"]) / "ia-agent"
TOKEN_PATH = AGENT_DATA_DIR / "token"

# PID files survive an agent restart on purpose — they are how a supervised service
# is adopted rather than orphaned or killed (ARCHITECTURE §3, PLAN CP 2.1).
SERVICE_RUN_DIR = AGENT_DATA_DIR / "run"
SERVICE_LOG_DIR = AGENT_DATA_DIR / "logs"
# Per-service self-heal / autostart switches. Machine-local, never synced (D12).
SERVICE_SETTINGS_PATH = AGENT_DATA_DIR / "services.json"

# Content-addressed flow-event image cache (CP 4.2) — entity_classify and
# entity_follow delete their source image right after logging it, so the
# agent reads the bytes the moment an event arrives rather than trusting the
# path to still resolve later.
IMAGE_CACHE_DIR = AGENT_DATA_DIR / "cache"
