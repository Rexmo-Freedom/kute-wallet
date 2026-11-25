// A look by eye at the Advanced chart's grouped tool rail (26 November
// 2026): the rail at rest, the Lines and the Positions and measure
// fly-outs open, a plot carrying one of each tool back on the rail (ray,
// extended line, horizontal ray, vertical line, parallel channel, long
// and short position, price and date range), a long position selected
// with its toolbar, and a zone's settings sheet. On a 390 x 844 and a
// 360 x 640 phone in portrait and an 844 x 390 one in landscape, light
// and dark, in the app's real theme and Inter. Written only when asked:
//
//   flutter test test/render/chart_rail_render_test.dart \
//     --dart-define=CHART_RAIL_OUT=<dir>

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/screens/hyperliquid/components/hl_drawing_tools.dart';
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

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Finder get _layer => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is KuteChartDrawingsPainter);

Offset _at(WidgetTester tester, ChartDrawingPoint p) {
  final painter =
      tester.widget<CustomPaint>(_layer).painter as KuteChartDrawingsPainter;
  final geom = painter.resolveGeometry(tester.getSize(_layer))!;
  return tester.getTopLeft(_layer) + geom.offsetFor(p);
}

Finder _group(String id) => find.descendant(
    of: find.byKey(ValueKey('hl-chart-rail-group-$id')),
    matching: find.byType(HlRailButton));

void main() {
  if (_out.isEmpty) {
    test('Chart rail render', () {},
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
  final up = AppColors.marketUp.toARGB32();
  final blue = 0xFF3B82F6;
  final amber = AppColors.warning.toARGB32();
  final restored = [
    ChartDrawing(
        id: 'ray',
        tool: ChartDrawingTool.ray,
        points: [at(46, 64100), at(62, 64700)],
        colorValue: blue),
    ChartDrawing(
        id: 'ext',
        tool: ChartDrawingTool.extendedLine,
        points: [at(70, 66600), at(90, 66200)]),
    ChartDrawing(
        id: 'hray',
        tool: ChartDrawingTool.horizontalRay,
        points: [at(78, 65900)],
        colorValue: amber),
    ChartDrawing(
        id: 'vline',
        tool: ChartDrawingTool.verticalLine,
        points: [at(104, 65000)],
        dashed: true),
    ChartDrawing(
        id: 'channel',
        tool: ChartDrawingTool.parallelChannel,
        points: [at(52, 64300), at(76, 65200), at(76, 64650)],
        colorValue: blue),
    ChartDrawing(
        id: 'long',
        tool: ChartDrawingTool.longPosition,
        points: [at(92, 65500), at(112, 66500), at(92, 65000)]),
    ChartDrawing(
        id: 'short',
        tool: ChartDrawingTool.shortPosition,
        points: [at(60, 66900), at(74, 66400), at(60, 67150)]),
    ChartDrawing(
        id: 'prange',
        tool: ChartDrawingTool.priceRange,
        points: [at(82, 64300), at(88, 64900)],
        colorValue: up),
    ChartDrawing(
        id: 'drange',
        tool: ChartDrawingTool.dateRange,
        points: [at(94, 64200), at(108, 64500)]),
  ];

  const sizes = {
    'phone': Size(390, 844),
    'small': Size(360, 640),
    'landscape': Size(844, 390),
  };

  for (final MapEntry(key: sizeName, value: size) in sizes.entries) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('rail $sizeName $mode', (tester) async {
        tester.view.devicePixelRatio = _dpr;
        addTearDown(tester.view.reset);
        // Real shadows: the test default draws each as a solid outline.
        debugDisableShadows = false;
        await pumpHlEditSheet(
          tester,
          width: size.width,
          height: size.height,
          theme: dark ? buildDarkTheme() : buildLightTheme(),
          // Around the navigator: the fly-out sheets are in the shot.
          appBuilder: (context, child) => RepaintBoundary(
            key: _key,
            child: ColoredBox(
              color: context.colors.background,
              child: child,
            ),
          ),
        );
        await enterHlEdit(tester);
        await _settle(tester);
        await _png(tester, '${sizeName}_rail_$mode');

        // A sheet (upright phone) closes on its X, a panel on a tap away.
        Future<void> closeFlyout() async {
          final close = find.byKey(const ValueKey('hl-tool-flyout-close'));
          if (close.evaluate().isNotEmpty) {
            await tester.tap(close);
          } else {
            await tester.tapAt(Offset(size.width - 8, size.height - 8));
          }
        }

        // The Lines fly-out.
        await tester.longPress(_group('lines'));
        await _settle(tester);
        await _png(tester, '${sizeName}_lines_$mode');
        await closeFlyout();
        await _settle(tester);

        // The Positions and measure fly-out.
        await tester.longPress(_group('positions'));
        await _settle(tester);
        await _png(tester, '${sizeName}_positions_$mode');
        await closeFlyout();
        await _settle(tester);

        // One of each restored tool on the plot.
        final notifier = hlEditDrawingsNotifier(tester);
        for (final d in restored) {
          notifier.add(d);
        }
        await _settle(tester);
        await _png(tester, '${sizeName}_tools_$mode');

        // A long position selected, its toolbar up.
        await tester.tapAt(_at(tester, at(102, 66000)));
        await _settle(tester);
        await _png(tester, '${sizeName}_long_selected_$mode');

        if (sizeName == 'phone') {
          // The selected position's settings sheet.
          await tester
              .tap(find.byKey(const ValueKey('hl-drawing-toolbar-settings')));
          await _settle(tester);
          await _png(tester, '${sizeName}_settings_$mode');
          await tester
              .tap(find.byKey(const ValueKey('hl-drawing-settings-close')));
          await _settle(tester);
        }

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        debugDisableShadows = true;
      });
    }
  }
}
