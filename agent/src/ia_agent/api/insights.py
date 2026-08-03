import asyncio

from fastapi import APIRouter

from ia_agent import insights

MAX_DAYS = insights.MAX_DAYS


def create_insights_router() -> APIRouter:
    router = APIRouter(prefix="/api/insights")

    @router.get("/funnel")
    async def get_funnel() -> dict:
        return await asyncio.to_thread(insights.funnel)

    @router.get("/ranking")
    async def get_ranking() -> list[dict]:
        return await asyncio.to_thread(insights.ranking)

    @router.get("/burndown")
    async def get_burndown(days: int = 30) -> dict:
        days = max(1, min(days, MAX_DAYS))
        return await asyncio.to_thread(insights.burndown, days)

    return router
