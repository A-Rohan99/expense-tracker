/// Household membership.
///
/// The dashboard's Private/Household toggle has always filtered on
/// `include_household`, but nothing in the app ever called `/households/*`, so
/// a household could never be created or joined and the toggle was inert.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_service.dart';
import 'dashboard_providers.dart';

class Household {
  const Household({
    required this.id,
    required this.name,
    required this.inviteCode,
  });

  final String id;
  final String name;

  /// What another member types in to join. The only way in.
  final String inviteCode;

  factory Household.fromJson(Map<String, dynamic> json) => Household(
        id: json['id'] as String,
        name: json['name'] as String,
        inviteCode: json['invite_code'] as String? ?? '',
      );
}

class HouseholdMember {
  const HouseholdMember({required this.id, required this.name, required this.email});

  final String id;
  final String name;
  final String email;

  factory HouseholdMember.fromJson(Map<String, dynamic> json) => HouseholdMember(
        id: json['id'] as String,
        name: json['full_name'] as String? ?? '',
        email: json['email'] as String? ?? '',
      );
}

/// The user's household, or null when they're not in one.
final householdProvider = FutureProvider<Household?>((ref) async {
  try {
    final response = await ref.watch(dioProvider).get('/households/me');
    return Household.fromJson(response.data as Map<String, dynamic>);
  } on DioException catch (e) {
    // Not being in a household is a normal state, not an error.
    if (e.response?.statusCode == 404) return null;
    rethrow;
  }
});

final householdMembersProvider =
    FutureProvider<List<HouseholdMember>>((ref) async {
  final household = await ref.watch(householdProvider.future);
  if (household == null) return const [];
  final response = await ref.watch(dioProvider).get('/households/members');
  return (response.data as List)
      .map((json) => HouseholdMember.fromJson(json as Map<String, dynamic>))
      .toList();
});

class HouseholdState {
  const HouseholdState({this.isLoading = false, this.errorMessage});

  final bool isLoading;
  final String? errorMessage;

  HouseholdState copyWith({bool? isLoading, String? errorMessage}) {
    return HouseholdState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class HouseholdController extends Notifier<HouseholdState> {
  @override
  HouseholdState build() => const HouseholdState();

  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(errorMessage: null);
  }

  Future<bool> create(String name) => _run(
        () => ref.read(dioProvider).post('/households/', data: {'name': name}),
      );

  Future<bool> join(String inviteCode) => _run(
        () => ref
            .read(dioProvider)
            .post('/households/join', data: {'invite_code': inviteCode.trim()}),
      );

  Future<bool> leave() =>
      _run(() => ref.read(dioProvider).post('/households/leave'));

  Future<bool> _run(Future<Response> Function() request) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await request();
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
    if (e.response?.statusCode == 404) {
      return 'That invite code does not match any household.';
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
    return 'Something went wrong (HTTP ${e.response?.statusCode}).';
  }

  /// Membership changes what the household view contains, so refresh it all.
  void _refresh() {
    ref.invalidate(householdProvider);
    ref.invalidate(householdMembersProvider);
    ref.invalidate(monthlyTransactionsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(dashboardSummaryProvider);
  }
}

final householdControllerProvider =
    NotifierProvider<HouseholdController, HouseholdState>(
  HouseholdController.new,
);
