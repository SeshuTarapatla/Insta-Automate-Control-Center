"""Read-only Postgres access for the dependency panel.

Credentials are never stored here. `my_modules.postgres.PostgresSecret` pulls them
from the k3s `postgres-secret`, which is the same path the pipeline uses — so there
is exactly one place they live, and it is not this repo. It does mean a postgres
check reports a credential failure when k3s is down rather than a database failure,
which the panel says plainly instead of blaming the database."""
import threading

from sqlalchemy import Engine, create_engine, text

from ia_agent.logging import logger

DATABASE = "insta_automate"

_lock = threading.Lock()
_engine: Engine | None = None


def get_engine() -> Engine:
    global _engine
    with _lock:
        if _engine is None:
            from my_modules.postgres import PostgresSecret

            url = PostgresSecret.get_connection_string(database=DATABASE)
            # pool_pre_ping so a connection dropped while the laptop slept is
            # replaced rather than raising on first use. pool_size raised from
            # 1 to 2 in CP 5.4 — the entity-view funnel query is now a second
            # real consumer alongside this module's own health check.
            _engine = create_engine(url, pool_pre_ping=True, pool_size=2, max_overflow=1)
        return _engine


def reset() -> None:
    global _engine
    with _lock:
        if _engine is not None:
            try:
                _engine.dispose()
            except Exception:
                logger.debug("engine dispose failed", exc_info=True)
        _engine = None


def check() -> dict:
    """Cheap liveness plus a little shape: the table count tells you whether you are
    looking at the real schema or an empty database someone just created."""
    with get_engine().connect() as connection:
        version = connection.execute(text("SHOW server_version")).scalar()
        tables = connection.execute(
            text(
                "SELECT count(*) FROM information_schema.tables "
                "WHERE table_schema = 'public'"
            )
        ).scalar()
        size = connection.execute(
            text("SELECT pg_size_pretty(pg_database_size(:db))"), {"db": DATABASE}
        ).scalar()
    return {"version": version, "tables": tables, "size": size, "database": DATABASE}
