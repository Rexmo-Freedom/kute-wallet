// The Portfolio screen's two share bars and the P&L card, by eye (founder,
// 2 November 2026: "Share portfolio" on Portfolio, "Share P&L" on P&L
// Charts, each its own card). Written only when asked:
//
//   R6_SHARE_RENDER=<dir> flutter test test/render/portfolio_share_render_test.dart
//
// The real Inter face and Sal's real sheets and stills; 390 wide at 3x,
// light. portfolio_section.png and pnl_section.png are the screen with the
// bar over it; pnl_share_sheet.png the preview sheet; pnl_share_card.png
// the shared image itself (1080 × 1350).
//
// The portfolio card with its holdings (founder, 7 November 2026: "how
// much i made on each?"), +$3.43 all time, with none, two and five
// positions open, in English and German: holdings_{n}_{lang}_sheet.png
// the preview sheet over the Portfolio, holdings_{n}_{lang}_export.png
// the PNG Share hands the OS (the export path itself, 1080 × 1350).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition, polymarketActivePositionsProvider;
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/portfolio/portfolio_screen.dart';
import 'package:kute/screens/share/brag/brag_card.dart'
    show kBragCardPixelRatio;
import 'package:kute/screens/share/brag/brag_preview_sheet.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart'
    show ShareCardSal;
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/kute_bar_test_support.dart';
import '../helpers/portfolio_overrides.dart';

final _dir = Platform.environment['R6_SHARE_RENDER'];

class _Sweeper extends VenueSweeperNotifier {
  @override
  VenueSweeperState build() => const VenueSweeperState();
  @override
  Future<void> preview() async {}
  @override
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async {}
}

const _btcHeld = HyperliquidTradingState(isInitialized: true, positions: [
  HlPerpPosition(
      coin: 'BTC',
      szi: 0.1,
      entryPx: 60000,
      positionValue: 10812.37,
      unrealizedPnl: 12.4,
      returnOnEquity: 0.004,
      liquidationPx: null,
      marginUsed: 10799.97,
      leverageType: 'isolated',
      leverageValue: 1,
      maxLeverage: 40),
]);

const _bothAtWork = OneBalanceState(
  dollarsUsd: 25,
  investedUsd: 10816.61,
  investedByVenue: {
    OneBalanceVenue.investing: 10812.37,
    OneBalanceVenue.predictions: 4.24,
  },
  investingKnown: true,
  predictionsKnown: true,
  venueCash: {
    OneBalanceVenue.investing: 17.21,
    OneBalanceVenue.predictions: 0.43,
  },
);

List<Override> _history() {
  final now = DateTime.now().toUtc();
  PortfolioPerformance perf(List<(int, double)> points, String source) =>
      PortfolioPerformance(
          points: [
            for (final (days, pnl) in points)
              PortfolioPnlPoint(
                  timestamp: now.subtract(Duration(days: days)), pnlUsd: pnl)
          ],
          totalPnlUsd: points.last.$2,
          realizedPnlUsd: points.last.$2,
          openPnlUsd: 0,
          asOf: now.subtract(Duration(days: points.last.$1)),
          sourceLabel: source,
          basisLabel: 'P&L',
          coverageLabel: 'All time');
  return [
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.trading))
        .overrideWith((_) async => perf([
              (400, 0),
              (300, 40),
              (200, -12),
              (120, 30),
              (60, 22),
              (40, 61),
              (22, 48),
              (14, 75.5),
              (8, 66.2),
              (3, 92.4),
              (1, 104.9)
            ], 'Hyperliquid')),
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.predictions))
        .overrideWith((_) async => perf(
            [(45, 0), (30, -3.2), (20, 2.5), (9, 6.1), (2, 7.61)],
            'Polymarket')),
  ];
}

Future<void> _assets(WidgetTester tester) async {
  await tester.runAsync(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Bold.ttf'));
    await inter.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    SalSpriteCache.debugSetManifest(
        jsonDecode(await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
            as Map<String, dynamic>);
    for (final clip in ['idle', 'curious', 'think', 'happy', 'share']) {
      await SalSpriteCache.clip(clip, 3);
    }
    await ShareCardSal.load();
  });
}

