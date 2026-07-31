# The `ia-agent` logon task

What CP 2.5 installed on this machine on **2026-07-31**, recorded so a future session can tell
exactly what was changed outside this repo and undo it.

## What changed

| Thing | Before | After |
|---|---|---|
| `…\Startup\dev-startup.exe.lnk` | present, four `wt.exe` tabs | **deleted** (backed up in `../2026-07-31-dev-startup/`) |
| Task Scheduler `\ia-agent` | did not exist | logon task, XML below |
| `%LOCALAPPDATA%\ia-agent\services.json` | did not exist | `autostart: true` for `adb`, `vl-server`, `wsl-bridge` |

`ia-agent-task.xml` in this folder is the exact XML that was registered (the installer writes it
here on every `install`, so it stays in step). The live copy Task Scheduler read is at
`%LOCALAPPDATA%\ia-agent\ia-agent-task.xml`, UTF-16 as `schtasks /XML` requires.

Nothing else in the Startup folder was touched: `Citrix Workspace.lnk`, `Ollama.lnk`,
`RBTray.exe - Shortcut.lnk`, `ShareX.lnk` are all still there.

## Undo

```powershell
uv run --project agent python -m ia_agent.startup remove
```

That deletes the task, copies the shortcut back from `../2026-07-31-dev-startup/`, and turns the
three `autostart` switches off again (leaving them on would have the restored shortcut and the agent
racing for the same ports at the next logon). Log out and back in — neither the task nor the
shortcut runs until a logon.

`… startup status` prints the current state of all of it without changing anything.

## Operating it

| Want | Do |
|---|---|
| start it now | `schtasks /Run /TN ia-agent` |
| stop the agent *and* its launcher | `schtasks /End /TN ia-agent` |
| keep it down across logons | create `%LOCALAPPDATA%\ia-agent\stop-launcher`, then `/End` |
| read what it did | `%LOCALAPPDATA%\ia-agent\logs\startup.log` |

The launcher restarts the agent on any non-zero exit (5 s, doubling to 300 s), so killing the agent
alone is not a way to stop it — that is what `/End` and the sentinel file are for. Killing the
launcher is enough, though: the agent is held in a job object and goes down with it.

## Why it is shaped this way

Measured on 2026-07-31, all four the hard way — see DECISIONS D20–D22:

- A console-subsystem action shows a real console window under a logon task, `<Hidden>` or not, and
  the venv's `pythonw.exe` is a uv trampoline that re-execs the console interpreter. The base
  interpreter's `pythonw.exe` (PE subsystem 2) shows nothing.
- `CREATE_NO_WINDOW` is cancelled by `DETACHED_PROCESS`, so the launcher passes it alone.
- `RestartOnFailure` did **not** restart a killed agent (`Last Result: 1`, `Status: Ready`, three
  minutes of nothing), so the launcher heals the agent and the trigger's 10-minute repetition is the
  net for the launcher itself. Repetition *was* measured to work: 55 s to restart a killed task.
- `schtasks /End` killed only the launcher and left the agent orphaned on port 8787, hence the job
  object.

One behaviour to know until CP 2.6 lands: anything the agent supervises dies when the agent dies,
so a restart of the agent cycles all three services (D22).
