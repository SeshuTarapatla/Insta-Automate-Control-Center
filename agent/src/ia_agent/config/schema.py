from dataclasses import dataclass
from enum import StrEnum


class ConfigType(StrEnum):
    INT = "int"
    BOOL01 = "bool01"  # stored as the string '0' or '1'
    QUEUE = "queue"  # comma-separated list


class ConfigGroup(StrEnum):
    SWITCH = "switch"
    SCAN = "scan"
    SCRAPE = "scrape"
    FOLLOW = "follow"


@dataclass(frozen=True)
class ConfigKey:
    name: str
    group: ConfigGroup
    type: ConfigType
    default: int | str
    help: str
    min: int | None = None
    max: int | None = None


SWITCH_KEYS = [
    "ENTITY_INGEST",
    "ENTITY_SCAN",
    "ENTITY_CLASSIFY",
    "ENTITY_SCRAPE",
    "ENTITY_FOLLOW",
]

# Defaults for the nine limit keys mirror insta_automate.models.meta.Limit._DEFAULTS
# exactly — that class is what the flows actually read at runtime.
SCHEMA: dict[str, ConfigKey] = {
    "ENTITY_INGEST": ConfigKey(
        "ENTITY_INGEST", ConfigGroup.SWITCH, ConfigType.BOOL01, 1,
        "Poll the Telegram entity channel for new profiles/posts/reels to queue.",
    ),
    "ENTITY_SCAN": ConfigKey(
        "ENTITY_SCAN", ConfigGroup.SWITCH, ConfigType.BOOL01, 1,
        "Harvest usernames from queued entities' followers/following/likers.",
    ),
    "ENTITY_CLASSIFY": ConfigKey(
        "ENTITY_CLASSIFY", ConfigGroup.SWITCH, ConfigType.BOOL01, 1,
        "Run gender/privacy classification on scanned row crops.",
    ),
    "ENTITY_SCRAPE": ConfigKey(
        "ENTITY_SCRAPE", ConfigGroup.SWITCH, ConfigType.BOOL01, 1,
        "Open profiles from scrape_queued and capture their stats.",
    ),
    "ENTITY_FOLLOW": ConfigKey(
        "ENTITY_FOLLOW", ConfigGroup.SWITCH, ConfigType.BOOL01, 1,
        "Follow profiles from follow_queued.",
    ),
    "ENTITY_QUEUE": ConfigKey(
        "ENTITY_QUEUE", ConfigGroup.SWITCH, ConfigType.QUEUE, "",
        "Priority order for scrape and follow candidates (shared list — see Q1).",
    ),
    "PROFILES": ConfigKey(
        "PROFILES", ConfigGroup.SCAN, ConfigType.INT, 10,
        "Daily cap on profile entities scanned.", min=0,
    ),
    "REELS": ConfigKey(
        "REELS", ConfigGroup.SCAN, ConfigType.INT, 30,
        "Daily cap on reel entities scanned.", min=0,
    ),
    "POSTS": ConfigKey(
        "POSTS", ConfigGroup.SCAN, ConfigType.INT, 30,
        "Daily cap on post entities scanned.", min=0,
    ),
    "SCRAPE": ConfigKey(
        "SCRAPE", ConfigGroup.SCRAPE, ConfigType.INT, 300,
        "Daily cap on profiles scraped.", min=0,
    ),
    "SCRAPE_BATCH": ConfigKey(
        "SCRAPE_BATCH", ConfigGroup.SCRAPE, ConfigType.INT, 10,
        "Profiles scraped per run before yielding.", min=0,
    ),
    "FOLLOW": ConfigKey(
        "FOLLOW", ConfigGroup.FOLLOW, ConfigType.INT, 60,
        "Daily cap on profiles followed.", min=0,
    ),
    "FOLLOW_BATCH": ConfigKey(
        "FOLLOW_BATCH", ConfigGroup.FOLLOW, ConfigType.INT, 5,
        "Profiles followed per run before yielding.", min=0,
    ),
    "FMIN": ConfigKey(
        "FMIN", ConfigGroup.FOLLOW, ConfigType.INT, 100,
        "Minimum follower count for a follow candidate.", min=0,
    ),
    "FMAX": ConfigKey(
        "FMAX", ConfigGroup.FOLLOW, ConfigType.INT, 2000,
        "Maximum follower count for a follow candidate.", min=0,
    ),
}
