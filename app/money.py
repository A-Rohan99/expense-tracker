"""
Monetary value handling.

Every money column in the schema is ``Numeric(14, 2)``.  These helpers are the
only sanctioned way to produce a value for one.

Why this module exists: money must never round-trip through ``float``.
Postgres rounds on write where SQLite does not, so a float cast makes the same
sequence of transactions produce *different* balances on the two backends —
which turns a SQLite-to-Postgres migration into silent data corruption.  Keep
values as ``Decimal`` from the request body all the way to the column.

Lives at the top of the package (not under ``routers`` or ``services``) so both
layers can use it without an import cycle.
"""

from __future__ import annotations

from decimal import ROUND_HALF_UP, Decimal

# The quantum of a Numeric(14, 2) column.
CENTS = Decimal("0.01")


def to_decimal(value) -> Decimal:
    """Convert an ORM numeric value to ``Decimal`` without going via float."""
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value))


def money(value) -> Decimal:
    """
    Normalise a monetary value to exactly two decimal places.

    Use on every write to a money column.  Rounds half-up, matching
    ``app.services.finance``, so interest and EMI splits round the same way
    the ledger does.
    """
    return to_decimal(value).quantize(CENTS, rounding=ROUND_HALF_UP)
