"""
JWT authentication utilities.

Provides:
* Password hashing (bcrypt — direct, no passlib wrapper)
* JWT creation (access + refresh tokens)
* Token verification
* FastAPI dependency (``get_current_user``) for route-level auth
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import bcrypt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from app.config import (
    ACCESS_TOKEN_EXPIRE_MINUTES,
    ALGORITHM,
    REFRESH_TOKEN_EXPIRE_DAYS,
    SECRET_KEY,
)
from app.db import get_db
from app.models import User

# ---------------------------------------------------------------------------
# Password hashing  (bcrypt direct — passlib is unmaintained)
# ---------------------------------------------------------------------------


def hash_password(plain: str) -> str:
    """Return a bcrypt hash of *plain*."""
    return bcrypt.hashpw(
        plain.encode("utf-8"), bcrypt.gensalt()
    ).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    """Check *plain* against a bcrypt *hashed* value."""
    return bcrypt.checkpw(
        plain.encode("utf-8"), hashed.encode("utf-8")
    )


# ---------------------------------------------------------------------------
# JWT creation
# ---------------------------------------------------------------------------

def create_access_token(
    subject: str,
    expires_delta: timedelta | None = None,
) -> str:
    """
    Create a short-lived access token.

    Parameters
    ----------
    subject : str
        The user's primary key (``User.id``).
    expires_delta : timedelta, optional
        Override the default expiry from config.
    """
    expire = datetime.now(timezone.utc) + (
        expires_delta
        or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    return jwt.encode(
        {"sub": subject, "exp": expire, "type": "access"},
        SECRET_KEY,
        algorithm=ALGORITHM,
    )


def create_refresh_token(
    subject: str,
    expires_delta: timedelta | None = None,
) -> str:
    """Create a longer-lived refresh token used to rotate access tokens."""
    expire = datetime.now(timezone.utc) + (
        expires_delta
        or timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    )
    return jwt.encode(
        {"sub": subject, "exp": expire, "type": "refresh"},
        SECRET_KEY,
        algorithm=ALGORITHM,
    )


# ---------------------------------------------------------------------------
# Token verification
# ---------------------------------------------------------------------------

def decode_token(token: str, *, expected_type: str = "access") -> dict:
    """
    Decode and validate a JWT.

    Returns the full claims dict on success.
    Raises ``HTTPException(401)`` on any failure.
    """
    credentials_exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        raise credentials_exc

    if payload.get("type") != expected_type:
        raise credentials_exc

    if payload.get("sub") is None:
        raise credentials_exc

    return payload


# ---------------------------------------------------------------------------
# FastAPI dependencies
# ---------------------------------------------------------------------------

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    """
    Dependency that extracts and verifies the bearer token, then loads the
    corresponding ``User`` row.

    Usage::

        @router.get("/me")
        def me(user: User = Depends(get_current_user)):
            ...
    """
    payload = decode_token(token, expected_type="access")
    user_id: str = payload["sub"]

    user = db.query(User).filter(User.id == user_id).first()
    if user is None or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found or inactive",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


def get_current_active_user(
    current_user: User = Depends(get_current_user),
) -> User:
    """Convenience alias that rejects inactive accounts explicitly."""
    if not current_user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is deactivated",
        )
    return current_user
