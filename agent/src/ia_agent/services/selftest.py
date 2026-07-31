import asyncio
import base64
import time
from pathlib import Path

import httpx

from ia_agent.logging import logger
from ia_agent.services.spec import TestOutcome
from ia_agent.vars import ANDROID_SERIAL

FIXTURE = Path(__file__).parent / "fixtures" / "row_crop.jpg"

# Mirrors AccessPrediction / GenderPrediction in insta_automate.models.meta. The
# point of the test is that the model still returns something that parses into the
# pipeline's enum, so the accepted values have to match the pipeline's exactly.
GENDER_VALUES = {"male", "female", "undef"}
VL_MODEL = "qwen3-vl:4b-instruct"

# The fixture is 1080x198 and encodes to ~231 prompt tokens with
# --image-min-tokens 64. Under Ollama's hardcoded floor of 1024 the same image
# costs ~1067 tokens and encoding takes 7-12 s on a CPU CLIP encoder — the exact
# regression start_vl_server.py exists to prevent. Token count is the honest
# discriminator here because, unlike wall-clock, it does not move with machine load.
VL_TOKEN_CEILING = 800


def _outcome(started: float, ok: bool, summary: str, **metrics) -> TestOutcome:
    return TestOutcome(
        ok=ok,
        summary=summary,
        metrics=metrics,
        duration_ms=(time.perf_counter() - started) * 1000,
        at=time.time(),
    )


# ---------------------------------------------------------------------- adb


async def adb_device_present() -> tuple[bool, str]:
    """Probe extra: a listening adb server with no phone attached is useless to the
    pipeline, so the probe asks whether ANDROID_SERIAL is actually in the list."""
    devices = await asyncio.to_thread(_adb_devices)
    if ANDROID_SERIAL and ANDROID_SERIAL not in devices:
        return False, f"device {ANDROID_SERIAL} not attached (saw {devices or 'none'})"
    return True, f"device {ANDROID_SERIAL or 'any'} attached"


def _adb_devices() -> list[str]:
    import adbutils

    client = adbutils.AdbClient(host="127.0.0.1", port=5037)
    return [device.serial for device in client.device_list()]


async def test_adb() -> TestOutcome:
    started = time.perf_counter()
    if not ANDROID_SERIAL:
        return _outcome(started, False, "ANDROID_SERIAL is not set in Insta-Automate/.env")

    def run() -> tuple[str, str]:
        import adbutils

        client = adbutils.AdbClient(host="127.0.0.1", port=5037)
        device = client.device(serial=ANDROID_SERIAL)
        return device.shell("echo ok").strip(), device.prop.model or "?"

    try:
        echoed, model = await asyncio.to_thread(run)
    except Exception as error:
        return _outcome(started, False, f"shell failed: {type(error).__name__}: {error}")

    ok = echoed == "ok"
    return _outcome(
        started,
        ok,
        f"{model} responded to a shell command" if ok else f"unexpected shell output: {echoed!r}",
        serial=ANDROID_SERIAL,
        model=model,
    )


# ----------------------------------------------------------------- vl-server


