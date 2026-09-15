/// Riverpod state for the standing monthly income instruction.
///
/// Fetching it is what drives the server-side catch-up, so this provider is
/// read on dashboard load: opening the app is what posts any income that fell
/// due while it was closed.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_service.dart';
import '../models/recurring_income.dart';
import 'dashboard_providers.dart';

/// `null` when the user hasn't set one up.
final recurringIncomeProvider =
    FutureProvider<RecurringIncome?>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/recurring-income/');
  final data = response.data;
  if (data == null) return null;
  return RecurringIncome.fromJson(data as Map<String, dynamic>);
});

class RecurringIncomeFormState {
  const RecurringIncomeFormState({this.isLoading = false, this.errorMessage});

  final bool isLoading;
  final String? errorMessage;

  RecurringIncomeFormState copyWith({bool? isLoading, String? errorMessage}) {
    return RecurringIncomeFormState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class RecurringIncomeController
    extends Notifier<RecurringIncomeFormState> {
  @override
  RecurringIncomeFormState build() => const RecurringIncomeFormState();

  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(errorMessage: null);
  }

  /// Create the instruction, or update it when [existingId] is non-null.
  Future<bool> save({
    required String? existingId,
    required double amount,
    required int dayOfMonth,
    required String accountId,
    String name = 'Monthly income',
    String category = 'Salary',
    bool isHouseholdShared = false,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final body = {
      'account_id': accountId,
      'amount': amount,
      'day_of_month': dayOfMonth,
      'name': name,
      'category': category,
      'is_household_shared': isHouseholdShared,
    };

    try {
      final dio = ref.read(dioProvider);
      if (existingId == null) {
        await dio.post('/recurring-income/', data: body);
      } else {
        await dio.patch('/recurring-income/', data: body);
      }
      _refresh();
      state = state.copyWith(isLoading: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _messageFor(e));
      return false;
    }
  }

  /// Stop future months. Income already posted stays in the ledger.
  Future<bool> remove() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await ref.read(dioProvider).delete('/recurring-income/');
      _refresh();
      state = state.copyWith(isLoading: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _messageFor(e));
      return false;
    }
  }

  String _messageFor(DioException e) {
    if (e.response == null) {
      return 'Cannot reach the server. Is the API running?';
    }
    final detail =
        e.response?.data is Map ? (e.response!.data as Map)['detail'] : null;

    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] != null) {
        return first['msg'].toString().replaceFirst('Value error, ', '');
      }
    }
    if (detail is String) return detail;
    return 'Could not save (HTTP ${e.response?.statusCode}). Please try again.';
  }

  void _refresh() {
    ref.invalidate(recurringIncomeProvider);
    // A save can post a month immediately, so balances may have moved.
    ref.invalidate(accountsProvider);
    ref.invalidate(monthlyTransactionsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(dashboardSummaryProvider);
  }
}

final recurringIncomeControllerProvider = NotifierProvider<
    RecurringIncomeController, RecurringIncomeFormState>(
  RecurringIncomeController.new,
);
