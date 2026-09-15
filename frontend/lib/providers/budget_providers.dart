/// Budgets and the server-side monthly report.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_service.dart';
import '../models/budget.dart';
import 'dashboard_providers.dart';

final budgetsProvider = FutureProvider<List<Budget>>((ref) async {
  // Household mode changes which spending counts, so re-fetch when it flips.
  ref.watch(householdModeProvider);
  final response = await ref.watch(dioProvider).get('/budgets/');
  return (response.data as List)
      .map((json) => Budget.fromJson(json as Map<String, dynamic>))
      .toList();
});

/// This month's totals, aggregated by the server.
///
/// Replaces the client summing a capped page of transactions, which went
/// silently wrong once a month had more rows than the cap.
final monthlyReportProvider = FutureProvider<MonthlyReport>((ref) async {
  final isHousehold = ref.watch(householdModeProvider);
  final response = await ref.watch(dioProvider).get(
    '/reports/monthly',
    queryParameters: {'include_household': isHousehold},
  );
  return MonthlyReport.fromJson(response.data as Map<String, dynamic>);
});

class BudgetFormState {
  const BudgetFormState({this.isLoading = false, this.errorMessage});

  final bool isLoading;
  final String? errorMessage;

  BudgetFormState copyWith({bool? isLoading, String? errorMessage}) {
    return BudgetFormState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class BudgetController extends Notifier<BudgetFormState> {
  @override
  BudgetFormState build() => const BudgetFormState();

  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(errorMessage: null);
  }

  /// Create when [existingId] is null, otherwise update the cap.
  Future<bool> save({
    required double amount,
    String? existingId,
    String? category,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final dio = ref.read(dioProvider);
      if (existingId == null) {
        await dio.post('/budgets/', data: {
          'amount': amount,
          if (category != null && category.isNotEmpty) 'category': category,
        });
      } else {
        await dio.patch('/budgets/$existingId', data: {'amount': amount});
      }
      _refresh();
      state = state.copyWith(isLoading: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _messageFor(e));
      return false;
    }
  }

  Future<bool> remove(String id) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await ref.read(dioProvider).delete('/budgets/$id');
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
      return 'Cannot reach the server. Check your connection.';
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
    return 'Could not save (HTTP ${e.response?.statusCode}).';
  }

  void _refresh() => ref.invalidate(budgetsProvider);
}

final budgetControllerProvider =
    NotifierProvider<BudgetController, BudgetFormState>(BudgetController.new);
