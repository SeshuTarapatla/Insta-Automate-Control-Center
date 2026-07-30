import asyncio

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ia_agent.config import env_file
from ia_agent.config.schema import SCHEMA, ConfigType, SWITCH_KEYS
from ia_agent.vars import CONFIG_PATH

router = APIRouter(prefix="/api")

# Serializes PATCH requests so two concurrent edits can't clobber each other via a
# stale read-modify-write of the same file.
_write_lock = asyncio.Lock()


class ConfigPatch(BaseModel):
    switches: dict[str, bool] | None = None
    entity_queue: list[str] | None = None
    limits: dict[str, int] | None = None


def _read_config() -> dict:
    data = env_file.load(CONFIG_PATH)
    if data is None:
        raise HTTPException(status_code=404, detail="config.env not found")

    return {
        "values": {
            "switches": {key: value == "1" for key, value in data.switches.items()},
            "entity_queue": data.entity_queue,
            "limits": data.limits,
        },
        "schema": list(SCHEMA.values()),
        "provenance": {key: ("file" if key in data.explicit_keys else "default") for key in SCHEMA},
    }


@router.get("/config/schema")
async def get_schema() -> list:
    return list(SCHEMA.values())


@router.get("/config")
async def get_config() -> dict:
    return _read_config()


@router.patch("/config")
async def patch_config(patch: ConfigPatch) -> dict:
    async with _write_lock:
        data = env_file.load(CONFIG_PATH)
        if data is None:
            raise HTTPException(status_code=404, detail="config.env not found")

        errors: list[str] = []
        new_switches = dict(data.switches)
        new_limits = dict(data.limits)

        for key, value in (patch.switches or {}).items():
            if key not in SWITCH_KEYS:
                errors.append(f"unknown switch key: {key}")
                continue
            new_switches[key] = "1" if value else "0"

        for key, value in (patch.limits or {}).items():
            spec = SCHEMA.get(key)
            if spec is None or spec.type != ConfigType.INT:
                errors.append(f"unknown limit key: {key}")
                continue
            if spec.min is not None and value < spec.min:
                errors.append(f"{key} must be >= {spec.min}")
                continue
            if spec.max is not None and value > spec.max:
                errors.append(f"{key} must be <= {spec.max}")
                continue
            new_limits[key] = value

        new_queue = patch.entity_queue if patch.entity_queue is not None else data.entity_queue

        # Cross-checks run against the merged result, not just the patched keys, so
        # a partial PATCH can't leave the file in a state these rules forbid.
        if new_limits["SCRAPE_BATCH"] > new_limits["SCRAPE"]:
            errors.append("SCRAPE_BATCH must be <= SCRAPE")
        if new_limits["FOLLOW_BATCH"] > new_limits["FOLLOW"]:
            errors.append("FOLLOW_BATCH must be <= FOLLOW")
        if new_limits["FMIN"] >= new_limits["FMAX"]:
            errors.append("FMIN must be < FMAX")

        if errors:
            raise HTTPException(status_code=422, detail={"errors": errors})

        env_file.save(CONFIG_PATH, data, entity_queue=new_queue, switches=new_switches, limits=new_limits)
        return _read_config()
