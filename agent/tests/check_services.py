"""Probe the real services and run their functional tests. Read-only: nothing is
started, stopped or restarted, and an existing scrcpy mirror is left alone."""
import asyncio
import json
import sys

from ia_agent.services import selftest
from ia_agent.services.probes import run_probe
from ia_agent.services.registry import build_specs


async def main() -> int:
    failures = 0
    for spec in build_specs():
        probe = await run_probe(spec.probe, spec.probe_extra)
        print(f"\n=== {spec.name}  (port {spec.probe.port})")
        print(f"  probe : {'ok' if probe.ok else 'FAIL'}  {probe.latency_ms:.0f} ms")
        print(f"          {probe.detail}")
        failures += not probe.ok

        if spec.self_test is None:
            print("  test  : none defined")
            continue

        outcome = await selftest.run(spec.self_test, spec.name)
        print(f"  test  : {'ok' if outcome.ok else 'FAIL'}  {outcome.duration_ms:.0f} ms")
        print(f"          {outcome.summary}")
        print(f"          {json.dumps(outcome.metrics, default=str)}")
        failures += not outcome.ok

    print(f"\n{'all good' if not failures else f'{failures} failure(s)'}")
    return 1 if failures else 0


sys.exit(asyncio.run(main()))
