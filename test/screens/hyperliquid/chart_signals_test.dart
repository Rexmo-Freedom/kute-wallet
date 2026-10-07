// The chart's market-signals layer: absent unless the host hands signals
// in, drawn through the chart's own geometry, and a tapped tag reports
// its id.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/shared/charts/kute_chart_signals.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/theme/app_theme.dart';

const _t0 = 1700000000000;

List<HyperliquidCandle> _candles(int n) => [
      for (var i = 0; i < n; i++)
        HyperliquidCandle(
          openTime: DateTime.fromMillisecondsSinceEpoch(_t0 + i * 60000),
          closeTime: DateTime.fromMillisecondsSinceEpoch(_t0 + (i + 1) * 60000),
          open: 100 + (i % 7).toDouble(),
          high: 103 + (i % 7).toDouble(),
          low: 98 + (i % 7).toDouble(),
          close: 101 + (i % 5).toDouble(),
          volume: 10,
        ),
    ];

Future<void> _pump(WidgetTester tester,
    {ChartSignals signals = ChartSignals.none,
    ValueChanged<String>? onTapped}) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
          fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
      home: Scaffold(
          body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 400,
          child: HlCandlestickChart(
            marketKey: 'hl:perp::BTC',
            candles: _candles(60),
            height: 240,
            showVolume: false,
            showSummary: false,
            signals: signals,
            onSignalTapped: onTapped,
          ),
        ),
      )),
    ),
  ));
  await tester.pump();
}

Iterable<KuteChartSignalsPainter> _painters(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<KuteChartSignalsPainter>();

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('no signals, no layer: the chart is as it was', (tester) async {
    await _pump(tester);
    expect(_painters(tester), isEmpty);
  });

  testWidgets('levels, dates and dots paint; a tapped tag reports its id',
      (tester) async {
    final tapped = <String>[];
    await _pump(
      tester,
      onTapped: tapped.add,
      signals: const ChartSignals(
        levels: [
          // On the scale, above it and below it.
          ChartSignalLevel(id: 'level:0', price: 103, label: '↑ 56% by Oct 31'),
          ChartSignalLevel(id: 'level:1', price: 500, label: '↑ 4% by Oct 31'),
          ChartSignalLevel(id: 'level:2', price: 1, label: '↓ 3% by Oct 31'),
        ],
        dates: [
          // In view, behind the tape, and ahead of it (pinned, tappable).
          ChartSignalDate(timeMs: _t0 + 30 * 60000, label: 'Funding +'),
          ChartSignalDate(timeMs: _t0 - 999 * 60000, label: 'Funding −'),
          ChartSignalDate(
              timeMs: _t0 + 9999 * 60000,
              label: 'Fed decision · Oct 28',
              id: 'date:0',
              pinWhenAhead: true),
        ],
        dots: [
          ChartSignalDot(timeMs: _t0 + 40 * 60000, price: 102, isBuy: true),
        ],
        caption: 'Open interest rising: +2.0% in 12 min',
      ),
    );
    final painter = _painters(tester).single;
    // The three levels and the pinned date are tappable; nothing else is.
    expect(painter.hits.map((h) => h.id),
        unorderedEquals(['level:0', 'level:1', 'level:2', 'date:0']));
    final surface = find.descendant(
        of: find.byType(HlCandlestickChart),
        matching: find.byWidgetPredicate(
            (w) => w is GestureDetector && w.onPanUpdate != null));
    final origin = tester.getTopLeft(surface);
    final size = tester.getSize(surface);
    for (final hit in painter.hits) {
      expect(Offset.zero & size, (Rect r) => r.overlaps(hit.rect),
          reason: '${hit.id} is on the plot');
    }
    final level = painter.hits.firstWhere((h) => h.id == 'level:0');
    await tester.tapAt(origin + level.rect.center);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, ['level:0']);
    // The level's tag sits at its price on the chart's own scale.
    final geom = painter.resolveGeometry(size)!;
    expect(level.rect.center.dy, closeTo(geom.yForPrice(103), 1));
    final date = painter.hits.firstWhere((h) => h.id == 'date:0');
    await tester.tapAt(origin + date.rect.center);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, ['level:0', 'date:0']);
  });

  // BTC on 1h with the Predictions levels on: "68% by Oct 31" was off the
  // top of the scale and pinned there, "91% by Oct 31" sat on its own
  // line just under the top, and one tag was written over the other.
  testWidgets('level tags never cover each other: pinned, near the top, '
      'close in price', (tester) async {
    await _pump(
      tester,
      signals: const ChartSignals(
        caption: 'Open interest +2.1% in 30m',
        levels: [
          ChartSignalLevel(id: 'a', price: 500, label: '↑ 68% by Oct 31'),
          ChartSignalLevel(id: 'b', price: 104.6, label: '↑ 91% by Oct 31'),
          ChartSignalLevel(id: 'c', price: 104.4, label: '↑ 88% by Oct 24'),
          ChartSignalLevel(id: 'd', price: 97.2, label: '↓ 82% by Oct 31'),
          ChartSignalLevel(id: 'e', price: 20, label: '↓ 60% by Oct 31'),
        ],
      ),
    );
    final hits = _painters(tester).single.hits;
    expect(hits.map((h) => h.id), ['a', 'b', 'c', 'd', 'e']);
    for (var i = 0; i < hits.length; i++) {
      for (var j = i + 1; j < hits.length; j++) {
        expect(hits[i].rect.overlaps(hits[j].rect), isFalse,
            reason: '${hits[i].id} over ${hits[j].id}');
      }
    }
    // The caption keeps the top line to itself.
    for (final h in hits) {
      expect(h.rect.top, greaterThanOrEqualTo(4 + 14));
    }
    expect(tester.takeException(), isNull);
  });

  // BTC on 4h: funding flipped three times in two days, and "Funding −",
  // "Funding +", "Funding −" were written through each other.
  group('the names of dates close together', () {
    test('the latest keeps its name; one that would run into it does not',
        () {
      final kept = signalDateLabelsKept([
        (left: 100, width: 52),
        (left: 110, width: 52),
        (left: 124, width: 52),
      ]);
      expect(kept, [2]);
    });

    test('names with room are all written', () {
      final kept = signalDateLabelsKept([
        (left: 10, width: 52),
        (left: 200, width: 52),
        (left: 100, width: 52),
      ]);
      expect(kept.toSet(), {0, 1, 2});
    });

    test('of four, every other one fits', () {
      final kept = signalDateLabelsKept([
        (left: 0, width: 52),
        (left: 40, width: 52),
        (left: 80, width: 52),
        (left: 120, width: 52),
      ]);
      expect(kept, [3, 1]);
    });
  });
}
