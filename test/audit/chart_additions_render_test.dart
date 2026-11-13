// Render harness for the Investing chart's additions (8 November 2026):
// the Chart sheet with Hollow candles, Baseline, the Display squares and
// the new indicators; Ichimoku, Pivots and ADX on a real-shaped tape; log
// on and off; Baseline with and without a position; the person's own
// trades on a line and on candles; the Interval sheet with seven; and a
// big move with Bollinger bands, on the page and in Advanced. Light and
// dark, 320 and 375 wide, in the app's real theme and Inter. Writes PNGs.
//
// Not part of the normal suite; it only runs when asked:
//
//   flutter test test/audit/chart_additions_render_test.dart \
//     --dart-define=CHART_ADD_OUT=/tmp/chart-add

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
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_series.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/hl_chart_edit_harness.dart';

const _out = String.fromEnvironment('CHART_ADD_OUT');
const _key = ValueKey('shot');
const _dpr = 2.0;

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

/// A BTC-shaped hourly tape: a seeded walk with quiet and busy stretches,
/// ending at 66,000. [bigMove] drops a 5% one-way move on the last hours.
List<HyperliquidCandle> _tape({int count = 400, bool bigMove = false}) {
  final rnd = math.Random(7);
  final start = DateTime.utc(2026, 10, 1);
  final bars = <HyperliquidCandle>[];
  var price = 64000.0;
  for (var i = 0; i < count; i++) {
    final busy = 0.5 + 1.5 * math.sin(i / 37).abs();
    var step = (rnd.nextDouble() - 0.5) * 260 * busy + 20 * math.sin(i / 23);
    if (bigMove && i >= count - 14 && i < count - 8) step = -560;
    final open = price;
    final close = open + step;
    final high = math.max(open, close) + rnd.nextDouble() * 90 * busy;
    final low = math.min(open, close) - rnd.nextDouble() * 90 * busy;
    bars.add(HyperliquidCandle(
      openTime: start.add(Duration(hours: i)),
      closeTime: start.add(Duration(hours: i + 1)),
      open: open,
      high: high,
      low: low,
      close: close,
      volume: 40 + rnd.nextDouble() * 120 * busy,
    ));
    price = close;
  }
  final d = 66000 - bars.last.close;
  return [
    for (final k in bars)
      HyperliquidCandle(
        openTime: k.openTime,
        closeTime: k.closeTime,
        open: k.open + d,
        high: k.high + d,
        low: k.low + d,
        close: k.close + d,
        volume: k.volume,
      ),
  ];
}

HlFill _fill(HyperliquidCandle k, int id, {required bool buy, String dir = ''}) =>
    HlFill(
      coin: 'BTC',
      px: (k.high + k.low) / 2,
      sz: 0.01,
      side: buy ? 'B' : 'A',
      time: k.openTime.millisecondsSinceEpoch + 60000 + id,
      closedPnl: 0,
      fee: 0,
      feeToken: 'USDC',
      oid: id,
      hash: '$id',
      dir: dir,
      cloid: null,
      tradeId: '$id',
    );

/// An entry and an exit, a closed position long ago, and a burst of three
/// in one bar.
List<HlFill> _fills(List<HyperliquidCandle> t) {
  final n = t.length;
  return [
    _fill(t[n - 80], 1, buy: true, dir: 'Open Long'),
    _fill(t[n - 52], 2, buy: false, dir: 'Close Long'),
    _fill(t[n - 40], 3, buy: false, dir: 'Open Short'),
    _fill(t[n - 24], 4, buy: true, dir: 'Close Short'),
    _fill(t[n - 14], 5, buy: true, dir: 'Open Long'),
    _fill(t[n - 14], 6, buy: true, dir: 'Open Long'),
    _fill(t[n - 14], 7, buy: true, dir: 'Open Long'),
  ];
}

const _position = HlPerpPosition(
  coin: 'BTC',
  szi: 0.03,
  entryPx: 65300,
  positionValue: 1980,
  unrealizedPnl: 21,
  returnOnEquity: 0.01,
  liquidationPx: 59000,
  marginUsed: 198,
  leverageType: 'cross',
  leverageValue: 10,
  maxLeverage: 40,
);

Future<void> _mount(
  WidgetTester tester, {
  required bool dark,
  required double width,
  List<HyperliquidCandle>? candles,
  List<HlFill> fills = const [],
  List<HlPerpPosition> positions = const [],
}) async {
  tester.view.devicePixelRatio = _dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  final tape = candles ?? _tape();
  await pumpHlEditSheet(
    tester,
    width: width,
    height: width < 350 ? 640 : 812,
    theme: dark ? buildDarkTheme() : buildLightTheme(),
    candles: tape,
    fills: fills,
    positions: positions,
    daily: hlDailyFromBars(tape),
    appBuilder: (context, child) => RepaintBoundary(
      key: _key,
      child: ColoredBox(color: context.colors.background, child: child),
    ),
  );
}

