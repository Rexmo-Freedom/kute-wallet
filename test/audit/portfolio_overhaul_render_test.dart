// Render harness for the Portfolio screen's overhaul (founder, 4 November
// 2026: "the top chart means nothing … much, much, much better fintech
// design comparable to the rest of the app"): the hero ("Invested", the
// figure, the P&L over the range, the one P&L chart, the line under it)
// over Activity | Positions | P&L, each section with a full account and
// with a never-traded one, light and dark, at 390 x 844 in the app's real
// theme and Inter; and the P&L section's squares (founder, 5 November
// 2026: "here should be square cards") with Predictions alone, with
// balances hidden, with a venue that never traded, and at 375 pt with
// 130 % text. Writes PNGs.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/portfolio_overhaul_render_test.dart \
//     --dart-define=PORTFOLIO_OVERHAUL_OUT=/tmp/portfolio-overhaul

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart' show Activity;
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidPerpMarketsProvider, hyperliquidSpotMarketsProvider;
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition, polymarketActivePositionsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/shared/sal_sprite.dart'
    show SalSpriteCache, kSalHeroLoop;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/portfolio_overrides.dart';

const _out = String.fromEnvironment('PORTFOLIO_OVERHAUL_OUT');
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

HlPerpPosition _perp(String coin, double szi, double entry, double value,
        double pnl) =>
    HlPerpPosition(
        coin: coin,
        szi: szi,
        entryPx: entry,
        positionValue: value,
        unrealizedPnl: pnl,
        returnOnEquity: pnl / (value - pnl),
        liquidationPx: null,
        marginUsed: value - pnl,
        leverageType: 'isolated',
        leverageValue: 1,
        maxLeverage: 20);

HlMarket _market(String coin, double px, double prev) => HlMarket(
    coin: coin,
    wireCoin: coin,
    assetId: coin.hashCode & 0xff,
    kind: HlMarketKind.perp,
    szDecimals: 4,
    maxLeverage: 20,
    onlyIsolated: false,
    markPx: px,
    midPx: px,
    prevDayPx: prev,
    dayNtlVlm: 1e6,
    category: 'crypto',
    dex: '',
    isHip3: false);

PolymarketPosition _position(String token, String question, String side,
        double size, double avg, double now) =>
    PolymarketPosition(
        marketId: 'm-$token',
        marketQuestion: question,
        outcome: side,
        size: size,
        avgPrice: avg,
        currentPrice: now,
        pnl: (now - avg) * size,
        pnlPercent: (now / avg - 1) * 100,
        isResolved: false,
        tokenId: token);

final _now = DateTime.now().toUtc();

PolymarketTransaction _bet(String id, Duration ago, String title,
        String outcome, String side, double usdc) =>
    PolymarketTransaction(
      id: id,
      timestamp: _now.subtract(ago),
      activity: Activity(
        proxyWallet: '0xself',
        timestamp: _now.subtract(ago).millisecondsSinceEpoch ~/ 1000,
        conditionId: '0x$id',
        type: 'TRADE',
        size: usdc / 0.4,
        usdcSize: usdc,
        transactionHash: '0x$id',
        side: side,
        asset: 'asset-$id',
        outcomeIndex: 0,
        title: title,
        outcome: outcome,
        eventSlug: '',
      ),
    );

HlFill _fill(String coin, Duration ago, String dir, double px, double sz,
        {double closedPnl = 0}) =>
    HlFill(
      coin: coin,
      px: px,
      sz: sz,
      side: dir.contains('Long') == dir.startsWith('Open') ? 'B' : 'A',
      time: _now.subtract(ago).millisecondsSinceEpoch,
      closedPnl: closedPnl,
      fee: 0.1,
      feeToken: 'USDC',
      oid: ago.inMinutes,
      hash: '0xfill-$coin-${ago.inMinutes}',
      dir: dir,
      cloid: null,
    );

