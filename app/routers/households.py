"""
Household management — create, join, leave, view members.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import get_current_active_user
from app.db import get_db
from app.models import Household, User
from app.schemas import HouseholdCreate, HouseholdJoin, HouseholdRead, UserRead

router = APIRouter(prefix="/households", tags=["households"])


# ── POST / — create a new household ───────────────────────────────────────

@router.post("/", response_model=HouseholdRead, status_code=201)
def create_household(
    body: HouseholdCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """Create a household and make the current user its first member."""
    if user.household_id:
        raise HTTPException(
            400, detail="You already belong to a household. Leave first."
        )

    household = Household(name=body.name)
    db.add(household)
    db.flush()  # get the generated id

    user.household_id = household.id
    db.commit()
    db.refresh(household)
    return household


# ── POST /join ─────────────────────────────────────────────────────────────

@router.post("/join", response_model=HouseholdRead)
def join_household(
    body: HouseholdJoin,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """Join an existing household using its invite code."""
    if user.household_id:
        raise HTTPException(
            400, detail="You already belong to a household. Leave first."
        )

    household = (
        db.query(Household)
        .filter(Household.invite_code == body.invite_code)
        .first()
    )
    if not household:
        raise HTTPException(404, detail="Invalid invite code")

    user.household_id = household.id
    db.commit()
    db.refresh(household)
    return household


# ── POST /leave ────────────────────────────────────────────────────────────

@router.post("/leave", status_code=204)
def leave_household(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """Leave your current household."""
    if not user.household_id:
        raise HTTPException(400, detail="You are not in a household")

    household_id = user.household_id
    user.household_id = None

    # Flush rather than commit, so the membership count below sees the
    # departure while staying inside one transaction. Committing here and again
    # after the cleanup left a window where a crash orphaned a member-less
    # household row permanently.
    db.flush()

    # Clean up: delete the household if it has no remaining members.
    remaining = (
        db.query(User)
        .filter(User.household_id == household_id)
        .count()
    )
    if remaining == 0:
        household = db.query(Household).filter(Household.id == household_id).first()
        if household:
            db.delete(household)

    db.commit()


# ── GET /me — current user's household ─────────────────────────────────────

@router.get("/me", response_model=HouseholdRead)
def my_household(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    if not user.household_id:
        raise HTTPException(404, detail="You are not in a household")
    household = db.query(Household).filter(Household.id == user.household_id).first()
    if not household:
        raise HTTPException(404, detail="Household not found")
    return household


# ── GET /members ───────────────────────────────────────────────────────────

@router.get("/members", response_model=list[UserRead])
def household_members(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """List all members of the current user's household."""
    if not user.household_id:
        raise HTTPException(404, detail="You are not in a household")
    return (
        db.query(User)
        .filter(User.household_id == user.household_id)
        .all()
    )
