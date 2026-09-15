/// The filterable transaction list.
///
/// The dashboard only ever showed the ten most recent rows, so there was no way
/// to find an old entry — or to correct one. This backs a real list screen with
/// the filters the API now supports.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_service.dart';
import '../models/transaction.dart';
import 'dashboard_providers.dart';

/// How the list is sorted. Values match the API's `sort` parameter.
enum TransactionSort {
  dateDesc('date_desc', 'Newest first'),
  dateAsc('date_asc', 'Oldest first'),
  amountDesc('amount_desc', 'Largest first'),
  amountAsc('amount_asc', 'Smallest first');

  const TransactionSort(this.value, this.label);

  final String value;
  final String label;
}

/// Everything the list screen can filter on.
class TransactionFilter {
  const TransactionFilter({
    this.search,
    this.type,
    this.accountId,
    this.creditCardId,
    this.startDate,
    this.endDate,
    this.sort = TransactionSort.dateDesc,
  });

  final String? search;
  final TransactionType? type;
  final String? accountId;
  final String? creditCardId;
  final DateTime? startDate;
  final DateTime? endDate;
  final TransactionSort sort;

  bool get isFiltered =>
      (search != null && search!.isNotEmpty) ||
      type != null ||
      accountId != null ||
      creditCardId != null ||
      startDate != null ||
      endDate != null;

  /// Sentinel so a caller can clear a field rather than leave it unchanged.
  static const Object _keep = Object();

  TransactionFilter copyWith({
    Object? search = _keep,
    Object? type = _keep,
    Object? accountId = _keep,
    Object? creditCardId = _keep,
    Object? startDate = _keep,
    Object? endDate = _keep,
    TransactionSort? sort,
  }) {
    return TransactionFilter(
      search: identical(search, _keep) ? this.search : search as String?,
      type: identical(type, _keep) ? this.type : type as TransactionType?,
      accountId:
          identical(accountId, _keep) ? this.accountId : accountId as String?,
      creditCardId: identical(creditCardId, _keep)
          ? this.creditCardId
          : creditCardId as String?,
      startDate:
          identical(startDate, _keep) ? this.startDate : startDate as DateTime?,
      endDate: identical(endDate, _keep) ? this.endDate : endDate as DateTime?,
      sort: sort ?? this.sort,
    );
  }

  TransactionFilter cleared() => TransactionFilter(sort: sort);

  Map<String, dynamic> toQuery({required bool includeHousehold}) {
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    return {
      'limit': 100,
      'sort': sort.value,
      'include_household': includeHousehold,
      if (search != null && search!.isNotEmpty) 'search': search,
      if (type != null) 'transaction_type': type!.name,
      if (accountId != null) 'account_id': accountId,
      if (creditCardId != null) 'credit_card_id': creditCardId,
      if (startDate != null) 'start_date': iso(startDate!),
      if (endDate != null) 'end_date': iso(endDate!),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is TransactionFilter &&
      other.search == search &&
      other.type == type &&
      other.accountId == accountId &&
      other.creditCardId == creditCardId &&
      other.startDate == startDate &&
      other.endDate == endDate &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
        search,
        type,
        accountId,
        creditCardId,
        startDate,
        endDate,
        sort,
      );
}

class TransactionFilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => const TransactionFilter();

  void setSearch(String? value) =>
      state = state.copyWith(search: (value ?? '').isEmpty ? null : value);
  void setType(TransactionType? value) => state = state.copyWith(type: value);
  void setAccount(String? value) => state = state.copyWith(accountId: value);
  void setCard(String? value) => state = state.copyWith(creditCardId: value);
  void setRange(DateTime? start, DateTime? end) =>
      state = state.copyWith(startDate: start, endDate: end);
  void setSort(TransactionSort value) => state = state.copyWith(sort: value);
  void clear() => state = state.cleared();
}

final transactionFilterProvider =
    NotifierProvider<TransactionFilterNotifier, TransactionFilter>(
  TransactionFilterNotifier.new,
);

final filteredTransactionsProvider =
    FutureProvider<List<TransactionModel>>((ref) async {
  final filter = ref.watch(transactionFilterProvider);
  final isHousehold = ref.watch(householdModeProvider);
  final response = await ref.watch(dioProvider).get(
        '/transactions/',
        queryParameters: filter.toQuery(includeHousehold: isHousehold),
      );
  return (response.data as List)
      .map((json) => TransactionModel.fromJson(json as Map<String, dynamic>))
      .toList();
});

// ═══════════════════════════════════════════════════════════════════════════
// Editing
// ═══════════════════════════════════════════════════════════════════════════

class TransactionEditState {
  const TransactionEditState({this.isLoading = false, this.errorMessage});

  final bool isLoading;
  final String? errorMessage;

  TransactionEditState copyWith({bool? isLoading, String? errorMessage}) {
    return TransactionEditState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class TransactionEditController extends Notifier<TransactionEditState> {
  @override
  TransactionEditState build() => const TransactionEditState();

  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(errorMessage: null);
  }

  /// Update the metadata on an existing entry.
  ///
  /// Amount and instrument links are immutable server-side — double-entry
  /// convention is to delete and re-record rather than rewrite history — so
  /// only the category, note, date and sharing flag are editable.
  Future<bool> update({
    required String id,
    String? category,
    String? description,
    DateTime? date,
    bool? isHouseholdShared,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await ref.read(dioProvider).patch('/transactions/$id', data: {
        'category': ?category,
        'description': ?description,
        if (date != null) 'transaction_date': _iso(date),
        'is_household_shared': ?isHouseholdShared,
      });
      _refresh();
      state = state.copyWith(isLoading: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _messageFor(e));
      return false;
    }
  }

  /// Delete an entry. The server reverses its effect on balances.
  Future<bool> remove(String id) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await ref.read(dioProvider).delete('/transactions/$id');
      _refresh();
      state = state.copyWith(isLoading: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _messageFor(e));
      return false;
    }
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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

  /// Deleting reverses balances, so the whole dashboard is stale afterwards.
  void _refresh() {
    ref.invalidate(filteredTransactionsProvider);
    ref.invalidate(accountsProvider);
    ref.invalidate(creditCardsProvider);
    ref.invalidate(creditCardSummariesProvider);
    ref.invalidate(loansProvider);
    ref.invalidate(monthlyTransactionsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(dashboardSummaryProvider);
  }
}

final transactionEditControllerProvider =
    NotifierProvider<TransactionEditController, TransactionEditState>(
  TransactionEditController.new,
);
