"""
Centralised application configuration.

All secrets and tunables come from environment variables (or a .env file
loaded by the shell / process manager).  Nothing is hard-coded.

Anything that would be *dangerous to get wrong in production* fails closed —
the process refuses to start rather than quietly falling back to a development
default.  A container that forgets ``DATABASE_URL`` should not boot happily
against a throwaway SQLite file and lose every write on the next restart.
"""

from __future__ import annotations

import os

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development").strip().lower()
IS_PRODUCTION: bool = ENVIRONMENT == "production"


def _require(name: str, hint: str) -> str:
    """Read a variable that production cannot run without."""
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"{name} environment variable is not set. {hint}")
    return value


def _int_env(name: str, default: int) -> int:
    """Read an integer setting, failing with a useful message if it's junk."""
    raw = os.getenv(name)
    if raw is None or not raw.strip():
        return default
    try:
        return int(raw)
    except ValueError as exc:
        raise RuntimeError(
            f"{name} must be an integer, got {raw!r}."
        ) from exc


# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
# Outside development this must be explicit. The SQLite default is a
# convenience for local work only; in a container it would be an ephemeral file
# that silently discards every write when the container restarts.
if IS_PRODUCTION:
    DATABASE_URL: str = _require(
        "DATABASE_URL",
        "Set it to your Postgres connection string, e.g. "
        "postgresql+psycopg://user:pass@host:5432/dbname",
    )
else:
    DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./expense_tracker.db")

# ---------------------------------------------------------------------------
# JWT / Auth
# ---------------------------------------------------------------------------
SECRET_KEY: str = _require(
    "SECRET_KEY",
    'Generate one with: python -c "import secrets; print(secrets.token_urlsafe(64))"',
)

ALGORITHM: str = os.getenv("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES: int = _int_env("ACCESS_TOKEN_EXPIRE_MINUTES", 30)
REFRESH_TOKEN_EXPIRE_DAYS: int = _int_env("REFRESH_TOKEN_EXPIRE_DAYS", 7)

# ---------------------------------------------------------------------------
# CORS
# ---------------------------------------------------------------------------
# Comma-separated list of origins allowed to call the API with credentials.
# "*" plus allow_credentials is a hole, so production must name its origins.
_origins_raw = os.getenv("ALLOWED_ORIGINS", "").strip()
if _origins_raw:
    ALLOWED_ORIGINS: list[str] = [
        origin.strip().rstrip("/")
        for origin in _origins_raw.split(",")
        if origin.strip()
    ]
elif IS_PRODUCTION:
    raise RuntimeError(
        "ALLOWED_ORIGINS environment variable is not set. "
        "Set it to the origin(s) serving the web app, e.g. "
        "https://expenses.example.com"
    )
else:
    # Local dev: the Flutter web dev server and the API's own docs.
    ALLOWED_ORIGINS = [
        "http://localhost:5000",
        "http://127.0.0.1:5000",
        "http://localhost:8000",
        "http://127.0.0.1:8000",
    ]

# ---------------------------------------------------------------------------
# Rate limiting
# ---------------------------------------------------------------------------
# Budget of *failed* auth attempts per client IP per window. Successful
# calls do not consume it, so a family sharing one NAT is unaffected while
# brute force — which needs thousands of wrong guesses — still gets stopped.
AUTH_RATE_LIMIT: str = os.getenv("AUTH_RATE_LIMIT", "20/minute")
RATE_LIMIT_ENABLED: bool = (
    os.getenv("RATE_LIMIT_ENABLED", "true").strip().lower() != "false"
)

# ---------------------------------------------------------------------------
# API documentation
# ---------------------------------------------------------------------------
# /docs, /redoc and /openapi.json publish the full API surface and every
# validation rule. Useful in development, needless exposure in production.
DOCS_ENABLED: bool = (
    os.getenv("DOCS_ENABLED", "false" if IS_PRODUCTION else "true")
    .strip()
    .lower()
    == "true"
)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO").strip().upper()
# JSON in production so the platform's log search can parse it.
LOG_JSON: bool = (
    os.getenv("LOG_JSON", "true" if IS_PRODUCTION else "false").strip().lower()
    == "true"
)