void _seed(WidgetTester tester,
    {List<String>? keys, bool log = false, String? style}) {
  final c = hlEditContainer(tester);
  final prefs = c.read(hlChartPreferencesProvider(hlEditBtcKey).notifier);
  if (keys != null) prefs.setIndicators(keys);
  prefs.setLogScale(log);
  if (style != null) c.read(hlChartLayoutProvider.notifier).setStyle(style);
}

void main() {
  if (_out.isEmpty) {
    test('Chart additions render', () {},
        skip: 'on demand: --dart-define=CHART_ADD_OUT=<dir>');
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
    for (final width in [320.0, 375.0]) {
      final tag = '${width.round()}_${dark ? 'dark' : 'light'}';

      testWidgets('chart sheet, $tag', (tester) async {
        await _mount(tester, dark: dark, width: width, fills: _fills(_tape()));
        _seed(tester, keys: ['vol', 'ichi', 'adx'], log: true);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-button')));
        await _settle(tester);
        await _png(tester, 'sheet_top_$tag');
        final scroll = find.byKey(const ValueKey('hl-chart-sheet-scroll'));
        await tester.drag(scroll, const Offset(0, -340));
        await _settle(tester);
        await _png(tester, 'sheet_display_$tag');
        await tester.drag(scroll, const Offset(0, -420));
        await _settle(tester);
        await _png(tester, 'sheet_trend_$tag');
        await tester.drag(scroll, const Offset(0, -420));
        await _settle(tester);
        await _png(tester, 'sheet_momentum_$tag');
      });

      testWidgets('interval sheet, $tag', (tester) async {
        await _mount(tester, dark: dark, width: width);
        await _png(tester, 'page_row_$tag');
        await enterHlEdit(tester);
        await _settle(tester);
        await tester
            .tap(find.byKey(const ValueKey('hl-chart-edit-interval-button')));
        await _settle(tester);
        await _png(tester, 'interval_sheet_$tag');
      });

      for (final (name, keys, log, style) in <(String, List<String>, bool, String)>[
        ('ichimoku', ['vol', 'ichi'], false, 'candles'),
        ('pivots', ['vol', 'pp'], false, 'candles'),
        ('adx', ['vol', 'adx'], false, 'candles'),
        ('log_on', ['vol', 'ema', 'bb'], true, 'candles'),
        ('log_off', ['vol', 'ema', 'bb'], false, 'candles'),
        ('hollow', ['vol'], false, 'hollow'),
        ('baseline_first', ['vol'], false, 'baseline'),
      ]) {
        testWidgets('$name advanced, $tag', (tester) async {
          await _mount(tester, dark: dark, width: width);
          _seed(tester, keys: keys, log: log, style: style);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          await enterHlEdit(tester);
          await _settle(tester);
          await _png(tester, '${name}_$tag');
        });
      }

      testWidgets('baseline on the entry, $tag', (tester) async {
        await _mount(tester,
            dark: dark, width: width, positions: const [_position]);
        _seed(tester, keys: ['vol'], style: 'baseline');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await enterHlEdit(tester);
        await _settle(tester);
        await _png(tester, 'baseline_entry_$tag');
      });

      testWidgets('own trades, $tag', (tester) async {
        final t = _tape();
        await _mount(tester, dark: dark, width: width, fills: _fills(t));
        _seed(tester, keys: ['vol'], style: 'candles');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await _settle(tester);
        await _png(tester, 'trades_candles_page_$tag');
        await enterHlEdit(tester);
        await _settle(tester);
        await _png(tester, 'trades_candles_$tag');
        _seed(tester, style: 'line');
        await _settle(tester);
        await _png(tester, 'trades_line_$tag');
      });

      testWidgets('1W with everything the limits allow, $tag', (tester) async {
        final start = DateTime.utc(2021, 1, 4);
        final hourly = _tape(count: 300);
        final weekly = [
          for (var i = 0; i < hourly.length; i++)
            HyperliquidCandle(
              openTime: start.add(Duration(days: 7 * i)),
              closeTime: start.add(Duration(days: 7 * (i + 1))),
              open: hourly[i].open,
              high: hourly[i].high,
              low: hourly[i].low,
              close: hourly[i].close,
              volume: hourly[i].volume,
            ),
        ];
        await _mount(tester, dark: dark, width: width, candles: weekly);
        _seed(tester,
            keys: ['vol', 'ichi', 'pp', 'bb', 'st', 'adx', 'rsi'],
            style: 'candles');
        hlEditContainer(tester).read(hlChartLayoutProvider.notifier)
            .setInterval('1w');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await enterHlEdit(tester);
        await _settle(tester);
        await _png(tester, 'week_all_on_$tag');
      });

      testWidgets('big move with bands, $tag', (tester) async {
        final t = _tape(bigMove: true);
        await _mount(tester, dark: dark, width: width, candles: t);
        _seed(tester, keys: ['vol', 'bb'], style: 'candles');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await _settle(tester);
        await _png(tester, 'bands_big_move_page_$tag');
        await enterHlEdit(tester);
        await _settle(tester);
        await _png(tester, 'bands_big_move_advanced_$tag');
      });
    }
  }
}
