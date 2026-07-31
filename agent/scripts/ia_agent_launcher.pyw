"""What the logon task actually runs: a GUI-subsystem babysitter for the agent.

Two Windows facts shaped this, both measured on 2026-07-31 rather than assumed
(D7's rule — a launch API reporting success is not evidence of an effect):

* **Task Scheduler exposes no window style**, so a console-subsystem program started
  from a logon task shows a real console window. `python.exe` did; so did the venv's
  `pythonw.exe`, which is a uv trampoline that re-execs the console interpreter. The
  base interpreter's `pythonw.exe` is GUI-subsystem and shows nothing at all
  (`GetConsoleWindow() == 0`), so the task runs that, against this file.

* **`RestartOnFailure` does not fire when the action exits non-zero.** The agent was
  killed, the task recorded `Last Result: 1` and went to `Ready`, and nothing
  restarted it in three minutes with `<Interval>PT1M</Interval>` set. Healing the
  agent is therefore this script's job, not the scheduler's: it restarts the agent
  with backoff and only stops when the agent exits cleanly. The task's repetition
  trigger is the outer net, for the case where this process itself dies.

Stdlib only — the base interpreter has none of the agent's dependencies.

CREATE_NO_WINDOW is passed alone. Combining it with DETACHED_PROCESS silently
cancels it (Windows ignores CREATE_NO_WINDOW when DETACHED_PROCESS or
CREATE_NEW_CONSOLE is also set), which is exactly how a "hidden" launch grows a
console window nobody asked for.
"""
import ctypes
import ctypes.wintypes as wintypes
import os
import subprocess
import sys
import time
from pathlib import Path

CREATE_NO_WINDOW = 0x08000000
LOG_MAX_BYTES = 5 * 1024 * 1024

BACKOFF_INITIAL = 5.0
BACKOFF_MAX = 300.0
# An agent that stayed up this long counts as healthy, so the next crash starts
# over at the short delay instead of inheriting a long one.
HEALTHY_AFTER = 120.0

AGENT_DIR = Path(__file__).resolve().parent.parent
AGENT_EXE = AGENT_DIR / ".venv" / "Scripts" / "ia-agent.exe"
DATA_DIR = Path(os.environ["LOCALAPPDATA"]) / "ia-agent"
LOG_PATH = DATA_DIR / "logs" / "startup.log"
# Touch this file to stop the loop after the next exit — the way to take the agent
# down for a while without deleting the task. `schtasks /End /TN ia-agent` is the
# immediate version; it kills this process too.
STOP_FILE = DATA_DIR / "stop-launcher"


def rotate(path: Path) -> None:
    if path.exists() and path.stat().st_size > LOG_MAX_BYTES:
        path.replace(path.with_suffix(".log.1"))


# --- keeping the agent tied to this process ---------------------------------
#
# `schtasks /End` kills this launcher and nothing else: measured, the agent kept
# serving on 8787 as an orphan whose parent was gone. That is worse than useless —
# the documented way to stop the agent left something holding its port, so the next
# task run could not bind. A job object with KILL_ON_JOB_CLOSE makes the kernel do
# what the parent-child relationship does not: when this process dies, by /End or
# by anything else, the agent and its trampolines go with it.

JobObjectExtendedLimitInformation = 9
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000
PROCESS_SET_QUOTA = 0x0100
PROCESS_TERMINATE = 0x0001

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)


class IO_COUNTERS(ctypes.Structure):
    _fields_ = [(name, ctypes.c_ulonglong) for name in (
        "ReadOperationCount", "WriteOperationCount", "OtherOperationCount",
        "ReadTransferCount", "WriteTransferCount", "OtherTransferCount")]


class JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("PerProcessUserTimeLimit", ctypes.c_int64),
        ("PerJobUserTimeLimit", ctypes.c_int64),
        ("LimitFlags", wintypes.DWORD),
        ("MinimumWorkingSetSize", ctypes.c_size_t),
        ("MaximumWorkingSetSize", ctypes.c_size_t),
        ("ActiveProcessLimit", wintypes.DWORD),
        ("Affinity", ctypes.POINTER(ctypes.c_ulong)),
        ("PriorityClass", wintypes.DWORD),
        ("SchedulingClass", wintypes.DWORD),
    ]


class JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("BasicLimitInformation", JOBOBJECT_BASIC_LIMIT_INFORMATION),
        ("IoInfo", IO_COUNTERS),
        ("ProcessMemoryLimit", ctypes.c_size_t),
        ("JobMemoryLimit", ctypes.c_size_t),
        ("PeakProcessMemoryUsed", ctypes.c_size_t),
        ("PeakJobMemoryUsed", ctypes.c_size_t),
    ]


def create_job() -> int | None:
    job = kernel32.CreateJobObjectW(None, None)
    if not job:
        return None
    limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    if not kernel32.SetInformationJobObject(
        job, JobObjectExtendedLimitInformation, ctypes.byref(limits), ctypes.sizeof(limits)
    ):
        kernel32.CloseHandle(job)
        return None
    return job


def assign(job: int, pid: int) -> bool:
    """Children the agent spawns inherit the job, so this covers the whole uv
    trampoline chain, not just the process we launched."""
    handle = kernel32.OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, False, pid)
    if not handle:
        return False
    try:
        return bool(kernel32.AssignProcessToJobObject(job, handle))
    finally:
        kernel32.CloseHandle(handle)


def main() -> int:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    rotate(LOG_PATH)

    # The agent's own stdout lands here too. Under the task there is no console to
    # inherit, and the hidden one CREATE_NO_WINDOW allocates is unreadable, so
    # without this redirect a failure at boot would leave nothing to read.
    with LOG_PATH.open("a", encoding="utf-8", errors="replace", buffering=1) as log:

        def note(message: str) -> None:
            log.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] launcher: {message}\n")
            log.flush()

        if not AGENT_EXE.exists():
            note(f"{AGENT_EXE} is missing - run `uv sync` in {AGENT_DIR}")
            return 2

        job = create_job()
        if job is None:
            note("could not create a job object - a kill of this launcher would orphan the agent")

        backoff = BACKOFF_INITIAL
        while True:
            if STOP_FILE.exists():
                note(f"{STOP_FILE.name} present - not starting; delete it and re-run the task")
                return 0

            started = time.time()
            try:
                process = subprocess.Popen(
                    [str(AGENT_EXE)],
                    cwd=str(AGENT_DIR),
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    stdin=subprocess.DEVNULL,
                    creationflags=CREATE_NO_WINDOW,
                    close_fds=True,
                )
            except OSError as error:
                note(f"failed to start - {error}")
                return 3

            if job is not None and not assign(job, process.pid):
                note(f"could not put pid {process.pid} in the job - it may outlive this launcher")
            note(f"started {AGENT_EXE.name} pid {process.pid}")
            code = process.wait()
            uptime = time.time() - started
            note(f"ia-agent (pid {process.pid}) exited with {code} after {uptime:.0f}s")

            # Exit 0 is a deliberate shutdown (Ctrl+C, a clean stop). Restarting it
            # would make the agent impossible to stop without deleting the task.
            if code == 0:
                return 0
            if STOP_FILE.exists():
                note(f"{STOP_FILE.name} present - staying down")
                return 0

            if uptime >= HEALTHY_AFTER:
                backoff = BACKOFF_INITIAL
            note(f"restarting in {backoff:.0f}s")
            time.sleep(backoff)
            backoff = min(backoff * 2, BACKOFF_MAX)


if __name__ == "__main__":
    sys.exit(main())
