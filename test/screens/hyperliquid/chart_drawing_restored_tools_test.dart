// The tools back on the Advanced chart's rail (batch 1): ray, extended
// line, horizontal ray, vertical line (Lines), parallel channel
// (Channels), long and short position, price range and date range
// (Positions and measure). Each one is taken from its group's fly-out,
// placed by taps, selected with its toolbar, moved by a handle and by
// its body, and deleted; its labels speak the app's language.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/screens/hyperliquid/components/hl_drawing_rail.dart';
import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';

import '../../helpers/hl_chart_edit_harness.dart';

Finder get _layer => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is KuteChartDrawingsPainter);

KuteChartDrawingsPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_layer).painter as KuteChartDrawingsPainter;

Offset _at(WidgetTester tester, ChartDrawingPoint p) {
  final geom = _painter(tester).resolveGeometry(tester.getSize(_layer))!;
  return tester.getTopLeft(_layer) + geom.offsetFor(p);
}

Future<void> _apart(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)));

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  final tape = hlEditCandles();
  ChartDrawingPoint at(int bar, double price) => ChartDrawingPoint(
      timeMs: tape[bar].openTime.millisecondsSinceEpoch, price: price);

  // Where each tool is tapped down, and a spot on its body away from its
  // handles (to select and move it).
  final cases = <ChartDrawingTool, (List<ChartDrawingPoint>, ChartDrawingPoint)>{
    ChartDrawingTool.ray: ([at(30, 64000), at(55, 64600)], at(95, 65560)),
    ChartDrawingTool.extendedLine: (
      [at(40, 64000), at(65, 64600)],
      at(100, 65440)
    ),
    ChartDrawingTool.horizontalRay: ([at(30, 64200)], at(90, 64200)),
    ChartDrawingTool.verticalLine: ([at(60, 64000)], at(60, 65300)),
    ChartDrawingTool.parallelChannel: (
      [at(30, 63900), at(100, 65100), at(100, 64300)],
      at(65, 64300)
    ),
    ChartDrawingTool.longPosition: (
      [at(30, 64300), at(100, 65300)],
      at(65, 64800)
    ),
    ChartDrawingTool.shortPosition: (
      [at(30, 65300), at(100, 64300)],
      at(65, 64800)
    ),
    ChartDrawingTool.priceRange: (
      [at(30, 63900), at(100, 65300)],
      at(65, 64600)
    ),
    ChartDrawingTool.dateRange: (
      [at(30, 63900), at(100, 65300)],
      at(65, 64600)
    ),
  };

  test('every restored tool is in its group', () {
    expect(hlGroupOf(ChartDrawingTool.ray)!.id, HlToolGroupId.lines);
    expect(hlGroupOf(ChartDrawingTool.extendedLine)!.id, HlToolGroupId.lines);
    expect(hlGroupOf(ChartDrawingTool.horizontalRay)!.id, HlToolGroupId.lines);
    expect(hlGroupOf(ChartDrawingTool.verticalLine)!.id, HlToolGroupId.lines);
    expect(hlGroupOf(ChartDrawingTool.parallelChannel)!.id,
        HlToolGroupId.channels);
    for (final t in [
      ChartDrawingTool.longPosition,
      ChartDrawingTool.shortPosition,
      ChartDrawingTool.priceRange,
      ChartDrawingTool.dateRange,
      ChartDrawingTool.dateAndPriceRange,
    ]) {
      expect(hlGroupOf(t)!.id, HlToolGroupId.positions);
    }
    // Every tool there is has a place on the rail.
    for (final t in ChartDrawingTool.values) {
      expect(hlGroupOf(t), isNotNull, reason: t.name);
    }
  });

  for (final MapEntry(key: tool, value: (taps, body)) in cases.entries) {
    testWidgets('${tool.name}: place, select, move, adjust, delete',
        (tester) async {
      await pumpHlEditSheet(tester);
      await enterHlEdit(tester);
      // A drawing mounts the layer the taps are measured against.
      hlEditDrawingsNotifier(tester).add(ChartDrawing(
          id: 'seed', tool: ChartDrawingTool.level, points: [at(5, 63000)]));
      await _settle(tester);

      await armHlTool(tester, tool);
      expect(find.byKey(ValueKey('hl-chart-rail-${tool.name}')),
          findsOneWidget);
      final spec = chartDrawingSpec(tool);
      expect(taps, hasLength(spec.taps));
      for (var i = 0; i < taps.length; i++) {
        await _apart(tester);
        await tester.tapAt(_at(tester, taps[i]));
        await tester.pump();
        if (spec.taps > 2 && i < taps.length - 1) {
          expect(find.text('Point ${i + 2} of ${spec.taps}: tap the chart.'),
              findsOneWidget);
        }
      }
      await _settle(tester);
      final placed = hlEditDrawings(tester).last;
      expect(placed.tool, tool);
      expect(placed.points, hasLength(spec.points));
      expect(placed.isValid, isTrue);
      // Placed and selected: its toolbar is up, the rail back on Cursor.
      expect(find.byKey(const ValueKey('hl-drawing-toolbar')), findsOneWidget);

      // Off and on again by a tap on its body.
      await _apart(tester);
      await tester.tapAt(_at(tester, at(112, 66800)));
      await _settle(tester);
      expect(find.byKey(const ValueKey('hl-drawing-toolbar')), findsNothing);
      await _apart(tester);
      await tester.tapAt(_at(tester, body));
      await _settle(tester);
      expect(find.byKey(const ValueKey('hl-drawing-toolbar')), findsOneWidget);

      // The body moves the whole drawing.
      final before = hlEditDrawings(tester).last;
      await _apart(tester);
      final drag = await tester.startGesture(_at(tester, body));
      await drag.moveBy(const Offset(0, -12));
      await tester.pump();
      await drag.moveBy(const Offset(-16, -18));
      await tester.pump();
      await drag.up();
      await _settle(tester);
      final moved = hlEditDrawings(tester).last;
      expect(moved.id, before.id);
      for (var i = 0; i < moved.points.length; i++) {
        expect(moved.points[i].price, greaterThan(before.points[i].price),
            reason: 'point $i follows the body');
      }

      // A handle moves one point.
      await _apart(tester);
      final handle = await tester.startGesture(_at(tester, moved.points[0]));
      await handle.moveBy(const Offset(0, 14));
      await tester.pump();
      await handle.moveBy(const Offset(0, 16));
      await tester.pump();
      await handle.up();
      await _settle(tester);
      final adjusted = hlEditDrawings(tester).last;
      expect(adjusted.points[0].price, lessThan(moved.points[0].price));
      if (adjusted.points.length > 1) {
        expect(adjusted.points[1].price, moved.points[1].price);
      }

      // Its labels in the app's words (no hard-coded English left).
      if (tool == ChartDrawingTool.dateRange) {
        expect(_painter(tester).words.bars(3, '3h'), '3 bars · 3h');
      }

      await tester.tap(find.byKey(const ValueKey('hl-drawing-toolbar-delete')));
      await _settle(tester);
      expect(hlEditDrawings(tester).map((d) => d.tool), [ChartDrawingTool.level]);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
    });
  }

  testWidgets('a position never speaks of leverage, and its pills are words',
      (tester) async {
    await pumpHlEditSheet(tester);
    await enterHlEdit(tester);
    hlEditDrawingsNotifier(tester).add(ChartDrawing(
        id: 'long',
        tool: ChartDrawingTool.longPosition,
        points: [at(30, 64000), at(100, 65000), at(30, 63500)]));
    await _settle(tester);
    final words = _painter(tester).words;
    final pills = [
      words.target(words.price(65000), words.percent(1000 / 64000)),
      words.stop(words.price(63500), words.percent(-500 / 64000)),
      words.long(words.price(64000), words.ratio(2)),
    ];
    expect(pills, ['Target 65,000  +1.56%', 'Stop 63,500  −0.78%',
        'Long 64,000 · R/R 2.00']);
    for (final p in pills) {
      expect(p.toLowerCase(), isNot(contains('lever')));
      expect(p, isNot(contains('×')));
    }
    expect(tester.takeException(), isNull);
  });
}
