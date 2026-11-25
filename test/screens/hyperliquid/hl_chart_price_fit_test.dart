// The price scale takes in everything drawn on the price, as TradingView's
// auto scale does: a Bollinger band is never cut flat at the plot's edge,
// on the page's chart and the Advanced chart alike, with the candles
// still readable after a big move. Only the scale's range moves: the plot
// keeps its size to the pixel. A drag on the price axis stays the person's
// own scale.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_advanced_layers.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_series.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/shared/charts/kute_chart_crosshair.dart';

import '../../helpers/hl_chart_edit_harness.dart';

/// Calm hours, then a 5% one-way move, then a few hours after it: the bands
/// are at their widest.
List<HyperliquidCandle> _bigMove({int count = 240}) {
  final start = DateTime.utc(2026, 10, 1);
  final out = <HyperliquidCandle>[];
  var price = 66000.0;
  for (var i = 0; i < count; i++) {
    final move = i >= count - 12 && i < count - 6
        ? -560.0
        : 40 * math.sin(i / 3) + 12 * math.cos(i / 1.3);
    final open = price;
    final close = open + move;
    out.add(HyperliquidCandle(
      openTime: start.add(Duration(hours: i)),
      closeTime: start.add(Duration(hours: i + 1)),
      open: open,
      high: math.max(open, close) + 30,
      low: math.min(open, close) - 30,
      close: close,
      volume: 50,
    ));
    price = close;
  }
  return out;
}

/// The volume profile layer maps through the shown domain: the way to read
/// it from outside (the chart's own painter is private).
({double lo, double hi, bool log}) _domain(WidgetTester tester) {
  final p = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<HlVolumeProfilePainter>()
      .single;
  return (lo: p.lo, hi: p.hi, log: p.log);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));
}

void _seed(WidgetTester tester, List<String> keys, {bool log = false}) {
  final c = hlEditContainer(tester);
  c.read(hlChartLayoutProvider.notifier).setStyle('candles');
  final prefs = c.read(hlChartPreferencesProvider(hlEditBtcKey).notifier);
  prefs.setIndicators(keys);
  prefs.setLogScale(log);
}

Rect _plot(WidgetTester tester) => tester.getRect(find.descendant(
    of: find.byType(HlCandlestickChart),
    matching: find.byType(KuteChartCrosshair)));

