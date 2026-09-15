"""
Recurring income posting.

There is no scheduler.  Instead every read of the standing instruction runs a
*catch-up*: it works out which months are due but not yet posted, and posts
them.  That keeps the ledger correct whether the app is opened daily or once a
quarter, and survives the process being down on payday.

``RecurringIncome.last_posted_period`` ("YYYY-MM") is the idempotency key, so
running the catch-up twice in the same second posts nothing the second time.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

from sqlalchemy.orm import Session

from app.models import Account, RecurringIncome, Transaction
from app.services.finance import clamp_day, shift_month

# A standing instruction set up long ago shouldn't flood the ledger on first
# run; cap how far back a single catch-up will reach.
MAX_CATCHUP_MONTHS = 24


def period_key(d: date) -> str:
    """The ``YYYY-MM`` bucket a date falls in."""
    return f"{d.year:04d}-{d.month:02d}"


def due_date_for(period: date, day_of_month: int) -> date:
    """
    The posting date within ``period``'s month.

    Months shorter than the chosen day clamp to the last day, so a "31st"
    instruction pays on the 28th/29th in February rather than being skipped.
    """
    return clamp_day(period.year, period.month, day_of_month)


def initial_last_posted(day_of_month: int, today: date | None = None) -> str | None:
    """
    What ``last_posted_period`` should be when an instruction is first created.

    If this month's pay date has already passed, mark the month as done — the
    user was almost certainly already paid and may have recorded it by hand, so
    posting it now would double-count.  If the date is still ahead, leave it
    unset so this month posts on schedule.
    """
    today = today or date.today()
    if due_date_for(today, day_of_month) < today:
        return period_key(today)
    return None


def next_due_date(income: RecurringIncome, today: date | None = None) -> date:
    """The next date this instruction will post on."""
    today = today or date.today()
    this_month = due_date_for(today, income.day_of_month)

    if income.last_posted_period == period_key(today):
        # Already paid this month — next one is next month.
        return due_date_for(shift_month(today, 1), income.day_of_month)
    if this_month >= today:
        return this_month
    # Date passed this month and not yet posted: a catch-up will post it now.
    return this_month


def _pending_periods(income: RecurringIncome, today: date) -> list[date]:
    """Every month that is due to post but hasn't been, oldest first."""
    if income.last_posted_period:
        year, month = (int(p) for p in income.last_posted_period.split("-"))
        cursor = shift_month(date(year, month, 1), 1)
    else:
        # Never posted — start from the month it was created in.
        created = income.created_at.date() if income.created_at else today
        cursor = date(created.year, created.month, 1)

    periods: list[date] = []
    current_month_start = date(today.year, today.month, 1)

    while cursor <= current_month_start and len(periods) < MAX_CATCHUP_MONTHS:
        if due_date_for(cursor, income.day_of_month) <= today:
            periods.append(cursor)
        cursor = shift_month(cursor, 1)

    return periods


def run_catch_up(
    db: Session,
    income: RecurringIncome | None,
    today: date | None = None,
) -> list[Transaction]:
    """
    Post every month that is due but unposted.  Returns the new transactions.

    Credits the destination account the same way a manual income entry does,
    so balances stay consistent with the rest of the ledger.
    """
    if income is None or not income.is_active:
        return []

    today = today or date.today()
    account: Account | None = db.get(Account, income.account_id)
    if account is None or not account.is_active:
        # Destination went away — leave the instruction alone rather than
        # posting into nothing; the API surfaces it as inactive.
        return []

    posted: list[Transaction] = []
    amount = Decimal(str(income.amount))

    for period in _pending_periods(income, today):
        txn = Transaction(
            user_id=income.user_id,
            transaction_type="income",
            amount=float(amount),
            currency=income.currency,
            transaction_date=due_date_for(period, income.day_of_month),
            category=income.category,
            description=f"{income.name} (automatic)",
            is_household_shared=income.is_household_shared,
            account_id=income.account_id,
        )
        db.add(txn)
        account.current_balance = float(
            Decimal(str(account.current_balance)) + amount
        )
        income.last_posted_period = period_key(period)
        posted.append(txn)

    if posted:
        db.commit()
        for txn in posted:
            db.refresh(txn)
        db.refresh(income)
        db.refresh(account)

    return posted
