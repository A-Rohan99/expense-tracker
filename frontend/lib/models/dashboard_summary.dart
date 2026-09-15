/// Consolidated summary data model for the Dashboard screen.
library;

import 'account.dart';
import 'credit_card.dart';
import 'loan.dart';
import 'transaction.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.totalLiquidBalance,
    required this.netIncomeThisMonth,
    required this.incomeThisMonth,
    required this.expenseThisMonth,
    required this.totalDebt,
    required this.creditCardDebt,
    required this.loanDebt,
    required this.accounts,
    required this.creditCards,
    required this.creditCardSummaries,
    required this.loans,
    required this.recentTransactions,
    required this.isHouseholdMode,
  });

  final double totalLiquidBalance;
  final double netIncomeThisMonth;
  final double incomeThisMonth;
  final double expenseThisMonth;
  final double totalDebt;
  final double creditCardDebt;
  final double loanDebt;
  final List<Account> accounts;
  final List<CreditCard> creditCards;
  final List<CreditCardSummary> creditCardSummaries;
  final List<Loan> loans;
  final List<TransactionModel> recentTransactions;
  final bool isHouseholdMode;

  factory DashboardSummary.empty({bool isHouseholdMode = false}) {
    return DashboardSummary(
      totalLiquidBalance: 0.0,
      netIncomeThisMonth: 0.0,
      incomeThisMonth: 0.0,
      expenseThisMonth: 0.0,
      totalDebt: 0.0,
      creditCardDebt: 0.0,
      loanDebt: 0.0,
      accounts: const [],
      creditCards: const [],
      creditCardSummaries: const [],
      loans: const [],
      recentTransactions: const [],
      isHouseholdMode: isHouseholdMode,
    );
  }
}
