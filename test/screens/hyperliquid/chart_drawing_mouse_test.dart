// The Advanced chart with a mouse (founder, 25 November 2026: "drawing
// tools not working properly here also ... on web"): with a tool in hand
// press-drag-release draws it and click, move, click draws it too (the
// second point follows the pointer between the clicks); a click that
// wobbles a pixel is still a click; with no tool a drag pans and a click
// selects; a drag on a drawing moves it; Escape drops the placing in
// hand; Delete removes the selected drawing; the cursor says what a press
// does. At the desk (the editor on a laptop) a live tick must not drop
// the drawing in hand. The same sequences with a finger stay as they were.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/hl_chart_edit_harness.dart';

List<HyperliquidCandle> _candles({int count = 10, double scale = 1}) => [
      for (var i = 0; i < count; i++)
        HyperliquidCandle(
          openTime:
              DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 60000),
          closeTime:
              DateTime.fromMillisecondsSinceEpoch(1700000060000 + i * 60000),
          open: (100 + i % 7) * scale,
          high: (102 + i % 7) * scale,
          low: (98 + i % 7) * scale,
          close: (101 + i % 7) * scale,
          volume: 10,
        ),
    ];

Finder get _layer => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is KuteChartDrawingsPainter);

KuteChartDrawingsPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_layer).painter as KuteChartDrawingsPainter;

KuteDrawingGeometry _geom(WidgetTester tester) =>
    _painter(tester).resolveGeometry(tester.getSize(_layer))!;

Finder get _surface => find.descendant(
    of: find.byType(HlCandlestickChart),
    matching: find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onPanUpdate != null));

/// The plot's mouse cursor (its MouseRegion with the hover handler).
MouseCursor _cursor(WidgetTester tester) => tester
    .widget<MouseRegion>(find.descendant(
        of: find.byType(HlCandlestickChart),
        matching: find.byWidgetPredicate(
            (w) => w is MouseRegion && w.onExit != null)))
    .cursor;

/// A short real-time pause, so two clicks never read as a double click.
Future<void> _apart(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)));

// A drawing already there keeps the drawings layer mounted to read its
// geometry from.
final _seed = ChartDrawing(
  id: 'seed',
  tool: ChartDrawingTool.level,
  points: [
    ChartDrawingPoint(
        timeMs: _candles()[0].openTime.millisecondsSinceEpoch, price: 97)
  ],
);

Widget _chart({
  ChartDrawingTool? tool,
  List<ChartDrawing>? drawings,
  String? selected,
  List<HyperliquidCandle>? candles,
  bool desk = false,
  ValueChanged<ChartDrawing>? onPlaced,
  ValueChanged<ChartDrawing>? onUpdated,
  ValueChanged<String?>? onSelected,
  ValueChanged<bool>? onPending,
}) =>
    ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 400,
              child: HlCandlestickChart(
                key: const ValueKey('chart'),
                marketKey: 'hl:perp::BTC',
                candles: candles ?? _candles(),
                height: 240,
                desk: desk,
                drawingMode: true,
                armedTool: tool,
                drawings: drawings ?? [_seed],
                selectedDrawingId: selected,
                showVolume: desk,
                magnet: false,
                onDrawingPlaced: onPlaced,
                onDrawingUpdated: onUpdated,
                onDrawingSelected: onSelected,
                onPlacementPendingChanged: onPending,
              ),
            ),
          ),
        ),
      ),
    );

Future<TestGesture> _mouse(WidgetTester tester, Offset at) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: at);
  await tester.pump();
  return g;
}

