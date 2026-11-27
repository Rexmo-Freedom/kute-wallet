// A look by eye at the Advanced chart's price scale (the rail's Price
// scale button on and off): a gold perp in candles and in a line, with
// the Volume and ATR panes, at the desk (1440, 1100) and in a phone's
// editor (390), light and dark. Written only when asked:
//   HL_PRICE_SCALE_RENDER=<dir> flutter test test/render/hl_chart_price_scale_render_test.dart
// Each capture is also read back: the scale's labels and price lines from
// the render tree, and the tag column's ink (pixels unlike the column's
// own background, the latest price's tag left out) from the image.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/hl_chart_edit_harness.dart';
import '../helpers/render_png.dart';
import '../helpers/hl_price_scale_probe.dart';

final _dir = Platform.environment['HL_PRICE_SCALE_RENDER'];

const _gold = HlMarket(
  coin: 'GOLD',
  wireCoin: 'xyz:GOLD',
  assetId: 110003,
  kind: HlMarketKind.perp,
  szDecimals: 4,
  maxLeverage: 20,
  onlyIsolated: false,
  markPx: 4140,
  midPx: 4140,
  prevDayPx: 4100,
  dayNtlVlm: 1e8,
);

/// The tag column's ink: pixels (at the capture's 2x) between the latest
/// price tag's left edge and the chart's right edge, over the plot's
/// whole height, unlike the column's background in their own row (read 2 px in
/// from the right edge, where no label reaches), the tag's band left out.
int _columnInk(ByteData rgba, int imageWidth, Rect chart, Rect tag,
    {double ratio = 2}) {
  var ink = 0;
  final x0 = ((chart.left + tag.left) * ratio).round();
  final x1 = ((chart.right - 2) * ratio).round();
  final y0 = (chart.top * ratio).round();
  final y1 = (chart.bottom * ratio).round();
  for (var y = y0; y < y1; y++) {
    final ly = y / ratio - chart.top;
    if (ly > tag.top - 3 && ly < tag.bottom + 3) continue;
    final ref = (y * imageWidth + x1) * 4;
    for (var x = x0; x < x1; x++) {
      final i = (y * imageWidth + x) * 4;
      var d = 0;
      for (var k = 0; k < 3; k++) {
        final v = (rgba.getUint8(i + k) - rgba.getUint8(ref + k)).abs();
        if (v > d) d = v;
      }
      if (d > 40) ink++;
    }
  }
  return ink;
}

Future<int> _capture(WidgetTester tester, String path) async {
  final chart = tester.getRect(hlLayerFinder('_HlCandlePainter'));
  final tag = lastPriceTag(tester);
  var ink = -1;
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
    ink = _columnInk(raw!, image.width, chart, tag);
    image.dispose();
  });
  return ink;
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final size in [
    const Size(1440, 900),
    const Size(1100, 800),
    const Size(390, 844),
  ]) {
    for (final style in ['candles', 'line']) {
      for (final dark in [false, true]) {
        final name = '${size.width.toInt()}_${style}_${dark ? 'dark' : 'light'}';
        testWidgets('price scale on and off: $name', (tester) async {
          await tester.runAsync(loadRenderFonts);
          // One logical pixel per physical one: the capture is the view.
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetDevicePixelRatio);
          final theme = dark ? buildDarkTheme() : buildLightTheme();
          await pumpHlEditSheet(
            tester,
            width: size.width,
            height: size.height,
            market: _gold,
            candles: goldCandles(),
            theme: theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'Inter')),
          );
          final c = hlEditContainer(tester);
          c.read(hlChartLayoutProvider.notifier).setStyle(style);
          c
              .read(hlChartPreferencesProvider(hlChartDrawingMarketKey(_gold))
                  .notifier)
              .setIndicators(const {'vol', 'atr'});
          await tester.pump();
          await enterHlEdit(tester);
          await tester.pump(const Duration(milliseconds: 600));
          final button =
              find.byKey(const ValueKey('hl-chart-rail-price-scale'));
          expect(button, findsOneWidget);

          final onLabels = scaleLabels(tester).length;
          final onLines = priceLines(tester).length;
          final dir = _dir;
          final onInk = dir == null
              ? null
              : await _capture(tester, '$dir/ps_${name}_on.png');

          await tester.tap(button);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(c.read(hlChartLayoutProvider).priceScale, isFalse);
          final offLabels = scaleLabels(tester).length;
          final offLines = priceLines(tester).length;
          final offInk = dir == null
              ? null
              : await _capture(tester, '$dir/ps_${name}_off.png');

          // ignore: avoid_print
          print('PS $name on: labels=$onLabels lines=$onLines ink=$onInk | '
              'off: labels=$offLabels lines=$offLines ink=$offInk');
          expect(onLabels, greaterThanOrEqualTo(3));
          expect(onLines, greaterThanOrEqualTo(3));
          expect(offLabels, 0);
          expect(offLines, 0);
          if (onInk != null && offInk != null) {
            expect(onInk, greaterThan(200));
            expect(offInk, lessThan(onInk ~/ 10));
          }
          // Back on for the next test's store.
          await tester.tap(button);
          await tester.pump();
        });
      }
    }
  }
}