List<Override> _history() {
  PortfolioPerformance perf(List<(int, double)> points, String source) =>
      PortfolioPerformance(
          points: [
            for (final (days, pnl) in points)
              PortfolioPnlPoint(
                  timestamp: _now.subtract(Duration(days: days)), pnlUsd: pnl)
          ],
          totalPnlUsd: points.last.$2,
          asOf: _now.subtract(Duration(days: points.last.$1)),
          sourceLabel: source,
          basisLabel: 'P&L',
          coverageLabel: 'All time');
  return [
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.trading))
        .overrideWith((_) async => perf([
              (120, 0),
              (90, 14),
              (70, -6),
              (45, 9),
              (30, 4.5),
              (22, -4),
              (15, 6.8),
              (8, 3.2),
              (3, 15.1),
              (1, 18.4)
            ], 'Hyperliquid')),
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.predictions))
        .overrideWith((_) async => perf(
                [(60, 0), (45, 2.5), (28, 1.2), (12, 5.6), (2, 7.61)],
                'Polymarket')
            .withPredictions(PredictionsBook(records: [
              for (final (i, token) in ['lakers', 'fed', 'btc150', 'rain', 'old']
                  .indexed)
                PredictionRecord(
                  tokenId: token,
                  open: i < 3,
                  redeemable: false,
                  size: i < 3 ? 40 : 0,
                  totalSize: 40,
                  avgPrice: 0.35,
                  entryCostUsd: i < 3 ? 14 : 0,
                  currentPrice: 0.37,
                  realizedPnlUsd: i < 3 ? 0 : (i == 3 ? 4.1 : -1.2),
                  unrealizedPnlUsd: i < 3 ? 0.8 : 0,
                  firstEntryAt: _now.subtract(Duration(days: 50 - i * 8)),
                  lastEventAt: _now.subtract(Duration(days: 20 - i * 4)),
                ),
            ]))),
  ];
}

List<Override> _full() {
  final perps = [
    _perp('BTC', 0.0125, 90120, 1168.75, 12.25),
    _perp('ETH', -0.08, 3120, 251.6, -3.4),
  ];
  return [
    ...portfolioOverrides(
        trading: HyperliquidTradingState(isInitialized: true, positions: perps),
        history: Transaction(
          bitcoinTransactions: const [],
          sparkTransactions: const [],
          sparkUnclaimedDeposits: const [],
          polymarketTransactions: [
            _bet('lakers', const Duration(hours: 2),
                'Will the Lakers win the 2027 NBA Finals?', 'Yes', 'BUY', 18.6),
            _bet('fed', const Duration(hours: 30),
                'Will the Fed cut rates in December?', 'No', 'BUY', 16.8),
            _bet('btc150', const Duration(days: 3),
                'Will Bitcoin reach \$150,000 in 2026?', 'Yes', 'SELL', 5.25),
            _bet('rain', const Duration(days: 6), 'Will it rain in London?',
                'Yes', 'BUY', 4),
          ],
        )),
    for (final p in perps)
      hyperliquidLiveMidProvider(p.coin).overrideWith((_) => null),
    hyperliquidPerpMarketsProvider.overrideWith((_) async => [
          _market('BTC', 91100, 90000),
          _market('ETH', 3162, 3100),
        ]),
    hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
    hyperliquidActivityFillsProvider.overrideWithValue([
      _fill('BTC', const Duration(hours: 5), 'Open Long', 90120, 0.0125),
      _fill('ETH', const Duration(days: 2), 'Open Short', 3120, 0.08),
      _fill('SOL', const Duration(days: 4), 'Close Long', 186, 0.6,
          closedPnl: 4.2),
    ]),
    polymarketActivePositionsProvider.overrideWith((_) => [
          _position('lakers', 'Will the Lakers win the 2027 NBA Finals?',
              'Yes', 60, 0.31, 0.37),
          _position('fed', 'Will the Fed cut rates in December?', 'No', 40,
              0.42, 0.38),
          _position('btc150', 'Will Bitcoin reach \$150,000 in 2026?', 'Yes',
              25, 0.18, 0.21),
        ]),
    oneBalanceProvider.overrideWith((ref) => const OneBalanceState(
          dollarsUsd: 12.5,
          investedUsd: 1474.13,
          investedByVenue: {
            OneBalanceVenue.investing: 1420.35,
            OneBalanceVenue.predictions: 53.78,
          },
          investingKnown: true,
          predictionsKnown: true,
          venueCash: {
            OneBalanceVenue.investing: 4.71,
            OneBalanceVenue.predictions: 0.43,
          },
        )),
    ..._history(),
  ];
}

