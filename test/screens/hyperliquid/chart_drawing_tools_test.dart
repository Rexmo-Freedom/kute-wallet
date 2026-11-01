// The Advanced chart's drawing tools, TradingView style: tap-tap
// placement with the magnet and the loupe, one drawing per pick (a
// double tap keeps the tool), selecting and moving a point, the floating
// toolbar (delete, lock, style, extend), undo over every edit, and
// drawings that stay put across an interval change.

import 'package:flutter/material.dart';
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

List<HyperliquidCandle> _candles() => [
      for (var i = 0; i < 10; i++)
        HyperliquidCandle(
          openTime:
              DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 60000),
          closeTime:
              DateTime.fromMillisecondsSinceEpoch(1700000060000 + i * 60000),
          open: 100.0 + i,
          high: 102.0 + i,
          low: 98.0 + i,
          close: 101.0 + i,
          volume: 10,
        ),
    ];

Finder get _layer => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is KuteChartDrawingsPainter);

KuteChartDrawingsPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_layer).painter as KuteChartDrawingsPainter;

KuteDrawingGeometry _geom(WidgetTester tester) =>
    _painter(tester).resolveGeometry(tester.getSize(_layer))!;

/// Screen position of a chart point.
Offset _at(WidgetTester tester, ChartDrawingPoint p) =>
    tester.getTopLeft(_layer) + _geom(tester).offsetFor(p);

