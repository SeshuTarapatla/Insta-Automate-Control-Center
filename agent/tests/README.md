# Agent verification scripts

Standalone scripts, not a pytest suite — run them directly. They exist because the supervisor's
interesting behaviour is process lifecycle, which unit-level mocking would not have caught: the
`origin = NONE` race in D9 and the launcher-restart-loop problem in D11 were both found here.

```
uv run --project agent python agent/tests/test_supervisor.py     # 57 checks, engine level
uv run --project agent python agent/tests/test_e2e.py            # 32 checks, real app + real WS
uv run --project agent python agent/tests/test_dependencies.py   # 26 checks, cluster faked out
uv run --project agent python agent/tests/test_ui_contract.py    # 49 checks, payloads the app decodes
uv run --project agent python agent/tests/test_scheduler.py      # 24 checks, scheduler mirror (CP 3.4)
uv run --project agent python agent/tests/test_startup.py        # 20 checks, logon task install/remove
uv run --project agent python agent/tests/test_flowruns.py       # 36 checks, flow-run log tailer (CP 4.1)
uv run --project agent python agent/tests/test_events.py         # 35 checks, flow-event + image cache (CP 4.2)
uv run --project agent python agent/tests/check_roots.py         # read-only, live machine
uv run --project agent python agent/tests/check_services.py      # runs the real self-tests
uv run --project agent python agent/tests/check_deps.py [-v]     # runs the real dependency panel
uv run --project agent python agent/tests/check_flowruns.py      # read-only, real Prefect + k3s log calls
```

The `check_*` scripts are the only ones that touch the real adb / vl-server / wsl-bridge / cluster,
and all three are read-only. The wsl-bridge test leaves an existing scrcpy mirror alone by design.

`test_dependencies.py` fakes the cluster on purpose: the live one is green, so a paused work pool,
an unattended pool and a crash-looping pod cannot be exercised against it without breaking the
user's pipeline — and those are the cases the panel exists for.

Both test scripts redirect `settings.SERVICE_SETTINGS_PATH` at import so flipping self-heal never
touches the real `services.json`.

`test_ui_contract.py` is the app's side of the same endpoints: it asserts the payload *shapes*
`app/lib/core/service_models.dart` and `dependency_models.dart` decode, because Dart's casts throw
where Python's dict access shrugs (`as int?` on a float, `as bool?` on a 0/1, a renamed key). Its
field tables are transcribed from those two files and have to be kept in step with them. It also
pins the one contract that is not obvious from the endpoints: the ring is written by the reader
thread while the WS batch for the same chunks is published on the next tick, so a client that
replays and then subscribes **will** see chunks twice — overlap is expected and deduped by `seq` in
the pane; a *gap* would be the bug.

`test_supervisor.py` and `test_e2e.py` drive `dummy_service.py` on ports 19801–19810 and 8789, so
they never touch adb, vl-server or wsl-bridge. `check_roots.py` *reads* the live machine and prints
what a takeover of each real service would kill — it starts and stops nothing.

Both test scripts exit non-zero on the first failing check, so they work as a pre-commit gate.
