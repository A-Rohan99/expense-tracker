"""
Standing monthly income.

The catch-up posts months that fell due while the app was closed, so the
interesting cases are all about *time*: dates are injected rather than waiting
for the calendar.
"""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

import pytest

from app.models import Account, RecurringIncome, Transaction, User
from app.services.recurring import (
    due_date_for,
    initial_last_posted,
    period_key,
    run_catch_up,
)

API = "/api/v1"


# ---------------------------------------------------------------------------
# Pure date logic
# ---------------------------------------------------------------------------

class TestDateLogic:
    def test_period_key_is_zero_padded(self):
        assert period_key(date(2026, 3, 9)) == "2026-03"

    @pytest.mark.parametrize(
        "day,period,expected",
        [
            (31, date(2026, 1, 1), date(2026, 1, 31)),
            (31, date(2026, 2, 1), date(2026, 2, 28)),  # clamps
            (31, date(2028, 2, 1), date(2028, 2, 29)),  # leap year
            (30, date(2026, 2, 1), date(2026, 2, 28)),
            (1, date(2026, 2, 1), date(2026, 2, 1)),
        ],
    )
    def test_pay_day_clamps_to_short_months(self, day, period, expected):
        assert due_date_for(period, day) == expected

    def test_setting_up_after_pay_day_does_not_back_post(self):
        # Paid on the 1st, set up on the 15th: the user was already paid, and
        # may have recorded it by hand. Posting now would double-count.
        assert initial_last_posted(1, today=date(2026, 9, 15)) == "2026-09"

    def test_setting_up_before_pay_day_leaves_the_month_to_post(self):
        assert initial_last_posted(25, today=date(2026, 9, 15)) is None

    def test_setting_up_on_pay_day_still_posts_today(self):
        assert initial_last_posted(15, today=date(2026, 9, 15)) is None


# ---------------------------------------------------------------------------
# Catch-up posting
# ---------------------------------------------------------------------------

@pytest.fixture
def instruction(db_session):
    """A user with an account and a standing instruction, created in Jan 2026."""

    def _make(day_of_month: int = 1, balance="0.00", created=date(2026, 1, 1)):
        user = User(
            email=f"recur_{day_of_month}_{created}@example.com",
            hashed_password="x",
            full_name="Recur",
        )
        db_session.add(user)
        db_session.flush()

        account = Account(
            user_id=user.id,
            name="Bank",
            account_type="bank",
            current_balance=Decimal(balance),
        )
        db_session.add(account)
        db_session.flush()

        income = RecurringIncome(
            user_id=user.id,
            account_id=account.id,
            name="Salary",
            amount=Decimal("50000.00"),
            day_of_month=day_of_month,
            category="Salary",
            created_at=datetime(created.year, created.month, created.day),
        )
        db_session.add(income)
        db_session.commit()
        return account, income

    return _make


class TestCatchUp:
    def test_a_due_month_posts_once_and_credits_the_account(
        self, db_session, instruction
    ):
        account, income = instruction(day_of_month=5, created=date(2026, 3, 1))
        posted = run_catch_up(db_session, income, today=date(2026, 3, 10))

        assert len(posted) == 1
        assert posted[0].transaction_date == date(2026, 3, 5)
        assert posted[0].transaction_type == "income"
        assert Decimal(str(account.current_balance)) == Decimal("50000.00")
        assert income.last_posted_period == "2026-03"

    def test_running_again_posts_nothing(self, db_session, instruction):
        account, income = instruction(day_of_month=5, created=date(2026, 3, 1))
        run_catch_up(db_session, income, today=date(2026, 3, 10))
        again = run_catch_up(db_session, income, today=date(2026, 3, 10))

        assert again == []
        assert Decimal(str(account.current_balance)) == Decimal("50000.00")

    def test_nothing_posts_before_the_pay_day(self, db_session, instruction):
        account, income = instruction(day_of_month=25, created=date(2026, 3, 1))
        assert run_catch_up(db_session, income, today=date(2026, 3, 10)) == []
        assert Decimal(str(account.current_balance)) == Decimal("0.00")

    def test_months_missed_while_closed_all_post(self, db_session, instruction):
        account, income = instruction(day_of_month=1, created=date(2026, 1, 1))
        posted = run_catch_up(db_session, income, today=date(2026, 4, 3))

        assert [t.transaction_date for t in posted] == [
            date(2026, 1, 1),
            date(2026, 2, 1),
            date(2026, 3, 1),
            date(2026, 4, 1),
        ]
        assert Decimal(str(account.current_balance)) == Decimal("200000.00")
        assert income.last_posted_period == "2026-04"

    def test_a_31st_instruction_pays_on_the_last_day_of_short_months(
        self, db_session, instruction
    ):
        _, income = instruction(day_of_month=31, created=date(2026, 1, 1))
        posted = run_catch_up(db_session, income, today=date(2026, 3, 31))

        assert [t.transaction_date for t in posted] == [
            date(2026, 1, 31),
            date(2026, 2, 28),
            date(2026, 3, 31),
        ]

    def test_a_paused_instruction_posts_nothing(self, db_session, instruction):
        account, income = instruction(day_of_month=5, created=date(2026, 3, 1))
        income.is_active = False
        db_session.commit()

        assert run_catch_up(db_session, income, today=date(2026, 6, 10)) == []
        assert Decimal(str(account.current_balance)) == Decimal("0.00")

    def test_catch_up_is_capped(self, db_session, instruction):
        """A long-dormant instruction must not flood the ledger."""
        _, income = instruction(day_of_month=1, created=date(2020, 1, 1))
        posted = run_catch_up(db_session, income, today=date(2026, 9, 15))
        assert len(posted) == 24

    def test_an_inactive_destination_stops_posting(
        self, db_session, instruction
    ):
        account, income = instruction(day_of_month=5, created=date(2026, 3, 1))
        account.is_active = False
        db_session.commit()

        assert run_catch_up(db_session, income, today=date(2026, 3, 10)) == []

    def test_posted_rows_reach_the_ledger(self, db_session, instruction):
        account, income = instruction(
            day_of_month=10, balance="1000.00", created=date(2026, 5, 1)
        )
        run_catch_up(db_session, income, today=date(2026, 7, 15))

        rows = (
            db_session.query(Transaction)
            .filter(Transaction.user_id == income.user_id)
            .all()
        )
        assert len(rows) == 3
        assert all("(automatic)" in (r.description or "") for r in rows)
        assert Decimal(str(account.current_balance)) == Decimal("151000.00")


