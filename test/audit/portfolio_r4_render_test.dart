// Render harness for the Portfolio screen's round of 1 November 2026: the
// two sections' one empty state (Portfolio, P&L Charts, Sal at one place;
// Activity moved to the Bitcoin home), the Portfolio section with a
// position in its soft card, and P&L Charts (a series that crosses zero
// with its split fill, the stats strip and the venue rows in their soft
// cards; and scrubbing), at
// 390 x 844 in the app's real theme and Inter, light (and the P&L dark).
// Writes PNGs.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/portfolio_r4_render_test.dart \
//     --dart-define=PORTFOLIO_R4_OUT=/tmp/portfolio-r4

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidPerpMarketsProvider, hyperliquidSpotMarketsProvider;
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/shared/sal_sprite.dart'
    show SalSpriteCache, kSalHeroLoop;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/portfolio_overrides.dart';

const _out = String.fromEnvironment('PORTFOLIO_R4_OUT');
const _key = ValueKey('shot');
const _dpr = 3.0;
const _size = Size(390, 844);

class _Sweeper extends VenueSweeperNotifier {
  @override
  VenueSweeperState build() => const VenueSweeperState();

  @override
  Future<void> preview() async {}

  @override
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async {}
}

/// Nothing open anywhere, the cash read.
const _nothingOpen = OneBalanceState(
  investingKnown: true,
  predictionsKnown: true,
  venueCash: {
    OneBalanceVenue.investing: 17.21,
    OneBalanceVenue.predictions: 0.43,
  },
);

/// Two Investing positions and some predictions.
const _held = OneBalanceState(
  investedUsd: 1723.88,
  investedByVenue: {
    OneBalanceVenue.investing: 1704.85,
    OneBalanceVenue.predictions: 19.03,
  },
  investingKnown: true,
  predictionsKnown: true,
  venueCash: {
    OneBalanceVenue.investing: 17.21,
    OneBalanceVenue.predictions: 0.43,
  },
);

const _btc = HlPerpPosition(
    coin: 'BTC',
    szi: 0.0125,
    entryPx: 90120,
    positionValue: 1168.75,
    unrealizedPnl: 12.25,
    returnOnEquity: 0.0109,
    liquidationPx: null,
    marginUsed: 1126.5,
    leverageType: 'isolated',
    leverageValue: 1,
    maxLeverage: 40);

class _Account extends HlAccountNotifier {
  @override
  Future<HlAccountSnapshot> build() async => const HlAccountSnapshot(
      accountValue: 1722.06,
      withdrawable: 17.21,
      totalMarginUsed: 1126.5,
      positions: [_btc],
      spotBalances: []);
}

/// A month of fills: four round trips closing +$19.80 net of fees.
List<HlFill> _fills() {
  final now = DateTime.now().toUtc();
  const closed = [-8.0, -6.4, 14.2, 20.4];
  return [
    for (var i = 0; i < 8; i++)
      HlFill.fromJson({
        'coin': 'ETH',
        'tid': '${i + 1}',
        'oid': i + 1,
        'hash': 'h$i',
        'time': now.subtract(Duration(days: 28 - i * 3)).millisecondsSinceEpoch,
        'startPosition': i.isEven ? '0' : '0.1',
        'sz': '0.1',
        'px': '3030',
        'side': i.isEven ? 'B' : 'A',
        'closedPnl': i.isEven ? '0' : '${closed[i ~/ 2]}',
        'fee': '0.05',
        'feeToken': 'USDC',
        'dir': i.isEven ? 'Open Long' : 'Close Long',
      }),
  ].reversed.toList();
}

/// The P&L that dips under zero and comes back: Investing −25 at its
/// lowest, +32.05 now; Predictions slightly down.
List<Override> _crossing() {
  final now = DateTime.now().toUtc();
  DateTime ago(int days) => now.subtract(Duration(days: days));
  PortfolioPerformance series(List<(int, double)> points, String source) =>
      PortfolioPerformance(
          points: [
            for (final (days, pnl) in points)
              PortfolioPnlPoint(timestamp: ago(days), pnlUsd: pnl)
          ],
          totalPnlUsd: points.last.$2,
          asOf: ago(points.last.$1),
          sourceLabel: source,
          basisLabel: 'P&L',
          coverageLabel: 'All time');
  PredictionRecord closed(int i, double pnl) => PredictionRecord(
      tokenId: 'closed-$i',
      open: false,
      redeemable: false,
      size: 10,
      totalSize: 10,
      avgPrice: 0.5,
      entryCostUsd: 5,
      currentPrice: 0,
      realizedPnlUsd: pnl,
      unrealizedPnlUsd: 0,
      firstEntryAt: ago(26 - i * 3),
      lastEventAt: ago(25 - i * 3),
      conditionId: 'c$i',
      title: 'Closed $i');
  final book = PredictionsBook(records: [
    for (final (i, pnl) in [-2.0, 1.5, -1.2, 0.9, -0.4].indexed)
      closed(i, pnl),
  ]);
  return [
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.trading))
        .overrideWith((_) async => series([
              (30, 0),
              (26, -6),
              (22, -14),
              (18, -25),
              (14, -11),
              (10, 4),
              (6, 18),
              (3, 26),
              (1, 32.05)
            ], 'Hyperliquid')),
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.predictions))
        .overrideWith((_) async => series([
              (28, 0),
              (22, -1.4),
              (15, 0.3),
              (9, -0.9),
              (2, -1.2)
            ], 'Polymarket')
                .withPredictions(book)),
    hyperliquidAccountProvider.overrideWith(_Account.new),
    hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
        const HyperliquidTradingState(
            isInitialized: true, positions: [_btc]))),
    hyperliquidDisplayTradingProvider
        .overrideWith((ref) => ref.watch(hyperliquidTradingProvider)),
    hyperliquidLiveMidProvider('BTC').overrideWith((_) => null),
    hyperliquidPerpMarketsProvider.overrideWith((_) async => [
          HlMarket(
              coin: 'BTC',
              wireCoin: 'BTC',
              assetId: 1,
              kind: HlMarketKind.perp,
              szDecimals: 4,
              maxLeverage: 40,
              onlyIsolated: false,
              markPx: 91100,
              midPx: 91100,
              prevDayPx: 90000,
              dayNtlVlm: 1e6,
              category: 'crypto',
              dex: '',
              isHip3: false),
        ]),
    hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
    hyperliquidDisplayAccountProvider
        .overrideWith((ref) => ref.watch(hyperliquidAccountProvider)),
    hyperliquidUserFillsProvider.overrideWith((_) async => _fills()),
    hyperliquidActivityFillsProvider.overrideWithValue(_fills()),
  ];
}

