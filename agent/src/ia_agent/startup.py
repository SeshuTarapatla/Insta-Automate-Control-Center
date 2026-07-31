"""Startup ownership: the logon task that replaces `dev-startup.exe.lnk` (CP 2.5).

    uv run --project agent python -m ia_agent.startup status
    uv run --project agent python -m ia_agent.startup install
    uv run --project agent python -m ia_agent.startup remove

A Task Scheduler logon task rather than a Startup shortcut because a shortcut has no
restart-on-failure: once the agent owns healing for the three core services it is
itself load-bearing and needs healing of its own.

Three things about this are measured rather than assumed (D7's rule — a Windows
launch API reporting success is not evidence of an effect):

* **The task must start a GUI-subsystem executable.** Task Scheduler exposes no
  window style, so a console app started from a logon task shows a real console
  window. `python.exe` did. The venv's `pythonw.exe` did too — it is a uv trampoline
  that re-execs the console interpreter. The base interpreter's `pythonw.exe` shows
  nothing (`GetConsoleWindow() == 0`), so that is what the task runs, against
  `scripts/ia_agent_launcher.pyw`.
* **The task runs in the interactive session, not session 0.** wsl-bridge spawns
  scrcpy, which needs a desktop, so `LogonType` is `InteractiveToken` and the task is
  bound to this user's logon.
* **The launcher waits for the agent** instead of spawning and exiting, or Task
  Scheduler would call the task finished and never restart a crash.
* **`RestartOnFailure` does not heal a crashed agent.** With `PT1M`/3 configured, an
  agent killed outright left the task at `Last Result: 1`, `Status: Ready`, and
  nothing restarted for three minutes. So the launcher restarts the agent itself
  (with backoff, stopping only on a clean exit), and the trigger repeats every 10
  minutes as an outer net for the launcher itself dying.

Deliberately not exposed in the UI. Installing a scheduled task and deleting a file
out of the Startup folder is a once-per-machine act with a documented rollback, not
a button anyone should press twice.
"""
import argparse
import hashlib
import os
import shutil
import socket
import subprocess
import sys
from pathlib import Path

from ia_agent.services import settings
from ia_agent.vars import AGENT_DATA_DIR, PORT

TASK_NAME = "ia-agent"

REPO_DIR = Path(__file__).resolve().parents[3]
AGENT_DIR = REPO_DIR / "agent"
LAUNCHER = AGENT_DIR / "scripts" / "ia_agent_launcher.pyw"
AGENT_EXE = AGENT_DIR / ".venv" / "Scripts" / "ia-agent.exe"

SHORTCUT = (
    Path(os.environ.get("APPDATA", ""))
    / "Microsoft"
    / "Windows"
    / "Start Menu"
    / "Programs"
    / "Startup"
    / "dev-startup.exe.lnk"
)
SHORTCUT_BACKUP = REPO_DIR / "backups" / "2026-07-31-dev-startup" / "dev-startup.exe.lnk"
RECORD_DIR = REPO_DIR / "backups" / "2026-07-31-agent-task"

TASK_XML_PATH = AGENT_DATA_DIR / "ia-agent-task.xml"
# Read by the launcher, not by the agent: while it exists the launcher refuses to
# start or restart the agent. The documented way to keep the agent down without
# deleting the task.
STOP_FILE = AGENT_DATA_DIR / "stop-launcher"

# The services whose autostart switches this hands over. Kept as names rather than
# read from the registry so `remove` can restore them without importing the specs.
SERVICE_NAMES = ("adb", "vl-server", "wsl-bridge")


def base_pythonw() -> Path:
    """The GUI-subsystem interpreter under the venv's base prefix. `sys.base_prefix`
    resolves to the uv-managed distribution even when we are running inside the venv,
    which is the whole point — the venv's own pythonw.exe is a trampoline and shows a
    console window."""
    return Path(sys.base_prefix) / "pythonw.exe"


def task_xml() -> str:
    user = f"{os.environ['USERDOMAIN']}\\{os.environ['USERNAME']}"
    return f"""<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>{user}</Author>
    <Description>Starts ia-agent at logon. It supervises adb, vl-server and wsl-bridge and serves the Insta-Automate Control Center on port {PORT}. Replaces the dev-startup.exe.lnk Startup shortcut (CP 2.5).</Description>
    <URI>\\{TASK_NAME}</URI>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>{user}</UserId>
      <Delay>PT15S</Delay>
      <!-- The outer net. RestartOnFailure below does not fire when the action
           exits non-zero (measured), and the launcher heals the agent itself, so
           this exists for the case where the launcher process dies: every 10
           minutes the trigger asks for the task again, and MultipleInstancesPolicy
           IgnoreNew makes that a no-op whenever it is already running. -->
      <Repetition>
        <Interval>PT10M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>{user}</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>3</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>{base_pythonw()}</Command>
      <Arguments>"{LAUNCHER}"</Arguments>
      <WorkingDirectory>{AGENT_DIR}</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"""


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def schtasks(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["schtasks", *args], capture_output=True, text=True)


def task_exists() -> bool:
    return schtasks("/Query", "/TN", TASK_NAME).returncode == 0


def agent_answers() -> bool:
    with socket.socket() as probe:
        probe.settimeout(1.0)
        return probe.connect_ex(("127.0.0.1", PORT)) == 0


# --------------------------------------------------------------------- install


