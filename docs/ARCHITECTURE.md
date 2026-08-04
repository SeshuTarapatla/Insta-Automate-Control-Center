# Insta-Automate Control Center — Architecture

> Status: **design agreed, not yet implemented** (2026-07-30)
> Companion docs: [PLAN.md](PLAN.md) (phased build) · [../CLAUDE.md](../CLAUDE.md) (session context)

---

## 1. What exists today (verified live, 2026-07-30)

### 1.1 The pipeline being controlled

```
Telegram message (Instagram URL) ──┐
                                   ▼
  entity_ingest    → entities/<id>.jpg (1080×2246 full profile page)
                     Entity row created, access resolved, status=QUEUED
                                   ▼
  entity_scan      → scanned/<root>/<user>.jpg (1080×198 list-row crops)
                     one per follower / following / liker, Scanned rows
                                   ▼
  entity_classify  → AccessClassifier: PUBLIC → file deleted
                                       PRIVATE → kept
                     GenderClassifier: FEMALE → gender_valid/<root>/
                                       MALE   → gender_invalid/<root>/
                                   ▼
  [ HUMAN REVIEW ]   gender_valid  →  scrape_queued        (mobile app today)
                                   ▼
  entity_scrape    → scraped/<root>/<user>.jpg (dp 1080² + profile header composite)
                     User rows; queued input jpg unlinked
                                   ▼
  [ HUMAN REVIEW ]   scraped  →  follow_queued              (mobile app today)
                                   ▼
  entity_follow    → follow request sent, image unlinked
```

Current volume in `IA_DIR`: `entities` 432 · `scrape_queued` 7,566 across 118 entity dirs ·
`follow_queued` 180 across 8 dirs · `scanned`/`gender_*`/`scraped` currently drained.
The Library UI must be built for **tens of thousands of files**, not hundreds.

### 1.2 Runtime topology (all endpoints confirmed reachable)

| Component | Where | Endpoint | Notes |
|---|---|---|---|
| Prefect server | k3s pod `prefect-server` | `http://localhost:4200/api` | `/health` → `true`; full REST available |
| Postgres | k3s pod `postgres` | `localhost:5432` | db `insta_automate` |
| IA scheduler | k3s pod `insta-automate` | — | runs `ia prefect serve` (the trigger loops) |
| IA worker | k3s pod `insta-automate-worker` | — | Prefect process worker, executes flows |
| ADB server | Windows | `0.0.0.0:5037` | started `adb -a start-server` |
| VL server | Windows | `127.0.0.1:11500/v1` | llama-server, qwen3-vl:4b-instruct |
| wsl-bridge | Windows | `0.0.0.0:8000` | FastAPI, `/scrcpy/{start,stop}` |
| k8s API | Windows | `127.0.0.1:6443` | Rancher Desktop |
| pod → host | — | `172.19.16.1` / `host.docker.internal` | WSL default gateway |
| **ia-agent (new)** | Windows | `0.0.0.0:8787` | this project |

`IA_DIR` = `C:\Users\seshu\Pictures\insta-automate`, hostPath-mounted into both IA pods as
`/insta-automate` (helm `mount.host` uses the WSL path `/mnt/c/...`). **Consequence:** any path
crossing the pod↔host boundary must be *IA_DIR-relative*, never absolute.

### 1.3 What is hardcoded today

**Delays and gates — all in `Insta-Automate/src/insta_automate/controllers/prefect.py`:**

| Loop | Hardcoded | Meaning |
|---|---|---|
| `keep_telegram_alive` | `wait=1800` | Telethon session keepalive ping |
| `entity_ingest_time_trigger` | `wait=600` | poll Telegram channel for new entities |
| `entity_scan_trigger` | `sleep(10)` | poll only — **no inter-run cooldown**, blocks on flow completion |
| `entity_classify_trigger` | `wait=10` | poll `scanned/` for jpgs |
| `entity_scrape_trigger` | `wait=600, buffer=10` | cooldown between scrape runs |
| `entity_follow_trigger` | `wait=1200, buffer=10` | cooldown between follow runs |
| `wait_day_change` | `sleep(60)` | day-rollover poll |
| scrape backpressure | `< Limit.get("FOLLOW") * 3` | **the `3` is hardcoded** |

