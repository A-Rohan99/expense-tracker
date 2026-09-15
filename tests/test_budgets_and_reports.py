"""Budgets and monthly reporting."""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest

API = "/api/v1"


def spend(client, auth, account_id, amount, category, on: date | None = None):
    body = {
        "transaction_type": "expense",
        "amount": str(amount),
        "category": category,
        "account_id": account_id,
    }
    if on:
        body["transaction_date"] = str(on)
    response = client.post(f"{API}/transactions/", headers=auth, json=body)
    assert response.status_code == 201, response.text
    return response.json()


def earn(client, auth, account_id, amount, category="Salary", on: date | None = None):
    body = {
        "transaction_type": "income",
        "amount": str(amount),
        "category": category,
        "account_id": account_id,
    }
    if on:
        body["transaction_date"] = str(on)
    response = client.post(f"{API}/transactions/", headers=auth, json=body)
    assert response.status_code == 201, response.text
    return response.json()


class TestBudgetCrud:
    def test_creating_an_overall_budget(self, client, auth):
        response = client.post(
            f"{API}/budgets/", headers=auth, json={"amount": "50000.00"}
        )
        assert response.status_code == 201
        body = response.json()
        assert body["category"] is None
        assert Decimal(body["amount"]) == Decimal("50000.00")

    def test_creating_a_category_budget(self, client, auth):
        response = client.post(
            f"{API}/budgets/",
            headers=auth,
            json={"amount": "8000.00", "category": "Groceries"},
        )
        assert response.status_code == 201
        assert response.json()["category"] == "Groceries"

    def test_only_one_overall_budget(self, client, auth):
        client.post(f"{API}/budgets/", headers=auth, json={"amount": "50000"})
        again = client.post(
            f"{API}/budgets/", headers=auth, json={"amount": "60000"}
        )
        assert again.status_code == 409

    def test_only_one_budget_per_category(self, client, auth):
        payload = {"amount": "8000", "category": "Groceries"}
        client.post(f"{API}/budgets/", headers=auth, json=payload)
        assert (
            client.post(f"{API}/budgets/", headers=auth, json=payload).status_code
            == 409
        )

    def test_an_overall_and_a_category_budget_coexist(self, client, auth):
        assert (
            client.post(
                f"{API}/budgets/", headers=auth, json={"amount": "50000"}
            ).status_code
            == 201
        )
        assert (
            client.post(
                f"{API}/budgets/",
                headers=auth,
                json={"amount": "8000", "category": "Groceries"},
            ).status_code
            == 201
        )
        assert len(client.get(f"{API}/budgets/", headers=auth).json()) == 2

    def test_updating_the_cap(self, client, auth):
        budget = client.post(
            f"{API}/budgets/", headers=auth, json={"amount": "50000"}
        ).json()
        response = client.patch(
            f"{API}/budgets/{budget['id']}", headers=auth, json={"amount": "75000"}
        )
        assert Decimal(response.json()["amount"]) == Decimal("75000.00")

    def test_deleting(self, client, auth):
        budget = client.post(
            f"{API}/budgets/", headers=auth, json={"amount": "50000"}
        ).json()
        assert (
            client.delete(f"{API}/budgets/{budget['id']}", headers=auth).status_code
            == 204
        )
        assert client.get(f"{API}/budgets/", headers=auth).json() == []

    def test_a_zero_or_negative_cap_is_rejected(self, client, auth):
        for amount in ("0", "-100"):
            response = client.post(
                f"{API}/budgets/", headers=auth, json={"amount": amount}
            )
            assert response.status_code == 422, amount

    def test_another_users_budget_is_invisible(self, client, auth, make_user):
        stranger = make_user()
        client.post(
            f"{API}/budgets/",
            headers=stranger["headers"],
            json={"amount": "99999"},
        )
        assert client.get(f"{API}/budgets/", headers=auth).json() == []


