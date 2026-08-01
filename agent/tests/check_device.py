"""Exercise CP 4.5's device integration against the live machine. Strictly
read-only: checks wsl-bridge's health/mirroring status and, if a real scrcpy
process is already running, confirms `window.find_window_by_pid` locates its
window — without moving it. Starting/stopping scrcpy or actually snapping a
window is deliberately left to `POST /api/device/scrcpy/{start|stop}` on a
real agent (or `test_device.py`'s mocks) rather than this script, the same
"don't be rude to an active mirror" discipline `test_wsl_bridge()`'s selftest
already established."""
import asyncio
import sys

import psutil

from ia_agent import window
from ia_agent.integrations import wsl_bridge
from ia_agent.vars import ANDROID_SERIAL


async def main() -> int:
    print(f"ANDROID_SERIAL: {ANDROID_SERIAL or '(not set)'}")

    healthy = await wsl_bridge.bridge_healthy()
    print(f"wsl-bridge healthy: {healthy}")
    if not healthy:
        print("FAIL: wsl-bridge is not reachable at http://127.0.0.1:8000")
        return 1

    mirroring = await wsl_bridge.scrcpy_status()
    print(f"currently mirroring: {mirroring}")

    scrcpy_procs = [p for p in psutil.process_iter(["pid", "name"]) if (p.info["name"] or "").lower() == "scrcpy.exe"]
    if not scrcpy_procs:
        print("no scrcpy.exe process found — nothing further to check (read-only script, won't start one)")
        return 0

    pid = scrcpy_procs[0].info["pid"]
    print(f"found real scrcpy.exe pid: {pid}")
    hwnd = window.find_window_by_pid(pid)
    print(f"find_window_by_pid -> hwnd {hwnd}")
    if hwnd is None:
        print("FAIL: could not locate the window for a real running scrcpy.exe")
        return 1

    print("PASS: the window-lookup mechanism correctly finds the real scrcpy window by pid")
    print("(snap_to_known_position was NOT called — that would move a window you may be looking at)")
    return 0


sys.exit(asyncio.run(main()))
