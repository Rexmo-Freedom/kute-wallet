// Predictions chart tag render harness: draws the market chart
// (market_chart.dart) for a few made-up markets whose lines end where
// their right-edge tags have to share room, in light and dark, and writes
// each as a PNG. Nothing reads the network.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/poly_chart_tags_render_test.dart \
//     --dart-define=CHART_TAGS_RENDER=true \
//     --dart-define=CHART_TAGS_RENDER_OUT=/tmp/kute_chart_tags
//
// The cases: a tennis match (27.5% / 72.5%), a three-way football match
// with its Draw, a landfall market with four lines (53% alone, 28 / 28 /
// 27.5 ending together), a binary Yes at 18%, an Up or Down round, six
// lines, two lines half a point apart, and lines at the top and bottom
// edges; each with the time axis under the plot. Also: the tennis chart
// pinched and panned away from the live edge (the axis ends on a date),
// the binary chart at the peak of the one-time zoom nudge, and a
// tweet-count event's six ranges whose live ticks step at the end
// (tweet_count_*, at the many-outcome chart's height).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/polymarket/components/game_chart_section.dart'
    show kGameSideColors;
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/polymarket/components/outcome_leading.dart'
    show kPolyOutcomeColors;
import 'package:kute/screens/shared/charts/kute_chart_zoom_hint.dart';
import 'package:kute/theme/app_theme.dart';

const _enabled = bool.fromEnvironment('CHART_TAGS_RENDER');
const _outDefine = String.fromEnvironment('CHART_TAGS_RENDER_OUT');

final String _out = _outDefine.isNotEmpty
    ? _outDefine
    : '${Directory.systemTemp.path}/kute_chart_tags';

const _phone = Size(393, 852);
const _shotKey = ValueKey('chart-tags-render-shot');

class _Quiet extends LivePriceNotifier {
  @override
  LivePriceState build() => LivePriceState(live: false);
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void pause() {}
  @override
  void resume() {}
  @override
  void subscribeTokens(List<String> tokenIds) {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void registerCardTokens(List<String> tokenIds) {}
  @override
  void unregisterCardTokens(List<String> tokenIds) {}
  @override
  void removeTokens(List<String> tokenIds) {}
  @override
  void unsubscribeAll() {}
}

final int _nowMs = DateTime.now().millisecondsSinceEpoch;
const _hour = 3600000;

/// A week of hourly points from [from] to [to], with a little wobble
/// ([seed] keeps each line's own).
List<PolymarketPricePoint> _line(double from, double to, int seed) => [
      for (var i = 0; i <= 168; i++)
        PolymarketPricePoint(
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              _nowMs - (168 - i) * _hour),
          price: (from +
                  (to - from) * i / 168 +
                  (i == 168
                      ? 0
                      : 0.025 *
                          math.sin(i / (5 + seed)) *
                          math.min(1.0, (168 - i) / 24)))
              .clamp(0.002, 0.998),
        ),
    ];

typedef _Spec = ({String label, Color color, double from, double to});

