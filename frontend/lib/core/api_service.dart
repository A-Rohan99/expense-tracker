/// Dio-based API client with JWT interceptor.
///
/// - Automatically attaches the Bearer token from secure storage.
/// - Catches 401 responses and attempts a token refresh.
/// - If refresh fails, clears tokens and signals the auth state to log out.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════════════════════════════════

/// Where the API lives.
///
/// Supplied at build time so the same source produces a local build and a
/// deployed one:
///
///     flutter build web --release ///       --dart-define=API_BASE_URL=https://api.example.com/api/v1
///
/// Without this the URL was a compile-time const pointing at localhost, so the
/// deployed web build talked to the user's own machine and failed on every
/// call. Production must be https — browsers block mixed content, and Android
/// and iOS both refuse cleartext by default.
const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

/// Fallbacks for local development only.
/// 10.0.2.2 is the Android emulator's alias for the host machine.
const String _devBaseUrlWeb = 'http://localhost:8000/api/v1';
const String _devBaseUrlDevice = 'http://10.0.2.2:8000/api/v1';

String get baseUrl {
  if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
  return kIsWeb ? _devBaseUrlWeb : _devBaseUrlDevice;
}

// Secure storage keys
const String _kAccessToken = 'access_token';
const String _kRefreshToken = 'refresh_token';

// ═══════════════════════════════════════════════════════════════════════════
// Token storage helpers
// ═══════════════════════════════════════════════════════════════════════════

const _storage = FlutterSecureStorage();

Future<String?> getAccessToken() => _storage.read(key: _kAccessToken);
Future<String?> getRefreshToken() => _storage.read(key: _kRefreshToken);

Future<void> saveTokens({
  required String accessToken,
  required String refreshToken,
}) async {
  await _storage.write(key: _kAccessToken, value: accessToken);
  await _storage.write(key: _kRefreshToken, value: refreshToken);
}

Future<void> clearTokens() async {
  await _storage.delete(key: _kAccessToken);
  await _storage.delete(key: _kRefreshToken);
}

// ═══════════════════════════════════════════════════════════════════════════
// Auth state notifier (signals UI to redirect on logout)
// ═══════════════════════════════════════════════════════════════════════════

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthNotifier extends Notifier<AuthStatus> {
  @override
  AuthStatus build() => AuthStatus.unknown;

  /// Decide the startup auth state.
  ///
  /// Having a token is not the same as having a *valid* one. Trusting mere
  /// presence sent expired sessions to the dashboard, where they got a spinner
  /// and then an error card. Ask the server instead; the JWT interceptor will
  /// transparently refresh on the way through if the access token has aged out.
  Future<void> checkSession() async {
    final token = await getAccessToken();
    if (token == null) {
      state = AuthStatus.unauthenticated;
      return;
    }
    try {
      await ref.read(dioProvider).get('/auth/me');
      state = AuthStatus.authenticated;
    } on DioException catch (e) {
      // Only a rejected identity means signed out. A network blip should not
      // discard a session that may well still be good.
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        await clearTokens();
        state = AuthStatus.unauthenticated;
      } else {
        state = AuthStatus.authenticated;
      }
    }
  }

  Future<void> login({
    required String accessToken,
    required String refreshToken,
  }) async {
    await saveTokens(accessToken: accessToken, refreshToken: refreshToken);
    state = AuthStatus.authenticated;
  }

  Future<void> logout() async {
    await clearTokens();
    state = AuthStatus.unauthenticated;
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthStatus>(
  AuthNotifier.new,
);

// ═══════════════════════════════════════════════════════════════════════════
// JWT Interceptor
// ═══════════════════════════════════════════════════════════════════════════

class JwtInterceptor extends Interceptor {
  JwtInterceptor(this._ref, this._dio);

  final Ref _ref;

  /// The client this interceptor is installed on. Held directly rather than
  /// read back from dioProvider, which would be a circular dependency — and
  /// holding it means the refresh and retry inherit the app's real transport
  /// and timeouts instead of a bare, unconfigurable Dio().
  final Dio _dio;

  /// In-flight refresh, if any.
  ///
  /// The dashboard fires six requests at once, so an expired token produces
  /// six simultaneous 401s. Previously the first one refreshed and the other
  /// five were passed through as hard failures, surfacing a spurious error
  /// screen. They now await the same refresh and retry once it lands.
  Future<String?>? _refreshInFlight;

  /// Marks a request that has already been retried after a refresh.
  static const String _retriedKey = 'jwt_retried';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Skip auth header for public endpoints
    final isPublic = options.path.contains('/auth/login') ||
        options.path.contains('/auth/register') ||
        options.path.contains('/utils/calculate-emi') ||
        options.path.contains('/health');

    if (!isPublic) {
      final token = await getAccessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }

    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Only handle 401 Unauthorized.
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    // A refresh call that itself 401s must not recurse.
    if (err.requestOptions.path.contains('/auth/refresh')) {
      await _forceLogout();
      return handler.next(err);
    }

    // Retry once and once only. Without this marker a request that 401s again
    // after a successful refresh would trigger another refresh, and so on.
    if (err.requestOptions.extra[_retriedKey] == true) {
      return handler.next(err);
    }

    // Join the in-flight refresh, or start one.
    final newAccess = await (_refreshInFlight ??= _refreshTokens());

    if (newAccess == null) {
      return handler.next(err);
    }

    try {
      final retryOptions = err.requestOptions;
      retryOptions.headers['Authorization'] = 'Bearer $newAccess';
      retryOptions.extra = {...retryOptions.extra, _retriedKey: true};
      // Reuse the app's Dio so the retry keeps the configured timeouts.
      final retryResponse = await _dio.fetch(retryOptions);
      return handler.resolve(retryResponse);
    } on DioException catch (retryErr) {
      return handler.next(retryErr);
    }
  }

  /// Exchange the refresh token for a new pair. Returns the new access token,
  /// or null when the session is genuinely over (the caller is logged out).
  Future<String?> _refreshTokens() async {
    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null) {
        await _forceLogout();
        return null;
      }

      // Separate Dio so this request doesn't re-enter this interceptor, but
      // sharing the app's transport and timeouts — a bare Dio() would ignore
      // both, and would be impossible to point at a test double.
      final refreshDio = Dio(_dio.options)
        ..httpClientAdapter = _dio.httpClientAdapter;
      final response = await refreshDio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        final newAccess = response.data['access_token'] as String;
        final newRefresh = response.data['refresh_token'] as String;
        await saveTokens(accessToken: newAccess, refreshToken: newRefresh);
        return newAccess;
      }
      await _forceLogout();
      return null;
    } on DioException {
      await _forceLogout();
      return null;
    } finally {
      // Clear the slot so a later expiry starts a fresh refresh.
      _refreshInFlight = null;
    }
  }

  Future<void> _forceLogout() async {
    await clearTokens();
    _ref.read(authProvider.notifier).logout();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Dio provider (app-wide singleton)
// ═══════════════════════════════════════════════════════════════════════════

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  dio.interceptors.addAll([
    JwtInterceptor(ref, dio),
    if (kDebugMode)
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => debugPrint(obj.toString()),
      ),
  ]);

  return dio;
});
