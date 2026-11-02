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
    SalSpriteCache.debugSetManifest(jsonDecode(
            await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
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

void main() {
  testWidgets('the share bars and the P&L card, light', (tester) async {
    Directory(_dir!).createSync(recursive: true);
    await _assets(tester);
    addTearDown(() => SalSpriteCache.debugSetManifest(null));
    addTearDown(ShareCardSal.debugReset);
    BragPreviewSheet.debugLineSeed = 1;
    addTearDown(() => BragPreviewSheet.debugLineSeed = null);
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(390, 960) * 3;
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
            language: 'en',
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
    expect(kuteBarPrimaryWithText('Share portfolio'), findsOneWidget);
    await _write(tester, find.byKey(screen), 'portfolio_section');

    await tester
        .tap(find.byKey(const ValueKey('portfolio-section-pill-charts')));
    await _frames(tester);
    expect(kuteBarPrimaryWithText('Share P&L'), findsOneWidget);
    await _write(tester, find.byKey(screen), 'pnl_section');

    await tester.tap(kuteBarPrimary);
    await _frames(tester);
    await _write(tester, find.byKey(screen), 'pnl_share_sheet');
    await _write(
        tester,
        find
            .descendant(
                of: find.byKey(const ValueKey('brag-preview-card')),
                matching: find.byType(RepaintBoundary))
            .first,
        'pnl_share_card',
        pixelRatio: kBragCardPixelRatio);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }, skip: _dir == null);
}
