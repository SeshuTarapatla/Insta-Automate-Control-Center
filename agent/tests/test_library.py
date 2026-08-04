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
import ia_agent.library.ops as ops
import ia_agent.library.settings as library_settings
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
library_settings.LIBRARY_SETTINGS_PATH = SCRATCH / "library.json"


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


# ------------------------------------------------------------------ settings.py

def settings_checks() -> None:
    print("\n9. default move targets encode the two real human-review steps, identity elsewhere")
    defaults = library_settings.load()
    check("gender_valid -> scrape_queued by default", defaults["gender_valid"] == "scrape_queued", str(defaults))
    check("scraped -> follow_queued by default", defaults["scraped"] == "follow_queued")
    check("scanned defaults to itself", defaults["scanned"] == "scanned")
    check("entities defaults to itself", defaults["entities"] == "entities")

    print("\n10. set_move_target persists and move_target() picks it up; other folders unaffected")
    library_settings.set_move_target("scanned", "gender_invalid")
    check("move_target reflects the new mapping", library_settings.move_target("scanned") == "gender_invalid")
    check("unrelated folder keeps its default", library_settings.move_target("scraped") == "follow_queued")
    library_settings.set_move_target("scanned", "scanned")  # restore identity for ops_checks() below
    check("restored to identity", library_settings.move_target("scanned") == "scanned")

    print("\n11. set_move_target rejects unknown folder names on either side")
    raised_source = raised_target = False
    try:
        library_settings.set_move_target("nope", "scanned")
    except KeyError:
        raised_source = True
    try:
        library_settings.set_move_target("scanned", "nope")
    except KeyError:
        raised_target = True
    check("unknown source folder raises", raised_source)
    check("unknown target folder raises", raised_target)


# ------------------------------------------------------------------------ ops.py

