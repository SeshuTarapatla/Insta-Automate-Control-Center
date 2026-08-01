import asyncio
import os
import tempfile
from dataclasses import dataclass
from pathlib import Path

from ia_agent.config.schema import SCHEMA, ConfigType, SWITCH_KEYS

# Shared by every router that reads-modifies-writes config.env (config.py's
# PATCH, queue.py's add/remove/reorder) so two concurrent writers can't race
# each other's read-modify-write and drop one's change — a per-module lock
# would only serialize writers within that one module.
WRITE_LOCK = asyncio.Lock()


@dataclass
class EnvData:
    switches: dict[str, str]
    entity_queue: list[str]
    limits: dict[str, int]
    raw_lines: list[str]
    explicit_keys: set[str]


def _strip_quotes(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def load(path: Path) -> EnvData | None:
    """Reads and parses config.env. Mirrors env_service.dart's parsing rules exactly
    so the desktop app and the mobile app agree on what a given file means."""
    if not path.exists():
        return None

    raw_lines = path.read_text(encoding="utf-8").splitlines()
    switches: dict[str, str] = {}
    limits: dict[str, int] = {}
    entity_queue: list[str] = []
    explicit_keys: set[str] = set()

    for line in raw_lines:
        trimmed = line.strip()
        if not trimmed or trimmed.startswith("#") or "=" not in trimmed:
            continue

        key, _, value = trimmed.partition("=")
        key = key.strip()
        value = _strip_quotes(value.strip())

        if key not in SCHEMA:
            continue
        explicit_keys.add(key)

        if key == "ENTITY_QUEUE":
            entity_queue = [e.strip() for e in value.split(",") if e.strip()]
        elif key in SWITCH_KEYS and value in ("0", "1"):
            switches[key] = value
        elif SCHEMA[key].type == ConfigType.INT:
            try:
                limits[key] = int(value)
            except ValueError:
                limits[key] = SCHEMA[key].default  # type: ignore[assignment]

    # Missing keys fall back to their schema default, so callers always see the
    # effective value the flows will use via Limit.get().
    for key, spec in SCHEMA.items():
        if spec.type == ConfigType.INT:
            limits.setdefault(key, spec.default)  # type: ignore[arg-type]
        elif spec.type == ConfigType.BOOL01:
            switches.setdefault(key, str(spec.default))

    return EnvData(
        switches=switches,
        entity_queue=entity_queue,
        limits=limits,
        raw_lines=raw_lines,
        explicit_keys=explicit_keys,
    )


def save(
    path: Path,
    data: EnvData,
    *,
    entity_queue: list[str] | None = None,
    switches: dict[str, str] | None = None,
    limits: dict[str, int] | None = None,
) -> None:
    """Writes config.env back, preserving comments, blank lines, key order and any
    unknown keys verbatim. Atomic via temp-file + os.replace so a reader never sees
    a half-written file."""
    queue = entity_queue if entity_queue is not None else data.entity_queue
    sw = switches if switches is not None else data.switches
    lims = limits if limits is not None else data.limits

    queue_value = ",".join(queue)
    written: set[str] = set()
    out_lines: list[str] = []

    for line in data.raw_lines:
        trimmed = line.strip()
        if not trimmed or trimmed.startswith("#") or "=" not in trimmed:
            out_lines.append(line)
            continue

        key = trimmed.split("=", 1)[0].strip()
        if key == "ENTITY_QUEUE":
            out_lines.append(f"ENTITY_QUEUE='{queue_value}'")
            written.add("ENTITY_QUEUE")
        elif key in sw:
            out_lines.append(f"{key}={sw[key]}")
            written.add(key)
        elif key in lims:
            out_lines.append(f"{key}={lims[key]}")
            written.add(key)
        else:
            out_lines.append(line)

    for key, value in sw.items():
        if key not in written:
            out_lines.append(f"{key}={value}")
    if "ENTITY_QUEUE" not in written:
        out_lines.append(f"ENTITY_QUEUE='{queue_value}'")
    for key, value in lims.items():
        if key not in written:
            out_lines.append(f"{key}={value}")

    content = "\n".join(out_lines) + "\n"

    fd, tmp_path = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        os.replace(tmp_path, path)
    except BaseException:
        Path(tmp_path).unlink(missing_ok=True)
        raise