async def test_vl_server() -> TestOutcome:
    """Real inference on a bundled fixture. This is the test worth having: a healthy
    /v1/models says the port is open, but only an actual classification tells you
    whether images take 0.2 s or 12 s — the difference between the tuned
    --image-min-tokens path and Ollama's default, which is the entire reason
    start_vl_server.py exists."""
    started = time.perf_counter()
    if not FIXTURE.exists():
        return _outcome(started, False, f"fixture missing: {FIXTURE}")

    encoded = base64.b64encode(FIXTURE.read_bytes()).decode()
    payload = {
        "model": VL_MODEL,
        "messages": [
            {"role": "system", "content": "You are a gender classifier. Output only JSON."},
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "Predict"},
                    {"type": "image_url",
                     "image_url": {"url": f"data:image/jpeg;base64,{encoded}"}},
                ],
            },
        ],
        "temperature": 0,
        "max_tokens": 20,
        "response_format": {
            "type": "json_schema",
            "json_schema": {
                "name": "GenderPrediction",
                "schema": {
                    "type": "object",
                    "properties": {"result": {"type": "string", "enum": sorted(GENDER_VALUES)}},
                    "required": ["result"],
                },
                "strict": True,
            },
        },
    }

    try:
        async with httpx.AsyncClient(base_url="http://127.0.0.1:11500/v1", timeout=180) as client:
            # Two passes. The first is cold — measured at 420-750 ms here against
            # ~150 ms warm — and a real classify run does images back to back, so
            # reporting the cold number would overstate the steady state by 3-5x and
            # read like a regression that is not there.
            cold_started = time.perf_counter()
            await client.post("/chat/completions", json=payload)
            cold_ms = (time.perf_counter() - cold_started) * 1000

            warm_started = time.perf_counter()
            response = await client.post("/chat/completions", json=payload)
            elapsed_ms = (time.perf_counter() - warm_started) * 1000
            response.raise_for_status()
            body = response.json()
    except httpx.HTTPError as error:
        return _outcome(started, False, f"inference failed: {type(error).__name__}: {error}")

    try:
        content = body["choices"][0]["message"]["content"]
        import json

        verdict = json.loads(content)["result"]
    except (KeyError, IndexError, ValueError) as error:
        return _outcome(started, False, f"response did not parse: {error}")

    if verdict not in GENDER_VALUES:
        return _outcome(started, False, f"verdict {verdict!r} is outside the pipeline's enum")

    usage = body.get("usage") or {}
    tokens = usage.get("prompt_tokens")
    metrics = dict(
        ms_per_image=round(elapsed_ms, 1),
        first_call_ms=round(cold_ms, 1),
        verdict=verdict,
        prompt_tokens=tokens,
        model=body.get("model"),
    )

    if tokens and tokens > VL_TOKEN_CEILING:
        return _outcome(
            started, False,
            f"{tokens} prompt tokens for a 1080x198 crop — the image-token floor "
            "looks wrong, so classification is on the slow path",
            **metrics,
        )

    return _outcome(
        started, True,
        f"classified the fixture at {elapsed_ms:.0f} ms/image, {tokens} prompt tokens "
        f"(verdict: {verdict})",
        **metrics,
    )


# ---------------------------------------------------------------- wsl-bridge


async def test_wsl_bridge() -> TestOutcome:
    """Deliberately non-destructive when the mirror is already up. `POST
    /scrcpy/start` calls stop() on the way in (wsl_bridge/scrcpy.py:23), so cycling
    it would kill a mirror in use and throw a new scrcpy window onto the screen. If
    scrcpy is already running the control plane has answered the only question the
    test can ask without being rude."""
    started = time.perf_counter()
    base = "http://127.0.0.1:8000"
    try:
        async with httpx.AsyncClient(base_url=base, timeout=30) as client:
            root = await client.get("/")
            if root.json() is not True:
                return _outcome(started, False, f"GET / returned {root.text!r}, expected true")

            already = (await client.get("/scrcpy/")).json() is True
            if already:
                return _outcome(
                    started, True,
                    "bridge healthy; scrcpy already mirroring, left running",
                    scrcpy_was_running=True,
                )

            if not ANDROID_SERIAL:
                return _outcome(started, False, "ANDROID_SERIAL is not set, cannot start scrcpy")

            start = await client.post("/scrcpy/start", params={"serial": ANDROID_SERIAL})
            start.raise_for_status()
            pid = start.json().get("pid")

            running = False
            for _ in range(20):
                await asyncio.sleep(0.25)
                if (await client.get("/scrcpy/")).json() is True:
                    running = True
                    break

            await client.post("/scrcpy/stop")
            stopped = (await client.get("/scrcpy/")).json() is not True
    except httpx.HTTPError as error:
        return _outcome(started, False, f"bridge call failed: {type(error).__name__}: {error}")

    ok = running and stopped
    return _outcome(
        started,
        ok,
        "started, confirmed and stopped a scrcpy session" if ok
        else f"scrcpy did not cycle cleanly (started={running}, stopped={stopped})",
        scrcpy_was_running=False,
        scrcpy_pid=pid,
    )


async def run(test, name: str) -> TestOutcome:
    started = time.perf_counter()
    try:
        return await test()
    except Exception as error:
        logger.exception(f"{name}: self-test raised")
        return _outcome(started, False, f"test raised {type(error).__name__}: {error}")
