"""
FastAPI application entry point.

Run with::

    uvicorn app.main:app --reload

All routes are versioned under ``/api/v1``.
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.db import Base, engine

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

@asynccontextmanager
async def lifespan(application: FastAPI):
    """Create DB tables on startup (idempotent — safe for dev restarts)."""
    Base.metadata.create_all(bind=engine)
    yield


# ---------------------------------------------------------------------------
# App factory
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Expense Tracker API",
    description="Premium fintech backend — double-entry personal finance.",
    version="0.1.0",
    lifespan=lifespan,
)

# CORS — permissive for local dev; tighten in production
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
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
    return {"status": "ok"}
