/// The typeface is bundled, not fetched.
///
/// Every text style used to come from `google_fonts`, which downloads from
/// fonts.gstatic.com on first launch — so the app rendered in a system
/// fallback until the request landed, and never got the right typeface
/// offline. The files now ship in `assets/fonts/`, which puts their SIL OFL
/// licence obligations on us.
library;

import 'package:expense_tracker_app/core/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bundled fonts', () {
    test('the theme names the bundled families', () {
      final theme = buildAppTheme();
      expect(theme.textTheme.displayLarge?.fontFamily, 'SpaceGrotesk');
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
    });

    test('every declared weight is in the bundle', () async {
      for (final family in ['SpaceGrotesk', 'Inter']) {
        for (final weight in [400, 500, 600, 700]) {
          final bytes =
              await rootBundle.load('assets/fonts/$family-$weight.ttf');
          expect(bytes.lengthInBytes, greaterThan(0),
              reason: '$family $weight');
        }
      }
    });

    test('the OFL licence ships with each family', () async {
      for (final family in ['SpaceGrotesk', 'Inter']) {
        final text = await rootBundle.loadString('assets/fonts/$family-OFL.txt');
        expect(text, contains('SIL OPEN FONT LICENSE'), reason: family);
      }
    });
  });
}
