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

/// Change this to your deployed backend URL in production.
const String kBaseUrl = 'http://10.0.2.2:8000/api/v1'; // Android emulator → host
const String kBaseUrlWeb = 'http://localhost:8000/api/v1';

String get baseUrl => kIsWeb ? kBaseUrlWeb : kBaseUrl;

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

  Future<void> checkSession() async {
    final token = await getAccessToken();
    state = token != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
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
  JwtInterceptor(this._ref);

  final Ref _ref;

  /// Flag to prevent infinite refresh loops.
  bool _isRefreshing = false;

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
    // Only handle 401 Unauthorized
    if (err.response?.statusCode != 401 || _isRefreshing) {
      return handler.next(err);
    }

    _isRefreshing = true;

    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null) {
        await _forceLogout();
        return handler.next(err);
      }

      // Attempt token refresh using a *separate* Dio instance
      // to avoid the interceptor catching its own 401.
      final refreshDio = Dio(BaseOptions(baseUrl: baseUrl));
      final response = await refreshDio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        final newAccess = response.data['access_token'] as String;
        final newRefresh = response.data['refresh_token'] as String;
        await saveTokens(accessToken: newAccess, refreshToken: newRefresh);

        // Retry the original request with the new token
        final retryOptions = err.requestOptions;
        retryOptions.headers['Authorization'] = 'Bearer $newAccess';

        final retryResponse = await Dio().fetch(retryOptions);
        return handler.resolve(retryResponse);
      } else {
        await _forceLogout();
        return handler.next(err);
      }
    } on DioException {
      await _forceLogout();
      return handler.next(err);
    } finally {
      _isRefreshing = false;
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
    JwtInterceptor(ref),
    if (kDebugMode)
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => debugPrint(obj.toString()),
      ),
  ]);

  return dio;
});
