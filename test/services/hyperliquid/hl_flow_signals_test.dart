// Pressure, big trades, funding flips, the next funding payment and the
// in-session open-interest signal.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart';
import 'package:kute/services/hyperliquid/insights/hl_flow_signals.dart';

HlTrade _trade(int t, double usd, {bool buy = true}) => HlTrade(
      coin: 'BTC',
      side: buy ? 'B' : 'A',
      px: 100,
      sz: usd / 100,
      time: t,
      hash: '0x',
    );

void main() {
  group('pressure', () {
    test('needs enough trades, then is the bought share of notional', () {
      final flow = HlTradeFlow();
      for (var i = 0; i < 10; i++) {
        flow.add(_trade(1000 + i, 100));
      }
      expect(flow.pressure(2000), isNull);
      for (var i = 0; i < 10; i++) {
        flow.add(_trade(2000 + i, 300, buy: false));
      }
      final p = flow.pressure(3000)!;
      expect(p.trades, 20);
      expect(p.buyShare, closeTo(1000 / 4000, 1e-9));
    });

    test('trades leave the window after five minutes', () {
      final flow = HlTradeFlow();
      for (var i = 0; i < 30; i++) {
        flow.add(_trade(1000 + i, 100));
      }
      expect(flow.pressure(2000), isNotNull);
      expect(flow.pressure(2000 + kHlPressureWindow.inMilliseconds), isNull);
    });

    test('a replayed older trade is dropped', () {
      final flow = HlTradeFlow();
      for (var i = 0; i < 20; i++) {
        flow.add(_trade(5000 + i, 100));
      }
      flow.add(_trade(1000, 1e9, buy: false));
      expect(flow.pressure(6000)!.buyShare, 1);
    });
  });

  group('big trades', () {
    HlTradeFlow seeded() {
      final flow = HlTradeFlow();
      for (var i = 0; i < kHlBigTradeMinBaseline; i++) {
        flow.add(_trade(1000 + i, 100));
      }
      return flow;
    }

    test('nothing is big before the baseline exists', () {
      final flow = HlTradeFlow();
      flow.add(_trade(1000, 100));
      flow.add(_trade(1001, 1e7));
      expect(flow.bigTrades, isEmpty);
    });

    test('big is a multiple of the market\'s own median trade', () {
      final flow = seeded();
      flow.add(_trade(5000, 100 * kHlBigTradeMultiple - 1));
      expect(flow.bigTrades, isEmpty);
      flow.add(_trade(5001, 100 * kHlBigTradeMultiple, buy: false));
      expect(flow.bigTrades.single.notional, 100 * kHlBigTradeMultiple);
      expect(flow.bigTrades.single.isBuy, isFalse);
    });

    test('the cap keeps the largest', () {
      final flow = seeded();
      for (var i = 0; i < kHlBigTradeMaxMarkers; i++) {
        flow.add(_trade(6000 + i, 10000.0 + i));
      }
      expect(flow.bigTrades, hasLength(kHlBigTradeMaxMarkers));
      // Smaller than every marker kept: no room.
      flow.add(_trade(7000, 9000));
      expect(flow.bigTrades.any((b) => b.notional == 9000), isFalse);
      // Larger: replaces the smallest.
      final revision = flow.bigRevision;
      flow.add(_trade(7001, 50000));
      expect(flow.bigTrades, hasLength(kHlBigTradeMaxMarkers));
      expect(flow.bigTrades.any((b) => b.notional == 10000), isFalse);
      expect(flow.bigTrades.last.notional, 50000);
      expect(flow.bigRevision, greaterThan(revision));
    });
  });

  group('funding', () {
    List<HlFundingPoint> hours(List<double> rates) => [
          for (var i = 0; i < rates.length; i++)
            (timeMs: i * 3600000, rate: rates[i])
        ];

    test('a flip must hold three hours', () {
      const p = 0.00001, n = -0.00001;
      final flips = hlFundingFlips(hours([
        p, p, p, p, // positive
        n, p, p, // one negative hour: noise
        n, n, n, n, // negative for good
        p, p, p,
      ]));
      expect(flips.map((f) => (f.timeMs ~/ 3600000, f.longsPay)),
          [(7, false), (11, true)]);
    });

    test('a steady sign has no flips; nor does an empty history', () {
      expect(hlFundingFlips(hours(List.filled(48, 0.00001))), isEmpty);
      expect(hlFundingFlips(const []), isEmpty);
    });

    test('at most the newest six', () {
      final rates = <double>[];
      for (var i = 0; i < 10; i++) {
        rates.addAll(List.filled(3, i.isEven ? 0.00001 : -0.00001));
      }
      final flips = hlFundingFlips(hours(rates));
      expect(flips, hasLength(kHlFundingFlipMax));
      expect(flips.last.timeMs, 27 * 3600000);
    });

    test('funding settles at the top of the next hour', () {
      expect(hlNextFundingTime(DateTime.utc(2026, 10, 4, 20, 37, 12)),
          DateTime.utc(2026, 10, 4, 21));
      expect(hlNextFundingTime(DateTime.utc(2026, 10, 4, 23, 59, 59)),
          DateTime.utc(2026, 10, 5));
    });

    test('longs pay a positive rate, shorts a negative one', () {
      final long = hlFundingEstimate(
          positionValue: 10000, isLong: true, rate: 0.0000125);
      expect(long.pays, isTrue);
      expect(long.amount, closeTo(0.125, 1e-9));
      expect(
          hlFundingEstimate(
                  positionValue: 10000, isLong: false, rate: 0.0000125)
              .pays,
          isFalse);
      expect(
          hlFundingEstimate(
                  positionValue: -10000, isLong: false, rate: -0.00002)
              .pays,
          isTrue);
    });
  });

  group('open interest', () {
    const minute = 60000;

    test('no signal until it has been watched for ten minutes', () {
      final t = HlOiTracker();
      t.sample(0, 1000);
      t.sample(5 * minute, 1100);
      expect(t.signal, isNull);
      t.sample(10 * minute, 1100);
      expect(t.signal!.rising, isTrue);
      expect(t.signal!.change, closeTo(0.10, 1e-9));
      expect(t.signal!.minutes, 10);
    });

    test('a small drift is not a signal', () {
      final t = HlOiTracker();
      t.sample(0, 1000);
      t.sample(12 * minute, 1005);
      expect(t.signal, isNull);
    });

    test('falling, and only over the last half hour', () {
      final t = HlOiTracker();
      t.sample(0, 2000); // an old high that ages out
      for (var m = 1; m <= 60; m++) {
        t.sample(m * minute, m < 30 ? 1000 : 1000 - (m - 30) * 2);
      }
      final s = t.signal!;
      expect(s.rising, isFalse);
      expect(s.minutes, lessThanOrEqualTo(31));
      expect(s.change, closeTo(-0.06, 0.005));
    });

    test('samples closer than thirty seconds are skipped', () {
      final t = HlOiTracker();
      t.sample(0, 1000);
      t.sample(1000, 5000);
      t.sample(11 * minute, 1000);
      expect(t.signal, isNull);
    });
  });
}