/// A short real-time pause, so two taps never read as a double tap.
Future<void> _apart(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)));

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('placing on the chart', () {
    Future<void> pumpChart(
      WidgetTester tester, {
      required ValueChanged<ChartDrawing> onPlaced,
      required ValueChanged<bool> onPending,
      List<ChartDrawing> drawings = const [],
      bool magnet = true,
    }) async {
      await tester.pumpWidget(ScreenUtilInit(
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
                  marketKey: 'hl:perp::BTC',
                  candles: _candles(),
                  height: 240,
                  drawingMode: true,
                  armedTool: ChartDrawingTool.trendline,
                  drawings: drawings,
                  showVolume: false,
                  magnet: magnet,
                  onDrawingPlaced: onPlaced,
                  onPlacementPendingChanged: onPending,
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets(
        'tap, tap: the first point snaps to the close within 12 px, the '
        'second lands where tapped; the loupe shows while the finger is down',
        (tester) async {
      final placed = <ChartDrawing>[];
      final pending = <bool>[];
      // A drawing already there keeps the drawings layer mounted to read
      // its geometry from.
      final c = _candles();
      final seed = ChartDrawing(
          id: 'seed',
          tool: ChartDrawingTool.level,
          points: [ChartDrawingPoint(timeMs: c[0].openTime.millisecondsSinceEpoch, price: 99)]);
      await pumpChart(tester,
          onPlaced: placed.add, onPending: pending.add, drawings: [seed]);
      final geom = _geom(tester);
      final origin = tester.getTopLeft(_layer);
      final bar2 = c[2].openTime.millisecondsSinceEpoch;
      final closeAt = geom.offsetFor(ChartDrawingPoint(timeMs: bar2, price: c[2].close));

      // Finger down 5 px off the close: the loupe is up on the snapped
      // point.
      final down = await tester.startGesture(origin + closeAt + const Offset(0, 5));
      await tester.pump();
      expect(find.byKey(const ValueKey('hl-drawing-loupe')), findsOneWidget);
      await down.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('hl-drawing-loupe')), findsNothing);
      expect(placed, isEmpty);
      expect(pending, [true]);
      expect(_painter(tester).draft!.points.first.price, c[2].close);
      expect(_painter(tester).draft!.points.first.timeMs, bar2);

      // The second tap far from any price: no snap.
      await _apart(tester);
      final bar7 = geom.xForTime(c[7].openTime.millisecondsSinceEpoch);
      final freeY = geom.yForPrice(c[7].low) + 30;
      await tester.tapAt(origin + Offset(bar7, freeY));
      await tester.pump();
      expect(placed, hasLength(1));
      expect(pending, [true, false]);
      final line = placed.single;
      expect(line.points.first.price, c[2].close);
      expect(line.points.last.price, closeTo(geom.priceForY(freeY), 1e-6));
      expect(tester.takeException(), isNull);
    });

    testWidgets('with the magnet off the first point is where tapped',
        (tester) async {
      final placed = <ChartDrawing>[];
      final c = _candles();
      final seed = ChartDrawing(
          id: 'seed',
          tool: ChartDrawingTool.level,
          points: [ChartDrawingPoint(timeMs: c[0].openTime.millisecondsSinceEpoch, price: 99)]);
      await pumpChart(tester,
          onPlaced: placed.add,
          onPending: (_) {},
          drawings: [seed],
          magnet: false);
      final geom = _geom(tester);
      final origin = tester.getTopLeft(_layer);
      final p = geom.offsetFor(ChartDrawingPoint(
              timeMs: c[2].openTime.millisecondsSinceEpoch,
              price: c[2].close)) +
          const Offset(0, 5);
      await tester.tapAt(origin + p);
      await tester.pump();
      expect(_painter(tester).draft!.points.first.price,
          closeTo(geom.priceForY(p.dy), 1e-6));
      expect(tester.takeException(), isNull);
    });
  });

  group('the Advanced chart', () {
    final tape = hlEditCandles();
    ChartDrawingPoint at(int bar, double price) => ChartDrawingPoint(
        timeMs: tape[bar].openTime.millisecondsSinceEpoch, price: price);
    final trend = ChartDrawing(
      id: 'trend',
      tool: ChartDrawingTool.trendline,
      points: [at(80, 64200), at(100, 65200)],
    );

    Future<void> open(WidgetTester tester,
        {List<ChartDrawing> drawings = const []}) async {
      await pumpHlEditSheet(tester);
      await enterHlEdit(tester);
      for (final d in drawings) {
        hlEditDrawingsNotifier(tester).add(d);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> selectTrend(WidgetTester tester) async {
      await tester.tapAt(
          (_at(tester, trend.points[0]) + _at(tester, trend.points[1])) / 2);
      await tester.pump();
      await _apart(tester);
    }

    bool railSelected(WidgetTester tester, String key) {
      final pill = find.descendant(
          of: find.byKey(ValueKey('hl-chart-rail-$key')),
          matching: find.byType(AnimatedContainer));
      final box = tester.widget<AnimatedContainer>(pill).decoration
          as BoxDecoration;
      return box.color != Colors.transparent;
    }

    testWidgets(
        'one pick draws one drawing, then the rail is back on Cursor with '
        'the new drawing selected; a double tap keeps the tool',
        (tester) async {
      await open(tester, drawings: [trend]);
      expect(railSelected(tester, 'cursor'), isTrue);

      await tester.tap(find.byKey(const ValueKey('hl-chart-rail-level')));
      await tester.pump();
      expect(railSelected(tester, 'level'), isTrue);
      expect(railSelected(tester, 'cursor'), isFalse);
      await _apart(tester);
      await tester.tapAt(_at(tester, at(60, 64800)));
      await tester.pump();
      expect(hlEditDrawings(tester), hasLength(2));
      expect(hlEditDrawings(tester).last.tool, ChartDrawingTool.level);
      expect(railSelected(tester, 'cursor'), isTrue);
      expect(find.byKey(const ValueKey('hl-drawing-toolbar')), findsOneWidget);
      // Its price, in the tag column.
      expect(
          find.byWidgetPredicate((w) =>
              w is CustomPaint && w.painter is KuteDrawingPriceTagsPainter),
          findsOneWidget);

      // A double tap: the tool stays in hand, with its lock.
      final level = find.byKey(const ValueKey('hl-chart-rail-level'));
      await tester.tap(level);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(level);
      await tester.pump();
      expect(find.byKey(const ValueKey('hl-rail-sticky')), findsOneWidget);
      await _apart(tester);
      await tester.tapAt(_at(tester, at(60, 64500)));
      await tester.pump();
      await _apart(tester);
      await tester.tapAt(_at(tester, at(60, 64300)));
      await tester.pump();
      expect(hlEditDrawings(tester), hasLength(4));
      expect(railSelected(tester, 'level'), isTrue);
      expect(find.byKey(const ValueKey('hl-rail-sticky')), findsOneWidget);
      expect(find.byKey(const ValueKey('hl-drawing-toolbar')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('select a trend line, drag one point; undo puts it back',
        (tester) async {
      await open(tester, drawings: [trend]);
      await selectTrend(tester);
      expect(find.byKey(const ValueKey('hl-drawing-toolbar')), findsOneWidget);

      final handle = _at(tester, trend.points[1]);
      final drag = await tester.startGesture(handle);
      await drag.moveBy(const Offset(-20, 30));
      await tester.pump();
      // The loupe rides the moving point; the toolbar steps aside.
      expect(find.byKey(const ValueKey('hl-drawing-loupe')), findsOneWidget);
      expect(find.byKey(const ValueKey('hl-drawing-toolbar')), findsNothing);
      await drag.moveBy(const Offset(-20, 30));
      await tester.pump();
      await drag.up();
      await tester.pump();

      final moved = hlEditDrawings(tester).single;
      expect(moved.points.first.timeMs, trend.points.first.timeMs);
      expect(moved.points.first.price, trend.points.first.price);
      expect(moved.points.last.price, lessThan(trend.points.last.price));
      expect(moved.points.last.timeMs, lessThan(trend.points.last.timeMs));

      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(hlEditDrawings(tester).single.points.last.price,
          trend.points.last.price);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'the toolbar: dashed, extend, lock (a locked line does not move), '
        'delete; undo walks every step back', (tester) async {
      await open(tester, drawings: [trend]);
      await selectTrend(tester);

      await tester.tap(find.byKey(const ValueKey('hl-drawing-toolbar-style')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('hl-drawing-toolbar-extend')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('hl-drawing-toolbar-color')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('hl-drawing-swatch-4')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('hl-drawing-toolbar-lock')));
      await tester.pump();
      var line = hlEditDrawings(tester).single;
      expect(line.dashed, isTrue);
      expect(line.extend, isTrue);
      expect(line.locked, isTrue);
      expect(line.colorValue, isNotNull);

      // Locked: a drag on its point moves the chart, not the line.
      final drag = await tester.startGesture(_at(tester, trend.points[1]));
      await drag.moveBy(const Offset(-40, 40));
      await tester.pump();
      await drag.up();
      await tester.pump();
      expect(hlEditDrawings(tester).single.points.last.price,
          trend.points.last.price);
      await _apart(tester);

      // Delete from the toolbar (the line is still selected).
      await selectTrend(tester);
      await tester
          .tap(find.byKey(const ValueKey('hl-drawing-toolbar-delete')));
      await tester.pump();
      expect(hlEditDrawings(tester), isEmpty);
      expect(find.byKey(const ValueKey('hl-drawing-toolbar')), findsNothing);

      // Undo: back, then each edit undone in turn.
      final undo = find.byTooltip('Undo');
      await tester.tap(undo);
      await tester.pump();
      expect(hlEditDrawings(tester).single.locked, isTrue);
      for (var i = 0; i < 4; i++) {
        await tester.tap(undo);
        await tester.pump();
      }
      line = hlEditDrawings(tester).single;
      expect(line.dashed, isFalse);
      expect(line.extend, isFalse);
      expect(line.locked, isFalse);
      expect(line.colorValue, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('duplicate adds a selected copy beside the original',
        (tester) async {
      await open(tester, drawings: [trend]);
      await selectTrend(tester);
      await tester
          .tap(find.byKey(const ValueKey('hl-drawing-toolbar-duplicate')));
      await tester.pump();
      final all = hlEditDrawings(tester);
      expect(all, hasLength(2));
      expect(all.last.id, isNot(trend.id));
      expect(all.last.points.first.price, lessThan(trend.points.first.price));
      expect(_painter(tester).selectedId, all.last.id);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'drawings are kept by time and price: they stay through an interval '
        'change and land on the same spot coming back', (tester) async {
      await open(tester, drawings: [trend]);
      final before = _at(tester, trend.points[1]);

      Future<void> pickInterval(String from, String to) async {
        await tester.tap(find.text(from).first);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text(to).last);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        // The top bar names the new interval.
        expect(find.text(to), findsOneWidget);
        expect(find.text(from), findsNothing);
      }

      await pickInterval('1h', '1D');
      expect(hlEditDrawings(tester).single.points.map((p) => p.toJson()),
          trend.points.map((p) => p.toJson()));
      expect(_painter(tester).drawings.single.id, trend.id);

      await pickInterval('1D', '1h');
      expect(_at(tester, trend.points[1]).dx, closeTo(before.dx, 0.5));
      expect(_at(tester, trend.points[1]).dy, closeTo(before.dy, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the overflow holds the magnet (on) and Remove all',
        (tester) async {
      await open(tester, drawings: [trend]);
      await tester.tap(find.byKey(const ValueKey('hl-chart-rail-more')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Snap to candle prices'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('hl-chart-rail-magnet')),
              matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget);
      await tester.tap(find.text('Remove all drawings'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Remove all'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(hlEditDrawings(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
