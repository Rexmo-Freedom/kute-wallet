// Chart render harness: draws the balance and price charts (Home, the
// Dollars balance, a watch-only wallet, the Investing and Predictions
// statistics) and the venue charts they follow (a Predictions market
// chart, an Investing position chart) from made-up but realistic series,
// at rest and with the scrub card up, in light and dark, in English and
// Portuguese, and writes each as a PNG. Nothing reads the network.
//
// Not part of the normal suite; it only runs when asked:
//
//   flutter test test/audit/chart_align_render_test.dart \
//     --dart-define=CHART_AUDIT=true \
//     --dart-define=CHART_AUDIT_OUT=/tmp/kute_chart_render
//
// Add --dart-define=CHART_AUDIT_ONLY=home to draw the cases whose name
// contains that text.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:coingecko_api/data/market_chart_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/analytics_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/coingecko_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/screens/shared/charts/kute_chart_trade_lines.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/usd/components/usd_balance_chart.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

const _enabled = bool.fromEnvironment('CHART_AUDIT');
const _outDefine = String.fromEnvironment('CHART_AUDIT_OUT');
const _only = String.fromEnvironment('CHART_AUDIT_ONLY');

final String _out = _outDefine.isNotEmpty
    ? _outDefine
    : '${Directory.systemTemp.path}/kute_chart_render';

const _phone = Size(393, 852);
const _shotKey = ValueKey('chart-render-shot');

// ───────────────────────────── data ─────────────────────────────

DateTime _day(int ago) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - ago);
}

/// A year of daily BTC prices: a slow climb with a few swings.
final List<MarketChartData> _prices = [
  for (var ago = 365; ago >= 0; ago--)
    MarketChartData(
      _day(ago).add(const Duration(hours: 12)),
      price: 61000 +
          9000 * (365 - ago) / 365 +
          2600 * math.sin(ago / 9) +
          900 * math.sin(ago / 2.3),
      marketCap: 0,
      totalVolume: 0,
    ),
];

/// Sats held each day, stepping on the days the balance changed (the
/// provider hands the chart one value per day).
const _satsChanges = {
  120: 400000.0,
  40: 900000.0,
  22: 1250000.0,
  9: 1100000.0,
  3: 1480000.0,
};

/// The same balance as the moments it changed (mid-morning each time),
/// for the Balance charts.
final BalanceHistory _satsHistory = BalanceHistory(
  opening: 0,
  changes: [
    for (final e in _satsChanges.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key)))
      (_day(e.key).add(const Duration(hours: 10)), e.value),
  ],
  current: 1480000,
);

final Map<DateTime, double> _satsByDay = () {
  const changes = _satsChanges;
  final out = <DateTime, double>{};
  var held = 0.0;
  for (var ago = 400; ago >= 0; ago--) {
    held = changes[ago] ?? held;
    out[_day(ago)] = held;
  }
  return out;
}();

class _Market extends BitcoinMarketDataNotifier {
  @override
  Future<List<MarketChartData>> build() async => _prices;
}

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

Settings _settings(String language,
        {WalletConfig? wallet, int balancePrivacy = 0}) =>
    Settings(
      currency: 'USD',
      balancePrivacy: balancePrivacy,
      language: language,
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: '',
      reviewDone: true,
      activeWalletId: 'spending',
      wallets: [
        WalletConfig(id: 'spending', name: 'Spending'),
        if (wallet != null) wallet,
      ],
    );

