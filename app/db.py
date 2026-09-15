"""
SQLAlchemy engine & session factory.

Uses DATABASE_URL from config, which defaults to SQLite but is designed for
a zero-change swap to PostgreSQL by simply changing the env var.
"""

from __future__ import annotations

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.config import (
    DATABASE_URL,
    DB_MAX_OVERFLOW,
    DB_POOL_RECYCLE_SECONDS,
    DB_POOL_SIZE,
    DB_POOL_TIMEOUT_SECONDS,
)

# ---------------------------------------------------------------------------
# Engine
# ---------------------------------------------------------------------------
_connect_args: dict = {}

if DATABASE_URL.startswith("sqlite"):
    # SQLite-specific: allow multi-threaded access (FastAPI uses a thread pool)
    _connect_args["check_same_thread"] = False

_engine_kwargs: dict = {
    "connect_args": _connect_args,
    # Verify a pooled connection before handing it out — a cloud database or
    # PgBouncer will drop idle connections without telling us.
    "pool_pre_ping": True,
    "echo": False,
}

if not DATABASE_URL.startswith("sqlite"):
    # SQLite has no meaningful pool (one file, one writer), so these apply to
    # Postgres only. Defaults leave pool_recycle unset, which reliably produces
    # stale-connection errors behind a proxy that closes idle sessions.
    _engine_kwargs.update(
        pool_size=DB_POOL_SIZE,
        max_overflow=DB_MAX_OVERFLOW,
        # Recycle below any sensible server-side idle timeout.
        pool_recycle=DB_POOL_RECYCLE_SECONDS,
        # Fail fast rather than hanging a request when the pool is exhausted.
        pool_timeout=DB_POOL_TIMEOUT_SECONDS,
    )

engine = create_engine(DATABASE_URL, **_engine_kwargs)

# Enable WAL mode & foreign keys for SQLite (no-ops on Postgres).
if DATABASE_URL.startswith("sqlite"):

    @event.listens_for(engine, "connect")
    def _set_sqlite_pragma(dbapi_conn, _connection_record):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


# ---------------------------------------------------------------------------
# Session
# ---------------------------------------------------------------------------
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


class Base(DeclarativeBase):
    """Shared declarative base for all ORM models."""


# ---------------------------------------------------------------------------
# Dependency for FastAPI route injection
# ---------------------------------------------------------------------------
def get_db():
    """
    Yield a scoped DB session; guaranteed to close after the request.

    The rollback matters: without it a failed ``commit()`` returns the
    connection to the pool still carrying an aborted transaction, and on
    Postgres the next request to pick it up fails with InFailedSqlTransaction —
    one bad write cascading into unrelated endpoints.
    """
    db = SessionLocal()
    try:
        yield db
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
