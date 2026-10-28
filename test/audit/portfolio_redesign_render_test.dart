// Render harness for the Investments → Portfolio redesign (October 2026):
// the Balances section (Available to invest with the small ring, Move
// money on the right, Predictions and Investing with their position rows in
// grouped cards; also
// with nothing open at Investing, and its split opened), at
// 390 x 844 in the app's real themes and Inter, light and dark. Writes
// PNGs.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/portfolio_redesign_render_test.dart \
//     --dart-define=PORTFOLIO_REDESIGN_OUT=/tmp/portfolio-redesign \
//     --dart-define=PORTFOLIO_REDESIGN_IMAGES=/tmp/portfolio-images
//
// The images directory (optional) holds the pictures the rows would load
// from the network: kane.jpg, lula.jpg, rm.png, f1.png (Polymarket market
// images) and btc.svg, nvda.svg (Hyperliquid's coin logos). Without it the
// rows draw their fallback glyphs.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// The cache manager's own File type (package:file), for the local
// artwork below.
// ignore: depend_on_referenced_packages
import 'package:file/file.dart' as fs;
// ignore: depend_on_referenced_packages
import 'package:file/local.dart' show LocalFileSystem;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart'
    show PolymarketEvent, PolymarketOutcome;
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidPerpMarketsProvider, hyperliquidSpotMarketsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show
        PolymarketPosition,
        polymarketActivePositionsProvider,
        polymarketClaimablePositionsProvider;
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/portfolio_overrides.dart';

const _out = String.fromEnvironment('PORTFOLIO_REDESIGN_OUT');
const _images = String.fromEnvironment('PORTFOLIO_REDESIGN_IMAGES');
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

/// Buying power \$17.64 (no dollars, \$17.21 at Hyperliquid, \$0.43 at
/// Polymarket); four predictions worth \$19.03 (one settled); two Investing
/// positions worth \$1,704.85.
const _state = OneBalanceState(
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

/// The same, nothing open at Investing.
const _emptyInvestingState = OneBalanceState(
  investedUsd: 19.03,
  investedByVenue: {OneBalanceVenue.predictions: 19.03},
  investingKnown: true,
  predictionsKnown: true,
  venueCash: {
    OneBalanceVenue.investing: 17.21,
    OneBalanceVenue.predictions: 0.43,
  },
);

/// Nothing open anywhere, the cash read: Sal's empty state.
const _nothingOpenState = OneBalanceState(
  investingKnown: true,
  predictionsKnown: true,
  venueCash: {
    OneBalanceVenue.investing: 17.21,
    OneBalanceVenue.predictions: 0.43,
  },
);

/// The first load: neither venue read yet this session.
const _unreadState = OneBalanceState(
  venueCash: {OneBalanceVenue.investing: 17.21},
);

/// No live price feed: the rows at their last read price.
class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();

  @override
  void acquire() {}

  @override
  void release() {}

  @override
  void registerCardTokens(List<String> tokens) {}

  @override
  void unregisterCardTokens(List<String> tokens) {}
}

/// Market pictures from the images directory, by a word of their URL.
class _LocalArtwork implements BaseCacheManager {
  static const _byWord = {
    'harry-kane': 'kane.jpg',
    'lula': 'lula.jpg',
    'league-lal': 'rm.png',
    'f1-': 'f1.png',
  };