List<Override> _bitcoinOverrides(String language, {WalletConfig? viewed}) => [
      settingsProvider
          .overrideWith((_) => SettingsModel(_settings(language, wallet: viewed))),
      bitcoinMarketDataProvider.overrideWith(_Market.new),
      bitcoinBalanceInFormatByDayProvider.overrideWith((_) => _satsByDay),
      bitcoinBalanceStepsProvider.overrideWith((_) => _satsHistory),
      viewedWalletBalanceProvider.overrideWithValue(WalletBalance(
        onChainBtcBalance: viewed == null ? 0 : 1480000,
        sparkBitcoinbalance: viewed == null ? 1480000 : 0,
      )),
      polymarketBalanceProvider.overrideWith((_) => 0),
      selectedCurrencyProvider.overrideWith((ref, code) =>
          Money.fromNumWithCurrency(70000, AppCurrencies.usd)),
      selectedCurrencyProviderFromUSD.overrideWith(
          (ref, code) => Money.fromNumWithCurrency(1, AppCurrencies.usd)),
      viewedWalletProvider.overrideWithValue(viewed),
      viewedWalletTransactionsProvider.overrideWithValue(Transaction.empty()),
    ];

/// Daily P&L over two months.
PortfolioPerformance _performance(bool predictions) {
  final now = DateTime.now().toUtc();
  final points = <PortfolioPnlPoint>[];
  for (var ago = 60; ago >= 0; ago--) {
    final t = DateTime.utc(now.year, now.month, now.day - ago, 23);
    final v = predictions
        ? -4 + 0.55 * (60 - ago) + 6 * math.sin(ago / 5)
        : 12 + 0.9 * (60 - ago) - 9 * math.sin(ago / 7);
    points.add(PortfolioPnlPoint(timestamp: t, pnlUsd: v));
  }
  return PortfolioPerformance(
    points: points,
    totalPnlUsd: points.last.pnlUsd,
    realizedPnlUsd: points.last.pnlUsd * 0.6,
    openPnlUsd: points.last.pnlUsd * 0.4,
    sourceLabel: predictions ? 'Polymarket' : 'Hyperliquid',
    basisLabel: 'Economic P&L',
    coverageLabel: 'All time',
  );
}

const _nowMs = 1790000000000;
const _min = 60000;

/// A Predictions line over a week, drifting from 38% to 61%.
final List<PolymarketPricePoint> _poly = [
  for (var i = 0; i <= 168; i++)
    PolymarketPricePoint(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          _nowMs - 7 * 24 * 60 * _min + i * 60 * _min),
      price: (0.38 +
              0.23 * i / 168 +
              0.035 * math.sin(i / 6) +
              0.012 * math.sin(i / 1.7))
          .clamp(0.01, 0.99),
    ),
];

/// Fifteen-minute bars climbing into a peak at the end (the SP500 case:
/// the entry sits on the latest price).
List<HyperliquidCandle> _candles() {
  final out = <HyperliquidCandle>[];
  var px = 7702.0;
  for (var i = 0; i < 26; i++) {
    final drift = i < 18 ? 1.2 * math.sin(i / 1.6) : (i - 17) * 5.5;
    final open = px;
    final close = 7710 + drift + 6 * math.sin(i * 1.3);
    px = close;
    out.add(HyperliquidCandle(
      openTime: DateTime.fromMillisecondsSinceEpoch(
          _nowMs - (26 - i) * 15 * _min),
      closeTime: DateTime.fromMillisecondsSinceEpoch(
          _nowMs - (25 - i) * 15 * _min),
      open: open,
      high: math.max(open, close) + 2,
      low: math.min(open, close) - 2,
      close: close,
      volume: i > 18 ? 60.0 + 20 * (i % 3) : 4.0 + (i % 4),
    ));
  }
  return out;
}

// ───────────────────────────── drawing ─────────────────────────────

