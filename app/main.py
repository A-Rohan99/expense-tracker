"""
FastAPI application entry point.

Run with::

    uvicorn app.main:app --reload

All routes are versioned under ``/api/v1``.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.config import (
    ALLOWED_ORIGINS,
    DOCS_ENABLED,
    ENVIRONMENT,
    IS_PRODUCTION,
)
from app.db import Base, engine, get_db
from app.errors import register_exception_handlers
from app.logging_config import configure_logging
from app.middleware import AuthRateLimitMiddleware, RequestContextMiddleware

# Import models so Base.metadata knows about all tables
import app.models  # noqa: F401

from app.routers import (
    accounts,
    auth,
    credit_cards,
    households,
    loans,
    recurring_income,
    transactions,
)
from app.schemas import EMICalculationRequest, EMICalculationResponse
from app.services.finance import calculate_emi


# ---------------------------------------------------------------------------
# Lifespan — create tables on startup
# ---------------------------------------------------------------------------

logger = logging.getLogger("app.main")


@asynccontextmanager
async def lifespan(application: FastAPI):
    """
    Startup work.

    Tables are created here only outside production. In production the schema
    is owned by Alembic — ``create_all`` can create a missing table but can
    never alter an existing one, so relying on it would silently leave a
    deployed database on an old schema.
    """
    configure_logging()
    logger.info(
        "Starting Expense Tracker API (environment=%s, docs=%s)",
        ENVIRONMENT,
        DOCS_ENABLED,
    )
    if not IS_PRODUCTION:
        Base.metadata.create_all(bind=engine)
    yield
    logger.info("Shutting down")


# ---------------------------------------------------------------------------
# App factory
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Expense Tracker API",
    description="Premium fintech backend — double-entry personal finance.",
    version="0.1.0",
    lifespan=lifespan,
    # Publishing the whole API surface and every validation rule is useful in
    # development and needless exposure in production.
    docs_url="/docs" if DOCS_ENABLED else None,
    redoc_url="/redoc" if DOCS_ENABLED else None,
    openapi_url="/openapi.json" if DOCS_ENABLED else None,
)

register_exception_handlers(app)

# Middleware runs bottom-up, so the context middleware is added last and wraps
# everything else — giving the rate limiter's log lines a request id too.
app.add_middleware(AuthRateLimitMiddleware)
app.add_middleware(RequestContextMiddleware)

# CORS: named origins only. "*" together with allow_credentials lets any site
# on the internet make credentialed calls on a signed-in user's behalf.
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["X-Request-ID"],
)


# ---------------------------------------------------------------------------
# Mount versioned routers
# ---------------------------------------------------------------------------

API_V1 = "/api/v1"

app.include_router(auth.router,         prefix=API_V1)
app.include_router(accounts.router,     prefix=API_V1)
app.include_router(credit_cards.router, prefix=API_V1)
app.include_router(loans.router,        prefix=API_V1)
app.include_router(transactions.router, prefix=API_V1)
app.include_router(households.router,   prefix=API_V1)
app.include_router(recurring_income.router, prefix=API_V1)


# ---------------------------------------------------------------------------
# Standalone utility endpoints (no auth required)
# ---------------------------------------------------------------------------

@app.post(
    f"{API_V1}/utils/calculate-emi",
    response_model=EMICalculationResponse,
    tags=["utilities"],
)
def calculate_emi_endpoint(body: EMICalculationRequest):
    """
    Standalone EMI calculator — no loan record or authentication required.

    Accepts principal, annual interest rate (%), and tenure in months.
    Returns the monthly EMI, total payment, and total interest.
    """
    result = calculate_emi(
        principal=body.principal,
        annual_rate=body.annual_rate,
        tenure_months=body.tenure_months,
    )
    return EMICalculationResponse(**result)


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------

@app.get("/health", tags=["system"])
def health():
    """Liveness: is the process up? Cheap enough to poll constantly."""
    return {"status": "ok", "environment": ENVIRONMENT}


@app.get("/health/ready", tags=["system"])
def readiness(db: Session = Depends(get_db)):
    """
    Readiness: can this instance actually serve traffic?

    /health alone returns 200 as long as Python is running, so a load balancer
    would happily route to an instance whose database connection is dead. This
    one touches the database.
    """
    try:
        db.execute(text("SELECT 1"))
    except Exception:
        logger.exception("Readiness check failed")
        return JSONResponse(
            status_code=503,
            content={"status": "unavailable", "database": "unreachable"},
        )
    return {"status": "ready", "database": "ok"}
