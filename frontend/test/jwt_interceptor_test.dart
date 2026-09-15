/// Tests for the JWT interceptor — token attachment, refresh-on-401, and the
/// concurrency behaviour that stops six parallel 401s triggering six refreshes.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:expense_tracker_app/core/api_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scriptable transport: queue a response per request path.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.respond);

  /// Given a request, return (statusCode, jsonBody).
  final (int, Object?) Function(RequestOptions options) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = respond(options);
    return ResponseBody.fromString(
      jsonEncode(body ?? {}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// flutter_secure_storage talks over a platform channel that doesn't exist in
/// a unit test, so back it with an in-memory map.
void _mockSecureStorage(Map<String, String> store) {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    switch (call.method) {
      case 'read':
        return store[args['key'] as String];
      case 'write':
        store[args['key'] as String] = args['value'] as String;
        return null;
      case 'delete':
        store.remove(args['key'] as String);
        return null;
      case 'readAll':
        return Map<String, String>.from(store);
      case 'deleteAll':
        store.clear();
        return null;
      default:
        return null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> storage;

  setUp(() {
    storage = <String, String>{};
    _mockSecureStorage(storage);
  });

  /// Build a container whose dioProvider uses [adapter] but keeps the real
  /// interceptor under test.
  ProviderContainer containerWith(_ScriptedAdapter adapter) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final dio = container.read(dioProvider);
    dio.httpClientAdapter = adapter;
    return container;
  }

  group('token attachment', () {
    test('attaches the stored access token to a protected request', () async {
      storage['access_token'] = 'stored-access';
      final adapter = _ScriptedAdapter((_) => (200, {'ok': true}));
      final container = containerWith(adapter);

      await container.read(dioProvider).get('/accounts/');

      expect(adapter.requests.single.headers['Authorization'],
          'Bearer stored-access');
    });

    test('does not attach a token to login or register', () async {
      storage['access_token'] = 'stored-access';
      final adapter = _ScriptedAdapter((_) => (200, {'ok': true}));
      final container = containerWith(adapter);

      await container.read(dioProvider).post('/auth/login');
      await container.read(dioProvider).post('/auth/register');

      for (final r in adapter.requests) {
        expect(r.headers.containsKey('Authorization'), isFalse,
            reason: '${r.path} should be public');
      }
    });
  });

  group('refresh on 401', () {
    test('refreshes once and retries the original request', () async {
      storage['access_token'] = 'expired';
      storage['refresh_token'] = 'good-refresh';

      var accountsCalls = 0;
      final adapter = _ScriptedAdapter((options) {
        if (options.path.contains('/auth/refresh')) {
          return (200, {
            'access_token': 'fresh-access',
            'refresh_token': 'fresh-refresh',
          });
        }
        accountsCalls++;
        // First attempt is stale, the retry carries the new token.
        return options.headers['Authorization'] == 'Bearer fresh-access'
            ? (200, {'ok': true})
            : (401, {'detail': 'expired'});
      });
      final container = containerWith(adapter);

      final response = await container.read(dioProvider).get('/accounts/');

      expect(response.statusCode, 200);
      expect(accountsCalls, 2, reason: 'original attempt plus one retry');
      expect(storage['access_token'], 'fresh-access');
      expect(storage['refresh_token'], 'fresh-refresh',
          reason: 'the rotated refresh token must be persisted too');
    });

    test('six concurrent 401s trigger exactly one refresh', () async {
      storage['access_token'] = 'expired';
      storage['refresh_token'] = 'good-refresh';

      var refreshCalls = 0;
      final adapter = _ScriptedAdapter((options) {
        if (options.path.contains('/auth/refresh')) {
          refreshCalls++;
          return (200, {
            'access_token': 'fresh-access',
            'refresh_token': 'fresh-refresh',
          });
        }
        return options.headers['Authorization'] == 'Bearer fresh-access'
            ? (200, {'ok': true})
            : (401, {'detail': 'expired'});
      });
      final container = containerWith(adapter);
      final dio = container.read(dioProvider);

      // This is what the dashboard does on load.
      final responses = await Future.wait([
        dio.get('/accounts/'),
        dio.get('/credit-cards/'),
        dio.get('/loans/'),
        dio.get('/transactions/'),
        dio.get('/recurring-income/'),
        dio.get('/auth/me'),
      ]);

      expect(responses.every((r) => r.statusCode == 200), isTrue,
          reason: 'every queued request should succeed after the refresh');
      expect(refreshCalls, 1,
          reason: 'concurrent 401s must share a single refresh');
    });

    test('a failed refresh logs the user out', () async {
      storage['access_token'] = 'expired';
      storage['refresh_token'] = 'revoked';

      final adapter = _ScriptedAdapter((options) {
        if (options.path.contains('/auth/refresh')) {
          return (401, {'detail': 'Invalid refresh token'});
        }
        return (401, {'detail': 'expired'});
      });
      final container = containerWith(adapter);

      await expectLater(
        container.read(dioProvider).get('/accounts/'),
        throwsA(isA<DioException>()),
      );

      expect(container.read(authProvider), AuthStatus.unauthenticated);
      expect(storage.containsKey('access_token'), isFalse,
          reason: 'tokens should be cleared on logout');
    });

    test('with no refresh token stored, it logs out without calling refresh',
        () async {
      storage['access_token'] = 'expired';

      var refreshCalls = 0;
      final adapter = _ScriptedAdapter((options) {
        if (options.path.contains('/auth/refresh')) refreshCalls++;
        return (401, {'detail': 'expired'});
      });
      final container = containerWith(adapter);

      await expectLater(
        container.read(dioProvider).get('/accounts/'),
        throwsA(isA<DioException>()),
      );

      expect(refreshCalls, 0);
      expect(container.read(authProvider), AuthStatus.unauthenticated);
    });
  });

  group('checkSession', () {
    test('no token means unauthenticated', () async {
      final adapter = _ScriptedAdapter((_) => (200, {'ok': true}));
      final container = containerWith(adapter);

      await container.read(authProvider.notifier).checkSession();

      expect(container.read(authProvider), AuthStatus.unauthenticated);
    });

    test('a token the server accepts means authenticated', () async {
      storage['access_token'] = 'good';
      final adapter = _ScriptedAdapter((_) => (200, {'email': 'a@b.com'}));
      final container = containerWith(adapter);

      await container.read(authProvider.notifier).checkSession();

      expect(container.read(authProvider), AuthStatus.authenticated);
      expect(adapter.requests.single.path, '/auth/me',
          reason: 'presence of a token is not proof it is valid');
    });

    test('a rejected token clears the session', () async {
      storage['access_token'] = 'stale';
      // No refresh token, so the interceptor gives up rather than retrying.
      final adapter = _ScriptedAdapter((_) => (401, {'detail': 'nope'}));
      final container = containerWith(adapter);

      await container.read(authProvider.notifier).checkSession();

      expect(container.read(authProvider), AuthStatus.unauthenticated);
    });

    test('a network failure keeps the session rather than discarding it',
        () async {
      storage['access_token'] = 'good';
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final dio = container.read(dioProvider);
      dio.httpClientAdapter = _ThrowingAdapter();

      await container.read(authProvider.notifier).checkSession();

      expect(container.read(authProvider), AuthStatus.authenticated,
          reason: 'a blip offline should not sign the user out');
    });
  });
}

/// Simulates the device being offline.
class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'offline',
    );
  }

  @override
  void close({bool force = false}) {}
}
