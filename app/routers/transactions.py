"""
Transaction routes — the unified financial ledger.

POST /  → applies double-entry balance logic.
DELETE / → reverses balance effects.
PATCH /  → metadata-only updates (amount is immutable).
"""

from __future__ import annotations

import logging

from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, or_
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.auth import get_current_active_user
from app.db import get_db
from app.models import Account, CreditCard, Loan, Transaction, User
from app.routers import get_or_404, money, to_decimal
from app.schemas import (
    TransactionCreate,
    TransactionRead,
    TransactionType,
    TransactionUpdate,
)

router = APIRouter(prefix="/transactions", tags=["transactions"])

logger = logging.getLogger("app.transactions")


# ═══════════════════════════════════════════════════════════════════════════
# GET / — list with filtering + household sharing
# ═══════════════════════════════════════════════════════════════════════════

@router.get("/", response_model=list[TransactionRead])
def list_transactions(
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    transaction_type: TransactionType | None = Query(
        None, description="income | expense | transfer"
    ),
    category: str | None = Query(None, description="Exact category match"),
    search: str | None = Query(
        None, min_length=1, max_length=120,
        description="Case-insensitive match on description or category",
    ),
    account_id: str | None = Query(None),
    credit_card_id: str | None = Query(None),
    loan_id: str | None = Query(None),
    min_amount: Decimal | None = Query(None, ge=0),
    max_amount: Decimal | None = Query(None, ge=0),
    start_date: date | None = Query(None),
    end_date: date | None = Query(None),
    sort: str = Query(
        "date_desc",
        description="date_desc | date_asc | amount_desc | amount_asc",
    ),
    include_household: bool = Query(False, description="Include shared household transactions"),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """
    List transactions for the current user.

    When ``include_household=true`` and the user belongs to a household,
    also returns transactions from other household members where
    ``is_household_shared`` is true.
    """
    query = db.query(Transaction)

    # ── Ownership / household filter ───────────────────────────────────
    if include_household and user.household_id:
        household_user_ids = [
            uid for (uid,) in
            db.query(User.id)
            .filter(User.household_id == user.household_id)
            .all()
        ]
        query = query.filter(
            or_(
                Transaction.user_id == user.id,
                and_(
                    Transaction.user_id.in_(household_user_ids),
                    Transaction.is_household_shared.is_(True),
                ),
            )
        )
    else:
        query = query.filter(Transaction.user_id == user.id)

    # ── Optional filters ───────────────────────────────────────────────
    if transaction_type:
        query = query.filter(
            Transaction.transaction_type == transaction_type.value
        )
    if category:
        query = query.filter(Transaction.category == category)
    if start_date:
        query = query.filter(Transaction.transaction_date >= start_date)
    if end_date:
        query = query.filter(Transaction.transaction_date <= end_date)

    # Instrument filters — "everything on this card".
    if account_id:
        query = query.filter(Transaction.account_id == account_id)
    if credit_card_id:
        query = query.filter(Transaction.credit_card_id == credit_card_id)
    if loan_id:
        query = query.filter(Transaction.loan_id == loan_id)

    if min_amount is not None:
        query = query.filter(Transaction.amount >= min_amount)
    if max_amount is not None:
        query = query.filter(Transaction.amount <= max_amount)

    if search:
        # Category is free text, so searching it alongside the description is
        # what people expect from one search box.
        pattern = f"%{search}%"
        query = query.filter(
            or_(
                Transaction.description.ilike(pattern),
                Transaction.category.ilike(pattern),
            )
        )

    orderings = {
        "date_desc": (
            Transaction.transaction_date.desc(),
            Transaction.created_at.desc(),
        ),
        "date_asc": (
            Transaction.transaction_date.asc(),
            Transaction.created_at.asc(),
        ),
        "amount_desc": (Transaction.amount.desc(),),
        "amount_asc": (Transaction.amount.asc(),),
    }
    if sort not in orderings:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"sort must be one of: {', '.join(orderings)}",
        )

    return (
        query
        .order_by(*orderings[sort])
        .offset(skip)
        .limit(limit)
        .all()
    )


# ═══════════════════════════════════════════════════════════════════════════
# POST / — create with double-entry balance logic
# ═══════════════════════════════════════════════════════════════════════════

