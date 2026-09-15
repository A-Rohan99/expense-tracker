/// Tests for the standing monthly income UI and its request shaping.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:expense_tracker_app/core/api_service.dart';
import 'package:expense_tracker_app/core/theme.dart';
import 'package:expense_tracker_app/models/account.dart';
import 'package:expense_tracker_app/models/recurring_income.dart';
import 'package:expense_tracker_app/providers/recurring_income_providers.dart';
import 'package:expense_tracker_app/widgets/monthly_income_card.dart';
import 'package:expense_tracker_app/widgets/monthly_income_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  int statusCode = 201;
  Object? responseBody = const {'id': 'ri_1'};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(responseBody),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Account _account(String id, String name) => Account(
      id: id,
      userId: 'u1',
      name: name,
      accountType: AccountType.bank,
      currentBalance: 50000,
      currency: 'INR',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );

RecurringIncome _income({int day = 1, double amount = 185000}) =>
    RecurringIncome(
      id: 'ri_1',
      accountId: 'acc_1',
      name: 'Salary',
      amount: amount,
      dayOfMonth: day,
      category: 'Salary',
      currency: 'INR',
      isHouseholdShared: false,
      isActive: true,
      accountName: 'HDFC Salary',
      nextDueDate: DateTime.now().add(const Duration(days: 5)),
    );

