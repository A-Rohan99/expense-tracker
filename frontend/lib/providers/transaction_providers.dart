/// Riverpod controller for recording new ledger entries.
///
/// The backend validates sources per type ([app/schemas.py]):
///   income  — account_id required
///   expense — at least one of account_id / credit_card_id
/// The sheet only ever offers a valid source, so a rejection here means a
/// server-side rule the UI doesn't know about; surface it rather than swallow.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_service.dart';
import '../models/transaction.dart';
import 'dashboard_providers.dart';

/// Where the money moved — a cash/bank account or a credit card.
enum SourceKind { account, creditCard }

class TransactionFormState {
  const TransactionFormState({this.isLoading = false, this.errorMessage});

  final bool isLoading;
  final String? errorMessage;

  TransactionFormState copyWith({bool? isLoading, String? errorMessage}) {
    return TransactionFormState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class TransactionController extends Notifier<TransactionFormState> {
  @override
  TransactionFormState build() => const TransactionFormState();

  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(errorMessage: null);
  }

  /// Record an income or expense. Returns true once the ledger accepted it.
  Future<bool> createTransaction({
    required TransactionType type,
    required double amount,
    required String category,
    required SourceKind sourceKind,
    required String sourceId,
    String? description,
    DateTime? date,
    bool isHouseholdShared = false,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final body = <String, dynamic>{
      'transaction_type': type.name,
      'amount': amount,
      'currency': 'INR',
      'category': category,
      'is_household_shared': isHouseholdShared,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (date != null) 'transaction_date': _isoDate(date),
      if (sourceKind == SourceKind.account) 'account_id': sourceId,
      if (sourceKind == SourceKind.creditCard) 'credit_card_id': sourceId,
    };

    try {
      await ref.read(dioProvider).post('/transactions/', data: body);
      _refreshAllData();
      state = state.copyWith(isLoading: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _messageFor(e));
      return false;
    }
  }

  /// The API takes a plain `YYYY-MM-DD` date, not a full timestamp.
  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _messageFor(DioException e) {
    if (e.response == null) {
      return 'Cannot reach the server. Is the API running?';
    }

    final detail = e.response?.data is Map
        ? (e.response!.data as Map)['detail']
        : null;

    // 422 detail is a list of pydantic validation errors.
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] != null) {
        // Pydantic prefixes custom errors with "Value error, " — drop it.
        return first['msg'].toString().replaceFirst('Value error, ', '');
      }
    }
    if (detail is String) return detail;

    return 'Could not save (HTTP ${e.response?.statusCode}). Please try again.';
  }

  void _refreshAllData() {
    ref.invalidate(accountsProvider);
    ref.invalidate(creditCardsProvider);
    ref.invalidate(creditCardSummariesProvider);
    ref.invalidate(monthlyTransactionsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(dashboardSummaryProvider);
  }
}

final transactionControllerProvider =
    NotifierProvider<TransactionController, TransactionFormState>(
  TransactionController.new,
);

/// Starting points offered as chips, per transaction type. The field stays
/// free-text — these just save typing for the common cases.
const List<String> kExpenseCategories = [
  'Groceries',
  'Dining',
  'Transport',
  'Shopping',
  'Utilities',
  'Rent',
  'Health',
  'Entertainment',
  'Travel',
  'Other',
];

const List<String> kIncomeCategories = [
  'Salary',
  'Freelance',
  'Bonus',
  'Interest',
  'Refund',
  'Gift',
  'Other',
];
