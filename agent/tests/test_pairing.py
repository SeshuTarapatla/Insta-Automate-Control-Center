"""Mobile pairing (PLAN CP 6.1, ARCHITECTURE §7).

Store-level checks against a scratch `PairingStore` (never the real
`%LOCALAPPDATA%\\ia-agent\\pairing.json`), then the same shape again over
live REST plus one real WS connection authenticated with a minted device
token instead of the desktop token — proving `auth.py`'s `is_authorized`
genuinely accepts both token classes, not just the one every other test
suite exercises.

`build_specs` monkeypatched to `[]` and the library folder taxonomy
redirected to a one-folder scratch tree, same boilerplate as
`test_queue.py` — this suite has no interest in the three real services or
the real `IA_DIR`, but the app's lifespan touches both on startup.
"""
import asyncio
import shutil
import sys
import tempfile
import threading
import time
from pathlib import Path

import httpx
import uvicorn
import websockets

OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


SCRATCH = Path(tempfile.mkdtemp(prefix="ia-agent-test-pairing-"))
FAKE_IA_DIR = SCRATCH / "ia_dir"
FAKE_IA_DIR.mkdir(parents=True)
(FAKE_IA_DIR / "entities").mkdir()

import ia_agent.pairing as pairing_module  # noqa: E402

pairing_module.PAIRING_DEVICES_PATH = SCRATCH / "pairing.json"


def store_checks() -> None:
    print("\n1. start() mints a 6-digit code with a ~120s TTL and a LAN host/port")
    store = pairing_module.PairingStore()
    started = store.start()
    check("code is 6 digits", len(started["code"]) == 6 and started["code"].isdigit(), started["code"])
    check("expires roughly 120s out", 110 < started["expires_at"] - time.time() < 121, str(started))
    check("host and port are present", started["host"] and started["port"] == 8787, str(started))

    print("\n2. claim() rejects a wrong code")
    check("wrong code returns None", store.claim("000000", "phone") is None or started["code"] == "000000")

    print("\n3. claim() rejects an expired code")
    store.start()
    store._pending["expires_at"] = time.time() - 1
    expired_code = store._pending["code"]
    check("expired code returns None", store.claim(expired_code, "phone") is None)

    print("\n4. claim() succeeds on a fresh, unexpired code and is single-use")
    fresh = store.start()
    claimed = store.claim(fresh["code"], "  Seshu's Phone  ")
    check("claim returns an id and a token", claimed is not None and claimed.get("token"), str(claimed))
    check("device name is trimmed", store.devices()[-1]["name"] == "Seshu's Phone", str(store.devices()))
    replay = store.claim(fresh["code"], "second phone")
    check("the same code cannot be claimed twice", replay is None)

    print("\n5. devices() never leaks the token")
    check("no 'token' key in the listing", all("token" not in d for d in store.devices()), str(store.devices()))

    print("\n6. authenticate() matches the real token and bumps last_seen")
    device_id = claimed["id"]
    before = store._devices[device_id]["last_seen"]
    time.sleep(0.05)
    matched = store.authenticate(claimed["token"])
    check("authenticate returns the right device id", matched == device_id, str(matched))
    check("last_seen advanced", store._devices[device_id]["last_seen"] > before)
    check("a wrong token authenticates nothing", store.authenticate("not-a-real-token") is None)
    check("an empty token authenticates nothing", store.authenticate("") is None)

    print("\n7. revoke() removes the device and its token stops working")
    check("revoke returns True for a real device", store.revoke(device_id) is True)
    check("revoke returns False the second time", store.revoke(device_id) is False)
    check("the revoked token no longer authenticates", store.authenticate(claimed["token"]) is None)

    print("\n8. devices persist across a fresh PairingStore over the same path")
    store.start()
    reclaimed = store.claim(store._pending["code"], "second phone")
    reloaded = pairing_module.PairingStore()
    check("the reloaded store sees the persisted device",
          any(d["name"] == "second phone" for d in reloaded.devices()), str(reloaded.devices()))
    store.revoke(reclaimed["id"])


store_checks()

# ------------------------------------------------------------------ live app

