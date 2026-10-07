// Chart drawings: JSON round-trip, chart-coordinate geometry mapping
// (time/price → pixels and back), and hit-testing — the invariants the
// Hyperliquid Advanced drawing tools rely on to survive timeframe
// switches and persistence.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';

void main() {
  group('ChartDrawing JSON', () {
    test('round-trips every tool with and without a color', () {
      for (final tool in ChartDrawingTool.values) {
        final d = ChartDrawing(
          id: 'id-${tool.name}',
          tool: tool,
          points: [
            const ChartDrawingPoint(timeMs: 1700000000000, price: 65000.5),
            if (chartDrawingPointCount(tool) >= 2)
              const ChartDrawingPoint(timeMs: 1700003600000, price: 66200.0),
            if (chartDrawingPointCount(tool) >= 3)
              const ChartDrawingPoint(timeMs: 1700000000000, price: 64000.0),
          ],
          colorValue: tool == ChartDrawingTool.ray ? 0xFF1FA663 : null,
          text: tool == ChartDrawingTool.text ? 'note' : null,
        );
        final back = ChartDrawing.fromJson(
            jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
        expect(back.id, d.id);
        expect(back.tool, tool);
        expect(back.points.length, d.points.length);
        expect(back.points.first.timeMs, d.points.first.timeMs);
        expect(back.points.first.price, d.points.first.price);
        expect(back.colorValue, d.colorValue);
        expect(back.isValid, isTrue);
      }
    });

    test('rejects corrupt entries via isValid', () {
      // Too few points for a trendline.
      expect(
        const ChartDrawing(
          id: 'x',
          tool: ChartDrawingTool.trendline,
          points: [ChartDrawingPoint(timeMs: 1, price: 10)],
        ).isValid,
        isFalse,
      );
      // Non-positive price.
      expect(
        const ChartDrawing(
          id: 'y',
          tool: ChartDrawingTool.level,
          points: [ChartDrawingPoint(timeMs: 1, price: 0)],
        ).isValid,
        isFalse,
      );
      // Unknown tool name falls back instead of throwing.
      final d = ChartDrawing.fromJson({
        'id': 'z',
        'tool': 'squiggle',
        'points': [
          {'t': 1, 'p': 2.0},
        ],
      });
      expect(d.tool, ChartDrawingTool.trendline);
    });
  });

  group('KuteDrawingGeometry', () {
    // 10 bars, one minute each, width 200 → slot 20, centers at 10, 30, …
    final times = [for (var i = 0; i < 10; i++) 1700000000000 + i * 60000];
    final geom = KuteDrawingGeometry(
      timesMs: times,
      width: 200,
      priceH: 100,
      loP: 100,
      rangeP: 50,
      bucketMs: 60000,
    );

    test('bar centers map to (i + 0.5) * slot', () {
      expect(geom.xForTime(times[0]), closeTo(10, 1e-9));
      expect(geom.xForTime(times[4]), closeTo(90, 1e-9));
      expect(geom.xForTime(times[9]), closeTo(190, 1e-9));
    });

    test('interpolates between bars and extrapolates past the ends', () {
      // Halfway through bucket 0 → halfway between centers 10 and 30.
      expect(geom.xForTime(times[0] + 30000), closeTo(20, 1e-9));
      // One bucket past the tape → one slot past the last center.
      expect(geom.xForTime(times[9] + 60000), closeTo(210, 1e-9));
      // One bucket before the tape → one slot before the first center.
      expect(geom.xForTime(times[0] - 60000), closeTo(-10, 1e-9));
    });

    test('timeForX inverts xForTime on and off the tape', () {
      for (final t in [
        times[0],
        times[3] + 15000,
        times[9],
        times[9] + 120000,
      ]) {
        expect(geom.timeForX(geom.xForTime(t)), t);
      }
    });

    test('gapped tapes interpolate between neighbours, not linearly', () {
      // Bars at t0, t0+1m, t0+10m (a thin market gap): the third center
      // still sits at index position 2, and mid-gap times land between
      // centers 1 and 2.
      final gappy = KuteDrawingGeometry(
        timesMs: [0, 60000, 600000],
        width: 90,
        priceH: 100,
        loP: 0,
        rangeP: 1,
        bucketMs: 60000,
      );
      expect(gappy.xForTime(600000), closeTo(75, 1e-9)); // (2+0.5)*30
      // Halfway through the gap in TIME is halfway between the centers.
      expect(gappy.xForTime(330000), closeTo(60, 1e-9));
    });

    test('price mapping inverts', () {
      expect(geom.yForPrice(150), closeTo(0, 1e-9)); // top of domain
      expect(geom.yForPrice(100), closeTo(100, 1e-9)); // bottom
      expect(geom.priceForY(geom.yForPrice(123.4)), closeTo(123.4, 1e-9));
    });
  });

  group('hit-testing', () {
    final times = [for (var i = 0; i < 10; i++) i * 60000];
    final geom = KuteDrawingGeometry(
      timesMs: times,
      width: 200,
      priceH: 100,
      loP: 0,
      rangeP: 100,
      bucketMs: 60000,
    );

    ChartDrawing make(ChartDrawingTool tool, List<(int, double)> pts) =>
        ChartDrawing(
          id: tool.name,
          tool: tool,
          points: [
            for (final (t, p) in pts) ChartDrawingPoint(timeMs: t, price: p),
          ],
        );

    test('level hits on its y within tolerance only', () {
      final level = make(ChartDrawingTool.level, [(0, 50.0)]); // y = 50
      expect(kuteDrawingHit(level, geom, const Offset(120, 55)), isTrue);
      expect(kuteDrawingHit(level, geom, const Offset(120, 70)), isFalse);
    });

    test('trendline hits near the segment, ray extends right', () {
      // Horizontal segment at price 50 from bar 0 to bar 4 (x 10..90).
      final line =
          make(ChartDrawingTool.trendline, [(times[0], 50.0), (times[4], 50.0)]);
      expect(kuteDrawingHit(line, geom, const Offset(50, 52)), isTrue);
      expect(kuteDrawingHit(line, geom, const Offset(150, 50)), isFalse);
      final ray =
          make(ChartDrawingTool.ray, [(times[0], 50.0), (times[4], 50.0)]);
      expect(kuteDrawingHit(ray, geom, const Offset(150, 50)), isTrue);
    });

    test('topmost drawing wins and handles out-grab the body', () {
      final a = make(ChartDrawingTool.level, [(0, 50.0)]);
      final b = make(ChartDrawingTool.level, [(0, 52.0)]);
      // Both within tolerance of y=50; the most recently created (b) wins.
      expect(
        kuteHitTestDrawings([a, b], geom, const Offset(100, 50)),
        b.id,
      );
      final line =
          make(ChartDrawingTool.trendline, [(times[0], 50.0), (times[4], 50.0)]);
      // Near the second endpoint (x 90, y 50).
      expect(kuteHitTestHandle(line, geom, const Offset(95, 55)), 1);
      expect(kuteHitTestHandle(line, geom, const Offset(150, 50)), isNull);
    });
  });
}
