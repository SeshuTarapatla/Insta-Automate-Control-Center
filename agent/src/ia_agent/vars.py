import os
from pathlib import Path

HOST = "0.0.0.0"
PORT = 8787

IA_DIR = Path(os.environ.get("IA_DIR", r"C:\Users\seshu\Pictures\insta-automate"))
CONFIG_PATH = IA_DIR / "config.env"

# Mirrors insta_automate.vars — the two directories ENTITY_QUEUE orders (see D8)
# plus the entity page images the queue's names refer to.
ENTITY_DIR = IA_DIR / "entities"
SCRAPE_QUEUE_DIR = IA_DIR / "scrape_queued"
FOLLOW_QUEUE_DIR = IA_DIR / "follow_queued"

AGENT_DATA_DIR = Path(os.environ["LOCALAPPDATA"]) / "ia-agent"
TOKEN_PATH = AGENT_DATA_DIR / "token"
