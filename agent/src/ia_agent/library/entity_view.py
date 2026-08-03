"""Per-entity yield funnel (PLAN CP 5.4) — one root entity's progress through
the pipeline stages, read live from Postgres.

`scanned`/`private`/`female`/`male` come straight from `scanned` rows keyed
by `root` — real per-entity data with an existing index-free equality filter
(fine at today's volume: measured well under 100ms against the live
155k/21k-row tables).

**D81-corrected (see DECISIONS.md): no `scraped`/`followed` here either.**
The first version counted `user` rows as "scraped" per entity and derived
`followed_est` from that — but `profile_scrape` writes that `user` row
*before* its own skip checks (PUBLIC/NO_POSTS/FMIN/FMAX), so it counts every
profile whose stats were read, not just the ones that produced a real
scraped image. `ia_agent/insights.py`'s `ranking()` hit the identical bug
(D76) and was fixed by dropping scraped/followed from the per-entity view
entirely, since the only accurate success signal (`Scrape.scraped`/
`Follow.followed`) is a **global daily counter with no entity attached** —
there is no accurate per-entity source for either number without a pipeline
schema change (out of scope, same as D49's "followed" tracking). This module
now matches that precedent exactly rather than showing an approximation
built on an inflated base."""
from sqlalchemy import Engine, text

from ia_agent.integrations import postgres

_SCAN_COUNTS_SQL = text(
    "SELECT "
    "count(*) AS scanned, "
    "sum(CASE WHEN access = 'PRIVATE' THEN 1 ELSE 0 END) AS private, "
    "sum(CASE WHEN access = 'PRIVATE' AND gender = 'FEMALE' THEN 1 ELSE 0 END) AS female, "
    "sum(CASE WHEN access = 'PRIVATE' AND gender = 'MALE' THEN 1 ELSE 0 END) AS male "
    "FROM scanned WHERE root = :root"
)
_ENTITY_SQL = text(
    "SELECT url, type, access, status, added_on, updated_on FROM entity WHERE id = :root"
)


def fetch(root: str, *, engine: Engine | None = None) -> dict | None:
    """`None` when `root` isn't a known `Entity.id` — the caller 404s."""
    engine = engine or postgres.get_engine()
    with engine.connect() as connection:
        entity = connection.execute(_ENTITY_SQL, {"root": root}).mappings().one_or_none()
        if entity is None:
            return None
        scan = connection.execute(_SCAN_COUNTS_SQL, {"root": root}).mappings().one()

    def _iso(value) -> str | None:
        return value.isoformat() if hasattr(value, "isoformat") else value

    return {
        "root": root,
        "url": entity["url"],
        "type": entity["type"],
        "access": entity["access"],
        "status": entity["status"],
        "added_on": _iso(entity["added_on"]),
        "updated_on": _iso(entity["updated_on"]),
        "scanned": scan["scanned"] or 0,
        "private": scan["private"] or 0,
        "female": scan["female"] or 0,
        "male": scan["male"] or 0,
    }
