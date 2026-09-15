"""
Shared router helpers.
"""

from __future__ import annotations

from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy.orm import Session


def get_or_404(
    db: Session,
    model,
    record_id: str,
    *,
    user_id: str | None = None,
):
    """
    Fetch a record by primary key, optionally verifying ownership.

    Raises HTTP 404 if not found or not owned by *user_id*.
    """
    query = db.query(model).filter(model.id == record_id)
    if user_id is not None:
        query = query.filter(model.user_id == user_id)
    obj = query.first()
    if obj is None:
        raise HTTPException(status_code=404, detail=f"{model.__name__} not found")
    return obj


def to_decimal(value) -> Decimal:
    """Safely convert an ORM numeric value to Decimal."""
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value))