Future<void> _mount(WidgetTester tester,
    {required bool dark,
    required OneBalanceState state,
    required PortfolioSection section,
    List<Override> extra = const []}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true))),
      oneBalanceProvider.overrideWith((ref) => state),
      usdBalanceUnknownProvider.overrideWithValue(false),
      venueSweeperProvider.overrideWith(_Sweeper.new),
      hyperliquidActivityFillsProvider.overrideWithValue(const []),
      portfolioSectionProvider.overrideWith((_) => section),
      ...extra,
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepaintBoundary(
          key: _key,
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: context.colors.background,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: true,
                title: Text('Portfolio',
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
              ),
              body: DecoratedBox(
                decoration: AppDecorations.screenGradient(context),
                child: SafeArea(
                  top: false,
                  child: Material(
                    color: Colors.transparent,
                    child: Consumer(
                      builder: (context, ref, _) => InvestmentsPortfolio(
                        onSection: (s) => ref
                            .read(portfolioSectionProvider.notifier)
                            .state = s,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    // Sal's sheets and the logos decode off the frame.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _png(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image =
      (await tester.runAsync(() => boundary.toImage(pixelRatio: _dpr)))!;
  await tester.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  if (_out.isEmpty) {
    test('Portfolio r4 render', () {},
        skip: 'on demand: --dart-define=PORTFOLIO_R4_OUT=<dir>');
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

  // The real Sal (flutter_test_config.dart nulls the manifest for the
  // suite): the hero sheet decoded in real time before any mount, as the
  // fake clock would not let the decode land before the shot.
  setUpAll(() async {
    SalSpriteCache.debugReset();
    await SalSpriteCache.warm([kSalHeroLoop], 3);
  });
  tearDownAll(() => SalSpriteCache.debugSetManifest(null));

  testWidgets('both sections empty, light', (tester) async {
    tester.view.devicePixelRatio = _dpr;
    tester.view.physicalSize = _size * _dpr;
    addTearDown(tester.view.reset);
    for (final (section, name) in [
      (PortfolioSection.balances, 'empty_portfolio'),
      (PortfolioSection.charts, 'empty_pnl'),
    ]) {
      await _mount(tester,
          dark: false, state: _nothingOpen, section: section);
      await _png(tester, name);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('P&L crossing zero, light and dark, at rest and scrubbing',
      (tester) async {
    tester.view.devicePixelRatio = _dpr;
    tester.view.physicalSize = _size * _dpr;
    addTearDown(tester.view.reset);
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      await _mount(tester,
          dark: dark,
          state: _held,
          section: PortfolioSection.charts,
          extra: _crossing());
      await _png(tester, 'pnl_crossing_zero_$theme');
      // The Portfolio section, the same language: a position row.
      await tester
          .tap(find.byKey(const ValueKey('portfolio-section-pill-balances')));
      await _settle(tester);
      await _png(tester, 'portfolio_held_$theme');
      await tester
          .tap(find.byKey(const ValueKey('portfolio-section-pill-charts')));
      await _settle(tester);
      // Scrub at the dip under zero (a long press, then hold).
      final plot = tester.getRect(find.byKey(const ValueKey('trend-chart-plot')));
      final touch =
          await tester.startGesture(plot.centerLeft + Offset(plot.width * 0.4, 0));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 400));
      await _png(tester, 'pnl_scrubbing_$theme');
      await touch.up();
      await tester.pump(const Duration(milliseconds: 400));
      // Predictions picked: its line, its stats with the win rate.
      if (!dark) {
        await tester.ensureVisible(
            find.byKey(const ValueKey('pnl-venue-predictions-pick')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester
            .tap(find.byKey(const ValueKey('pnl-venue-predictions-pick')));
        await _settle(tester);
        await _png(tester, 'pnl_predictions_picked_light');
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
