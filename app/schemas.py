"""
Pydantic schemas (v2) for request validation, response serialisation,
and internal DTOs.

Naming convention
-----------------
* ``*Create``  — write payloads (POST / PUT bodies)
* ``*Update``  — partial-update payloads (PATCH bodies)
* ``*Read``    — API response shapes (include computed & server-side fields)
"""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from typing import Annotated

from pydantic import (
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
    model_validator,
)


# ═══════════════════════════════════════════════════════════════════════════
# Enums (used in validation AND as OpenAPI documentation)
# ═══════════════════════════════════════════════════════════════════════════

class AccountType(str, Enum):
    bank = "bank"
    cash = "cash"
    wallet = "wallet"


class LoanType(str, Enum):
    personal = "personal"
    home = "home"
    auto = "auto"
    education = "education"
    other = "other"


class TransactionType(str, Enum):
    income = "income"
    expense = "expense"
    transfer = "transfer"


class Currency(str, Enum):
    """
    Currencies the app supports.

    Was a free-form 3-character string, so "XXX" and "123" both validated —
    and since the UI formats everything as ₹ with Indian digit grouping,
    anything but INR would have displayed as rupees regardless. Add codes here
    only alongside real multi-currency support in the client.
    """
    INR = "INR"


# ═══════════════════════════════════════════════════════════════════════════
# Shared field types (DRY)
# ═══════════════════════════════════════════════════════════════════════════

PositiveAmount = Annotated[Decimal, Field(gt=0, max_digits=14, decimal_places=2)]
NonNegativeAmount = Annotated[Decimal, Field(ge=0, max_digits=14, decimal_places=2)]
DayOfMonth = Annotated[int, Field(ge=1, le=31)]


# ═══════════════════════════════════════════════════════════════════════════
# AUTH / TOKEN
# ═══════════════════════════════════════════════════════════════════════════

class TokenRequest(BaseModel):
    """OAuth2-compatible login body (form fields: ``username``, ``password``)."""
    username: EmailStr
    password: str = Field(min_length=8, max_length=128)


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class TokenPayload(BaseModel):
    """Decoded JWT claims — internal use only, never returned to the client."""
    sub: str          # user id
    exp: datetime
    type: str = "access"  # access | refresh


# ═══════════════════════════════════════════════════════════════════════════
# HOUSEHOLD
# ═══════════════════════════════════════════════════════════════════════════

class HouseholdCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class HouseholdRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    invite_code: str
    created_at: datetime


class HouseholdJoin(BaseModel):
    """Body for the "join household" endpoint."""
    invite_code: str = Field(min_length=1, max_length=32)


# ═══════════════════════════════════════════════════════════════════════════
# USER
# ═══════════════════════════════════════════════════════════════════════════

class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    full_name: str = Field(min_length=1, max_length=120)


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    email: EmailStr
    full_name: str
    is_active: bool
    household_id: str | None = None
    created_at: datetime
    updated_at: datetime


class UserUpdate(BaseModel):
    full_name: str | None = Field(None, min_length=1, max_length=120)
    email: EmailStr | None = None


# ═══════════════════════════════════════════════════════════════════════════
# ACCOUNT  (Assets)
# ═══════════════════════════════════════════════════════════════════════════

class AccountCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    account_type: AccountType = AccountType.bank
    current_balance: NonNegativeAmount = Decimal("0.00")
    currency: Currency = Currency.INR


class AccountRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    name: str
    account_type: AccountType
    current_balance: Decimal
    currency: str
    is_active: bool
    created_at: datetime


class AccountUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=120)
    account_type: AccountType | None = None
    current_balance: NonNegativeAmount | None = None
    currency: Currency | None = None
    is_active: bool | None = None


# ═══════════════════════════════════════════════════════════════════════════
# CREDIT CARD  (Liabilities)
# ═══════════════════════════════════════════════════════════════════════════

class CreditCardCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    last_four: str | None = Field(None, min_length=4, max_length=4, pattern=r"^\d{4}$")
    total_limit: PositiveAmount
    statement_day: DayOfMonth
    due_day: DayOfMonth
    currency: Currency = Currency.INR


class CreditCardRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    name: str
    last_four: str | None = None
    total_limit: Decimal
    statement_day: int
    due_day: int
    currency: str
    is_active: bool
    created_at: datetime

    # These are *not* columns — they'll be populated by the service layer
    # using SUM queries against the transaction table.
    unbilled_amount: Decimal = Decimal("0.00")
    billed_amount: Decimal = Decimal("0.00")
    available_limit: Decimal = Decimal("0.00")


class CreditCardUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=120)
    last_four: str | None = Field(None, min_length=4, max_length=4, pattern=r"^\d{4}$")
    total_limit: PositiveAmount | None = None
    statement_day: DayOfMonth | None = None
    due_day: DayOfMonth | None = None
    currency: Currency | None = None
    is_active: bool | None = None


# ═══════════════════════════════════════════════════════════════════════════
# LOAN  (Liabilities)
# ═══════════════════════════════════════════════════════════════════════════

class LoanCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    loan_type: LoanType = LoanType.personal
    principal_amount: PositiveAmount
    interest_rate: Annotated[Decimal, Field(ge=0, max_digits=5, decimal_places=2)]
    tenure_months: int = Field(gt=0, le=600)
    outstanding_balance: PositiveAmount
    start_date: date
    currency: Currency = Currency.INR


class LoanRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    name: str
    loan_type: LoanType
    principal_amount: Decimal
    interest_rate: Decimal
    tenure_months: int
    outstanding_balance: Decimal
    start_date: date
    currency: str
    is_active: bool
    created_at: datetime

    # Derived from the ledger, not stored — mirrors how credit-card
    # outstanding is computed, so it can never drift from reality.
    emi_paid_this_month: bool = False
    last_emi_payment_date: date | None = None


class LoanUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=120)
    loan_type: LoanType | None = None
    interest_rate: Annotated[Decimal, Field(ge=0, max_digits=5, decimal_places=2)] | None = None
    outstanding_balance: NonNegativeAmount | None = None
    currency: Currency | None = None
    is_active: bool | None = None


# ═══════════════════════════════════════════════════════════════════════════
# TRANSACTION  (unified ledger)
# ═══════════════════════════════════════════════════════════════════════════

class TransactionCreate(BaseModel):
    transaction_type: TransactionType
    amount: PositiveAmount
    currency: Currency = Currency.INR
    transaction_date: date = Field(default_factory=date.today)
    category: str = Field(min_length=1, max_length=60)
    description: str | None = Field(None, max_length=500)
    is_household_shared: bool = False

    # Instrument links (nullable — set based on transaction_type)
    account_id: str | None = None
    credit_card_id: str | None = None
    loan_id: str | None = None

    @model_validator(mode="after")
    def validate_instrument_links(self) -> "TransactionCreate":
        """
        Business rules:
        - income:   account_id required (where the money lands)
        - expense:  at least one of account_id or credit_card_id required
        - transfer: account_id required + exactly one of credit_card_id / loan_id
        """
        t = self.transaction_type

        if t == TransactionType.income:
            if not self.account_id:
                raise ValueError(
                    "Income transactions require an account_id "
                    "(the account receiving the money)."
                )

        elif t == TransactionType.expense:
            if not self.account_id and not self.credit_card_id:
                raise ValueError(
                    "Expense transactions require at least one of "
                    "account_id or credit_card_id."
                )

        elif t == TransactionType.transfer:
            if not self.account_id:
                raise ValueError(
                    "Transfer transactions require an account_id "
                    "(the source account)."
                )
            destinations = sum([
                self.credit_card_id is not None,
                self.loan_id is not None,
            ])
            if destinations != 1:
                raise ValueError(
                    "Transfer transactions require exactly one destination: "
                    "either credit_card_id (CC bill payment) or "
                    "loan_id (EMI payment)."
                )

        return self


class TransactionRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    transaction_type: TransactionType
    amount: Decimal
    currency: str
    transaction_date: date
    category: str
    description: str | None = None
    is_household_shared: bool

    account_id: str | None = None
    credit_card_id: str | None = None
    loan_id: str | None = None

    created_at: datetime
    updated_at: datetime


