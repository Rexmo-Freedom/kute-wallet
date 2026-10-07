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

List<HyperliquidCandle> _candles({double scale = 1}) => [
      for (var i = 0; i < 10; i++)
        HyperliquidCandle(
          openTime:
              DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 60000),
          closeTime:
              DateTime.fromMillisecondsSinceEpoch(1700000060000 + i * 60000),
          open: (100 + i) * scale,
          high: (102 + i) * scale,
          low: (98 + i) * scale,
          close: (101 + i) * scale,
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

Future<void> _pumpChart(
  WidgetTester tester, {
  String marketKey = 'hl:perp::BTC',
  ChartDrawingTool? tool = ChartDrawingTool.trendline,
  List<HyperliquidCandle>? candles,
  List<ChartDrawing> drawings = const [],
  String? selected,
  ValueChanged<ChartDrawing>? onPlaced,
  ValueChanged<ChartDrawing>? onUpdated,
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
            marketKey: marketKey,
            candles: candles ?? _candles(),
            height: 240,
            drawingMode: true,
            armedTool: tool,
            drawings: drawings,
            selectedDrawingId: selected,
            showVolume: false,
            onDrawingPlaced: onPlaced,
            onDrawingUpdated: onUpdated,
          ),
        ),
      )),
    ),
  ));
  await tester.pump();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('trendline starts at finger down, not after the drag threshold',
      (tester) async {
    final placed = <ChartDrawing>[];
    await _pumpChart(tester, onPlaced: placed.add);
    final origin = tester.getTopLeft(_surface);
    final gesture = await tester.startGesture(origin + const Offset(60, 80));
    await gesture.moveTo(origin + const Offset(95, 90));
    await tester.pump();
    await gesture.moveTo(origin + const Offset(190, 140));
    await tester.pump();
    final painter = _painter(tester);
    final geom = painter.resolveGeometry(tester.getSize(_surface))!;
    expect(geom.offsetFor(painter.draft!.points.first).dx, closeTo(60, 0.01));
    expect(geom.offsetFor(painter.draft!.points.first).dy, closeTo(80, 0.01));
    await gesture.up();
    await tester.pump();
    expect(placed, hasLength(1));
    expect(geom.offsetFor(placed.single.points.last).dx, closeTo(190, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel discards a partial drawing', (tester) async {
    final placed = <ChartDrawing>[];
    await _pumpChart(tester, onPlaced: placed.add);
    final origin = tester.getTopLeft(_surface);
    final gesture = await tester.startGesture(origin + const Offset(60, 80));
    await gesture.moveBy(const Offset(110, 40));
    await tester.pump();
    expect(_painter(tester).draft, isNotNull);
    await gesture.cancel();
    await tester.pump();
    expect(placed, isEmpty);
    expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<KuteChartDrawingsPainter>(),
        isEmpty);
  });

  testWidgets('switching markets discards draft before pointer-up',
      (tester) async {
    final placed = <ChartDrawing>[];
    await _pumpChart(tester, onPlaced: placed.add);
    final origin = tester.getTopLeft(_surface);
    final gesture = await tester.startGesture(origin + const Offset(60, 80));
    await gesture.moveBy(const Offset(110, 40));
    await tester.pump();
    await _pumpChart(tester, marketKey: 'hl:perp::ETH', onPlaced: placed.add);
    await gesture.up();
    await tester.pump();
    expect(placed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live price changes do not rescale the active drag',
      (tester) async {
    final placed = <ChartDrawing>[];
    await _pumpChart(tester, onPlaced: placed.add);
    final origin = tester.getTopLeft(_surface);
    final gesture = await tester.startGesture(origin + const Offset(60, 80));
    await gesture.moveBy(const Offset(60, 20));
    await tester.pump();
    final geom = _painter(tester).resolveGeometry(tester.getSize(_surface))!;
    await _pumpChart(tester,
        candles: _candles(scale: 10), onPlaced: placed.add);
    await gesture.moveTo(origin + const Offset(210, 140));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(
        placed.single.points.last.price, closeTo(geom.priceForY(140), 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('handle drag preserves where the finger grabbed the handle',
      (tester) async {
    final updated = <ChartDrawing>[];
    final drawing =
        ChartDrawing(id: 'line', tool: ChartDrawingTool.trendline, points: [
      ChartDrawingPoint(
          timeMs: _candles()[1].openTime.millisecondsSinceEpoch, price: 107),
      ChartDrawingPoint(
          timeMs: _candles()[5].openTime.millisecondsSinceEpoch, price: 104),
    ]);
    await _pumpChart(tester,
        tool: null,
        drawings: [drawing],
        selected: drawing.id,
        onUpdated: updated.add);
    final origin = tester.getTopLeft(_surface);
    final geom = _painter(tester).resolveGeometry(tester.getSize(_surface))!;
    final handle = geom.offsetFor(drawing.points.last);
    final gesture =
        await tester.startGesture(origin + handle + const Offset(5, 5));
    await gesture.moveBy(const Offset(45, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(updated, hasLength(1));
    final moved = geom.offsetFor(updated.single.points.last);
    expect(moved.dx, closeTo(handle.dx + 75, 0.01));
    expect(moved.dy, closeTo(handle.dy + 30, 0.01));
    expect(updated.single.points.first.timeMs, drawing.points.first.timeMs);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving a whole drawing keeps its shape at the plot edge',
      (tester) async {
    final updated = <ChartDrawing>[];
    final drawing =
        ChartDrawing(id: 'line', tool: ChartDrawingTool.trendline, points: [
      ChartDrawingPoint(
          timeMs: _candles()[1].openTime.millisecondsSinceEpoch, price: 107),
      ChartDrawingPoint(
          timeMs: _candles()[5].openTime.millisecondsSinceEpoch, price: 104),
    ]);
    await _pumpChart(tester,
        tool: null,
        drawings: [drawing],
        selected: drawing.id,
        onUpdated: updated.add);
    final origin = tester.getTopLeft(_surface);
    final geom = _painter(tester).resolveGeometry(tester.getSize(_surface))!;
    final a = geom.offsetFor(drawing.points.first);
    final b = geom.offsetFor(drawing.points.last);
    final gesture = await tester.startGesture(origin + (a + b) / 2);
    await gesture.moveBy(const Offset(230, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(updated, hasLength(1));
    final movedA = geom.offsetFor(updated.single.points.first);
    final movedB = geom.offsetFor(updated.single.points.last);
    expect(movedB.dx, closeTo(geom.width, 0.01));
    expect(movedB.dx - movedA.dx, closeTo(b.dx - a.dx, 0.01));
    expect(movedB.dy - movedA.dy, closeTo(b.dy - a.dy, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a horizontal level can be positioned by dragging',
      (tester) async {
    final placed = <ChartDrawing>[];
    await _pumpChart(tester,
        tool: ChartDrawingTool.level, onPlaced: placed.add);
    final origin = tester.getTopLeft(_surface);
    final gesture = await tester.startGesture(origin + const Offset(60, 80));
    await gesture.moveBy(const Offset(50, 40));
    await tester.pump();
    final geom = _painter(tester).resolveGeometry(tester.getSize(_surface))!;
    await gesture.up();
    await tester.pump();
    expect(placed, hasLength(1));
    expect(placed.single.tool, ChartDrawingTool.level);
    expect(geom.offsetFor(placed.single.points.single).dy, closeTo(120, 0.01));
    expect(tester.takeException(), isNull);
  });
}
