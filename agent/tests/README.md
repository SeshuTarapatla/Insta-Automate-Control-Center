# Agent verification scripts

Standalone scripts, not a pytest suite — run them directly. They exist because the supervisor's
interesting behaviour is process lifecycle, which unit-level mocking would not have caught: the
`origin = NONE` race in D9 and the launcher-restart-loop problem in D11 were both found here.

```
uv run --project agent python agent/tests/test_supervisor.py     # 57 checks, engine level
uv run --project agent python agent/tests/test_e2e.py            # 32 checks, real app + real WS
uv run --project agent python agent/tests/test_dependencies.py   # 26 checks, cluster faked out
uv run --project agent python agent/tests/check_roots.py         # read-only, live machine
uv run --project agent python agent/tests/check_services.py      # runs the real self-tests
uv run --project agent python agent/tests/check_deps.py [-v]     # runs the real dependency panel
```

The `check_*` scripts are the only ones that touch the real adb / vl-server / wsl-bridge / cluster,
and all three are read-only. The wsl-bridge test leaves an existing scrcpy mirror alone by design.

`test_dependencies.py` fakes the cluster on purpose: the live one is green, so a paused work pool,
an unattended pool and a crash-looping pod cannot be exercised against it without breaking the
user's pipeline — and those are the cases the panel exists for.

Both test scripts redirect `settings.SERVICE_SETTINGS_PATH` at import so flipping self-heal never
touches the real `services.json`.

`test_supervisor.py` and `test_e2e.py` drive `dummy_service.py` on ports 19801–19810 and 8789, so
they never touch adb, vl-server or wsl-bridge. `check_roots.py` *reads* the live machine and prints
what a takeover of each real service would kill — it starts and stops nothing.

Both test scripts exit non-zero on the first failing check, so they work as a pre-commit gate.
