"""
Pure financial calculation utilities.

No database access — these are deterministic functions used by routers
to compute EMIs, billing cycles, and amortisation schedules.
"""

from __future__ import annotations

import calendar
from datetime import date
from decimal import Decimal, ROUND_HALF_UP

TWO_PLACES = Decimal("0.01")


def _round(value: Decimal) -> Decimal:
    """Round to 2 decimal places using banker-friendly rounding."""
    return value.quantize(TWO_PLACES, rounding=ROUND_HALF_UP)


# ═══════════════════════════════════════════════════════════════════════════
# Date helpers
# ═══════════════════════════════════════════════════════════════════════════

def clamp_day(year: int, month: int, day: int) -> date:
    """Return ``date(year, month, day)`` clamped to the last valid day."""
    max_day = calendar.monthrange(year, month)[1]
    return date(year, month, min(day, max_day))


def shift_month(d: date, delta: int) -> date:
    """
    Shift *d* by *delta* calendar months, clamping the day.

    >>> shift_month(date(2026, 1, 31), 1)
    datetime.date(2026, 2, 28)
    >>> shift_month(date(2026, 3, 15), -1)
    datetime.date(2026, 2, 15)
    """
    month = d.month - 1 + delta
    year = d.year + month // 12
    month = month % 12 + 1
    max_day = calendar.monthrange(year, month)[1]
    return date(year, month, min(d.day, max_day))


# ═══════════════════════════════════════════════════════════════════════════
# Credit-card billing cycle
# ═══════════════════════════════════════════════════════════════════════════

def get_statement_cycle(
    statement_day: int,
    due_day: int,
    ref_date: date | None = None,
) -> dict:
    """
    Compute billing-cycle boundary dates relative to *ref_date*.

    Parameters
    ----------
    statement_day : int
        Day of month when the statement is generated (1-31).
    due_day : int
        Day of month when payment is due (1-31).
    ref_date : date, optional
        Reference date.  Defaults to ``date.today()``.

    Returns
    -------
    dict with:
        prev_statement_date  – start of the billed period
        last_statement_date  – most recent statement date
        next_statement_date  – upcoming statement date
        due_date             – payment due for the *last* statement
        days_until_due       – calendar days remaining (negative = overdue)
    """
    ref = ref_date or date.today()

    # ── Most recent statement date ─────────────────────────────────────
    if ref.day >= statement_day:
        last_stmt = clamp_day(ref.year, ref.month, statement_day)
    else:
        prev = shift_month(ref, -1)
        last_stmt = clamp_day(prev.year, prev.month, statement_day)

    # ── Previous & next statement dates ────────────────────────────────
    prev_m = shift_month(last_stmt, -1)
    prev_stmt = clamp_day(prev_m.year, prev_m.month, statement_day)

    next_m = shift_month(last_stmt, 1)
    next_stmt = clamp_day(next_m.year, next_m.month, statement_day)

    # ── Due date for the last statement ────────────────────────────────
    # If due_day > statement_day → due falls in the same month.
    # If due_day <= statement_day → due falls in the next month.
    if due_day > statement_day:
        due = clamp_day(last_stmt.year, last_stmt.month, due_day)
    else:
        nm = shift_month(last_stmt, 1)
        due = clamp_day(nm.year, nm.month, due_day)

    return {
        "prev_statement_date": prev_stmt,
        "last_statement_date": last_stmt,
        "next_statement_date": next_stmt,
        "due_date": due,
        "days_until_due": (due - ref).days,
    }


# ═══════════════════════════════════════════════════════════════════════════
# EMI calculations
# ═══════════════════════════════════════════════════════════════════════════

def calculate_emi(
    principal: Decimal,
    annual_rate: Decimal,
    tenure_months: int,
) -> dict:
    """
    Standard EMI formula::

        EMI = P × r × (1+r)^n  /  ((1+r)^n − 1)

    Parameters
    ----------
    principal : Decimal   – loan principal
    annual_rate : Decimal – annual interest rate as % (e.g. ``8.50``)
    tenure_months : int   – repayment period

    Returns
    -------
    dict with ``emi``, ``total_payment``, ``total_interest``, ``principal``
    """
    if annual_rate == 0:
        emi = _round(principal / tenure_months)
        return {
            "emi": emi,
            "total_payment": _round(principal),
            "total_interest": Decimal("0.00"),
            "principal": _round(principal),
        }

    r = annual_rate / Decimal("1200")       # monthly rate
    n = tenure_months
    compound = (1 + r) ** n

    emi = _round(principal * r * compound / (compound - 1))
    total_payment = _round(emi * n)
    total_interest = _round(total_payment - principal)

    return {
        "emi": emi,
        "total_payment": total_payment,
        "total_interest": total_interest,
        "principal": _round(principal),
    }


def calculate_emi_breakdown(
    outstanding: Decimal,
    annual_rate: Decimal,
    emi: Decimal,
) -> dict:
    """
    Split a single EMI payment into principal and interest components.

    interest_component  = outstanding × (annual_rate / 1200)
    principal_component = EMI − interest_component
    new_outstanding     = outstanding − principal_component

    Returns dict with ``interest_component``, ``principal_component``,
    ``new_outstanding``.
    """
    if annual_rate == 0:
        return {
            "interest_component": Decimal("0.00"),
            "principal_component": _round(min(emi, outstanding)),
            "new_outstanding": _round(max(outstanding - emi, Decimal("0"))),
        }

    monthly_rate = annual_rate / Decimal("1200")
    interest = _round(outstanding * monthly_rate)
    principal = _round(emi - interest)
    new_outstanding = _round(max(outstanding - principal, Decimal("0")))

    return {
        "interest_component": interest,
        "principal_component": principal,
        "new_outstanding": new_outstanding,
    }


def generate_amortisation_schedule(
    principal: Decimal,
    annual_rate: Decimal,
    tenure_months: int,
) -> list[dict]:
    """
    Generate a full month-by-month amortisation table.

    Each row: ``month``, ``opening_balance``, ``emi``, ``principal``,
    ``interest``, ``closing_balance``.
    """
    emi_data = calculate_emi(principal, annual_rate, tenure_months)
    emi = emi_data["emi"]
    schedule: list[dict] = []
    balance = _round(principal)

    for month in range(1, tenure_months + 1):
        bk = calculate_emi_breakdown(balance, annual_rate, emi)

        # Last month: clear the balance exactly
        if month == tenure_months:
            bk["principal_component"] = balance
            bk["interest_component"] = _round(emi - balance) if emi > balance else Decimal("0.00")
            bk["new_outstanding"] = Decimal("0.00")

        schedule.append({
            "month": month,
            "opening_balance": balance,
            "emi": emi,
            "principal": bk["principal_component"],
            "interest": bk["interest_component"],
            "closing_balance": bk["new_outstanding"],
        })
        balance = bk["new_outstanding"]

    return schedule