final Map<String, List<_Spec>> _cases = {
  'tennis': [
    (label: 'Viktoria Hruncakova', color: kGameSideColors[0], from: 0.45, to: 0.275),
    (label: 'Himeno Sakatsume', color: kGameSideColors[1], from: 0.55, to: 0.725),
  ],
  'three_way': [
    (label: 'Arsenal', color: kGameSideColors[0], from: 0.40, to: 0.47),
    (label: 'Draw', color: kGameSideColors[2], from: 0.28, to: 0.26),
    (label: 'Manchester City', color: kGameSideColors[1], from: 0.32, to: 0.27),
  ],
  'isaias': [
    (label: 'Louisiana', color: kPolyOutcomeColors[0], from: 0.35, to: 0.53),
    (label: 'Mississippi', color: kPolyOutcomeColors[1], from: 0.20, to: 0.28),
    (label: 'Alabama', color: kPolyOutcomeColors[2], from: 0.31, to: 0.28),
    (label: 'Florida', color: kPolyOutcomeColors[3], from: 0.38, to: 0.275),
  ],
  'binary_yes': [
    (label: 'Yes', color: AppColors.marketUp, from: 0.31, to: 0.18),
  ],
  'up_down': [
    (label: 'Up', color: AppColors.marketUp, from: 0.50, to: 0.51),
    (label: 'Down', color: AppColors.marketDown, from: 0.50, to: 0.49),
  ],
  'six_lines': [
    (label: 'Gavin Newsom', color: kPolyOutcomeColors[0], from: 0.30, to: 0.41),
    (label: 'Josh Shapiro', color: kPolyOutcomeColors[1], from: 0.18, to: 0.22),
    (label: 'Pete Buttigieg', color: kPolyOutcomeColors[2], from: 0.12, to: 0.13),
    (label: 'Alexandria Ocasio-Cortez', color: kPolyOutcomeColors[3], from: 0.10, to: 0.09),
    (label: 'Wes Moore', color: kPolyOutcomeColors[4], from: 0.06, to: 0.085),
    (label: 'Andy Beshear', color: kPolyOutcomeColors[5], from: 0.07, to: 0.08),
  ],
  'half_point': [
    (label: 'Over 2.5', color: kPolyOutcomeColors[0], from: 0.44, to: 0.505),
    (label: 'Under 2.5', color: kPolyOutcomeColors[1], from: 0.56, to: 0.50),
  ],
  'top_edge': [
    (label: 'Jannik Sinner', color: kGameSideColors[0], from: 0.93, to: 0.99),
    (label: 'Carlos Alcaraz', color: kGameSideColors[1], from: 0.90, to: 0.98),
  ],
  'bottom_edge': [
    (label: 'Netherlands', color: kPolyOutcomeColors[0], from: 0.08, to: 0.02),
    (label: 'Belgium', color: kPolyOutcomeColors[1], from: 0.05, to: 0.01),
  ],
};

/// A tweet-count event's six ranges: hourly history for two days, then
/// live ticks seconds apart at the end, where the leader steps up and the
/// runner-up drops (the shape whose curve shot out of the plot).
List<PolymarketPricePoint> _ticked(
    double from, double to, List<double> ticks, int seed) {
  final hourly = [
    for (var i = 0; i <= 47; i++)
      PolymarketPricePoint(
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(_nowMs - (48 - i) * _hour),
        price: (from +
                (to - from) * i / 47 +
                0.01 * math.sin(i / (3 + seed)))
            .clamp(0.001, 0.999),
      ),
  ];
  return [
    ...hourly,
    for (var k = 0; k < ticks.length; k++)
      PolymarketPricePoint(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            _nowMs - (ticks.length - k) * 15000),
        price: ticks[k],
      ),
  ];
}

typedef _Ticked = ({String label, Color color, List<PolymarketPricePoint> points});

final Map<String, List<_Ticked>> _tickedCases = {
  'tweet_count': [
    (label: '40-64', color: kPolyOutcomeColors[0], points: _ticked(0.55, 0.78, [0.80, 0.90, 0.921], 0)),
    (label: '65-89', color: kPolyOutcomeColors[1], points: _ticked(0.30, 0.19, [0.17, 0.09, 0.076], 1)),
    (label: '<40', color: kPolyOutcomeColors[2], points: _ticked(0.04, 0.004, [0.003, 0.001, 0.001], 2)),
    (label: '90-114', color: kPolyOutcomeColors[3], points: _ticked(0.06, 0.02, [0.015, 0.006, 0.004], 3)),
    (label: '115-139', color: kPolyOutcomeColors[4], points: _ticked(0.03, 0.01, [0.008, 0.003, 0.002], 4)),
    (label: '140+', color: kPolyOutcomeColors[5], points: _ticked(0.02, 0.006, [0.005, 0.002, 0.001], 5)),
  ],
};

Future<void> _show(WidgetTester tester, Widget child,
    {required bool dark,
    List<Override> overrides = const [],
    bool settle = true}) async {
  tester.view.physicalSize = _phone * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: overrides,
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepaintBoundary(
          key: _shotKey,
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: context.colors.background,
              body: SafeArea(child: child),
            ),
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < (settle ? 30 : 2); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  // ignore: avoid_print
  print('RENDER wrote $name.png');
}

