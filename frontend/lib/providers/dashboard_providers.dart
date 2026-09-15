/// Riverpod providers for Dashboard data, calculations, and household toggle.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_service.dart';
import '../models/account.dart';
import '../models/credit_card.dart';
import '../models/dashboard_summary.dart';
import '../models/loan.dart';
import '../models/transaction.dart';
import 'budget_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Household Mode Toggle Notifier (Riverpod 3.x)
// ═══════════════════════════════════════════════════════════════════════════

class HouseholdModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void setMode(bool isHousehold) => state = isHousehold;
}

final householdModeProvider = NotifierProvider<HouseholdModeNotifier, bool>(
  HouseholdModeNotifier.new,
);

// ═══════════════════════════════════════════════════════════════════════════
// Data Source Providers
// ═══════════════════════════════════════════════════════════════════════════

final accountsProvider = FutureProvider<List<Account>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/accounts/');
  final data = response.data as List;
  return data.map((json) => Account.fromJson(json as Map<String, dynamic>)).toList();
});

final creditCardsProvider = FutureProvider<List<CreditCard>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/credit-cards/');
  final data = response.data as List;
  return data.map((json) => CreditCard.fromJson(json as Map<String, dynamic>)).toList();
});

final creditCardSummariesProvider = FutureProvider<List<CreditCardSummary>>((ref) async {
  final cards = await ref.watch(creditCardsProvider.future);
  final dio = ref.watch(dioProvider);

  if (cards.isEmpty) return <CreditCardSummary>[];

  final summaries = await Future.wait(
    cards.map((card) async {
      try {
        final response = await dio.get('/credit-cards/${card.id}/summary');
        return CreditCardSummary.fromJson(response.data as Map<String, dynamic>);
      } catch (_) {
        // Fall back to the amounts the card list already carries, but leave
        // the billing-cycle dates null. Inventing a due date here rendered as
        // a confident "Due in 15d" badge and could make someone miss a real
        // payment — the UI shows "due date unavailable" instead.
        return CreditCardSummary(
          cardId: card.id,
          cardName: card.name,
          totalLimit: card.totalLimit,
          billedAmount: card.billedAmount,
          unbilledAmount: card.unbilledAmount,
          totalOutstanding: card.billedAmount + card.unbilledAmount,
          availableLimit: card.availableLimit > 0
              ? card.availableLimit
              : card.totalLimit - (card.billedAmount + card.unbilledAmount),
          totalPayments: 0.0,
          minDueAmount: 0.0,
        );
      }
    }),
  );

  return summaries;
});

final loansProvider = FutureProvider<List<Loan>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/loans/');
  final data = response.data as List;
  return data.map((json) => Loan.fromJson(json as Map<String, dynamic>)).toList();
});

final monthlyTransactionsProvider = FutureProvider<List<TransactionModel>>((ref) async {
  final isHousehold = ref.watch(householdModeProvider);
  final dio = ref.watch(dioProvider);

  final now = DateTime.now();
  final startDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';

  final response = await dio.get(
    '/transactions/',
    queryParameters: {
      'start_date': startDate,
      'include_household': isHousehold,
      'limit': 100,
    },
  );

  final data = response.data as List;
  return data.map((json) => TransactionModel.fromJson(json as Map<String, dynamic>)).toList();
});

final recentTransactionsProvider = FutureProvider<List<TransactionModel>>((ref) async {
  final isHousehold = ref.watch(householdModeProvider);
  final dio = ref.watch(dioProvider);

  final response = await dio.get(
    '/transactions/',
    queryParameters: {
      'include_household': isHousehold,
      'limit': 10,
    },
  );

  final data = response.data as List;
  return data.map((json) => TransactionModel.fromJson(json as Map<String, dynamic>)).toList();
});

// ═══════════════════════════════════════════════════════════════════════════
// Composite Dashboard Summary Provider
// ═══════════════════════════════════════════════════════════════════════════

final dashboardSummaryProvider = FutureProvider<DashboardSummary>((ref) async {
  final isHousehold = ref.watch(householdModeProvider);

  // Await all sources concurrently
  final accountsFuture = ref.watch(accountsProvider.future);
  final creditCardsFuture = ref.watch(creditCardsProvider.future);
  final creditCardSummariesFuture = ref.watch(creditCardSummariesProvider.future);
  final loansFuture = ref.watch(loansProvider.future);
  final monthlyTxFuture = ref.watch(monthlyTransactionsProvider.future);
  final recentTxFuture = ref.watch(recentTransactionsProvider.future);
  final reportFuture = ref.watch(monthlyReportProvider.future);

  final accounts = await accountsFuture;
  final creditCards = await creditCardsFuture;
  final creditCardSummaries = await creditCardSummariesFuture;
  final loans = await loansFuture;
  await monthlyTxFuture;
  final recentTx = await recentTxFuture;

  // 1. Total Liquid Balance (Bank / Cash / Wallet active accounts)
  final totalLiquidBalance = accounts
      .where((a) => a.isActive)
      .fold<double>(0.0, (sum, a) => sum + a.currentBalance);

  // 2. Monthly cash flow, aggregated by the server.
  //
  // This used to sum `monthlyTx` here, but that list is capped at 100 rows, so
  // once a month had more transactions than the cap the headline figures were
  // silently wrong — and the error grew with use. /reports/monthly counts
  // everything.
  final report = await reportFuture;
  final incomeThisMonth = report.income;
  final expenseThisMonth = report.expense;
  final netIncomeThisMonth = report.net;

  // 3. Liabilities / Debt
  final creditCardDebt = creditCardSummaries.fold<double>(
    0.0,
    (sum, s) => sum + s.totalOutstanding,
  );

  final loanDebt = loans
      .where((l) => l.isActive)
      .fold<double>(0.0, (sum, l) => sum + l.outstandingBalance);

  final totalDebt = creditCardDebt + loanDebt;

  return DashboardSummary(
    totalLiquidBalance: totalLiquidBalance,
    netIncomeThisMonth: netIncomeThisMonth,
    incomeThisMonth: incomeThisMonth,
    expenseThisMonth: expenseThisMonth,
    totalDebt: totalDebt,
    creditCardDebt: creditCardDebt,
    loanDebt: loanDebt,
    accounts: accounts,
    creditCards: creditCards,
    creditCardSummaries: creditCardSummaries,
    loans: loans,
    recentTransactions: recentTx,
    isHouseholdMode: isHousehold,
  );
});
