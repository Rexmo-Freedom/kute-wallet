// Two-finger pinch in editing mode: fingers together with the whole tape
// on screen asks the host for more history; fingers apart narrows the
// visible window; and a drawing that one finger started is dropped the
// moment the second finger lands, so a pinch never places anything.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/theme/app_theme.dart';

List<HyperliquidCandle> _candles(int n) => [
      for (var i = 0; i < n; i++)
        HyperliquidCandle(
          openTime:
              DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 60000),
          closeTime:
              DateTime.fromMillisecondsSinceEpoch(1700000060000 + i * 60000),
          open: 100 + (i % 7).toDouble(),
          high: 103 + (i % 7).toDouble(),
          low: 98 + (i % 7).toDouble(),
          close: 101 + (i % 5).toDouble(),
          volume: 10,
        ),
    ];

Finder get _surface => find.descendant(
    of: find.byType(HlCandlestickChart),
    matching: find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onPanUpdate != null));

KuteChartDrawingsPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<KuteChartDrawingsPainter>()
    .single;

/// A saved level keeps the drawings painter mounted, so its geometry can
/// be read even while nothing is being drawn.
const _level = ChartDrawing(
  id: 'level',
  tool: ChartDrawingTool.level,
  points: [ChartDrawingPoint(timeMs: 1700000000000, price: 101)],
);

Future<void> _pumpChart(
  WidgetTester tester, {
  required List<HyperliquidCandle> candles,
  VoidCallback? onMoreHistoryWanted,
  ValueChanged<ChartDrawing>? onPlaced,
  ChartDrawingTool? tool = ChartDrawingTool.trendline,
}) async {
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
            key: const ValueKey('chart'),
            marketKey: 'hl:perp::BTC',
            candles: candles,
            height: 240,
            drawingMode: true,
            armedTool: tool,
            drawings: const [_level],
            showVolume: false,
            onDrawingPlaced: onPlaced,
            onMoreHistoryWanted: onMoreHistoryWanted,
          ),
        ),
      )),
    ),
  ));
  await tester.pump();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('fingers apart narrows the window; together asks for history',
      (tester) async {
    var asked = 0;
    await _pumpChart(tester,
        candles: _candles(120), onMoreHistoryWanted: () => asked++);
    final origin = tester.getTopLeft(_surface);
    final size = tester.getSize(_surface);
    // Every chart opens on its newest 100 bars, like TradingView.
    expect(_painter(tester).resolveGeometry(size)!.timesMs, hasLength(100));

    // Zoom in: two fingers move apart.
    final a = await tester.startGesture(origin + const Offset(150, 100));
    final b = await tester.startGesture(origin + const Offset(250, 100));
    await tester.pump();
    await a.moveTo(origin + const Offset(50, 100));
    await tester.pump();
    await b.moveTo(origin + const Offset(350, 100));
    await tester.pump();
    final zoomed = _painter(tester).resolveGeometry(size)!.timesMs;
    expect(zoomed.length, lessThan(120));
    expect(zoomed.length, greaterThanOrEqualTo(12));
    // The newest bar stays on the right edge.
    expect(zoomed.last, 1700000000000 + 119 * 60000);
    await a.up();
    await b.up();
    await tester.pump();
    expect(asked, 0);

    // Zoom out past the loaded tape: two fingers move together.
    final c = await tester.startGesture(origin + const Offset(50, 100));
    final d = await tester.startGesture(origin + const Offset(350, 100));
    await tester.pump();
    await c.moveTo(origin + const Offset(120, 100));
    await tester.pump();
    await d.moveTo(origin + const Offset(280, 100));
    await tester.pump();
    await c.moveTo(origin + const Offset(190, 100));
    await tester.pump();
    await d.moveTo(origin + const Offset(210, 100));
    await tester.pump();
    expect(_painter(tester).resolveGeometry(size)!.timesMs, hasLength(120));
    expect(asked, greaterThanOrEqualTo(1));
    await c.up();
    await d.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second finger cancels the drawing the first one started',
      (tester) async {
    final placed = <ChartDrawing>[];
    await _pumpChart(tester, candles: _candles(60), onPlaced: placed.add);
    final origin = tester.getTopLeft(_surface);
    final a = await tester.startGesture(origin + const Offset(60, 80));
    await a.moveTo(origin + const Offset(120, 100));
    await tester.pump();
    expect(_painter(tester).draft, isNotNull);
    final b = await tester.startGesture(origin + const Offset(250, 100));
    await tester.pump();
    expect(_painter(tester).draft, isNull);
    await a.moveTo(origin + const Offset(40, 100));
    await b.moveTo(origin + const Offset(300, 100));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pump();
    expect(placed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one finger on empty chart scrolls back in time in select mode',
      (tester) async {
    var asked = 0;
    await _pumpChart(tester,
        candles: _candles(120), tool: null, onMoreHistoryWanted: () => asked++);
    final origin = tester.getTopLeft(_surface);
    final size = tester.getSize(_surface);

    // Zoom in first so there is history off the left edge to scroll to.
    final a = await tester.startGesture(origin + const Offset(150, 100));
    final b = await tester.startGesture(origin + const Offset(250, 100));
    await tester.pump();
    await a.moveTo(origin + const Offset(50, 100));
    await b.moveTo(origin + const Offset(350, 100));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pump();
    final zoomed = _painter(tester).resolveGeometry(size)!.timesMs;
    expect(zoomed.length, lessThan(120));
    expect(zoomed.last, 1700000000000 + 119 * 60000);

    // Drag right on empty chart (well away from the level's handle):
    // the window slides back so the newest bar leaves the right edge.
    final drag = await tester.startGesture(origin + const Offset(100, 30));
    await drag.moveTo(origin + const Offset(300, 30));
    await tester.pump();
    final scrolled = _painter(tester).resolveGeometry(size)!.timesMs;
    expect(scrolled.length, zoomed.length);
    expect(scrolled.last, lessThan(zoomed.last));
    await drag.up();
    await tester.pump();
    expect(asked, 0);
    expect(tester.takeException(), isNull);
  });
}
