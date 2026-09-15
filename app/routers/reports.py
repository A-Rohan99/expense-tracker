"""
Monthly reporting.

Aggregation belongs on the server. The client used to fetch a capped list of
transactions and sum them itself, so once a month exceeded the cap the headline
income and expense figures were silently wrong — and the error grew with use.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth import get_current_active_user
from app.db import get_db
from app.models import Transaction, User
from app.money import money, to_decimal
from app.schemas import CategoryBreakdownRow, MonthlyReport, MonthlyTotals
from app.services.finance import shift_month

router = APIRouter(prefix="/reports", tags=["reports"])

ZERO = Decimal("0.00")
MAX_TREND_MONTHS = 24


def _parse_period(period: str | None) -> date:
    if not period:
        today = date.today()
        return date(today.year, today.month, 1)
    try:
        year, month = (int(part) for part in period.split("-"))
        return date(year, month, 1)
    except (ValueError, TypeError):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="period must look like YYYY-MM",
        )


def _scope(db: Session, user: User, include_household: bool):
    """Which users' transactions count, and whether to require the shared flag."""
    if include_household and user.household_id:
        member_ids = [
            row[0]
            for row in db.query(User.id)
            .filter(User.household_id == user.household_id)
            .all()
        ]
        return (
            Transaction.user_id.in_(member_ids),
            Transaction.is_household_shared.is_(True),
        )
    return (Transaction.user_id == user.id,)


@router.get("/monthly", response_model=MonthlyReport)
def monthly_report(
    period: str | None = Query(None, description="Month as YYYY-MM."),
    include_household: bool = Query(False),
    trend_months: int = Query(6, ge=1, le=MAX_TREND_MONTHS),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """
    Totals, a category breakdown and a month-over-month trend.

    Transfers are excluded throughout: paying a credit-card bill or an EMI
    moves money between the user's own instruments, so counting it as spending
    would double-count the original purchase.
    """
    start = _parse_period(period)
    next_start = shift_month(start, 1)
    label = f"{start.year:04d}-{start.month:02d}"
    scope = _scope(db, user, include_household)

    def _total(txn_type: str, window_start: date, window_end: date) -> Decimal:
        return to_decimal(
            db.query(func.coalesce(func.sum(Transaction.amount), 0))
            .filter(
                *scope,
                Transaction.transaction_type == txn_type,
                Transaction.transaction_date >= window_start,
                Transaction.transaction_date < window_end,
            )
            .scalar()
        )

    income = _total("income", start, next_start)
    expense = _total("expense", start, next_start)

    count = (
        db.query(func.count(Transaction.id))
        .filter(
            *scope,
            Transaction.transaction_type.in_(("income", "expense")),
            Transaction.transaction_date >= start,
            Transaction.transaction_date < next_start,
        )
        .scalar()
        or 0
    )

    # ── Category breakdown of spending ────────────────────────────────────
    rows = (
        db.query(
            Transaction.category,
            func.coalesce(func.sum(Transaction.amount), 0),
            func.count(Transaction.id),
        )
        .filter(
            *scope,
            Transaction.transaction_type == "expense",
            Transaction.transaction_date >= start,
            Transaction.transaction_date < next_start,
        )
        .group_by(Transaction.category)
        .order_by(func.sum(Transaction.amount).desc())
        .all()
    )
    by_category = [
        CategoryBreakdownRow(
            category=category,
            amount=money(to_decimal(total)),
            percent=money(to_decimal(total) / expense * 100)
            if expense > 0
            else ZERO,
            transaction_count=row_count,
        )
        for category, total, row_count in rows
    ]

    # ── Trend, oldest first ───────────────────────────────────────────────
    trend: list[MonthlyTotals] = []
    for offset in range(trend_months - 1, -1, -1):
        window_start = shift_month(start, -offset)
        window_end = shift_month(window_start, 1)
        month_income = _total("income", window_start, window_end)
        month_expense = _total("expense", window_start, window_end)
        trend.append(
            MonthlyTotals(
                period=f"{window_start.year:04d}-{window_start.month:02d}",
                income=money(month_income),
                expense=money(month_expense),
                net=money(month_income - month_expense),
            )
        )

    return MonthlyReport(
        period=label,
        income=money(income),
        expense=money(expense),
        net=money(income - expense),
        transaction_count=count,
        by_category=by_category,
        trend=trend,
    )
