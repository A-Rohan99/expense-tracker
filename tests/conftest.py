"""
Shared test fixtures.

Each test gets its own database and its own TestClient, so tests never see one
another's data and can run in any order.

The suite runs against SQLite by default for speed. CI points DATABASE_URL at
Postgres so dialect differences — the exact thing that makes a
SQLite-to-Postgres migration dangerous — get caught before a deploy.
"""

from __future__ import annotations

import os
import uuid

# Set before importing anything from app: app.config validates at import time.
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("SECRET_KEY", "test-only-secret-never-used-in-production")
os.environ.setdefault("ALLOWED_ORIGINS", "http://localhost:5000")
# Rate limiting is stateful across a process; tests that care enable it
# explicitly rather than having every other test fight the shared counter.
os.environ.setdefault("RATE_LIMIT_ENABLED", "false")

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.db import Base, get_db  # noqa: E402
# Aliased: `import app.models` below would otherwise rebind the name `app`
# from the FastAPI instance to the package itself.
from app.main import app as fastapi_app  # noqa: E402
import app.models  # noqa: E402,F401  (registers tables on Base.metadata)


@pytest.fixture
def db_session():
    """A fresh in-memory database per test."""
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        # One shared connection, so the schema created here is the same one
        # the request sees — an in-memory SQLite database is per-connection.
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    TestingSession = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    session = TestingSession()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


@pytest.fixture
def client(db_session):
    """A TestClient wired to the per-test database."""

    def _override_get_db():
        try:
            yield db_session
        finally:
            # The session's lifetime is the fixture's, not the request's.
            pass

    fastapi_app.dependency_overrides[get_db] = _override_get_db
    with TestClient(fastapi_app) as test_client:
        yield test_client
    fastapi_app.dependency_overrides.clear()


# ---------------------------------------------------------------------------
# Convenience helpers
# ---------------------------------------------------------------------------

DEFAULT_PASSWORD = "TestPassword123!"


@pytest.fixture
def make_user(client):
    """Register a user and return its auth headers."""

    def _make(email: str | None = None, password: str = DEFAULT_PASSWORD):
        email = email or f"user_{uuid.uuid4().hex[:10]}@example.com"
        response = client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": password, "full_name": "Test User"},
        )
        assert response.status_code == 201, response.text

        token_response = client.post(
            "/api/v1/auth/login",
            data={"username": email, "password": password},
        )
        assert token_response.status_code == 200, token_response.text
        tokens = token_response.json()
        return {
            "email": email,
            "password": password,
            "headers": {"Authorization": f"Bearer {tokens['access_token']}"},
            "refresh_token": tokens["refresh_token"],
        }

    return _make


@pytest.fixture
def user(make_user):
    """The common case: one signed-in user."""
    return make_user()


@pytest.fixture
def auth(user):
    """Authorization headers for [user]."""
    return user["headers"]


@pytest.fixture
def make_account(client, auth):
    """Create an account for the signed-in user."""

    def _make(name: str = "Test Bank", balance: str = "10000.00", **kwargs):
        response = client.post(
            "/api/v1/accounts/",
            headers=auth,
            json={
                "name": name,
                "account_type": kwargs.pop("account_type", "bank"),
                "current_balance": balance,
                **kwargs,
            },
        )
        assert response.status_code == 201, response.text
        return response.json()

    return _make
