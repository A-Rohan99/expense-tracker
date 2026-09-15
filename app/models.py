"""
SQLAlchemy ORM models — double-entry-style personal finance schema.

Design notes
------------
* **Household** is the sharing boundary.  A user may belong to zero or one
  household.  Transactions flagged ``is_household_shared`` become visible to
  all household members.

* **Account** = liquid assets (bank accounts, cash wallets, digital wallets).
  ``current_balance`` is authoritative and updated transactionally.

* **CreditCard** tracks limits and billing cycle metadata.  Billed / unbilled
  amounts are *derived* at query time from Transactions — never stored as
  static columns — so the numbers can never drift.

* **Loan** tracks the amortisation schedule metadata.  ``outstanding_balance``
  is updated on each EMI payment transaction.

* **Transaction** is the unified ledger.  ``transaction_type`` selects the
  variant (income / expense / transfer), and nullable FKs point to the
  specific instrument involved.  For a *transfer* (e.g. paying a CC bill
  from a bank account) both ``account_id`` (source) and one of
  ``credit_card_id`` / ``loan_id`` (destination) will be populated.

All monetary columns use ``Numeric(14, 2)`` — a fixed-point type that avoids
floating-point drift and maps cleanly to both SQLite REAL and Postgres NUMERIC.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _uuid() -> str:
    """Generate a URL-safe UUID4 string (works on both SQLite & Postgres)."""
    return uuid.uuid4().hex


# ═══════════════════════════════════════════════════════════════════════════
# HOUSEHOLD
# ═══════════════════════════════════════════════════════════════════════════

class Household(Base):
    __tablename__ = "households"

    id: Mapped[str] = mapped_column(
        String(32), primary_key=True, default=_uuid
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    invite_code: Mapped[str] = mapped_column(
        String(32), unique=True, nullable=False, default=_uuid,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False,
    )

    # back-refs
    members: Mapped[list["User"]] = relationship(back_populates="household")

    def __repr__(self) -> str:
        return f"<Household {self.name!r}>"


# ═══════════════════════════════════════════════════════════════════════════
# USER
# ═══════════════════════════════════════════════════════════════════════════

class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(
        String(32), primary_key=True, default=_uuid,
    )
    email: Mapped[str] = mapped_column(
        String(254), unique=True, nullable=False, index=True,
    )
    hashed_password: Mapped[str] = mapped_column(String(128), nullable=False)
    full_name: Mapped[str] = mapped_column(String(120), nullable=False)
    is_active: Mapped[bool] = mapped_column(
        Boolean, default=True, nullable=False,
    )

    # Optional household membership
    household_id: Mapped[str | None] = mapped_column(
        String(32), ForeignKey("households.id", ondelete="SET NULL"),
        nullable=True, index=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # relationships
    household: Mapped[Household | None] = relationship(back_populates="members")
    accounts: Mapped[list["Account"]] = relationship(
        back_populates="owner", cascade="all, delete-orphan",
    )
    credit_cards: Mapped[list["CreditCard"]] = relationship(
        back_populates="owner", cascade="all, delete-orphan",
    )
    loans: Mapped[list["Loan"]] = relationship(
        back_populates="owner", cascade="all, delete-orphan",
    )
    recurring_income: Mapped["RecurringIncome | None"] = relationship(
        back_populates="owner",
        cascade="all, delete-orphan",
        uselist=False,
    )
    transactions: Mapped[list["Transaction"]] = relationship(
        back_populates="owner", cascade="all, delete-orphan",
    )

    def __repr__(self) -> str:
        return f"<User {self.email!r}>"


# ═══════════════════════════════════════════════════════════════════════════
# ACCOUNT  (Assets — Bank accounts, wallets)
# ═══════════════════════════════════════════════════════════════════════════

class Account(Base):
    __tablename__ = "accounts"

    id: Mapped[str] = mapped_column(
        String(32), primary_key=True, default=_uuid,
    )
    user_id: Mapped[str] = mapped_column(
        String(32),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    account_type: Mapped[str] = mapped_column(
        String(30), nullable=False, default="bank",
    )  # bank | cash | wallet
    current_balance: Mapped[float] = mapped_column(
        Numeric(14, 2), nullable=False, default=0,
    )
    currency: Mapped[str] = mapped_column(
        String(3), nullable=False, default="INR",
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean, default=True, nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False,
    )

    # constraints
    __table_args__ = (
        CheckConstraint(
            "account_type IN ('bank', 'cash', 'wallet')",
            name="ck_account_type",
        ),
    )

    # relationships
    owner: Mapped["User"] = relationship(back_populates="accounts")
    transactions: Mapped[list["Transaction"]] = relationship(
        back_populates="account",
    )

    def __repr__(self) -> str:
        return f"<Account {self.name!r} bal={self.current_balance}>"


# ═══════════════════════════════════════════════════════════════════════════
# CREDIT CARD  (Liabilities)
# ═══════════════════════════════════════════════════════════════════════════

class CreditCard(Base):
    __tablename__ = "credit_cards"

    id: Mapped[str] = mapped_column(
        String(32), primary_key=True, default=_uuid,
    )
    user_id: Mapped[str] = mapped_column(
        String(32),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(
        String(120), nullable=False,
    )  # e.g. "HDFC Regalia"
    last_four: Mapped[str | None] = mapped_column(
        String(4), nullable=True,
    )  # optional card identifier
    total_limit: Mapped[float] = mapped_column(
        Numeric(14, 2), nullable=False,
    )
    statement_day: Mapped[int] = mapped_column(
        Integer, nullable=False,
    )  # 1-31
    due_day: Mapped[int] = mapped_column(
        Integer, nullable=False,
    )  # 1-31
    currency: Mapped[str] = mapped_column(
        String(3), nullable=False, default="INR",
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean, default=True, nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False,
    )

    __table_args__ = (
        CheckConstraint(
            "statement_day BETWEEN 1 AND 31", name="ck_cc_statement_day",
        ),
        CheckConstraint(
            "due_day BETWEEN 1 AND 31", name="ck_cc_due_day",
        ),
        CheckConstraint(
            "total_limit >= 0", name="ck_cc_total_limit_nonneg",
        ),
    )

    # relationships
    owner: Mapped["User"] = relationship(back_populates="credit_cards")
    transactions: Mapped[list["Transaction"]] = relationship(
        back_populates="credit_card",
    )

    # NOTE: billed/unbilled are *derived* from transaction queries —
    # never persisted as columns.

    def __repr__(self) -> str:
        return f"<CreditCard {self.name!r} limit={self.total_limit}>"


# ═══════════════════════════════════════════════════════════════════════════
# LOAN  (Liabilities — personal, auto, home, etc.)
# ═══════════════════════════════════════════════════════════════════════════

class Loan(Base):
    __tablename__ = "loans"

    id: Mapped[str] = mapped_column(
        String(32), primary_key=True, default=_uuid,
    )
    user_id: Mapped[str] = mapped_column(
        String(32),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(
        String(120), nullable=False,
    )  # e.g. "SBI Home Loan"
    loan_type: Mapped[str] = mapped_column(
        String(30), nullable=False, default="personal",
    )  # personal | home | auto | education | other
    principal_amount: Mapped[float] = mapped_column(
        Numeric(14, 2), nullable=False,
    )
    interest_rate: Mapped[float] = mapped_column(
        Numeric(5, 2), nullable=False,
    )  # annual % e.g. 8.50
    tenure_months: Mapped[int] = mapped_column(
        Integer, nullable=False,
    )
    outstanding_balance: Mapped[float] = mapped_column(
        Numeric(14, 2), nullable=False,
    )
    start_date: Mapped[date] = mapped_column(
        Date, nullable=False,
    )
    currency: Mapped[str] = mapped_column(
        String(3), nullable=False, default="INR",
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean, default=True, nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False,
    )

    __table_args__ = (
        CheckConstraint(
            "principal_amount > 0", name="ck_loan_principal_positive",
        ),
        CheckConstraint(
            "interest_rate >= 0", name="ck_loan_rate_nonneg",
        ),
        CheckConstraint(
            "tenure_months > 0", name="ck_loan_tenure_positive",
        ),
        CheckConstraint(
            "outstanding_balance >= 0", name="ck_loan_outstanding_nonneg",
        ),
        CheckConstraint(
            "loan_type IN ('personal', 'home', 'auto', 'education', 'other')",
            name="ck_loan_type",
        ),
    )

    # relationships
    owner: Mapped["User"] = relationship(back_populates="loans")
    transactions: Mapped[list["Transaction"]] = relationship(
        back_populates="loan",
    )

    def __repr__(self) -> str:
        return f"<Loan {self.name!r} outstanding={self.outstanding_balance}>"


# ═══════════════════════════════════════════════════════════════════════════
# TRANSACTION  (unified ledger)
# ═══════════════════════════════════════════════════════════════════════════

class Transaction(Base):
    """
    Unified ledger entry.

    ``transaction_type`` semantics:
        income   — money in.  ``account_id`` = destination.
        expense  — money out. ``account_id`` or ``credit_card_id`` = source.
        transfer — money moved between instruments.
                   ``account_id`` = source account,
                   ``credit_card_id`` or ``loan_id`` = destination
                   (e.g. CC bill payment, EMI payment).
    """
    __tablename__ = "transactions"

    id: Mapped[str] = mapped_column(
        String(32), primary_key=True, default=_uuid,
    )
    user_id: Mapped[str] = mapped_column(
        String(32),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    # ── Core fields ────────────────────────────────────────────────────
    transaction_type: Mapped[str] = mapped_column(
        String(10), nullable=False,
    )  # income | expense | transfer
    amount: Mapped[float] = mapped_column(
        Numeric(14, 2), nullable=False,
    )  # always positive
    currency: Mapped[str] = mapped_column(
        String(3), nullable=False, default="INR",
    )
    transaction_date: Mapped[date] = mapped_column(
        Date, nullable=False, default=date.today,
    )
    category: Mapped[str] = mapped_column(
        String(60), nullable=False,
    )
    description: Mapped[str | None] = mapped_column(
        Text, nullable=True,
    )

    # ── Household sharing ──────────────────────────────────────────────
    is_household_shared: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False,
    )

    # ── Instrument links (nullable — set based on type) ────────────────
    account_id: Mapped[str | None] = mapped_column(
        String(32),
        ForeignKey("accounts.id", ondelete="SET NULL"),
        nullable=True,
    )
    credit_card_id: Mapped[str | None] = mapped_column(
        String(32),
        ForeignKey("credit_cards.id", ondelete="SET NULL"),
        nullable=True,
    )
    loan_id: Mapped[str | None] = mapped_column(
        String(32),
        ForeignKey("loans.id", ondelete="SET NULL"),
        nullable=True,
    )

    # ── Timestamps ─────────────────────────────────────────────────────
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # ── Constraints & indexes ──────────────────────────────────────────
    __table_args__ = (
        CheckConstraint(
            "transaction_type IN ('income', 'expense', 'transfer')",
            name="ck_txn_type",
        ),
        CheckConstraint("amount > 0", name="ck_txn_amount_positive"),
        # Most common query: "my transactions this month"
        Index("ix_txn_user_date", "user_id", "transaction_date"),
        # Household queries: "shared transactions for my household"
        Index("ix_txn_household", "user_id", "is_household_shared"),
    )

    # ── Relationships ──────────────────────────────────────────────────
    owner: Mapped["User"] = relationship(back_populates="transactions")
    account: Mapped[Account | None] = relationship(back_populates="transactions")
    credit_card: Mapped[CreditCard | None] = relationship(
        back_populates="transactions",
    )
    loan: Mapped[Loan | None] = relationship(back_populates="transactions")

    def __repr__(self) -> str:
        return (
            f"<Transaction {self.transaction_type} "
            f"{self.amount} {self.category!r}>"
        )


# ═══════════════════════════════════════════════════════════════════════════
# RECURRING INCOME  (salary / retainer that lands on the same day each month)
# ═══════════════════════════════════════════════════════════════════════════

class RecurringIncome(Base):
    """
    A standing monthly income instruction.

    On ``day_of_month`` each month an ``income`` Transaction is posted into
    ``account_id``.  Posting is driven by a catch-up pass (see
    ``app.services.recurring``) rather than a scheduler, so the app works
    correctly even if nothing runs for weeks.

    ``last_posted_period`` is the ``YYYY-MM`` of the most recent month already
    posted.  It is the idempotency key: a month is never posted twice, no
    matter how often the catch-up runs.
    """
    __tablename__ = "recurring_incomes"

    id: Mapped[str] = mapped_column(
        String(32), primary_key=True, default=_uuid,
    )
    user_id: Mapped[str] = mapped_column(
        String(32),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    account_id: Mapped[str] = mapped_column(
        String(32),
        ForeignKey("accounts.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(
        String(120), nullable=False, default="Monthly income",
    )
    amount: Mapped[float] = mapped_column(Numeric(14, 2), nullable=False)
    # 1–31.  Months shorter than the chosen day clamp to the last day.
    day_of_month: Mapped[int] = mapped_column(Integer, nullable=False)
    category: Mapped[str] = mapped_column(
        String(60), nullable=False, default="Salary",
    )
    currency: Mapped[str] = mapped_column(
        String(3), nullable=False, default="INR",
    )
    is_household_shared: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False,
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean, default=True, nullable=False,
    )
    # "YYYY-MM" of the last month posted; NULL means nothing posted yet.
    last_posted_period: Mapped[str | None] = mapped_column(
        String(7), nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    __table_args__ = (
        CheckConstraint("amount > 0", name="ck_recurring_income_positive"),
        CheckConstraint(
            "day_of_month >= 1 AND day_of_month <= 31",
            name="ck_recurring_income_day",
        ),
        # One standing instruction per user keeps the UI unambiguous.
        UniqueConstraint("user_id", name="uq_recurring_income_user"),
    )

    owner: Mapped["User"] = relationship(back_populates="recurring_income")
    account: Mapped[Account] = relationship()

    def __repr__(self) -> str:
        return (
            f"<RecurringIncome {self.amount} on day {self.day_of_month} "
            f"last={self.last_posted_period}>"
        )
