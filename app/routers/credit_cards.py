"""
Credit-card CRUD + dynamic billing summary.
"""

from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth import get_current_active_user
from app.db import get_db
from app.models import CreditCard, Transaction, User
from app.routers import get_or_404, to_decimal
from app.schemas import (
    CreditCardCreate,
    CreditCardRead,
    CreditCardSummaryResponse,
    CreditCardUpdate,
)
from app.services.finance import get_statement_cycle

router = APIRouter(prefix="/credit-cards", tags=["credit cards"])


# ═══════════════════════════════════════════════════════════════════════════
# CRUD
# ═══════════════════════════════════════════════════════════════════════════

@router.get("/", response_model=list[CreditCardRead])
def list_credit_cards(
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    return (
        db.query(CreditCard)
        .filter(CreditCard.user_id == user.id)
        .offset(skip)
        .limit(limit)
        .all()
    )


@router.post("/", response_model=CreditCardRead, status_code=201)
def create_credit_card(
    body: CreditCardCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    card = CreditCard(
        user_id=user.id,
        name=body.name,
        last_four=body.last_four,
        total_limit=body.total_limit,
        statement_day=body.statement_day,
        due_day=body.due_day,
        currency=body.currency,
    )
    db.add(card)
    db.commit()
    db.refresh(card)
    return card


@router.get("/{card_id}", response_model=CreditCardRead)
def get_credit_card(
    card_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    return get_or_404(db, CreditCard, card_id, user_id=user.id)


@router.patch("/{card_id}", response_model=CreditCardRead)
def update_credit_card(
    card_id: str,
    body: CreditCardUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    card = get_or_404(db, CreditCard, card_id, user_id=user.id)
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(card, field, value)
    db.commit()
    db.refresh(card)
    return card


@router.delete("/{card_id}", status_code=204)
def delete_credit_card(
    card_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    card = get_or_404(db, CreditCard, card_id, user_id=user.id)
    db.delete(card)
    db.commit()


# ═══════════════════════════════════════════════════════════════════════════
# GET /{id}/summary — dynamic billing snapshot
# ═══════════════════════════════════════════════════════════════════════════

@router.get("/{card_id}/summary", response_model=CreditCardSummaryResponse)
def credit_card_summary(
    card_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """
    Dynamically compute the credit-card billing summary.

    **Nothing is stored as a static column** — billed, unbilled, and
    available-limit are all derived on the fly from the transaction ledger.

    Calculation logic
    -----------------
    1. ``total_charges``  = SUM of all ``expense`` transactions on this card.
    2. ``total_payments`` = SUM of all ``transfer`` transactions to this card
       (i.e. bill payments from a bank account).
    3. ``total_outstanding`` = total_charges − total_payments.
    4. ``unbilled``  = charges since the *last* statement date.
    5. ``billed``    = total_outstanding − unbilled  (clamped ≥ 0).
    6. ``available_limit`` = total_limit − total_outstanding.
    7. ``min_due``   = max(5% of billed, ₹200)  — or 0 if billed is 0.
    8. Billing cycle dates and days-until-due from ``get_statement_cycle``.
    """
    card = get_or_404(db, CreditCard, card_id, user_id=user.id)

    # ── Billing cycle dates ────────────────────────────────────────────
    cycle = get_statement_cycle(card.statement_day, card.due_day)

    # ── Aggregate queries ──────────────────────────────────────────────
    total_charges = to_decimal(
        db.query(func.coalesce(func.sum(Transaction.amount), 0))
        .filter(
            Transaction.credit_card_id == card.id,
            Transaction.transaction_type == "expense",
        )
        .scalar()
    )

    total_payments = to_decimal(
        db.query(func.coalesce(func.sum(Transaction.amount), 0))
        .filter(
            Transaction.credit_card_id == card.id,
            Transaction.transaction_type == "transfer",
        )
        .scalar()
    )

    # Charges since last statement (unbilled)
    unbilled = to_decimal(
        db.query(func.coalesce(func.sum(Transaction.amount), 0))
        .filter(
            Transaction.credit_card_id == card.id,
            Transaction.transaction_type == "expense",
            Transaction.transaction_date > cycle["last_statement_date"],
        )
        .scalar()
    )

    total_outstanding = total_charges - total_payments
    billed = max(total_outstanding - unbilled, Decimal("0.00"))
    available = to_decimal(card.total_limit) - max(total_outstanding, Decimal("0.00"))

    # Min due: 5% of billed or ₹200, whichever is higher (0 if no bill)
    if billed > 0:
        min_due = max(
            (billed * Decimal("0.05")).quantize(Decimal("0.01")),
            Decimal("200.00"),
        )
    else:
        min_due = Decimal("0.00")

    return CreditCardSummaryResponse(
        card_id=card.id,
        card_name=card.name,
        total_limit=to_decimal(card.total_limit),
        billed_amount=billed,
        unbilled_amount=unbilled,
        total_outstanding=total_outstanding,
        available_limit=available,
        total_payments=total_payments,
        min_due_amount=min_due,
        last_statement_date=cycle["last_statement_date"],
        next_statement_date=cycle["next_statement_date"],
        due_date=cycle["due_date"],
        days_until_due=cycle["days_until_due"],
    )
