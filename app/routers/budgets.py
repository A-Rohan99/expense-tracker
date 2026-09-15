"""
Monthly budgets.

A budget is a cap; the spend against it is always derived from the ledger for
the month being asked about. Storing a running total would be a second source
of truth that drifts the moment a transaction is edited or deleted.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth import get_current_active_user
from app.db import get_db
from app.models import Budget, Transaction, User
from app.money import money, to_decimal
from app.routers import get_or_404
from app.schemas import BudgetCreate, BudgetRead, BudgetUpdate
from app.services.finance import shift_month

router = APIRouter(prefix="/budgets", tags=["budgets"])

ZERO = Decimal("0.00")


def _month_bounds(period: str | None) -> tuple[date, date, str]:
    """Return (first day, last day, 'YYYY-MM') for *period*, defaulting to now."""
    if period:
        try:
            year, month = (int(part) for part in period.split("-"))
            start = date(year, month, 1)
        except (ValueError, TypeError):
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="period must look like YYYY-MM",
            )
    else:
        today = date.today()
        start = date(today.year, today.month, 1)

    # Last day = day before the first of next month.
    next_month = shift_month(start, 1)
    end = date(next_month.year, next_month.month, 1)
    return start, end, f"{start.year:04d}-{start.month:02d}"


def _household_user_ids(db: Session, user: User) -> list[str]:
    if not user.household_id:
        return [user.id]
    return [
        row[0]
        for row in db.query(User.id)
        .filter(User.household_id == user.household_id)
        .all()
    ]


def _spend_for(
    db: Session,
    user: User,
    *,
    start: date,
    end: date,
    category: str | None,
    include_household: bool,
) -> Decimal:
    """Total expense in the window, optionally scoped to one category."""
    query = db.query(func.coalesce(func.sum(Transaction.amount), 0)).filter(
        Transaction.transaction_type == "expense",
        Transaction.transaction_date >= start,
        Transaction.transaction_date < end,
    )
    if include_household and user.household_id:
        query = query.filter(
            Transaction.user_id.in_(_household_user_ids(db, user)),
            Transaction.is_household_shared.is_(True),
        )
    else:
        query = query.filter(Transaction.user_id == user.id)

    if category is not None:
        query = query.filter(Transaction.category == category)

    return to_decimal(query.scalar())


def _to_read(
    db: Session, user: User, budget: Budget, start: date, end: date, period: str
) -> BudgetRead:
    spent = _spend_for(
        db,
        user,
        start=start,
        end=end,
        category=budget.category,
        include_household=budget.include_household,
    )
    cap = to_decimal(budget.amount)
    payload = BudgetRead.model_validate(budget)
    payload.spent = money(spent)
    # Clamped at zero: "how much is left" should not read as negative debt.
    payload.remaining = money(max(cap - spent, ZERO))
    payload.percent_used = (
        money(spent / cap * 100) if cap > 0 else ZERO
    )
    payload.period = period
    return payload


# ── GET / ──────────────────────────────────────────────────────────────────

@router.get("/", response_model=list[BudgetRead])
def list_budgets(
    period: str | None = Query(
        None, description="Month to report spend against, as YYYY-MM."
    ),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """Every budget, with its spend for *period* (default: this month)."""
    start, end, label = _month_bounds(period)
    budgets = (
        db.query(Budget)
        .filter(Budget.user_id == user.id)
        # Overall budget first, then categories alphabetically.
        .order_by(Budget.category.is_(None).desc(), Budget.category)
        .all()
    )
    return [_to_read(db, user, b, start, end, label) for b in budgets]


# ── POST / ─────────────────────────────────────────────────────────────────

@router.post("/", response_model=BudgetRead, status_code=201)
def create_budget(
    body: BudgetCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """
    Set a cap. One overall budget and one per category.

    A unique constraint covers the per-category case, but SQL treats NULLs as
    distinct, so the overall budget needs an explicit check.
    """
    existing = (
        db.query(Budget)
        .filter(Budget.user_id == user.id, Budget.category.is_(body.category))
        if body.category is None
        else db.query(Budget).filter(
            Budget.user_id == user.id, Budget.category == body.category
        )
    )
    if existing.first() is not None:
        scope = body.category or "overall"
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail=f"A {scope} budget already exists. Update it instead.",
        )

    budget = Budget(
        user_id=user.id,
        category=body.category,
        amount=money(body.amount),
        currency=body.currency.value,
        include_household=body.include_household,
    )
    db.add(budget)
    db.commit()
    db.refresh(budget)

    start, end, label = _month_bounds(None)
    return _to_read(db, user, budget, start, end, label)


# ── PATCH /{id} ────────────────────────────────────────────────────────────

@router.patch("/{budget_id}", response_model=BudgetRead)
def update_budget(
    budget_id: str,
    body: BudgetUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    budget = get_or_404(db, Budget, budget_id, user_id=user.id)
    data = body.model_dump(exclude_unset=True)
    if data.get("amount") is not None:
        data["amount"] = money(data["amount"])
    for field, value in data.items():
        setattr(budget, field, value)
    db.commit()
    db.refresh(budget)

    start, end, label = _month_bounds(None)
    return _to_read(db, user, budget, start, end, label)


# ── DELETE /{id} ───────────────────────────────────────────────────────────

@router.delete("/{budget_id}", status_code=204)
def delete_budget(
    budget_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    budget = get_or_404(db, Budget, budget_id, user_id=user.id)
    db.delete(budget)
    db.commit()