Future<void> _show(
  WidgetTester tester,
  Widget child, {
  required bool dark,
  required String locale,
  List<Override> overrides = const [],
}) async {
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
        locale: Locale(locale),
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
  for (var i = 0; i < 30; i++) {
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

/// Two fingers spread on the plot (a zoom in), then a drag back in time:
/// the Balance charts' time axis away from "Now".
Future<void> _pannedShot(
    WidgetTester tester, String name, Finder plot) async {
  final rect = tester.getRect(plot);
  final a = await tester.startGesture(rect.center - const Offset(30, 0));
  final b = await tester.startGesture(rect.center + const Offset(30, 0),
      pointer: 77);
  await tester.pump();
  await a.moveBy(const Offset(-60, 0));
  await b.moveBy(const Offset(60, 0));
  await tester.pump();
  await a.up();
  await b.up();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.dragFrom(rect.center, const Offset(120, 0));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await _shot(tester, name);
}

/// A press held on the plot (long enough for a long press), at [at] of
/// its width: the crosshair and the scrub card.
Future<void> _scrubShot(WidgetTester tester, String name, Finder plot,
    {double at = 0.62, double y = 0.45}) async {
  final rect = tester.getRect(plot.first);
  final gesture = await tester.startGesture(
      Offset(rect.left + rect.width * at, rect.top + rect.height * y));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 300));
  await _shot(tester, name);
  await gesture.up();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) return;
  await tester.tap(f.first, warnIfMissed: false);
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _case(String name,
    Future<void> Function(WidgetTester tester, bool dark, String locale) body) {
  for (final dark in [false, true]) {
    for (final locale in ['en', 'pt']) {
      final id = '${name}_${dark ? 'dark' : 'light'}_$locale';
      testWidgets(id, (tester) async {
        await body(tester, dark, locale);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 8));
      }, skip: _only.isNotEmpty && !id.contains(_only));
    }
  }
}

