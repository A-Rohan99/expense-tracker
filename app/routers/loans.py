"""
Loan CRUD, EMI calculator utility, and Pay-EMI endpoint.
"""

from __future__ import annotations

import logging

from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth import get_current_active_user
from app.db import get_db
from app.models import Account, Loan, Transaction, User
from app.routers import get_or_404, money, to_decimal
from app.schemas import (
    AmortisationRow,
    EMICalculationRequest,
    EMICalculationResponse,
    EMIPaymentRequest,
    EMIPaymentResponse,
    LoanCreate,
    LoanRead,
    LoanUpdate,
)
from app.services.finance import (
    calculate_emi,
    calculate_emi_breakdown,
    generate_amortisation_schedule,
)

router = APIRouter(prefix="/loans", tags=["loans"])

logger = logging.getLogger("app.loans")

# Category written by pay_emi; distinguishes a scheduled instalment from an
# ad-hoc prepayment made through POST /transactions/.
EMI_CATEGORY = "EMI Payment"

# ═══════════════════════════════════════════════════════════════════════════
# Derived EMI payment state
# ═══════════════════════════════════════════════════════════════════════════

def _month_start(today: date | None = None) -> date:
    today = today or date.today()
    return date(today.year, today.month, 1)


def _last_emi_payment(db: Session, loan_id: str) -> date | None:
    """Date of the most recent EMI payment recorded against *loan_id*."""
    return (
        db.query(func.max(Transaction.transaction_date))
        .filter(
            Transaction.loan_id == loan_id,
            Transaction.transaction_type == "transfer",
            Transaction.category == EMI_CATEGORY,
        )
        .scalar()
    )


def _attach_emi_state(db: Session, loans: list[Loan]) -> list[Loan]:
    """
    Populate ``emi_paid_this_month`` / ``last_emi_payment_date``.

    The client used to track "paid" in widget state alone, so restarting the
    app made an already-paid EMI look payable again — and nothing stopped the
    second deduction. The server is the only place that can answer this
    honestly, so it does, in one grouped query for the whole set.
    """
    if not loans:
        return loans

    rows = (
        db.query(
            Transaction.loan_id,
            func.max(Transaction.transaction_date),
        )
        .filter(
            Transaction.loan_id.in_([loan.id for loan in loans]),
            Transaction.transaction_type == "transfer",
            Transaction.category == EMI_CATEGORY,
        )
        .group_by(Transaction.loan_id)
        .all()
    )
    last_paid = {loan_id: paid_on for loan_id, paid_on in rows}
    month_start = _month_start()

    for loan in loans:
        paid_on = last_paid.get(loan.id)
        loan.last_emi_payment_date = paid_on
        loan.emi_paid_this_month = paid_on is not None and paid_on >= month_start
    return loans


# ═══════════════════════════════════════════════════════════════════════════
# CRUD
# ═══════════════════════════════════════════════════════════════════════════

