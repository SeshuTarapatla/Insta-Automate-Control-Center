"""Run the dependency panel against the live machine. Strictly read-only: it opens
sockets to k3s, Postgres, Prefect, adb and 1.1.1.1, and changes nothing."""
import asyncio
import json
import sys
import time

from ia_agent import dependencies

MARK = {"ok": "OK  ", "warn": "WARN", "fail": "FAIL"}


async def main() -> int:
    started = time.perf_counter()
    items = await dependencies.snapshot(force=True)
    total = (time.perf_counter() - started) * 1000

    group = None
    for item in items:
        if item["group"] != group:
            group = item["group"]
            print(f"\n-- {group}")
        print(f"  [{MARK[item['level']]}] {item['key']:<15} {item['latency_ms']:>6.0f}ms  "
              f"{item['detail']}")
        if item["metrics"] and "-v" in sys.argv:
            print(f"          {json.dumps(item['metrics'], default=str)}")

    failed = [item['key'] for item in items if item["level"] == "fail"]
    warned = [item['key'] for item in items if item["level"] == "warn"]
    print(f"\n{len(items)} checks in {total:.0f} ms (concurrent)")
    if warned:
        print(f"warn: {', '.join(warned)}")
    print(f"fail: {', '.join(failed)}" if failed else "all green")
    return 1 if failed else 0


sys.exit(asyncio.run(main()))