void main() {
  if (!_enabled) {
    test('chart render', () {},
        skip: 'on demand: --dart-define=CHART_AUDIT=true');
    return;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Directory(_out).createSync(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [GoogleFonts.inter().fontFamily!, 'Inter', 'FlutterTest']) {
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
    // Every icon font the bundle carries.
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
        as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  // Home: the Balance tab of the analytics strip on the spending wallet.
  _case('home_balance', (tester, dark, locale) async {
    await _show(
      tester,
      const SingleChildScrollView(
          child: HomeAnalyticsWidget(surface: 'home')),
      dark: dark,
      locale: locale,
      overrides: _bitcoinOverrides(locale),
    );
    await _tapText(tester, '1M');
    final name = 'home_balance_${dark ? 'dark' : 'light'}_$locale';
    await _shot(tester, name);
    await _scrubShot(tester, '${name}_scrub', find.byType(KuteLineChart),
        at: 0.5);
  });

  // Home: the Price tab.
  _case('home_price', (tester, dark, locale) async {
    await _show(
      tester,
      const SingleChildScrollView(
          child: HomeAnalyticsWidget(surface: 'home')),
      dark: dark,
      locale: locale,
      overrides: _bitcoinOverrides(locale),
    );
    await _tapText(tester, locale == 'pt' ? 'Preço' : 'Price');
    await _tapText(tester, '1M');
    final name = 'home_price_${dark ? 'dark' : 'light'}_$locale';
    await _shot(tester, name);
    await _scrubShot(tester, '${name}_scrub', find.byType(KuteLineChart));
  });

  // A watch-only wallet's Bitcoin screen: the same strip on its wallet.
  _case('watch_only', (tester, dark, locale) async {
    final wallet = WalletConfig(
        id: 'watch', name: 'Watch-only', isWatchOnly: true, sparkEnabled: false);
    await _show(
      tester,
      const SingleChildScrollView(
          child: HomeAnalyticsWidget(surface: 'wallet_detail')),
      dark: dark,
      locale: locale,
      overrides: _bitcoinOverrides(locale, viewed: wallet),
    );
    await _tapText(tester, '1M');
    final name = 'watch_only_${dark ? 'dark' : 'light'}_$locale';
    await _shot(tester, name);
    await _scrubShot(tester, '${name}_scrub', find.byType(KuteLineChart));
    await _pannedShot(tester, '${name}_panned', find.byType(KuteLineChart));
  });

  // Dollars: the Balance tab's dollar chart.
  _case('dollars', (tester, dark, locale) async {
    final byDay = <DateTime, double>{
      _day(28): 120,
      _day(21): 340,
      _day(15): 310,
      _day(8): 520.5,
      _day(2): 480.25,
    };
    await _show(
      tester,
      const SingleChildScrollView(
          child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: UsdBalanceChart())),
      dark: dark,
      locale: locale,
      overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(_settings(locale))),
        usdBalanceProvider.overrideWithValue(480.25),
        usdBalanceHistoryProvider.overrideWithValue(byDay),
        usdBalanceStepsProvider.overrideWithValue(BalanceHistory(
          opening: 0,
          changes: [
            for (final e in byDay.entries)
              (e.key.add(const Duration(hours: 10)), e.value),
          ],
          current: 480.25,
        )),
        viewedWalletTransactionsProvider
            .overrideWithValue(Transaction.empty()),
      ],
    );
    await _tapText(tester, '1M');
    final name = 'dollars_${dark ? 'dark' : 'light'}_$locale';
    await _shot(tester, name);
    await _scrubShot(tester, '${name}_scrub', find.byType(KuteLineChart));
    await _pannedShot(tester, '${name}_panned', find.byType(KuteLineChart));
  });

  for (final predictions in [false, true]) {
    final label = predictions ? 'predictions_balance' : 'investing_balance';
    _case(label, (tester, dark, locale) async {
      final venue = predictions
          ? PortfolioPerformanceVenue.predictions
          : PortfolioPerformanceVenue.trading;
      await _show(
        tester,
        PortfolioStatistics(venue: venue),
        dark: dark,
        locale: locale,
        overrides: [
          settingsProvider
              .overrideWith((_) => SettingsModel(_settings(locale))),
          livePriceProvider.overrideWith(_Quiet.new),
          portfolioPerformanceProvider(PortfolioPerformanceRequest(venue: venue))
              .overrideWith((_) async => _performance(predictions)),
        ],
      );
      await _shot(tester, '${label}_${dark ? 'dark' : 'light'}_$locale');
    });
  }

  // The reference: a Predictions market chart, 1W.
  _case('market_chart', (tester, dark, locale) async {
    await _show(
      tester,
      const Padding(
        padding: EdgeInsets.all(16),
        child: MarketChart(tokenId: 'tok', height: 260),
      ),
      dark: dark,
      locale: locale,
      overrides: [
        livePriceProvider.overrideWith(_Quiet.new),
        polymarketMarketHistoryProvider
            .overrideWith((ref, arg) async => _poly),
      ],
    );
    final name = 'market_chart_${dark ? 'dark' : 'light'}_$locale';
    await _shot(tester, name);
    await _scrubShot(tester, '${name}_scrub', find.byType(MarketChart),
        y: 0.4);
  });

  // A Predictions position: the Bought line on the live price.
  _case('poly_position', (tester, dark, locale) async {
    await _show(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: MarketChart(
          tokenId: 'tok',
          height: 260,
          bought: [MarketChartBought(tokenId: 'tok', price: _poly.last.price)],
          surface: 'position',
        ),
      ),
      dark: dark,
      locale: locale,
      overrides: [
        livePriceProvider.overrideWith(_Quiet.new),
        polymarketMarketHistoryProvider
            .overrideWith((ref, arg) async => _poly),
      ],
    );
    final name = 'poly_position_${dark ? 'dark' : 'light'}_$locale';
    await _shot(tester, name);
  });

  // The reference: an Investing chart (area), and the position case from
  // the SP500 report: the entry on the latest price, the liquidation far
  // under the window.
  _case('hl_position', (tester, dark, locale) async {
    final candles = _candles();
    final entry = candles.last.close - 0.3;
    const liq = 1.486;
    await _show(
      tester,
      Builder(builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: HlCandlestickChart(
            marketKey: 'hl:perp:xyz:SP500',
            candles: candles,
            height: 380,
            isLive: true,
            showVolume: true,
            style: HlChartStyle.area,
            summaryBelow: true,
            tradeLines: [
              ChartTradeLine(
                id: 'position',
                kind: ChartTradeLineKind.entry,
                price: entry,
                label: context.l10n.hlChartEntry,
                detail: formatHlPriceLike(entry, candles.last.close),
              ),
              ChartTradeLine(
                id: 'liq',
                kind: ChartTradeLineKind.liquidation,
                price: liq,
                label: context.l10n.hlChartLiq,
                detail: formatHlPriceLike(liq, candles.last.close),
              ),
            ],
          ),
        );
      }),
      dark: dark,
      locale: locale,
    );
    final name = 'hl_position_${dark ? 'dark' : 'light'}_$locale';
    await _shot(tester, name);
    await _scrubShot(tester, '${name}_scrub',
        find.byType(HlCandlestickChart), at: 0.55, y: 0.3);
  });
  // ── The Balance charts with no range picker (Bitcoin wallets and
  // Dollars): the whole history fitted to the width. Before the change
  // the same cases are drawn on the range the reports showed.
  for (final b in _balanceCases) {
    _case('bal_${b.name}', (tester, dark, locale) async {
      final wallet = b.hardware
          ? WalletConfig(
              id: 'ledger',
              name: 'Ledger',
              isHardware: true,
              sparkEnabled: false)
          : null;
      await _show(
        tester,
        b.dollars
            ? const SingleChildScrollView(
                child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    child: UsdBalanceChart()))
            : SingleChildScrollView(
                child: HomeAnalyticsWidget(
                    surface: b.hardware ? 'wallet_detail' : 'home')),
        dark: dark,
        locale: locale,
        overrides: _balanceOverrides(b, locale, wallet),
      );
      final base = 'bal_${b.name}_${dark ? 'dark' : 'light'}_$locale';
      final ranges = b.ranges;
      if (find.text(ranges.first).evaluate().isEmpty) {
        // No range row: the one view.
        await _shot(tester, base);
        await _scrubShot(tester, '${base}_scrub', find.byType(KuteLineChart),
            at: 0.7);
        return;
      }
      for (final r in ranges) {
        await _tapText(tester, r);
        await _shot(tester, '${base}_$r');
      }
    });
  }
}

