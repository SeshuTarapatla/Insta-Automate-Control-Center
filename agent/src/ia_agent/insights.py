"""Cross-entity views (PLAN CP 7.2) built on the same read-only Postgres
access CP 5.4's `library/entity_view.py` already established.

**D75-corrected (see DECISIONS.md): "scraped" is not `count(*) from user`.**
The first version of this module counted `user` table rows as "scraped" per
entity — but `profile_scrape` (`Insta-Automate/tasks/ia.py`) writes that row
via `user.update(session)` *before* its four skip checks (PUBLIC, NO_POSTS,
FMIN, FMAX), so a `user` row exists for every profile whose stats were read,
not just the ones that produced a real scraped image. That inflated both
"scraped" and the `followed_est` derived from it until they were nearly
equal, contradicting the Daily-limits chart's own accurate counters. The real
per-flow success signal already exists — `Scrape.scraped`/`Follow.followed`
only increment when `profile_scrape`/`profile_follow` actually succeed
(`entity_scrape.py`/`entity_follow.py`) — but those are **global daily
counters with no entity attached**, so they can produce a real whole-library
total (summed across every day) and nothing broken down per entity.

So `funnel()` (whole-library, no per-entity breakdown needed) reports real
`scraped`/`followed` totals summed from those tables. `ranking()` (per-entity)
only reports `scanned`/`private`/`female`/`male` — all real, all from the
`scanned` table keyed by `root` — and drops scraped/followed entirely rather
than show an inaccurate number, per direct instruction. The Library screen's
existing per-entity funnel dialog (`entity_view.fetch()`, CP 5.4) still shows
its own already-documented `followed_est` approximation for one entity at a
time — unrelated to and unchanged by this module.

`burndown()` reads real history: `scan`/`scrape`/`follow` are one row per
calendar day, kept forever, so multi-day history already exists with no new
instrumentation."""
from sqlalchemy import Engine, text

from ia_agent.config import env_file
from ia_agent.integrations import postgres
from ia_agent.vars import CONFIG_PATH

MAX_DAYS = 365

_RANKING_SQL = text(
    "SELECT e.id AS root, e.url, e.type, e.access, e.status, "
    "COALESCE(sc.scanned, 0) AS scanned, "
    "COALESCE(sc.private, 0) AS private, "
    "COALESCE(sc.female, 0) AS female, "
    "COALESCE(sc.male, 0) AS male "
    "FROM entity e "
    "JOIN ("
    "  SELECT root, count(*) AS scanned, "
    "  sum(CASE WHEN access = 'PRIVATE' THEN 1 ELSE 0 END) AS private, "
    "  sum(CASE WHEN access = 'PRIVATE' AND gender = 'FEMALE' THEN 1 ELSE 0 END) AS female, "
    "  sum(CASE WHEN access = 'PRIVATE' AND gender = 'MALE' THEN 1 ELSE 0 END) AS male "
    "  FROM scanned GROUP BY root"
    ") sc ON sc.root = e.id "
    "ORDER BY scanned DESC, e.id ASC"
)

_SCRAPE_TOTAL_SQL = text("SELECT COALESCE(SUM(scraped), 0) FROM scrape")
_FOLLOW_TOTAL_SQL = text("SELECT COALESCE(SUM(followed), 0) FROM follow")

_SCAN_HISTORY_SQL = text("SELECT date, profiles, reels, posts FROM scan ORDER BY date DESC LIMIT :n")
_SCRAPE_HISTORY_SQL = text("SELECT date, scraped, processed FROM scrape ORDER BY date DESC LIMIT :n")
_FOLLOW_HISTORY_SQL = text("SELECT date, followed FROM follow ORDER BY date DESC LIMIT :n")


def _iso(value) -> str | None:
    return value.isoformat() if hasattr(value, "isoformat") else value


def ranking(*, engine: Engine | None = None) -> list[dict]:
    """One row per entity with any real scan activity — `scanned`/`private`/
    `female`/`male` only, all real per-entity Postgres counts. No
    scraped/followed column: see the module docstring for why neither has an
    accurate per-entity source."""
    engine = engine or postgres.get_engine()
    with engine.connect() as connection:
        rows = connection.execute(_RANKING_SQL).mappings().all()
    return [
        {
            "root": row["root"],
            "url": row["url"],
            "type": row["type"],
            "access": row["access"],
            "status": row["status"],
            "scanned": row["scanned"] or 0,
            "private": row["private"] or 0,
            "female": row["female"] or 0,
            "male": row["male"] or 0,
        }
        for row in rows
    ]


def funnel(*, engine: Engine | None = None) -> dict:
    """Whole-library totals. `scanned`/`private`/`female`/`male` are
    `ranking()` summed (real per-entity data with nothing to lose by
    aggregating); `scraped`/`followed` are real all-time totals summed
    straight from the `Scrape`/`Follow` day-counter tables, independent of
    `ranking()` entirely — see the module docstring."""
    engine = engine or postgres.get_engine()
    rows = ranking(engine=engine)
    totals = {"entities": len(rows), "scanned": 0, "private": 0, "female": 0, "male": 0}
    for row in rows:
        for key in ("scanned", "private", "female", "male"):
            totals[key] += row[key]

    with engine.connect() as connection:
        totals["scraped"] = connection.execute(_SCRAPE_TOTAL_SQL).scalar() or 0
        totals["followed"] = connection.execute(_FOLLOW_TOTAL_SQL).scalar() or 0
    return totals


def _history(connection, query, days: int, fields: tuple[str, ...]) -> list[dict]:
    """Newest-first `LIMIT :n`, reversed to oldest-first for a chart's x-axis."""
    rows = connection.execute(query, {"n": days}).mappings().all()
    return [{"date": _iso(row["date"]), **{field: row[field] or 0 for field in fields}} for row in reversed(rows)]


def burndown(days: int = 30, *, engine: Engine | None = None, config_path=None) -> dict:
    # `config_path` is resolved against the module-level `CONFIG_PATH` at call
    # time, not bound as a default value, so a test can monkeypatch
    # `insights.CONFIG_PATH` after import the same way it monkeypatches
    # `insights.postgres.get_engine` — a default argument would freeze the
    # real machine's path in at import time instead.
    engine = engine or postgres.get_engine()
    config_path = config_path or CONFIG_PATH
    days = max(1, min(days, MAX_DAYS))
    with engine.connect() as connection:
        scan_history = _history(connection, _SCAN_HISTORY_SQL, days, ("profiles", "reels", "posts"))
        scrape_history = _history(connection, _SCRAPE_HISTORY_SQL, days, ("scraped", "processed"))
        follow_history = _history(connection, _FOLLOW_HISTORY_SQL, days, ("followed",))

    data = env_file.load(config_path)
    limits = data.limits if data else {}
    return {
        "days": days,
        "limits": {
            "profiles": limits.get("PROFILES"),
            "reels": limits.get("REELS"),
            "posts": limits.get("POSTS"),
            "scrape": limits.get("SCRAPE"),
            "follow": limits.get("FOLLOW"),
        },
        "scan": scan_history,
        "scrape": scrape_history,
        "follow": follow_history,
    }
