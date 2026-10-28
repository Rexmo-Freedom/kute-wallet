// The chart's market-signals layer: absent unless the host hands signals
// in, drawn through the chart's own geometry, and a tapped tag reports
// its id. No signal label sits over the candles: the levels' tags are in
// the tag column, the dates' names, the upcoming dates' tags and the
// caption in the band under the plot; none is ever cut with "…".

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

KuteChartSignalBandPainter _band(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<KuteChartSignalBandPainter>()
    .single;

Finder get _bandBox => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is KuteChartSignalBandPainter);

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
    // The three levels are tappable on the plot, the pinned date in the
    // band under it; nothing else is.
    expect(painter.hits.map((h) => h.id),
        unorderedEquals(['level:0', 'level:1', 'level:2']));
    expect(_band(tester).hits.map((h) => h.id), ['date:0']);
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
    // In the tag column, past the end of the candles.
    for (final hit in painter.hits) {
      expect(
          hit.rect.left, greaterThanOrEqualTo(size.width - painter.tagColumn),
          reason: '${hit.id} covers the candles');
      expect(hit.rect.right, lessThanOrEqualTo(size.width + 0.01));
    }
    // The band is under the plot.
    final band = tester.getRect(_bandBox);
    expect(band.top, greaterThanOrEqualTo(origin.dy + size.height - 0.01));
    final date = _band(tester).hits.single;
    expect(date.rect.right, lessThanOrEqualTo(band.width + 0.01));
    await tester.tapAt(band.topLeft + date.rect.center);
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
    // All in the tag column; the caption is in the band under the plot.
    final layer = tester.getSize(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is KuteChartSignalsPainter));
    final column = _painters(tester).single.tagColumn;
    for (final h in hits) {
      expect(h.rect.left, greaterThanOrEqualTo(layer.width - column));
    }
    expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is KuteChartSignalBandPainter),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // BTC on 4h: funding flipped three times in two days, and "Funding −",
  // "Funding +", "Funding −" were written through each other.
  testWidgets(
      'dates close together: the latest keeps its name, none is '
      'written through another', (tester) async {
    await _pump(
      tester,
      signals: const ChartSignals(dates: [
        ChartSignalDate(timeMs: _t0 + 40 * 60000, label: 'Funding −'),
        ChartSignalDate(timeMs: _t0 + 41 * 60000, label: 'Funding +'),
        ChartSignalDate(timeMs: _t0 + 42 * 60000, label: 'Funding −'),
        ChartSignalDate(timeMs: _t0 + 10 * 60000, label: 'Funding +'),
      ]),
    );
    final spans = <Rect>[];
    expect(
      tester.renderObject(_bandBox),
      paints
        ..everything((method, args) {
          if (method == #drawParagraph) {
            final p = args[0] as dynamic;
            final o = args[1] as Offset;
            spans.add(Rect.fromLTWH(
                o.dx, o.dy, p.longestLine as double, p.height as double));
            expect(p.didExceedMaxLines as bool, isFalse);
          }
          return true;
        }),
    );
    // The far one and the latest of the three close together.
    expect(spans, hasLength(2));
    expect(spans[0].overlaps(spans[1]), isFalse);
    expect(tester.takeException(), isNull);
  });

  test(
      'a label that does not fit writes its shorter text, then a smaller '
      'font, never an ellipsis', () {
    final c = kuteSignalCandidates('Fed decision · Oct 28', 'Fed decision');
    expect(c.first, (text: 'Fed decision · Oct 28', fontSize: 9.5));
    expect(c[1], (text: 'Fed decision', fontSize: 9.5));
    expect(c[2].fontSize, lessThan(9.5));
    for (final x in c) {
      expect(x.text, isNot(contains('…')));
    }
  });
}
