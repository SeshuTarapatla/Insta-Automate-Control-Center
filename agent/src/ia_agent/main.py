import uvicorn

from ia_agent.app import create_app
from ia_agent.logging import logger
from ia_agent.vars import HOST, PORT


def main() -> None:
    logger.info(f"ia-agent starting on {HOST}:{PORT}")
    uvicorn.run(create_app(), host=HOST, port=PORT)
