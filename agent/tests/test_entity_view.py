"""Entity-view funnel (CP 5.4, D81-corrected) — `entity_view.fetch()` against a
scratch SQLite engine standing in for Postgres (raw `text()` SQL only, no ORM
models, so the same statements run against either dialect), then the same
thing again over the live REST surface with `entity_view.postgres.get_engine`
monkeypatched to the same fixture engine. Never touches the real Postgres
database or the real `IA_DIR`.

D81: `scraped`/`followed_est` are gone from this module entirely — the same
`count(*) from "user"` inflation bug D76 found and fixed in `insights.py`'s
`ranking()` lived here too (unfixed, since CP 5.4 was already-accepted code
out of that session's ask). Fixed now the same way: no per-entity source
exists for either number, so neither is reported. The fixture keeps a
`"user"` table only to prove `fetch()` no longer reads it.
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

import ia_agent.library.entity_view as entity_view

OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


SCRATCH = Path(tempfile.mkdtemp(prefix="ia-agent-test-entity-view-"))

# ------------------------------------------------------------ fixture engine

ENGINE = create_engine(
    "sqlite:///:memory:", connect_args={"check_same_thread": False}, poolclass=StaticPool
)  # a plain :memory: engine hands each thread its own empty database (its default
# SingletonThreadPool is per-thread); StaticPool shares the one connection so the
# live app's asyncio.to_thread() worker sees the same tables the fixtures wrote.
with ENGINE.begin() as conn:
    conn.execute(text(
        "CREATE TABLE entity (id TEXT PRIMARY KEY, url TEXT, type TEXT, access TEXT, "
        "status TEXT, added_on TEXT, updated_on TEXT)"
    ))
    conn.execute(text("CREATE TABLE scanned (id TEXT PRIMARY KEY, root TEXT, access TEXT, gender TEXT)"))
    # Kept only to prove fetch() no longer reads it (see check 1 below) —
    # this is exactly the table whose count(*) used to inflate "scraped".
    conn.execute(text('CREATE TABLE "user" (id TEXT PRIMARY KEY, root TEXT)'))

    # "alice": a full scan funnel — 10 scanned, 6 private, 3 female (the only
    # ones ever gender-classified — access=PUBLIC rows never reach the
    # classifier), 2 male. Two "user" rows exist for alice (pre-skip-check
    # writes profile_scrape makes regardless of outcome) — deliberately not
    # reflected anywhere in fetch()'s result.
    conn.execute(
        text("INSERT INTO entity VALUES (:id, :url, 'PROFILE', 'PRIVATE', 'COMPLETED', '2026-07-01T00:00:00', '2026-07-02T00:00:00')"),
        {"id": "alice", "url": "https://www.instagram.com/alice"},
    )
    for i in range(4):
        conn.execute(text("INSERT INTO scanned VALUES (:id, 'alice', 'PUBLIC', 'UNDEF')"), {"id": f"alice_pub{i}"})
    for i in range(3):
        conn.execute(text("INSERT INTO scanned VALUES (:id, 'alice', 'PRIVATE', 'FEMALE')"), {"id": f"alice_f{i}"})
    for i in range(2):
        conn.execute(text("INSERT INTO scanned VALUES (:id, 'alice', 'PRIVATE', 'MALE')"), {"id": f"alice_m{i}"})
    conn.execute(text("INSERT INTO scanned VALUES ('alice_undef', 'alice', 'PRIVATE', 'UNDEF')"))
    conn.execute(text("INSERT INTO \"user\" VALUES ('alice_u1', 'alice')"))
    conn.execute(text("INSERT INTO \"user\" VALUES ('alice_u2', 'alice')"))

    # "bob": scanned but nothing else — scan-side counts should be 0 beyond
    # its one row.
    conn.execute(
        text("INSERT INTO entity VALUES ('bob', 'https://www.instagram.com/bob', 'PROFILE', 'PRIVATE', 'QUEUED', '2026-07-03T00:00:00', '2026-07-03T00:00:00')")
    )
    conn.execute(text("INSERT INTO scanned VALUES ('bob_x', 'bob', 'PRIVATE', 'FEMALE')"))


def real_checks() -> None:
    print("\n1. a known root returns the scan-side funnel only — no scraped/followed_est")
    result = entity_view.fetch("alice", engine=ENGINE)
    check("found", result is not None)
    check("url/type/access/status carried through", result["url"] == "https://www.instagram.com/alice" and result["type"] == "PROFILE" and result["status"] == "COMPLETED", str(result))
    check("scanned = 10", result["scanned"] == 10, str(result["scanned"]))
    check("private = 6 (public rows excluded)", result["private"] == 6, str(result["private"]))
    check("female = 3", result["female"] == 3, str(result["female"]))
    check("male = 2", result["male"] == 2, str(result["male"]))
    check("no scraped key", "scraped" not in result, str(result))
    check("no followed_est key", "followed_est" not in result, str(result))
    check("no in_scraped_folder/in_follow_queued_folder keys", "in_scraped_folder" not in result and "in_follow_queued_folder" not in result, str(result))

    print("\n2. an entity with nothing beyond one scan row reads correctly")
    bob = entity_view.fetch("bob", engine=ENGINE)
    check("scanned = 1, private = 1, female = 1", bob["scanned"] == 1 and bob["private"] == 1 and bob["female"] == 1, str(bob))

    print("\n3. an unknown root returns None, not an exception")
    check("ghost is None", entity_view.fetch("ghost", engine=ENGINE) is None)


real_checks()


# ------------------------------------------------------------------ live app

import ia_agent.app as app_module  # noqa: E402

app_module.build_specs = lambda: []
entity_view.postgres.get_engine = lambda: ENGINE
PORT = 8796
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

        print("\n4. GET /api/library/entity/{root}/yield, over REST")
        response = await client.get("/api/library/entity/alice/yield")
        body = response.json() if response.status_code == 200 else {}
        check("200 with the scan-side funnel, no scraped key", response.status_code == 200 and body.get("scanned") == 10 and "scraped" not in body, response.text)

        print("\n5. an unknown root is a 404 over REST, not a 500")
        missing = await client.get("/api/library/entity/ghost/yield")
        check("404", missing.status_code == 404, str(missing.status_code))


async def main() -> int:
    await live_checks()
    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    shutil.rmtree(SCRATCH, ignore_errors=True)
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
