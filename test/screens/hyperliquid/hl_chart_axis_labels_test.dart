// The modern Investing chart's pure helpers (hl_charts.dart): the price
// axis' few labels (hlPriceAxisLabels), the merged bars a crowded window
// is drawn from (hlResampleCandles) and the low volume band's height.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';

HyperliquidCandle _bar(int i,
        {required double open,
        required double close,
        required double high,
        required double low,
        double volume = 1}) =>
    HyperliquidCandle(
      openTime: DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 60000),
      closeTime:
          DateTime.fromMillisecondsSinceEpoch(1700000059999 + i * 60000),
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume,
    );

void main() {
  group('hlPriceAxisLabels', () {
    test('BTC: three round thousands-grouped levels, no dollar sign', () {
      final labels = hlPriceAxisLabels(86135, 86185, decimals: 0);
      expect(labels.map((l) => l.text).toList(), ['86,140', '86,160', '86,180']);
      expect(labels.map((l) => l.value).toList(), [86140, 86160, 86180]);
    });

    test('never more than three labels', () {
      for (final (lo, hi, d) in [
        (0.0, 100.0, 0),
        (85900.0, 86440.0, 0),
        (3900.0, 3960.0, 1),
        (0.0122, 0.0131, 6),
        (211.5, 213.0, 2),
      ]) {
        expect(hlPriceAxisLabels(lo, hi, decimals: d).length,
            lessThanOrEqualTo(3),
            reason: '$lo..$hi');
      }
      expect(hlPriceAxisLabels(0, 100, decimals: 0, maxLabels: 5).length,
          lessThanOrEqualTo(5));
    });

    test('the asset\'s own decimals, every label alike', () {
      expect(hlPriceAxisLabels(3900, 3960, decimals: 1).map((l) => l.text),
          ['3,900.0', '3,950.0']);
      expect(hlPriceAxisLabels(0.0122, 0.0131, decimals: 4).map((l) => l.text),
          ['0.0125', '0.0130']);
      // Four halves would be one too many: whole numbers instead.
      expect(hlPriceAxisLabels(211.5, 213, decimals: 2).map((l) => l.text),
          ['212.00', '213.00']);
    });

    test('a range that dips under zero is clamped at zero, never "-0"', () {
      final labels = hlPriceAxisLabels(-5, 10, decimals: 0);
      expect(labels, isNotEmpty);
      for (final l in labels) {
        expect(l.value, greaterThanOrEqualTo(0));
        expect(l.text, isNot(startsWith('-')));
      }
      expect(labels.map((l) => l.text), contains('0'));
      final small = hlPriceAxisLabels(-0.004, 0.012, decimals: 2);
      expect(small.map((l) => l.text), ['0.00', '0.01']);
      for (final l in small) {
        expect(l.text, isNot(contains('-0')));
      }
    });

    test('nothing on a degenerate range or one finer than the precision',
        () {
      expect(hlPriceAxisLabels(5, 5, decimals: 0), isEmpty);
      expect(hlPriceAxisLabels(7, 5, decimals: 0), isEmpty);
      expect(hlPriceAxisLabels(double.nan, 5, decimals: 0), isEmpty);
      expect(hlPriceAxisLabels(-3, -1, decimals: 0), isEmpty);
      // Whole-number precision on a range inside one unit: no label.
      expect(hlPriceAxisLabels(1.1, 1.9, decimals: 0), isEmpty);
    });

    test('a sweep: at most three, ascending, in range, none negative', () {
      final rnd = math.Random(7);
      for (var i = 0; i < 2000; i++) {
        final lo = (rnd.nextDouble() - 0.1) * math.pow(10, rnd.nextInt(7));
        final hi = lo + rnd.nextDouble() * lo.abs() * 0.2 + 1e-6;
        final d = rnd.nextInt(7);
        final labels = hlPriceAxisLabels(lo, hi, decimals: d);
        expect(labels.length, lessThanOrEqualTo(3), reason: '$lo..$hi d$d');
        for (var j = 0; j < labels.length; j++) {
          final l = labels[j];
          expect(l.value, greaterThanOrEqualTo(0));
          expect(l.value, greaterThanOrEqualTo(math.max(lo, 0) - 1e-6));
          expect(l.value, lessThanOrEqualTo(hi + 1e-6));
          expect(l.text, isNot(startsWith('-')));
          if (j > 0) expect(l.value, greaterThan(labels[j - 1].value));
        }
      }
    });
  });

  group('hlResampleCandles', () {
    final tape = [
      for (var i = 0; i < 10; i++)
        _bar(i,
            open: 100.0 + i,
            close: 100.5 + i,
            high: 101.0 + i + (i == 4 ? 50 : 0),
            low: 99.0 + i - (i == 7 ? 30 : 0),
            volume: 1.0 + i),
    ];

    test('a window that fits is itself', () {
      expect(hlResampleGroup(100, 100), 1);
      expect(hlResampleGroup(5, 100), 1);
      expect(identical(hlResampleCandles(tape, 10), tape), isTrue);
      expect(identical(hlResampleCandles(tape, 50), tape), isTrue);
    });

    test('groups just big enough to fit, never more bars than asked', () {
      expect(hlResampleGroup(101, 100), 2);
      expect(hlResampleGroup(96, 70), 2);
      expect(hlResampleGroup(300, 100), 3);
      expect(hlResampleGroup(1000, 87), 12);
      for (final maxBars in [1, 2, 3, 4, 7, 9]) {
        final out = hlResampleCandles(tape, maxBars);
        expect(out.length, lessThanOrEqualTo(maxBars), reason: 'max $maxBars');
        expect(out.length, (10 / hlResampleGroup(10, maxBars)).ceil());
      }
    });

    test('open of the first, close of the last, max high, min low, summed '
        'volume, the span\'s times', () {
      final out = hlResampleCandles(tape, 4); // groups of 3: 3, 3, 3, 1
      expect(out.length, 4);
      final a = out[0];
      expect(a.open, tape[0].open);
      expect(a.close, tape[2].close);
      expect(a.high, tape[2].high);
      expect(a.low, tape[0].low);
      expect(a.volume, tape[0].volume + tape[1].volume + tape[2].volume);
      expect(a.openTime, tape[0].openTime);
      expect(a.closeTime, tape[2].closeTime);
      // The spike at bar 4 and the dip at bar 7 survive the merge.
      expect(out[1].high, tape[4].high);
      expect(out[2].low, tape[7].low);
      // The short last group is the one bar.
      final z = out[3];
      expect(z.open, tape[9].open);
      expect(z.close, tape[9].close);
      expect(z.volume, tape[9].volume);
    });

    test('how many bars a plot draws: one per 4 px', () {
      expect(hlMaxBars(400), 100);
      expect(hlMaxBars(350), 87);
      expect(hlMaxBars(2), 1);
    });
  });

  test('the volume band is low: 16% of the plot, 40 px at most', () {
    expect(hlVolumeBandHeight(260), 40);
    expect(hlVolumeBandHeight(200), 32);
    expect(hlVolumeBandHeight(0), 0);
  });
}