/// A mouse click at [at] through [g] (press, release).
Future<void> _click(WidgetTester tester, TestGesture g, Offset at,
    {Offset wobble = Offset.zero}) async {
  await g.moveTo(at);
  await tester.pump();
  await g.down(at);
  await tester.pump();
  if (wobble != Offset.zero) {
    await g.moveTo(at + wobble);
    await tester.pump();
  }
  await g.up();
  await tester.pump();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('with a mouse', () {
    testWidgets('press-drag-release draws a trend line and does not pan',
        (tester) async {
      final placed = <ChartDrawing>[];
      await tester.pumpWidget(_chart(
          tool: ChartDrawingTool.trendline, onPlaced: placed.add));
      await tester.pump();
      final origin = tester.getTopLeft(_layer);
      final geom = _geom(tester);
      final g = await _mouse(tester, origin + const Offset(60, 80));
      await g.down(origin + const Offset(60, 80));
      await tester.pump();
      await g.moveTo(origin + const Offset(120, 110));
      await tester.pump();
      await g.moveTo(origin + const Offset(220, 150));
      await tester.pump();
      // The preview while placing; no magnifier for a mouse.
      expect(_painter(tester).draft, isNotNull);
      expect(find.byKey(const ValueKey('hl-drawing-loupe')), findsNothing);
      await g.up();
      await tester.pump();
      expect(placed, hasLength(1));
      expect(geom.offsetFor(placed.single.points.first).dx, closeTo(60, 0.01));
      expect(geom.offsetFor(placed.single.points.last).dx, closeTo(220, 0.01));
      // Same mapping after: the view did not move.
      expect(_geom(tester).offsetFor(placed.single.points.first).dx,
          closeTo(60, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'click, move, click draws one; the second point follows the '
        'pointer between the clicks', (tester) async {
      final placed = <ChartDrawing>[];
      final pending = <bool>[];
      await tester.pumpWidget(_chart(
          tool: ChartDrawingTool.trendline,
          onPlaced: placed.add,
          onPending: pending.add));
      await tester.pump();
      final origin = tester.getTopLeft(_layer);
      final g = await _mouse(tester, origin + const Offset(50, 50));
      await _click(tester, g, origin + const Offset(60, 80));
      expect(pending, [true]);
      await g.moveTo(origin + const Offset(150, 120));
      await tester.pump();
      final geom = _geom(tester);
      expect(geom.offsetFor(_painter(tester).draft!.points[1]).dx,
          closeTo(150, 0.01));
      await _apart(tester);
      await _click(tester, g, origin + const Offset(200, 140));
      expect(placed, hasLength(1));
      expect(geom.offsetFor(placed.single.points.last).dx, closeTo(200, 0.01));
      expect(pending, [true, false]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a click that wobbles 3 px is still a click', (tester) async {
      final placed = <ChartDrawing>[];
      final pending = <bool>[];
      await tester.pumpWidget(_chart(
          tool: ChartDrawingTool.trendline,
          onPlaced: placed.add,
          onPending: pending.add));
      await tester.pump();
      final origin = tester.getTopLeft(_layer);
      final g = await _mouse(tester, origin + const Offset(50, 50));
      await _click(tester, g, origin + const Offset(60, 80),
          wobble: const Offset(3, 0));
      expect(pending, [true]);
      await _apart(tester);
      await _click(tester, g, origin + const Offset(200, 140),
          wobble: const Offset(0, 3));
      expect(placed, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Measure tool dragged by a plain mouse measures',
        (tester) async {
      final placed = <ChartDrawing>[];
      await tester.pumpWidget(_chart(
          tool: ChartDrawingTool.dateAndPriceRange, onPlaced: placed.add));
      await tester.pump();
      final origin = tester.getTopLeft(_layer);
      final g = await _mouse(tester, origin + const Offset(60, 80));
      await g.down(origin + const Offset(60, 80));
      await tester.pump();
      await g.moveTo(origin + const Offset(200, 160));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(placed.single.tool, ChartDrawingTool.dateAndPriceRange);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Escape drops a first point waiting for its second',
        (tester) async {
      final placed = <ChartDrawing>[];
      final pending = <bool>[];
      await tester.pumpWidget(_chart(
          tool: ChartDrawingTool.trendline,
          onPlaced: placed.add,
          onPending: pending.add));
      await tester.pump();
      final origin = tester.getTopLeft(_layer);
      final g = await _mouse(tester, origin + const Offset(50, 50));
      await _click(tester, g, origin + const Offset(60, 80));
      expect(pending, [true]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(pending, [true, false]);
      // The next click starts over rather than finishing a line.
      await _apart(tester);
      await _click(tester, g, origin + const Offset(200, 140));
      expect(placed, isEmpty);
      expect(pending, [true, false, true]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with no tool: a drag pans, a click selects, a drag moves',
        (tester) async {
      final tape = _candles(count: 200);
      ChartDrawingPoint at(int bar, double price) => ChartDrawingPoint(
          timeMs: tape[bar].openTime.millisecondsSinceEpoch, price: price);
      final line = ChartDrawing(
          id: 'line',
          tool: ChartDrawingTool.trendline,
          points: [at(150, 101), at(180, 104)]);
      final selected = <String?>[];
      final updated = <ChartDrawing>[];
      Widget build(String? sel) => _chart(
          candles: tape,
          drawings: [line],
          selected: sel,
          onSelected: selected.add,
          onUpdated: updated.add);
      await tester.pumpWidget(build(null));
      await tester.pump();
      final origin = tester.getTopLeft(_layer);
      final a0 = _geom(tester).offsetFor(line.points[0]);
      final b0 = _geom(tester).offsetFor(line.points[1]);
      final mid = (a0 + b0) / 2;

      // Empty plot under the cursor: grab.
      final g = await _mouse(tester, origin + Offset(mid.dx, 10));
      await g.moveTo(origin + Offset(mid.dx, 12));
      await tester.pump();
      expect(_cursor(tester), SystemMouseCursors.grab);
      // Over the line: move.
      await g.moveTo(origin + mid);
      await tester.pump();
      expect(_cursor(tester), SystemMouseCursors.move);

      // A click on the line selects it.
      await _click(tester, g, origin + mid);
      expect(selected, ['line']);
      await tester.pumpWidget(build('line'));
      await tester.pump();
      await _apart(tester);

      // A drag on its body moves it, the view stays.
      await g.moveTo(origin + mid);
      await tester.pump();
      await g.down(origin + mid);
      await tester.pump();
      await g.moveTo(origin + mid + const Offset(-30, 0));
      await tester.pump();
      expect(_cursor(tester), SystemMouseCursors.move);
      await g.moveTo(origin + mid + const Offset(-60, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(updated, hasLength(1));
      expect(_geom(tester).offsetFor(updated.single.points[0]).dx,
          closeTo(a0.dx - 60, 3));

      // A drag on empty plot pans the chart: the line slides with it.
      await _apart(tester);
      final empty = origin + Offset(mid.dx, 10);
      await g.moveTo(empty);
      await tester.pump();
      await g.down(empty);
      await tester.pump();
      await g.moveTo(empty + const Offset(40, 0));
      await tester.pump();
      expect(_cursor(tester), SystemMouseCursors.grabbing);
      await g.moveTo(empty + const Offset(80, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(updated, hasLength(1));
      expect(_geom(tester).offsetFor(line.points[0]).dx,
          greaterThan(a0.dx + 40));

      // A click on empty plot lets the selection go.
      await _apart(tester);
      await _click(tester, g, origin + Offset(mid.dx, 10));
      expect(selected.last, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tool in hand: the precise cursor and a level preview',
        (tester) async {
      await tester.pumpWidget(_chart(tool: ChartDrawingTool.level));
      await tester.pump();
      final origin = tester.getTopLeft(_layer);
      final g = await _mouse(tester, origin + const Offset(100, 90));
      await g.moveTo(origin + const Offset(100, 100));
      await tester.pump();
      expect(_cursor(tester), SystemMouseCursors.precise);
      final ghost = _painter(tester).drawings.last;
      expect(ghost.id, 'hover-ghost');
      expect(ghost.tool, ChartDrawingTool.level);
      expect(_geom(tester).offsetFor(ghost.points.single).dy,
          closeTo(100, 0.01));
      expect(tester.takeException(), isNull);
    });
  });

  group('at the desk, a live tick', () {
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      testWidgets('does not drop the drawing in hand (${kind.name})',
          (tester) async {
        final placed = <ChartDrawing>[];
        Widget build(double scale) => _chart(
            tool: ChartDrawingTool.trendline,
            desk: true,
            candles: _candles(scale: scale),
            onPlaced: placed.add);
        await tester.pumpWidget(build(1));
        await tester.pump();
        final origin = tester.getTopLeft(_layer);
        final g = await tester.startGesture(origin + const Offset(60, 80),
            kind: kind);
        await g.moveTo(origin + const Offset(120, 100));
        await tester.pump();
        // The parent rebuilds with a fresh tape (a live tick).
        await tester.pumpWidget(build(1.0001));
        await g.moveTo(origin + const Offset(200, 140));
        await tester.pump();
        await g.up();
        await tester.pump();
        expect(placed, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('with a finger, as before', () {
    testWidgets('a drag with a tool draws; the loupe shows', (tester) async {
      final placed = <ChartDrawing>[];
      await tester.pumpWidget(_chart(
          tool: ChartDrawingTool.trendline, onPlaced: placed.add));
      await tester.pump();
      final origin = tester.getTopLeft(_surface);
      final g = await tester.startGesture(origin + const Offset(60, 80));
      await g.moveTo(origin + const Offset(190, 140));
      await tester.pump();
      expect(find.byKey(const ValueKey('hl-drawing-loupe')), findsOneWidget);
      await g.up();
      await tester.pump();
      expect(placed, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Measure tool dragged by a finger measures',
        (tester) async {
      final placed = <ChartDrawing>[];
      await tester.pumpWidget(_chart(
          tool: ChartDrawingTool.dateAndPriceRange, onPlaced: placed.add));
      await tester.pump();
      final origin = tester.getTopLeft(_surface);
      final g = await tester.startGesture(origin + const Offset(60, 80));
      await g.moveTo(origin + const Offset(200, 160));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(placed.single.tool, ChartDrawingTool.dateAndPriceRange);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 3 px finger slide is not a tap', (tester) async {
      final pending = <bool>[];
      await tester.pumpWidget(_chart(
          tool: ChartDrawingTool.trendline, onPending: pending.add));
      await tester.pump();
      final origin = tester.getTopLeft(_surface);
      final g = await tester.startGesture(origin + const Offset(60, 80));
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      // A short finger drag is a drag, as before: nothing pending.
      expect(pending, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('the editor with a mouse', () {
    testWidgets('a click selects a drawing, Delete removes it',
        (tester) async {
      final tape = hlEditCandles();
      ChartDrawingPoint at(int bar, double price) => ChartDrawingPoint(
          timeMs: tape[bar].openTime.millisecondsSinceEpoch, price: price);
      final trend = ChartDrawing(
        id: 'trend',
        tool: ChartDrawingTool.trendline,
        points: [at(80, 64200), at(100, 65200)],
      );
      await pumpHlEditSheet(tester);
      await enterHlEdit(tester);
      hlEditDrawingsNotifier(tester).add(trend);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final origin = tester.getTopLeft(_layer);
      final geom = _geom(tester);
      final mid =
          origin + (geom.offsetFor(trend.points[0]) + geom.offsetFor(trend.points[1])) / 2;
      final g = await _mouse(tester, mid - const Offset(0, 40));
      await _click(tester, g, mid);
      expect(find.byKey(const ValueKey('hl-drawing-toolbar')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(hlEditDrawings(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Escape steps back: the first point, then the tool, then out of '
        'the editor', (tester) async {
      await pumpHlEditSheet(tester);
      await enterHlEdit(tester);
      await tester
          .tap(find.byKey(const ValueKey('hl-chart-rail-trendline')));
      await tester.pump();
      await _apart(tester);
      final layer = find.byType(HlCandlestickChart);
      final origin = tester.getTopLeft(layer);
      final g = await _mouse(tester, origin + const Offset(100, 100));
      await _click(tester, g, origin + const Offset(100, 120));
      bool railSelected(String key) {
        final pill = find.descendant(
            of: find.byKey(ValueKey('hl-chart-rail-$key')),
            matching: find.byType(AnimatedContainer));
        final box =
            tester.widget<AnimatedContainer>(pill).decoration as BoxDecoration;
        return box.color != Colors.transparent &&
            box.color!.a > 0.5;
      }

      expect(_painter(tester).draft, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      // The point is dropped, the tool still in hand.
      expect(_layer, findsNothing);
      expect(railSelected('trendline'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(railSelected('trendline'), isFalse);
      expect(railSelected('cursor'), isTrue);
      // Nothing in hand: Escape leaves the editor, as Done does.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('hl-chart-tool-rail')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
