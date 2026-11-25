// Render harness for the Advanced chart's Funding pane: a BTC perp on an
// hourly and a 4-hour tape with a made-up but Hyperliquid-shaped funding
// history (mostly longs paying, a stretch of shorts paying), alone and
// beside RSI, with the crosshair up, and its loading, empty and error
// states; phone portrait (390x844), phone landscape (844x390) and a wide
// window (1440x900), light and dark, in the app's theme and Inter.
//
// Not part of the normal suite; it only runs when asked:
//
//   flutter test test/render/chart_funding_render_test.dart \
//     --dart-define=CHART_FUNDING_OUT=/tmp/chart-funding

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/providers/hyperliquid_funding_history_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/hl_chart_edit_harness.dart';

const _out = String.fromEnvironment('CHART_FUNDING_OUT');
const _key = ValueKey('shot');
const _dpr = 2.0;
const _h = 3600000;

/// The harness' BTC perp with the venue's live rate: about 11 % a year,
/// longs paying.
const _btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 66000,
  midPx: 66000,
  prevDayPx: 65000,
  dayNtlVlm: 1e9,
  funding: 0.0000125,
);

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
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// A history over [tape]: about 0.00125 %/h (the venue's interest
/// floor) with a premium swing, and a day where shorts paid.
HlFundingFetch _history(List<HyperliquidCandle> tape) =>
    (coin, start, end) async {
      final first = tape.first.openTime.millisecondsSinceEpoch;
      final last = tape.last.closeTime.millisecondsSinceEpoch;
      final out = <({int timeMs, double rate})>[];
      var i = 0;
      for (var t = (first ~/ _h + 1) * _h; t <= last; t += _h, i++) {
        if (t < start || t > end) continue;
        var r = 0.0000125 +
            0.000012 * math.sin(i / 9) +
            0.000004 * math.cos(i / 2.1);
        final day = i ~/ 24;
        if (day % 5 == 3) r -= 0.000035;
        out.add((timeMs: t + 41, rate: r));
      }
      return out;
    };

Future<void> _mount(
  WidgetTester tester, {
  required Size size,
  required bool dark,
  required List<String> keys,
  List<HyperliquidCandle>? tape,
  HlFundingFetch? fetch,
  String interval = '1h',
}) async {
  tester.view.devicePixelRatio = _dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  final t = tape ?? hlEditCandles(count: 200);
  await pumpHlEditSheet(
    tester,
    width: size.width,
    height: size.height,
    theme: dark ? buildDarkTheme() : buildLightTheme(),
    candles: t,
    fundingFetch: fetch ?? _history(t),
    market: _btc,
    appBuilder: (context, child) => RepaintBoundary(
      key: _key,
      child: ColoredBox(color: context.colors.background, child: child),
    ),
  );
  final c = hlEditContainer(tester);
  c.read(hlChartPreferencesProvider(hlEditBtcKey).notifier).setIndicators(keys);
  c.read(hlChartLayoutProvider.notifier)
    ..setStyle('candles')
    ..setInterval(interval);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await enterHlEdit(tester);
  await _settle(tester);
}

void main() {
  if (_out.isEmpty) {
    test('Funding pane render', () {},
        skip: 'on demand: --dart-define=CHART_FUNDING_OUT=<dir>');
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

  const sizes = {
    'phone': Size(390, 844),
    'landscape': Size(844, 390),
    'wide': Size(1440, 900),
  };

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    for (final MapEntry(key: name, value: size) in sizes.entries) {
      final tag = '${name}_$theme';

      testWidgets('funding alone, $tag', (tester) async {
        await _mount(tester,
            size: size, dark: dark, keys: ['vol', 'fund']);
        await _png(tester, 'funding_1h_$tag');
      });

      testWidgets('funding beside RSI, $tag', (tester) async {
        await _mount(tester,
            size: size, dark: dark, keys: ['vol', 'ema', 'rsi', 'fund']);
        await _png(tester, 'funding_rsi_$tag');
      });

      testWidgets('funding on 4h bars, $tag', (tester) async {
        final tape =
            hlEditCandles(count: 160, step: const Duration(hours: 4));
        await _mount(tester,
            size: size,
            dark: dark,
            keys: ['vol', 'fund'],
            tape: tape,
            interval: '4h');
        await _png(tester, 'funding_4h_$tag');
      });

      testWidgets('funding with the crosshair, $tag', (tester) async {
        await _mount(tester, size: size, dark: dark, keys: ['vol', 'fund']);
        final plot = find.byKey(const ValueKey('hl-chart-funding-pane'));
        final box = tester.getRect(plot);
        // Hold a finger on the price plot above the pane.
        final g = await tester.startGesture(
            Offset(box.left + box.width * 0.55, box.top - 120));
        await tester.pump(const Duration(milliseconds: 700));
        await g.moveBy(const Offset(4, 0));
        await tester.pump(const Duration(milliseconds: 100));
        await _png(tester, 'funding_scrub_$tag');
        await g.up();
        await tester.pump();
      });
    }

    for (final (state, fetch) in <(String, HlFundingFetch)>[
      ('loading', (coin, s, e) => Completer<List<({int timeMs, double rate})>>().future),
      ('empty', (coin, s, e) async => const []),
      ('error', (coin, s, e) async => throw Exception('down')),
    ]) {
      testWidgets('funding $state, phone $theme', (tester) async {
        await _mount(tester,
            size: sizes['phone']!,
            dark: dark,
            keys: ['vol', 'fund'],
            fetch: fetch);
        await _png(tester, 'funding_${state}_phone_$theme');
      });
    }
  }
}