Future<void> _write(WidgetTester tester, Finder boundary, String name,
    {double pixelRatio = 3}) async {
  final render = tester.renderObject(boundary) as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data;
  });
  File('$_dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The live prices, quiet: no socket, the prices given.
class _Prices extends LivePriceNotifier {
  _Prices(this.prices);
  final Map<String, double> prices;
  @override
  LivePriceState build() => LivePriceState(live: true, prices: prices);
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

/// The founder's all time: +$2.10 Investing and +$1.33 Predictions.
List<Override> _founderHistory() {
  final now = DateTime.now().toUtc();
  PortfolioPerformance perf(List<(int, double)> points, String source) =>
      PortfolioPerformance(
          points: [
            for (final (days, pnl) in points)
              PortfolioPnlPoint(
                  timestamp: now.subtract(Duration(days: days)), pnlUsd: pnl)
          ],
          totalPnlUsd: points.last.$2,
          realizedPnlUsd: points.last.$2,
          openPnlUsd: 0,
          asOf: now.subtract(Duration(days: points.last.$1)),
          sourceLabel: source,
          basisLabel: 'P&L',
          coverageLabel: 'All time');
  return [
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.trading))
        .overrideWith((_) async => perf([
              (60, 0),
              (45, 0.4),
              (30, -0.9),
              (20, 0.6),
              (12, 1.4),
              (6, 1.1),
              (2, 1.8),
              (1, 2.1)
            ], 'Hyperliquid')),
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.predictions))
        .overrideWith((_) async => perf(
            [(40, 0), (25, -0.4), (14, 0.5), (5, 0.9), (1, 1.33)],
            'Polymarket')),
  ];
}

HlPerpPosition _perp(String coin, double szi, double entry, double pnl) =>
    HlPerpPosition(
        coin: coin,
        szi: szi,
        entryPx: entry,
        positionValue: (szi * entry).abs() + pnl,
        unrealizedPnl: pnl,
        returnOnEquity: pnl / 40,
        liquidationPx: null,
        marginUsed: 40 + pnl,
        leverageType: 'isolated',
        leverageValue: 3,
        maxLeverage: 10);

/// [n] open positions (0, 2 or 5): Anthropic short +$2.61, Fed No
/// −$1.12, then Ethereum long +$0.84, Lakers Yes +$0.20, Verstappen +$0.10.
({List<HlPerpPosition> perps, List<PolymarketPosition> predictions})
    _founderHoldings(int n) {
  final perps = [
    _perp('ANTH', -0.5, 240, 2.61),
    _perp('ETH', 0.01, 3000, 0.84),
  ];
  PolymarketPosition poly(String token, String q, String outcome, double size,
          double avg, double price) =>
      PolymarketPosition(
          marketId: token,
          marketQuestion: q,
          outcome: outcome,
          size: size,
          avgPrice: avg,
          currentPrice: price,
          pnl: 0,
          pnlPercent: 0,
          isResolved: false,
          tokenId: token);
  final predictions = [
    poly('fed-no', 'Fed cuts rates in December?', 'No', 10, 0.5, 0.388),
    poly('lakers-yes', 'Will the Lakers win the 2026 NBA Finals?', 'Yes', 4,
        0.25, 0.3),
    poly('f1-ver', 'F1 Drivers Champion 2026', 'Verstappen', 2, 0.3, 0.35),
  ];
  return switch (n) {
    0 => (perps: const [], predictions: const []),
    2 => (
        perps: perps.take(1).toList(),
        predictions: predictions.take(1).toList()
      ),
    _ => (perps: perps, predictions: predictions),
  };
}

