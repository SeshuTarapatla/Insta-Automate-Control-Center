"""Per-entity yield funnel (PLAN CP 5.4) — one root entity's progress through
the pipeline stages, read live from Postgres plus the folder counts CP 5.1
already tracks.

`scanned`/`private`/`female`/`male` come straight from `scanned` rows keyed
by `root`, and `scraped` from `user` rows keyed by `root` — real per-entity
data with an existing index-free equality filter (fine at today's volume:
measured well under 100ms against the live 155k/21k-row tables).

**`followed` has no equivalent source.** `entity_follow` sends the request
and unlinks the image with no DB row ever written for it — the only
persisted signal is a global daily counter (`Follow.followed`), not
per-entity. Inventing a real one means a pipeline schema change, out of
scope for a checkpoint marked agent+app only. Approximated instead as
`scraped − (still in scraped/ + still in follow_queued/)`, using
`LibraryCounts`' live per-root numbers: every scraped user starts in
`scraped/`, gets promoted to `follow_queued/` on human review, and
disappears from both once `entity_follow` actually processes it — so
whatever's still sitting in either folder hasn't been followed yet, and
what's left over has (or was silently dropped during review, which this
can't distinguish and says so in `CLAUDE.md`/`DECISIONS.md`, not to the
user inline)."""
from sqlalchemy import Engine, text

from ia_agent.integrations import postgres
from ia_agent.library.counts import LibraryCounts

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
_SCRAPED_COUNT_SQL = text('SELECT count(*) FROM "user" WHERE root = :root')


def fetch(root: str, counts: LibraryCounts, *, engine: Engine | None = None) -> dict | None:
    """`None` when `root` isn't a known `Entity.id` — the caller 404s."""
    engine = engine or postgres.get_engine()
    with engine.connect() as connection:
        entity = connection.execute(_ENTITY_SQL, {"root": root}).mappings().one_or_none()
        if entity is None:
            return None
        scan = connection.execute(_SCAN_COUNTS_SQL, {"root": root}).mappings().one()
        scraped = connection.execute(_SCRAPED_COUNT_SQL, {"root": root}).scalar() or 0

    in_scraped_folder = counts.count_for("scraped", root)
    in_follow_queued_folder = counts.count_for("follow_queued", root)
    followed_est = max(0, scraped - in_scraped_folder - in_follow_queued_folder)

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
        "scraped": scraped,
        "in_scraped_folder": in_scraped_folder,
        "in_follow_queued_folder": in_follow_queued_folder,
        "followed_est": followed_est,
    }
