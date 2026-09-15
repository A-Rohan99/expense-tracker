/// Widget tests for [LoginScreen] — form rendering, mode switching, and
/// client-side validation. None of these hit the network.
library;

import 'package:expense_tracker_app/core/theme.dart';
import 'package:expense_tracker_app/providers/auth_providers.dart';
import 'package:expense_tracker_app/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every test pumpAndSettles after mounting: the brand mark's entrance
/// animation leaves a pending timer that a bare pump() would trip over.
Widget _harness() => ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const LoginScreen(),
      ),
    );

void main() {
  group('LoginScreen', () {
    testWidgets('starts in sign-in mode without the full-name field',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('SIGN IN'), findsOneWidget);
      // Full name belongs to sign-up only.
      expect(find.text('Full name'), findsNothing);
    });

    testWidgets('switching to Create account reveals the full-name field',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('CREATE ACCOUNT'), findsOneWidget);
      expect(find.text('SIGN IN'), findsNothing);
    });

    testWidgets('submitting an empty form shows validation errors',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('SIGN IN'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
    });

    testWidgets('rejects a malformed email and a too-short password',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
      await tester.enterText(find.byType(TextFormField).at(1), 'short');
      await tester.tap(find.text('SIGN IN'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Must be at least 8 characters'), findsOneWidget);
    });

    testWidgets('validation errors clear as the user corrects the field',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('SIGN IN'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your email'), findsOneWidget);

      // autovalidateMode: onUserInteraction should drop the error immediately.
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'someone@example.com',
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter your email'), findsNothing);
    });
  });

  group('AuthController', () {
    test('setMode flips the form and clears any standing error', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(authControllerProvider.notifier);
      expect(container.read(authControllerProvider).isSignUp, isFalse);

      controller.setMode(AuthMode.signUp);
      expect(container.read(authControllerProvider).isSignUp, isTrue);
      expect(container.read(authControllerProvider).errorMessage, isNull);
    });
  });
}
