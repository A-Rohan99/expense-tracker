"""
Standing monthly income routes.

A user has at most one instruction, so this is a singleton resource at
``/recurring-income`` rather than a collection.

Every read runs the catch-up first (see ``app.services.recurring``), so simply
opening the app posts any income that fell due while it was closed.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.auth import get_current_active_user
from app.db import get_db
from app.models import Account, RecurringIncome, User
from app.routers import money
from app.schemas import (
    RecurringIncomeCreate,
    RecurringIncomeRead,
    RecurringIncomeUpdate,
)
from app.services.recurring import (
    initial_last_posted,
    next_due_date,
    run_catch_up,
)

router = APIRouter(prefix="/recurring-income", tags=["recurring income"])


def _get_for_user(db: Session, user: User) -> RecurringIncome | None:
    return (
        db.query(RecurringIncome)
        .filter(RecurringIncome.user_id == user.id)
        .first()
    )


def _own_account_or_404(db: Session, user: User, account_id: str) -> Account:
    account = (
        db.query(Account)
        .filter(Account.id == account_id, Account.user_id == user.id)
        .first()
    )
    if account is None:
        raise HTTPException(404, detail="Account not found")
    return account


def _to_read(
    db: Session,
    income: RecurringIncome,
    posted_count: int = 0,
) -> RecurringIncomeRead:
    """Serialise, adding the computed fields the client would otherwise guess."""
    account = db.get(Account, income.account_id)
    payload = RecurringIncomeRead.model_validate(income)
    payload.next_due_date = next_due_date(income)
    payload.account_name = account.name if account else None
    payload.posted_this_run = posted_count
    return payload


# ── GET / ──────────────────────────────────────────────────────────────────

@router.get("/", response_model=RecurringIncomeRead | None)
def get_recurring_income(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """
    Return the standing instruction, or ``null`` if none is set up.

    Posts any months that fell due since the last call, and reports how many
    in ``posted_this_run`` so the UI can tell the user what just happened.
    """
    income = _get_for_user(db, user)
    if income is None:
        return None

    posted = run_catch_up(db, income)
    return _to_read(db, income, len(posted))


# ── POST / ─────────────────────────────────────────────────────────────────

@router.post("/", response_model=RecurringIncomeRead, status_code=201)
def create_recurring_income(
    body: RecurringIncomeCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """
    Set up the standing instruction.  Only one per user — use PATCH to change
    an existing one.
    """
    if _get_for_user(db, user) is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="Monthly income is already set up. Update it instead.",
        )

    _own_account_or_404(db, user, body.account_id)

    income = RecurringIncome(
        user_id=user.id,
        account_id=body.account_id,
        name=body.name,
        amount=money(body.amount),
        day_of_month=body.day_of_month,
        category=body.category,
        currency=body.currency,
        is_household_shared=body.is_household_shared,
        # If this month's date already passed, don't back-post it — the user
        # was likely already paid and may have recorded it by hand.
        last_posted_period=initial_last_posted(body.day_of_month),
    )
    db.add(income)
    db.commit()
    db.refresh(income)

    posted = run_catch_up(db, income)
    return _to_read(db, income, len(posted))


# ── PATCH / ────────────────────────────────────────────────────────────────

@router.patch("/", response_model=RecurringIncomeRead)
def update_recurring_income(
    body: RecurringIncomeUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """Change the amount, pay day, destination account, or pause it."""
    income = _get_for_user(db, user)
    if income is None:
        raise HTTPException(404, detail="Monthly income is not set up")

    data = body.model_dump(exclude_unset=True)
    if "account_id" in data and data["account_id"] is not None:
        _own_account_or_404(db, user, data["account_id"])
    if "amount" in data and data["amount"] is not None:
        data["amount"] = money(data["amount"])

    for field, value in data.items():
        setattr(income, field, value)

    db.commit()
    db.refresh(income)

    posted = run_catch_up(db, income)
    return _to_read(db, income, len(posted))


# ── DELETE / ───────────────────────────────────────────────────────────────

@router.delete("/", status_code=204)
def delete_recurring_income(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """
    Remove the standing instruction.  Income already posted stays in the
    ledger — this only stops future months.
    """
    income = _get_for_user(db, user)
    if income is None:
        raise HTTPException(404, detail="Monthly income is not set up")

    db.delete(income)
    db.commit()
    return Response(status_code=204)