**Limits** already live in `IA_DIR/config.env` and are read live via `Limit.get()`
(`models/meta.py`) — no rebuild needed. Nine keys: `PROFILES REELS POSTS SCRAPE
SCRAPE_BATCH FOLLOW FOLLOW_BATCH FMIN FMAX`.

**Known quirks worth fixing while we're in there:**
- The comment in `config.env` claims `PROFILES/REELS/POSTS` "aren't the live enforcement point".
  They *are* — `Scan.limit_reached` calls `Limit.get()` on each. Comment is stale.
- After `wait_day_change()` returns, `entity_scan_trigger`/`entity_scrape_trigger`/
  `entity_follow_trigger` fall through to the gate check **without re-fetching** the daily
  counter row, so the first post-midnight iteration evaluates yesterday's object.
- `Queue(FOLLOW_QUEUE_DIR)` and `Queue(SCRAPE_QUEUE_DIR)` both default to `env_key="ENTITY_QUEUE"`
  — the scrape and follow priority queues are the *same list*. See open question Q1.
- `asyncio.sleep(wait)` snapshots the value at call time, so editing a delay mid-wait has no
  effect until the next cycle. Fixed by `wait_until()` (§4.2).

---

## 2. Chosen architecture

**Flutter Windows UI + a Python `ia-agent` service, both in this repo.**

The agent — not the UI — is the long-lived process. It becomes the single Windows startup entry,
replacing today's `wt.exe adb -a start-server ; python start_vl_server.py ; wsl-bridge.exe`
shortcut. Closing the control center window never takes the scraping stack down with it.

```
┌─ Windows 11 host ──────────────────────────────────────────────────────┐
│                                                                         │
│  ia-agent  (FastAPI, 0.0.0.0:8787)          ← Startup / Task Scheduler  │
│    ├── supervisor ─── adb server        (0.0.0.0:5037)                  │
│    ├── supervisor ─── vl-server         (127.0.0.1:11500)               │
│    ├── supervisor ─── wsl-bridge        (0.0.0.0:8000)                  │
│    ├── watchers   ─── IA_DIR tree, config.env                           │
│    ├── clients    ─── Prefect API, Postgres, k8s API, Telegram bot      │
│    ├── stores     ─── image cache, event ring, notification history     │
│    └── serves     ─── REST + one multiplexed WebSocket                  │
│                          │                                              │
│  Flutter Windows app ────┤  (pure client; may launch the agent if down) │
│  Rancher Desktop / k3s   │                                              │
│    ├── prefect-server ───┼── localhost:4200                             │
│    ├── postgres ─────────┼── localhost:5432                             │
│    ├── insta-automate ───┼── scheduler: heartbeat ⇄ commands            │
│    └── ia-worker ────────┴── flows: events, notify                      │
└─────────────────────────────────────────────────────────────────────────┘
                    ▲                              ▲
        LAN / wifi, QR-paired, bearer token        │ 172.19.16.1:8787
                    │                              │
          Flutter Android client            scheduler + flow runs
```

**Why the agent:** services must outlive the UI; the phone needs the same API the desktop uses;
the pods need a stable inbound endpoint for events and notifications; and Python already owns
every integration we need (`adbutils`, `telethon`, `my_modules.postgres/kubernetes/scrcpy/win32`,
the Prefect client).

**wsl-bridge stays untouched** as a supervised core service. It keeps its `/scrcpy` role and the
`ScrcpyClient` import in `insta_automate.controllers.device` keeps working unchanged.

---

## 3. Agent internals

