import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';

const _up = Color(0xFF00AA00);
const _down = Color(0xFFAA0000);

Future<void> _pump(WidgetTester tester, List<double> closes) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      home: Center(
        child: HlLineSparkline(
            closes: closes,
            width: 64,
            height: 28,
            upColor: _up,
            downColor: _down),
      ),
    ),
  ));
}

RenderObject _paint(WidgetTester tester) => tester.renderObject(find.descendant(
    of: find.byType(HlLineSparkline), matching: find.byType(CustomPaint)));

/// The baseline call: dots in [color] at 40%, 1.2 wide, round.
bool _dots(Symbol method, List<dynamic> args, Color color) {
  if (method != #drawPoints) return false;
  final paint = args[2] as Paint;
  return args[0] == PointMode.points &&
      // Paint keeps its colour in 32-bit floats: compared as ARGB bytes.
      paint.color.toARGB32() == color.withValues(alpha: 0.4).toARGB32() &&
      (paint.strokeWidth - 1.2).abs() < 1e-6 &&
      paint.strokeCap == StrokeCap.round;
}

void main() {
  testWidgets('a 1.5 px line over a faint dotted baseline, no fill',
      (tester) async {
    await _pump(tester, [10, 20, 5, 12]);
    expect(
        _paint(tester),
        paints
          ..something((m, args) => _dots(m, args, _up))
          ..path(color: _up, strokeWidth: 1.5, style: PaintingStyle.stroke));
    // The line only: one path, nothing filled.
    expect(_paint(tester), paintsExactlyCountTimes(#drawPath, 1));
    expect(_paint(tester), paintsExactlyCountTimes(#drawRect, 0));
  });

  testWidgets('a falling series draws in the down colour', (tester) async {
    await _pump(tester, [12, 20, 5, 10]);
    expect(
        _paint(tester),
        paints
          ..something((m, args) => _dots(m, args, _down))
          ..path(color: _down));
  });

  testWidgets('its own repaint boundary keeps the line out of the card repaints',
      (tester) async {
    await _pump(tester, [1, 2, 3]);
    expect(
        find.descendant(
            of: find.byType(HlLineSparkline),
            matching: find.byType(RepaintBoundary)),
        findsOneWidget);
  });

  test('the baseline sits at the first value and spans the width', () {
    const size = Size(64, 28);
    final p = HlLineSparklinePainter(
        data: const [10, 20, 5, 12], upColor: _up, downColor: _down);
    // min 5, max 20: the first value is a third of the way up, inside the
    // 12% pads.
    const norm = (10 - 5) / 15;
    const y = 28 * (0.12 + 0.76 * (1 - norm));
    expect(p.baselineY(size), closeTo(y, 1e-9));
    final dots = p.baselineDots(size);
    expect(dots.every((d) => d.dy == dots.first.dy), isTrue);
    expect(dots.first.dx, inInclusiveRange(0, HlLineSparklinePainter.dotSpacing));
    expect(dots.last.dx,
        inInclusiveRange(64 - HlLineSparklinePainter.dotSpacing, 64));
    // Evenly spread: the leftover is split between the two ends.
    expect(dots.first.dx, closeTo(64 - dots.last.dx, 1e-9));
  });

  test('an equal series does not repaint; a moved one does', () {
    HlLineSparklinePainter p(List<double> d, {Color up = _up}) =>
        HlLineSparklinePainter(data: d, upColor: up, downColor: _down);
    expect(p([1, 2, 3]).shouldRepaint(p([1, 2, 3])), isFalse);
    expect(p([1, 2, 3]).shouldRepaint(p([1, 2, 4])), isTrue);
    expect(p([1, 2, 3]).shouldRepaint(p([1, 2, 3], up: _down)), isTrue);
  });
}
