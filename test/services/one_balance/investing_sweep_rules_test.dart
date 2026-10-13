// Investing's input to the idle rule: anything open is activity now; at
// rest, the last recorded activity; first sight starts the window.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show kHlDefaultCross;
import 'package:kute/services/one_balance/investing_sweep_rules.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/sweep_rules.dart';
import 'package:kute/services/one_balance/venue_activity.dart';

void main() {
  final now = DateTime(2026, 10, 13, 12);

  setUp(() {
    VenueActivity.reset();
    VenueActivity.clock = () => now;
  });

  tearDown(() {
    VenueActivity.reset();
    VenueActivity.clock = DateTime.now;
  });

  test('an open position or a resting order is activity now', () {
    final dayAgo = now.subtract(const Duration(days: 2));
    VenueActivity.clock = () => dayAgo;
    VenueActivity.note(OneBalanceVenue.investing);
    VenueActivity.clock = () => now;
    expect(
        investingLastActivity(
            hasOpenPositions: true, hasRestingOrders: false, now: now),
        now);
    expect(
        investingLastActivity(
            hasOpenPositions: false, hasRestingOrders: true, now: now),
        now);
    // Never cross collateral, never a resting order's money: the cash stays.
    expect(venueKeepsCash(now, now), isTrue);
  });

  test('at rest: the last recorded activity, a day later it may go home', () {
    final dayAgo = now.subtract(const Duration(hours: 25));
    VenueActivity.clock = () => dayAgo;
    VenueActivity.note(OneBalanceVenue.investing);
    VenueActivity.clock = () => now;
    final at = investingLastActivity(
        hasOpenPositions: false, hasRestingOrders: false, now: now);
    expect(at, dayAgo);
    expect(venueKeepsCash(at, now), isFalse);
  });

  test('first sight of the cash starts (and records) the window', () {
    expect(VenueActivity.last(OneBalanceVenue.investing), isNull);
    final at = investingLastActivity(
        hasOpenPositions: false, hasRestingOrders: false, now: now);
    expect(at, now);
    expect(VenueActivity.last(OneBalanceVenue.investing), now);
    expect(venueKeepsCash(at, now), isTrue);
  });

  test('new perp positions open isolated by default', () {
    expect(kHlDefaultCross, isFalse);
  });
}
