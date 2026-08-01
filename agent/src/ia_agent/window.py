"""Native window positioning via raw ctypes (CP 4.5) — the same
`ctypes.windll.user32` approach `my_modules.win32.snap_window` already uses
(no `pywin32` dependency), but finding the window by **PID** rather than
title. scrcpy's window title varies by phone model (no fixed string to
search for), and `my_modules`/wsl-bridge are marked "no changes expected"
(ARCHITECTURE §8), so title normalization there wasn't an option — the PID
wsl-bridge already returns from `POST /scrcpy/start` is exact and needs no
cooperation from either repo.
"""
import ctypes
from ctypes import wintypes

_user32 = ctypes.windll.user32
_EnumWindowsProc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)


def find_window_by_pid(pid: int) -> int | None:
    found: list[int] = []

    def _callback(hwnd: int, _lparam: int) -> bool:
        owner_pid = wintypes.DWORD()
        _user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner_pid))
        if owner_pid.value == pid and _user32.IsWindowVisible(hwnd):
            found.append(hwnd)
            return False  # stop enumeration, found it
        return True

    _user32.EnumWindows(_EnumWindowsProc(_callback), 0)
    return found[0] if found else None


def snap_to_known_position(pid: int, x: int = 1, y: int = 45) -> bool:
    """Re-asserts the window at a known screen position **without resizing
    it** — purely defensive. `my_modules.scrcpy.Scrcpy.start()` already
    requests this exact position (`--window-x=1 --window-y=45`) at launch;
    this exists only for the rare case a compositor/DPI quirk ignores that
    initial hint. Reads the window's own current size first so this can
    never squish or stretch the video."""
    hwnd = find_window_by_pid(pid)
    if hwnd is None:
        return False
    rect = wintypes.RECT()
    _user32.GetWindowRect(hwnd, ctypes.byref(rect))
    width = rect.right - rect.left
    height = rect.bottom - rect.top
    return bool(_user32.MoveWindow(hwnd, x, y, width, height, True))
