// Render harness for the Advanced chart's drawing tools (1 November
// 2026): the tool rail with a tool in hand, a selected trend line with
// its floating toolbar (and its colours open), a horizontal line with its
// price pill in the tag column, a selected zone with its range, the loupe
// while a point is placed, and a tool kept in hand. The Investing market
// sheet at 390 x 844 in the app's real theme and Inter, light and dark.
// Writes PNGs.
//
// Not part of the normal suite; it only runs when asked:
//
//   flutter test test/audit/chart_drawing_rail_render_test.dart \
//     --dart-define=CHART_RAIL_OUT=/tmp/chart-rail

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/hl_chart_edit_harness.dart';

const _out = String.fromEnvironment('CHART_RAIL_OUT');
const _key = ValueKey('shot');
const _dpr = 3.0;

Future<void> _png(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image =
      (await tester.runAsync(() => boundary.toImage(pixelRatio: _dpr)))!;
  await tester.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// Implicit animations start on the frame that rebuilds them: a second
/// frame lets them land before the shot.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Finder get _drawingsLayer => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is KuteChartDrawingsPainter);

/// Screen position of a chart point on the drawings layer.
Offset _at(WidgetTester tester, ChartDrawingPoint p) {
  final layer = _drawingsLayer;
  final painter =
      tester.widget<CustomPaint>(layer).painter as KuteChartDrawingsPainter;
  final geom = painter.resolveGeometry(tester.getSize(layer))!;
  return tester.getTopLeft(layer) + geom.offsetFor(p);
}

Future<void> _mount(WidgetTester tester, {required bool dark}) async {
  await tester.pumpWidget(const SizedBox());
  await pumpHlEditSheet(
    tester,
    theme: dark ? buildDarkTheme() : buildLightTheme(),
    wrap: (child) => RepaintBoundary(
      key: _key,
      child: Builder(
        builder: (context) => ColoredBox(
          color: context.colors.background,
          child: child,
        ),
      ),
    ),
  );
  await enterHlEdit(tester);
}

void main() {
  if (_out.isEmpty) {
    test('Chart drawing rail render', () {},
        skip: 'on demand: --dart-define=CHART_RAIL_OUT=<dir>');
    return;
  }

  setUpAll(() async {
    Directory(_out).createSync(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
    final root = Platform.environment['FLUTTER_ROOT'];
    final icons = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (root != null && icons.existsSync()) {
      final bytes = icons.readAsBytesSync();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });

  final tape = hlEditCandles();
  ChartDrawingPoint at(int bar, double price) => ChartDrawingPoint(
      timeMs: tape[bar].openTime.millisecondsSinceEpoch, price: price);
  final trend = ChartDrawing(
    id: 'trend',
    tool: ChartDrawingTool.trendline,
    points: [at(72, tape[72].low), at(104, tape[104].low)],
  );
  final level = ChartDrawing(
    id: 'level',
    tool: ChartDrawingTool.level,
    points: [at(90, 65400)],
    colorValue: AppColors.warning.toARGB32(),
  );
  final zone = ChartDrawing(
    id: 'zone',
    tool: ChartDrawingTool.rect,
    points: [at(80, 64400), at(96, 64950)],
    colorValue: AppColors.marketUp.toARGB32(),
  );

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('drawing tools, $mode', (tester) async {
      tester.view.devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      await _mount(tester, dark: dark);
      final notifier = hlEditDrawingsNotifier(tester);
      notifier.add(trend);
      notifier.add(level);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The rail, a tool in hand.
      await tester.tap(find.byKey(const ValueKey('hl-chart-rail-trendline')));
      await _settle(tester);
      await _png(tester, 'rail_$mode');

      // The loupe while the first point goes down.
      final gesture =
          await tester.startGesture(_at(tester, at(60, tape[60].high)));
      await tester.pump();
      await _png(tester, 'loupe_$mode');
      await gesture.up();
      await _settle(tester);

      // Back to Cursor; a horizontal line with its price pill.
      await tester.tap(find.byKey(const ValueKey('hl-chart-rail-cursor')));
      await _settle(tester);
      await _png(tester, 'level_pill_$mode');

      // A selected trend line and its toolbar, then its colours.
      final mid = (_at(tester, trend.points[0]) +
              _at(tester, trend.points[1])) /
          2;
      await tester.tapAt(mid);
      await _settle(tester);
      await _png(tester, 'trend_selected_$mode');
      await tester.tap(find.byKey(const ValueKey('hl-drawing-toolbar-color')));
      await _settle(tester);
      await _png(tester, 'trend_colors_$mode');
      await tester.tap(find.byKey(const ValueKey('hl-drawing-swatch-4')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('hl-drawing-toolbar-extend')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('hl-drawing-toolbar-style')));
      await _settle(tester);
      await _png(tester, 'trend_extended_dashed_$mode');

      // A selected zone shows its range.
      notifier.add(zone);
      await _settle(tester);
      await tester.tapAt(_at(tester, at(88, 64700)));
      await _settle(tester);
      await _png(tester, 'zone_selected_$mode');

      // A tool kept in hand (double tap): its small lock.
      final rect = find.byKey(const ValueKey('hl-chart-rail-rect'));
      await tester.tap(rect);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(rect);
      await _settle(tester);
      await _png(tester, 'sticky_$mode');

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
