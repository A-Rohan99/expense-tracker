"""
Alembic environment.

The database URL comes from the application's own config rather than
alembic.ini, so migrations always run against the same database the app talks
to and there is one place to change it.
"""

from __future__ import annotations

import os
from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

# Load .env the same way the app's launcher does, so `alembic upgrade head`
# works from a plain shell without exporting anything by hand.
try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:  # pragma: no cover - dotenv is a dev convenience
    pass

# Importing app.config validates required settings; importing app.models
# registers every table on Base.metadata for autogenerate.
from app.config import DATABASE_URL  # noqa: E402
from app.db import Base  # noqa: E402
import app.models  # noqa: E402,F401

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Escape any '%' so ConfigParser interpolation doesn't choke on a password.
config.set_main_option("sqlalchemy.url", DATABASE_URL.replace("%", "%%"))

target_metadata = Base.metadata

# SQLite cannot ALTER most things in place; batch mode recreates the table
# behind the scenes. Harmless on Postgres, essential for local development.
IS_SQLITE = DATABASE_URL.startswith("sqlite")


def run_migrations_offline() -> None:
    """Emit SQL to stdout without connecting."""
    context.configure(
        url=config.get_main_option("sqlalchemy.url"),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
        render_as_batch=IS_SQLITE,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations against a live connection."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            # Without this a changed column type is silently ignored.
            compare_type=True,
            compare_server_default=True,
            render_as_batch=IS_SQLITE,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