  @override
  Future<fs.File> getSingleFile(String url,
      {String key = "", Map<String, String> headers = const {}}) async {
    for (final e in _byWord.entries) {
      if (url.contains(e.key)) {
        return const LocalFileSystem().file('$_images/${e.value}');
      }
    }
    throw const HttpException('no local artwork');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Hyperliquid's coin logos from the images directory.
final _coinLogos = MockClient((request) async {
  final path = request.url.path;
  for (final (word, file) in [('NVDA', 'nvda.svg'), ('BTC', 'btc.svg')]) {
    final f = File('$_images/$file');
    if (path.contains(word) && f.existsSync()) {
      return http.Response.bytes(f.readAsBytesSync(), 200,
          headers: {'content-type': 'image/svg+xml'});
    }
  }
  return http.Response('', 404);
});

const _btc = HlPerpPosition(
    coin: 'BTC',
    szi: 0.0125,
    entryPx: 90120,
    positionValue: 1168.75,
    unrealizedPnl: 42.25,
    returnOnEquity: 0.0375,
    liquidationPx: null,
    marginUsed: 1126.5,
    leverageType: 'isolated',
    leverageValue: 1,
    maxLeverage: 40);

const _nvda = HlPerpPosition(
    coin: 'xyz:NVDA',
    szi: -3,
    entryPx: 182.4,
    positionValue: 558.3,
    unrealizedPnl: -11.1,
    returnOnEquity: -0.0203,
    liquidationPx: 360.2,
    marginUsed: 547.2,
    leverageType: 'isolated',
    leverageValue: 1,
    maxLeverage: 10);

HlMarket _perp(String coin, String wire, double mid,
        {String category = 'crypto', bool hip3 = false}) =>
    HlMarket(
        coin: coin,
        wireCoin: wire,
        assetId: 1,
        kind: HlMarketKind.perp,
        szDecimals: 4,
        maxLeverage: 10,
        onlyIsolated: false,
        markPx: mid,
        midPx: mid,
        prevDayPx: mid,
        dayNtlVlm: 1e6,
        category: category,
        dex: hip3 ? 'xyz' : '',
        isHip3: hip3);

const _kane = PolymarketPosition(
    marketId: 'kane',
    marketQuestion: "Will Harry Kane win the 2026 Ballon d'Or?",
    marketImage: 'https://polymarket-upload.s3.us-east-2.amazonaws.com/'
        'ballon-dor-2026-harry-kane-536e46ad53.jpg',
    outcome: 'Yes',
    size: 4.99,
    avgPrice: 0.72,
    currentPrice: 0.718,
    pnl: 0,
    pnlPercent: 0,
    isResolved: false,
    tokenId: 'kane-yes',
    eventSlug: 'ballon-dor-2026');

const _madrid = PolymarketPosition(
    marketId: 'rm',
    marketQuestion: 'Will Real Madrid CF win on 2026-10-25?',
    marketImage:
        'https://polymarket-upload.s3.us-east-2.amazonaws.com/league-lal.png',
    outcome: 'No',
    size: 10,
    avgPrice: 0.40,
    currentPrice: 0.47,
    pnl: 0,
    pnlPercent: 0,
    isResolved: false,
    tokenId: 'rm-no');

const _lula = PolymarketPosition(
    marketId: 'lula',
    marketQuestion: 'Will Luiz Inácio Lula da Silva win the 2026 Brazilian '
        'presidential election?',
    marketImage: 'https://polymarket-upload.s3.us-east-2.amazonaws.com/'
        'will-luiz-incio-lula-da-silva-win-the-2026-brazilian-presidential-'
        'election-reTil6nEVB1J.jpg',
    outcome: 'Yes',
    size: 12.5,
    avgPrice: 0.38,
    currentPrice: 0.3801,
    pnl: 0,
    pnlPercent: 0,
    isResolved: false,
    tokenId: 'lula-yes',
    eventSlug: 'brazil-presidential-election');

const _f1 = PolymarketPosition(
    marketId: 'f1',
    marketQuestion: 'Who will finish higher: Verstappen or Hadjar?',
    marketImage: 'https://polymarket-upload.s3.us-east-2.amazonaws.com/'
        'f1-constructors-champion-2025-PULWDiyoGXZ7.png',
    outcome: 'Verstappen',
    size: 6,
    avgPrice: 0.55,
    currentPrice: 1,
    pnl: 0,
    pnlPercent: 0,
    isResolved: true,
    won: true,
    tokenId: 'f1-v');

/// A many-outcome event holding the market [conditionId] under its own
/// name ([candidate], Polymarket's groupItemTitle).
PolymarketEvent _event(
        String slug, String title, String conditionId, String candidate) =>
    PolymarketEvent(
      id: slug,
      slug: slug,
      title: title,
      volume: 1e6,
      liquidity: 1e5,
      category: 'politics',
      conditionId: conditionId,
      outcomes: [
        PolymarketOutcome(
            name: candidate,
            price: 0.4,
            conditionId: conditionId,
            tokenId: '$conditionId-yes',
            noTokenId: '$conditionId-no'),
        PolymarketOutcome(
            name: 'Someone else',
            price: 0.2,
            conditionId: 'other',
            tokenId: 'other-yes',
            noTokenId: 'other-no'),
      ],
    );

List<Override> get _held => [
      polyPositionEventProvider('ballon-dor-2026').overrideWith((_) =>
          _event('ballon-dor-2026', "Ballon d'Or 2026", 'kane', 'Harry Kane')),
      polyPositionEventProvider('brazil-presidential-election').overrideWith(
          (_) => _event('brazil-presidential-election',
              'Brazil Presidential Election', 'lula', 'Lula da Silva')),
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
          const HyperliquidTradingState(
              isInitialized: true, positions: [_btc, _nvda]))),
      hyperliquidDisplayTradingProvider
          .overrideWith((ref) => ref.watch(hyperliquidTradingProvider)),
      hyperliquidLiveMidProvider('BTC').overrideWith((_) => null),
      hyperliquidLiveMidProvider('xyz:NVDA').overrideWith((_) => null),
      hyperliquidPerpMarketsProvider.overrideWith((_) async => [
            _perp('BTC', 'BTC', 93500),
            _perp('NVDA', 'xyz:NVDA', 186.1, category: 'stocks', hip3: true),
          ]),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      polymarketActivePositionsProvider
          .overrideWith((_) => const [_kane, _madrid, _lula]),
      polymarketClaimablePositionsProvider.overrideWith((_) => const [_f1]),
      livePriceProvider.overrideWith(_Prices.new),
    ];

