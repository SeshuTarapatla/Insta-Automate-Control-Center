"""Library API (CP 5.1) — the folder taxonomy, the cached-counts store,
watcher-driven invalidation, and the REST/WS surface the app will eventually
decode.

`ia_agent.library.folders.IA_DIR`/`FOLDERS` and `ia_agent.images.IA_DIR`/
`IMAGE_CACHE_DIR` are monkeypatched to a scratch directory before anything
runs, exactly like `test_events.py` swaps `images.IA_DIR` — this never
touches the real `IA_DIR` or the real `%LOCALAPPDATA%\\ia-agent\\cache`.

`folders_checks()`/`counts_checks()` run and finish their filesystem
mutations *before* the live app is created below — `LibraryCounts.seed()`
scans the real (scratch) tree on startup, so if fixture setup raced with
that background scan the live-app assertions further down would be
timing-dependent. Sequencing fixture setup first, on the same thread, before
the app object (and its startup thread) even exists removes the race.
"""
import asyncio
import json
import shutil
import sys
import tempfile
import threading
from pathlib import Path

import httpx
import uvicorn
import websockets
from PIL import Image

import ia_agent.images as images
import ia_agent.library.folders as folders
from ia_agent.library.counts import LibraryCounts
from ia_agent.library.folders import LibraryFolder

OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


SCRATCH = Path(tempfile.mkdtemp(prefix="ia-agent-test-library-"))
FAKE_IA_DIR = SCRATCH / "ia_dir"
FAKE_CACHE_DIR = SCRATCH / "cache"
FAKE_IA_DIR.mkdir(parents=True)

images.IA_DIR = FAKE_IA_DIR
images.IMAGE_CACHE_DIR = FAKE_CACHE_DIR
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


def make_jpg(rel_path: str, size=(40, 20), color=(200, 30, 30)) -> Path:
    path = FAKE_IA_DIR / rel_path
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", size, color).save(path, "JPEG")
    return path


# ---------------------------------------------------------------- folders.py

def folders_checks() -> None:
    print("\n1. resolve() maps a real path back to (folder, root)")
    make_jpg("scrape_queued/alice/pic1.jpg")
    resolved = folders.resolve(FAKE_IA_DIR / "scrape_queued/alice/pic1.jpg")
    check("folder/root resolved", resolved == ("scrape_queued", "alice"), str(resolved))

    print("\n2. resolve() on the flat entities/ folder has no root")
    make_jpg("entities/alice.jpg")
    resolved_flat = folders.resolve(FAKE_IA_DIR / "entities/alice.jpg")
    check("flat folder resolves with root=None", resolved_flat == ("entities", None), str(resolved_flat))

    print("\n3. resolve() rejects paths outside the known folders")
    check(".thumbs is not a library folder", folders.resolve(FAKE_IA_DIR / ".thumbs/x.jpg") is None)
    check("config.env is not a library folder", folders.resolve(FAKE_IA_DIR / "config.env") is None)
    check("a path outside IA_DIR entirely", folders.resolve(FAKE_IA_DIR.parent / "outside.jpg") is None)


# ----------------------------------------------------------------- counts.py

def counts_checks() -> None:
    print("\n4. seed() counts a flat folder and per-root folders correctly")
    # alice already has pic1.jpg from folders_checks() above.
    make_jpg("entities/bob.jpg")
    make_jpg("entities/carol.jpg")
    make_jpg("scrape_queued/alice/pic2.jpg")
    make_jpg("scrape_queued/dave/pic1.jpg")
    make_jpg("scrape_queued/dave/pic2.jpg")
    counts = LibraryCounts()
    counts.seed()
    by_name = {f["name"]: f for f in counts.folders()}
    check("entities total is 3 (alice+bob+carol)", by_name["entities"]["total"] == 3, str(by_name["entities"]))
    check("entities folder reports flat=True, entities=0", by_name["entities"]["flat"] is True and by_name["entities"]["entities"] == 0)
    check("scrape_queued total sums both roots (alice=2, dave=2)",
          by_name["scrape_queued"]["total"] == 4, str(by_name["scrape_queued"]))
    check("scrape_queued has 2 distinct entities", by_name["scrape_queued"]["entities"] == 2)
    entity_rows = {row["root"]: row["count"] for row in counts.entities("scrape_queued")}
    check("alice has 2 files, dave has 2", entity_rows == {"alice": 2, "dave": 2}, str(entity_rows))

    print("\n5. touch() recomputes exactly one (folder, root) pair")
    make_jpg("scrape_queued/alice/pic3.jpg")
    result = counts.touch("scrape_queued", "alice")
    check("touch reports the fresh count", result == {"folder": "scrape_queued", "root": "alice", "count": 3}, str(result))
    dave_count = {r["root"]: r["count"] for r in counts.entities("scrape_queued")}["dave"]
    check("dave is untouched", dave_count == 2, str(dave_count))

    print("\n6. a root whose files are all removed disappears from entities()")
    (FAKE_IA_DIR / "scrape_queued/alice/pic1.jpg").unlink()
    (FAKE_IA_DIR / "scrape_queued/alice/pic2.jpg").unlink()
    (FAKE_IA_DIR / "scrape_queued/alice/pic3.jpg").unlink()
    result2 = counts.touch("scrape_queued", "alice")
    check("touch reports count 0", result2["count"] == 0, str(result2))
    remaining = {row["root"] for row in counts.entities("scrape_queued")}
    check("alice dropped, dave remains", remaining == {"dave"}, str(remaining))

    print("\n7. touch() on the flat entities/ folder ignores root and recounts the whole folder")
    make_jpg("entities/erin.jpg")
    result3 = counts.touch("entities", None)
    check("flat total recomputed to 4", result3 == {"folder": "entities", "root": None, "count": 4}, str(result3))

    print("\n8. entities() on an unknown or flat folder raises rather than silently returning []")
    raised_unknown = raised_flat = False
    try:
        counts.entities("nope")
    except KeyError:
        raised_unknown = True
    try:
        counts.entities("entities")
    except ValueError:
        raised_flat = True
    check("unknown folder raises KeyError", raised_unknown)
    check("flat folder raises ValueError", raised_flat)


