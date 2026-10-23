// What Investments can spend: Dollars plus the venue cash the engine can
// reach (before costs) for the From row, and a Max the engine's own plan
// always covers.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/one_balance/investments_spendable.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';

VenueCashCandidate _c(OneBalanceVenue venue, double usd,
        {double minimum = 1}) =>
    (
      venue: venue,
      availableUsd: usd,
      eta: kVenuePullEta[venue]!,
      minimumUsd: minimum,
    );

void main() {
  test('Dollars alone: the total and Max are Dollars', () {
    final s = investmentsSpendable(dollarsUsd: 42.5, sources: const []);
    expect(s.totalUsd, 42.5);
    expect(s.maxUsd, 42.5);
    expect(s.venueCashUsd, 0);
  });

  test('venue cash counts before costs on the row, after costs in Max', () {
    final s = investmentsSpendable(dollarsUsd: 10, sources: [
      _c(OneBalanceVenue.predictions, 60),
      _c(OneBalanceVenue.investing, 40, minimum: 5),
    ]);
    expect(s.totalUsd, 110);
    // 60 x 0.98 + (40 x 0.98 - 0.30) = 58.80 + 38.90.
    expect(s.maxUsd, closeTo(107.70, 1e-9));
    expect(
        planDollarsShortfall(neededUsd: s.maxUsd, dollarsUsd: 10, sources: [
          _c(OneBalanceVenue.predictions, 60),
          _c(OneBalanceVenue.investing, 40, minimum: 5),
        ]).covers,
        isTrue);
  });

  test('a venue under its route minimum is not spendable', () {
    final s = investmentsSpendable(dollarsUsd: 10, sources: [
      _c(OneBalanceVenue.predictions, 0.6),
      _c(OneBalanceVenue.investing, 4, minimum: 5),
    ]);
    expect(s.totalUsd, 10);
    expect(s.maxUsd, 10);
  });

  test('Max is always an amount the plan covers', () {
    final random = math.Random(7);
    for (var i = 0; i < 500; i++) {
      final dollars = (random.nextDouble() * 50 * 100).floor() / 100;
      final sources = [
        _c(OneBalanceVenue.predictions,
            (random.nextDouble() * 300 * 100).floor() / 100),
        _c(OneBalanceVenue.investing,
            (random.nextDouble() * 300 * 100).floor() / 100,
            minimum: 5),
      ];
      final s = investmentsSpendable(dollarsUsd: dollars, sources: sources);
      expect(s.maxUsd, lessThanOrEqualTo(s.totalUsd + 1e-9));
      expect(s.maxUsd, greaterThanOrEqualTo(dollars));
      expect(
          planDollarsShortfall(
                  neededUsd: s.maxUsd, dollarsUsd: dollars, sources: sources)
              .covers,
          isTrue,
          reason: '$s from $sources');
    }
  });
}
