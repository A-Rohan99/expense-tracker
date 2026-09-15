"""
The paths that move money.

These are the regression net for the defects found during the readiness
review: float precision destroying balances, double EMI payment, and
credit-card amounts reported as zero.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest

API = "/api/v1"


def balance_of(client, auth, account_id) -> Decimal:
    response = client.get(f"{API}/accounts/{account_id}", headers=auth)
    assert response.status_code == 200, response.text
    return Decimal(response.json()["current_balance"])


class TestDecimalPrecision:
    """A float round-trip loses paise; a Decimal one does not."""

    def test_many_awkward_credits_stay_exact(self, client, auth, make_account):
        account = make_account(balance="1000.00")

        # 0.07 is not representable in binary floating point: adding it 100
        # times to 1000.0 gives 1007.000000000005.
        for _ in range(100):
            response = client.post(
                f"{API}/transactions/",
                headers=auth,
                json={
                    "transaction_type": "income",
                    "amount": "0.07",
                    "category": "Drift",
                    "account_id": account["id"],
                },
            )
            assert response.status_code == 201, response.text

        assert balance_of(client, auth, account["id"]) == Decimal("1007.00")

    def test_mixed_debits_and_credits_stay_exact(
        self, client, auth, make_account
    ):
        account = make_account(balance="1000.00")
        movements = [
            ("income", "0.10"),
            ("income", "0.20"),
            ("expense", "0.30"),  # 0.1 + 0.2 != 0.3 in float
            ("income", "1234.56"),
            ("expense", "999.99"),
            ("income", "0.01"),
            ("expense", "0.03"),
        ]
        expected = Decimal("1000.00")
        for kind, amount in movements:
            response = client.post(
                f"{API}/transactions/",
                headers=auth,
                json={
                    "transaction_type": kind,
                    "amount": amount,
                    "category": "Mixed",
                    "account_id": account["id"],
                },
            )
            assert response.status_code == 201, response.text
            expected += Decimal(amount) if kind == "income" else -Decimal(amount)

        assert balance_of(client, auth, account["id"]) == expected

    def test_sub_paise_precision_is_rejected_not_silently_rounded(
        self, client, auth, make_account
    ):
        account = make_account(balance="1000.00")
        response = client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "income",
                "amount": "2.675",
                "category": "Too precise",
                "account_id": account["id"],
            },
        )
        assert response.status_code == 422
        assert balance_of(client, auth, account["id"]) == Decimal("1000.00")

    def test_stored_amounts_never_exceed_two_decimal_places(
        self, client, auth, make_account
    ):
        account = make_account(balance="500.00")
        for amount in ("0.01", "33.33", "66.67"):
            client.post(
                f"{API}/transactions/",
                headers=auth,
                json={
                    "transaction_type": "expense",
                    "amount": amount,
                    "category": "Thirds",
                    "account_id": account["id"],
                },
            )
        rows = client.get(f"{API}/transactions/", headers=auth).json()
        assert all(
            Decimal(row["amount"]).as_tuple().exponent >= -2 for row in rows
        )


class TestBalanceRules:
    def test_income_credits_and_expense_debits(self, client, auth, make_account):
        account = make_account(balance="1000.00")
        client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "income",
                "amount": "500.00",
                "category": "Salary",
                "account_id": account["id"],
            },
        )
        assert balance_of(client, auth, account["id"]) == Decimal("1500.00")

        client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "expense",
                "amount": "200.00",
                "category": "Food",
                "account_id": account["id"],
            },
        )
        assert balance_of(client, auth, account["id"]) == Decimal("1300.00")

    def test_overdrawing_is_rejected_and_leaves_the_balance_alone(
        self, client, auth, make_account
    ):
        account = make_account(balance="100.00")
        response = client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "expense",
                "amount": "100.01",
                "category": "Too much",
                "account_id": account["id"],
            },
        )
        assert response.status_code == 400
        assert balance_of(client, auth, account["id"]) == Decimal("100.00")

    def test_spending_exactly_the_balance_is_allowed(
        self, client, auth, make_account
    ):
        account = make_account(balance="100.00")
        response = client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "expense",
                "amount": "100.00",
                "category": "All of it",
                "account_id": account["id"],
            },
        )
        assert response.status_code == 201
        assert balance_of(client, auth, account["id"]) == Decimal("0.00")

    def test_a_card_expense_does_not_touch_any_account(
        self, client, auth, make_account
    ):
        account = make_account(balance="1000.00")
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

        client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "expense",
                "amount": "750.00",
                "category": "Travel",
                "credit_card_id": card["id"],
            },
        )
        assert balance_of(client, auth, account["id"]) == Decimal("1000.00")

    def test_deleting_a_transaction_reverses_its_effect(
        self, client, auth, make_account
    ):
        account = make_account(balance="1000.00")
        txn = client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "expense",
                "amount": "250.00",
                "category": "Oops",
                "account_id": account["id"],
            },
        ).json()
        assert balance_of(client, auth, account["id"]) == Decimal("750.00")

        assert (
            client.delete(
                f"{API}/transactions/{txn['id']}", headers=auth
            ).status_code
            == 204
        )
        assert balance_of(client, auth, account["id"]) == Decimal("1000.00")


class TestTransferRules:
    def test_a_transfer_needs_a_destination(self, client, auth, make_account):
        account = make_account(balance="1000.00")
        response = client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "transfer",
                "amount": "100.00",
                "category": "Nowhere",
                "account_id": account["id"],
            },
        )
        assert response.status_code == 422

    def test_paying_a_card_bill_debits_the_account_and_restores_the_limit(
        self, client, auth, make_account
    ):
        account = make_account(balance="50000.00")
        card = client.post(
            f"{API}/credit-cards/",
            headers=auth,
            json={
                "name": "Card",
                "total_limit": "100000",
                "statement_day": 5,
                "due_day": 25,
            },
        ).json()

        client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "expense",
                "amount": "15000.00",
                "category": "Travel",
                "credit_card_id": card["id"],
            },
        )
        summary = client.get(
            f"{API}/credit-cards/{card['id']}/summary", headers=auth
        ).json()
        assert Decimal(summary["available_limit"]) == Decimal("85000.00")

        client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "transfer",
                "amount": "15000.00",
                "category": "Credit Card Bill",
                "account_id": account["id"],
                "credit_card_id": card["id"],
            },
        )
        assert balance_of(client, auth, account["id"]) == Decimal("35000.00")
        summary = client.get(
            f"{API}/credit-cards/{card['id']}/summary", headers=auth
        ).json()
        assert Decimal(summary["available_limit"]) == Decimal("100000.00")


class TestCreditCardDerivedAmounts:
    """List and detail used to report 0.00 for every card."""

    def test_list_reports_real_amounts(self, client, auth):
        card = client.post(
            f"{API}/credit-cards/",
            headers=auth,
            json={
                "name": "Card",
                "total_limit": "200000",
                "statement_day": 5,
                "due_day": 25,
            },
        ).json()
        client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "expense",
                "amount": "15000.00",
                "category": "Travel",
                "credit_card_id": card["id"],
            },
        )

        listed = client.get(f"{API}/credit-cards/", headers=auth).json()[0]
        assert Decimal(listed["available_limit"]) == Decimal("185000.00")

    def test_list_detail_and_summary_all_agree(self, client, auth):
        card = client.post(
            f"{API}/credit-cards/",
            headers=auth,
            json={
                "name": "Card",
                "total_limit": "200000",
                "statement_day": 5,
                "due_day": 25,
            },
        ).json()
        client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "expense",
                "amount": "1234.56",
                "category": "Travel",
                "credit_card_id": card["id"],
            },
        )

        listed = client.get(f"{API}/credit-cards/", headers=auth).json()[0]
        detail = client.get(
            f"{API}/credit-cards/{card['id']}", headers=auth
        ).json()
        summary = client.get(
            f"{API}/credit-cards/{card['id']}/summary", headers=auth
        ).json()

        for field in ("available_limit", "billed_amount", "unbilled_amount"):
            assert listed[field] == detail[field] == summary[field], field

    def test_a_fresh_card_has_its_whole_limit(self, client, auth):
        card = client.post(
            f"{API}/credit-cards/",
            headers=auth,
            json={
                "name": "Unused",
                "total_limit": "75000",
                "statement_day": 1,
                "due_day": 20,
            },
        ).json()
        listed = client.get(f"{API}/credit-cards/", headers=auth).json()[0]
        assert Decimal(listed["available_limit"]) == Decimal("75000.00")
        assert card["id"] == listed["id"]


class TestEmiPayment:
    @pytest.fixture
    def loan(self, client, auth):
        return client.post(
            f"{API}/loans/",
            headers=auth,
            json={
                "name": "Car Loan",
                "loan_type": "auto",
                "principal_amount": "500000",
                "interest_rate": "9.5",
                "tenure_months": 60,
                "outstanding_balance": "500000",
                "start_date": str(date.today()),
            },
        ).json()

    def test_paying_debits_the_account_and_reduces_the_principal(
        self, client, auth, make_account, loan
    ):
        account = make_account(balance="100000.00")
        response = client.post(
            f"{API}/loans/{loan['id']}/pay-emi",
            headers=auth,
            json={"account_id": account["id"]},
        )
        assert response.status_code == 200, response.text
        payment = response.json()

        assert (
            Decimal(payment["principal_component"])
            + Decimal(payment["interest_component"])
            == Decimal(payment["emi_amount"])
        )
        assert balance_of(client, auth, account["id"]) == Decimal(
            "100000.00"
        ) - Decimal(payment["emi_amount"])

        after = client.get(f"{API}/loans/{loan['id']}", headers=auth).json()
        assert Decimal(after["outstanding_balance"]) == Decimal(
            "500000.00"
        ) - Decimal(payment["principal_component"])

    def test_a_second_payment_in_the_same_month_is_refused(
        self, client, auth, make_account, loan
    ):
        account = make_account(balance="100000.00")
        first = client.post(
            f"{API}/loans/{loan['id']}/pay-emi",
            headers=auth,
            json={"account_id": account["id"]},
        )
        assert first.status_code == 200
        after_first = balance_of(client, auth, account["id"])

        second = client.post(
            f"{API}/loans/{loan['id']}/pay-emi",
            headers=auth,
            json={"account_id": account["id"]},
        )
        assert second.status_code == 409
        # The money must not move twice.
        assert balance_of(client, auth, account["id"]) == after_first

    def test_the_loan_reports_that_it_has_been_paid(
        self, client, auth, make_account, loan
    ):
        account = make_account(balance="100000.00")
        before = client.get(f"{API}/loans/{loan['id']}", headers=auth).json()
        assert before["emi_paid_this_month"] is False
        assert before["last_emi_payment_date"] is None

        client.post(
            f"{API}/loans/{loan['id']}/pay-emi",
            headers=auth,
            json={"account_id": account["id"]},
        )

        after = client.get(f"{API}/loans/{loan['id']}", headers=auth).json()
        assert after["emi_paid_this_month"] is True
        assert after["last_emi_payment_date"] == str(date.today())

    def test_an_ad_hoc_prepayment_does_not_count_as_the_emi(
        self, client, auth, make_account, loan
    ):
        """A voluntary extra payment shouldn't block the month's instalment."""
        account = make_account(balance="100000.00")
        client.post(
            f"{API}/transactions/",
            headers=auth,
            json={
                "transaction_type": "transfer",
                "amount": "5000.00",
                "category": "Loan prepayment",
                "account_id": account["id"],
                "loan_id": loan["id"],
            },
        )

        state = client.get(f"{API}/loans/{loan['id']}", headers=auth).json()
        assert state["emi_paid_this_month"] is False

        response = client.post(
            f"{API}/loans/{loan['id']}/pay-emi",
            headers=auth,
            json={"account_id": account["id"]},
        )
        assert response.status_code == 200

    def test_paying_from_an_account_without_the_funds_is_refused(
        self, client, auth, make_account, loan
    ):
        account = make_account(name="Nearly empty", balance="100.00")
        response = client.post(
            f"{API}/loans/{loan['id']}/pay-emi",
            headers=auth,
            json={"account_id": account["id"]},
        )
        assert response.status_code == 400
        assert balance_of(client, auth, account["id"]) == Decimal("100.00")
