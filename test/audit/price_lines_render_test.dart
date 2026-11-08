// Render harness for price lines on the Investing chart: the plain chart
// with lines waiting and one reached, the Advanced chart with the tool in
// hand, the Chart sheet's section, the remove question and the quiet snack
// bar. The market sheet at 390 x 844 in the app's real theme and Inter,
// light and dark. Writes PNGs.
//
// Not part of the normal suite; it only runs when asked:
//
//   flutter test test/audit/price_lines_render_test.dart \
//     --dart-define=PRICE_LINES_OUT=/tmp/price-lines

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/providers/hl_price_lines_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_price_lines_host.dart';
import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/hl_chart_edit_harness.dart';

const _out = String.fromEnvironment('PRICE_LINES_OUT');
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
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  if (_out.isEmpty) {
    test('Price lines render', () {},
        skip: 'on demand: --dart-define=PRICE_LINES_OUT=<dir>');
    return;
  }

  setUpAll(() async {
    Directory(_out).createSync(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        final file = File('lib/assets/fonts/Inter-$f.ttf');
        if (file.existsSync()) {
          inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
        }
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

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('price lines, $mode', (tester) async {
      tester.view.devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      await pumpHlEditSheet(
        tester,
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        // Around the navigator: a sheet and a toast are in the shot.
        appBuilder: (context, child) => RepaintBoundary(
          key: _key,
          child: ColoredBox(
            color: context.colors.background,
            child: child,
          ),
        ),
        wrap: (child) => Stack(children: [
          Positioned.fill(child: child),
          const HlPriceLinesHost(),
        ]),
      );
      final lines = hlEditContainer(tester).read(hlPriceLinesProvider.notifier);
      void set(double level) => lines.add(
          market: hlEditBtc,
          marketKey: hlEditBtcKey,
          level: level,
          reference: 66000);
      set(65200);
      set(64600);
      set(66050);
      await _settle(tester);
      await _png(tester, 'chart_waiting_$mode');

      // The reached one, and the snack bar saying so.
      lines.applyLiveTicks({'BTC': 66060}, (c) => c);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _png(tester, 'chart_reached_snack_$mode');
      await tester.pump(const Duration(seconds: 5));

      // The remove question, from a tap on the waiting line.
      final layer = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is KuteChartDrawingsPainter);
      final painter =
          tester.widget<CustomPaint>(layer).painter as KuteChartDrawingsPainter;
      final geom = painter.resolveGeometry(tester.getSize(layer))!;
      await tester
          .tapAt(tester.getTopLeft(layer) + Offset(120, geom.yForPrice(65200)));
      await _settle(tester);
      await _png(tester, 'remove_question_$mode');
      await tester.tap(find.text('Cancel'));
      await _settle(tester);

      // The Chart sheet's section.
      await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-button')));
      await _settle(tester);
      await _png(tester, 'chart_sheet_$mode');

      // A new line: the sheet closes, Advanced opens with the tool in hand.
      await tester.tap(find.byKey(const ValueKey('hl-chart-price-line-new')));
      await _settle(tester);
      await _png(tester, 'advanced_tool_in_hand_$mode');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });
  }
}
