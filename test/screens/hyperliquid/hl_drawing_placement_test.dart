// The Advanced chart's generic placement (hl_drawing_placement.dart):
// one state machine for every tool, driven by its spec alone. Two-point
// and one-point tools place as they always did; a tool declared with
// three points places with three taps, and the editor's hint counts them
// ("Point 2 of 3").

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/screens/hyperliquid/components/hl_drawing_placement.dart';
import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';

import '../../helpers/hl_chart_edit_harness.dart';

ChartDrawingPoint _p(int t, double price) =>
    ChartDrawingPoint(timeMs: t, price: price);

/// Pixels as the time and price apart, enough for the "same spot" rule.
double _distance(ChartDrawingPoint a, ChartDrawingPoint b) =>
    ((a.timeMs - b.timeMs).abs() + (a.price - b.price).abs()).toDouble();

HlDrawingPlacement _placing(ChartDrawingTool tool) {
  var n = 0;
  return HlDrawingPlacement(tool: tool, newId: () => 'id${n++}');
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => debugChartDrawingSpecOverride = null);

  group('the state machine', () {
    test('a one-point tool lands on its tap', () {
      final p = _placing(ChartDrawingTool.level);
      final done = p.tap(_p(10, 100), distance: _distance);
      expect(done?.points, hasLength(1));
      expect(done!.points.single.price, 100);
      expect(p.active, isFalse);
    });

    test('a two-point tool: tap, tap; a tap on the first point adds nothing',
        () {
      final p = _placing(ChartDrawingTool.trendline);
      expect(p.tap(_p(10, 100), distance: _distance), isNull);
      expect(p.placed, 1);
      // The preview is the anchor alone (every point on it).
      expect(p.preview!.points.every((q) => q.price == 100), isTrue);
      expect(p.tap(_p(12, 102), distance: _distance), isNull);
      expect(p.placed, 1);
      final done = p.tap(_p(50, 130), distance: _distance)!;
      expect(done.points.map((q) => q.price), [100, 130]);
      expect(p.placed, 0);
    });

    test('a drag draws a two-point tool in one go; a short one is nothing',
        () {
      final p = _placing(ChartDrawingTool.rect);
      p.dragStart(_p(10, 100));
      p.dragUpdate(_p(40, 120));
      expect(p.preview!.points.map((q) => q.price), [100, 120]);
      final done = p.dragEnd(distance: _distance)!;
      expect(done.points.map((q) => q.timeMs), [10, 40]);

      p.dragStart(_p(10, 100));
      p.dragUpdate(_p(11, 101));
      expect(p.dragEnd(distance: _distance), isNull);
      expect(p.active, isFalse);
    });

    test('a cancelled drag keeps the anchors already tapped', () {
      final p = _placing(ChartDrawingTool.trendline);
      p.tap(_p(10, 100), distance: _distance);
      p.dragStart(_p(30, 110));
      p.dragUpdate(_p(40, 120));
      p.cancelDrag();
      expect(p.placed, 1);
      expect(p.preview!.points.every((q) => q.price == 100), isTrue);
    });

    test('a position derives its stop from entry and target (1:1)', () {
      final p = _placing(ChartDrawingTool.longPosition);
      p.tap(_p(10, 100), distance: _distance);
      final done = p.tap(_p(60, 110), distance: _distance)!;
      expect(done.points, hasLength(3));
      expect(done.points[2].price, 90);
    });

    test('a three-point tool: three taps, the third previewed, drag or tap',
        () {
      final p = _placing(ChartDrawingTool.parallelChannel);
      expect(chartDrawingSpec(ChartDrawingTool.parallelChannel).taps, 3);
      p.tap(_p(10, 100), distance: _distance);
      p.tap(_p(60, 120), distance: _distance);
      expect(p.placed, 2);
      // The rail the third tap will set is already suggested.
      expect(p.preview!.points[2].price, lessThan(120));
      final done = p.tap(_p(60, 100), distance: _distance)!;
      expect(done.points.map((q) => q.price), [100, 120, 100]);

      // A drag for the base, then a tap for the rail.
      p.dragStart(_p(10, 100));
      p.dragUpdate(_p(60, 120));
      expect(p.dragEnd(distance: _distance), isNull);
      expect(p.placed, 2);
      expect(p.tap(_p(60, 95), distance: _distance)!.points[2].price, 95);
    });

    test('an open-ended tool goes on until its last point is tapped again',
        () {
      debugChartDrawingSpecOverride = (tool) =>
          tool == ChartDrawingTool.trendline
              ? const ChartDrawingSpec.openEnded(2, 5)
              : null;
      final p = _placing(ChartDrawingTool.trendline);
      p.tap(_p(10, 100), distance: _distance);
      // One point is not enough: the same spot again is ignored.
      expect(p.tap(_p(10, 100), distance: _distance), isNull);
      p.tap(_p(30, 120), distance: _distance);
      p.tap(_p(50, 110), distance: _distance);
      final done = p.tap(_p(50, 110), distance: _distance)!;
      expect(done.points.map((q) => q.price), [100, 120, 110]);

      // At its most points it lands on the last tap.
      for (var i = 0; i < 4; i++) {
        expect(p.tap(_p(i * 20, 100.0 + i * 15), distance: _distance), isNull);
      }
      expect(p.tap(_p(200, 90), distance: _distance)!.points, hasLength(5));
    });
  });

  group('in the editor', () {
    Finder layer() => find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is KuteChartDrawingsPainter);

    testWidgets(
        'a tool declared with three points places with three taps and the '
        'hint counts them', (tester) async {
      // The trend line, declared here as a three-point tool: nothing else
      // about it changes.
      debugChartDrawingSpecOverride = (tool) =>
          tool == ChartDrawingTool.trendline
              ? const ChartDrawingSpec(points: 3)
              : null;
      final tape = hlEditCandles();
      ChartDrawingPoint at(int bar, double price) => ChartDrawingPoint(
          timeMs: tape[bar].openTime.millisecondsSinceEpoch, price: price);
      await pumpHlEditSheet(tester);
      await enterHlEdit(tester);
      // A drawing mounts the layer the taps are measured against.
      hlEditDrawingsNotifier(tester).add(ChartDrawing(
          id: 'seed', tool: ChartDrawingTool.level, points: [at(10, 63000)]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      Offset screen(ChartDrawingPoint p) {
        final painter = tester.widget<CustomPaint>(layer()).painter
            as KuteChartDrawingsPainter;
        final geom = painter.resolveGeometry(tester.getSize(layer()))!;
        return tester.getTopLeft(layer()) + geom.offsetFor(p);
      }

      Future<void> apart() => tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)));

      await tester.tap(find.byKey(const ValueKey('hl-chart-rail-trendline')));
      await tester.pump();
      await apart();
      await tester.tapAt(screen(at(60, 64000)));
      await tester.pump();
      expect(find.text('Point 2 of 3: tap the chart.'), findsOneWidget);
      await apart();
      await tester.tapAt(screen(at(80, 65200)));
      await tester.pump();
      expect(find.text('Point 3 of 3: tap the chart.'), findsOneWidget);
      expect(hlEditDrawings(tester), hasLength(1));
      await apart();
      await tester.tapAt(screen(at(100, 64400)));
      await tester.pump();
      final placed = hlEditDrawings(tester).last;
      expect(placed.tool, ChartDrawingTool.trendline);
      expect(placed.points, hasLength(3));
      expect(find.textContaining('Point '), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
