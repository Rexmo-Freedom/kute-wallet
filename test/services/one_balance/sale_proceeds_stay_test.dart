// Sale proceeds stay on the venue they were sold on (founder, 9 November
// 2026: "Sell we keep in the venue, we have to"): a position closed or
// sold releases its cash, and the sweeper, automatic sweeping off, only
// reads the venues; nothing is sent. Only the Portfolio's Rebalance moves
// venue cash home. Standing orders never reach the sweeper at all.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/one_balance/venue_sweeper.dart';

void main() {
  test('automatic sweeping is off: a sale releases, nothing is swept', () {
    expect(kVenueAutoSweepEnabled, isFalse);
    // The sweeper as the app builds it (no autoSweep argument) does not
    // sweep on its own: `trigger` previews, `sweepNow` is Rebalance alone.
    final source = File('lib/services/one_balance/venue_sweeper.dart')
        .readAsStringSync();
    expect(source, contains('if (!autoSweep) {'));
    expect(source, contains('await preview();\n      return;'));
    expect(source, contains('const bool kVenueAutoSweepEnabled = false;'));
  });

  test('a sale emits a release, never a sweep or a withdrawal', () {
    final pm = File('lib/providers/polymarket_trading_provider.dart')
        .readAsStringSync();
    final hl = File('lib/providers/hyperliquid_trading_provider.dart')
        .readAsStringSync();
    for (final s in [pm, hl]) {
      expect(s, contains('VenueCashReleased.emit('));
      expect(s, isNot(contains('sweepNow(')));
      expect(s, isNot(contains('.rebalance(')));
    }
  });

  test('standing orders never sweep, withdraw or touch the sweeper', () {
    final dir = Directory('lib/services/standing_orders');
    for (final f in dir.listSync().whereType<File>()) {
      final s = f.readAsStringSync();
      for (final forbidden in [
        'venue_sweeper',
        'sweepNow',
        'rebalance',
        'withdrawUsdc',
        'VenueCashReleased',
        "'orchestra.swap'",
      ]) {
        expect(s, isNot(contains(forbidden)), reason: '${f.path}: $forbidden');
      }
    }
  });
}