```
agent/
├── pyproject.toml                 # uv project, console script: ia-agent
└── src/ia_agent/
    ├── __init__.py                # main() → uvicorn
    ├── vars.py                    # IA_DIR, ports, paths, defaults
    ├── config/
    │   ├── env_file.py            # comment-preserving dotenv reader/writer (atomic)
    │   └── schema.py              # typed key registry + validation + defaults
    ├── services/
    │   ├── spec.py                # ServiceSpec, HealthProbe, RestartPolicy, states
    │   ├── supervisor.py          # spawn / adopt / stop / restart / takeover, backoff
    │   ├── probes.py              # tcp, http, custom probes
    │   ├── logs.py                # raw ConPTY chunk ring (512 KB) + flattened file
    │   ├── settings.py            # per-service self_heal / autostart, services.json
    │   ├── selftest.py            # functional tests + adb's device-present probe
    │   ├── fixtures/row_crop.jpg  # synthetic 1080x198 crop for the vl-server test
    │   └── registry.py            # the 3 core services + read-only dependency checks
    ├── scheduler/
    │   ├── state.py               # mirror of the pod scheduler's per-flow state
    │   └── commands.py            # command queue drained by heartbeat responses
    ├── events/
    │   ├── schema.py              # FlowEvent models
    │   ├── bus.py                 # fan-out + replay ring buffer
    │   └── images.py              # content-addressed cache + thumbnails
    ├── dependencies.py            # the read-only dependency panel (CP 2.3)
    ├── integrations/
    │   ├── prefect.py             # health, work pool, workers; later: runs, logs, triggers
    │   ├── postgres.py            # liveness now; later: read models over entity/user/scan/...
    │   ├── kube.py                # pod phase + restarts; later: log stream, helm ops
    │   ├── telegram.py            # bot notify fallback + entity-channel post
    │   └── device.py              # adb device list, screencap frames, scrcpy control
    ├── notify/
    │   └── router.py              # app-first → Telegram fallback, dedupe, transient
    ├── library/
    │   ├── watcher.py             # IA_DIR watchdog → invalidation + change events
    │   ├── counts.py              # cached per-folder / per-entity counts
    │   └── ops.py                 # apply (move+delete), delete, queue mutations
    └── api/
        ├── auth.py                # tokens: desktop, device (QR), service (pods)
        ├── ws.py                  # single /ws, channel subscriptions
        └── routes_*.py            # REST surface (§3.1)
```

### 3.1 REST surface

| Group | Endpoints |
|---|---|
| health | `GET /api/health` · `GET /api/dependencies?refresh=` · `GET /api/system` (one-shot snapshot of everything) |
| config | `GET /api/config` · `GET /api/config/schema` · `PATCH /api/config` |
| services | `GET /api/services` · `GET /api/services/{name}` · `PATCH /api/services/{name}` (self_heal, autostart) · `POST /api/services/{name}/{start\|stop\|restart\|takeover\|test\|resize}` · `GET /api/services/{name}/logs?since=` |
| flows | `GET /api/flows` · `POST /api/flows/{flow}/{run\|force-run\|skip-wait}` · `POST /api/flows/{flow}/switch` |
| runs | `GET /api/flow-runs?limit=` · `GET /api/flow-runs/{id}` · `GET /api/flow-runs/{id}/logs?since=` · `POST /api/flow-runs/{id}/cancel` |
| events | `POST /api/events` (from flows) · `GET /api/events?since=` (replay) |
| images | `GET /api/images/{key}` · `GET /api/images/{key}/thumb?w=` |
| library | `GET /api/library/{folders\|entities\|images}` · `POST /api/library/{apply\|delete\|queue}` |
| stats | `GET /api/stats/{daily\|funnel\|entities}` |
| entities | `GET /api/entities` · `POST /api/entities` (adds via Telegram channel) |
| notify | `POST /api/notify` → `{delivered, targets}` · `GET /api/notify?since=&unread_only=` · `POST /api/notify/{id}/read` · `POST /api/notify/read-all` |
| scheduler | `GET /api/scheduler` (full snapshot) · `POST /api/scheduler/heartbeat` → `{commands:[…]}` · `POST /api/scheduler/{flow}/command` |
| ops | `POST /api/ops/{build\|deploy\|undeploy\|purge-runs\|db-backup\|db-restore}` |
| pairing | `POST /api/pair/start` · `POST /api/pair/claim` · `GET /api/pair/devices` · `DELETE /api/pair/devices/{id}` |
| device | `GET /api/device` · `POST /api/device/scrcpy/{start\|stop}` |

### 3.2 WebSocket

One socket at `/ws`, client subscribes to channels:

