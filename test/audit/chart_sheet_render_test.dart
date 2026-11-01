// Render harness for the Hyperliquid chart's Chart sheet and the Advanced
// chart's polish (1 November 2026): the sheet over the market page (three
// style cards, the indicator switches, Reset), light and dark; and the
// Advanced chart with EMA 9/21 and RSI on, its legend and labelled pane,
// at rest and with the long-press crosshair's price and time pills. The
// Investing market sheet at 390 x 844 in the app's real theme and Inter.
// Writes PNGs.
//
// Not part of the normal suite; it only runs when asked:
//
//   flutter test test/audit/chart_sheet_render_test.dart \
//     --dart-define=CHART_SHEET_OUT=/tmp/chart-sheet

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/hl_chart_edit_harness.dart';

const _out = String.fromEnvironment('CHART_SHEET_OUT');
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
}

Future<void> _mount(WidgetTester tester, {required bool dark}) async {
  await tester.pumpWidget(const SizedBox());
  await pumpHlEditSheet(
    tester,
    theme: dark ? buildDarkTheme() : buildLightTheme(),
    appBuilder: (context, child) => RepaintBoundary(
      key: _key,
      child: ColoredBox(color: context.colors.background, child: child),
    ),
  );
}

void main() {
  if (_out.isEmpty) {
    test('Chart sheet render', () {},
        skip: 'on demand: --dart-define=CHART_SHEET_OUT=<dir>');
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

    testWidgets('chart sheet, $mode', (tester) async {
      tester.view.devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      await _mount(tester, dark: dark);
      hlEditContainer(tester)
          .read(hlChartPreferencesProvider(hlEditBtcKey).notifier)
          .setIndicators(['vol', 'ema']);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-button')));
      await _settle(tester);
      await _png(tester, 'chart_sheet_$mode');
    });

    testWidgets('advanced chart with EMA and RSI, $mode', (tester) async {
      tester.view.devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      await _mount(tester, dark: dark);
      hlEditContainer(tester)
          .read(hlChartPreferencesProvider(hlEditBtcKey).notifier)
          .setIndicators(['vol', 'ema', 'rsi']);
      await tester.pump();
      await enterHlEdit(tester);
      await _settle(tester);
      await _png(tester, 'advanced_ema_rsi_$mode');

      // The crosshair: a long press with Cursor in hand.
      final legend = find.byKey(const ValueKey('hl-chart-overlay-legend'));
      final at = tester.getTopLeft(legend) + const Offset(170, 110);
      final g = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 600));
      await g.moveTo(at + const Offset(-30, 24));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await _png(tester, 'advanced_crosshair_$mode');
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
    });
  }
}
