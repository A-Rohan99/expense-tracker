"""
Tests for app/services/finance.py.

Pure, deterministic, dependency-free code — EMI amortisation and billing-cycle
date maths with month-length and leap-year edge cases. It is the most
correctness-critical file in the project and had no tests at all. Its
docstrings even carried doctests that nothing executed.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest

from app.services.finance import (
    calculate_emi,
    calculate_emi_breakdown,
    clamp_day,
    generate_amortisation_schedule,
    get_statement_cycle,
    shift_month,
)


class TestClampDay:
    def test_keeps_a_valid_day(self):
        assert clamp_day(2026, 1, 15) == date(2026, 1, 15)

    def test_clamps_to_the_last_day_of_a_short_month(self):
        assert clamp_day(2026, 2, 31) == date(2026, 2, 28)
        assert clamp_day(2026, 4, 31) == date(2026, 4, 30)

    def test_handles_leap_february(self):
        assert clamp_day(2028, 2, 31) == date(2028, 2, 29)
        assert clamp_day(2028, 2, 29) == date(2028, 2, 29)

    def test_century_years_are_not_leap_unless_divisible_by_400(self):
        assert clamp_day(2100, 2, 29) == date(2100, 2, 28)
        assert clamp_day(2000, 2, 29) == date(2000, 2, 29)


class TestShiftMonth:
    def test_forward_and_back(self):
        assert shift_month(date(2026, 3, 15), 1) == date(2026, 4, 15)
        assert shift_month(date(2026, 3, 15), -1) == date(2026, 2, 15)

    def test_clamps_the_day_when_the_target_month_is_shorter(self):
        assert shift_month(date(2026, 1, 31), 1) == date(2026, 2, 28)
        assert shift_month(date(2026, 3, 31), -1) == date(2026, 2, 28)

    def test_crosses_a_year_boundary(self):
        assert shift_month(date(2026, 12, 10), 1) == date(2027, 1, 10)
        assert shift_month(date(2026, 1, 10), -1) == date(2025, 12, 10)

    def test_multi_month_shifts(self):
        assert shift_month(date(2026, 1, 15), 12) == date(2027, 1, 15)
        assert shift_month(date(2026, 1, 15), -14) == date(2024, 11, 15)

    def test_zero_is_identity(self):
        assert shift_month(date(2026, 6, 9), 0) == date(2026, 6, 9)


class TestCalculateEmi:
    def test_matches_the_standard_amortisation_formula(self):
        # 5,00,000 at 9.5% for 60 months. Cross-checked against the closed-form
        # E = P*r*(1+r)^n / ((1+r)^n - 1).
        result = calculate_emi(
            principal=Decimal("500000"),
            annual_rate=Decimal("9.5"),
            tenure_months=60,
        )
        assert result["emi"] == Decimal("10500.93")
        assert result["principal"] == Decimal("500000.00")
        assert result["total_payment"] == Decimal("630055.80")
        assert result["total_interest"] == Decimal("130055.80")

    def test_total_payment_and_interest_reconcile(self):
        result = calculate_emi(
            principal=Decimal("250000"),
            annual_rate=Decimal("7.25"),
            tenure_months=36,
        )
        assert (
            result["total_interest"]
            == result["total_payment"] - result["principal"]
        )

    def test_zero_interest_splits_the_principal_evenly(self):
        result = calculate_emi(
            principal=Decimal("120000"),
            annual_rate=Decimal("0"),
            tenure_months=12,
        )
        assert result["emi"] == Decimal("10000.00")
        assert result["total_interest"] == Decimal("0.00")

    def test_results_are_decimal_not_float(self):
        result = calculate_emi(
            principal=Decimal("100000"),
            annual_rate=Decimal("8"),
            tenure_months=24,
        )
        assert all(isinstance(v, Decimal) for v in result.values())

    def test_quantised_to_paise(self):
        result = calculate_emi(
            principal=Decimal("333333"),
            annual_rate=Decimal("11.11"),
            tenure_months=17,
        )
        assert result["emi"].as_tuple().exponent == -2


class TestEmiBreakdown:
    def test_principal_and_interest_sum_to_the_emi(self):
        breakdown = calculate_emi_breakdown(
            outstanding=Decimal("500000"),
            annual_rate=Decimal("9.5"),
            emi=Decimal("10500.93"),
        )
        assert (
            breakdown["principal_component"] + breakdown["interest_component"]
            == Decimal("10500.93")
        )

    def test_interest_is_charged_on_the_outstanding_balance(self):
        # One month at 9.5%/12 on 5,00,000 = 3958.33.
        breakdown = calculate_emi_breakdown(
            outstanding=Decimal("500000"),
            annual_rate=Decimal("9.5"),
            emi=Decimal("10500.93"),
        )
        assert breakdown["interest_component"] == Decimal("3958.33")
        assert breakdown["principal_component"] == Decimal("6542.60")

    def test_outstanding_falls_by_the_principal_component(self):
        breakdown = calculate_emi_breakdown(
            outstanding=Decimal("500000"),
            annual_rate=Decimal("9.5"),
            emi=Decimal("10500.93"),
        )
        assert breakdown["new_outstanding"] == Decimal("500000") - breakdown[
            "principal_component"
        ]

    def test_interest_shrinks_as_the_balance_does(self):
        big = calculate_emi_breakdown(
            outstanding=Decimal("500000"),
            annual_rate=Decimal("9.5"),
            emi=Decimal("10500.93"),
        )
        small = calculate_emi_breakdown(
            outstanding=Decimal("50000"),
            annual_rate=Decimal("9.5"),
            emi=Decimal("10500.93"),
        )
        assert small["interest_component"] < big["interest_component"]

    def test_final_instalment_cannot_drive_the_balance_negative(self):
        breakdown = calculate_emi_breakdown(
            outstanding=Decimal("1000"),
            annual_rate=Decimal("9.5"),
            emi=Decimal("10500.93"),
        )
        assert breakdown["new_outstanding"] >= Decimal("0")


class TestAmortisationSchedule:
    def test_one_row_per_month(self):
        rows = generate_amortisation_schedule(
            principal=Decimal("500000"),
            annual_rate=Decimal("9.5"),
            tenure_months=60,
        )
        assert len(rows) == 60
        assert [r["month"] for r in rows] == list(range(1, 61))

    def test_the_loan_is_fully_repaid_by_the_last_row(self):
        rows = generate_amortisation_schedule(
            principal=Decimal("500000"),
            annual_rate=Decimal("9.5"),
            tenure_months=60,
        )
        assert rows[-1]["closing_balance"] <= Decimal("0.01")

    def test_each_row_closes_where_the_next_one_opens(self):
        rows = generate_amortisation_schedule(
            principal=Decimal("200000"),
            annual_rate=Decimal("8"),
            tenure_months=24,
        )
        for previous, following in zip(rows, rows[1:]):
            assert previous["closing_balance"] == following["opening_balance"]

    def test_principal_repaid_equals_the_loan(self):
        principal = Decimal("200000")
        rows = generate_amortisation_schedule(
            principal=principal, annual_rate=Decimal("8"), tenure_months=24
        )
        total_principal = sum(r["principal"] for r in rows)
        # Rounding each month can drift by at most a paisa per row.
        assert abs(total_principal - principal) < Decimal("0.25")

    def test_principal_share_grows_over_the_life_of_the_loan(self):
        rows = generate_amortisation_schedule(
            principal=Decimal("500000"),
            annual_rate=Decimal("9.5"),
            tenure_months=60,
        )
        assert rows[0]["principal"] < rows[-1]["principal"]
        assert rows[0]["interest"] > rows[-1]["interest"]


class TestStatementCycle:
    def test_returns_the_expected_keys(self):
        cycle = get_statement_cycle(statement_day=5, due_day=25)
        assert {
            "last_statement_date",
            "next_statement_date",
            "due_date",
            "days_until_due",
        } <= set(cycle)

    def test_the_next_statement_follows_the_last(self):
        cycle = get_statement_cycle(statement_day=5, due_day=25)
        assert cycle["next_statement_date"] > cycle["last_statement_date"]

    @pytest.mark.parametrize("statement_day", [1, 5, 15, 28, 29, 30, 31])
    def test_survives_every_statement_day_including_short_months(
        self, statement_day
    ):
        # A day past 28 must clamp rather than raise.
        cycle = get_statement_cycle(statement_day=statement_day, due_day=20)
        assert isinstance(cycle["last_statement_date"], date)
        assert isinstance(cycle["due_date"], date)

    def test_days_until_due_agrees_with_the_due_date(self):
        cycle = get_statement_cycle(statement_day=5, due_day=25)
        expected = (cycle["due_date"] - date.today()).days
        assert cycle["days_until_due"] == expected