# ---------------------------------------------------------------------------
# HTTP surface
# ---------------------------------------------------------------------------

class TestEndpoints:
    def test_returns_null_when_nothing_is_set_up(self, client, auth):
        response = client.get(f"{API}/recurring-income/", headers=auth)
        assert response.status_code == 200
        assert response.json() is None

    def test_create_then_read(self, client, auth, make_account):
        account = make_account()
        created = client.post(
            f"{API}/recurring-income/",
            headers=auth,
            json={
                "account_id": account["id"],
                "amount": "185000.00",
                "day_of_month": 25,
                "name": "Salary",
            },
        )
        assert created.status_code == 201
        body = created.json()
        assert body["day_of_month"] == 25
        assert body["account_name"] == account["name"]
        assert body["next_due_date"] is not None

    def test_only_one_instruction_per_user(self, client, auth, make_account):
        account = make_account()
        payload = {
            "account_id": account["id"],
            "amount": "1000.00",
            "day_of_month": 5,
        }
        assert (
            client.post(
                f"{API}/recurring-income/", headers=auth, json=payload
            ).status_code
            == 201
        )
        assert (
            client.post(
                f"{API}/recurring-income/", headers=auth, json=payload
            ).status_code
            == 409
        )

    def test_cannot_target_another_users_account(
        self, client, auth, make_user
    ):
        stranger = make_user()
        their_account = client.post(
            f"{API}/accounts/",
            headers=stranger["headers"],
            json={"name": "Theirs", "account_type": "bank"},
        ).json()

        response = client.post(
            f"{API}/recurring-income/",
            headers=auth,
            json={
                "account_id": their_account["id"],
                "amount": "500.00",
                "day_of_month": 5,
            },
        )
        assert response.status_code == 404

    def test_get_does_not_post_but_catch_up_does(
        self, client, auth, make_account
    ):
        """A GET must not mutate the ledger."""
        account = make_account()
        client.post(
            f"{API}/recurring-income/",
            headers=auth,
            json={
                "account_id": account["id"],
                "amount": "1000.00",
                "day_of_month": 5,
            },
        )
        read = client.get(f"{API}/recurring-income/", headers=auth).json()
        assert read["posted_this_run"] == 0

        caught_up = client.post(
            f"{API}/recurring-income/catch-up", headers=auth
        )
        assert caught_up.status_code == 200

    def test_delete_removes_it(self, client, auth, make_account):
        account = make_account()
        client.post(
            f"{API}/recurring-income/",
            headers=auth,
            json={
                "account_id": account["id"],
                "amount": "1000.00",
                "day_of_month": 5,
            },
        )
        assert (
            client.delete(f"{API}/recurring-income/", headers=auth).status_code
            == 204
        )
        assert client.get(f"{API}/recurring-income/", headers=auth).json() is None

    @pytest.mark.parametrize("day", [0, 32, -1])
    def test_an_impossible_pay_day_is_rejected(
        self, client, auth, make_account, day
    ):
        account = make_account()
        response = client.post(
            f"{API}/recurring-income/",
            headers=auth,
            json={
                "account_id": account["id"],
                "amount": "1000.00",
                "day_of_month": day,
            },
        )
        assert response.status_code == 422