def ops_checks() -> None:
    print("\n12. apply(): identity-mapped folder keeps the selection in place, trashes the rest")
    make_jpg("scanned/erin/keep.jpg")
    make_jpg("scanned/erin/toss.jpg")
    result = ops.apply("scanned", "erin", ["keep.jpg"])
    check("kept file is still there", (FAKE_IA_DIR / "scanned/erin/keep.jpg").exists())
    check("unselected file is gone", not (FAKE_IA_DIR / "scanned/erin/toss.jpg").exists())
    check(
        "report shape",
        result["moved"] == ["keep.jpg"] and result["trashed"] == ["toss.jpg"] and result["target"] == "scanned",
        str(result),
    )

    print("\n13. apply(): a real promotion moves the selected file, preserving <root>/<name>")
    make_jpg("gender_valid/frank/a.jpg")
    make_jpg("gender_valid/frank/b.jpg")
    result2 = ops.apply("gender_valid", "frank", ["a.jpg"])
    check("a.jpg landed at scrape_queued/frank/a.jpg", (FAKE_IA_DIR / "scrape_queued/frank/a.jpg").exists())
    check("a.jpg is gone from gender_valid", not (FAKE_IA_DIR / "gender_valid/frank/a.jpg").exists())
    check(
        "b.jpg (unselected) was trashed, not promoted",
        not (FAKE_IA_DIR / "gender_valid/frank/b.jpg").exists()
        and not (FAKE_IA_DIR / "scrape_queued/frank/b.jpg").exists(),
    )
    check("report names the real target", result2["target"] == "scrape_queued", str(result2))

    print("\n14. apply() rejects a selected filename that isn't actually present, before moving anything")
    make_jpg("scanned/erin/keep.jpg")  # re-add so a false-positive move would be observable
    raised = False
    try:
        ops.apply("scanned", "erin", ["ghost.jpg"])
    except ops.LibraryOpError:
        raised = True
    check("unknown selection raises LibraryOpError", raised)
    check("nothing in the directory moved as a side effect", (FAKE_IA_DIR / "scanned/erin/keep.jpg").exists())

    print("\n15. delete() trashes an explicit set of IA_DIR-relative paths regardless of folder/entity")
    make_jpg("scrape_queued/frank/c.jpg")
    result3 = ops.delete(["scrape_queued/frank/a.jpg", "scrape_queued/frank/c.jpg"])
    check(
        "both reported deleted",
        set(result3["deleted"]) == {"scrape_queued/frank/a.jpg", "scrape_queued/frank/c.jpg"},
        str(result3),
    )
    check(
        "both gone from disk",
        not (FAKE_IA_DIR / "scrape_queued/frank/a.jpg").exists()
        and not (FAKE_IA_DIR / "scrape_queued/frank/c.jpg").exists(),
    )

    print("\n16. delete() reports paths outside the library folders as errors, never raises")
    result4 = ops.delete(["../outside.jpg", "config.env", "scrape_queued/frank/does-not-exist.jpg"])
    check(
        "all three reported as errors, nothing deleted",
        len(result4["errors"]) == 3 and result4["deleted"] == [],
        str(result4),
    )

    print("\n16b. move(): relocates exactly the named file, nothing else in either directory")
    make_jpg("scrape_queued/henry/p1.jpg")
    make_jpg("scrape_queued/henry/untouched.jpg")
    result5 = ops.move([{"from": "scrape_queued/henry/p1.jpg", "to": "follow_queued/henry/p1.jpg"}])
    check("reported under moved", result5 == {"moved": ["follow_queued/henry/p1.jpg"], "already_synced": [], "errors": []}, str(result5))
    check("landed at the new path", (FAKE_IA_DIR / "follow_queued/henry/p1.jpg").exists())
    check("gone from the old path", not (FAKE_IA_DIR / "scrape_queued/henry/p1.jpg").exists())
    check("the sibling file was never touched", (FAKE_IA_DIR / "scrape_queued/henry/untouched.jpg").exists())

    print("\n16c. move() is idempotent against a Syncthing-catch-up race: dest already there")
    make_jpg("scrape_queued/henry/p2.jpg")
    make_jpg("follow_queued/henry/p2.jpg")  # simulates Syncthing having already delivered this one
    result6 = ops.move([{"from": "scrape_queued/henry/p2.jpg", "to": "follow_queued/henry/p2.jpg"}])
    check("reported under already_synced, not moved", result6 == {"moved": [], "already_synced": ["follow_queued/henry/p2.jpg"], "errors": []}, str(result6))
    check("the stray source copy was trashed, not overwritten onto", not (FAKE_IA_DIR / "scrape_queued/henry/p2.jpg").exists())
    check("the destination is untouched", (FAKE_IA_DIR / "follow_queued/henry/p2.jpg").exists())

    print("\n16d. move(): neither side exists is a reported error, not a crash")
    result7 = ops.move([{"from": "scrape_queued/henry/ghost.jpg", "to": "follow_queued/henry/ghost.jpg"}])
    check("one error, nothing moved or already_synced", len(result7["errors"]) == 1 and not result7["moved"] and not result7["already_synced"], str(result7))

    print("\n16e. move(): a traversal attempt is a reported error, never raises or touches disk")
    result8 = ops.move([{"from": "../outside.jpg", "to": "follow_queued/henry/x.jpg"}])
    check("reported as an error", len(result8["errors"]) == 1, str(result8))
    check("nothing created at the destination", not (FAKE_IA_DIR / "follow_queued/henry/x.jpg").exists())

    print("\n16f. move(): one bad item in a batch doesn't block the rest")
    make_jpg("scrape_queued/henry/p3.jpg")
    result9 = ops.move([
        {"from": "scrape_queued/henry/p3.jpg", "to": "follow_queued/henry/p3.jpg"},
        {"from": "scrape_queued/henry/ghost2.jpg", "to": "follow_queued/henry/ghost2.jpg"},
    ])
    check("the good item still moved", result9["moved"] == ["follow_queued/henry/p3.jpg"], str(result9))
    check("the bad item is the one error", len(result9["errors"]) == 1, str(result9))

    # henry/follow_queued's henry only exist for the checks above — clear
    # them so the live app's seed() below sees the same stable state the
    # comment ahead of it already documents (scrape_queued: dave only, 2 files).
    shutil.rmtree(FAKE_IA_DIR / "scrape_queued/henry", ignore_errors=True)
    shutil.rmtree(FAKE_IA_DIR / "follow_queued/henry", ignore_errors=True)


folders_checks()
counts_checks()
settings_checks()
ops_checks()

