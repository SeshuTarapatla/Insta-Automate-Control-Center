"""Queue API (CP 1.4's `GET /api/queue`, CP 5.2's add/remove/reorder mutations).

`ia_agent.api.queue`'s `CONFIG_PATH`/`ENTITY_DIR`/`SCRAPE_QUEUE_DIR`/`FOLLOW_QUEUE_DIR`
are name-imports from `vars.py`, so they are monkeypatched on the `queue` module
itself (not on `vars`) before the app is built — the same pattern
`test_supervisor.py`/`test_device.py` use for `settings.SERVICE_SETTINGS_PATH`.
This never touches the real `IA_DIR` or the real `config.env`.
"""
import asyncio
import shutil
import sys
import tempfile
import threading
from pathlib import Path

import httpx
import uvicorn

OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


SCRATCH = Path(tempfile.mkdtemp(prefix="ia-agent-test-queue-"))
FAKE_IA_DIR = SCRATCH / "ia_dir"
FAKE_IA_DIR.mkdir(parents=True)
CONFIG_PATH = FAKE_IA_DIR / "config.env"
CONFIG_PATH.write_text(
    "# a real config.env has comments and unrelated keys, kept verbatim by env_file.save()\n"
    "SCRAPE=60\n"
    "ENTITY_QUEUE=''\n",
    encoding="utf-8",
)
ENTITY_DIR = FAKE_IA_DIR / "entities"
SCRAPE_QUEUE_DIR = FAKE_IA_DIR / "scrape_queued"
FOLLOW_QUEUE_DIR = FAKE_IA_DIR / "follow_queued"
ENTITY_DIR.mkdir()
SCRAPE_QUEUE_DIR.mkdir()
FOLLOW_QUEUE_DIR.mkdir()

import ia_agent.api.queue as queue_module  # noqa: E402

queue_module.CONFIG_PATH = CONFIG_PATH
queue_module.ENTITY_DIR = ENTITY_DIR
queue_module.SCRAPE_QUEUE_DIR = SCRAPE_QUEUE_DIR
queue_module.FOLLOW_QUEUE_DIR = FOLLOW_QUEUE_DIR

import ia_agent.app as app_module  # noqa: E402

app_module.build_specs = lambda: []
# Also redirect the library router's folder taxonomy at the scratch IA_DIR so
# the app's lifespan (which seeds LibraryCounts and starts watch_library) has
# somewhere real to scan — this suite doesn't exercise those endpoints, but
# the app has to start cleanly regardless.
import ia_agent.images as images  # noqa: E402
import ia_agent.library.folders as folders  # noqa: E402
from ia_agent.library.folders import LibraryFolder  # noqa: E402

images.IA_DIR = FAKE_IA_DIR
images.IMAGE_CACHE_DIR = SCRATCH / "cache"
folders.IA_DIR = FAKE_IA_DIR
folders.FOLDERS = {"entities": LibraryFolder("entities", ENTITY_DIR, flat=True)}

PORT = 8796
app = app_module.create_app()
from ia_agent.vars import TOKEN_PATH  # noqa: E402

token = TOKEN_PATH.read_text().strip()
headers = {"Authorization": f"Bearer {token}"}
server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=PORT, log_level="error"))
threading.Thread(target=server.run, daemon=True).start()


def make_entity(name: str) -> None:
    (ENTITY_DIR / f"{name}.jpg").write_bytes(b"\xff\xd8\xff\xd9")


async def live_checks() -> None:
    async with httpx.AsyncClient(base_url=f"http://127.0.0.1:{PORT}", headers=headers) as client:
        for _ in range(50):
            try:
                await client.get("/api/health")
                break
            except httpx.HTTPError:
                await asyncio.sleep(0.2)

        print("\n1. GET /api/queue on an empty queue reports nothing queued")
        empty = (await client.get("/api/queue")).json()
        check("both lists empty", empty == {"queued": [], "unqueued": []}, str(empty))

        print("\n2. POST /api/queue/add without entities/<name>.jpg is a 422")
        rejected = await client.post("/api/queue/add", json={"name": "ghost"})
        check("422, not silently accepted", rejected.status_code == 422, str(rejected.status_code))

        print("\n3. POST /api/queue/add with a real entity image succeeds and is reflected in GET")
        make_entity("alice")
        added = await client.post("/api/queue/add", json={"name": "alice"})
        check("200 with alice queued", added.status_code == 200 and any(e["name"] == "alice" for e in added.json()["queued"]), added.text)

        print("\n4. POST /api/queue/add the same entity twice is a 409")
        dup = await client.post("/api/queue/add", json={"name": "alice"})
        check("409 on duplicate add", dup.status_code == 409, str(dup.status_code))

        print("\n5. POST /api/queue/add rejects a name with a path separator")
        traversal = await client.post("/api/queue/add", json={"name": "../evil"})
        check("422 on a path-shaped name", traversal.status_code == 422, str(traversal.status_code))

        print("\n6. POST /api/queue/remove refuses while the entity still has queued jpegs, unless forced")
        make_entity("bob")
        await client.post("/api/queue/add", json={"name": "bob"})
        (SCRAPE_QUEUE_DIR / "bob").mkdir()
        (SCRAPE_QUEUE_DIR / "bob" / "pic.jpg").write_bytes(b"\xff\xd8\xff\xd9")
        blocked = await client.post("/api/queue/remove", json={"name": "bob"})
        check("409 while pending images remain", blocked.status_code == 409, str(blocked.status_code))
        forced = await client.post("/api/queue/remove", json={"name": "bob", "force": True})
        check(
            "force=True removes it anyway",
            forced.status_code == 200 and all(e["name"] != "bob" for e in forced.json()["queued"]),
            forced.text,
        )

        print("\n7. POST /api/queue/remove on a name that isn't queued is a 404")
        missing = await client.post("/api/queue/remove", json={"name": "carol"})
        check("404, not a silent no-op", missing.status_code == 404, str(missing.status_code))

        print("\n8. POST /api/queue/reorder accepts a real permutation and rejects a fake one")
        make_entity("carol")
        await client.post("/api/queue/add", json={"name": "carol"})
        current = (await client.get("/api/queue")).json()
        queued_names = [e["name"] for e in current["queued"]]
        check("alice and carol are both queued now", set(queued_names) == {"alice", "carol"}, str(queued_names))
        reordered = await client.post("/api/queue/reorder", json={"order": list(reversed(queued_names))})
        check(
            "200 with the new order",
            reordered.status_code == 200 and [e["name"] for e in reordered.json()["queued"]] == list(reversed(queued_names)),
            reordered.text,
        )
        bad_order = await client.post("/api/queue/reorder", json={"order": ["alice"]})
        check("a partial list is a 422, not a silent drop", bad_order.status_code == 422, str(bad_order.status_code))
        bad_member = await client.post("/api/queue/reorder", json={"order": ["alice", "carol", "dave"]})
        check("a foreign name is a 422, not silently added", bad_member.status_code == 422, str(bad_member.status_code))

        print("\n9. config.env's unrelated key and comment survive every mutation")
        text = CONFIG_PATH.read_text()
        check("the comment line is intact", text.startswith("# a real config.env"), text.splitlines()[0])
        check("SCRAPE=60 is untouched", "SCRAPE=60" in text, text)


async def main() -> int:
    await live_checks()
    print(f"\n{sum(OK)}/{len(OK)} checks passed")
    shutil.rmtree(SCRATCH, ignore_errors=True)
    return 0 if all(OK) else 1


sys.exit(asyncio.run(main()))
