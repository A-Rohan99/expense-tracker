/// Tests for the transaction list screen.
///
/// Search used to apply on submit only, so typing into the box appeared to do
/// nothing at all until the user happened to press the keyboard's search key.
/// These pin the debounce, the query shaping behind it, and the edit/delete
/// calls the screen makes.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:expense_tracker_app/core/api_service.dart';
import 'package:expense_tracker_app/core/theme.dart';
import 'package:expense_tracker_app/models/transaction.dart';
import 'package:expense_tracker_app/providers/transaction_list_providers.dart';
import 'package:expense_tracker_app/screens/transactions_screen.dart';
import 'package:expense_tracker_app/widgets/transaction_edit_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every GET with one transaction and records what was asked for.
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode([
        {
          'id': 'txn_1',
          'user_id': 'u1',
          'transaction_type': 'expense',
          'amount': '1451.00',
          'currency': 'INR',
          'category': 'Groceries',
          'description': 'Sunday farmers market',
          'transaction_date': '2026-09-15',
          'is_household_shared': false,
          'created_at': '2026-09-15T00:00:00Z',
        }
      ]),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _RecordingAdapter adapter;

  setUp(() => adapter = _RecordingAdapter());

  // Riverpod 3 does not export a public `Override` type name; let it infer.
  overrides() {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    return [dioProvider.overrideWithValue(dio)];
  }

  Widget wrap() => ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const TransactionsScreen(),
        ),
      );

  group('TransactionFilter query shaping', () {
    test('an empty filter asks only for the sort and scope', () {
      final query =
          const TransactionFilter().toQuery(includeHousehold: false);
      expect(query['sort'], 'date_desc');
      expect(query['include_household'], false);
      expect(query.containsKey('search'), isFalse);
      expect(query.containsKey('transaction_type'), isFalse);
      expect(query.containsKey('start_date'), isFalse);
    });

    test('dates are sent as zero-padded ISO days', () {
      final query = const TransactionFilter()
          .copyWith(
            startDate: DateTime(2026, 1, 5),
            endDate: DateTime(2026, 12, 31),
          )
          .toQuery(includeHousehold: true);
      expect(query['start_date'], '2026-01-05');
      expect(query['end_date'], '2026-12-31');
      expect(query['include_household'], true);
    });

    test('type and search are passed through when set', () {
      final query = const TransactionFilter()
          .copyWith(search: 'goa', type: TransactionType.expense)
          .toQuery(includeHousehold: false);
      expect(query['search'], 'goa');
      expect(query['transaction_type'], 'expense');
    });

    test('copyWith clears a field rather than leaving it unchanged', () {
      // The sentinel exists so `null` means "clear", not "keep".
      final filtered = const TransactionFilter().copyWith(search: 'goa');
      expect(filtered.copyWith(search: null).search, isNull);
      expect(filtered.copyWith(type: TransactionType.income).search, 'goa');
    });

    test('isFiltered ignores sort, which is never a filter', () {
      expect(const TransactionFilter().isFiltered, isFalse);
      expect(
        const TransactionFilter(sort: TransactionSort.amountAsc).isFiltered,
        isFalse,
      );
      expect(const TransactionFilter(search: 'x').isFiltered, isTrue);
    });
  });

  group('Search box', () {
    testWidgets('typing issues a search request without pressing enter',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      final initial = adapter.requests.length;
      await tester.enterText(find.byType(TextField), 'goa');
      // Before the debounce elapses nothing should have gone out.
      await tester.pump(const Duration(milliseconds: 100));
      expect(adapter.requests.length, initial);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(adapter.requests.last.queryParameters['search'], 'goa');
    });

    testWidgets('a typing burst collapses into one request', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      final initial = adapter.requests.length;
      for (final term in ['g', 'go', 'goa']) {
        await tester.enterText(find.byType(TextField), term);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(adapter.requests.length - initial, 1);
      expect(adapter.requests.last.queryParameters['search'], 'goa');
    });

    testWidgets('clearing the filters does not restore a pending term',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'goa');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear'));
      // Long enough for a stale debounce to have fired.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(adapter.requests.last.queryParameters.containsKey('search'),
          isFalse);
      expect(find.text('Clear'), findsNothing);
    });
  });

  group('Filter chips', () {
    testWidgets('picking Expenses narrows the request', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Expenses'));
      await tester.pumpAndSettle();

      expect(adapter.requests.last.queryParameters['transaction_type'],
          'expense');

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(
        adapter.requests.last.queryParameters.containsKey('transaction_type'),
        isFalse,
      );
    });
  });

  group('Edit sheet layout', () {
    testWidgets('category chips wrap instead of filling the row',
        (tester) async {
      // Each chip was a Container with `alignment` set and no width, which
      // stretches to the incoming maxWidth — so the Wrap laid out 10 chips
      // in 10 full-width rows.
      await tester.pumpWidget(ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: TransactionEditSheet(
                transaction: TransactionModel(
                  id: 'txn_1',
                  userId: 'u1',
                  transactionType: TransactionType.expense,
                  amount: 32000,
                  currency: 'INR',
                  category: 'Travel',
                  transactionDate: DateTime(2026, 9, 15),
                  isHouseholdShared: false,
                  createdAt: DateTime(2026, 9, 15),
                  updatedAt: DateTime(2026, 9, 15),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final groceries = tester.getSize(
        find.ancestor(
          of: find.text('Groceries'),
          matching: find.byType(AnimatedContainer),
        ).first,
      );
      expect(groceries.height, greaterThanOrEqualTo(44.0));
      expect(groceries.width, lessThan(200.0),
          reason: 'a chip should hug its label, not fill the sheet');

      // Two chips fitting on one line is what the Wrap is for.
      final dining = tester.getTopLeft(find.text('Dining'));
      expect(dining.dy, tester.getTopLeft(find.text('Groceries')).dy);
    });
  });

  group('Editing', () {
    test('update PATCHes only the mutable metadata', () async {
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);

      await c.read(transactionEditControllerProvider.notifier).update(
            id: 'txn_1',
            category: 'Dining',
            date: DateTime(2026, 3, 9),
          );

      final sent = adapter.requests.last;
      expect(sent.method, 'PATCH');
      expect(sent.path, '/transactions/txn_1');
      final body = sent.data as Map;
      expect(body['category'], 'Dining');
      expect(body['transaction_date'], '2026-03-09');
      // Amount and instrument links are immutable server-side.
      expect(body.containsKey('amount'), isFalse);
      expect(body.containsKey('description'), isFalse);
    });

    test('remove DELETEs the entry', () async {
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);

      final ok =
          await c.read(transactionEditControllerProvider.notifier).remove('t9');
      expect(ok, isTrue);
      expect(adapter.requests.last.method, 'DELETE');
      expect(adapter.requests.last.path, '/transactions/t9');
    });
  });
}
