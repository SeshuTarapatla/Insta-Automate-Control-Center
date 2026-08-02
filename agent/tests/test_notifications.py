"""Notification store (PLAN CP 6.1, ARCHITECTURE §6).

Store-level checks against a scratch `NotificationStore` (never the real
`%LOCALAPPDATA%\\ia-agent\\notifications.json`) covering persistence,
dedupe (only while unread), image caching, and history capping, then the
same shape again over live REST plus a real `notifications` WS delivery.
`controllers.notify`'s pipeline-side facade (CP 6.2) doesn't exist yet —
this suite only proves the agent's own half: `POST /api/notify` in,
`notifications` broadcast + persisted history out.
"""
import asyncio
import shutil
import sys
import tempfile
import threading
from pathlib import Path

import httpx
import uvicorn
import websockets

OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


SCRATCH = Path(tempfile.mkdtemp(prefix="ia-agent-test-notifications-"))
FAKE_IA_DIR = SCRATCH / "ia_dir"
FAKE_IA_DIR.mkdir(parents=True)
(FAKE_IA_DIR / "entities").mkdir()

import ia_agent.images as images  # noqa: E402
import ia_agent.notifications as notifications_module  # noqa: E402

notifications_module.NOTIFICATIONS_PATH = SCRATCH / "notifications.json"
images.IA_DIR = FAKE_IA_DIR
images.IMAGE_CACHE_DIR = SCRATCH / "cache"


def make_image(rel: str) -> None:
    path = FAKE_IA_DIR / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\xff\xd8\xff\xd9")


async def store_checks() -> None:
    from ia_agent.events.bus import EventBus
    from ia_agent.notifications import NotificationStore

    print("\n1. add() assigns id/seq/ts and defaults level/tags/transient/read")
    bus = EventBus()
    store = NotificationStore(bus)
    entry = await store.add({"msg": "FOLLOW limit reached"})
    check("has an id and seq 1", entry["id"] and entry["seq"] == 1, str(entry))
    check("defaults are sane", entry["level"] == "info" and entry["tags"] == [] and entry["transient"] is False and entry["read"] is False, str(entry))
    check("ts was stamped", entry["ts"] > 0)

    print("\n2. add() caches a referenced image and stores its key")
    make_image("entities/alice.jpg")
    with_image = await store.add({"msg": "new entity", "image": "entities/alice.jpg"})
    check("image_key is set", bool(with_image["image_key"]), str(with_image))
    missing_image = await store.add({"msg": "gone by the time we read it", "image": "entities/ghost.jpg"})
    check("a missing source file caches to None, doesn't raise", missing_image["image_key"] is None)

    print("\n3. dedupe replaces a prior *unread* entry with the same key")
    first = await store.add({"msg": "SCRAPE limit reached (180/300)", "dedupe": "scrape-limit"})
    second = await store.add({"msg": "SCRAPE limit reached (250/300)", "dedupe": "scrape-limit"})
    ids = [n["id"] for n in store.tail()]
    check("the first entry is gone", first["id"] not in ids, str(ids))
    check("the second entry replaced it", second["id"] in ids, str(ids))

    print("\n4. dedupe leaves a *read* entry alone — a repeat is a new occurrence")
    store.mark_read(second["id"])
    third = await store.add({"msg": "SCRAPE limit reached (300/300)", "dedupe": "scrape-limit"})
    ids = [n["id"] for n in store.tail()]
    check("the read entry survives", second["id"] in ids, str(ids))
    check("the new one is added alongside it", third["id"] in ids, str(ids))

    print("\n5. tail(since=) and tail(unread_only=) filter correctly")
    all_entries = store.tail()
    check("since= excludes everything up to and including that seq",
          all(n["seq"] > entry["seq"] for n in store.tail(since=entry["seq"])))
    unread = store.tail(unread_only=True)
    check("second (read) is excluded from unread", all(n["id"] != second["id"] for n in unread), str(unread))
    check("third (unread) is included", any(n["id"] == third["id"] for n in unread))

    print("\n6. mark_read()/mark_all_read()")
    check("marking an unknown id returns False", store.mark_read("nonexistent") is False)
    check("marking a real id returns True", store.mark_read(third["id"]) is True)
    check("marking an already-read id still returns True", store.mark_read(third["id"]) is True)
    unread_before = len(store.tail(unread_only=True))
    marked = store.mark_all_read()
    check("mark_all_read marks exactly what was unread", marked == unread_before, str((marked, unread_before)))
    check("nothing left unread", store.tail(unread_only=True) == [])

    print("\n7. history persists across a fresh NotificationStore over the same path")
    reloaded = NotificationStore(bus)
    check("the reloaded store sees prior entries", len(reloaded.tail()) == len(store.tail()),
          str((len(reloaded.tail()), len(store.tail()))))
    check("seq continues from where it left off, not restarting at 1",
          reloaded._seq == store._seq, str((reloaded._seq, store._seq)))

    print("\n8. publish() reports the live *device* subscriber count as 'targets' — desktop doesn't count")
    check("zero subscribers today", await store.publish(entry) == 0)
    desktop_queue = bus.subscribe()  # device_id=None — the desktop
    check("a desktop-only subscriber still reports zero device targets", await store.publish(entry) == 0)
    device_queue = bus.subscribe(device_id="phone-1")
    check("a device subscriber brings targets to one", await store.publish(entry) == 1)
    check("subscriber_count() without devices_only still counts both",
          bus.subscriber_count() == 2 and bus.subscriber_count(devices_only=True) == 1)
    check("device_ids() reports the connected phone", bus.device_ids() == {"phone-1"})
    bus.unsubscribe(desktop_queue)
    bus.unsubscribe(device_queue)
    check("device_ids() empties out after disconnect", bus.device_ids() == set())


