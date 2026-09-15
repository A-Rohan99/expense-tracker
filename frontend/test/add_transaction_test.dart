/// Tests for the transaction capture path.
///
/// The controller tests pin the request body shape — that's where a silent
/// mistake would cost a wrong ledger entry. The widget tests cover the rule
/// that income can't be sourced from a credit card.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:expense_tracker_app/core/api_service.dart';
import 'package:expense_tracker_app/core/theme.dart';
import 'package:expense_tracker_app/models/account.dart';
import 'package:expense_tracker_app/models/credit_card.dart';
import 'package:expense_tracker_app/models/transaction.dart';
import 'package:expense_tracker_app/providers/transaction_providers.dart';
import 'package:expense_tracker_app/widgets/add_transaction_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures the outgoing request instead of hitting the network.
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  int statusCode = 201;
  Object responseBody = const {'id': 'txn_1'};

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

ProviderContainer _containerWith(_CapturingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
    ..httpClientAdapter = adapter;
  final container = ProviderContainer(
    overrides: [dioProvider.overrideWithValue(dio)],
  );
  addTearDown(container.dispose);
  return container;
}

Account _account(String id, String name, {double balance = 1000}) => Account(
      id: id,
      userId: 'u1',
      name: name,
      accountType: AccountType.bank,
      currentBalance: balance,
      currency: 'INR',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );

CreditCard _card(String id, String name) => CreditCard(
      id: id,
      userId: 'u1',
      name: name,
      lastFour: '4021',
      totalLimit: 100000,
      statementDay: 5,
      dueDay: 25,
      currency: 'INR',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      unbilledAmount: 0,
      billedAmount: 0,
      availableLimit: 100000,
    );

void main() {
  group('TransactionController', () {
    test('an account-sourced expense sends account_id, not credit_card_id',
        () async {
      final adapter = _CapturingAdapter();
      final container = _containerWith(adapter);

      final ok = await container
          .read(transactionControllerProvider.notifier)
          .createTransaction(
            type: TransactionType.expense,
            amount: 250.5,
            category: 'Groceries',
            sourceKind: SourceKind.account,
            sourceId: 'acc_1',
            description: 'Weekly shop',
            date: DateTime(2026, 3, 7),
          );

      expect(ok, isTrue);
      final body = adapter.lastRequest!.data as Map<String, dynamic>;
      expect(adapter.lastRequest!.path, '/transactions/');
      expect(body['transaction_type'], 'expense');
      expect(body['amount'], 250.5);
      expect(body['category'], 'Groceries');
      expect(body['account_id'], 'acc_1');
      expect(body.containsKey('credit_card_id'), isFalse);
      // Date must be a plain YYYY-MM-DD, zero-padded.
      expect(body['transaction_date'], '2026-03-07');
    });

    test('a card-sourced expense sends credit_card_id, not account_id',
        () async {
      final adapter = _CapturingAdapter();
      final container = _containerWith(adapter);

      await container
          .read(transactionControllerProvider.notifier)
          .createTransaction(
            type: TransactionType.expense,
            amount: 1200,
            category: 'Travel',
            sourceKind: SourceKind.creditCard,
            sourceId: 'card_1',
          );

      final body = adapter.lastRequest!.data as Map<String, dynamic>;
      expect(body['credit_card_id'], 'card_1');
      expect(body.containsKey('account_id'), isFalse);
    });

    test('a blank description is omitted rather than sent empty', () async {
      final adapter = _CapturingAdapter();
      final container = _containerWith(adapter);

      await container
          .read(transactionControllerProvider.notifier)
          .createTransaction(
            type: TransactionType.income,
            amount: 5000,
            category: 'Salary',
            sourceKind: SourceKind.account,
            sourceId: 'acc_1',
            description: '   ',
          );

      final body = adapter.lastRequest!.data as Map<String, dynamic>;
      expect(body.containsKey('description'), isFalse);
      expect(body['is_household_shared'], isFalse);
    });

    test('a server validation error surfaces without the pydantic prefix',
        () async {
      final adapter = _CapturingAdapter()
        ..statusCode = 422
        ..responseBody = {
          'detail': [
            {'msg': 'Value error, Income transactions require an account_id'}
          ]
        };
      final container = _containerWith(adapter);

      final ok = await container
          .read(transactionControllerProvider.notifier)
          .createTransaction(
            type: TransactionType.income,
            amount: 100,
            category: 'Salary',
            sourceKind: SourceKind.account,
            sourceId: 'acc_1',
          );

      expect(ok, isFalse);
      expect(
        container.read(transactionControllerProvider).errorMessage,
        'Income transactions require an account_id',
      );
    });
  });

  group('AddTransactionSheet', () {
    Widget harness({List<Account>? accounts, List<CreditCard>? cards}) {
      final dio = Dio()..httpClientAdapter = _CapturingAdapter();
      return ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: AddTransactionSheet(
              accounts: accounts ?? [_account('acc_1', 'HDFC Salary')],
              cards: cards ?? [_card('card_1', 'Amex Platinum')],
            ),
          ),
        ),
      );
    }

    testWidgets('opens on Expense and offers cards as a source',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('RECORD EXPENSE'), findsOneWidget);
      expect(find.text('PAID FROM'), findsOneWidget);
      expect(find.text('Amex Platinum'), findsOneWidget);
      expect(find.text('HDFC Salary'), findsOneWidget);
    });

    testWidgets('switching to Income drops credit cards from the sources',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();

      expect(find.text('RECORD INCOME'), findsOneWidget);
      expect(find.text('RECEIVED INTO'), findsOneWidget);
      // Income can only land in an account.
      expect(find.text('Amex Platinum'), findsNothing);
      expect(find.text('HDFC Salary'), findsOneWidget);
    });

    testWidgets('category chips swap with the transaction type',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Salary'), findsNothing);

      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();

      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
    });

    testWidgets('submitting with no amount shows an error and sends nothing',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // The sheet is taller than the default test surface.
      await tester.ensureVisible(find.text('RECORD EXPENSE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RECORD EXPENSE'));
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount greater than zero'), findsOneWidget);
    });

    testWidgets('with no accounts the submit button is disabled',
        (tester) async {
      await tester.pumpWidget(harness(accounts: [], cards: []));
      await tester.pumpAndSettle();

      expect(
        find.text('No accounts yet — add one before recording transactions.'),
        findsOneWidget,
      );
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'RECORD EXPENSE'),
      );
      expect(button.onPressed, isNull);
    });
  });
}