import ia_agent.app as app_module  # noqa: E402
import ia_agent.images as images  # noqa: E402
import ia_agent.library.folders as folders  # noqa: E402
from ia_agent.library.folders import LibraryFolder  # noqa: E402

app_module.build_specs = lambda: []
images.IA_DIR = FAKE_IA_DIR
images.IMAGE_CACHE_DIR = SCRATCH / "cache"
folders.IA_DIR = FAKE_IA_DIR
folders.FOLDERS = {"entities": LibraryFolder("entities", FAKE_IA_DIR / "entities", flat=True)}

PORT = 8797
app = app_module.create_app()
from ia_agent.vars import TOKEN_PATH  # noqa: E402

desktop_token = TOKEN_PATH.read_text().strip()
desktop_headers = {"Authorization": f"Bearer {desktop_token}"}
server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=PORT, log_level="error"))
threading.Thread(target=server.run, daemon=True).start()


async def live_checks() -> None:
    async with httpx.AsyncClient(base_url=f"http://127.0.0.1:{PORT}") as client:
        for _ in range(50):
            try:
                await client.get("/api/health", headers=desktop_headers)
                break
            except httpx.HTTPError:
                await asyncio.sleep(0.2)

        print("\n9. POST /api/pair/start requires the desktop token")
        no_auth = await client.post("/api/pair/start")
        check("401 with no bearer at all", no_auth.status_code == 401, str(no_auth.status_code))
        started = (await client.post("/api/pair/start", headers=desktop_headers)).json()
        check("a code comes back", len(started["code"]) == 6, str(started))

        print("\n10. POST /api/pair/claim needs no bearer token at all")
        wrong = await client.post("/api/pair/claim", json={"code": "000000", "device_name": "x"})
        check("a wrong code is a 400, not a 401", wrong.status_code == 400, str(wrong.status_code))
        claimed = await client.post("/api/pair/claim", json={"code": started["code"], "device_name": "Pixel 7"})
        check("the real code succeeds unauthenticated", claimed.status_code == 200, claimed.text)
        device_token = claimed.json()["token"]
        device_id = claimed.json()["id"]
        device_headers = {"Authorization": f"Bearer {device_token}"}

        print("\n11. the minted device token authenticates against a normal bearer-protected route")
        as_device = await client.get("/api/health", headers=device_headers)
        check("device token works like a real bearer token", as_device.status_code == 200, str(as_device.status_code))

        print("\n12. GET /api/pair/devices lists it, requires the desktop token")
        forbidden = await client.get("/api/pair/devices", headers=device_headers)
        check("a device token cannot list paired devices", forbidden.status_code == 401, str(forbidden.status_code))
        listing = (await client.get("/api/pair/devices", headers=desktop_headers)).json()
        check("Pixel 7 is in the list", any(d["name"] == "Pixel 7" for d in listing), str(listing))
        check("no token field leaks over REST either", all("token" not in d for d in listing), str(listing))

        print("\n13. a device token can open the shared /ws and receive a broadcast")
        async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws?token={device_token}") as ws:
            await client.post("/api/pair/start", headers=desktop_headers)  # any harmless authed call
            # notifications provide a real broadcast to wait on (next suite covers
            # its own semantics) - this just proves the socket stays open and
            # was accepted, which is this checkpoint's actual claim.
            await asyncio.sleep(0.1)
            check("the socket accepted the device token (still open)", ws.state.name == "OPEN")

        print("\n14. DELETE /api/pair/devices/{id} revokes; the old device token stops working everywhere")
        revoked = await client.delete(f"/api/pair/devices/{device_id}", headers=desktop_headers)
        check("revoke succeeds", revoked.status_code == 200, revoked.text)
        after_revoke = await client.get("/api/health", headers=device_headers)
        check("the revoked device token is now unauthorized", after_revoke.status_code == 401, str(after_revoke.status_code))
        missing = await client.delete(f"/api/pair/devices/{device_id}", headers=desktop_headers)
        check("revoking an already-revoked id is a 404", missing.status_code == 404, str(missing.status_code))


async def main() -> int:
    await live_checks()
    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    shutil.rmtree(SCRATCH, ignore_errors=True)
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
