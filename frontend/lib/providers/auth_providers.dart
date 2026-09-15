/// Riverpod auth controller backing the login / sign-up screen.
///
/// Talks to `POST /auth/login` (OAuth2 form-encoded) and `POST /auth/register`
/// (JSON), then hands the token pair to [AuthNotifier] so GoRouter's redirect
/// sends the user through to `/home`.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_service.dart';

/// Which form the login screen is currently showing.
enum AuthMode { signIn, signUp }

class AuthFormState {
  const AuthFormState({
    this.mode = AuthMode.signIn,
    this.isLoading = false,
    this.errorMessage,
  });

  final AuthMode mode;
  final bool isLoading;
  final String? errorMessage;

  bool get isSignUp => mode == AuthMode.signUp;

  AuthFormState copyWith({
    AuthMode? mode,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthFormState(
      mode: mode ?? this.mode,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthController extends Notifier<AuthFormState> {
  @override
  AuthFormState build() => const AuthFormState();

  /// Flip between "Sign in" and "Create account", clearing any stale error.
  void setMode(AuthMode mode) {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode, errorMessage: null);
  }

  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(errorMessage: null);
  }

  /// Sign in with an existing account. Returns true on success.
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _authenticate(email: email, password: password);
      state = state.copyWith(isLoading: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _messageFor(e));
      return false;
    }
  }

  /// Register a new user, then sign them straight in. Returns true on success.
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          'full_name': fullName,
        },
      );
      // Registration returns the user, not tokens — log in to get the pair.
      await _authenticate(email: email, password: password);
      state = state.copyWith(isLoading: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _messageFor(e));
      return false;
    }
  }

  /// POST /auth/login and persist the returned token pair.
  ///
  /// The endpoint is OAuth2-compatible, so it wants `username` / `password`
  /// as **form fields** — not the JSON body the Dio singleton defaults to.
  Future<void> _authenticate({
    required String email,
    required String password,
  }) async {
    final dio = ref.read(dioProvider);
    final response = await dio.post(
      '/auth/login',
      data: {'username': email, 'password': password},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );

    final data = response.data as Map;
    await ref.read(authProvider.notifier).login(
          accessToken: data['access_token'] as String,
          refreshToken: data['refresh_token'] as String,
        );
  }

  /// Turn a DioException into something worth showing a human.
  String _messageFor(DioException e) {
    final status = e.response?.statusCode;

    if (status == null) {
      return 'Cannot reach the server. Is the API running on $baseUrl?';
    }
    if (status == 401) return 'Incorrect email or password.';
    if (status == 403) return 'This account has been deactivated.';
    if (status == 409) return 'An account with this email already exists.';

    final detail = e.response?.data is Map
        ? (e.response!.data as Map)['detail']
        : null;

    // 422 detail is a list of pydantic validation errors.
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] != null) return first['msg'].toString();
    }
    if (detail is String) return detail;

    return 'Something went wrong (HTTP $status). Please try again.';
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthFormState>(AuthController.new);
