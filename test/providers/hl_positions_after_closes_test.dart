// A perp closed in full leaves the account's positions the moment the
// close fills, not on the next account read (founder, 10 November 2026, on
// 2.2.0 (101): "after selling an investment ... it still shows up in the
// Overview for some seconds"): a read that still shows it at its size
// before the close (the poll in flight, or the account's previous answer
// given again while it refreshes) keeps it off, until a read shows it gone
// or at another size, or the hold runs out.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlPerpPosition;
import 'package:kute/providers/hyperliquid_trading_provider.dart';

HlPerpPosition _perp(String coin, double szi) => HlPerpPosition(
    coin: coin,
    szi: szi,
    entryPx: 180,
    positionValue: szi.abs() * 180,
    unrealizedPnl: 0,
    returnOnEquity: 0,
    liquidationPx: null,
    marginUsed: 10,
    leverageType: 'cross',
    leverageValue: 1,
    maxLeverage: 10);

void main() {
  final now = DateTime(2026, 11, 10, 12);
  final closed = <String, HlClosedInFull>{
    'xyz:NVDA': (szi: -0.06, at: now.subtract(const Duration(seconds: 2))),
  };
  List<String> coins(List<HlPerpPosition> ps) => [for (final p in ps) p.coin];

  test('nothing closed: the read as it is', () {
    final read = [_perp('BTC', 0.01)];
    final out = hlPositionsAfterCloses(read, const {}, now: now);
    expect(identical(out.positions, read), isTrue);
    expect(out.held, isEmpty);
  });

  test(
      'a stale read (the closed perp at its size before the close) keeps '
      'it off, and the close held', () {
    final out = hlPositionsAfterCloses(
        [_perp('BTC', 0.01), _perp('xyz:NVDA', -0.06)], closed,
        now: now);
    expect(coins(out.positions), ['BTC']);
    expect(out.held.keys, ['xyz:NVDA']);
  });

  test('a read without it: the close indexed, let go', () {
    final out = hlPositionsAfterCloses([_perp('BTC', 0.01)], closed, now: now);
    expect(coins(out.positions), ['BTC']);
    expect(out.held, isEmpty);
  });

  test(
      'a new position of the coin (another size or side) shows, and the '
      'close is let go', () {
    for (final szi in [-0.1, 0.06]) {
      final out =
          hlPositionsAfterCloses([_perp('xyz:NVDA', szi)], closed, now: now);
      expect(coins(out.positions), ['xyz:NVDA']);
      expect(out.held, isEmpty);
    }
  });

  test('past the hold the venue\'s read wins', () {
    final out = hlPositionsAfterCloses([_perp('xyz:NVDA', -0.06)], closed,
        now: now.add(kHlClosedInFullHold));
    expect(coins(out.positions), ['xyz:NVDA']);
    expect(out.held, isEmpty);
  });

  test('only the closed dex\'s perp: another dex\'s Nvidia stays', () {
    final out =
        hlPositionsAfterCloses([_perp('io:NVDA', -0.06)], closed, now: now);
    expect(coins(out.positions), ['io:NVDA']);
    expect(out.held, isEmpty);
  });
}
