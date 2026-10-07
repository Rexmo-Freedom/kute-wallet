// How a Hyperliquid chart opens: the interval a thin market steps up to,
// and the price range the autoscale fits when a bar or two stand far
// outside the rest of the tape.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_opening.dart';

HyperliquidCandle _bar(int i,
        {required double close,
        double? open,
        double? high,
        double? low,
        double volume = 10}) =>
    HyperliquidCandle(
      openTime: DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 300000),
      closeTime:
          DateTime.fromMillisecondsSinceEpoch(1700000299999 + i * 300000),
      open: open ?? close,
      high: high ?? close,
      low: low ?? close,
      close: close,
      volume: volume,
    );

/// A liquid tape: every bar trades, prices wander in a normal band.
List<HyperliquidCandle> _liquid(int n) => [
      for (var i = 0; i < n; i++)
        _bar(i,
            open: 85000 + (i % 9) * 40,
            close: 85000 + (i % 7) * 50,
            high: 85000 + (i % 7) * 50 + 120,
            low: 85000 + (i % 7) * 50 - 110),
    ];

/// A thin tape: carry-forward bars with no volume, [traded] of the newest
/// ones with a print.
List<HyperliquidCandle> _thin(int n, {required int traded}) => [
      for (var i = 0; i < n; i++)
        _bar(i, close: 318, volume: i >= n - traded ? 5 : 0),
    ];

