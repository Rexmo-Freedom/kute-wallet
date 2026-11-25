// The grouped rail's tools with a mouse (the web on a laptop), to the
// standard of chart_drawing_mouse_test.dart: every restored tool places
// by press-drag-release and by click, move, click through the one
// placement machine (HlDrawingPlacement); the parallel channel takes three
// clicks, its remaining points following the pointer and the hint
// counting them; a one-point tool previews under the pointer; at the desk
// a live tick mid-placement drops none of them. On a laptop a group's
// fly-out is the panel beside its button, opened by a right click, the
// corner mark or a second click, and closed by Escape or a click outside;
// the settings sheet opens in the app's shared panel.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/hyperliquid/components/hl_drawing_rail.dart';
import 'package:kute/screens/hyperliquid/components/hl_drawing_tools.dart';
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

Future<void> _apart(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)));

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

final _seed = ChartDrawing(
  id: 'seed',
  tool: ChartDrawingTool.level,
  points: [
    ChartDrawingPoint(
        timeMs: _candles()[0].openTime.millisecondsSinceEpoch, price: 97)
  ],
);

Widget _chart({
  required ChartDrawingTool tool,
  List<HyperliquidCandle>? candles,
  bool desk = false,
  ValueChanged<ChartDrawing>? onPlaced,
  ValueChanged<int>? onPoints,
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
                drawings: [_seed],
                showVolume: desk,
                magnet: false,
                onDrawingPlaced: onPlaced,
                onPlacementPointsChanged: onPoints,
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

Future<void> _click(WidgetTester tester, TestGesture g, Offset at) async {
  await g.moveTo(at);
  await tester.pump();
  await g.down(at);
  await tester.pump();
  await g.up();
  await tester.pump();
}

Future<void> _drag(
    WidgetTester tester, TestGesture g, Offset from, Offset to) async {
  await g.moveTo(from);
  await tester.pump();
  await g.down(from);
  await tester.pump();
  await g.moveTo(Offset.lerp(from, to, 0.5)!);
  await tester.pump();
  await g.moveTo(to);
  await tester.pump();
  await g.up();
  await tester.pump();
}

/// The restored two-anchor tools and the positions (two clicks, the stop
/// derived).
const _twoClickTools = [
  ChartDrawingTool.ray,
  ChartDrawingTool.extendedLine,
  ChartDrawingTool.longPosition,
  ChartDrawingTool.shortPosition,
  ChartDrawingTool.priceRange,
  ChartDrawingTool.dateRange,
];

/// The restored one-anchor tools.
const _oneClickTools = [
  ChartDrawingTool.horizontalRay,
  ChartDrawingTool.verticalLine,
];

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('restored tools with a mouse', () {
    for (final tool in _twoClickTools) {
      testWidgets('${tool.name}: press-drag-release places it',
          (tester) async {
        final placed = <ChartDrawing>[];
        await tester.pumpWidget(_chart(tool: tool, onPlaced: placed.add));
        await tester.pump();
        final origin = tester.getTopLeft(_layer);
        final geom = _geom(tester);
        final g = await _mouse(tester, origin + const Offset(40, 40));
        await _drag(tester, g, origin + const Offset(80, 90),
            origin + const Offset(220, 60));
        expect(placed, hasLength(1));
        final d = placed.single;
        expect(d.tool, tool);
        expect(d.points, hasLength(chartDrawingSpec(tool).points));
        expect(geom.offsetFor(d.points[0]).dx, closeTo(80, 0.01));
        expect(geom.offsetFor(d.points[1]).dx, closeTo(220, 0.01));
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          '${tool.name}: click, move, click places it; the second point '
          'follows the pointer', (tester) async {
        final placed = <ChartDrawing>[];
        final points = <int>[];
        await tester.pumpWidget(
            _chart(tool: tool, onPlaced: placed.add, onPoints: points.add));
        await tester.pump();
        final origin = tester.getTopLeft(_layer);
        final g = await _mouse(tester, origin + const Offset(40, 40));
        await _click(tester, g, origin + const Offset(80, 90));
        expect(points, [1]);
        await g.moveTo(origin + const Offset(170, 70));
        await tester.pump();
        final geom = _geom(tester);
        expect(geom.offsetFor(_painter(tester).draft!.points[1]).dx,
            closeTo(170, 0.01));
        await _apart(tester);
        await _click(tester, g, origin + const Offset(220, 60));
        expect(placed, hasLength(1));
        expect(placed.single.tool, tool);
        expect(geom.offsetFor(placed.single.points[1]).dx, closeTo(220, 0.01));
        expect(points, [1, 0]);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        'a position: the stop is derived at 1:1 by click and by drag alike',
        (tester) async {
      final placed = <ChartDrawing>[];
      await tester.pumpWidget(_chart(
          tool: ChartDrawingTool.longPosition, onPlaced: placed.add));
      await tester.pump();
      final origin = tester.getTopLeft(_layer);
      final g = await _mouse(tester, origin + const Offset(40, 40));
      await _drag(tester, g, origin + const Offset(80, 120),
          origin + const Offset(200, 80));
      await _apart(tester);
      await _click(tester, g, origin + const Offset(80, 120));
      await _apart(tester);
      await _click(tester, g, origin + const Offset(200, 80));
      expect(placed, hasLength(2));
      for (final d in placed) {
        final entry = d.points[0].price, target = d.points[1].price;
        expect(d.points[2].price, closeTo(entry - (target - entry), 1e-6));
      }
      expect(placed[0].points[2].price, closeTo(placed[1].points[2].price, 1e-6));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a parallel channel: three clicks, the hint counts the points and '
        'the rest follow the pointer', (tester) async {
      final placed = <ChartDrawing>[];
      final points = <int>[];
      await tester.pumpWidget(_chart(
          tool: ChartDrawingTool.parallelChannel,
          onPlaced: placed.add,
          onPoints: points.add));
      await tester.pump();
      final origin = tester.getTopLeft(_layer);
      final geom = _geom(tester);
      final g = await _mouse(tester, origin + const Offset(40, 40));
      await _click(tester, g, origin + const Offset(60, 120));
      await g.moveTo(origin + const Offset(160, 70));
      await tester.pump();
      // The second point (and the derived rail) follow the pointer.
      var draft = _painter(tester).draft!;
      expect(geom.offsetFor(draft.points[1]).dx, closeTo(160, 0.01));
      await _apart(tester);
      await _click(tester, g, origin + const Offset(220, 60));
      expect(points, [1, 2]);
      await g.moveTo(origin + const Offset(200, 140));
      await tester.pump();
      draft = _painter(tester).draft!;
      expect(geom.offsetFor(draft.points[2]).dy, closeTo(140, 0.01));
      expect(placed, isEmpty);
      await _apart(tester);
      await _click(tester, g, origin + const Offset(200, 150));
      expect(placed, hasLength(1));
      expect(placed.single.tool, ChartDrawingTool.parallelChannel);
      expect(geom.offsetFor(placed.single.points[2]).dy, closeTo(150, 0.01));
      expect(points, [1, 2, 0]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a parallel channel: a drag for the base, a click for the rail',
        (tester) async {
      final placed = <ChartDrawing>[];
      await tester.pumpWidget(_chart(
          tool: ChartDrawingTool.parallelChannel, onPlaced: placed.add));
      await tester.pump();
      final origin = tester.getTopLeft(_layer);
      final g = await _mouse(tester, origin + const Offset(40, 40));
      await _drag(tester, g, origin + const Offset(60, 120),
          origin + const Offset(220, 60));
      expect(placed, isEmpty);
      await _apart(tester);
      await _click(tester, g, origin + const Offset(200, 150));
      expect(placed, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    for (final tool in _oneClickTools) {
      testWidgets('${tool.name}: previews under the pointer, a click places it',
          (tester) async {
        final placed = <ChartDrawing>[];
        await tester.pumpWidget(_chart(tool: tool, onPlaced: placed.add));
        await tester.pump();
        final origin = tester.getTopLeft(_layer);
        final g = await _mouse(tester, origin + const Offset(100, 90));
        await g.moveTo(origin + const Offset(120, 100));
        await tester.pump();
        final ghost = _painter(tester).drawings.last;
        expect(ghost.id, 'hover-ghost');
        expect(ghost.tool, tool);
        await _click(tester, g, origin + const Offset(150, 110));
        expect(placed.single.tool, tool);
        expect(_geom(tester).offsetFor(placed.single.points.single).dx,
            closeTo(150, 0.01));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Escape drops a channel half placed', (tester) async {
      final placed = <ChartDrawing>[];
      final points = <int>[];
      await tester.pumpWidget(_chart(
          tool: ChartDrawingTool.parallelChannel,
          onPlaced: placed.add,
          onPoints: points.add));
      await tester.pump();
      final origin = tester.getTopLeft(_layer);
      final g = await _mouse(tester, origin + const Offset(40, 40));
      await _click(tester, g, origin + const Offset(60, 120));
      await _apart(tester);
      await _click(tester, g, origin + const Offset(220, 60));
      expect(points, [1, 2]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(points, [1, 2, 0]);
      expect(placed, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('at the desk, a live tick mid-placement', () {
    for (final tool in [
      ChartDrawingTool.ray,
      ChartDrawingTool.longPosition,
      ChartDrawingTool.parallelChannel,
      ChartDrawingTool.dateRange,
    ]) {
      testWidgets('drops nothing of a ${tool.name} placed by clicks',
          (tester) async {
        final placed = <ChartDrawing>[];
        Widget build(double scale) => _chart(
            tool: tool,
            desk: true,
            candles: _candles(scale: scale),
            onPlaced: placed.add);
        await tester.pumpWidget(build(1));
        await tester.pump();
        final origin = tester.getTopLeft(_layer);
        final g = await _mouse(tester, origin + const Offset(40, 40));
        final clicks = [
          const Offset(60, 120),
          const Offset(220, 60),
          const Offset(200, 150),
        ].take(chartDrawingSpec(tool).taps).toList();
        for (var i = 0; i < clicks.length; i++) {
          if (i > 0) {
            // A live tick between the clicks.
            await tester.pumpWidget(build(1 + i * 0.0001));
            await g.moveTo(origin + clicks[i] - const Offset(5, 5));
            await tester.pump();
            await _apart(tester);
          }
          await _click(tester, g, origin + clicks[i]);
        }
        expect(placed, hasLength(1));
        expect(placed.single.tool, tool);
        expect(tester.takeException(), isNull);
      });

      testWidgets('drops nothing of a ${tool.name} placed by a drag',
          (tester) async {
        final placed = <ChartDrawing>[];
        Widget build(double scale) => _chart(
            tool: tool,
            desk: true,
            candles: _candles(scale: scale),
            onPlaced: placed.add);
        await tester.pumpWidget(build(1));
        await tester.pump();
        final origin = tester.getTopLeft(_layer);
        final g = await _mouse(tester, origin + const Offset(40, 40));
        await g.moveTo(origin + const Offset(60, 120));
        await tester.pump();
        await g.down(origin + const Offset(60, 120));
        await tester.pump();
        await g.moveTo(origin + const Offset(140, 90));
        await tester.pump();
        await tester.pumpWidget(build(1.0001));
        await g.moveTo(origin + const Offset(220, 60));
        await tester.pump();
        await g.up();
        await tester.pump();
        if (chartDrawingSpec(tool).taps > 2) {
          await tester.pumpWidget(build(1.0002));
          await _apart(tester);
          await _click(tester, g, origin + const Offset(200, 150));
        }
        expect(placed, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the rail on a laptop (1440 x 900)', () {
    Finder group(HlToolGroupId id) => find.descendant(
        of: find.byKey(ValueKey('hl-chart-rail-group-${id.name}')),
        matching: find.byType(HlRailButton));

    Future<TestGesture> open(WidgetTester tester) async {
      await pumpHlEditSheet(tester, width: 1440, height: 900);
      await enterHlEdit(tester);
      final g = await _mouse(tester, const Offset(700, 450));
      return g;
    }

    Finder row(ChartDrawingTool t) =>
        find.byKey(ValueKey('hl-tool-flyout-${t.name}'));

    testWidgets('a right click opens the fly-out beside the button',
        (tester) async {
      await open(tester);
      final lines = group(HlToolGroupId.lines);
      await tester.tap(lines,
          buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(row(ChartDrawingTool.ray), findsOneWidget);
      // A panel to the right of the button, not a sheet.
      expect(find.byKey(const ValueKey('hl-tool-flyout-lines')), findsNothing);
      expect(tester.getTopLeft(row(ChartDrawingTool.ray)).dx,
          greaterThan(tester.getTopRight(lines).dx));
      // Its top near the button's.
      expect(
          (tester.getTopLeft(row(ChartDrawingTool.trendline)).dy -
                  tester.getTopLeft(lines).dy)
              .abs(),
          lessThan(40));
      // Picking a tool takes it and makes it the face.
      await tester.tap(row(ChartDrawingTool.ray),
          kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(row(ChartDrawingTool.ray), findsNothing);
      expect(find.byKey(const ValueKey('hl-chart-rail-ray')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the corner mark and a second click open it too',
        (tester) async {
      await open(tester);
      final positions = group(HlToolGroupId.positions);
      // The corner mark, bottom right of the button.
      await tester.tapAt(tester.getBottomRight(positions) - const Offset(5, 5),
          kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(row(ChartDrawingTool.longPosition), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(row(ChartDrawingTool.longPosition), findsNothing);
      // Still in the editor: Escape closed only the fly-out.
      expect(find.byKey(const ValueKey('hl-chart-tool-rail')), findsOneWidget);

      // A click takes the face; a second click (not a double) opens it.
      await tester.tap(positions, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      await _apart(tester);
      await tester.tap(positions, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(row(ChartDrawingTool.dateRange), findsOneWidget);
      // A click outside closes it.
      await tester.tapAt(const Offset(1300, 860),
          kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(row(ChartDrawingTool.dateRange), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the rail buttons and the panel rows show the pointer',
        (tester) async {
      final g = await open(tester);
      final lines = group(HlToolGroupId.lines);
      await g.moveTo(tester.getCenter(lines));
      await tester.pump();
      expect(
          find.descendant(
              of: lines,
              matching: find.byWidgetPredicate((w) =>
                  w is MouseRegion && w.cursor == SystemMouseCursors.click)),
          findsOneWidget);
      expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click);
      await tester.tap(lines,
          buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      await g.moveTo(tester.getCenter(row(ChartDrawingTool.ray)));
      await tester.pump();
      expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a ray placed with the mouse, its settings in the panel',
        (tester) async {
      final g = await open(tester);
      await tester.tap(group(HlToolGroupId.lines),
          buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      await tester.tap(row(ChartDrawingTool.ray),
          kind: PointerDeviceKind.mouse);
      await _settle(tester);
      final plot = find.byType(HlCandlestickChart);
      final origin = tester.getTopLeft(plot);
      await _drag(tester, g, origin + const Offset(300, 200),
          origin + const Offset(600, 120));
      await _settle(tester);
      final ray = hlEditDrawings(tester).single;
      expect(ray.tool, ChartDrawingTool.ray);
      // Placed and selected: its toolbar's settings open in the panel.
      await tester.tap(
          find.byKey(const ValueKey('hl-drawing-toolbar-settings')),
          kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(find.byKey(const ValueKey('hl-drawing-settings-ray')),
          findsOneWidget);
      await tester.tap(
          find.byKey(const ValueKey('hl-drawing-setting-step-width-up')),
          kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(hlEditDrawings(tester).single.width, 3);
      await tester.tap(find.byKey(const ValueKey('hl-drawing-settings-close')),
          kind: PointerDeviceKind.mouse);
      await _settle(tester);
      // Delete removes it.
      await g.moveTo(origin + const Offset(450, 160));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(hlEditDrawings(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
