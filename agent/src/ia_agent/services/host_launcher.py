"""Spawns the service host and exits immediately — CP 2.6.

The whole reason this exists as a separate hop rather than the agent spawning
`host.py` directly: `taskkill /F /T` walks the *live* process tree from its target
pid at the moment it runs. If the agent spawned the host directly, the host would
be a live child of a live agent for as long as both ran, and a tree-kill aimed at
the agent would find and kill it too — exactly the failure D22 measured and this
checkpoint exists to fix. By spawning the host and exiting immediately, this
process is gone (typically within milliseconds) by the time anyone tree-kills the
agent, so the host — whose `ppid` still points at this now-dead launcher — is
unreachable from that walk. No job object, no breakaway flag: Windows does not
kill a child when its immediate parent exits, it only orphans it.

Run as `python -m ia_agent.services.host_launcher <name>`, itself spawned by the
agent with `CREATE_NO_WINDOW` passed alone (D20: combined with `DETACHED_PROCESS`
or `CREATE_NEW_CONSOLE`, Windows silently ignores it and a console window appears).
"""
import subprocess
import sys

CREATE_NO_WINDOW = 0x08000000


def main(name: str) -> int:
    subprocess.Popen(
        [sys.executable, "-m", "ia_agent.services.host", name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL,
        creationflags=CREATE_NO_WINDOW,
        close_fds=True,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
