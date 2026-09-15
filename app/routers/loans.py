"""
Loan CRUD, EMI calculator utility, and Pay-EMI endpoint.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.auth import get_current_active_user
from app.db import get_db
from app.models import Account, Loan, Transaction, User
from app.routers import get_or_404, to_decimal
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
    return (
        db.query(Loan)
        .filter(Loan.user_id == user.id)
        .offset(skip)
        .limit(limit)
        .all()
    )


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
    return get_or_404(db, Loan, loan_id, user_id=user.id)


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
    loan = get_or_404(db, Loan, loan_id, user_id=user.id)
    account = get_or_404(db, Account, body.account_id, user_id=user.id)

    outstanding = to_decimal(loan.outstanding_balance)
    if outstanding <= 0:
        raise HTTPException(400, detail="Loan is already fully paid off")

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
    account.current_balance = float(account_balance - actual_deduction)
    loan.outstanding_balance = float(breakdown["new_outstanding"])

    txn = Transaction(
        user_id=user.id,
        transaction_type="transfer",
        amount=float(actual_deduction),
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

    return EMIPaymentResponse(
        transaction_id=txn.id,
        emi_amount=actual_deduction,
        principal_component=breakdown["principal_component"],
        interest_component=breakdown["interest_component"],
        new_outstanding_balance=to_decimal(loan.outstanding_balance),
        account_new_balance=to_decimal(account.current_balance),
    )