def preflight() -> list[str]:
    problems = []
    if os.name != "nt":
        problems.append("this only makes sense on Windows")
    if not base_pythonw().exists():
        problems.append(f"no GUI interpreter at {base_pythonw()}")
    if not LAUNCHER.exists():
        problems.append(f"launcher missing: {LAUNCHER}")
    if not AGENT_EXE.exists():
        problems.append(f"agent missing: {AGENT_EXE} — run `uv sync` in {AGENT_DIR}")
    return problems


def install() -> int:
    problems = preflight()
    if problems:
        for problem in problems:
            print(f"  [!!] {problem}")
        return 1

    RECORD_DIR.mkdir(parents=True, exist_ok=True)
    AGENT_DATA_DIR.mkdir(parents=True, exist_ok=True)

    # 1. the task
    xml = task_xml()
    TASK_XML_PATH.write_text(xml, encoding="utf-16")
    (RECORD_DIR / "ia-agent-task.xml").write_text(xml, encoding="utf-8")
    result = schtasks("/Create", "/TN", TASK_NAME, "/XML", str(TASK_XML_PATH), "/F")
    if result.returncode != 0:
        print(f"  [!!] schtasks /Create failed: {(result.stderr or result.stdout).strip()}")
        return 1
    print(f"  [ok] registered task {TASK_NAME} -> {base_pythonw().name} {LAUNCHER.name}")

    # 2. the switches the task hands over to
    for name in SERVICE_NAMES:
        settings.update(name, autostart=True)
    print(f"  [ok] autostart on for {', '.join(SERVICE_NAMES)} ({settings.SERVICE_SETTINGS_PATH})")

    # 3. the shortcut this replaces — never deleted without a verified backup
    if not SHORTCUT.exists():
        print(f"  [--] startup shortcut already gone ({SHORTCUT.name})")
    elif not SHORTCUT_BACKUP.exists():
        print(f"  [!!] refusing to delete {SHORTCUT}: no backup at {SHORTCUT_BACKUP}")
        return 1
    else:
        live, backed_up = sha256(SHORTCUT), sha256(SHORTCUT_BACKUP)
        if live != backed_up:
            # It changed since the backup was taken; keep the version we are about to
            # destroy rather than trusting the older copy.
            shutil.copy2(SHORTCUT, RECORD_DIR / "dev-startup.exe.lnk.live")
            print(f"  [!?] shortcut differs from the backup — kept a copy in {RECORD_DIR.name}/")
        SHORTCUT.unlink()
        print(f"  [ok] removed {SHORTCUT}")

    print()
    print("  The task runs at logon, 15 s in. Nothing has been started right now -")
    print("  start the agent as usual, or run: schtasks /Run /TN ia-agent")
    print()
    print("  To stop the agent and its launcher:  schtasks /End /TN ia-agent")
    print(f"  To keep it down across logons:      touch {STOP_FILE}")
    return 0


# ---------------------------------------------------------------------- remove


def remove() -> int:
    if task_exists():
        result = schtasks("/Delete", "/TN", TASK_NAME, "/F")
        if result.returncode != 0:
            print(f"  [!!] schtasks /Delete failed: {(result.stderr or result.stdout).strip()}")
            return 1
        print(f"  [ok] deleted task {TASK_NAME}")
    else:
        print(f"  [--] no task named {TASK_NAME}")

    if SHORTCUT.exists():
        print(f"  [--] startup shortcut already in place ({SHORTCUT.name})")
    elif SHORTCUT_BACKUP.exists():
        SHORTCUT.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SHORTCUT_BACKUP, SHORTCUT)
        print(f"  [ok] restored {SHORTCUT}")
    else:
        print(f"  [!!] no backup at {SHORTCUT_BACKUP} — see backups/2026-07-31-dev-startup/MANIFEST.md")

    # The restored shortcut starts the services itself; leaving autostart on would
    # have both of them racing for the same ports at the next logon.
    for name in SERVICE_NAMES:
        settings.update(name, autostart=False)
    print(f"  [ok] autostart off for {', '.join(SERVICE_NAMES)}")
    print()
    print("  Log out and back in — neither the task nor the shortcut runs until a logon.")
    return 0


# ---------------------------------------------------------------------- status


def status() -> int:
    print(f"  task {TASK_NAME}: {'installed' if task_exists() else 'not installed'}")
    if task_exists():
        query = schtasks("/Query", "/TN", TASK_NAME, "/FO", "LIST", "/V")
        wanted = ("Status:", "Last Run Time:", "Last Result:", "Next Run Time:", "Task To Run:")
        for line in query.stdout.splitlines():
            if line.strip().startswith(wanted):
                print(f"    {line.strip()}")
    print(f"  startup shortcut: {'present' if SHORTCUT.exists() else 'removed'} ({SHORTCUT})")
    print(f"  agent on {PORT}: {'answering' if agent_answers() else 'not answering'}")
    if STOP_FILE.exists():
        print(f"  [!?] {STOP_FILE} exists - the launcher will keep the agent down")
    stored = settings.load()
    for name in SERVICE_NAMES:
        entry = stored.get(name, {})
        print(
            f"  {name}: autostart={entry.get('autostart', 'spec default (off)')} "
            f"self_heal={entry.get('self_heal', 'spec default (on)')}"
        )
    for problem in preflight():
        print(f"  [!!] {problem}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("action", choices=("install", "remove", "status"))
    action = parser.parse_args().action
    return {"install": install, "remove": remove, "status": status}[action]()


if __name__ == "__main__":
    raise SystemExit(main())
