"""Stand-in for "the agent" in CP 2.6's kill-survival test.

Spawns one real service through the real Supervisor/host path, exactly like the
actual agent does, then blocks so the outer test can `taskkill /F` and `taskkill
/F /T` *this* process and prove the service it spawned keeps running (D22). The
old adoption test built two Supervisors inside one process, where the pty handles
never closed — this is the genuinely separate process that test structurally
could not be.
"""
import asyncio
import sys
from pathlib import Path

from ia_agent.events.bus import EventBus
from ia_agent.services.spec import HealthProbe, ProbeKind, ServiceSpec
from ia_agent.services.supervisor import Supervisor

HERE = Path(__file__).parent
DUMMY = HERE / "dummy_service.py"


async def main() -> None:
    name, port = sys.argv[1], int(sys.argv[2])
    spec = ServiceSpec(
        name=name,
        label=name,
        cmd=[sys.executable, str(DUMMY), str(port)],
        probe=HealthProbe(kind=ProbeKind.TCP, port=port, timeout=1.0),
        probe_interval=0.5,
        start_grace=3.0,
    )
    sup = Supervisor([spec], EventBus())
    sup.get(name).start()
    while True:
        await sup.get(name).tick()
        await asyncio.sleep(0.1)


if __name__ == "__main__":
    asyncio.run(main())
