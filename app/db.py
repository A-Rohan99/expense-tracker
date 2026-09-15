"""
SQLAlchemy engine & session factory.

Uses DATABASE_URL from config, which defaults to SQLite but is designed for
a zero-change swap to PostgreSQL by simply changing the env var.
"""

from __future__ import annotations

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.config import DATABASE_URL

# ---------------------------------------------------------------------------
# Engine
# ---------------------------------------------------------------------------
_connect_args: dict = {}

if DATABASE_URL.startswith("sqlite"):
    # SQLite-specific: allow multi-threaded access (FastAPI uses a thread pool)
    _connect_args["check_same_thread"] = False

engine = create_engine(
    DATABASE_URL,
    connect_args=_connect_args,
    pool_pre_ping=True,
    echo=False,
)

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
    """Yield a scoped DB session; guaranteed to close after the request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
