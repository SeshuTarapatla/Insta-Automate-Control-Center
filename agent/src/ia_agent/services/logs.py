import logging
import re
import threading
import time
from collections import deque
from logging.handlers import RotatingFileHandler

from ia_agent.vars import SERVICE_LOG_DIR

# Scrollback is bounded by bytes rather than lines: terminal output has no reliable
# line granularity (a progress bar is one line rewritten a thousand times), so a
# line count is not a bound on memory but a byte budget is.
MAX_BYTES = 512_000
MAX_CHUNKS = 5000

# CSI / OSC / two-character escapes. Only used for the on-disk copy.
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[@-Z\\-_]")


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


def render_plain(line: str) -> str:
    """Collapse a terminal line to what a human would see: escapes removed, and
    anything before the last carriage return overwritten, which is how a progress
    bar ends up as its final frame instead of a thousand frames."""
    return ANSI.sub("", line).rsplit("\r", 1)[-1]


class LogRing:
    """Raw terminal output for one service, kept verbatim.

    Chunks, not lines. The output comes from a ConPTY and carries ANSI colour,
    cursor movement and carriage returns that the in-app terminal needs in order to
    render what the wt.exe tab used to show — splitting on newlines and stripping
    them, as a log console would, destroys exactly that. The rotating file on disk
    is the one place output is flattened, because escape codes make a log file
    unreadable after the fact.

    Written from the reader thread, read from the event loop, so every mutation is
    under a lock; `seq` is monotonic and never reused, which is what lets a
    reconnecting terminal ask for everything after the last chunk it rendered."""

    def __init__(self, name: str) -> None:
        self._lock = threading.Lock()
        self._chunks: deque[dict] = deque()
        self._bytes = 0
        self._seq = 0
        self._logger = _file_logger(name)
        self._file_buffer = ""

    def append(self, data: str) -> dict:
        with self._lock:
            self._seq += 1
            entry = {"seq": self._seq, "ts": time.time(), "data": data}
            self._chunks.append(entry)
            self._bytes += len(data)
            while self._chunks and (self._bytes > MAX_BYTES or len(self._chunks) > MAX_CHUNKS):
                self._bytes -= len(self._chunks.popleft()["data"])

            # Whole lines go to disk flattened; the tail with no newline yet is held
            # back so a half-written line is not logged twice.
            self._file_buffer += data
            *lines, self._file_buffer = self._file_buffer.split("\n")

        for line in lines:
            rendered = render_plain(line).rstrip()
            if rendered:
                self._logger.info(rendered)
        return entry

    def note(self, message: str) -> dict:
        """A line from the agent itself rather than the service — start, stop, exit,
        adoption. Marked so the terminal can render it distinctly."""
        return self.append(f"\x1b[2m── {message}\x1b[0m\r\n")

    def tail(self, since: int | None = None) -> list[dict]:
        with self._lock:
            chunks = list(self._chunks)
        if since is None:
            return chunks
        return [chunk for chunk in chunks if chunk["seq"] > since]

    @property
    def seq(self) -> int:
        with self._lock:
            return self._seq
