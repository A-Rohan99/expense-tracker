/// Accessibility guarantees.
///
/// The app had zero `Semantics` anywhere, a dozen `GestureDetector` controls
/// that announced as plain text with no button role or selected state, and
/// several tap targets under the 44dp minimum. These tests keep that from
/// coming back.
library;

import 'package:expense_tracker_app/core/theme.dart';
import 'package:expense_tracker_app/models/account.dart';
import 'package:expense_tracker_app/widgets/household_toggle.dart';
import 'package:expense_tracker_app/widgets/monthly_income_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Account _account() => Account(
      id: 'acc_1',
      userId: 'u1',
      name: 'HDFC Savings',
      accountType: AccountType.bank,
      currentBalance: 50000,
      currency: 'INR',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: child),
      ),
    );

void main() {
  group('HouseholdToggle', () {
    testWidgets('both options expose a button role and selected state',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(
        HouseholdToggle(isHousehold: false, onChanged: (_) {}),
      ));
      await tester.pumpAndSettle();

      // Colour alone used to convey which mode was active.
      expect(
        tester.getSemantics(find.bySemanticsLabel('private view')),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          hasEnabledState: false,
          label: 'private view',
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('household view')),
        matchesSemantics(
          isButton: true,
          isSelected: false,
          hasSelectedState: true,
          hasTapAction: true,
          hasEnabledState: false,
          label: 'household view',
        ),
      );
      handle.dispose();
    });

    testWidgets('selected state follows the active mode', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(
        HouseholdToggle(isHousehold: true, onChanged: (_) {}),
      ));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('household view')),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          label: 'household view',
        ),
      );
      handle.dispose();
    });

    testWidgets('each option meets the minimum tap target', (tester) async {
      await tester.pumpWidget(_wrap(
        HouseholdToggle(isHousehold: false, onChanged: (_) {}),
      ));
      await tester.pumpAndSettle();

      // Was roughly 30dp tall before.
      for (final label in ['PRIVATE', 'HOUSEHOLD']) {
        final size = tester.getSize(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ).first,
        );
        expect(size.height, greaterThanOrEqualTo(44.0), reason: label);
      }
    });
  });

  group('HouseholdToggle at phone width', () {
    testWidgets('expanded fills the row without overflowing 375dp',
        (tester) async {
      final handle = tester.ensureSemantics();
      // The dashboard header put the title, this toggle and the Manage
      // button on one row; at 375dp that overflowed by 45px. Narrow now
      // gives the toggle a line of its own, stretched.
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 375,
          child: HouseholdToggle(
            isHousehold: false,
            expanded: true,
            onChanged: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(HouseholdToggle)).width, 375);

      // Stretching must not cost the roles or the tap targets.
      for (final label in ['private view', 'household view']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      for (final label in ['PRIVATE', 'HOUSEHOLD']) {
        final size = tester.getSize(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ).first,
        );
        expect(size.height, greaterThanOrEqualTo(44.0), reason: label);
      }
      handle.dispose();
    });
  });

  group('MonthlyIncomeSheet day picker', () {
    testWidgets('each day cell is labelled and meets the tap target',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(
        MonthlyIncomeSheet(accounts: [_account()]),
      ));
      await tester.pumpAndSettle();

      // A bare "17" told a screen-reader user nothing about what it meant.
      expect(find.bySemanticsLabel('Day 17 of the month'), findsOneWidget);

      final cell = tester.getSize(
        find.ancestor(
          of: find.text('17'),
          matching: find.byType(AnimatedContainer),
        ).first,
      );
      // Was 38x34.
      expect(cell.width, greaterThanOrEqualTo(44.0));
      expect(cell.height, greaterThanOrEqualTo(44.0));
      handle.dispose();
    });

    testWidgets('the chosen day is announced as selected', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(
        MonthlyIncomeSheet(accounts: [_account()]),
      ));
      await tester.pumpAndSettle();

      // Defaults to the 1st.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Day 1 of the month')),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          label: 'Day 1 of the month',
        ),
      );

      await tester.tap(find.bySemanticsLabel('Day 17 of the month'));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Day 17 of the month')),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          label: 'Day 17 of the month',
        ),
      );
      handle.dispose();
    });
  });

  group('Layout under long content', () {
    testWidgets('a very long account name does not overflow the picker',
        (tester) async {
      // Names are user-supplied; several rows used to put an unconstrained
      // Text beside a fixed-width badge.
      final longName = 'A' * 120;
      await tester.pumpWidget(_wrap(
        MonthlyIncomeSheet(
          accounts: [
            Account(
              id: 'acc_long',
              userId: 'u1',
              name: longName,
              accountType: AccountType.bank,
              currentBalance: 1000,
              currency: 'INR',
              isActive: true,
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      // A RenderFlex overflow raises during layout, so reaching here clean
      // is the assertion.
      expect(tester.takeException(), isNull);
    });
  });
}