# scanned/erin now holds exactly keep.jpg; gender_valid/frank is fully drained;
# scrape_queued/frank holds exactly b.jpg (trashed) minus a.jpg/c.jpg (deleted
# above) — i.e. empty; scrape_queued/dave (from counts_checks) is unaffected
# at 2 files. The live app's own seed() below scans this exact, now-stable
# state.


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

        print("\n17. GET /api/library/folders lists all seven, seeded from the scratch tree")
        folder_list = (await client.get("/api/library/folders")).json()
        names = {f["name"] for f in folder_list}
        check("all seven folders present", names == set(folders.FOLDERS), str(names))
        by_name = {f["name"]: f for f in folder_list}
        check("scrape_queued total matches disk (dave=2)", by_name["scrape_queued"]["total"] == 2, str(by_name["scrape_queued"]))

        print("\n18. GET /api/library/entities?folder= drills into one folder")
        entity_list = (await client.get("/api/library/entities?folder=scrape_queued")).json()
        check("dave listed with count 2", entity_list == [{"root": "dave", "count": 2}], str(entity_list))

        print("\n18b. GET /api/library/entities?folder=entities (flat) is a 400")
        flat_entities = await client.get("/api/library/entities?folder=entities")
        check("flat folder rejected with 400", flat_entities.status_code == 400)

        print("\n19. GET /api/library/images lists real filenames with offset/limit")
        images_page = (await client.get("/api/library/images?folder=scrape_queued&entity=dave&limit=1")).json()
        check("total is 2, one returned", images_page["total"] == 2 and len(images_page["images"]) == 1, str(images_page))
        second_page = (await client.get("/api/library/images?folder=scrape_queued&entity=dave&offset=1&limit=1")).json()
        check("offset=1 returns the other file", second_page["images"][0]["name"] != images_page["images"][0]["name"])

        print("\n19b. GET /api/library/images on a nonexistent entity returns an empty list, not an error")
        empty_page = (await client.get("/api/library/images?folder=scrape_queued&entity=nobody")).json()
        check("empty, no 500", empty_page == {"total": 0, "offset": 0, "images": []}, str(empty_page))

        print("\n20. GET /api/library/image serves the real bytes")
        rel_path = images_page["images"][0]["path"]
        image_response = await client.get(f"/api/library/image?path={rel_path}")
        check("200 jpeg", image_response.status_code == 200 and image_response.headers["content-type"] == "image/jpeg")
        check("byte-identical to source", image_response.content == (FAKE_IA_DIR / rel_path).read_bytes())

        print("\n21. GET /api/library/image/thumb serves a resized image")
        thumb_response = await client.get(f"/api/library/image/thumb?path={rel_path}&w=20")
        with Image.open(__import__("io").BytesIO(thumb_response.content)) as thumb_img:
            check("thumbnail width is 20", thumb_img.width == 20, str(thumb_img.size))

        print("\n22. path traversal is rejected with 400, not served")
        traversal = await client.get("/api/library/image?path=../../config.env")
        check("traversal outside a library folder is a 400", traversal.status_code == 400, str(traversal.status_code))
        top_level = await client.get("/api/library/image?path=config.env")
        check("a real top-level file that isn't in a library folder is also a 400", top_level.status_code == 400)

        print("\n23. GET /api/library/image on a missing file is a 404")
        missing = await client.get("/api/library/image?path=scrape_queued/dave/does-not-exist.jpg")
        check("missing file 404s", missing.status_code == 404)

        print("\n24. library.changes reaches a WS subscriber when a real file is added")
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

        print("\n25. GET /api/library/move-targets reports the settings.py defaults")
        targets = (await client.get("/api/library/move-targets")).json()
        check(
            "gender_valid/scraped show the real pipeline promotions, scanned is identity",
            targets["gender_valid"] == "scrape_queued" and targets["scraped"] == "follow_queued" and targets["scanned"] == "scanned",
            str(targets),
        )

        print("\n26. PATCH /api/library/move-targets/{folder} changes one mapping, GET reflects it")
        patched = await client.patch("/api/library/move-targets/scanned", json={"target": "gender_invalid"})
        check("200 with the new mapping", patched.status_code == 200 and patched.json()["scanned"] == "gender_invalid")
        refetched = (await client.get("/api/library/move-targets")).json()
        check("persisted across a fresh GET", refetched["scanned"] == "gender_invalid", str(refetched))
        restore = await client.patch("/api/library/move-targets/scanned", json={"target": "scanned"})
        check("restored to identity for later checks", restore.json()["scanned"] == "scanned")

        print("\n26b. PATCH /api/library/move-targets/{folder} 404s on an unknown folder on either side")
        bad_source = await client.patch("/api/library/move-targets/nope", json={"target": "scanned"})
        bad_target = await client.patch("/api/library/move-targets/scanned", json={"target": "nope"})
        check("unknown source folder is a 404", bad_source.status_code == 404)
        check("unknown target folder is a 404", bad_target.status_code == 404)

        print("\n27. POST /api/library/apply promotes the selected file and trashes the rest, over REST")
        make_jpg("gender_valid/grace/x.jpg")
        make_jpg("gender_valid/grace/y.jpg")
        applied = await client.post(
            "/api/library/apply", json={"folder": "gender_valid", "entity": "grace", "selected": ["x.jpg"]}
        )
        check("200 with the real target", applied.status_code == 200 and applied.json()["target"] == "scrape_queued", applied.text)
        check("x.jpg promoted to scrape_queued/grace", (FAKE_IA_DIR / "scrape_queued/grace/x.jpg").exists())
        check(
            "y.jpg trashed, not promoted",
            not (FAKE_IA_DIR / "gender_valid/grace/y.jpg").exists() and not (FAKE_IA_DIR / "scrape_queued/grace/y.jpg").exists(),
        )

        print("\n27b. POST /api/library/apply with a selection that isn't present is a 400, over REST")
        rejected = await client.post(
            "/api/library/apply", json={"folder": "gender_valid", "entity": "grace", "selected": ["ghost.jpg"]}
        )
        check("400, not 500", rejected.status_code == 400, str(rejected.status_code))

        print("\n28. POST /api/library/delete trashes an explicit path list, over REST")
        make_jpg("scrape_queued/grace/z.jpg")
        deleted_resp = await client.post("/api/library/delete", json={"paths": ["scrape_queued/grace/z.jpg"]})
        deleted_body = deleted_resp.json()
        check(
            "reports the deletion, no errors",
            deleted_body == {"deleted": ["scrape_queued/grace/z.jpg"], "errors": []},
            str(deleted_body),
        )
        check("gone from disk", not (FAKE_IA_DIR / "scrape_queued/grace/z.jpg").exists())

        print("\n29. POST /api/library/move relocates an explicit path pair, over REST")
        make_jpg("scrape_queued/iris/q1.jpg")
        move_resp = await client.post(
            "/api/library/move", json={"moves": [{"from": "scrape_queued/iris/q1.jpg", "to": "follow_queued/iris/q1.jpg"}]}
        )
        move_body = move_resp.json()
        check(
            "200, reported under moved",
            move_resp.status_code == 200 and move_body == {"moved": ["follow_queued/iris/q1.jpg"], "already_synced": [], "errors": []},
            str(move_body),
        )
        check("landed at the new path", (FAKE_IA_DIR / "follow_queued/iris/q1.jpg").exists())
        check("gone from the old path", not (FAKE_IA_DIR / "scrape_queued/iris/q1.jpg").exists())

        print("\n29b. POST /api/library/move is idempotent when the destination already exists, over REST")
        make_jpg("scrape_queued/iris/q2.jpg")
        make_jpg("follow_queued/iris/q2.jpg")
        move_resp2 = await client.post(
            "/api/library/move", json={"moves": [{"from": "scrape_queued/iris/q2.jpg", "to": "follow_queued/iris/q2.jpg"}]}
        )
        move_body2 = move_resp2.json()
        check(
            "reported under already_synced, no error",
            move_body2 == {"moved": [], "already_synced": ["follow_queued/iris/q2.jpg"], "errors": []},
            str(move_body2),
        )
        check("stray source trashed", not (FAKE_IA_DIR / "scrape_queued/iris/q2.jpg").exists())


async def main() -> int:
    await live_checks()
    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    shutil.rmtree(SCRATCH, ignore_errors=True)
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
