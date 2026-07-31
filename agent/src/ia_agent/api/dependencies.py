from fastapi import APIRouter

from ia_agent import dependencies

router = APIRouter(prefix="/api")


@router.get("/dependencies")
async def get_dependencies(refresh: bool = False) -> dict:
    """Read-only view of everything the pipeline needs but the agent does not
    supervise. Always 200: a failing dependency is the answer, not an error."""
    items = await dependencies.snapshot(force=refresh)
    return {
        "dependencies": items,
        "summary": {
            "ok": sum(item["level"] == "ok" for item in items),
            "warn": sum(item["level"] == "warn" for item in items),
            "fail": sum(item["level"] == "fail" for item in items),
        },
    }
