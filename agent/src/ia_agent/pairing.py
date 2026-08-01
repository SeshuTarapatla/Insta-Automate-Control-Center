"""Mobile pairing (PLAN CP 6.1, ARCHITECTURE §7).

A 6-digit code with a short TTL stands in for the QR handshake's trust
step: the desktop app mints one (already holding the desktop token), shows
it as a QR the phone scans, and the phone — which by definition has no
token yet — trades the code for a long-lived device token via the one
endpoint this module leaves outside `auth.py`'s bearer check. Single-use:
`claim()` clears `_pending` on its first (successful or not) real match so
a leaked or reused code can't mint a second device.

Paired devices persist to `PAIRING_DEVICES_PATH`, machine-local — same D12
reasoning as `services/settings.py` and `library/settings.py`. Revoking a
device just deletes its record; `authenticate()` failing for that token
from then on is the entire enforcement mechanism, exactly like the single
static desktop/service token today.
"""
import json
import secrets
import socket
import threading
import time
import uuid
from typing import Any

from ia_agent.logging import logger
from ia_agent.vars import AGENT_DATA_DIR, PAIRING_DEVICES_PATH

CODE_TTL = 120.0
PORT = 8787


def _lan_ip() -> str:
    """Best-effort LAN-facing address for the QR payload. Connecting a UDP
    socket sends nothing on the wire — it only asks the OS which local
    interface it would use to reach that address — so this is safe to call
    with no network side effect even if 8.8.8.8 is unreachable."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


class PairingStore:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._pending: dict[str, Any] | None = None
        self._devices: dict[str, dict[str, Any]] = self._load()

    # ------------------------------------------------------------ persistence

    def _load(self) -> dict[str, dict[str, Any]]:
        if not PAIRING_DEVICES_PATH.exists():
            return {}
        try:
            data = json.loads(PAIRING_DEVICES_PATH.read_text())
        except (json.JSONDecodeError, OSError) as error:
            logger.warning(f"unreadable pairing devices file, starting empty — {error}")
            return {}
        return data.get("devices", {})

    def _save(self) -> None:
        AGENT_DATA_DIR.mkdir(parents=True, exist_ok=True)
        temp = PAIRING_DEVICES_PATH.with_suffix(".tmp")
        temp.write_text(json.dumps({"devices": self._devices}, indent=2))
        temp.replace(PAIRING_DEVICES_PATH)

    # ------------------------------------------------------------- QR handshake

    def start(self) -> dict[str, Any]:
        """Desktop-side, bearer-protected: mint a fresh code, replacing
        whatever code was pending — only one QR is ever on screen at once."""
        with self._lock:
            code = f"{secrets.randbelow(1_000_000):06d}"
            self._pending = {"code": code, "expires_at": time.time() + CODE_TTL}
            return {"code": code, "expires_at": self._pending["expires_at"], "host": _lan_ip(), "port": PORT}

    def claim(self, code: str, device_name: str) -> dict[str, Any] | None:
        """Phone-side, unauthenticated by design (§7) — the code plus its
        TTL is the only proof of proximity. Returns the new device's id and
        token, or None for a wrong/expired/already-used code."""
        with self._lock:
            pending = self._pending
            if pending is None or pending["code"] != code or time.time() > pending["expires_at"]:
                return None
            self._pending = None
            device_id = str(uuid.uuid4())
            now = time.time()
            self._devices[device_id] = {
                "id": device_id,
                "name": device_name.strip() or "unnamed device",
                "token": secrets.token_urlsafe(32),
                "created_at": now,
                "last_seen": now,
            }
            self._save()
            return {"id": device_id, "token": self._devices[device_id]["token"]}

    # ------------------------------------------------------------- management

    def devices(self) -> list[dict[str, Any]]:
        with self._lock:
            return [
                {k: v for k, v in device.items() if k != "token"}
                for device in sorted(self._devices.values(), key=lambda d: d["created_at"])
            ]

    def revoke(self, device_id: str) -> bool:
        with self._lock:
            if device_id not in self._devices:
                return False
            del self._devices[device_id]
            self._save()
            return True

    def authenticate(self, token: str) -> str | None:
        """Bumps `last_seen` on a match. Returns the device id, or None —
        callers (auth.py, ws.py) only care whether it's a device at all."""
        if not token:
            return None
        with self._lock:
            for device_id, device in self._devices.items():
                if secrets.compare_digest(device["token"], token):
                    device["last_seen"] = time.time()
                    self._save()
                    return device_id
        return None
