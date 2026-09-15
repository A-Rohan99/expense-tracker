"""Authentication, token lifecycle and tenant isolation."""

from __future__ import annotations

import pytest

API = "/api/v1"


class TestRegistration:
    def test_creates_a_user(self, client):
        response = client.post(
            f"{API}/auth/register",
            json={
                "email": "new@example.com",
                "password": "GoodPassword123!",
                "full_name": "New User",
            },
        )
        assert response.status_code == 201
        assert response.json()["email"] == "new@example.com"
        assert "password" not in response.text.lower().replace(
            "hashed_password", ""
        )

    def test_rejects_a_duplicate_email(self, client, user):
        response = client.post(
            f"{API}/auth/register",
            json={
                "email": user["email"],
                "password": "GoodPassword123!",
                "full_name": "Impostor",
            },
        )
        assert response.status_code == 409

    def test_rejects_a_short_password(self, client):
        response = client.post(
            f"{API}/auth/register",
            json={
                "email": "short@example.com",
                "password": "abc",
                "full_name": "Short",
            },
        )
        assert response.status_code == 422

    def test_rejects_a_malformed_email(self, client):
        response = client.post(
            f"{API}/auth/register",
            json={
                "email": "not-an-email",
                "password": "GoodPassword123!",
                "full_name": "Nope",
            },
        )
        assert response.status_code == 422


class TestLongPasswords:
    """bcrypt raises above 72 bytes; that used to surface as a 500."""

    LONG = "L" * 120

    def test_registering_with_a_long_password_works(self, client):
        response = client.post(
            f"{API}/auth/register",
            json={
                "email": "long@example.com",
                "password": self.LONG,
                "full_name": "Long",
            },
        )
        assert response.status_code == 201

    def test_logging_in_with_a_long_password_works(self, client):
        client.post(
            f"{API}/auth/register",
            json={
                "email": "long@example.com",
                "password": self.LONG,
                "full_name": "Long",
            },
        )
        response = client.post(
            f"{API}/auth/login",
            data={"username": "long@example.com", "password": self.LONG},
        )
        assert response.status_code == 200

    def test_a_wrong_long_password_is_401_not_500(self, client):
        client.post(
            f"{API}/auth/register",
            json={
                "email": "long@example.com",
                "password": self.LONG,
                "full_name": "Long",
            },
        )
        response = client.post(
            f"{API}/auth/login",
            data={"username": "long@example.com", "password": "X" * 120},
        )
        assert response.status_code == 401


class TestLogin:
    def test_wrong_password_is_rejected(self, client, user):
        response = client.post(
            f"{API}/auth/login",
            data={"username": user["email"], "password": "wrong"},
        )
        assert response.status_code == 401

    def test_unknown_email_is_rejected(self, client):
        response = client.post(
            f"{API}/auth/login",
            data={"username": "ghost@example.com", "password": "whatever123"},
        )
        assert response.status_code == 401

    def test_returns_both_tokens(self, client, user):
        response = client.post(
            f"{API}/auth/login",
            data={"username": user["email"], "password": user["password"]},
        )
        body = response.json()
        assert body["access_token"] and body["refresh_token"]
        assert body["token_type"] == "bearer"


class TestTokenLifecycle:
    def test_a_valid_token_identifies_the_user(self, client, user):
        response = client.get(f"{API}/auth/me", headers=user["headers"])
        assert response.status_code == 200
        assert response.json()["email"] == user["email"]

    def test_no_token_is_rejected(self, client):
        assert client.get(f"{API}/auth/me").status_code == 401

    def test_a_forged_token_is_rejected(self, client):
        response = client.get(
            f"{API}/auth/me", headers={"Authorization": "Bearer not.a.token"}
        )
        assert response.status_code == 401

    def test_a_refresh_token_cannot_be_used_as_an_access_token(
        self, client, user
    ):
        response = client.get(
            f"{API}/auth/me",
            headers={"Authorization": f"Bearer {user['refresh_token']}"},
        )
        assert response.status_code == 401

    def test_refresh_issues_a_new_pair(self, client, user):
        response = client.post(
            f"{API}/auth/refresh", json={"refresh_token": user["refresh_token"]}
        )
        assert response.status_code == 200
        assert response.json()["access_token"]


