# `dev-startup.exe.lnk`

The Startup-folder shortcut that started the pipeline's Windows services at logon, backed up
**2026-07-31** before CP 2.5 replaced it with a Task Scheduler logon task running `ia-agent`.

## Where it lived

```
C:\Users\seshu\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\dev-startup.exe.lnk
```

1560 bytes · SHA256 `6BE3B4DDF7C0BC2AC1EFF123EA78059C1234E981CEA46AEC36B7D0037B6B2D73`
· last modified 2026-06-05 10:56:50.

## What it actually was

Despite the name there is no `dev-startup.exe`. It is a shortcut to **Windows Terminal**, opening
four tabs, one command each:

| Field | Value |
|---|---|
| Target | `C:\Users\seshu\AppData\Local\Microsoft\WindowsApps\wt.exe` |
| Arguments | `adb -a start-server ; ollama serve ; D:\Coding\Insta-Automate\.venv\Scripts\python.exe D:\Coding\Insta-Automate\scripts\start_vl_server.py ; D:\Coding\wsl-bridge\.venv\Scripts\wsl-bridge.exe` |
| Working directory | `C:\Users\seshu\AppData\Local\Microsoft\WindowsApps` |
| Window style | 1 (normal) |
| Icon / description | none |

`;` is `wt.exe`'s tab separator, so that is four tabs: adb, Ollama, vl-server, wsl-bridge.

Two things about it are worth remembering, because they are half the reason CP 2.5 exists:

- **`adb -a start-server` forks.** The tab's command returns immediately and the tab exits, so
  nothing was ever supervising adb — the agent runs `adb -a nodaemon server start` instead (D14).
- **`ollama serve` was redundant twice over.** Nothing in the pipeline talks to port 11434, and
  `Ollama.lnk` is separately in the same Startup folder (D13). It is deliberately *not* carried over,
  which is the one behavioural difference between this shortcut and its replacement.

**Deleted on 2026-07-31** by CP 2.5's installer, which checked this backup's SHA-256 against the live
file first. What replaced it is documented in `../2026-07-31-agent-task/MANIFEST.md`.

## Restoring it

**Either** let the installer do it, which also turns the services' `autostart` switches back off:

```powershell
uv run --project agent python -m ia_agent.startup remove
```

**Or** copy the file back and remove the task by hand:

```powershell
Copy-Item "D:\Coding\Insta-Automate-Control-Center\backups\2026-07-31-dev-startup\dev-startup.exe.lnk" `
          (Join-Path ([Environment]::GetFolderPath('Startup')) 'dev-startup.exe.lnk')
schtasks /Delete /TN "ia-agent" /F
```

**Or** recreate it from nothing, if the backup is ever lost — this produces the same shortcut:

```powershell
$sh = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'dev-startup.exe.lnk'))
$lnk.TargetPath = "C:\Users\seshu\AppData\Local\Microsoft\WindowsApps\wt.exe"
$lnk.Arguments = 'adb -a start-server ; ollama serve ; D:\Coding\Insta-Automate\.venv\Scripts\python.exe D:\Coding\Insta-Automate\scripts\start_vl_server.py ; D:\Coding\wsl-bridge\.venv\Scripts\wsl-bridge.exe'
$lnk.WorkingDirectory = "C:\Users\seshu\AppData\Local\Microsoft\WindowsApps"
$lnk.Save()
```

Either way, log out and back in — neither the shortcut nor the task runs until a logon.

## The rest of that Startup folder, for reference

Untouched by this project, recorded so a future session can tell what it did not do:
`Citrix Workspace.lnk`, `Ollama.lnk`, `RBTray.exe - Shortcut.lnk`, `ShareX.lnk`.