class TransactionUpdate(BaseModel):
    """Partial update for transaction metadata.

    Amount and instrument links are immutable — delete and recreate to
    change.  This follows double-entry accounting conventions.
    """
    transaction_date: date | None = None
    category: str | None = Field(None, min_length=1, max_length=60)
    description: str | None = Field(None, max_length=500)
    is_household_shared: bool | None = None


# ═══════════════════════════════════════════════════════════════════════════
# PAGINATION (reusable wrapper)
# ═══════════════════════════════════════════════════════════════════════════

class PaginationParams(BaseModel):
    """Query params for paginated list endpoints."""
    skip: int = Field(default=0, ge=0)
    limit: int = Field(default=50, ge=1, le=100)


class PaginatedResponse(BaseModel):
    """Generic paginated envelope — ``items`` is typed per-endpoint."""
    total: int
    skip: int
    limit: int
    items: list


# ═══════════════════════════════════════════════════════════════════════════
# AUTH — refresh token
# ═══════════════════════════════════════════════════════════════════════════

class RefreshTokenRequest(BaseModel):
    refresh_token: str


# ═══════════════════════════════════════════════════════════════════════════
# CREDIT CARD — dynamic summary
# ═══════════════════════════════════════════════════════════════════════════

class CreditCardSummaryResponse(BaseModel):
    """Dynamically computed credit-card billing snapshot."""
    card_id: str
    card_name: str
    total_limit: Decimal

    # Derived from transaction queries
    billed_amount: Decimal
    unbilled_amount: Decimal
    total_outstanding: Decimal
    available_limit: Decimal
    total_payments: Decimal
    min_due_amount: Decimal

    # Billing cycle dates
    last_statement_date: date
    next_statement_date: date
    due_date: date
    days_until_due: int  # negative = overdue


# ═══════════════════════════════════════════════════════════════════════════
# EMI — calculator & payment
# ═══════════════════════════════════════════════════════════════════════════

class EMICalculationRequest(BaseModel):
    """Standalone EMI calculator (no loan record required)."""
    principal: PositiveAmount
    annual_rate: Annotated[Decimal, Field(ge=0, max_digits=5, decimal_places=2)]
    tenure_months: int = Field(gt=0, le=600)


class EMICalculationResponse(BaseModel):
    emi: Decimal
    total_payment: Decimal
    total_interest: Decimal
    principal: Decimal


class EMIPaymentRequest(BaseModel):
    """Body for the pay-EMI endpoint."""
    account_id: str  # source bank account


class EMIPaymentResponse(BaseModel):
    transaction_id: str
    emi_amount: Decimal
    principal_component: Decimal
    interest_component: Decimal
    new_outstanding_balance: Decimal
    account_new_balance: Decimal


class AmortisationRow(BaseModel):
    month: int
    opening_balance: Decimal
    emi: Decimal
    principal: Decimal
    interest: Decimal
    closing_balance: Decimal


# ═══════════════════════════════════════════════════════════════════════════
# RECURRING INCOME
# ═══════════════════════════════════════════════════════════════════════════

class RecurringIncomeCreate(BaseModel):
    """Set up (or replace) the standing monthly income instruction."""
    account_id: str
    amount: Decimal = Field(gt=0)
    day_of_month: int = Field(ge=1, le=31)
    name: str = Field("Monthly income", min_length=1, max_length=120)
    category: str = Field("Salary", min_length=1, max_length=60)
    currency: Currency = Currency.INR
    is_household_shared: bool = False


class RecurringIncomeUpdate(BaseModel):
    account_id: str | None = None
    amount: Decimal | None = Field(None, gt=0)
    day_of_month: int | None = Field(None, ge=1, le=31)
    name: str | None = Field(None, min_length=1, max_length=120)
    category: str | None = Field(None, min_length=1, max_length=60)
    is_household_shared: bool | None = None
    is_active: bool | None = None


class RecurringIncomeRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    account_id: str
    name: str
    amount: Decimal
    day_of_month: int
    category: str
    currency: str
    is_household_shared: bool
    is_active: bool
    last_posted_period: str | None = None
    created_at: datetime
    updated_at: datetime

    # Server-computed conveniences so the client never has to do calendar math.
    next_due_date: date | None = None
    account_name: str | None = None
    posted_this_run: int = 0