void main() {
  group('thin tape', () {
    test('a liquid market is not thin', () {
      expect(hlTapeActivity(_liquid(240)), (visible: 100, traded: 100));
      expect(hlTapeIsThin(_liquid(240)), isFalse);
    });

    test('only the opening view counts, not older bars', () {
      // 140 traded bars long ago, the newest 100 all silent.
      final tape = [
        for (var i = 0; i < 240; i++)
          _bar(i, close: 318, volume: i < 140 ? 5 : 0),
      ];
      expect(hlTapeActivity(tape), (visible: 100, traded: 0));
      expect(hlTapeIsThin(tape), isTrue);
    });

    test('under 30% of the visible bars traded is thin', () {
      expect(hlTapeIsThin(_thin(240, traded: 29)), isTrue);
      expect(hlTapeIsThin(_thin(240, traded: 30)), isFalse);
    });

    test('under 20 traded bars is thin even when every bar traded', () {
      expect(hlTapeIsThin(_liquid(19)), isTrue);
      expect(hlTapeIsThin(_liquid(20)), isFalse);
    });
  });

  group('opening ladder', () {
    test('climbs 1m to 1D and stops there; 1W is left alone', () {
      expect(hlCoarserOpeningInterval('1m'), '5m');
      expect(hlCoarserOpeningInterval('5m'), '15m');
      expect(hlCoarserOpeningInterval('15m'), '1h');
      expect(hlCoarserOpeningInterval('1h'), '4h');
      expect(hlCoarserOpeningInterval('4h'), '1d');
      expect(hlCoarserOpeningInterval('1d'), isNull);
      expect(hlCoarserOpeningInterval('1w'), isNull);
    });

    test('a liquid market opens on the saved interval, in one look', () {
      final opening = HlChartOpening();
      expect(opening.onTapeLoaded(saved: '5m', candles: _liquid(240)), isFalse);
      expect(opening.settled, isTrue);
      expect(opening.stepped, isFalse);
      expect(opening.intervalFor('5m'), '5m');
    });

    test('a thin market steps up until enough bars traded', () {
      final opening = HlChartOpening();
      expect(
          opening.onTapeLoaded(saved: '5m', candles: _thin(240, traded: 2)),
          isTrue);
      expect(opening.intervalFor('5m'), '15m');
      expect(opening.settled, isFalse);
      expect(
          opening.onTapeLoaded(saved: '5m', candles: _thin(240, traded: 4)),
          isTrue);
      expect(opening.intervalFor('5m'), '1h');
      expect(
          opening.onTapeLoaded(saved: '5m', candles: _thin(240, traded: 12)),
          isTrue);
      expect(opening.intervalFor('5m'), '4h');
      // Enough of the 4h bars traded: this is where it opens.
      expect(
          opening.onTapeLoaded(saved: '5m', candles: _thin(240, traded: 45)),
          isFalse);
      expect(opening.settled, isTrue);
      expect(opening.intervalFor('5m'), '4h');
    });

    test('a market thin on every interval stops at 1D', () {
      final opening = HlChartOpening();
      var looks = 0;
      while (!opening.settled && looks < 10) {
        opening.onTapeLoaded(saved: '1m', candles: _thin(240, traded: 3));
        looks++;
      }
      expect(opening.intervalFor('1m'), '1d');
      expect(looks, 6);
    });

    test('a young market keeps the interval with more traded bars', () {
      // Listed a day ago: 15 traded 5m bars, which 15m merges into 6.
      final opening = HlChartOpening();
      expect(opening.onTapeLoaded(saved: '5m', candles: _liquid(15)), isTrue);
      expect(opening.intervalFor('5m'), '15m');
      expect(opening.onTapeLoaded(saved: '5m', candles: _liquid(6)), isTrue);
      expect(opening.settled, isTrue);
      expect(opening.stepped, isFalse);
      expect(opening.intervalFor('5m'), '5m');
    });

    test('an interval the user picks is never stepped', () {
      final opening = HlChartOpening()..userPicked();
      expect(
          opening.onTapeLoaded(saved: '5m', candles: _thin(240, traded: 1)),
          isFalse);
      expect(opening.intervalFor('5m'), '5m');
    });

    test('a pick after a step returns to the saved layout for good', () {
      final opening = HlChartOpening();
      opening.onTapeLoaded(saved: '5m', candles: _thin(240, traded: 2));
      expect(opening.intervalFor('5m'), '15m');
      opening.userPicked();
      expect(opening.intervalFor('5m'), '5m');
      expect(opening.intervalFor('1m'), '1m');
      expect(
          opening.onTapeLoaded(saved: '1m', candles: _thin(240, traded: 0)),
          isFalse);
      expect(opening.intervalFor('1m'), '1m');
    });

    test('a market that is not low liquidity is never stepped', () {
      final opening = HlChartOpening()..forMarket(lowLiquidity: false);
      expect(opening.settled, isTrue);
      expect(
          opening.onTapeLoaded(saved: '1m', candles: _thin(240, traded: 1)),
          isFalse);
      expect(opening.intervalFor('1m'), '1m');

      final thin = HlChartOpening()..forMarket(lowLiquidity: true);
      expect(thin.settled, isFalse);
    });

    test('another market decides again', () {
      final opening = HlChartOpening();
      opening.onTapeLoaded(saved: '5m', candles: _thin(240, traded: 2));
      opening.reset();
      expect(opening.settled, isFalse);
      expect(opening.intervalFor('5m'), '5m');
    });
  });

  group('outlier-aware range', () {
    test('a liquid market keeps its full fit', () {
      expect(hlOutlierAwareRange(_liquid(100), asLine: false), isNull);
      expect(hlOutlierAwareRange(_liquid(100), asLine: true), isNull);
    });

    test('a trend out of the early range keeps its full fit', () {
      final tape = [
        for (var i = 0; i < 100; i++)
          _bar(i,
              open: 100.0 + i,
              close: 101.0 + i,
              high: 102.0 + i,
              low: 99.0 + i),
      ];
      expect(hlOutlierAwareRange(tape, asLine: false), isNull);
      expect(hlOutlierAwareRange(tape, asLine: true), isNull);
    });

    test('a single stray bar does not flatten the rest', () {
      final tape = _liquid(100);
      // One print at a third of the price, mid-tape.
      tape[40] = _bar(40, open: 85100, close: 85050, high: 85200, low: 30000);
      final r = hlOutlierAwareRange(tape, asLine: false)!;
      // The body of the tape, not the stray low.
      expect(r.lo, greaterThan(84000));
      expect(r.hi, lessThan(86000));
      expect(r.hi - r.lo, lessThan(1000));
    });

    test('a stray close does not flatten a line chart', () {
      final tape = _liquid(100);
      tape[40] = _bar(40, close: 30000);
      final r = hlOutlierAwareRange(tape, asLine: true)!;
      expect(r.lo, greaterThan(84000));
      expect(r.hi, lessThan(86000));
    });

    test('a spike on the newest bar keeps the whole scale to its close', () {
      final tape = _liquid(100);
      tape[99] = _bar(99, open: 85100, close: 99000, high: 99000, low: 85000);
      final r = hlOutlierAwareRange(tape, asLine: false)!;
      // The price line sits on the newest close: it is always in range.
      expect(r.hi, 99000);
      expect(r.lo, greaterThan(84000));
    });

    test('a flat tape with one print has no body to fit', () {
      final tape = _thin(100, traded: 0);
      tape[98] = _bar(98, close: 300);
      expect(hlOutlierAwareRange(tape, asLine: true), isNull);
    });

    test('a short tape is fitted whole', () {
      final tape = _liquid(19);
      tape[5] = _bar(5, open: 85100, close: 85050, high: 85200, low: 30000);
      expect(hlOutlierAwareRange(tape, asLine: false), isNull);
    });
  });
}