void main() {
  // English at 390; the long languages at the narrowest phone too.
  for (final (lang, width) in const [
    ('en', 390.0),
    ('de', 320.0),
    ('fi', 320.0),
    ('hu', 320.0),
  ]) {
    final tag = lang == 'en' ? '' : '_${lang}_${width.toInt()}';
    testWidgets('the share bars and the P&L card, light, $lang at $width',
        (tester) async {
      final words = lookupAppLocalizations(Locale(lang));
      Directory(_dir!).createSync(recursive: true);
      await _assets(tester);
      addTearDown(() => SalSpriteCache.debugSetManifest(null));
      addTearDown(ShareCardSal.debugReset);
      BragPreviewSheet.debugLineSeed = 1;
      addTearDown(() => BragPreviewSheet.debugLineSeed = null);
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = Size(width, 960) * 3;
      addTearDown(tester.view.reset);
      final screen = GlobalKey();
      final base = buildLightTheme();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...portfolioOverrides(trading: _btcHeld),
          hyperliquidLiveMidProvider('BTC').overrideWith((_) => null),
          hyperliquidAccountMarketProvider('BTC').overrideWith((_) => null),
          hyperliquidPerpMarketsProvider
              .overrideWith((_) async => <HlMarket>[]),
          hyperliquidSpotMarketsProvider
              .overrideWith((_) async => <HlMarket>[]),
          settingsProvider.overrideWith((_) => SettingsModel(Settings(
              currency: 'USD',
              language: lang,
              btcFormat: 'sats',
              backup: false,
              biometricsEnabled: false,
              bitcoinElectrumNode: '',
              nodeType: '',
              reviewDone: true))),
          oneBalanceProvider.overrideWith((ref) => _bothAtWork),
          usdBalanceUnknownProvider.overrideWithValue(false),
          venueSweeperProvider.overrideWith(_Sweeper.new),
          hyperliquidActivityFillsProvider.overrideWithValue(const []),
          portfolioSectionProvider
              .overrideWith((_) => PortfolioSection.balances),
          ..._history(),
        ],
        child: RepaintBoundary(
          key: screen,
          child: ScreenUtilInit(
            designSize: const Size(430, 932),
            builder: (_, __) => MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: Locale(lang),
              theme: base.copyWith(
                  textTheme: base.textTheme.apply(fontFamily: 'Inter')),
              builder: withKuteShellBar,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const PortfolioScreen(),
            ),
          ),
        ),
      ));
      await _frames(tester);
      expect(
          kuteBarPrimaryWithText(words.bragPortfolioBarLabel), findsOneWidget);
      await _write(tester, find.byKey(screen), 'portfolio_section$tag');

      await tester
          .tap(find.byKey(const ValueKey('portfolio-section-pill-charts')));
      await _frames(tester);
      expect(kuteBarPrimaryWithText(words.bragPnlBarLabel), findsOneWidget);
      await _write(tester, find.byKey(screen), 'pnl_section$tag');

      await tester.tap(kuteBarPrimary);
      await _frames(tester);
      await _write(tester, find.byKey(screen), 'pnl_share_sheet$tag');
      await _write(
          tester,
          find
              .descendant(
                  of: find.byKey(const ValueKey('brag-preview-card')),
                  matching: find.byType(RepaintBoundary))
              .first,
          'pnl_share_card$tag',
          pixelRatio: kBragCardPixelRatio);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }, skip: _dir == null);
  }

  for (final lang in const ['en', 'de']) {
    for (final n in const [0, 2, 5]) {
      testWidgets('the portfolio card with $n open, $lang: sheet and export',
          (tester) async {
        Directory(_dir!).createSync(recursive: true);
        await _assets(tester);
        addTearDown(() => SalSpriteCache.debugSetManifest(null));
        addTearDown(ShareCardSal.debugReset);
        BragPreviewSheet.debugLineSeed = 0;
        addTearDown(() => BragPreviewSheet.debugLineSeed = null);
        final exported = <List<int>>[];
        BragPreviewSheet.debugSharer =
            (file, _) async => exported.add(await file.readAsBytes());
        addTearDown(() => BragPreviewSheet.debugSharer = null);
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(390, 844) * 3;
        addTearDown(tester.view.reset);
        final holdings = _founderHoldings(n);
        final screen = GlobalKey();
        final base = buildLightTheme();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            ...portfolioOverrides(
                trading: HyperliquidTradingState(
                    isInitialized: true, positions: holdings.perps)),
            for (final coin in const ['ANTH', 'ETH']) ...[
              hyperliquidLiveMidProvider(coin).overrideWith((_) => null),
              hyperliquidAccountMarketProvider(coin).overrideWith((_) => null),
            ],
            hyperliquidPerpMarketsProvider
                .overrideWith((_) async => <HlMarket>[]),
            hyperliquidSpotMarketsProvider
                .overrideWith((_) async => <HlMarket>[]),
            polymarketActivePositionsProvider
                .overrideWith((_) => holdings.predictions),
            livePriceProvider.overrideWith(() => _Prices({
                  for (final p in holdings.predictions)
                    p.tokenId!: p.currentPrice
                })),
            settingsProvider.overrideWith((_) => SettingsModel(Settings(
                currency: 'USD',
                language: lang,
                btcFormat: 'sats',
                backup: false,
                biometricsEnabled: false,
                bitcoinElectrumNode: '',
                nodeType: '',
                reviewDone: true))),
            oneBalanceProvider.overrideWith((ref) => _bothAtWork),
            usdBalanceUnknownProvider.overrideWithValue(false),
            venueSweeperProvider.overrideWith(_Sweeper.new),
            hyperliquidActivityFillsProvider.overrideWithValue(const []),
            portfolioSectionProvider
                .overrideWith((_) => PortfolioSection.balances),
            ..._founderHistory(),
          ],
          child: RepaintBoundary(
            key: screen,
            child: ScreenUtilInit(
              designSize: const Size(430, 932),
              builder: (_, __) => MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: Locale(lang),
                theme: base.copyWith(
                    textTheme: base.textTheme.apply(fontFamily: 'Inter')),
                builder: withKuteShellBar,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const PortfolioScreen(),
              ),
            ),
          ),
        ));
        await _frames(tester);
        await tester.tap(kuteBarPrimary);
        await _frames(tester);
        expect(tester.takeException(), isNull);
        await _write(tester, find.byKey(screen), 'holdings_${n}_${lang}_sheet');
        // Share: the export path's own PNG (toImage at 3x).
        await tester.runAsync(() async {
          await tester.tap(kuteBarPrimary);
          for (var i = 0; i < 100 && exported.isEmpty; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        });
        expect(exported, hasLength(1));
        File('$_dir/holdings_${n}_${lang}_export.png')
            .writeAsBytesSync(exported.single);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      }, skip: _dir == null);
    }
  }
}