class TestLogout:
    """Logout bumps the token version, killing every issued token."""

    def test_the_access_token_stops_working(self, client, user):
        assert (
            client.post(f"{API}/auth/logout", headers=user["headers"]).status_code
            == 204
        )
        assert client.get(f"{API}/auth/me", headers=user["headers"]).status_code == 401

    def test_the_refresh_token_stops_working_too(self, client, user):
        client.post(f"{API}/auth/logout", headers=user["headers"])
        response = client.post(
            f"{API}/auth/refresh", json={"refresh_token": user["refresh_token"]}
        )
        # Without revocation a stolen refresh token stayed good for 7 days.
        assert response.status_code == 401

    def test_signing_back_in_works(self, client, user):
        client.post(f"{API}/auth/logout", headers=user["headers"])
        response = client.post(
            f"{API}/auth/login",
            data={"username": user["email"], "password": user["password"]},
        )
        assert response.status_code == 200
        fresh = {"Authorization": f"Bearer {response.json()['access_token']}"}
        assert client.get(f"{API}/auth/me", headers=fresh).status_code == 200

    def test_logging_out_does_not_affect_another_user(self, client, make_user):
        alice = make_user()
        bob = make_user()
        client.post(f"{API}/auth/logout", headers=alice["headers"])
        assert client.get(f"{API}/auth/me", headers=bob["headers"]).status_code == 200


class TestTenantIsolation:
    """Every resource fetch is scoped to the owner."""

    @pytest.fixture
    def other_users_account(self, client, make_user):
        stranger = make_user()
        account = client.post(
            f"{API}/accounts/",
            headers=stranger["headers"],
            json={
                "name": "Private",
                "account_type": "bank",
                "current_balance": "9999.00",
            },
        ).json()
        return account

    def test_listing_shows_only_your_own(
        self, client, auth, make_account, other_users_account
    ):
        make_account(name="Mine")
        listed = client.get(f"{API}/accounts/", headers=auth).json()
        assert [a["name"] for a in listed] == ["Mine"]

    def test_reading_someone_elses_is_404(
        self, client, auth, other_users_account
    ):
        response = client.get(
            f"{API}/accounts/{other_users_account['id']}", headers=auth
        )
        assert response.status_code == 404

    def test_deleting_someone_elses_is_404(
        self, client, auth, other_users_account
    ):
        response = client.delete(
            f"{API}/accounts/{other_users_account['id']}", headers=auth
        )
        assert response.status_code == 404

    def test_updating_someone_elses_is_404(
        self, client, auth, other_users_account
    ):
        response = client.patch(
            f"{API}/accounts/{other_users_account['id']}",
            headers=auth,
            json={"name": "Hijacked"},
        )
        assert response.status_code == 404

    def test_cannot_spend_from_someone_elses_account(
        self, client, auth, other_users_account
    ):
        response = client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "expense",
                "amount": "10.00",
                "category": "Theft",
                "account_id": other_users_account["id"],
            },
        )
        assert response.status_code == 404


class TestErrorContract:
    def test_errors_carry_a_request_id(self, client):
        body = client.get(f"{API}/auth/me").json()
        assert "detail" in body and "request_id" in body

    def test_responses_echo_the_request_id_header(self, client):
        response = client.get(f"{API}/auth/me")
        assert response.headers.get("x-request-id")

    def test_a_supplied_request_id_is_preserved(self, client):
        response = client.get(
            f"{API}/auth/me", headers={"X-Request-ID": "trace-me-123"}
        )
        assert response.headers["x-request-id"] == "trace-me-123"
