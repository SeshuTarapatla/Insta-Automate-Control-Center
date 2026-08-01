"""Flow-event aggregation (CP 4.2) — content-addressed image caching (read the
bytes before a flow can unlink them), thumbnail generation, the replay ring,
and the REST/WS surface the app will eventually decode.

`ia_agent.images.IA_DIR`/`IMAGE_CACHE_DIR` are monkeypatched to a scratch
directory before anything runs, exactly like `test_scheduler.py` swaps
`build_specs` — this never touches the real `IA_DIR` or the real
`%LOCALAPPDATA%\\ia-agent\\cache`.
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
from ia_agent.events.bus import EventBus
from ia_agent.events.store import EventStore

OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


SCRATCH = Path(tempfile.mkdtemp(prefix="ia-agent-test-events-"))
FAKE_IA_DIR = SCRATCH / "ia_dir"
FAKE_CACHE_DIR = SCRATCH / "cache"
FAKE_IA_DIR.mkdir(parents=True)

images.IA_DIR = FAKE_IA_DIR
images.IMAGE_CACHE_DIR = FAKE_CACHE_DIR


def make_jpg(rel_path: str, size=(40, 20), color=(200, 30, 30)) -> Path:
    path = FAKE_IA_DIR / rel_path
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", size, color).save(path, "JPEG")
    return path


# ---------------------------------------------------------------- unit checks

def images_checks() -> None:
    print("\n1. cache() reads bytes and keys them by content hash")
    make_jpg("scanned/root/user1.jpg")
    key = images.cache("scanned/root/user1.jpg")
    check("a key is returned", bool(key), str(key))
    cached = images.original(key)
    check("the cached file exists", cached is not None and cached.exists())

    print("\n2. two identical images share one cache entry")
    make_jpg("scanned/root/user2.jpg")  # same size/color -> identical bytes
    key2 = images.cache("scanned/root/user2.jpg")
    check("identical content produces the same key", key2 == key, f"{key} vs {key2}")

    print("\n3. a different image gets a different key")
    make_jpg("scanned/root/user3.jpg", color=(10, 200, 10))
    key3 = images.cache("scanned/root/user3.jpg")
    check("different content produces a different key", key3 != key)

    print("\n4. cache() on a missing file returns None, not an exception")
    check("missing file -> None", images.cache("scanned/root/does-not-exist.jpg") is None)

    print("\n5. original() on an unknown key returns None")
    check("unknown key -> None", images.original("0" * 64) is None)

    print("\n6. thumbnail() resizes proportionally and is cached on disk")
    thumb = images.thumbnail(key, 20)
    check("a thumbnail path is returned", thumb is not None)
    with Image.open(thumb) as img:
        check("width matches the request", img.width == 20, str(img.size))
        check("height scaled proportionally (40x20 -> 20x10)", img.height == 10, str(img.size))
    check("thumbnail file is cached on disk", thumb.exists())

    print("\n7. thumbnail() on an unknown key returns None")
    check("unknown key -> None", images.thumbnail("0" * 64, 100) is None)


async def store_checks() -> None:
    print("\n8. EventStore.record() assigns seq/id, caches the image, and publishes")
    make_jpg("scanned/root/store-test.jpg", color=(1, 2, 3))
    bus = EventBus()
    published = []

    async def capture(channel, data):
        published.append((channel, data))

    bus.publish = capture
    store = EventStore(bus)
    entry = await store.record({
        "flow": "entity-scan", "kind": "scan.item", "image": "scanned/root/store-test.jpg",
    })
    check("seq starts at 1", entry["seq"] == 1)
    check("an id is assigned", bool(entry.get("id")))
    check("a ts is assigned", entry.get("ts") is not None)
    check("the image was cached and image_key set", bool(entry.get("image_key")))
    check("published on flow.events", published and published[0][0] == "flow.events")

    print("\n9. an event with no image gets image_key None, still records fine")
    entry2 = await store.record({"flow": "entity-scan", "kind": "scan.completed"})
    check("no image -> image_key is None", entry2.get("image_key") is None)
    check("seq keeps incrementing", entry2["seq"] == 2)

    print("\n10. tail(since) replays only newer entries")
    check("tail(None) returns both", len(store.tail(None)) == 2)
    check("tail(1) returns only the second", [e["seq"] for e in store.tail(1)] == [2])

    print("\n11. a caller-supplied id/ts is preserved rather than overwritten")
    entry3 = await store.record({"flow": "entity-scan", "kind": "x", "id": "caller-id", "ts": "2026-08-01T00:00:00Z"})
    check("caller id preserved", entry3["id"] == "caller-id")
    check("caller ts preserved", entry3["ts"] == "2026-08-01T00:00:00Z")


# ------------------------------------------------------------------ live app

import ia_agent.app as app_module  # noqa: E402

app_module.build_specs = lambda: []
PORT = 8793
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

        print("\n12. POST /api/events caches the image and returns id/seq/image_key")
        make_jpg("scanned/root/live1.jpg", color=(9, 8, 7))
        posted = (await client.post("/api/events", json={
            "flow": "entity-scan", "kind": "scan.item",
            "entity": "root", "subject": "live1", "image": "scanned/root/live1.jpg",
            "counters": {"added": 1, "scanned": 1},
        })).json()
        check("a seq is assigned", posted["seq"] >= 1, str(posted))
        check("an image_key is returned", bool(posted["image_key"]), str(posted))

        print("\n13. GET /api/images/{key} serves the real cached bytes")
        image_response = await client.get(f"/api/images/{posted['image_key']}")
        check("200 with jpeg content-type", image_response.status_code == 200
              and image_response.headers["content-type"] == "image/jpeg", str(image_response.status_code))
        check("served bytes are byte-identical to the source (a plain copy, no re-encode)",
              image_response.content == (FAKE_IA_DIR / "scanned/root/live1.jpg").read_bytes())

        print("\n14. GET /api/images/{key}/thumb?w= serves a resized image")
        thumb_response = await client.get(f"/api/images/{posted['image_key']}/thumb?w=20")
        check("200 with jpeg content-type", thumb_response.status_code == 200)
        with Image.open(__import__("io").BytesIO(thumb_response.content)) as thumb_img:
            check("thumbnail width is 20", thumb_img.width == 20, str(thumb_img.size))

        print("\n14b. a width below MIN_WIDTH is clamped rather than producing a 0px image")
        tiny_response = await client.get(f"/api/images/{posted['image_key']}/thumb?w=1")
        with Image.open(__import__("io").BytesIO(tiny_response.content)) as tiny_img:
            check("clamped up to MIN_WIDTH (16)", tiny_img.width == 16, str(tiny_img.size))

        print("\n15. GET /api/images/{unknown} is a 404")
        missing = await client.get("/api/images/" + "f" * 64)
        check("unknown key 404s", missing.status_code == 404)

        print("\n16. GET /api/events replays everything, since= trims the head")
        all_events = (await client.get("/api/events")).json()
        check("at least one event listed", len(all_events) >= 1, str(len(all_events)))
        cursor = all_events[0]["seq"]
        # Post one more event so since= has something to trim off.
        await client.post("/api/events", json={"flow": "entity-scan", "kind": "scan.completed"})
        trimmed = (await client.get(f"/api/events?since={cursor}")).json()
        check("since= excludes the cursor event itself", all(e["seq"] > cursor for e in trimmed), str(trimmed))

        print("\n17. an event whose image already vanished still records, with image_key null")
        vanished = (await client.post("/api/events", json={
            "flow": "entity-classify", "kind": "classify.access", "image": "gone/nowhere.jpg",
        })).json()
        check("no exception, event still recorded", vanished["seq"] > 0, str(vanished))
        check("image_key is null for a missing file", vanished["image_key"] is None)

        print("\n18. flow.events reaches a WS subscriber")
        async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws?token={token}") as ws:
            await client.post("/api/events", json={
                "flow": "entity-follow", "kind": "follow.result", "verdict": "FOLLOWED",
            })
            frame = None
            deadline = asyncio.get_running_loop().time() + 6
            while asyncio.get_running_loop().time() < deadline:
                try:
                    frame = json.loads(await asyncio.wait_for(ws.recv(), timeout=2))
                except asyncio.TimeoutError:
                    continue
                if frame.get("channel") == "flow.events" and frame["data"].get("verdict") == "FOLLOWED":
                    break
                frame = None
            check("the event arrives live over the socket", frame is not None)


async def main() -> int:
    images_checks()
    await store_checks()
    await live_checks()
    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    shutil.rmtree(SCRATCH, ignore_errors=True)
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