/// One Balance-chart render case: changes as (when, held after), oldest
/// first, in sats (Bitcoin) or dollars.
class _BalanceCase {
  final String name;
  final bool dollars;
  final bool hardware;
  final bool hidden;
  final List<(DateTime, double)> steps;
  final List<String> ranges;
  const _BalanceCase(this.name, this.steps,
      {this.dollars = false,
      this.hardware = false,
      this.hidden = false,
      required this.ranges});
  double get current => steps.isEmpty ? 0 : steps.last.$2;
  BalanceHistory get history =>
      BalanceHistory(opening: 0, changes: steps, current: current);
}

DateTime _ago(Duration d) => DateTime.now().subtract(d);

final List<_BalanceCase> _balanceCases = [
  // João's report: 17,520 sats arriving today after months at zero.
  _BalanceCase('fresh_sats', [(_ago(const Duration(hours: 2)), 17520)],
      ranges: ['3M']),
  // A spending wallet with nine months of history.
  _BalanceCase(
      'history_sats',
      [
        (_ago(const Duration(days: 270, hours: 3)), 250000),
        (_ago(const Duration(days: 231)), 410000),
        (_ago(const Duration(days: 190, hours: 5)), 380500),
        (_ago(const Duration(days: 150)), 520000),
        (_ago(const Duration(days: 96)), 300000),
        (_ago(const Duration(days: 61)), 640000),
        (_ago(const Duration(days: 33)), 615200),
        (_ago(const Duration(days: 12)), 702000),
        (_ago(const Duration(days: 4)), 690400),
      ],
      ranges: ['1Y', 'ALL']),
  // A Ledger holding cold savings for two years.
  _BalanceCase(
      'hardware_sats',
      [
        (_ago(const Duration(days: 700)), 5000000),
        (_ago(const Duration(days: 520)), 9000000),
        (_ago(const Duration(days: 300)), 12500000),
        (_ago(const Duration(days: 120)), 12500000 + 2000000),
        (_ago(const Duration(days: 45)), 11000000),
      ],
      hardware: true,
      ranges: ['1Y', 'ALL']),
  // João's Dollars reports: one $5.02 deposit today.
  _BalanceCase('fresh_dollars', [(_ago(const Duration(hours: 3)), 5.02)],
      dollars: true, ranges: ['7D', '1Y', 'ALL']),
  // Dollars with a few months of transfers.
  _BalanceCase(
      'history_dollars',
      [
        (_ago(const Duration(days: 80)), 120),
        (_ago(const Duration(days: 52)), 340),
        (_ago(const Duration(days: 30)), 310),
        (_ago(const Duration(days: 9)), 520.5),
        (_ago(const Duration(days: 2)), 480.25),
      ],
      dollars: true,
      ranges: ['1M', 'ALL']),
  // Balances hidden (the headline tapped): the scale keeps its hairlines
  // and drops its figures.
  _BalanceCase(
      'hidden_sats',
      [
        (_ago(const Duration(days: 150)), 520000),
        (_ago(const Duration(days: 61)), 640000),
        (_ago(const Duration(days: 12)), 702000),
      ],
      hidden: true,
      ranges: ['ALL']),
];