({double lo, double hi}) _span(List<double> a, [List<double>? b]) {
  var lo = double.infinity, hi = double.negativeInfinity;
  for (final v in [...a, ...?b]) {
    if (!v.isFinite) continue;
    lo = math.min(lo, v);
    hi = math.max(hi, v);
  }
  return (lo: lo, hi: hi);
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the fit', () {
    test('no indicators: the bars', () {
      expect(hlFitWithIndicators(100, 110, null, null), (lo: 100.0, hi: 110.0));
    });
    test('lines inside the bars leave it alone', () {
      expect(hlFitWithIndicators(100, 110, 102, 108), (lo: 100.0, hi: 110.0));
    });
    test('a band past the bars widens it on its own side', () {
      expect(hlFitWithIndicators(100, 110, 95, 108), (lo: 95.0, hi: 110.0));
      expect(hlFitWithIndicators(100, 110, 95, 118), (lo: 95.0, hi: 118.0));
    });
    test('the bars keep a quarter of the scale, the two sides sharing', () {
      // 10 of bars: at most 30 of widening. 90 and 30 asked: 22.5 and 7.5.
      final f = hlFitWithIndicators(100, 110, 10, 140);
      expect(f.lo, moreOrLessEquals(77.5));
      expect(f.hi, moreOrLessEquals(117.5));
      expect((110 - 100) / (f.hi - f.lo), moreOrLessEquals(kHlFitBarsMinShare));
    });
    test('on a log axis it works in ln space', () {
      final lo = math.log(100), hi = math.log(110);
      final f = hlFitWithIndicators(lo, hi, math.log(95), math.log(112));
      expect(f.lo, moreOrLessEquals(math.log(95)));
      expect(f.hi, moreOrLessEquals(math.log(112)));
    });
  });

  for (final advanced in [false, true]) {
    final where = advanced ? 'the Advanced chart' : "the page's chart";

    testWidgets('$where: Bollinger bands after a big move fit, and the '
        'candles stay readable', (tester) async {
      final tape = _bigMove();
      await pumpHlEditSheet(tester, candles: tape);
      _seed(tester, ['vol', 'bb', 'vp']);
      await _settle(tester);
      if (advanced) await enterHlEdit(tester);
      await _settle(tester);

      final d = _domain(tester);
      // The chart opens on its newest 100 bars.
      final b = hlBollinger(tape);
      final from = tape.length - 100;
      final band = _span(b.upper.sublist(from), b.lower.sublist(from));
      expect(d.lo, lessThan(band.lo), reason: 'the lower band is cut');
      expect(d.hi, greaterThan(band.hi), reason: 'the upper band is cut');
      // Readable: the visible bars keep a big share of the scale.
      final bars = tape.sublist(from);
      final barSpan = bars.map((k) => k.high).reduce(math.max) -
          bars.map((k) => k.low).reduce(math.min);
      expect(barSpan / (d.hi - d.lo), greaterThan(0.45));
    });

    testWidgets('$where: an indicator on the price never resizes the plot',
        (tester) async {
      await pumpHlEditSheet(tester, candles: _bigMove());
      _seed(tester, ['vol']);
      await _settle(tester);
      if (advanced) await enterHlEdit(tester);
      await _settle(tester);
      final without = _plot(tester);
      for (final on in [
        ['vol', 'bb'],
        ['vol', 'ichi'],
        ['vol', 'st', 'vwap', 'ema', 'ma'],
      ]) {
        _seed(tester, on);
        await _settle(tester);
        expect(_plot(tester), without, reason: '$on');
      }
    });
  }

  testWidgets('switching a wide one off tightens the scale again',
      (tester) async {
    await pumpHlEditSheet(tester, candles: _bigMove());
    _seed(tester, ['vol', 'vp', 'bb']);
    await _settle(tester);
    final wide = _domain(tester);
    _seed(tester, ['vol', 'vp']);
    await _settle(tester);
    final tight = _domain(tester);
    expect(tight.hi - tight.lo, lessThan(wide.hi - wide.lo));
  });

  testWidgets("Pivots: today's levels fit, and an older day's far ones don't "
      'stretch the scale', (tester) async {
    final tape = _bigMove();
    final daily = hlDailyFromBars(tape);
    await pumpHlEditSheet(tester, candles: tape, daily: daily);
    _seed(tester, ['vol', 'pp', 'vp']);
    await _settle(tester);
    final d = _domain(tester);
    final today = daily[daily.length - 2];
    final levels = HlPivotLevels.of(today.high, today.low, today.close);
    expect(d.hi, greaterThan(levels.r3));
    expect(d.lo, lessThan(levels.s3));
    // The candles still hold their quarter of the scale, margins aside.
    final bars = tape.sublist(tape.length - 100);
    final barSpan = bars.map((k) => k.high).reduce(math.max) -
        bars.map((k) => k.low).reduce(math.min);
    expect(barSpan / (d.hi - d.lo), greaterThan(kHlFitBarsMinShare * 0.8 - 0.01));
  });

  testWidgets('a log axis takes the bands in too', (tester) async {
    final tape = _bigMove();
    await pumpHlEditSheet(tester, candles: tape);
    _seed(tester, ['vol', 'bb', 'vp'], log: true);
    await _settle(tester);
    final d = _domain(tester);
    expect(d.log, isTrue);
    final b = hlBollinger(tape);
    final band =
        _span(b.upper.sublist(tape.length - 100), b.lower.sublist(tape.length - 100));
    expect(d.lo, lessThan(math.log(band.lo)));
    expect(d.hi, greaterThan(math.log(band.hi)));
  });

  testWidgets(
      'a drag on the price axis stays manual: indicators do not refit it, '
      'and a double tap goes back', (tester) async {
    await pumpHlEditSheet(tester, candles: _bigMove());
    _seed(tester, ['vol', 'vp']);
    await _settle(tester);
    await enterHlEdit(tester);
    await _settle(tester);
    final before = _domain(tester);

    // The tag column at the plot's right.
    final plot = _plot(tester);
    final at = Offset(plot.right + 12, plot.center.dy);
    final g = await tester.startGesture(at);
    await tester.pump(const Duration(milliseconds: 50));
    await g.moveBy(const Offset(0, 30));
    await tester.pump();
    await g.moveBy(const Offset(0, 60));
    await tester.pump();
    await g.up();
    await _settle(tester);
    final manual = _domain(tester);
    expect(manual.hi - manual.lo, greaterThan(before.hi - before.lo));

    _seed(tester, ['vol', 'vp', 'bb']);
    await _settle(tester);
    final still = _domain(tester);
    expect(still.lo, moreOrLessEquals(manual.lo));
    expect(still.hi, moreOrLessEquals(manual.hi));
  });
}
