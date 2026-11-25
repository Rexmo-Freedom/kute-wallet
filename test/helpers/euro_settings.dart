// A person with euros in Settings and a rate far from 1: Dollars money must
// still read in dollars, the figures equal to the USD input. Shared by the
// "dollars stay dollars" tests of the Portfolio, the Dollars tabs and the
// slips.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:money2/money2.dart';

/// $1 is €0.92, so a stray conversion shows in any figure.
Override euroRateOverride() => selectedCurrencyProviderFromUSD('EUR')
    .overrideWith((_) => Money.fromFixed(Fixed.parse('0.92'), isoCode: 'EUR'));

/// No euro anywhere on screen, rolling figures included.
void expectNoEuroOnScreen(WidgetTester tester) {
  expect(find.textContaining('€', findRichText: true), findsNothing);
  for (final w in tester.widgetList<RollingNumberText>(
      find.byType(RollingNumberText, skipOffstage: false))) {
    expect(w.text, isNot(contains('€')));
  }
  for (final w in tester
      .widgetList<RollingFigure>(find.byType(RollingFigure, skipOffstage: false))) {
    expect(w.text, isNot(contains('€')));
  }
}
