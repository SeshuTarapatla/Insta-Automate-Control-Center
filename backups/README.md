# Backups

Anything this project changes **outside its own repo** — a machine-level file, a startup entry, a
scheduled task — is copied here first, with the restore steps written down beside it. Standing user
requirement (2026-07-31): the overhaul may change how the machine works, provided every file it
touches can be put back.

One directory per change, named `<date>-<what>`, containing the original file verbatim plus a
`MANIFEST.md` that records where it came from, what it did, and **two** ways to restore it: copy the
file back, and recreate it from scratch. The second matters — a `.lnk` is a binary blob, and a
backup you cannot read is a backup you cannot check.

| Directory | What it is | Replaced by | Status |
|---|---|---|---|
| `2026-07-31-dev-startup/` | `dev-startup.exe.lnk`, the Startup-folder shortcut that launched four `wt.exe` tabs | the `ia-agent` logon task (CP 2.5) | active rollback |

These files are committed deliberately. They are small, contain no secrets, and a backup that lives
only on the machine being changed is not a backup.