void main() {
  group('RecurringIncome model', () {
    test('parses the server payload including computed fields', () {
      final income = RecurringIncome.fromJson({
        'id': 'ri_1',
        'user_id': 'u1',
        'account_id': 'acc_1',
        'name': 'Salary',
        'amount': '185000.00',
        'day_of_month': 25,
        'category': 'Salary',
        'currency': 'INR',
        'is_household_shared': false,
        'is_active': true,
        'last_posted_period': '2026-08',
        'next_due_date': '2026-09-25',
        'account_name': 'HDFC Salary',
        'posted_this_run': 2,
      });

      expect(income.amount, 185000.0);
      expect(income.dayOfMonth, 25);
      expect(income.lastPostedPeriod, '2026-08');
      expect(income.nextDueDate, DateTime(2026, 9, 25));
      expect(income.accountName, 'HDFC Salary');
      expect(income.postedThisRun, 2);
    });

    test('renders the pay day as an ordinal', () {
      expect(_income(day: 1).dayLabel, '1st');
      expect(_income(day: 2).dayLabel, '2nd');
      expect(_income(day: 3).dayLabel, '3rd');
      expect(_income(day: 4).dayLabel, '4th');
      // The teens are the case a naive `% 10` gets wrong.
      expect(_income(day: 11).dayLabel, '11th');
      expect(_income(day: 12).dayLabel, '12th');
      expect(_income(day: 13).dayLabel, '13th');
      expect(_income(day: 21).dayLabel, '21st');
      expect(_income(day: 31).dayLabel, '31st');
    });
  });

  group('RecurringIncomeController', () {
    ProviderContainer containerWith(_CapturingAdapter adapter) {
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter;
      final c = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('creating POSTs the amount, day and account', () async {
      final adapter = _CapturingAdapter();
      final container = containerWith(adapter);

      final ok = await container
          .read(recurringIncomeControllerProvider.notifier)
          .save(
            existingId: null,
            amount: 185000,
            dayOfMonth: 25,
            accountId: 'acc_1',
            name: 'Salary',
          );

      expect(ok, isTrue);
      expect(adapter.lastRequest!.method, 'POST');
      expect(adapter.lastRequest!.path, '/recurring-income/');
      final body = adapter.lastRequest!.data as Map<String, dynamic>;
      expect(body['amount'], 185000);
      expect(body['day_of_month'], 25);
      expect(body['account_id'], 'acc_1');
      expect(body['name'], 'Salary');
    });

    test('editing an existing instruction PATCHes instead of POSTing',
        () async {
      final adapter = _CapturingAdapter()..statusCode = 200;
      final container = containerWith(adapter);

      await container.read(recurringIncomeControllerProvider.notifier).save(
            existingId: 'ri_1',
            amount: 200000,
            dayOfMonth: 5,
            accountId: 'acc_2',
          );

      expect(adapter.lastRequest!.method, 'PATCH');
      expect(adapter.lastRequest!.path, '/recurring-income/');
    });

    test('a duplicate setup surfaces the server message', () async {
      final adapter = _CapturingAdapter()
        ..statusCode = 409
        ..responseBody = {
          'detail': 'Monthly income is already set up. Update it instead.'
        };
      final container = containerWith(adapter);

      final ok = await container
          .read(recurringIncomeControllerProvider.notifier)
          .save(
            existingId: null,
            amount: 1000,
            dayOfMonth: 5,
            accountId: 'acc_1',
          );

      expect(ok, isFalse);
      expect(
        container.read(recurringIncomeControllerProvider).errorMessage,
        'Monthly income is already set up. Update it instead.',
      );
    });

    test('removing DELETEs the instruction', () async {
      final adapter = _CapturingAdapter()
        ..statusCode = 204
        ..responseBody = null;
      final container = containerWith(adapter);

      await container.read(recurringIncomeControllerProvider.notifier).remove();
      expect(adapter.lastRequest!.method, 'DELETE');
    });
  });

  group('MonthlyIncomeCard', () {
    Widget harness(RecurringIncome? income) => ProviderScope(
          overrides: [
            recurringIncomeProvider.overrideWith((ref) async => income),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: MonthlyIncomeCard(
                  accounts: [_account('acc_1', 'HDFC Salary')],
                ),
              ),
            ),
          ),
        );

    testWidgets('with nothing set up it shows the set-up call to action',
        (tester) async {
      await tester.pumpWidget(harness(null));
      await tester.pumpAndSettle();

      expect(find.text('MONTHLY INCOME'), findsOneWidget);
      expect(find.text('SET MONTHLY INCOME'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('once configured it shows the amount, day and account',
        (tester) async {
      await tester.pumpWidget(harness(_income(day: 25)));
      await tester.pumpAndSettle();

      expect(find.textContaining('1,85,000'), findsOneWidget);
      expect(
        find.textContaining('every month on the 25th'),
        findsOneWidget,
      );
      expect(find.textContaining('HDFC Salary'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('SET MONTHLY INCOME'), findsNothing);
    });

    testWidgets('it reports months the server posted in the background',
        (tester) async {
      final income = RecurringIncome(
        id: 'ri_1',
        accountId: 'acc_1',
        name: 'Salary',
        amount: 185000,
        dayOfMonth: 1,
        category: 'Salary',
        currency: 'INR',
        isHouseholdShared: false,
        isActive: true,
        accountName: 'HDFC Salary',
        postedThisRun: 3,
      );
      await tester.pumpWidget(harness(income));
      await tester.pumpAndSettle();

      expect(find.text('Just added 3 months of income'), findsOneWidget);
    });
  });

  group('MonthlyIncomeSheet', () {
    Widget harness({RecurringIncome? existing, List<Account>? accounts}) {
      final dio = Dio()..httpClientAdapter = _CapturingAdapter();
      return ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: MonthlyIncomeSheet(
              accounts: accounts ?? [_account('acc_1', 'HDFC Salary')],
              existing: existing,
            ),
          ),
        ),
      );
    }

    testWidgets('new setup asks how much, which day, and where',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('SET UP MONTHLY INCOME'), findsOneWidget);
      expect(find.text('HOW MUCH'), findsOneWidget);
      expect(find.text('WHICH DAY OF THE MONTH'), findsOneWidget);
      expect(find.text('PAID INTO'), findsOneWidget);
      expect(find.text('SET UP INCOME'), findsOneWidget);
    });

    testWidgets('picking a day updates the summary line', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('Every month on the 1st'), findsOneWidget);

      await tester.tap(find.text('17'));
      await tester.pumpAndSettle();

      expect(find.text('Every month on the 17th'), findsOneWidget);
    });

    testWidgets('a day past 28 warns about shorter months', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.textContaining('last day instead'), findsNothing);

      await tester.tap(find.text('31'));
      await tester.pumpAndSettle();

      expect(find.textContaining('last day instead'), findsOneWidget);
    });

    testWidgets('editing prefills and offers to stop the income',
        (tester) async {
      await tester.pumpWidget(harness(existing: _income(day: 25)));
      await tester.pumpAndSettle();

      expect(find.text('EDIT MONTHLY INCOME'), findsOneWidget);
      expect(find.text('SAVE CHANGES'), findsOneWidget);
      expect(find.text('Stop monthly income'), findsOneWidget);
      expect(find.text('Every month on the 25th'), findsOneWidget);
      expect(find.text('185000'), findsOneWidget);
    });

    testWidgets('saving with no amount is rejected', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('SET UP INCOME'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SET UP INCOME'));
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount greater than zero'), findsOneWidget);
    });
  });
}
