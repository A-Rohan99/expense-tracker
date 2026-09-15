"""
Account (asset) CRUD routes.
"""

from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.auth import get_current_active_user
from app.db import get_db
from app.models import Account, User
from app.routers import get_or_404
from app.schemas import AccountCreate, AccountRead, AccountUpdate

router = APIRouter(prefix="/accounts", tags=["accounts"])


# ── GET / ──────────────────────────────────────────────────────────────────

@router.get("/", response_model=list[AccountRead])
def list_accounts(
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """List all accounts belonging to the current user."""
    return (
        db.query(Account)
        .filter(Account.user_id == user.id)
        .offset(skip)
        .limit(limit)
        .all()
    )


# ── POST / ─────────────────────────────────────────────────────────────────

@router.post("/", response_model=AccountRead, status_code=201)
def create_account(
    body: AccountCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """Create a new bank / cash / wallet account."""
    account = Account(
        user_id=user.id,
        name=body.name,
        account_type=body.account_type.value,
        current_balance=body.current_balance,
        currency=body.currency,
    )
    db.add(account)
    db.commit()
    db.refresh(account)
    return account


# ── GET /{id} ──────────────────────────────────────────────────────────────

@router.get("/{account_id}", response_model=AccountRead)
def get_account(
    account_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    return get_or_404(db, Account, account_id, user_id=user.id)


# ── PATCH /{id} ────────────────────────────────────────────────────────────

@router.patch("/{account_id}", response_model=AccountRead)
def update_account(
    account_id: str,
    body: AccountUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    account = get_or_404(db, Account, account_id, user_id=user.id)
    updates = body.model_dump(exclude_unset=True)

    if "account_type" in updates and updates["account_type"] is not None:
        updates["account_type"] = updates["account_type"].value

    for field, value in updates.items():
        setattr(account, field, value)

    db.commit()
    db.refresh(account)
    return account


# ── DELETE /{id} ────────────────────────────────────────────────────────────

@router.delete("/{account_id}", status_code=204)
def delete_account(
    account_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    account = get_or_404(db, Account, account_id, user_id=user.id)
    db.delete(account)
    db.commit()
