// A selected drawing's settings sheet (hl_drawing_settings_sheet.dart):
// opened from its floating toolbar, it shows only the rows its tool has
// and writes them on the drawing (width, fill, labels, text size, the
// Fibonacci levels); Reset takes every one back to the default.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';

import '../../helpers/hl_chart_edit_harness.dart';

Finder get _layer => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is KuteChartDrawingsPainter);

Offset _at(WidgetTester tester, ChartDrawingPoint p) {
  final painter =
      tester.widget<CustomPaint>(_layer).painter as KuteChartDrawingsPainter;
  final geom = painter.resolveGeometry(tester.getSize(_layer))!;
  return tester.getTopLeft(_layer) + geom.offsetFor(p);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  final tape = hlEditCandles();
  ChartDrawingPoint at(int bar, double price) => ChartDrawingPoint(
      timeMs: tape[bar].openTime.millisecondsSinceEpoch, price: price);

  Future<void> openFor(WidgetTester tester, ChartDrawing d, Offset Function() tapAt) async {
    await pumpHlEditSheet(tester);
    await enterHlEdit(tester);
    hlEditDrawingsNotifier(tester).add(d);
    await _settle(tester);
    await tester.tapAt(tapAt());
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('hl-drawing-toolbar-settings')));
    await _settle(tester);
  }

  ChartDrawing saved(WidgetTester tester, String id) =>
      hlEditDrawings(tester).firstWhere((d) => d.id == id);

  testWidgets(
      'a zone: width, fill and labels, written on the drawing; Reset '
      'takes them back', (tester) async {
    final zone = ChartDrawing(
        id: 'zone',
        tool: ChartDrawingTool.rect,
        points: [at(80, 64400), at(96, 64950)]);
    await openFor(tester, zone, () => _at(tester, at(88, 64700)));
    expect(find.byKey(const ValueKey('hl-drawing-settings-rect')),
        findsOneWidget);
    expect(find.text('Rectangle settings'), findsOneWidget);
    // A zone has no text size and no levels.
    expect(find.byKey(const ValueKey('hl-drawing-setting-textSize')),
        findsNothing);
    expect(find.text('Levels'), findsNothing);
    expect(find.text('8%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hl-drawing-setting-step-width-up')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('hl-drawing-setting-step-fill-up')));
    await _settle(tester);
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('hl-drawing-setting-labels')),
        matching: find.byType(Switch)));
    await _settle(tester);
    var d = saved(tester, 'zone');
    expect(d.width, 3);
    expect(d.fill, 10);
    expect(d.labels, isFalse);

    await tester.tap(find.byKey(const ValueKey('hl-drawing-settings-reset')));
    await _settle(tester);
    d = saved(tester, 'zone');
    expect(d.hasDefaultSettings, isTrue);
    expect(d.toJson().keys, isNot(contains('w')));
    await tester.tap(find.byKey(const ValueKey('hl-drawing-settings-close')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('hl-drawing-settings-rect')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a retracement: its levels on and off', (tester) async {
    final fib = ChartDrawing(
        id: 'fib',
        tool: ChartDrawingTool.fibonacci,
        points: [at(70, 64000), at(100, 65600)]);
    await openFor(tester, fib, () => _at(tester, at(85, 64800)));
    expect(find.text('Levels'), findsOneWidget);
    Finder level(double r) => find.descendant(
        of: find.byKey(ValueKey('hl-drawing-setting-level-$r')),
        matching: find.byType(Switch));
    await tester.ensureVisible(level(1.618));
    await tester.tap(level(1.618));
    await _settle(tester);
    await tester.ensureVisible(level(0.786));
    await tester.tap(level(0.786));
    await _settle(tester);
    expect(saved(tester, 'fib').levels,
        [0, 0.236, 0.382, 0.5, 0.618, 1, 1.618]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a note: its text size only', (tester) async {
    final note = ChartDrawing(
        id: 'note',
        tool: ChartDrawingTool.text,
        points: [at(60, 65000)],
        text: 'Breakout');
    await openFor(tester, note, () => _at(tester, at(60, 65000)) + const Offset(12, 10));
    expect(find.byKey(const ValueKey('hl-drawing-setting-width')), findsNothing);
    expect(find.byKey(const ValueKey('hl-drawing-setting-labels')),
        findsNothing);
    for (var i = 0; i < 3; i++) {
      await tester
          .tap(find.byKey(const ValueKey('hl-drawing-setting-step-textSize-up')));
      await _settle(tester);
    }
    expect(saved(tester, 'note').textSize, 16);
    expect(tester.takeException(), isNull);
  });
}
