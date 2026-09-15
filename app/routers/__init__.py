"""
Shared router helpers.
"""

from __future__ import annotations

from fastapi import HTTPException
from sqlalchemy.orm import Session

# Re-exported so routers can keep importing money helpers from one place.
from app.money import money, to_decimal  # noqa: F401


def get_or_404(
    db: Session,
    model,
    record_id: str,
    *,
    user_id: str | None = None,
    for_update: bool = False,
):
    """
    Fetch a record by primary key, optionally verifying ownership.

    Raises HTTP 404 if not found or not owned by *user_id*.

    Pass ``for_update=True`` when the caller is about to mutate a balance.
    Without the row lock two concurrent requests both read the same balance,
    both pass their sufficiency check, and the second write silently discards
    the first — a lost update that lets an account be overdrawn.  SQLite
    ignores ``FOR UPDATE`` (it locks the whole database anyway), so this is a
    no-op in dev and load-bearing on Postgres.
    """
    query = db.query(model).filter(model.id == record_id)
    if user_id is not None:
        query = query.filter(model.user_id == user_id)
    if for_update:
        query = query.with_for_update()
    obj = query.first()
    if obj is None:
        raise HTTPException(status_code=404, detail=f"{model.__name__} not found")
    return obj

