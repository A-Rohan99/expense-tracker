"""
Auth routes — register, login, token refresh, and current-user info.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Response, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.auth import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_current_active_user,
    hash_password,
    verify_password,
)
from app.db import get_db
from app.models import User
from app.schemas import (
    RefreshTokenRequest,
    TokenResponse,
    UserCreate,
    UserRead,
)

router = APIRouter(prefix="/auth", tags=["auth"])

logger = logging.getLogger("app.auth")


# ── POST /register ─────────────────────────────────────────────────────────

@router.post("/register", response_model=UserRead, status_code=201)
def register(body: UserCreate, db: Session = Depends(get_db)):
    """Create a new user account."""
    if db.query(User).filter(User.email == body.email).first():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A user with this email already exists",
        )

    user = User(
        email=body.email,
        hashed_password=hash_password(body.password),
        full_name=body.full_name,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


# ── POST /login ────────────────────────────────────────────────────────────

@router.post("/login", response_model=TokenResponse)
def login(
    form: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db),
):
    """
    OAuth2-compatible login.

    Accepts ``username`` (email) and ``password`` as form fields.
    Returns an access + refresh token pair.
    """
    user = db.query(User).filter(User.email == form.username).first()
    if not user or not verify_password(form.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is deactivated",
        )

    return TokenResponse(
        access_token=create_access_token(user.id, token_version=user.token_version),
        refresh_token=create_refresh_token(user.id, token_version=user.token_version),
    )


# ── POST /refresh ──────────────────────────────────────────────────────────

@router.post("/refresh", response_model=TokenResponse)
def refresh(body: RefreshTokenRequest, db: Session = Depends(get_db)):
    """Exchange a valid refresh token for a new access + refresh pair."""
    payload = decode_token(body.refresh_token, expected_type="refresh")
    user = db.query(User).filter(User.id == payload["sub"]).first()
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # A refresh token from before the last logout must not mint a new pair.
    if payload.get("ver", 0) != user.token_version:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session has been signed out",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return TokenResponse(
        access_token=create_access_token(user.id, token_version=user.token_version),
        refresh_token=create_refresh_token(user.id, token_version=user.token_version),
    )


# ── GET /me ────────────────────────────────────────────────────────────────

@router.get("/me", response_model=UserRead)
def me(user: User = Depends(get_current_active_user)):
    """Return the authenticated user's profile."""
    return user


# ── POST /logout ───────────────────────────────────────────────────────────

@router.post("/logout", status_code=204)
def logout(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
):
    """
    Sign out everywhere.

    Bumps the user's token version, which invalidates every access and refresh
    token already issued. Previously there was no logout at all: a stolen
    refresh token stayed usable for its full 7-day life and the only kill
    switch was deactivating the account, which locks the real user out too.
    """
    user.token_version += 1
    db.commit()
    logger.info("User signed out of all sessions", extra={
        "extra_fields": {"user_id": user.id},
    })
    return Response(status_code=204)