/// Nothing open at Investing; the four predictions as above.
List<Override> get _emptyInvestingHeld => [
      ..._held,
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
          const HyperliquidTradingState(isInitialized: true))),
    ];

/// Nothing open at either venue.
List<Override> get _nothingOpenHeld => [
      ..._held,
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
          const HyperliquidTradingState(isInitialized: true))),
      polymarketActivePositionsProvider.overrideWith((_) => const []),
      polymarketClaimablePositionsProvider.overrideWith((_) => const []),
    ];

/// The first load: Investing's positions still being read.
List<Override> get _firstLoadHeld => [
      ..._held,
      hyperliquidDisplayTradingProvider
          .overrideWith((_) => const AsyncLoading<HyperliquidTradingState>()),
    ];

Future<ui.Image> _shoot(WidgetTester tester, bool dark,
    {required WidgetBuilder body,
    List<Override> overrides = const [],
    OneBalanceState state = _state,
    List<Override>? held}) async {
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
      ...(held ?? _held),
      ...overrides,
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
              body: DecoratedBox(
                decoration: AppDecorations.screenGradient(context),
                child: SafeArea(
                    child: Material(
                        color: Colors.transparent, child: body(context))),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    // The pictures load from files and decode off the frame.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)));
  }
  await tester.pump(const Duration(seconds: 1));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  return (await tester.runAsync(() => boundary.toImage(pixelRatio: _dpr)))!;
}

Future<void> _png(WidgetTester tester, ui.Image image, String name) =>
    tester.runAsync(() async {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });

Widget _section(PortfolioSection section) => ProviderScope(
      overrides: [portfolioSectionProvider.overrideWith((_) => section)],
      child: InvestmentsPortfolio(onSection: (_) {}),
    );

/// Balances scrolled to its end ([scroll]) or with the split opened
/// ([split]).
Future<void> _prepare(WidgetTester tester,
    {bool scroll = false, bool split = false}) async {
  if (split) {
    await tester
        .tap(find.byKey(const ValueKey('portfolio-balance-split-toggle')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  if (scroll) {
    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, -2000));
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  if (_out.isEmpty) {
    test('portfolio redesign render', () {},
        skip: 'on demand: --dart-define=PORTFOLIO_REDESIGN_OUT=<dir>');
    return;
  }

  setUpAll(() async {
    Directory(_out).createSync(recursive: true);
    if (_images.isNotEmpty) {
      PolyCrestImage.debugCacheManager = _LocalArtwork();
      SharedHttpClient.debugOverride = _coinLogos;
    }
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
    // The app bundles Material's icon font; the test does not, so the
    // chevrons would draw as boxes. The SDK's own copy, when it is there.
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

  // The first load (the venues' skeleton) and nothing open anywhere
  // (Sal), light only.
  for (final (name, state, held) in [
    ('balances_first_load', _unreadState, _firstLoadHeld),
    ('balances_nothing_open', _nothingOpenState, _nothingOpenHeld),
  ]) {
    testWidgets('$name, light', (tester) async {
      tester.view.devicePixelRatio = _dpr;
      tester.view.physicalSize = _size * _dpr;
      addTearDown(tester.view.reset);
      final img = await _shoot(tester, false,
          state: state,
          held: held,
          body: (_) => _section(PortfolioSection.balances));
      await _png(tester, img, '${name}_light');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final (name, empty, split, scroll) in [
    ('balances', false, false, false),
    ('balances_split', false, true, false),
    ('balances_empty_investing', true, false, false),
    ('hero_balances', false, false, false),
  ]) {
    testWidgets('$name, light and dark', (tester) async {
      tester.view.devicePixelRatio = _dpr;
      tester.view.physicalSize = _size * _dpr;
      addTearDown(tester.view.reset);
      for (final dark in [false, true]) {
        await _shoot(tester, dark,
            state: empty ? _emptyInvestingState : _state,
            held: empty ? _emptyInvestingHeld : null,
            body: (_) => name.startsWith('hero')
                // The Investments hero ("Available · Invested" under the
                // total) over Balances, without the app's top tabs.
                ? Column(children: [
                    const InvestmentBalanceHeader(
                        product: InvestmentsProduct.trading, oneBalance: true),
                    Expanded(child: _section(PortfolioSection.balances)),
                  ])
                : _section(PortfolioSection.balances));
        await _prepare(tester, scroll: scroll, split: split);
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
        final img =
            (await tester.runAsync(() => boundary.toImage(pixelRatio: _dpr)))!;
        await _png(tester, img, '${name}_${dark ? 'dark' : 'light'}');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