void main() {
  if (!_enabled) {
    test('chart tags render', () {},
        skip: 'on demand: --dart-define=CHART_TAGS_RENDER=true');
    return;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Directory(_out).createSync(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [
      GoogleFonts.inter().fontFamily!,
      'Inter',
      'FlutterTest'
    ]) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => '$_out/cache');
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
        as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  for (final entry in _tickedCases.entries) {
    for (final dark in [false, true]) {
      final name = '${entry.key}_${dark ? 'dark' : 'light'}';
      testWidgets(name, (tester) async {
        final specs = entry.value;
        var seen = true;
        KuteZoomHint.debugReset(read: () => seen, write: () => seen = true);
        addTearDown(KuteZoomHint.debugReset);
        await _show(
          tester,
          Padding(
            padding: const EdgeInsets.all(16),
            child: MarketChart(
              lines: [
                for (var i = 0; i < specs.length; i++)
                  MarketChartLine(
                    tokenId: 'tok$i',
                    color: specs[i].color,
                    label: specs[i].label,
                    livePrice: specs[i].points.last.price,
                  ),
              ],
              height: polyChartHeightFor(specs.length),
            ),
          ),
          dark: dark,
          overrides: [
            livePriceProvider.overrideWith(_Quiet.new),
            polymarketMarketHistoryProvider.overrideWith((ref, arg) async =>
                specs[int.parse(arg.tokenId.substring(3))].points),
          ],
        );
        await _shot(tester, name);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 8));
      });
    }
  }

  for (final entry in _cases.entries) {
    for (final dark in [false, true]) {
      final name = '${entry.key}_${dark ? 'dark' : 'light'}';
      testWidgets(name, (tester) async {
        final specs = entry.value;
        final history = {
          for (var i = 0; i < specs.length; i++)
            'tok$i': _line(specs[i].from, specs[i].to, i),
        };
        var seen = true;
        KuteZoomHint.debugReset(read: () => seen, write: () => seen = true);
        addTearDown(KuteZoomHint.debugReset);
        await _show(
          tester,
          Padding(
            padding: const EdgeInsets.all(16),
            child: MarketChart(
              lines: [
                for (var i = 0; i < specs.length; i++)
                  MarketChartLine(
                    tokenId: 'tok$i',
                    color: specs[i].color,
                    label: specs[i].label,
                    livePrice: specs[i].to,
                  ),
              ],
              height: 220,
            ),
          ),
          dark: dark,
          overrides: [
            livePriceProvider.overrideWith(_Quiet.new),
            polymarketMarketHistoryProvider.overrideWith(
                (ref, arg) async => history[arg.tokenId] ?? const []),
          ],
        );
        if (entry.key == 'binary_yes') {
          // The one-time zoom nudge at its peak: a fresh chart on a device
          // that never saw it.
          seen = false;
          KuteZoomHint.debugReset(read: () => seen, write: () => seen = true);
          await _show(
            tester,
            Padding(
              padding: const EdgeInsets.all(16),
              child: MarketChart(
                key: UniqueKey(),
                lines: [
                  MarketChartLine(
                    tokenId: 'tok0',
                    color: specs[0].color,
                    label: specs[0].label,
                    livePrice: specs[0].to,
                  ),
                ],
                height: 220,
              ),
            ),
            dark: dark,
            settle: false,
            overrides: [
              livePriceProvider.overrideWith(_Quiet.new),
              polymarketMarketHistoryProvider.overrideWith(
                  (ref, arg) async => history[arg.tokenId] ?? const []),
            ],
          );
          await tester.pump(kKuteZoomNudgeDelay);
          await tester.pump(const Duration(milliseconds: 400));
          await _shot(tester, '${name}_nudge_peak');
          await tester.pump(const Duration(milliseconds: 600));
        }
        await _shot(tester, name);
        if (entry.key == 'tennis') {
          // Pinch in, then pan back in time.
          final rect = tester.getRect(find.byType(MarketChart));
          final y = rect.top + 90;
          final a = await tester.startGesture(Offset(rect.center.dx - 30, y));
          final b = await tester.startGesture(Offset(rect.center.dx + 30, y),
              pointer: 2);
          for (var i = 1; i <= 6; i++) {
            await a.moveTo(Offset(rect.center.dx - 30 - i * 18, y));
            await b.moveTo(Offset(rect.center.dx + 30 + i * 18, y));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await a.up();
          await b.up();
          await tester.pump(const Duration(milliseconds: 300));
          final d = await tester.startGesture(Offset(rect.center.dx - 80, y));
          for (var i = 1; i <= 8; i++) {
            await d.moveTo(Offset(rect.center.dx - 80 + i * 20, y));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await d.up();
          await tester.pump(const Duration(milliseconds: 400));
          await _shot(tester, '${name}_panned');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 8));
      });
    }
  }
}
