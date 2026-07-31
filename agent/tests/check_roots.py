"""Read-only: what would takeover actually kill for each live service?"""
import psutil

from ia_agent.services.registry import build_specs
from ia_agent.services.supervisor import _describe, _port_owner, _service_root

for spec in build_specs():
    owner = _port_owner(spec.probe.port)
    print(f"\n=== {spec.name} (port {spec.probe.port})")
    if owner is None:
        print("  no listener")
        continue
    root = _service_root(owner)
    print(f"  port owner : {owner.pid} {_describe(owner)['cmdline'][:110]}")
    print(f"  kill target: {root.pid} {_describe(root)['cmdline'][:110]}")
    try:
        parent = root.parent()
        print(f"  stopped at : {parent.pid} {parent.name()}" if parent else "  stopped at : (no parent)")
    except psutil.Error:
        print("  stopped at : (unreadable)")
    tree = [root, *root.children(recursive=True)]
    print(f"  would kill : {[(p.pid, p.name()) for p in tree]}")
