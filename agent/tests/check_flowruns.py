"""Exercise CP 4.1's Prefect/k8s integration functions against the live machine.
Strictly read-only: every call here is a GET or a filter POST that Prefect and
k8s already serve for any client, and none of it starts, adopts or otherwise
touches a service or flow run."""
import asyncio
import sys

from ia_agent.flowruns import FLOWS, SCHEDULER_POD_DEPLOYMENT
from ia_agent.integrations import kube, prefect


async def main() -> int:
    print("-- resolving deployment ids for the five flows")
    ids: dict[str, str] = {}
    for flow in FLOWS:
        resolved = await prefect.deployment_id(flow)
        print(f"  {flow:<18} {resolved}")
        if resolved:
            ids[flow] = resolved
    if len(ids) != len(FLOWS):
        print("FAIL: not every flow resolved a deployment id")
        return 1

    print("\n-- recent flow runs across all five deployments")
    runs = await prefect.flow_runs_filter(deployment_ids=list(ids.values()), limit=8)
    by_deployment = {v: k for k, v in ids.items()}
    for run in runs:
        flow = by_deployment.get(run.get("deployment_id"), "?")
        print(f"  {run['id']}  {flow:<18} {run.get('state_type'):<10} start={run.get('start_time')}")
    if not runs:
        print("no flow runs exist yet on this pool — nothing further to check")
        return 0

    sample = runs[0]
    print(f"\n-- logs for the most recent run ({sample['id']}, {by_deployment.get(sample.get('deployment_id'))})")
    rows = await prefect.run_logs(sample["id"], limit=10)
    print(f"  {len(rows)} rows (capped at 10)")
    for row in rows[:5]:
        print(f"    [{row['level']}] {row['timestamp']} {row['message'][:80]}")
    task_row = next((r for r in rows if r.get("task_run_id")), None)
    if task_row:
        name = await prefect.task_run_name(task_row["task_run_id"])
        print(f"  task_run_id {task_row['task_run_id']} resolved to: {name}")

    print(f"\n-- tailing the scheduler pod's container log ({SCHEDULER_POD_DEPLOYMENT})")
    lines = await asyncio.to_thread(kube.pod_logs, SCHEDULER_POD_DEPLOYMENT, None, 20)
    print(f"  {len(lines)} lines (tail_lines=20)")
    for ts, text in lines[-5:]:
        print(f"    {ts}  {text[:90]}")
    if lines:
        again = await asyncio.to_thread(kube.pod_logs, SCHEDULER_POD_DEPLOYMENT, 2, 20)
        print(f"  re-polled with since_seconds=2 -> {len(again)} new line(s)")

    print("\nall checks completed")
    return 0


sys.exit(asyncio.run(main()))
