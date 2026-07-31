import asyncio
import time
from dataclasses import dataclass

import httpx

from ia_agent.services.spec import HealthProbe, ProbeKind


@dataclass(frozen=True)
class ProbeResult:
    ok: bool
    latency_ms: float
    detail: str
    at: float

    def as_dict(self) -> dict:
        return {
            "ok": self.ok,
            "latency_ms": round(self.latency_ms, 1),
            "detail": self.detail,
            "at": self.at,
        }


async def _tcp(probe: HealthProbe) -> tuple[bool, str]:
    writer = None
    try:
        _, writer = await asyncio.wait_for(
            asyncio.open_connection(probe.host, probe.port), timeout=probe.timeout
        )
        return True, f"tcp {probe.host}:{probe.port} open"
    except (OSError, asyncio.TimeoutError) as error:
        return False, f"tcp {probe.host}:{probe.port} — {error or type(error).__name__}"
    finally:
        if writer is not None:
            writer.close()


async def _http(probe: HealthProbe) -> tuple[bool, str]:
    url = f"http://{probe.host}:{probe.port}{probe.path}"
    try:
        async with httpx.AsyncClient(timeout=probe.timeout) as client:
            response = await client.get(url)
        ok = response.status_code == probe.expect_status
        return ok, f"GET {probe.path} → {response.status_code}"
    except httpx.HTTPError as error:
        return False, f"GET {probe.path} — {error or type(error).__name__}"


async def run_probe(probe: HealthProbe) -> ProbeResult:
    started = time.perf_counter()
    if probe.kind == ProbeKind.HTTP:
        ok, detail = await _http(probe)
    else:
        ok, detail = await _tcp(probe)
    return ProbeResult(
        ok=ok, latency_ms=(time.perf_counter() - started) * 1000, detail=detail, at=time.time()
    )
