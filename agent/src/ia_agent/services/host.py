"""The detached service host — CP 2.6.

Owns the ConPTY that used to live inside the agent. `host_launcher.py` spawns this
process and exits immediately, so by the time anything walks the process tree from
the agent this process's `ppid` points at an already-dead launcher — unreachable
from a `taskkill /F /T` rooted at the agent (D22). Killing, restarting or crashing
the agent no longer touches this process or the pty it owns; only an explicit stop
or takeover (which the supervisor aims at this process's own pid) does.

Run as `python -m ia_agent.services.host <name>`. Reads its spawn parameters — cmd,
cwd, env, the ConPTY grid — from `<name>.spawn.json`, written by the supervisor
right before it launches this process. Host needs none of `ServiceSpec`'s
probe/self-test callables (only the supervisor probes and tests), and taking cmd/
cwd/env/rows/cols as data rather than resolving a `ServiceSpec` by name keeps this
process usable for whatever the caller wants run in a pty — including the fake
services the test suite spawns, which are never part of the real registry.

Everything the agent needs from this process crosses one of two channels, deliberately
kept separate:

* the raw output stream (`<name>.stream`, truncated fresh on every spawn) — a file,
  because the agent may not even be running when most of it is written;
* resize (`<name>` named pipe) — the one thing a file cannot carry, since it has to
  reach a *live* pty, not a log.

`<name>.json` is the handshake and the exit signal: once the exit-immediately
launcher is gone, the agent has no OS-level wait() relationship to this process, so
this file is the only way it learns pid, start time, or exit code.
"""
import json
import os
import sys
import threading
import time
from multiprocessing.connection import Listener

import psutil
from winpty import PtyProcess

from ia_agent.vars import SERVICE_RUN_DIR

READ_SIZE = 8192
PIPE_AUTHKEY = b"ia-agent-host-ipc"


def pipe_address(name: str) -> str:
    return rf"\\.\pipe\ia-agent-svc-{name}"


def _state_path(name: str):
    return SERVICE_RUN_DIR / f"{name}.json"


def _stream_path(name: str):
    return SERVICE_RUN_DIR / f"{name}.stream"


def spawn_request_path(name: str):
    return SERVICE_RUN_DIR / f"{name}.spawn.json"


def _write_state(name: str, **fields) -> None:
    # Same atomic-enough shape as the old PID file: small, infrequent writes: a
    # reader mid-write would only ever see a stale-but-valid previous version on
    # POSIX, and on Windows a whole-file write_text is effectively atomic at this
    # size. Good enough for a local handshake file nothing else writes to.
    _state_path(name).write_text(json.dumps(fields))


def _resize_loop(proc: PtyProcess, name: str) -> None:
    """One connection at a time: the agent opens a fresh Client per resize rather
    than holding a pipe open, so there is nothing to keep alive here beyond the
    listener itself."""
    try:
        listener = Listener(pipe_address(name), family="AF_PIPE", authkey=PIPE_AUTHKEY)
    except OSError:
        return
    try:
        while True:
            try:
                conn = listener.accept()
            except OSError:
                return
            try:
                command = conn.recv()
                if command.get("cmd") == "resize":
                    proc.setwinsize(command["rows"], command["cols"])
                    conn.send({"ok": True})
            except Exception:
                pass
            finally:
                conn.close()
    finally:
        listener.close()


def main(name: str) -> int:
    try:
        request = json.loads(spawn_request_path(name).read_text())
    except (OSError, json.JSONDecodeError):
        return 2

    cmd = request["cmd"]
    cwd = request.get("cwd")
    env = {**os.environ, **request.get("env", {})}
    rows, cols = request.get("rows", 40), request.get("cols", 140)

    SERVICE_RUN_DIR.mkdir(parents=True, exist_ok=True)
    host_process = psutil.Process()

    try:
        proc = PtyProcess.spawn(cmd, cwd=cwd, env=env, dimensions=(rows, cols))
    except Exception as error:
        _write_state(
            name,
            host_pid=os.getpid(),
            host_create_time=host_process.create_time(),
            pid=None,
            create_time=None,
            started_at=None,
            cmd=cmd,
            exit_code=1,
            exited_at=time.time(),
            spawn_error=str(error),
        )
        return 1

    started_at = time.time()
    try:
        child_create_time = psutil.Process(proc.pid).create_time()
    except psutil.Error:
        child_create_time = started_at

    # Truncate the stream file *before* the state-file handshake is written, not
    # after: the supervisor starts tailing the instant it sees the state file, and
    # if a stale stream file from an earlier run with this name were still sitting
    # there, the tailer's initial size/offset would be measured against that stale
    # file a moment before this truncates it out from under it — an offset it
    # would then never see written data reach.
    # newline="" disables Python's universal-newline translation — without it,
    # writing on Windows turns every bare \n into \r\n and reading collapses \r
    # into \n, both of which corrupt the raw carriage-return/cursor-move bytes a
    # ConPTY stream depends on (a progress bar becomes garbage instead of one line).
    stream = _stream_path(name).open("w", encoding="utf-8", errors="replace", newline="")

    _write_state(
        name,
        host_pid=os.getpid(),
        host_create_time=host_process.create_time(),
        pid=proc.pid,
        create_time=child_create_time,
        started_at=started_at,
        cmd=cmd,
        exit_code=None,
        exited_at=None,
    )

    threading.Thread(target=_resize_loop, args=(proc, name), daemon=True).start()

    try:
        while True:
            try:
                data = proc.read(READ_SIZE)
            except EOFError:
                break
            except OSError:
                break
            if not data:
                if not proc.isalive():
                    break
                time.sleep(0.02)
                continue
            stream.write(data)
            stream.flush()
    finally:
        stream.close()

    try:
        proc.wait()
    except Exception:
        pass

    _write_state(
        name,
        host_pid=os.getpid(),
        host_create_time=host_process.create_time(),
        pid=proc.pid,
        create_time=child_create_time,
        started_at=started_at,
        cmd=cmd,
        exit_code=proc.exitstatus,
        exited_at=time.time(),
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
