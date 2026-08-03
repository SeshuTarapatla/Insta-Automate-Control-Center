"""Cross-entity insights (CP 7.2, corrected per D75) — `ranking()`/`funnel()`
against a scratch SQLite engine standing in for Postgres (same `text()`-only
convention `test_entity_view.py` established), plus `burndown()` against
scratch `scan`/`scrape`/`follow` history rows and a scratch `config.env`.
Then the same REST surface again over a live app instance. Never touches the
real Postgres database, `IA_DIR`, or `config.env`.

D75's correction: `ranking()` no longer reports scraped/followed at all (no
accurate per-entity source exists — see `insights.py`'s module docstring),
and `funnel()`'s scraped/followed are real all-time totals summed from the
`scrape`/`follow` day-counter tables, entirely independent of the `scanned`/
`entity`/`user` tables `ranking()` reads. This suite's fixture deliberately
gives those two numbers no arithmetic relationship to the per-entity data,
so a test that accidentally reads the old (wrong) formula would fail loudly.
"""
import asyncio
import shutil
import sys
import tempfile
import threading
from pathlib import Path

import httpx
import uvicorn
from sqlalchemy import create_engine, text
from sqlalchemy.pool import StaticPool

import ia_agent.insights as insights

OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


SCRATCH = Path(tempfile.mkdtemp(prefix="ia-agent-test-insights-"))
CONFIG_PATH = SCRATCH / "config.env"
CONFIG_PATH.write_text("PROFILES=10\nREELS=30\nPOSTS=30\nSCRAPE=300\nFOLLOW=60\n", encoding="utf-8")

# ------------------------------------------------------------ fixture engine

ENGINE = create_engine(
    "sqlite:///:memory:", connect_args={"check_same_thread": False}, poolclass=StaticPool
)
with ENGINE.begin() as conn:
    conn.execute(text(
        "CREATE TABLE entity (id TEXT PRIMARY KEY, url TEXT, type TEXT, access TEXT, "
        "status TEXT, added_on TEXT, updated_on TEXT)"
    ))
    conn.execute(text("CREATE TABLE scanned (id TEXT PRIMARY KEY, root TEXT, access TEXT, gender TEXT)"))
    conn.execute(text('CREATE TABLE "user" (id TEXT PRIMARY KEY, root TEXT)'))
    conn.execute(text("CREATE TABLE scan (date TEXT PRIMARY KEY, profiles INT, reels INT, posts INT)"))
    conn.execute(text("CREATE TABLE scrape (date TEXT PRIMARY KEY, scraped INT, processed INT)"))
    conn.execute(text("CREATE TABLE follow (date TEXT PRIMARY KEY, followed INT)"))

    # "alice": a real scan funnel. Also seeded with 5 rows in the `user` table
    # (the old, wrong "scraped" source) deliberately outnumbering anything
    # the real scrape/follow day-counters below say, so a regression back to
    # counting `user` rows would show up as a wildly wrong ranking/funnel
    # number instead of silently passing.
    conn.execute(
        text("INSERT INTO entity VALUES ('alice', 'https://www.instagram.com/alice', 'PROFILE', 'PRIVATE', 'COMPLETED', '2026-07-01T00:00:00', '2026-07-02T00:00:00')")
    )
    for i in range(4):
        conn.execute(text("INSERT INTO scanned VALUES (:id, 'alice', 'PUBLIC', 'UNDEF')"), {"id": f"alice_pub{i}"})
    for i in range(3):
        conn.execute(text("INSERT INTO scanned VALUES (:id, 'alice', 'PRIVATE', 'FEMALE')"), {"id": f"alice_f{i}"})
    for i in range(2):
        conn.execute(text("INSERT INTO scanned VALUES (:id, 'alice', 'PRIVATE', 'MALE')"), {"id": f"alice_m{i}"})
    conn.execute(text("INSERT INTO scanned VALUES ('alice_undef', 'alice', 'PRIVATE', 'UNDEF')"))
    for i in range(5):
        conn.execute(text("INSERT INTO \"user\" VALUES (:id, 'alice')"), {"id": f"alice_u{i}"})

    # "bob": scanned, never scraped — must still appear in ranking (real scan
    # activity is the only bar for inclusion now that scraped/followed are
    # gone from the per-entity shape).
    conn.execute(
        text("INSERT INTO entity VALUES ('bob', 'https://www.instagram.com/bob', 'PROFILE', 'PRIVATE', 'QUEUED', '2026-07-03T00:00:00', '2026-07-03T00:00:00')")
    )
    conn.execute(text("INSERT INTO scanned VALUES ('bob_x', 'bob', 'PRIVATE', 'FEMALE')"))

    # "carol": an entity row with no scan activity at all — must not appear.
    conn.execute(
        text("INSERT INTO entity VALUES ('carol', 'https://www.instagram.com/carol', 'PROFILE', 'UNDEF', 'QUEUED', '2026-07-04T00:00:00', '2026-07-04T00:00:00')")
    )

    # Five days of real daily history — the only source `funnel()`'s
    # scraped/followed totals should read from.
    for i, (date, p, r, po) in enumerate(
        [("2026-07-28", 3, 5, 2), ("2026-07-29", 10, 30, 1), ("2026-07-30", 0, 0, 0), ("2026-07-31", 4, 6, 3), ("2026-08-01", 1, 2, 0)]
    ):
        conn.execute(text("INSERT INTO scan VALUES (:d, :p, :r, :po)"), {"d": date, "p": p, "r": r, "po": po})
        conn.execute(text("INSERT INTO scrape VALUES (:d, :s, :pr)"), {"d": date, "s": i * 10, "pr": i * 12})
        conn.execute(text("INSERT INTO follow VALUES (:d, :f)"), {"d": date, "f": i * 3})


