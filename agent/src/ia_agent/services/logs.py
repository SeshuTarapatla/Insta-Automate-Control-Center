import logging
import threading
import time
from collections import deque
from logging.handlers import RotatingFileHandler

from ia_agent.vars import SERVICE_LOG_DIR

RING_CAPACITY = 5000


def _file_logger(name: str) -> logging.Logger:
    """A private logger per service, detached from the root handlers so service
    output never leaks into the agent's own console log."""
    SERVICE_LOG_DIR.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger(f"ia-agent.service.{name}")
    logger.propagate = False
    logger.setLevel(logging.INFO)
    if not logger.handlers:
        handler = RotatingFileHandler(
            SERVICE_LOG_DIR / f"{name}.log", maxBytes=1_000_000, backupCount=3, encoding="utf-8"
        )
        handler.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
        logger.addHandler(handler)
    return logger


class LogRing:
    """Per-service log store: a bounded in-memory ring the UI replays from, plus a
    rotating file so output from before the window was open is still readable.
    Written from the stdout and stderr reader threads, so every mutation is under a
    lock; `seq` is monotonic and never reused, which is what lets a reconnecting
    client ask for everything after the last line it saw."""

    def __init__(self, name: str) -> None:
        self._lock = threading.Lock()
        self._entries: deque[dict] = deque(maxlen=RING_CAPACITY)
        self._seq = 0
        self._logger = _file_logger(name)

    def append(self, line: str, stream: str = "stdout") -> dict:
        with self._lock:
            self._seq += 1
            entry = {"seq": self._seq, "ts": time.time(), "stream": stream, "line": line}
            self._entries.append(entry)
        self._logger.info(f"[{stream}] {line}")
        return entry

    def tail(self, count: int = 500, since: int | None = None) -> list[dict]:
        with self._lock:
            entries = list(self._entries)
        if since is not None:
            return [entry for entry in entries if entry["seq"] > since]
        return entries[-count:]

    @property
    def seq(self) -> int:
        with self._lock:
            return self._seq
