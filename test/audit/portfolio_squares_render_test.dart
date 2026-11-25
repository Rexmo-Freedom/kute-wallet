// Render harness for the Portfolio section's squares (founder, 2 November
// 2026: "maybe the biggest investments get the squares and the others
// just get a normal line"): the biggest open positions as squares two by
// two, the rest as the Investing list's rows under their venue, with 2, 3
// and 6 positions (Investing and Predictions mixed), light and dark, at
// 390 x 844 in the app's real theme and Inter. Writes PNGs.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/portfolio_squares_render_test.dart \
//     --dart-define=PORTFOLIO_SQUARES_OUT=/tmp/portfolio-squares

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
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidPerpMarketsProvider, hyperliquidSpotMarketsProvider;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition, polymarketActivePositionsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
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

const _out = String.fromEnvironment('PORTFOLIO_SQUARES_OUT');
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

PolymarketPosition _bet(String token, String question, String side,
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

final _btc = _perp('BTC', 0.0125, 90120, 1168.75, 12.25);
final _eth = _perp('ETH', -0.08, 3120, 251.6, -3.4);
final _sol = _perp('SOL', 0.6, 180, 108.9, 2.1);
final _lakers = _bet('lakers', 'Will the Lakers win the 2027 NBA Finals?',
    'Yes', 60, 0.31, 0.37);
final _rain = _bet('fed', 'Will the Fed cut rates in December?', 'No', 40,
    0.42, 0.38);
final _btc150 = _bet('btc150', 'Will Bitcoin reach \$150,000 in 2026?',
    'Yes', 25, 0.18, 0.21);

/// A scenario: its Investing positions and its predictions.
typedef _Scenario = ({
  String name,
  List<HlPerpPosition> perps,
  List<PolymarketPosition> bets,
});

final _scenarios = <_Scenario>[
  (name: 'two', perps: [_btc], bets: [_lakers]),
  (name: 'three', perps: [_btc, _eth], bets: [_lakers]),
  (name: 'six', perps: [_btc, _eth, _sol], bets: [_lakers, _rain, _btc150]),
];

OneBalanceState _stateFor(_Scenario s) {
  final investing = s.perps.fold<double>(0, (t, p) => t + p.positionValue);
  final predictions =
      s.bets.fold<double>(0, (t, p) => t + p.size * p.currentPrice);
  return OneBalanceState(
    investedUsd: investing + predictions,
    investedByVenue: {
      OneBalanceVenue.investing: investing,
      OneBalanceVenue.predictions: predictions,
    },
    investingKnown: true,
    predictionsKnown: true,
    venueCash: const {
      OneBalanceVenue.investing: 17.21,
      OneBalanceVenue.predictions: 0.43,
    },
  );
}

List<Override> _held(_Scenario s) => [
      ...portfolioOverrides(
          trading: HyperliquidTradingState(
              isInitialized: true, positions: s.perps)),
      for (final p in s.perps)
        hyperliquidLiveMidProvider(p.coin).overrideWith((_) => null),
      hyperliquidPerpMarketsProvider.overrideWith((_) async => [
            _market('BTC', 91100, 90000),
            _market('ETH', 3162, 3100),
            _market('SOL', 181.5, 178),
          ]),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      polymarketActivePositionsProvider.overrideWith((_) => s.bets),
    ];

Future<void> _mount(WidgetTester tester,
    {required bool dark,
    required OneBalanceState state,
    required PortfolioSection section,
    List<Override> extra = const []}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ProviderScope(
    overrides: [
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
    test('Portfolio squares render', () {},
        skip: 'on demand: --dart-define=PORTFOLIO_SQUARES_OUT=<dir>');
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

  for (final s in _scenarios) {
    testWidgets('${s.name} positions, light and dark', (tester) async {
      tester.view.devicePixelRatio = _dpr;
      tester.view.physicalSize = _size * _dpr;
      addTearDown(tester.view.reset);
      for (final dark in [false, true]) {
        await _mount(tester,
            dark: dark,
            state: _stateFor(s),
            section: PortfolioSection.balances,
            extra: _held(s));
        await _png(tester,
            'portfolio_squares_${s.name}_${dark ? 'dark' : 'light'}');
        // Scrolled to the section, the strip pinned: the whole list.
        await tester.drag(
            find.byKey(const ValueKey('portfolio-page-scroll')),
            const Offset(0, -260));
        await _settle(tester);
        await _png(tester,
            'portfolio_squares_${s.name}_${dark ? 'dark' : 'light'}_scrolled');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
