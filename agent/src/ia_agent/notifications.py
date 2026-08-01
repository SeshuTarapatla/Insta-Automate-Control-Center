"""Persisted notification store (PLAN CP 6.1, ARCHITECTURE §6).

Unlike `events/store.py`'s in-memory-only replay ring — a flow run's
per-item images are worthless the moment the next run starts, so nothing
of value survives losing them on restart — an unread "limit reached" or
"scan complete" notification is exactly the state a restart must not
silently drop. History is written to disk on every mutation (add / mark
read), capped at `MAX_HISTORY` so months of uptime can't grow the file
without bound.

`dedupe` preserves the search-and-replace semantics `Insta-Automate`'s
`tl.bot.notify_transient` already had (ARCHITECTURE §6): a fresh
notification with the same `dedupe` key drops any *unread* prior one with
that key rather than piling up "FOLLOW limit reached" ten times in a row.
Once a notification has been read, a same-key repeat is a genuinely new
occurrence, not an update to the old one, so it is left alone.
"""
import asyncio
import json
import threading
import time
import uuid
from typing import Any

from ia_agent import images
from ia_agent.events.bus import EventBus
from ia_agent.logging import logger
from ia_agent.vars import AGENT_DATA_DIR, NOTIFICATIONS_PATH

MAX_HISTORY = 1000


class NotificationStore:
    def __init__(self, bus: EventBus) -> None:
        self._bus = bus
        self._lock = threading.Lock()
        self._notifications: list[dict[str, Any]] = self._load()
        self._seq = max((n["seq"] for n in self._notifications), default=0)

    # ------------------------------------------------------------ persistence

    def _load(self) -> list[dict[str, Any]]:
        if not NOTIFICATIONS_PATH.exists():
            return []
        try:
            data = json.loads(NOTIFICATIONS_PATH.read_text())
        except (json.JSONDecodeError, OSError) as error:
            logger.warning(f"unreadable notification history, starting empty — {error}")
            return []
        return data.get("notifications", [])

    def _save(self) -> None:
        AGENT_DATA_DIR.mkdir(parents=True, exist_ok=True)
        temp = NOTIFICATIONS_PATH.with_suffix(".tmp")
        temp.write_text(json.dumps({"notifications": self._notifications}, indent=2))
        temp.replace(NOTIFICATIONS_PATH)

    # ------------------------------------------------------------------- API

    async def add(self, payload: dict[str, Any]) -> dict[str, Any]:
        image_rel = payload.get("image")
        image_key = await asyncio.to_thread(images.cache, image_rel) if image_rel else None
        dedupe_key = payload.get("dedupe")
        with self._lock:
            if dedupe_key:
                self._notifications = [
                    n for n in self._notifications
                    if not (n.get("dedupe") == dedupe_key and not n["read"])
                ]
            self._seq += 1
            entry = {
                "id": str(uuid.uuid4()),
                "seq": self._seq,
                "ts": payload.get("ts") or time.time(),
                "msg": payload.get("msg", ""),
                "image_key": image_key,
                "level": payload.get("level", "info"),
                "tags": list(payload.get("tags") or []),
                "dedupe": dedupe_key,
                "transient": bool(payload.get("transient", False)),
                "read": False,
            }
            self._notifications.append(entry)
            if len(self._notifications) > MAX_HISTORY:
                self._notifications = self._notifications[-MAX_HISTORY:]
            self._save()
        return entry

    async def publish(self, entry: dict[str, Any]) -> int:
        """Returns how many live WS clients were reachable at publish time —
        the closest thing to "delivered" the bus's broadcast-to-everyone
        model (see events/bus.py) can answer today."""
        targets = self._bus.subscriber_count()
        await self._bus.publish("notifications", entry)
        return targets

    def tail(self, since: int | None = None, unread_only: bool = False) -> list[dict[str, Any]]:
        with self._lock:
            items = list(self._notifications)
        if since is not None:
            items = [n for n in items if n["seq"] > since]
        if unread_only:
            items = [n for n in items if not n["read"]]
        return items

    def mark_read(self, notification_id: str) -> bool:
        with self._lock:
            for n in self._notifications:
                if n["id"] == notification_id:
                    if not n["read"]:
                        n["read"] = True
                        self._save()
                    return True
        return False

    def mark_all_read(self) -> int:
        with self._lock:
            changed = [n for n in self._notifications if not n["read"]]
            for n in changed:
                n["read"] = True
            if changed:
                self._save()
            return len(changed)