class TestBudgetSpend:
    """Spend is derived from the ledger, never stored."""

    def test_a_fresh_budget_has_nothing_spent(self, client, auth):
        budget = client.post(
            f"{API}/budgets/", headers=auth, json={"amount": "10000"}
        ).json()
        assert Decimal(budget["spent"]) == Decimal("0.00")
        assert Decimal(budget["remaining"]) == Decimal("10000.00")
        assert Decimal(budget["percent_used"]) == Decimal("0.00")

    def test_spending_counts_against_the_overall_budget(
        self, client, auth, make_account
    ):
        account = make_account(balance="50000")
        client.post(f"{API}/budgets/", headers=auth, json={"amount": "10000"})
        spend(client, auth, account["id"], "2500.00", "Groceries")
        spend(client, auth, account["id"], "1500.00", "Transport")

        budget = client.get(f"{API}/budgets/", headers=auth).json()[0]
        assert Decimal(budget["spent"]) == Decimal("4000.00")
        assert Decimal(budget["remaining"]) == Decimal("6000.00")
        assert Decimal(budget["percent_used"]) == Decimal("40.00")

    def test_a_category_budget_only_counts_its_own_category(
        self, client, auth, make_account
    ):
        account = make_account(balance="50000")
        client.post(
            f"{API}/budgets/",
            headers=auth,
            json={"amount": "5000", "category": "Groceries"},
        )
        spend(client, auth, account["id"], "2000.00", "Groceries")
        spend(client, auth, account["id"], "9000.00", "Travel")

        budget = client.get(f"{API}/budgets/", headers=auth).json()[0]
        assert Decimal(budget["spent"]) == Decimal("2000.00")

    def test_income_does_not_count_as_spending(
        self, client, auth, make_account
    ):
        account = make_account(balance="1000")
        client.post(f"{API}/budgets/", headers=auth, json={"amount": "10000"})
        earn(client, auth, account["id"], "25000.00")

        budget = client.get(f"{API}/budgets/", headers=auth).json()[0]
        assert Decimal(budget["spent"]) == Decimal("0.00")

    def test_overspending_reports_remaining_as_zero_not_negative(
        self, client, auth, make_account
    ):
        account = make_account(balance="50000")
        client.post(f"{API}/budgets/", headers=auth, json={"amount": "1000"})
        spend(client, auth, account["id"], "2500.00", "Groceries")

        budget = client.get(f"{API}/budgets/", headers=auth).json()[0]
        assert Decimal(budget["spent"]) == Decimal("2500.00")
        assert Decimal(budget["remaining"]) == Decimal("0.00")
        assert Decimal(budget["percent_used"]) == Decimal("250.00")

    def test_last_months_spending_does_not_count(
        self, client, auth, make_account
    ):
        account = make_account(balance="50000")
        client.post(f"{API}/budgets/", headers=auth, json={"amount": "10000"})

        today = date.today()
        last_month = date(today.year, today.month, 1)
        # Step back one day to land in the previous month.
        last_month = date.fromordinal(last_month.toordinal() - 1)
        spend(client, auth, account["id"], "7000.00", "Old", on=last_month)

        budget = client.get(f"{API}/budgets/", headers=auth).json()[0]
        assert Decimal(budget["spent"]) == Decimal("0.00")

    def test_an_explicit_period_reports_that_month(
        self, client, auth, make_account
    ):
        account = make_account(balance="50000")
        client.post(f"{API}/budgets/", headers=auth, json={"amount": "10000"})

        today = date.today()
        last_month_end = date.fromordinal(
            date(today.year, today.month, 1).toordinal() - 1
        )
        spend(client, auth, account["id"], "7000.00", "Old", on=last_month_end)

        period = f"{last_month_end.year:04d}-{last_month_end.month:02d}"
        budget = client.get(
            f"{API}/budgets/?period={period}", headers=auth
        ).json()[0]
        assert Decimal(budget["spent"]) == Decimal("7000.00")
        assert budget["period"] == period

    def test_a_malformed_period_is_rejected(self, client, auth):
        response = client.get(f"{API}/budgets/?period=nonsense", headers=auth)
        assert response.status_code == 422