`services.status` · `services.logs.<name>` · `flows.state` · `flowrun.logs` · `flow.events` ·
`library.changes` · `config.changed` · `notifications` · `device.mirror` · `ops.logs`

Every channel supports replay-from-cursor so a reconnecting client never loses a window.

### 3.3 Auth

Three token classes, all bearer:

- **desktop** — generated on first agent run, written to `%LOCALAPPDATA%\ia-agent\token`; the
  Flutter app reads the file. Same-machine trust.
- **device** — minted by QR pairing (§7), one per phone, revocable, listed in the UI.
- **service** — static token for the pods, injected as `IA_AGENT_TOKEN` via `DockerEnv` / helm env.

v1 transport is plain HTTP on the LAN. This is a deliberate, documented tradeoff: the LAN carries
Instagram usernames and profile screenshots. Optional v2 adds a self-signed cert with the SPKI
fingerprint embedded in the pairing QR.

---

## 4. Configuration model

`IA_DIR/config.env` stays the **single source of truth**. It already works offline, is
Syncthing-replicated to the phone, and is read live by the flows. The agent adds validation,
atomic writes, comment preservation, and change notification — it does not replace the file.

### 4.1 Keys

Existing (unchanged): `ENTITY_INGEST ENTITY_SCAN ENTITY_CLASSIFY ENTITY_SCRAPE ENTITY_FOLLOW`,
`ENTITY_QUEUE`, and the nine limits.

New, all live-read, all defaulted so an absent key is never an error:

```env
# Trigger timings (seconds)
TG_KEEPALIVE_WAIT=1800
INGEST_POLL_WAIT=600
SCAN_POLL_WAIT=10
SCAN_WAIT=0                   # cooldown between scan runs (0 = back-to-back, today's behaviour)
CLASSIFY_POLL_WAIT=10
SCRAPE_WAIT=600
SCRAPE_BUFFER=10
FOLLOW_WAIT=1200
FOLLOW_BUFFER=10
DAY_CHANGE_POLL=60
TICK=5                        # granularity of interruptible sleeps / countdown resolution

# Gates
SCRAPE_RESERVE_FACTOR=3       # pause scrape while scraped+follow_queued >= FOLLOW × factor
SCAN_LIST=auto                # auto | followers | following

# Control-center wiring
IA_AGENT_URL=http://172.19.16.1:8787
NOTIFY_POLICY=app_first       # app_first | both | telegram_only
```

### 4.2 Interruptible waiting

`Limit` in `models/meta.py` is generalised into a typed `Config` accessor (`Limit` kept as an
alias so nothing breaks) — landed in CP 3.1. Every `asyncio.sleep(long)` in the scheduler becomes,
landed in CP 3.2:

```python
async def wait_until(self, flow: str, key: str) -> str:
    """Sleep in Config.get("TICK") increments, re-reading Config.get(key) every
    tick so an edited delay re-targets the deadline live. Returns the wake
    reason - "elapsed" is the only one until CP 3.3/3.4 wire a command queue
    through the agent."""
```

Takes the **config key name**, not a resolved seconds value — `seconds` was the original sketch,
but re-reading a captured number can't re-target anything; re-reading the *key* on every tick is
what makes an edited `FOLLOW_WAIT` actually shorten or extend a wait already in progress. Every
scheduler trigger loop's hardcoded `wait`/`buffer`/`sleep` calls this now instead
(`controllers/prefect.py`), and the day-rollover fall-through is fixed alongside it: each trigger
loop's gate check now `continue`s back to the top after `wait_day_change()` instead of falling
through into the same iteration's trigger logic on stale pre-rollover state.

Publishing the countdown and honouring `run_now`/`skip_wait` commands are **not yet implemented** —
they need the command queue CP 3.3 (agent client in the pod) and CP 3.4 (scheduler mirror in the
agent) build. Until then `wait_until` always returns `"elapsed"`; this is what makes the UI's
countdown rings truthful and the "Skip wait" button possible once CP 3.3-3.5 land.

### 4.3 Scheduler state, published every tick