def real_checks() -> None:
    print("\n1. ranking() has no scraped/followed at all, and never reads the `user` table")
    rows = insights.ranking(engine=ENGINE)
    by_root = {row["root"]: row for row in rows}
    check("alice and bob present, carol excluded (no scan activity)", set(by_root) == {"alice", "bob"}, str(set(by_root)))
    check("no row carries a scraped/followed/followed_est key", all("scraped" not in r and "followed" not in r and "followed_est" not in r for r in rows), str(rows))
    check("alice: scanned=10 private=6 female=3 male=2", (
        by_root["alice"]["scanned"] == 10 and by_root["alice"]["private"] == 6
        and by_root["alice"]["female"] == 3 and by_root["alice"]["male"] == 2
    ), str(by_root["alice"]))
    check("bob: scanned=1 private=1 female=1", (
        by_root["bob"]["scanned"] == 1 and by_root["bob"]["private"] == 1 and by_root["bob"]["female"] == 1
    ), str(by_root["bob"]))
    check("sorted scanned desc: alice (10) before bob (1)", [r["root"] for r in rows] == ["alice", "bob"], str(rows))

    print("\n2. funnel()'s scanned/private/female/male are ranking() summed")
    summary = insights.funnel(engine=ENGINE)
    check("entities = 2", summary["entities"] == 2, str(summary))
    check("scanned = 11 (10 + 1)", summary["scanned"] == 11, str(summary))
    check("private = 7, female = 4, male = 2", summary["private"] == 7 and summary["female"] == 4 and summary["male"] == 2, str(summary))

    print("\n3. funnel()'s scraped/followed are REAL totals from scrape/follow, NOT derived from the 5 `user` rows")
    check("scraped = 100 (sum of 0+10+20+30+40 from the scrape table)", summary["scraped"] == 100, str(summary))
    check("followed = 30 (sum of 0+3+6+9+12 from the follow table)", summary["followed"] == 30, str(summary))
    check("no followed_est key on the funnel summary", "followed_est" not in summary, str(summary))

    print("\n4. burndown() returns real multi-day history, oldest first, plus the live limits")
    bd = insights.burndown(3, engine=ENGINE, config_path=CONFIG_PATH)
    check("days clamped to what was asked (3)", bd["days"] == 3, str(bd["days"]))
    check("3 days of scan/scrape/follow history", len(bd["scan"]) == 3 and len(bd["scrape"]) == 3 and len(bd["follow"]) == 3, str(bd))
    check("oldest-first ordering (07-30 before 08-01)", bd["scan"][0]["date"] == "2026-07-30" and bd["scan"][-1]["date"] == "2026-08-01", str(bd["scan"]))
    check("scrape counts carried through untouched", bd["scrape"][-1]["scraped"] == 40, str(bd["scrape"]))
    check("limits read from the scratch config.env", bd["limits"] == {"profiles": 10, "reels": 30, "posts": 30, "scrape": 300, "follow": 60}, str(bd["limits"]))

    print("\n5. burndown() clamps an out-of-range days request rather than raising")
    clamped = insights.burndown(0, engine=ENGINE, config_path=CONFIG_PATH)
    check("0 clamps up to 1", clamped["days"] == 1, str(clamped["days"]))
    huge = insights.burndown(10_000, engine=ENGINE, config_path=CONFIG_PATH)
    check(f"an oversized request clamps to MAX_DAYS ({insights.MAX_DAYS})", huge["days"] == insights.MAX_DAYS, str(huge["days"]))


real_checks()


# ------------------------------------------------------------------ live app

import ia_agent.app as app_module  # noqa: E402

app_module.build_specs = lambda: []
insights.postgres.get_engine = lambda: ENGINE
insights.CONFIG_PATH = CONFIG_PATH
PORT = 8798
app = app_module.create_app()
from ia_agent.vars import TOKEN_PATH  # noqa: E402

token = TOKEN_PATH.read_text().strip()
headers = {"Authorization": f"Bearer {token}"}
server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=PORT, log_level="error"))
threading.Thread(target=server.run, daemon=True).start()


async def live_checks() -> None:
    async with httpx.AsyncClient(base_url=f"http://127.0.0.1:{PORT}", headers=headers) as client:
        for _ in range(50):
            try:
                await client.get("/api/health")
                break
            except httpx.HTTPError:
                await asyncio.sleep(0.2)

        print("\n6. GET /api/insights/funnel, over REST — real scraped/followed totals")
        response = await client.get("/api/insights/funnel")
        check("200 with scraped=100 followed=30 from the day-counter tables", (
            response.status_code == 200 and response.json()["scraped"] == 100 and response.json()["followed"] == 30
        ), response.text)

        print("\n7. GET /api/insights/ranking, over REST — no scraped/followed columns")
        response = await client.get("/api/insights/ranking")
        body = response.json()
        check("200 with 2 ranked entities, none carrying scraped/followed", (
            response.status_code == 200 and len(body) == 2
            and all("scraped" not in row and "followed" not in row for row in body)
        ), response.text)

        print("\n8. GET /api/insights/burndown?days=, over REST")
        response = await client.get("/api/insights/burndown", params={"days": 3})
        check("200 with 3 days of real history", response.status_code == 200 and len(response.json()["scan"]) == 3, response.text)

        print("\n9. GET /api/insights/burndown with an oversized days= clamps rather than 500ing")
        response = await client.get("/api/insights/burndown", params={"days": 999_999})
        check("200, clamped to MAX_DAYS", response.status_code == 200 and response.json()["days"] == insights.MAX_DAYS, response.text)


async def main() -> int:
    await live_checks()
    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    shutil.rmtree(SCRATCH, ignore_errors=True)
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
