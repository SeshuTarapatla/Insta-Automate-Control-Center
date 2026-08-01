"""Entity-view funnel (CP 5.4) — `entity_view.fetch()` against a scratch
SQLite engine standing in for Postgres (raw `text()` SQL only, no ORM models,
so the same statements run against either dialect — see D?? for why
`sum(CASE WHEN ...)` was used instead of Postgres's `FILTER` clause) plus a
real `LibraryCounts` seeded from a scratch `IA_DIR`, then the same thing
again over the live REST surface with `entity_view.postgres.get_engine`
monkeypatched to the same fixture engine. Never touches the real Postgres
database or the real `IA_DIR`.
"""
import asyncio
import shutil
import sys
import tempfile
import threading
from pathlib import Path

import httpx
import uvicorn
from PIL import Image
from sqlalchemy import create_engine, text
from sqlalchemy.pool import StaticPool

import ia_agent.library.entity_view as entity_view
import ia_agent.library.folders as folders
from ia_agent.library.counts import LibraryCounts
from ia_agent.library.folders import LibraryFolder

OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


SCRATCH = Path(tempfile.mkdtemp(prefix="ia-agent-test-entity-view-"))
FAKE_IA_DIR = SCRATCH / "ia_dir"
FAKE_IA_DIR.mkdir(parents=True)

folders.IA_DIR = FAKE_IA_DIR
folders.FOLDERS = {
    "entities": LibraryFolder("entities", FAKE_IA_DIR / "entities", flat=True),
    "scanned": LibraryFolder("scanned", FAKE_IA_DIR / "scanned", flat=False),
    "gender_valid": LibraryFolder("gender_valid", FAKE_IA_DIR / "gender_valid", flat=False),
    "gender_invalid": LibraryFolder("gender_invalid", FAKE_IA_DIR / "gender_invalid", flat=False),
    "scrape_queued": LibraryFolder("scrape_queued", FAKE_IA_DIR / "scrape_queued", flat=False),
    "scraped": LibraryFolder("scraped", FAKE_IA_DIR / "scraped", flat=False),
    "follow_queued": LibraryFolder("follow_queued", FAKE_IA_DIR / "follow_queued", flat=False),
}


def make_jpg(rel_path: str) -> Path:
    path = FAKE_IA_DIR / rel_path
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (10, 10), (10, 20, 30)).save(path, "JPEG")
    return path


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
    conn.execute(text('CREATE TABLE "user" (id TEXT PRIMARY KEY, root TEXT)'))

    # "alice": a full funnel — 10 scanned, 6 private, 3 female (the only ones
    # ever gender-classified — access=PUBLIC rows never reach the classifier),
    # 2 scraped. One of the two scraped users is still sitting in scraped/
    # (not yet reviewed), the other has been promoted to follow_queued/ and
    # already processed by entity_follow (gone from disk on both sides) — so
    # followed_est should read 1, not 2.
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

    # "bob": scanned but nothing scraped yet — scraped/followed should both be 0.
    conn.execute(
        text("INSERT INTO entity VALUES ('bob', 'https://www.instagram.com/bob', 'PROFILE', 'PRIVATE', 'QUEUED', '2026-07-03T00:00:00', '2026-07-03T00:00:00')")
    )
    conn.execute(text("INSERT INTO scanned VALUES ('bob_x', 'bob', 'PRIVATE', 'FEMALE')"))

make_jpg("scraped/alice/alice_u1.jpg")  # still awaiting human review


counts = LibraryCounts()
counts.seed()


def real_checks() -> None:
    print("\n1. a known root returns the full DB-backed funnel, folded with real folder counts")
    result = entity_view.fetch("alice", counts, engine=ENGINE)
    check("found", result is not None)
    check("url/type/access/status carried through", result["url"] == "https://www.instagram.com/alice" and result["type"] == "PROFILE" and result["status"] == "COMPLETED", str(result))
    check("scanned = 10", result["scanned"] == 10, str(result["scanned"]))
    check("private = 6 (public rows excluded)", result["private"] == 6, str(result["private"]))
    check("female = 3", result["female"] == 3, str(result["female"]))
    check("male = 2", result["male"] == 2, str(result["male"]))
    check("scraped = 2 (real user rows)", result["scraped"] == 2, str(result["scraped"]))
    check("in_scraped_folder = 1 (alice_u1.jpg on disk)", result["in_scraped_folder"] == 1, str(result["in_scraped_folder"]))
    check("in_follow_queued_folder = 0 (nothing there)", result["in_follow_queued_folder"] == 0)
    check("followed_est = 1 (2 scraped - 1 still pending review)", result["followed_est"] == 1, str(result["followed_est"]))

    print("\n2. an entity with nothing scraped yet reads all-zero for that half of the funnel")
    bob = entity_view.fetch("bob", counts, engine=ENGINE)
    check("scanned = 1, private = 1, female = 1", bob["scanned"] == 1 and bob["private"] == 1 and bob["female"] == 1, str(bob))
    check("scraped = 0, followed_est = 0", bob["scraped"] == 0 and bob["followed_est"] == 0, str(bob))

    print("\n3. an unknown root returns None, not an exception")
    check("ghost is None", entity_view.fetch("ghost", counts, engine=ENGINE) is None)

    print("\n4. followed_est never goes negative even if folder counts somehow exceed scraped")
    # A root with 1 scraped user but 2 files still sitting in scraped/ — an
    # inconsistent state that should never happen live, but the formula must
    # not report a negative "followed" if it ever does.
    with ENGINE.begin() as conn:
        conn.execute(text("INSERT INTO entity VALUES ('carol', 'https://www.instagram.com/carol', 'PROFILE', 'PRIVATE', 'QUEUED', '2026-07-04T00:00:00', '2026-07-04T00:00:00')"))
        conn.execute(text("INSERT INTO \"user\" VALUES ('carol_u1', 'carol')"))
    make_jpg("scraped/carol/a.jpg")
    make_jpg("scraped/carol/b.jpg")
    counts.touch("scraped", "carol")
    carol = entity_view.fetch("carol", counts, engine=ENGINE)
    check("followed_est clamped at 0, not -1", carol["followed_est"] == 0, str(carol["followed_est"]))


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

        print("\n5. GET /api/library/entity/{root}/yield, over REST")
        response = await client.get("/api/library/entity/alice/yield")
        check("200 with the funnel", response.status_code == 200 and response.json()["scraped"] == 2, response.text)

        print("\n6. an unknown root is a 404 over REST, not a 500")
        missing = await client.get("/api/library/entity/ghost/yield")
        check("404", missing.status_code == 404, str(missing.status_code))


async def main() -> int:
    await live_checks()
    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    shutil.rmtree(SCRATCH, ignore_errors=True)
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