```json
{
  "flow": "entity-scrape",
  "switch": true,
  "phase": "waiting",
  "next_trigger_at": "2026-07-30T14:22:10+05:30",
  "gate": {
    "ok": false,
    "reason": "backpressure",
    "detail": "scraped+follow_queued = 180 ≥ FOLLOW×3 = 180"
  },
  "today": { "scraped": 42, "limit": 300 },
  "last_run": { "id": "2fc1d0d4…", "state": "COMPLETED", "duration_s": 214 }
}
```

The `gate.detail` string is the single most valuable thing this project produces: it answers
*"why isn't it running right now?"* without reading code. Right now the answer to that question
requires knowing that `follow_queued` has 180 jpgs and that 180 ≥ 60×3.

### 4.4 Command channel

The pod scheduler cannot accept inbound connections, so it drives the exchange: it POSTs its state
to `/api/scheduler/heartbeat` every ~2 s and the **response body carries queued commands**.
One endpoint, bidirectional, no inbound networking, no polling files.

Commands: `run_now`, `force_run` (bypass gates, confirmed in UI), `skip_wait`, `pause`, `resume`,
`reload_config`, `reduce_reserve` (entity-follow only, added D86 — keeps entity-follow processing
the queue, successes and skips alike, until scraped+follow_queued drops to the backpressure
reserve target, instead of stopping at `FOLLOW_BATCH` successful follows; implies `force_run`'s
daily-limit bypass too, confirmed in UI).

**Landed in CP 3.4** (agent-side) **and closed the same session** (D28: `Prefect.serve()` now runs
`heartbeat_loop()`, posting every flow's real state every ~2s — `gate` is set by each trigger loop
at its own decision point and left untouched by `wait_until`, which only updates `phase`/
`next_trigger_at`; `today`/`last_run`/`switch` are read fresh on every heartbeat):
`SchedulerMirror` (`ia_agent/scheduler.py`) is an `RLock`-guarded in-memory store, one state block
per flow name, exactly mirroring `ManagedService`'s locking idiom (D9). `heartbeat(state)` records
the block and drains (and clears) that flow's queued commands in one call — a flow only ever sees
commands meant for it. `POST /api/scheduler/{flow}/command` (body `{"command": "skip_wait"}`,
validated against the six names above, 400 on anything else) is how something would queue one —
nothing calls it yet either, since CP 3.5 (Flows UI) is what gets buttons.

