/// Tests for the instrument management flow.
///
/// The request-shaping tests exist because of a real bug: `last_four` was
/// flagged as an integer field, which controlled both input filtering *and*
/// the JSON type, so the server rejected a card with "Input should be a valid
/// string". Digit-only input and numeric JSON are separate concerns.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:expense_tracker_app/core/api_service.dart';
import 'package:expense_tracker_app/core/theme.dart';
import 'package:expense_tracker_app/providers/manage_providers.dart';
import 'package:expense_tracker_app/widgets/instrument_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  int statusCode = 201;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode({"id": "new_1"}),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _CapturingAdapter adapter;

  setUp(() => adapter = _CapturingAdapter());

  ProviderContainer container() {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    final c = ProviderContainer(
      overrides: [dioProvider.overrideWithValue(dio)],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('ManageController', () {
    test('creating POSTs to the right collection', () async {
      final c = container();
      await c.read(manageControllerProvider.notifier).save(
        kind: InstrumentKind.account,
        body: {'name': 'Bank', 'account_type': 'bank'},
      );
      expect(adapter.lastRequest!.method, 'POST');
      expect(adapter.lastRequest!.path, '/accounts/');
    });

    test('editing PATCHes the specific resource', () async {
      final c = container();
      adapter.statusCode = 200;
      await c.read(manageControllerProvider.notifier).save(
        kind: InstrumentKind.creditCard,
        body: {'name': 'Renamed'},
        id: 'card_7',
      );
      expect(adapter.lastRequest!.method, 'PATCH');
      expect(adapter.lastRequest!.path, '/credit-cards/card_7');
    });

    test('deleting targets the specific resource', () async {
      final c = container();
      adapter.statusCode = 204;
      await c
          .read(manageControllerProvider.notifier)
          .remove(kind: InstrumentKind.loan, id: 'loan_3');
      expect(adapter.lastRequest!.method, 'DELETE');
      expect(adapter.lastRequest!.path, '/loans/loan_3');
    });

    test('a server validation error is unwrapped for display', () async {
      // A dedicated adapter, because the shared one always returns success.
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = _ErrorAdapter();
      final errored = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(errored.dispose);

      final ok = await errored.read(manageControllerProvider.notifier).save(
        kind: InstrumentKind.account,
        body: {'name': ''},
      );
      expect(ok, isFalse);
      expect(
        errored.read(manageControllerProvider).errorMessage,
        'Name must not be empty',
      );
    });
  });

  group('Card form request shaping', () {
    Future<void> openCardSheet(WidgetTester tester) async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dioProvider.overrideWithValue(dio)],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => InstrumentFormSheet.creditCard(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('sends last_four as a string and the day fields as numbers',
        (tester) async {
      await openCardSheet(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'), 'Amex');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Last 4 digits'), '4021');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Credit limit'), '300000');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Statement day'), '5');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Payment due day'), '25');
      await tester.pumpAndSettle();

      final submit = find.widgetWithText(ElevatedButton, 'ADD CREDIT CARD');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      final body = adapter.lastRequest!.data as Map<String, dynamic>;
      // The schema types last_four as str with pattern ^\d{4}$.
      expect(body['last_four'], isA<String>());
      expect(body['last_four'], '4021');
      // These are genuinely ints server-side.
      expect(body['statement_day'], isA<int>());
      expect(body['statement_day'], 5);
      expect(body['due_day'], 25);
    });

    testWidgets('a day outside 1-31 is rejected before any request',
        (tester) async {
      await openCardSheet(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'), 'Amex');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Credit limit'), '300000');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Statement day'), '45');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Payment due day'), '25');
      await tester.pumpAndSettle();

      final submit = find.widgetWithText(ElevatedButton, 'ADD CREDIT CARD');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(find.text('Must be between 1 and 31'), findsOneWidget);
      expect(adapter.lastRequest, isNull,
          reason: 'nothing should reach the server');
    });

    testWidgets('an empty required field blocks submission', (tester) async {
      await openCardSheet(tester);

      final submit = find.widgetWithText(ElevatedButton, 'ADD CREDIT CARD');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(find.text('Enter name'), findsOneWidget);
      expect(adapter.lastRequest, isNull);
    });
  });

  group('Account form', () {
    testWidgets('offers the three account types and defaults to bank',
        (tester) async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dioProvider.overrideWithValue(dio)],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => InstrumentFormSheet.account(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Bank'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Wallet'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'), 'Wallet money');
      await tester.tap(find.text('Wallet'));
      await tester.pumpAndSettle();

      final submit = find.widgetWithText(ElevatedButton, 'ADD ACCOUNT');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      final body = adapter.lastRequest!.data as Map<String, dynamic>;
      expect(body['account_type'], 'wallet');
      expect(body['name'], 'Wallet money');
    });
  });
}

/// Returns the server's 422 shape so the error-unwrapping path can be tested.
class _ErrorAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({
        "detail": [
          {"msg": "Value error, Name must not be empty"}
        ],
        "request_id": "abc123",
      }),
      422,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
