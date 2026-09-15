import 'package:expense_tracker_app/models/account.dart';
import 'package:expense_tracker_app/models/credit_card.dart';
import 'package:expense_tracker_app/models/dashboard_summary.dart';
import 'package:expense_tracker_app/models/loan.dart';
import 'package:expense_tracker_app/models/transaction.dart';
import 'package:expense_tracker_app/providers/dashboard_providers.dart';
import 'package:expense_tracker_app/utils/currency_formatter.dart';
import 'package:expense_tracker_app/utils/loan_calculator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CurrencyFormatter', () {
    test('formats numbers into Indian numbering format with Rupee symbol', () {
      expect(CurrencyFormatter.format(1234), '₹1,234');
      expect(CurrencyFormatter.format(1234567), '₹12,34,567');
      expect(CurrencyFormatter.format(10000000), '₹1,00,00,000');
    });

    test('handles negative and signed values correctly', () {
      expect(CurrencyFormatter.format(-500), '-₹500');
      expect(CurrencyFormatter.format(500, showSign: true), '+₹500');
    });

    test('compact format formats lakhs and thousands', () {
      expect(CurrencyFormatter.formatCompact(150000), '₹1.5L');
      expect(CurrencyFormatter.formatCompact(25000), '₹25.0k');
      expect(CurrencyFormatter.formatCompact(10000000), '₹1.0Cr');
    });
  });

  group('Model Deserialization', () {
    test('Account.fromJson deserializes correctly', () {
      final json = {
        'id': 'acc-1',
        'user_id': 'user-1',
        'name': 'HDFC Salary',
        'account_type': 'bank',
        'current_balance': '125000.50',
        'currency': 'INR',
        'is_active': true,
        'created_at': '2026-09-01T00:00:00Z',
      };
      final account = Account.fromJson(json);
      expect(account.id, 'acc-1');
      expect(account.name, 'HDFC Salary');
      expect(account.accountType, AccountType.bank);
      expect(account.currentBalance, 125000.50);
    });

    test('CreditCard and Summary deserialization', () {
      final summaryJson = {
        'card_id': 'cc-1',
        'card_name': 'Infinia',
        'total_limit': 1000000,
        'billed_amount': 45000,
        'unbilled_amount': 15000,
        'total_outstanding': 60000,
        'available_limit': 940000,
        'total_payments': 20000,
        'min_due_amount': 2250,
        'last_statement_date': '2026-09-01',
        'next_statement_date': '2026-10-01',
        'due_date': '2026-09-20',
        'days_until_due': 9,
      };
      final summary = CreditCardSummary.fromJson(summaryJson);
      expect(summary.cardName, 'Infinia');
      expect(summary.totalOutstanding, 60000.0);
      expect(summary.availableLimit, 940000.0);
      expect(summary.daysUntilDue, 9);
    });

    test('Loan.fromJson deserializes correctly', () {
      final json = {
        'id': 'loan-1',
        'user_id': 'user-1',
        'name': 'Home Loan',
        'loan_type': 'home',
        'principal_amount': '5000000',
        'interest_rate': '8.5',
        'tenure_months': 240,
        'outstanding_balance': '4200000',
        'start_date': '2025-01-01',
        'currency': 'INR',
        'is_active': true,
        'created_at': '2025-01-01T00:00:00Z',
      };
      final loan = Loan.fromJson(json);
      expect(loan.name, 'Home Loan');
      expect(loan.loanType, LoanType.home);
      expect(loan.outstandingBalance, 4200000.0);
    });

    test('TransactionModel.fromJson deserializes correctly', () {
      final json = {
        'id': 'tx-1',
        'user_id': 'user-1',
        'transaction_type': 'transfer',
        'amount': '15000.00',
        'currency': 'INR',
        'transaction_date': '2026-09-11',
        'category': 'Credit Card Bill',
        'description': 'Payment for Infinia',
        'is_household_shared': false,
        'account_id': 'acc-1',
        'credit_card_id': 'cc-1',
        'created_at': '2026-09-11T00:00:00Z',
        'updated_at': '2026-09-11T00:00:00Z',
      };
      final tx = TransactionModel.fromJson(json);
      expect(tx.id, 'tx-1');
      expect(tx.transactionType, TransactionType.transfer);
      expect(tx.amount, 15000.0);
      expect(tx.creditCardId, 'cc-1');
    });
  });

  group('LoanCalculator', () {
    test('calculates accurate monthly EMI', () {
      // 100,000 at 12% for 12 months = ~8,884.88
      final emi = LoanCalculator.calculateMonthlyEmi(
        principal: 100000,
        annualRate: 12,
        tenureMonths: 12,
      );
      expect(emi.round(), 8885);
    });
  });

  group('HouseholdModeNotifier', () {
    test('toggles mode correctly in Riverpod container', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(householdModeProvider), isFalse);

      container.read(householdModeProvider.notifier).toggle();
      expect(container.read(householdModeProvider), isTrue);

      container.read(householdModeProvider.notifier).setMode(false);
      expect(container.read(householdModeProvider), isFalse);
    });
  });

  group('DashboardSummary empty factory', () {
    test('returns zeroed defaults', () {
      final summary = DashboardSummary.empty();
      expect(summary.totalLiquidBalance, 0.0);
      expect(summary.totalDebt, 0.0);
      expect(summary.netIncomeThisMonth, 0.0);
      expect(summary.accounts, isEmpty);
      expect(summary.creditCards, isEmpty);
      expect(summary.loans, isEmpty);
    });
  });
}