class TestMonthlyReport:
    def test_totals_are_computed_server_side(self, client, auth, make_account):
        account = make_account(balance="100000")
        earn(client, auth, account["id"], "80000.00")
        spend(client, auth, account["id"], "5000.00", "Groceries")
        spend(client, auth, account["id"], "3000.00", "Transport")

        report = client.get(f"{API}/reports/monthly", headers=auth).json()
        assert Decimal(report["income"]) == Decimal("80000.00")
        assert Decimal(report["expense"]) == Decimal("8000.00")
        assert Decimal(report["net"]) == Decimal("72000.00")
        assert report["transaction_count"] == 3

    def test_totals_are_right_beyond_the_old_client_side_cap(
        self, client, auth, make_account
    ):
        """The client used to sum at most 100 rows and silently under-report."""
        account = make_account(balance="100000")
        for _ in range(120):
            spend(client, auth, account["id"], "10.00", "Micro")

        report = client.get(f"{API}/reports/monthly", headers=auth).json()
        assert Decimal(report["expense"]) == Decimal("1200.00")
        assert report["transaction_count"] == 120

    def test_category_breakdown_is_ordered_and_totals_to_100_percent(
        self, client, auth, make_account
    ):
        account = make_account(balance="100000")
        spend(client, auth, account["id"], "6000.00", "Rent")
        spend(client, auth, account["id"], "3000.00", "Groceries")
        spend(client, auth, account["id"], "1000.00", "Transport")

        report = client.get(f"{API}/reports/monthly", headers=auth).json()
        rows = report["by_category"]
        assert [r["category"] for r in rows] == ["Rent", "Groceries", "Transport"]
        assert Decimal(rows[0]["percent"]) == Decimal("60.00")
        assert sum(Decimal(r["percent"]) for r in rows) == Decimal("100.00")

    def test_transfers_are_excluded(self, client, auth, make_account):
        """Paying a card bill is not spending — the purchase already counted."""
        account = make_account(balance="100000")
        card = client.post(
            f"{API}/credit-cards/",
            headers=auth,
            json={
                "name": "Card",
                "total_limit": "50000",
                "statement_day": 5,
                "due_day": 25,
            },
        ).json()
        spend_response = client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "expense",
                "amount": "2000.00",
                "category": "Travel",
                "credit_card_id": card["id"],
            },
        )
        assert spend_response.status_code == 201
        client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "transfer",
                "amount": "2000.00",
                "category": "Credit Card Bill",
                "account_id": account["id"],
                "credit_card_id": card["id"],
            },
        )

        report = client.get(f"{API}/reports/monthly", headers=auth).json()
        assert Decimal(report["expense"]) == Decimal("2000.00")

    def test_the_trend_has_one_entry_per_month_oldest_first(
        self, client, auth
    ):
        report = client.get(
            f"{API}/reports/monthly?trend_months=6", headers=auth
        ).json()
        trend = report["trend"]
        assert len(trend) == 6
        assert trend == sorted(trend, key=lambda row: row["period"])
        assert trend[-1]["period"] == report["period"]

    @pytest.mark.parametrize("months", [0, 25])
    def test_an_out_of_range_trend_length_is_rejected(
        self, client, auth, months
    ):
        response = client.get(
            f"{API}/reports/monthly?trend_months={months}", headers=auth
        )
        assert response.status_code == 422

    def test_another_users_spending_is_not_included(
        self, client, auth, make_user, make_account
    ):
        make_account(balance="10000")
        stranger = make_user()
        their_account = client.post(
            f"{API}/accounts/",
            headers=stranger["headers"],
            json={"name": "Theirs", "account_type": "bank",
                  "current_balance": "50000"},
        ).json()
        spend(
            client, stranger["headers"], their_account["id"], "9999.00", "Theirs"
        )

        report = client.get(f"{API}/reports/monthly", headers=auth).json()
        assert Decimal(report["expense"]) == Decimal("0.00")


class TestTransactionFiltering:
    @pytest.fixture
    def seeded(self, client, auth, make_account):
        account = make_account(balance="100000")
        spend(client, auth, account["id"], "500.00", "Groceries")
        spend(client, auth, account["id"], "2500.00", "Travel")
        spend(client, auth, account["id"], "100.00", "Transport")
        earn(client, auth, account["id"], "50000.00")
        return account

    def test_filter_by_type(self, client, auth, seeded):
        rows = client.get(
            f"{API}/transactions/?transaction_type=expense", headers=auth
        ).json()
        assert len(rows) == 3
        assert all(r["transaction_type"] == "expense" for r in rows)

    def test_an_invalid_type_is_rejected_rather_than_returning_nothing(
        self, client, auth, seeded
    ):
        # This used to be an unvalidated string, so a typo returned 200 + [].
        response = client.get(
            f"{API}/transactions/?transaction_type=expenses", headers=auth
        )
        assert response.status_code == 422

    def test_search_matches_category_or_description(self, client, auth, seeded):
        rows = client.get(
            f"{API}/transactions/?search=trav", headers=auth
        ).json()
        assert len(rows) == 1
        assert rows[0]["category"] == "Travel"

    def test_filter_by_amount_range(self, client, auth, seeded):
        rows = client.get(
            f"{API}/transactions/?min_amount=200&max_amount=1000", headers=auth
        ).json()
        assert [r["category"] for r in rows] == ["Groceries"]

    def test_filter_by_account(self, client, auth, seeded, make_account):
        other = make_account(name="Other", balance="5000")
        spend(client, auth, other["id"], "42.00", "Elsewhere")

        rows = client.get(
            f"{API}/transactions/?account_id={other['id']}", headers=auth
        ).json()
        assert [r["category"] for r in rows] == ["Elsewhere"]

    def test_sort_by_amount(self, client, auth, seeded):
        rows = client.get(
            f"{API}/transactions/?transaction_type=expense&sort=amount_desc",
            headers=auth,
        ).json()
        amounts = [Decimal(r["amount"]) for r in rows]
        assert amounts == sorted(amounts, reverse=True)

    def test_an_unknown_sort_is_rejected(self, client, auth, seeded):
        response = client.get(
            f"{API}/transactions/?sort=sideways", headers=auth
        )
        assert response.status_code == 422