folders_checks()
counts_checks()

# At this point scrape_queued/dave has exactly 2 files (pic1.jpg, pic2.jpg)
# and alice has been fully drained — the live app's own seed() below will
# scan this exact, now-stable state.


# ------------------------------------------------------------------ live app

import ia_agent.app as app_module  # noqa: E402

app_module.build_specs = lambda: []
PORT = 8795
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

        print("\n9. GET /api/library/folders lists all seven, seeded from the scratch tree")
        folder_list = (await client.get("/api/library/folders")).json()
        names = {f["name"] for f in folder_list}
        check("all seven folders present", names == set(folders.FOLDERS), str(names))
        by_name = {f["name"]: f for f in folder_list}
        check("scrape_queued total matches disk (dave=2)", by_name["scrape_queued"]["total"] == 2, str(by_name["scrape_queued"]))

        print("\n10. GET /api/library/entities?folder= drills into one folder")
        entity_list = (await client.get("/api/library/entities?folder=scrape_queued")).json()
        check("dave listed with count 2", entity_list == [{"root": "dave", "count": 2}], str(entity_list))

        print("\n10b. GET /api/library/entities?folder=entities (flat) is a 400")
        flat_entities = await client.get("/api/library/entities?folder=entities")
        check("flat folder rejected with 400", flat_entities.status_code == 400)

        print("\n11. GET /api/library/images lists real filenames with offset/limit")
        images_page = (await client.get("/api/library/images?folder=scrape_queued&entity=dave&limit=1")).json()
        check("total is 2, one returned", images_page["total"] == 2 and len(images_page["images"]) == 1, str(images_page))
        second_page = (await client.get("/api/library/images?folder=scrape_queued&entity=dave&offset=1&limit=1")).json()
        check("offset=1 returns the other file", second_page["images"][0]["name"] != images_page["images"][0]["name"])

        print("\n11b. GET /api/library/images on a nonexistent entity returns an empty list, not an error")
        empty_page = (await client.get("/api/library/images?folder=scrape_queued&entity=nobody")).json()
        check("empty, no 500", empty_page == {"total": 0, "offset": 0, "images": []}, str(empty_page))

        print("\n12. GET /api/library/image serves the real bytes")
        rel_path = images_page["images"][0]["path"]
        image_response = await client.get(f"/api/library/image?path={rel_path}")
        check("200 jpeg", image_response.status_code == 200 and image_response.headers["content-type"] == "image/jpeg")
        check("byte-identical to source", image_response.content == (FAKE_IA_DIR / rel_path).read_bytes())

        print("\n13. GET /api/library/image/thumb serves a resized image")
        thumb_response = await client.get(f"/api/library/image/thumb?path={rel_path}&w=20")
        with Image.open(__import__("io").BytesIO(thumb_response.content)) as thumb_img:
            check("thumbnail width is 20", thumb_img.width == 20, str(thumb_img.size))

        print("\n14. path traversal is rejected with 400, not served")
        traversal = await client.get("/api/library/image?path=../../config.env")
        check("traversal outside a library folder is a 400", traversal.status_code == 400, str(traversal.status_code))
        top_level = await client.get("/api/library/image?path=config.env")
        check("a real top-level file that isn't in a library folder is also a 400", top_level.status_code == 400)

        print("\n15. GET /api/library/image on a missing file is a 404")
        missing = await client.get("/api/library/image?path=scrape_queued/dave/does-not-exist.jpg")
        check("missing file 404s", missing.status_code == 404)

        print("\n16. library.changes reaches a WS subscriber when a real file is added")
        async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws?token={token}") as ws:
            make_jpg("scanned/frank/newpic.jpg")
            frame = None
            deadline = asyncio.get_running_loop().time() + 6
            while asyncio.get_running_loop().time() < deadline:
                try:
                    frame = json.loads(await asyncio.wait_for(ws.recv(), timeout=2))
                except asyncio.TimeoutError:
                    continue
                if frame.get("channel") == "library.changes":
                    changes = frame["data"]["changes"]
                    if any(c["folder"] == "scanned" and c["root"] == "frank" for c in changes):
                        break
                frame = None
            check("the watcher-driven change arrives live over the socket", frame is not None)
            if frame:
                match = next(c for c in frame["data"]["changes"] if c["folder"] == "scanned" and c["root"] == "frank")
                check("the pushed count reflects the new file", match["count"] == 1, str(match))


async def main() -> int:
    await live_checks()
    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    shutil.rmtree(SCRATCH, ignore_errors=True)
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
