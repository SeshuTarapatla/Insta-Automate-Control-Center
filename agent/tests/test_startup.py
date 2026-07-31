"""CP 2.5 — the logon task's shape, and the two Windows behaviours it rests on.

Nothing here installs, deletes or runs anything: the task itself was verified live
(no window in its process tree, agent answering, the three services untouched, a
killed agent healed in 5 s, `schtasks /End` leaving nothing behind). What this pins
is what a future edit could quietly break — the interpreter being GUI-subsystem, the
flags, and the job object that keeps the agent from outliving its launcher.
"""
import ctypes
import importlib.util
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import psutil

from ia_agent import startup

HERE = Path(__file__).parent
DUMMY = HERE / "dummy_service.py"
NS = {"t": "http://schemas.microsoft.com/windows/2004/02/mit/task"}
OK = []


def check(label, condition, detail=""):
    OK.append(bool(condition))
    print(f"  [{'PASS' if condition else 'FAIL'}] {label} {detail}")


def load_launcher():
    """The launcher is a .pyw, so it is loaded by path rather than imported."""
    spec = importlib.util.spec_from_file_location("ia_agent_launcher", startup.LAUNCHER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def pe_subsystem(path: Path) -> int:
    """2 = Windows GUI, 3 = console. The whole no-console-window design is this one
    number: Task Scheduler offers no window style, so a console-subsystem action
    shows a real window (measured, with python.exe and with the venv's pythonw.exe,
    which is a uv trampoline around the console interpreter)."""
    data = path.read_bytes()
    pe = int.from_bytes(data[0x3C:0x40], "little")
    optional_header = pe + 24
    return int.from_bytes(data[optional_header + 68 : optional_header + 70], "little")


print("1. the task XML")
xml = startup.task_xml()
root = ET.fromstring(xml)
command = Path(root.find(".//t:Actions/t:Exec/t:Command", NS).text)
arguments = root.find(".//t:Actions/t:Exec/t:Arguments", NS).text

check("well-formed and namespaced", root.tag.endswith("}Task"))
check("action is the base interpreter", command == startup.base_pythonw(), str(command))
check("action exists on disk", command.exists())
check("action is GUI-subsystem", pe_subsystem(command) == 2, f"subsystem={pe_subsystem(command)}")
check("argument is the launcher", startup.LAUNCHER.name in arguments, arguments)
check("launcher exists on disk", startup.LAUNCHER.exists())
check(
    "runs in the interactive session",
    root.find(".//t:Principal/t:LogonType", NS).text == "InteractiveToken",
)
check(
    "never times out",
    root.find(".//t:Settings/t:ExecutionTimeLimit", NS).text == "PT0S",
)
check(
    "a second instance is ignored",
    root.find(".//t:Settings/t:MultipleInstancesPolicy", NS).text == "IgnoreNew",
)
check(
    "the trigger repeats as an outer net",
    root.find(".//t:LogonTrigger/t:Repetition/t:Interval", NS).text == "PT10M",
)
check("triggered at logon, after a delay", root.find(".//t:LogonTrigger/t:Delay", NS).text == "PT15S")

print("\n2. the launcher")
launcher = load_launcher()
check("CREATE_NO_WINDOW is 0x08000000", launcher.CREATE_NO_WINDOW == 0x08000000)
# DETACHED_PROCESS silently cancels CREATE_NO_WINDOW, which is how a hidden launch
# grows a console window nobody asked for. Read the flags off the call rather than
# grepping the file — the docstring names the trap, and a substring search cannot
# tell an explanation from a mistake.
source = startup.LAUNCHER.read_text(encoding="utf-8")
flags = [
    line.split("creationflags=")[1].strip().rstrip(",")
    for line in source.splitlines()
    if "creationflags=" in line
]
check("spawned with CREATE_NO_WINDOW alone", flags == ["CREATE_NO_WINDOW"], str(flags))
check("restarts on a crash, stops on a clean exit", "if code == 0:" in source)
check("agent exe path is the venv console script", startup.AGENT_EXE.name == "ia-agent.exe")

print("\n3. the job object actually kills what it holds")
# schtasks /End kills the launcher and nothing else — measured, the agent kept
# serving as an orphan on 8787. KILL_ON_JOB_CLOSE is what closes that hole, so this
# asserts the behaviour rather than the constant: a process in the job dies when the
# job handle does.
job = launcher.create_job()
check("job created", job is not None)
child = subprocess.Popen(
    [sys.executable, str(DUMMY), "19881"],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    creationflags=launcher.CREATE_NO_WINDOW,
)
check("child assigned to the job", launcher.assign(job, child.pid))
check("child is alive before the job closes", psutil.pid_exists(child.pid))
ctypes.WinDLL("kernel32").CloseHandle(job)
for _ in range(40):
    if not psutil.pid_exists(child.pid):
        break
    time.sleep(0.1)
check("child died with the job", not psutil.pid_exists(child.pid))
if psutil.pid_exists(child.pid):
    child.kill()

print("\n4. preflight on this machine")
problems = startup.preflight()
check("no problems reported", not problems, "; ".join(problems))

print(f"\n{sum(OK)}/{len(OK)} checks passed")
sys.exit(0 if all(OK) else 1)
