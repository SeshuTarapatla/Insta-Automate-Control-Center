import os
import re
from pathlib import Path

HOST = "0.0.0.0"
PORT = 8787

INSTA_AUTOMATE_DIR = Path(r"D:\Coding\Insta-Automate")
HELMCHARTS_DIR = Path(r"D:\Coding\Helmcharts\Insta-Automate")
PREFECT_K3S_DIR = Path(r"D:\Coding\Prefect-K3S")

# The branch every ops job (build/deploy/helm upgrade) targets — one place to
# change instead of a value someone's shell needs to remember to set, which is
# the actual root cause behind D55/D59's repeated "deployed from main by
# accident" incidents. Flip to "" once the control center is accepted and
# these repos merge to main (see CLAUDE.md rule 3).
IA_OPS_GIT_BRANCH = os.environ.get("IA_OPS_GIT_BRANCH", "feat/control-center")


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

# The remaining ARCHITECTURE §1.1 pipeline stage directories — CP 5.1's Library
# API browses all seven, ENTITY_DIR/SCRAPE_QUEUE_DIR/FOLLOW_QUEUE_DIR included.
SCANNED_DIR = IA_DIR / "scanned"
GENDER_VALID_DIR = IA_DIR / "gender_valid"
GENDER_INVALID_DIR = IA_DIR / "gender_invalid"
SCRAPED_DIR = IA_DIR / "scraped"

AGENT_DATA_DIR = Path(os.environ["LOCALAPPDATA"]) / "ia-agent"
TOKEN_PATH = AGENT_DATA_DIR / "token"

# PID files survive an agent restart on purpose — they are how a supervised service
# is adopted rather than orphaned or killed (ARCHITECTURE §3, PLAN CP 2.1).
SERVICE_RUN_DIR = AGENT_DATA_DIR / "run"
SERVICE_LOG_DIR = AGENT_DATA_DIR / "logs"
# Per-service self-heal / autostart switches. Machine-local, never synced (D12).
SERVICE_SETTINGS_PATH = AGENT_DATA_DIR / "services.json"

# Per-folder Library "apply" move targets (PLAN CP 5.2) — which stage folder a
# review approval promotes into. Machine-local for the same D12 reason: which
# folder curation moves files into is a desktop-app concern, not something the
# pipeline reads.
LIBRARY_SETTINGS_PATH = AGENT_DATA_DIR / "library.json"

# Content-addressed flow-event image cache (CP 4.2) — entity_classify and
# entity_follow delete their source image right after logging it, so the
# agent reads the bytes the moment an event arrives rather than trusting the
# path to still resolve later.
IMAGE_CACHE_DIR = AGENT_DATA_DIR / "cache"

# Paired phones (PLAN CP 6.1, ARCHITECTURE §7) — device id/name/token/last_seen.
# Machine-local for the same D12 reason every other *.json settings file is:
# which phones are paired is a property of this agent instance, not the
# pipeline. Device tokens live here, never in config.env.
PAIRING_DEVICES_PATH = AGENT_DATA_DIR / "pairing.json"

# Persisted notification history (PLAN CP 6.1, ARCHITECTURE §6) — unlike
# events/store.py's in-memory-only ring (a flow run's images are gone the
# moment the next run starts, so nothing of value survives a restart
# anyway), an unread "limit reached" or "scan complete" notification is
# exactly the kind of state a restart must not silently drop.
NOTIFICATIONS_PATH = AGENT_DATA_DIR / "notifications.json"

# Ops job history (PLAN CP 7.1) — same D50 reasoning as notifications: a
# helm uninstall or db restore's outcome must survive an agent restart, not
# just live in memory until the next one.
OPS_JOBS_DIR = AGENT_DATA_DIR / "ops_jobs"
OPS_JOBS_KEEP = 50
