// On demand: renders the P&L chart (with history, scrubbing, and without
// history) and the Balance chart on the modern line chart, light and
// dark, with the app's Inter face, into PNGs for a look by eye.
//
//   flutter test test/screens/shared/charts/trend_chart_render_test.dart \
//     --dart-define=TREND_RENDER_OUT=scratchpad/r3-charts

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/analytics/components/balance_history_chart.dart';
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart';
import 'package:kute/theme/app_theme.dart';

const _out = String.fromEnvironment('TREND_RENDER_OUT');
final _shotKey = GlobalKey();
final _now = DateTime(2026, 10, 31, 17, 0);

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: '',
      reviewDone: true,
      balancePrivacy: 0,
    );

PortfolioPerformance _pnl(List<(int, double)> daysAgoAndPnl) =>
    PortfolioPerformance(
      points: [
        for (final (d, v) in daysAgoAndPnl)
          PortfolioPnlPoint(
              timestamp: _now.subtract(Duration(days: d, hours: 3)),
              pnlUsd: v),
      ],
      totalPnlUsd: daysAgoAndPnl.isEmpty ? null : daysAgoAndPnl.last.$2,
      sourceLabel: 'Hyperliquid',
      basisLabel: 'Reported account P&L',
      coverageLabel: 'All time',
    );

final _history = _pnl([
  (70, 0),
  (60, 4.2),
  (55, 9.8),
  (50, 6.1),
  (45, 14.3),
  (40, 11.9),
  (35, 18.6),
  (30, 22.4),
  (27, 19.2),
  (24, 25.7),
  (20, 31.0),
  (17, 28.4),
  (14, 36.9),
  (11, 33.2),
  (8, 41.5),
  (5, 45.3),
  (3, 42.8),
  (1, 51.7),
  (0, 54.24),
]);

final _balance = BalanceHistory(
  opening: 0,
  changes: [
    (_now.subtract(const Duration(days: 80)), 120000),
    (_now.subtract(const Duration(days: 44)), 260000),
    (_now.subtract(const Duration(days: 31)), 215000),
    (_now.subtract(const Duration(days: 20)), 340000),
    (_now.subtract(const Duration(days: 12)), 310000),
    (_now.subtract(const Duration(days: 4)), 402000),
  ],
  current: 402000,
);

Future<void> _show(WidgetTester tester, Widget child,
    {required bool dark}) async {
  tester.view.physicalSize = const Size(390, 560) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        locale: const Locale('en'),
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RepaintBoundary(
            key: _shotKey,
            child: Builder(
              builder: (context) => Container(
                color: context.colors.background,
                padding: const EdgeInsets.all(16),
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  // Past the draw-in.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  if (_out.isEmpty) {
    test('trend chart render', () {},
        skip: 'on demand: --dart-define=TREND_RENDER_OUT=<dir>');
    return;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Directory(_out).createSync(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('P&L chart $mode', (tester) async {
      await _show(tester,
          PortfolioPnlChart(venue: null, data: _history, now: _now),
          dark: dark);
      await _shot(tester, 'pnl_$mode');
      // A finger on the line.
      final plot = tester.getRect(find.byKey(const ValueKey('trend-chart-plot')));
      final touch = await tester.startGesture(
          Offset(plot.left + plot.width * 0.55, plot.center.dy));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 150));
      await _shot(tester, 'pnl_${mode}_scrub');
      await touch.up();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('ALL'));
      await tester.pump(const Duration(milliseconds: 500));
      await _shot(tester, 'pnl_${mode}_all');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('P&L chart without history $mode', (tester) async {
      await _show(tester,
          PortfolioPnlChart(venue: null, data: _pnl(const []), now: _now),
          dark: dark);
      await _shot(tester, 'pnl_empty_$mode');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Balance chart $mode', (tester) async {
      await _show(
          tester,
          Builder(
            builder: (context) => Container(
              decoration: AppDecorations.card(context),
              padding: const EdgeInsets.all(16),
              child: BalanceHistoryChart(
                history: _balance,
                format: (sats) => '₿${sats.round()}',
                secondary: (sats) =>
                    '\$${(sats / 1e8 * 71250).toStringAsFixed(2)}',
                trackingChart: 'valuation',
                now: _now,
              ),
            ),
          ),
          dark: dark);
      await _shot(tester, 'balance_$mode');
      final plot = tester.getRect(find.byKey(const ValueKey('trend-chart-plot')));
      final touch = await tester.startGesture(
          Offset(plot.left + plot.width * 0.4, plot.center.dy));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 150));
      await _shot(tester, 'balance_${mode}_scrub');
      await touch.up();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