@router.get("/", response_model=list[LoanRead])
def list_loans(
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    loans = (
        db.query(Loan)
        .filter(Loan.user_id == user.id)
        .offset(skip)
        .limit(limit)
        .all()
    )
    return _attach_emi_state(db, loans)


@router.post("/", response_model=LoanRead, status_code=201)
def create_loan(
    body: LoanCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    loan = Loan(
        user_id=user.id,
        name=body.name,
        loan_type=body.loan_type.value,
        principal_amount=body.principal_amount,
        interest_rate=body.interest_rate,
        tenure_months=body.tenure_months,
        outstanding_balance=body.outstanding_balance,
        start_date=body.start_date,
        currency=body.currency,
    )
    db.add(loan)
    db.commit()
    db.refresh(loan)
    return loan


@router.get("/{loan_id}", response_model=LoanRead)
def get_loan(
    loan_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    loan = get_or_404(db, Loan, loan_id, user_id=user.id)
    return _attach_emi_state(db, [loan])[0]


@router.patch("/{loan_id}", response_model=LoanRead)
def update_loan(
    loan_id: str,
    body: LoanUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    loan = get_or_404(db, Loan, loan_id, user_id=user.id)
    updates = body.model_dump(exclude_unset=True)

    if "loan_type" in updates and updates["loan_type"] is not None:
        updates["loan_type"] = updates["loan_type"].value

    for field, value in updates.items():
        setattr(loan, field, value)

    db.commit()
    db.refresh(loan)
    return loan


@router.delete("/{loan_id}", status_code=204)
def delete_loan(
    loan_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    loan = get_or_404(db, Loan, loan_id, user_id=user.id)
    db.delete(loan)
    db.commit()


# ═══════════════════════════════════════════════════════════════════════════
# GET /{id}/emi-schedule — amortisation table for an existing loan
# ═══════════════════════════════════════════════════════════════════════════

@router.get("/{loan_id}/emi-schedule", response_model=list[AmortisationRow])
def emi_schedule(
    loan_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """
    Generate the full month-by-month amortisation schedule for a loan.

    Uses the loan's ``principal_amount``, ``interest_rate``, and
    ``tenure_months`` to compute each row (opening balance, EMI,
    principal/interest split, closing balance).
    """
    loan = get_or_404(db, Loan, loan_id, user_id=user.id)
    return generate_amortisation_schedule(
        principal=to_decimal(loan.principal_amount),
        annual_rate=to_decimal(loan.interest_rate),
        tenure_months=loan.tenure_months,
    )


# ═══════════════════════════════════════════════════════════════════════════
# POST /{id}/pay-emi — execute an EMI payment
# ═══════════════════════════════════════════════════════════════════════════

@router.post("/{loan_id}/pay-emi", response_model=EMIPaymentResponse)
def pay_emi(
    loan_id: str,
    body: EMIPaymentRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """
    Execute a single EMI payment.

    This endpoint:
    1. Calculates the EMI from the loan's original terms.
    2. Splits it into principal and interest components **based on the
       current outstanding balance** (standard reducing-balance method).
    3. Deducts the EMI from the chosen bank ``Account``.
    4. Reduces the ``Loan.outstanding_balance`` by the principal component.
    5. Records a ``transfer`` transaction in the ledger.

    If the outstanding balance is less than a full EMI, only the remaining
    amount is charged (final instalment adjustment).
    """
    loan = get_or_404(db, Loan, loan_id, user_id=user.id, for_update=True)
    account = get_or_404(
        db, Account, body.account_id, user_id=user.id, for_update=True
    )

    outstanding = to_decimal(loan.outstanding_balance)
    if outstanding <= 0:
        raise HTTPException(400, detail="Loan is already fully paid off")

    # One EMI per calendar month. The client cannot enforce this — it forgets
    # on restart, and a double tap or a stale screen would otherwise deduct
    # twice. Checked here, inside the same locked transaction as the write.
    already_paid_on = _last_emi_payment(db, loan.id)
    if already_paid_on is not None and already_paid_on >= _month_start():
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail=(
                f"This month's EMI for '{loan.name}' was already paid on "
                f"{already_paid_on.isoformat()}."
            ),
        )

    # ── Calculate EMI and breakdown ────────────────────────────────────
    emi_data = calculate_emi(
        principal=to_decimal(loan.principal_amount),
        annual_rate=to_decimal(loan.interest_rate),
        tenure_months=loan.tenure_months,
    )
    emi = emi_data["emi"]

    breakdown = calculate_emi_breakdown(
        outstanding=outstanding,
        annual_rate=to_decimal(loan.interest_rate),
        emi=emi,
    )

    # Final instalment: cap the deduction at the remaining balance + interest
    actual_deduction = min(emi, outstanding + breakdown["interest_component"])

    # ── Validate account balance ───────────────────────────────────────
    account_balance = to_decimal(account.current_balance)
    if account_balance < actual_deduction:
        raise HTTPException(
            400,
            detail=(
                f"Insufficient balance in '{account.name}'. "
                f"Required: {actual_deduction}, Available: {account_balance}"
            ),
        )

    # ── Atomically update balances + create transaction ────────────────
    account.current_balance = money(account_balance - actual_deduction)
    loan.outstanding_balance = money(breakdown["new_outstanding"])

    txn = Transaction(
        user_id=user.id,
        transaction_type="transfer",
        amount=money(actual_deduction),
        currency=loan.currency,
        transaction_date=date.today(),
        category="EMI Payment",
        description=f"EMI for {loan.name} (P: {breakdown['principal_component']}, I: {breakdown['interest_component']})",
        is_household_shared=False,
        account_id=account.id,
        loan_id=loan.id,
    )
    db.add(txn)
    db.commit()
    db.refresh(txn)
    db.refresh(account)

    logger.info(
        "EMI paid for loan %s",
        loan.name,
        extra={"extra_fields": {
            "audit": True,
            "user_id": user.id,
            "loan_id": loan.id,
            "txn_id": txn.id,
            "emi_amount": str(actual_deduction),
            "principal_component": str(breakdown["principal_component"]),
            "interest_component": str(breakdown["interest_component"]),
            "outstanding_after": str(loan.outstanding_balance),
            "account_balance_after": str(account.current_balance),
        }},
    )

    return EMIPaymentResponse(
        transaction_id=txn.id,
        emi_amount=actual_deduction,
        principal_component=breakdown["principal_component"],
        interest_component=breakdown["interest_component"],
        new_outstanding_balance=to_decimal(loan.outstanding_balance),
        account_new_balance=to_decimal(account.current_balance),
    )
