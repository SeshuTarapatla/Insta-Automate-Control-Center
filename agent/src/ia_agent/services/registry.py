import shutil
from pathlib import Path

from ia_agent.services.spec import (
    HealthProbe,
    ProbeKind,
    RestartPolicy,
    ServiceSpec,
)

INSTA_AUTOMATE_DIR = Path(r"D:\Coding\Insta-Automate")
WSL_BRIDGE_DIR = Path(r"D:\Coding\wsl-bridge")

ADB = shutil.which("adb") or r"C:\Users\seshu\.android\platform-tools\adb.exe"


def build_specs() -> list[ServiceSpec]:
    """The three Windows services the pipeline depends on. Autostart stays off in
    CP 2.1: everything here is already running under the wt.exe shortcut, so the
    agent's job for now is to see and adopt it, not to start a second copy.
    CP 2.5 turns autostart on when the agent takes over startup ownership."""
    return [
        ServiceSpec(
            name="adb",
            label="ADB server",
            description="Android Debug Bridge server. Every phone interaction goes through it.",
            # `nodaemon` keeps the server in the foreground so it is supervisable at
            # all — the usual `adb start-server` forks and exits immediately, which
            # would leave nothing to watch. `-a` makes it listen on all interfaces
            # so the pods can reach it via host.docker.internal.
            cmd=[ADB, "-a", "nodaemon", "server", "start"],
            probe=HealthProbe(kind=ProbeKind.TCP, port=5037),
            restart=RestartPolicy.ALWAYS,
            start_grace=10.0,
        ),
        ServiceSpec(
            name="vl-server",
            label="VL server",
            description="qwen3-vl:4b-instruct behind llama-server — gender and privacy classification.",
            cmd=[
                str(INSTA_AUTOMATE_DIR / ".venv" / "Scripts" / "python.exe"),
                str(INSTA_AUTOMATE_DIR / "scripts" / "start_vl_server.py"),
            ],
            cwd=INSTA_AUTOMATE_DIR,
            probe=HealthProbe(kind=ProbeKind.HTTP, port=11500, path="/v1/models"),
            restart=RestartPolicy.ALWAYS,
            # Loading a 4B model takes far longer than a port bind, so the probe is
            # allowed to fail for a while before the tile turns red.
            start_grace=120.0,
            probe_interval=10.0,
        ),
        ServiceSpec(
            name="wsl-bridge",
            label="WSL bridge",
            description="scrcpy shim used for the device mirror. Not modified by this project.",
            cmd=[str(WSL_BRIDGE_DIR / ".venv" / "Scripts" / "wsl-bridge.exe")],
            cwd=WSL_BRIDGE_DIR,
            probe=HealthProbe(kind=ProbeKind.HTTP, port=8000, path="/"),
            restart=RestartPolicy.ALWAYS,
            start_grace=20.0,
        ),
    ]
