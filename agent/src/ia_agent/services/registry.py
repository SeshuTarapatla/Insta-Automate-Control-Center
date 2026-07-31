import shutil
from pathlib import Path

from ia_agent.services.selftest import (
    adb_device_present,
    test_adb,
    test_vl_server,
    test_wsl_bridge,
)
from ia_agent.services.spec import HealthProbe, ProbeKind, ServiceSpec

INSTA_AUTOMATE_DIR = Path(r"D:\Coding\Insta-Automate")
WSL_BRIDGE_DIR = Path(r"D:\Coding\wsl-bridge")

ADB = shutil.which("adb") or r"C:\Users\seshu\.android\platform-tools\adb.exe"


def build_specs() -> list[ServiceSpec]:
    """The three core services the pipeline depends on, replacing the four tabs of
    the `dev-startup.exe.lnk` shortcut:

        wt.exe  adb -a start-server ; ollama serve ;
                python start_vl_server.py ; wsl-bridge.exe

    `ollama serve` is deliberately absent — nothing in the pipeline talks to 11434
    (`vars.py` points at `VL_SERVER_URL` on 11500, and `OLLAMA_URL` is defined but
    unused), `start_vl_server.py` needs Ollama installed rather than serving, and
    Ollama.lnk already starts it at login. See D13.

    These values are defaults. `self_heal` and `autostart` are overridden per service
    from services.json, so the switches survive a restart. `autostart` stays *off* in
    the spec so that running the agent from a source checkout never spawns services
    behind your back; CP 2.5's installer turns it on in services.json for all three,
    which is what the logon task starts from. See `ia_agent.startup`."""
    return [
        ServiceSpec(
            name="adb",
            label="ADB server",
            description="Android Debug Bridge server. Every phone interaction goes through it.",
            # `nodaemon` keeps the server in the foreground so it is supervisable at
            # all — the shortcut's `adb -a start-server` forks and the tab exits,
            # which is why nothing supervises adb today. `-a` makes it listen on all
            # interfaces so the pods can reach it via host.docker.internal.
            cmd=[ADB, "-a", "nodaemon", "server", "start"],
            probe=HealthProbe(kind=ProbeKind.TCP, port=5037),
            # A listening adb server with no phone attached is green on port and
            # useless to the pipeline, so the probe checks the device list too.
            probe_extra=adb_device_present,
            self_test=test_adb,
            start_grace=10.0,
        ),
        ServiceSpec(
            name="vl-server",
            label="VL server",
            description="qwen3-vl:4b-instruct behind llama-server — gender and privacy classification.",
            # --no-autorestart hands restart duty to the agent. The launcher's own
            # loop (start_vl_server.py) would otherwise be a second supervisor: it
            # would resurrect llama-server underneath a stop or takeover, and its
            # restart count would stay invisible in a terminal tab. The flag already
            # exists, so this needs no change in the Insta-Automate repo. See D14.
            cmd=[
                str(INSTA_AUTOMATE_DIR / ".venv" / "Scripts" / "python.exe"),
                str(INSTA_AUTOMATE_DIR / "scripts" / "start_vl_server.py"),
                "--no-autorestart",
            ],
            cwd=INSTA_AUTOMATE_DIR,
            probe=HealthProbe(kind=ProbeKind.HTTP, port=11500, path="/v1/models"),
            self_test=test_vl_server,
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
            self_test=test_wsl_bridge,
            start_grace=20.0,
        ),
    ]