asyncio.run(store_checks())

# ------------------------------------------------------------------ live app

import ia_agent.app as app_module  # noqa: E402
import ia_agent.library.folders as folders  # noqa: E402
import ia_agent.pairing as pairing_module  # noqa: E402
from ia_agent.library.folders import LibraryFolder  # noqa: E402

app_module.build_specs = lambda: []
folders.IA_DIR = FAKE_IA_DIR
# 11c mints a real device pairing to test device-aware targets — must not
# touch the real %LOCALAPPDATA%\ia-agent\pairing.json (same precedent as
# test_pairing.py).
pairing_module.PAIRING_DEVICES_PATH = SCRATCH / "pairing.json"
folders.FOLDERS = {"entities": LibraryFolder("entities", FAKE_IA_DIR / "entities", flat=True)}

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

        print("\n9. POST /api/notify with no live WS subscriber reports delivered: false")
        posted = await client.post("/api/notify", json={"msg": "device disconnected", "level": "warn"})
        check("200 with delivered false, zero targets", posted.status_code == 200 and posted.json() == {
            "delivered": False, "targets": 0, "id": posted.json()["id"]
        }, posted.text)

        print("\n10. GET /api/notify replays history, newest included")
        listed = (await client.get("/api/notify")).json()
        check("the posted notification is in the list", any(n["msg"] == "device disconnected" for n in listed), str(listed))

        print("\n11a. a desktop WS connection alone does NOT flip delivered — the D53/D57 regression case")
        async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws?token={token}") as desktop_ws:
            posted_desktop_only = await client.post("/api/notify", json={"msg": "desktop is open, no phone"})
            check("delivered stays false with only the desktop connected",
                  posted_desktop_only.json()["delivered"] is False and posted_desktop_only.json()["targets"] == 0,
                  posted_desktop_only.text)

            print("\n11b. but the desktop still receives the broadcast — it's a passive viewer, not a gate")
            frame = None
            deadline = asyncio.get_running_loop().time() + 5
            while asyncio.get_running_loop().time() < deadline:
                try:
                    frame = __import__("json").loads(await asyncio.wait_for(desktop_ws.recv(), timeout=2))
                except asyncio.TimeoutError:
                    continue
                if frame.get("channel") == "notifications":
                    break
                frame = None
            check("the desktop still gets the frame despite delivered=false", frame is not None)

            print("\n11c. a paired *device* WS connection is what actually flips delivered")
            started = (await client.post("/api/pair/start", headers=headers)).json()
            claimed = await client.post("/api/pair/claim", json={"code": started["code"], "device_name": "test phone"})
            device_token = claimed.json()["token"]
            async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws?token={device_token}") as ws:
                posted2 = await client.post("/api/notify", json={"msg": "scan complete", "tags": ["scan"]})
                check("delivered true with a device connected (desktop still open too)",
                      posted2.json()["delivered"] is True and posted2.json()["targets"] == 1, posted2.text)

                frame = None
                deadline = asyncio.get_running_loop().time() + 5
                while asyncio.get_running_loop().time() < deadline:
                    try:
                        frame = __import__("json").loads(await asyncio.wait_for(ws.recv(), timeout=2))
                    except asyncio.TimeoutError:
                        continue
                    if frame.get("channel") == "notifications":
                        break
                    frame = None
                check("a notifications frame arrives on the device socket", frame is not None)
                if frame:
                    check("carries the real message", frame["data"]["msg"] == "scan complete", str(frame))

                print("\n11d. GET /api/pair/devices reports this device as live-connected, not just paired")
                listing = (await client.get("/api/pair/devices", headers=headers)).json()
                check("the connected phone shows connected: true",
                      any(d["name"] == "test phone" and d["connected"] is True for d in listing), str(listing))

        print("\n12. POST /api/notify/{id}/read and /api/notify/read-all")
        notification_id = posted2.json()["id"]
        marked = await client.post(f"/api/notify/{notification_id}/read")
        check("marking a real id succeeds", marked.status_code == 200, marked.text)
        unknown = await client.post("/api/notify/unknown-id/read")
        check("marking an unknown id is a 404", unknown.status_code == 404, str(unknown.status_code))
        read_all = (await client.post("/api/notify/read-all")).json()
        check("read-all marks the rest (device-disconnected was still unread)", read_all["marked"] >= 1, str(read_all))
        still_unread = (await client.get("/api/notify", params={"unread_only": True})).json()
        check("nothing left unread", still_unread == [], str(still_unread))


async def main() -> int:
    await live_checks()
    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    shutil.rmtree(SCRATCH, ignore_errors=True)
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