@router.post("/", response_model=TransactionRead, status_code=201)
def create_transaction(
    body: TransactionCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """
    Record a financial transaction and atomically update instrument balances.

    Balance rules
    -------------
    * **income**:  ``account.current_balance += amount``
    * **expense (account)**:  ``account.current_balance -= amount``
      (requires sufficient balance)
    * **expense (credit card)**: no balance change — CC outstanding is
      derived dynamically from the ledger.
    * **transfer → credit card**: ``account.current_balance -= amount``
      (CC outstanding decreases automatically via ledger queries)
    * **transfer → loan**: ``account.current_balance -= amount``,
      ``loan.outstanding_balance -= amount``
    """
    amount = body.amount

    # ── Verify ownership of all referenced instruments ─────────────────
    account: Account | None = None
    credit_card: CreditCard | None = None
    loan: Loan | None = None

    # Lock the instruments whose balances we are about to change.
    if body.account_id:
        account = get_or_404(
            db, Account, body.account_id, user_id=user.id, for_update=True
        )
    if body.credit_card_id:
        credit_card = get_or_404(db, CreditCard, body.credit_card_id, user_id=user.id)
    if body.loan_id:
        loan = get_or_404(
            db, Loan, body.loan_id, user_id=user.id, for_update=True
        )

    # ── Apply balance mutations ────────────────────────────────────────
    if body.transaction_type == TransactionType.income:
        # Money IN → increase account balance
        account.current_balance = money(to_decimal(account.current_balance) + amount)

    elif body.transaction_type == TransactionType.expense:
        if account:
            # Paid from bank/cash → deduct
            acct_bal = to_decimal(account.current_balance)
            if acct_bal < amount:
                raise HTTPException(
                    400,
                    detail=(
                        f"Insufficient balance in '{account.name}'. "
                        f"Required: {amount}, Available: {acct_bal}"
                    ),
                )
            account.current_balance = money(acct_bal - amount)
        # If paid via credit card: no balance mutation here — the
        # CC summary endpoint derives outstanding from the ledger.

    elif body.transaction_type == TransactionType.transfer:
        # Source account must have sufficient funds
        acct_bal = to_decimal(account.current_balance)
        if acct_bal < amount:
            raise HTTPException(
                400,
                detail=(
                    f"Insufficient balance in '{account.name}'. "
                    f"Required: {amount}, Available: {acct_bal}"
                ),
            )
        account.current_balance = money(acct_bal - amount)

        # For loan payments via the generic endpoint (not /pay-emi),
        # reduce outstanding by the full transfer amount.
        if loan:
            outstanding = to_decimal(loan.outstanding_balance)
            loan.outstanding_balance = money(max(outstanding - amount, Decimal("0")))

    # ── Persist transaction ────────────────────────────────────────────
    txn = Transaction(
        user_id=user.id,
        transaction_type=body.transaction_type.value,
        amount=money(amount),
        currency=body.currency,
        transaction_date=body.transaction_date,
        category=body.category,
        description=body.description,
        is_household_shared=body.is_household_shared,
        account_id=body.account_id,
        credit_card_id=body.credit_card_id,
        loan_id=body.loan_id,
    )
    db.add(txn)
    db.commit()
    db.refresh(txn)

    logger.info(
        "Recorded %s of %s",
        body.transaction_type.value,
        amount,
        extra={"extra_fields": {
            "audit": True,
            "user_id": user.id,
            "txn_id": txn.id,
            "type": body.transaction_type.value,
            "amount": str(amount),
            "account_id": body.account_id,
            "credit_card_id": body.credit_card_id,
            "loan_id": body.loan_id,
            "account_balance_after": (
                str(account.current_balance) if account else None
            ),
        }},
    )
    return txn


# ═══════════════════════════════════════════════════════════════════════════
# GET /{id}
# ═══════════════════════════════════════════════════════════════════════════

@router.get("/{txn_id}", response_model=TransactionRead)
def get_transaction(
    txn_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    return get_or_404(db, Transaction, txn_id, user_id=user.id)


# ═══════════════════════════════════════════════════════════════════════════
# PATCH /{id} — metadata only
# ═══════════════════════════════════════════════════════════════════════════

@router.patch("/{txn_id}", response_model=TransactionRead)
def update_transaction(
    txn_id: str,
    body: TransactionUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """
    Update non-financial metadata on a transaction.

    Amount and instrument links are **immutable** — delete and recreate
    to correct.  This follows double-entry accounting conventions.
    """
    txn = get_or_404(db, Transaction, txn_id, user_id=user.id)
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(txn, field, value)
    db.commit()
    db.refresh(txn)
    return txn


# ═══════════════════════════════════════════════════════════════════════════
# DELETE /{id} — with balance reversal
# ═══════════════════════════════════════════════════════════════════════════

@router.delete("/{txn_id}", status_code=204)
def delete_transaction(
    txn_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """
    Delete a transaction and **reverse its balance effects**.

    * Deleting an income → account balance decreases.
    * Deleting an expense paid from account → account balance increases.
    * Deleting a transfer → account balance increases, loan outstanding
      increases (if applicable).
    * CC outstanding adjusts automatically (derived from the ledger).
    """
    txn = get_or_404(db, Transaction, txn_id, user_id=user.id)
    amount = to_decimal(txn.amount)

    # ── Reverse balance effects ────────────────────────────────────────
    if txn.transaction_type == "income" and txn.account_id:
        acct = db.query(Account).filter(Account.id == txn.account_id).first()
        if acct:
            acct.current_balance = money(to_decimal(acct.current_balance) - amount)

    elif txn.transaction_type == "expense" and txn.account_id:
        acct = db.query(Account).filter(Account.id == txn.account_id).first()
        if acct:
            acct.current_balance = money(to_decimal(acct.current_balance) + amount)

    elif txn.transaction_type == "transfer":
        # Restore account balance
        if txn.account_id:
            acct = db.query(Account).filter(Account.id == txn.account_id).first()
            if acct:
                acct.current_balance = money(
                    to_decimal(acct.current_balance) + amount
                )
        # Restore loan outstanding
        if txn.loan_id:
            loan = db.query(Loan).filter(Loan.id == txn.loan_id).first()
            if loan:
                loan.outstanding_balance = money(
                    to_decimal(loan.outstanding_balance) + amount
                )
        # CC: no reversal needed — derived from ledger (this row disappears)

    db.delete(txn)
    db.commit()
