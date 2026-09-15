/// Create / update / delete for accounts, credit cards and loans.
///
/// The backend has had full CRUD for all three since the start; only the UI was
/// missing, which is why a new signup could not add anything and the app dead-
/// ended on an empty dashboard.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_service.dart';
import 'dashboard_providers.dart';

class ManageState {
  const ManageState({this.isLoading = false, this.errorMessage});

  final bool isLoading;
  final String? errorMessage;

  ManageState copyWith({bool? isLoading, String? errorMessage}) {
    return ManageState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// Which instrument a form is editing.
enum InstrumentKind {
  account('/accounts/', 'Account'),
  creditCard('/credit-cards/', 'Credit card'),
  loan('/loans/', 'Loan');

  const InstrumentKind(this.path, this.label);

  final String path;
  final String label;
}

class ManageController extends Notifier<ManageState> {
  @override
  ManageState build() => const ManageState();

  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(errorMessage: null);
  }

  /// Create when [id] is null, otherwise update.
  Future<bool> save({
    required InstrumentKind kind,
    required Map<String, dynamic> body,
    String? id,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final dio = ref.read(dioProvider);
      if (id == null) {
        await dio.post(kind.path, data: body);
      } else {
        await dio.patch('${kind.path}$id', data: body);
      }
      _refresh();
      state = state.copyWith(isLoading: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _messageFor(e));
      return false;
    }
  }

  Future<bool> remove({
    required InstrumentKind kind,
    required String id,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await ref.read(dioProvider).delete('${kind.path}$id');
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
    final data = e.response?.data;
    final detail = data is Map ? data['detail'] : null;

    // 422 detail is a list of per-field validation errors.
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] != null) {
        return first['msg'].toString().replaceFirst('Value error, ', '');
      }
    }
    if (detail is String) return detail;
    return 'Could not save (HTTP ${e.response?.statusCode}).';
  }

  /// Any instrument change moves balances or debt, so refresh the lot.
  void _refresh() {
    ref.invalidate(accountsProvider);
    ref.invalidate(creditCardsProvider);
    ref.invalidate(creditCardSummariesProvider);
    ref.invalidate(loansProvider);
    ref.invalidate(monthlyTransactionsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(dashboardSummaryProvider);
  }
}

final manageControllerProvider =
    NotifierProvider<ManageController, ManageState>(ManageController.new);

/// Signs the user out everywhere.
///
/// Calls `POST /auth/logout`, which bumps the server-side token version and
/// invalidates every token already issued — not just the one on this device.
/// Local tokens are cleared regardless, so a network failure still gets the
/// user out of the app.
final logoutProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    try {
      await ref.read(dioProvider).post('/auth/logout');
    } on DioException {
      // Best effort: the session may already be gone server-side.
    }
    await ref.read(authProvider.notifier).logout();
  };
});