**Staleness** (not specified in this doc before CP 3.4, decided during implementation): no
heartbeat for `STALE_AFTER = 15.0`s flips `online` false. Nothing but a heartbeat arriving would
ever notice that on its own, so a small watchdog task (`WATCHDOG_TICK = 3.0`s) re-checks and
re-broadcasts on every tick, in addition to the heartbeat handler broadcasting immediately after
every POST for low-latency countdown updates. `GET /api/scheduler` returns
`{"online": bool, "last_heartbeat_at": float | null, "flows": {<flow>: <§4.3 block>}}` — the same
shape `flows.state` broadcasts, published only when its signature changes (online flag, or any
flow's `switch`/`phase`/`next_trigger_at`), matching `services.status`'s publish-on-change
discipline. See D27.

**Replay for this channel is the plain `GET`, not a cursor.** §3.2 says every channel supports
"replay-from-cursor" — for `services.logs.<name>` that means an actual `seq`-numbered ring, because
a log is a delta stream where losing an entry is losing information. `flows.state` is a full
snapshot on every publish, not a delta, so a client that connects mid-session loses nothing by
calling `GET /api/scheduler` once and then subscribing — there is no missing middle to replay.

---

## 5. Flow events — the basis for live image rendering

Flows emit structured events beside their existing `log.info` calls. Emission is
**failure-tolerant and fire-and-forget**: a 1 s timeout, exceptions swallowed, so the agent being
down can never break a scrape.

```python
class FlowEvent(BaseModel):
    id: UUID
    ts: datetime
    flow: str                    # entity_scan | entity_classify | …
    flow_run_id: str | None
    kind: str                    # see table below
    entity: str | None           # root entity id
    subject: str | None          # username / post id
    image: str | None            # ALWAYS IA_DIR-relative, e.g. "scanned/jpg.pragati/foo.jpg"
    image_key: str | None        # filled in by the agent after caching
    verdict: str | None
    reason: str | None
    counters: dict[str, int]
    extra: dict
```

**The agent caches the image bytes the moment an event arrives.** This is essential:
`entity_classify` unlinks public profiles and moves everything else, and `entity_follow` unlinks
the image right after acting. Without a cache, the UI races a `Path.unlink()` and shows holes.

### 5.1 Per-flow event kinds and their UI semantics

| Flow | Kind | Image (and its shape) | Rendering |
|---|---|---|---|
| `entity_ingest` | `entity.added` | `entities/<id>.jpg` — 1080×2246 full page | Hero card: full profile page, access + type badges, IG deep link |
| `entity_scan` | `scan.started` | `entities/<root>.jpg` | Header hero, which list (followers/following) and why, target counts |
| `entity_scan` | `scan.item` | `scanned/<root>/<user>.jpg` — 1080×198 row strip | Tile appended live to a filmstrip; `added/scanned` counter; duplicates greyed |
| `entity_scan` | `scan.completed` | — | Summary: total, new, duration, entity → COMPLETED |
| `entity_classify` | `classify.access` | the row strip | Verdict card: PUBLIC (red, about to be deleted) / PRIVATE (green) |
| `entity_classify` | `classify.gender` | the row strip | Verdict card: FEMALE → gender_valid / MALE → gender_invalid; live img/s rate |
| `entity_scrape` | `scrape.started` | `scrape_queued/<root>/<user>.jpg` | "Now scraping" panel with the input strip and @id |
| `entity_scrape` | `scrape.skipped` | input strip | Reason chip with **real numbers**: `PUBLIC` · `NO_POSTS` · `f=87 < FMIN=100` · `f=3.2K > FMAX=2000` |
| `entity_scrape` | `scrape.done` | `scraped/<root>/<user>.jpg` — 1080×~2000 composite | Before → after transition: row strip morphs into the profile report; parsed posts/followers/following |
| `entity_follow` | `follow.attempt` | `follow_queued/<root>/<user>.jpg` | Profile report card |
| `entity_follow` | `follow.result` | same | FOLLOWED / REQUESTED / FOLLOWING / FOLLOWED_BY / WANTS_TO_FOLLOW / FAILED |
| any | `device.state` | live screencap frame | Mirror pane |

Three distinct aspect ratios (wide 5.5:1 strip, tall 1:2 page, tall 1:1.9 composite) means the
visualization surface needs per-kind layout, not one generic grid. This is exactly the
"what we show should make sense with the objective of the flow" requirement.

### 5.2 Log tailing

Prefect exposes no log stream, so the agent polls `POST /api/logs/filter` with
`timestamp > cursor` at ~1 s per active run, discovers the active run from the scheduler heartbeat
(falling back to `flow_runs/filter` sorted by start time), and **merges in the scheduler pod's
container log** via the k8s API — that's where the trigger decisions and gate reasons are printed.

---

## 6. Notification routing

A `Notifier` facade in `insta_automate.controllers.notify` replaces direct `tl.bot.notify(...)`:

```python
async def notify(msg, *, image=None, transient=False, dedupe=None,
                 level="info", tags=()) -> bool
```

1. Unless `NOTIFY_POLICY == telegram_only`, POST to `{IA_AGENT_URL}/api/notify` (2 s timeout).
2. Agent broadcasts on the `notifications` channel, persists to history, and answers
   `{delivered: bool, targets: int}` — `delivered` is true only if at least one live subscriber
   (focused desktop app or connected phone) received it.
3. If `delivered` is false, the call raised, or `NOTIFY_POLICY == both` → fall through to the
   existing `tl.bot.notify(...)`. **Telegram remains the guaranteed backstop.**

`transient` (auto-delete after 5 s) and the search-and-replace dedupe of `notify_transient` are
preserved: `dedupe` key replaces any prior unread notification with the same key.

Call sites to convert: `tasks/telegram.py` (4 functions), `tasks/device.py::wait_for_device`
(connect/disconnect), `tasks/ia.py::add_new_entity` and `::profile_follow`,
`flows/entity_scrape.py` and `flows/entity_follow.py` (limit-reached messages).

---

## 7. Mobile pairing

1. Desktop → `POST /api/pair/start` → agent mints a 6-digit code, 120 s TTL, returns LAN IP+port.
2. Desktop renders a QR of `iacc://pair?h=<lan-ip>&p=8787&c=<code>`.
3. Phone scans (`mobile_scanner`), POSTs code + device name to `/api/pair/claim`, receives a
   long-lived device token and persists it.
4. Desktop lists paired devices with last-seen and a revoke action.

On the phone, an Android **foreground service** (`flutter_foreground_task`) keeps the WebSocket
alive so notifications arrive within a second; `flutter_local_notifications` renders them. When
the socket is up the client reads and writes config through the agent (instant); when it is down
it falls back to editing `config.env` directly and letting Syncthing carry it — exactly today's
behaviour, so nothing regresses when off-wifi.

---

## 8. Cross-repo changes

All work outside this repo happens on a **feature branch and is never merged** until the control
center is accepted (see [../CLAUDE.md](../CLAUDE.md) §Rules).

| Repo | Branch | Changes |
|---|---|---|
| `Insta-Automate` | `feat/control-center` | `models/meta.py` typed `Config`; `controllers/prefect.py` config-driven + interruptible waits + heartbeat; new `controllers/agent.py` (client, CP 3.3) and `controllers/notify.py` (facade); `emit()` instrumentation in `tasks/ia.py` + `tasks/ollama.py`; `vars.py` `IA_AGENT_TOKEN` (secret, env-only — `IA_AGENT_URL` stays a live `Config` key instead, since it isn't sensitive and doesn't need a pod restart to change, see CP 3.3); `models/docker.py` env additions; fix the stale `config.env` comment |
| `flutter/Insta-Automate-Client` | `feat/lan-agent` | QR scan, agent client, foreground-service WS, local notifications, config writes via agent when connected |
| `Helmcharts/Insta-Automate` | `feat/control-center` | surface `IA_AGENT_URL`/`IA_AGENT_TOKEN` as deployment env (from `values.yaml`) so changing them needs no image rebuild |
| `wsl-bridge` | — | **no changes**; supervised as-is |
| `my-modules` | — | none expected |

---

## 9. Flutter app design direction

"Sophisticated, mature control center, no compromise" — concretely:

- **Shell** — custom title bar (`window_manager`), Mica/acrylic backdrop, left navigation rail:
  Overview · Flows · Live · Services · Library · Insights · Settings. Persisted window geometry,
  system tray icon with quick service toggles, global show/hide hotkey.
- **Overview is mission control** — one screen that answers everything at a glance: five flow
  countdown rings with gate reasons, three core-service pills, a dependency strip (k3s, postgres,
  prefect, pods, device, internet, disk), today's limit burn-down bars, a device thumbnail, and
  the recent notification feed.
- **Motion with purpose** — `AnimatedSwitcher` for the scrape before→after morph, implicit
  animation on counters and rings. Nothing decorative.
- **Keyboard-first** — every action has a shortcut; the Library grid is fully navigable with
  arrows / space / shift-range, because reviewing 7.5k images with a mouse is the current pain.
- **Honest degradation** — agent down shows a non-blocking banner with Retry and *Start agent*
  (the app can launch it, being on the same machine), never a dead white screen.
- **Stack** — Riverpod (state), `dio` (REST), `web_socket_channel` (WS), `freezed` +
  `json_serializable` (models mirrored from the agent's pydantic schema), `fl_chart` (insights),
  `qr_flutter` (pairing), `window_manager` + `flutter_acrylic` (shell).

---

## 10. Security note (flagged, needs a decision)

`D:\Coding\Insta-Automate\Dockerfile` is committed to git and contains, in plaintext: the Postgres
password, the Telegram API hash, the bot token, and **two Telethon session strings**. A session
string is a full account credential — it grants complete control of the Telegram account without
a login prompt.

`ia build` regenerates that Dockerfile on every build from `DockerEnv` + `TelegramSecret`, so it
never needed to be committed. Recommended: add `Dockerfile` to `.gitignore`, purge it from
history, and rotate the bot token and both session strings. Worth doing *before* this project
opens another network listener on the LAN. Tracked as open question Q10.