/// Closing balance per day, as the day-keyed providers hand it over.
Map<DateTime, double> _closingByDay(List<(DateTime, double)> steps) => {
      for (final s in steps)
        DateTime(s.$1.year, s.$1.month, s.$1.day): s.$2,
    };

List<Override> _balanceOverrides(
    _BalanceCase b, String language, WalletConfig? wallet) {
  if (b.dollars) {
    return [
      settingsProvider.overrideWith((_) => SettingsModel(
          _settings(language, balancePrivacy: b.hidden ? 1 : 0))),
      usdBalanceProvider.overrideWithValue(b.current),
      usdBalanceStepsProvider.overrideWithValue(b.history),
      usdBalanceHistoryProvider.overrideWithValue({
        ..._closingByDay(b.steps),
        _day(0): b.current,
      }),
      viewedWalletTransactionsProvider.overrideWithValue(Transaction.empty()),
    ];
  }
  final sats = b.current.round();
  return [
    settingsProvider.overrideWith((_) => SettingsModel(_settings(language,
        wallet: wallet, balancePrivacy: b.hidden ? 1 : 0))),
    bitcoinMarketDataProvider.overrideWith(_Market.new),
    bitcoinBalanceStepsProvider.overrideWith((_) => b.history),
    bitcoinBalanceOverPeriod.overrideWith((_) => {
          ..._closingByDay(b.steps),
          _day(0): sats,
        }),
    viewedWalletBalanceProvider.overrideWithValue(WalletBalance(
      onChainBtcBalance: wallet == null ? 0 : sats,
      sparkBitcoinbalance: wallet == null ? sats : 0,
    )),
    polymarketBalanceProvider.overrideWith((_) => 0),
    selectedCurrencyProvider.overrideWith(
        (ref, code) => Money.fromNumWithCurrency(70000, AppCurrencies.usd)),
    selectedCurrencyProviderFromUSD.overrideWith(
        (ref, code) => Money.fromNumWithCurrency(1, AppCurrencies.usd)),
    viewedWalletProvider.overrideWithValue(wallet),
    viewedWalletTransactionsProvider.overrideWithValue(Transaction.empty()),
  ];
}