List<Override> _empty() => [
      ...portfolioOverrides(),
      hyperliquidActivityFillsProvider.overrideWithValue(const []),
      oneBalanceProvider.overrideWith((ref) => const OneBalanceState(
            dollarsUsd: 25,
            investingKnown: true,
            predictionsKnown: true,
          )),
    ];

Future<void> _mount(WidgetTester tester,
    {required bool dark,
    required PortfolioSection section,
    required List<Override> overrides,
    bool hidden = false}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...overrides,
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true,
          balancePrivacy: hidden ? 1 : 0,
          activeWalletId: 'spending',
          wallets: [WalletConfig(id: 'spending', name: 'Spending')]))),
      usdBalanceUnknownProvider.overrideWithValue(false),
      venueSweeperProvider.overrideWith(_Sweeper.new),
      portfolioSectionProvider.overrideWith((_) => section),
      currentBtcUsdProvider.overrideWithValue(100000),
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
    test('Portfolio overhaul render', () {},
        skip: 'on demand: --dart-define=PORTFOLIO_OVERHAUL_OUT=<dir>');
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

  setUpAll(() async {
    SalSpriteCache.debugReset();
    await SalSpriteCache.warm([kSalHeroLoop], 3);
  });
  tearDownAll(() => SalSpriteCache.debugSetManifest(null));

  testWidgets('P&L squares: one venue, hidden, a quiet venue, 375 at 130 %',
      (tester) async {
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final variants = <(String, List<Override> Function(), bool, Size, double)>[
      (
        'predictions_only',
        () => [
              ..._full(),
              portfolioVenuesProvider.overrideWithValue(
                  const PortfolioVenues(trading: false, predictions: true)),
            ],
        false,
        _size,
        1
      ),
      ('hidden', _full, true, _size, 1),
      (
        'investing_quiet',
        () => [
              ..._full(),
              portfolioPerformanceProvider(const PortfolioPerformanceRequest(
                      venue: PortfolioPerformanceVenue.trading))
                  .overrideWith((_) async => const PortfolioPerformance(
                      points: [],
                      sourceLabel: 'Hyperliquid',
                      basisLabel: 'P&L',
                      coverageLabel: 'All time')),
            ],
        false,
        _size,
        1
      ),
      ('375_130', _full, false, const Size(375, 812), 1.3),
    ];
    for (final (name, overrides, hidden, size, scale) in variants) {
      tester.view.devicePixelRatio = _dpr;
      tester.view.physicalSize = size * _dpr;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      for (final dark in [false, true]) {
        await _mount(tester,
            dark: dark,
            section: PortfolioSection.charts,
            overrides: overrides(),
            hidden: hidden);
        await tester.drag(find.byKey(const ValueKey('portfolio-page-scroll')),
            const Offset(0, -420));
        await _settle(tester);
        await _png(
            tester, 'portfolio_pnl_${name}_${dark ? 'dark' : 'light'}');
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  for (final (name, overrides) in [('full', _full), ('empty', _empty)]) {
    testWidgets('$name, every section, light and dark', (tester) async {
      tester.view.devicePixelRatio = _dpr;
      tester.view.physicalSize = _size * _dpr;
      addTearDown(tester.view.reset);
      for (final dark in [false, true]) {
        for (final section in PortfolioSection.values) {
          await _mount(tester,
              dark: dark, section: section, overrides: overrides());
          final tag = '${name}_${section.key}_${dark ? 'dark' : 'light'}';
          await _png(tester, 'portfolio_$tag');
          // Scrolled to the section, the strip pinned.
          await tester.drag(
              find.byKey(const ValueKey('portfolio-page-scroll')),
              const Offset(0, -420));
          await _settle(tester);
          await _png(tester, 'portfolio_${tag}_scrolled');
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
