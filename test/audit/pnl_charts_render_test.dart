// Render harness for Investments → Portfolio → P&L charts (founder review,
// 28 October 2026): the P&L chart card, then the Balances frame around
// the figures (the bare ring, Open P&L with the Active | Historic pair,
// each venue's row with its figures, its sub-row and its resting orders),
// Active and Historic, at the top and scrolled to the figures, at 390 x
// 844 in the app's real themes and Inter, light and dark. Writes PNGs.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/pnl_charts_render_test.dart \
//     --dart-define=PORTFOLIO_REDESIGN_OUT=/tmp/pnl-charts \
//     --dart-define=PORTFOLIO_REDESIGN_IMAGES=/tmp/portfolio-images
//
// The images directory (optional) holds the pictures the order rows would
// load from the network: kane.jpg (a Polymarket market image) and btc.svg
// (Hyperliquid's coin logo). Without it the rows draw their fallback
// glyphs. The wallet is the Balances render's: four predictions (three
// live, one settled), two Investing positions, one resting order at each
// venue.

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
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidPerpMarketsProvider, hyperliquidSpotMarketsProvider;
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_order_metadata_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

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

/// Buying power \$17.64; four predictions worth \$19.03 (one settled); two
/// Investing positions worth \$1,704.85.
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
  static const _byWord = {'harry-kane': 'kane.jpg'};

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

/// The Investing account as the venue reports it, every read.
class _Account extends HlAccountNotifier {
  @override
  Future<HlAccountSnapshot> build() async => const HlAccountSnapshot(
      accountValue: 1722.06,
      withdrawable: 17.21,
      totalMarginUsed: 1673.7,
      positions: [_btc, _nvda],
      spotBalances: []);
}

/// The account's fills: the two open positions and one ETH round trip
/// closed for +60 on 1.20 of fees.
List<HlFill> _fills() {
  final now = DateTime.now().toUtc();
  int ago(int days) =>
      now.subtract(Duration(days: days)).millisecondsSinceEpoch;
  HlFill fill(String id, String coin, double before, double size, String side,
          int time,
          {required double px, double pnl = 0, required double fee}) =>
      HlFill.fromJson({
        'coin': coin,
        'tid': id,
        'oid': int.parse(id),
        'hash': 'h$id',
        'time': time,
        'startPosition': '$before',
        'sz': '$size',
        'px': '$px',
        'side': side,
        'closedPnl': '$pnl',
        'fee': '$fee',
        'feeToken': 'USDC',
        'dir': before == 0 ? 'Open Long' : 'Close Long',
      });
  return [
    fill('4', 'xyz:NVDA', 0, 3, 'A', ago(3), px: 182.4, fee: 0.55),
    fill('3', 'BTC', 0, 0.0125, 'B', ago(6), px: 90120, fee: 0.4),
    fill('2', 'ETH', 0.5, 0.5, 'A', ago(14), px: 3120, pnl: 60, fee: 0.6),
    fill('1', 'ETH', 0, 0.5, 'B', ago(21), px: 3000, fee: 0.6),
  ];
}

/// A resting Investing limit order: buy a little more BTC at 88,000.
const _hlOrder = HlOpenOrder(
    coin: 'BTC',
    oid: 7,
    isBuy: true,
    limitPx: 88000,
    sz: 0.005,
    origSz: 0.005,
    timestamp: 1761600000000,
    cloid: null,
    reduceOnly: false,
    orderType: 'Limit',
    isTrigger: false,
    triggerPx: null);

/// A resting Predictions limit order: 10 more Kane Yes shares at 65¢.
const _pmOrder = Order(
    id: 'pm-1',
    market: 'kane',
    assetId: 'kane-yes',
    owner: '0xme',
    side: 'BUY',
    price: '0.65',
    originalSize: '10',
    sizeMatched: '0',
    outcome: 'Yes',
    timestamp: '1761600000');

/// The venues' P&L series and, for Predictions, the account's positions:
/// three live (Kane, Madrid, Lula) and one settled win (F1).
List<Override> _performance() {
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
  PredictionRecord record(String token,
          {required bool open,
          bool redeemable = false,
          required double size,
          required double avgPrice,
          required double price,
          required int entered,
          String market = '',
          String title = ''}) =>
      PredictionRecord(
          tokenId: token,
          open: open,
          redeemable: redeemable,
          size: size,
          totalSize: size,
          avgPrice: avgPrice,
          entryCostUsd: size * avgPrice,
          currentPrice: price,
          realizedPnlUsd: 0,
          unrealizedPnlUsd: size * (price - avgPrice),
          firstEntryAt: ago(entered),
          lastEventAt: ago(entered),
          conditionId: market,
          title: title);
  final book = PredictionsBook(records: [
    record('kane-yes',
        open: true,
        size: 4.99,
        avgPrice: 0.72,
        price: 0.718,
        entered: 9,
        market: 'kane',
        title: "Will Harry Kane win the 2026 Ballon d'Or?"),
    record('rm-no',
        open: true,
        size: 10,
        avgPrice: 0.40,
        price: 0.47,
        entered: 4,
        market: 'rm',
        title: 'Will Real Madrid CF win on 2026-10-25?'),
    record('lula-yes',
        open: true,
        size: 12.5,
        avgPrice: 0.38,
        price: 0.3801,
        entered: 2,
        market: 'lula',
        title: 'Will Lula win the 2026 Brazilian presidential election?'),
    record('f1-v',
        open: true,
        redeemable: true,
        size: 6,
        avgPrice: 0.55,
        price: 1,
        entered: 12,
        market: 'f1',
        title: 'Who will finish higher: Verstappen or Hadjar?'),
  ]);
  return [
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.trading))
        .overrideWith((_) async => series(
            [(30, 0), (21, -4.2), (14, 55.4), (9, 48.1), (6, 61.3), (1, 89.0)],
            'Hyperliquid')),
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.predictions))
        .overrideWith((_) async =>
            series([(12, 0), (9, -0.4), (4, 2.3), (2, 3.1)], 'Polymarket')
                .withPredictions(book)),
  ];
}

List<Override> get _held => [
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
          const HyperliquidTradingState(
              isInitialized: true,
              positions: [_btc, _nvda],
              openOrders: [_hlOrder]))),
      hyperliquidDisplayTradingProvider
          .overrideWith((ref) => ref.watch(hyperliquidTradingProvider)),
      hyperliquidAccountProvider.overrideWith(_Account.new),
      hyperliquidDisplayAccountProvider
          .overrideWith((ref) => ref.watch(hyperliquidAccountProvider)),
      hyperliquidUserFillsProvider.overrideWith((_) async => _fills()),
      hyperliquidActivityFillsProvider.overrideWithValue(_fills()),
      hyperliquidLiveMidProvider('BTC').overrideWith((_) => null),
      hyperliquidLiveMidProvider('xyz:NVDA').overrideWith((_) => null),
      hyperliquidPerpMarketsProvider.overrideWith((_) async => [
            _perp('BTC', 'BTC', 93500),
            _perp('NVDA', 'xyz:NVDA', 186.1, category: 'stocks', hip3: true),
          ]),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      polymarketOpenOrdersProvider
          .overrideWith((_) => Stream.value(const [_pmOrder])),
      polymarketOrderMetadataProvider.overrideWith((_) async => const {
            'kane': PolymarketOrderMetadata(
                title: "Will Harry Kane win the 2026 Ballon d'Or?",
                imageUrl:
                    'https://polymarket-upload.s3.us-east-2.amazonaws.com/'
                    'ballon-dor-2026-harry-kane-536e46ad53.jpg'),
          }),
      livePriceProvider.overrideWith(_Prices.new),
      ..._performance(),
    ];

Future<void> _mount(WidgetTester tester, bool dark) async {
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
      oneBalanceProvider.overrideWith((ref) => _state),
      usdBalanceUnknownProvider.overrideWithValue(false),
      venueSweeperProvider.overrideWith(_Sweeper.new),
      ..._held,
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
                    color: Colors.transparent,
                    child: ProviderScope(
                      overrides: [
                        portfolioSectionProvider
                            .overrideWith((_) => PortfolioSection.charts)
                      ],
                      child: InvestmentsPortfolio(onSection: (_) {}),
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
    // The pictures load from files and decode off the frame.
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

Future<void> _scroll(WidgetTester tester, double by) async {
  await tester.drag(find.byType(CustomScrollView).first, Offset(0, -by));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  if (_out.isEmpty) {
    test('P&L charts render', () {},
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

  for (final historic in [false, true]) {
    final scope = historic ? 'historic' : 'active';
    testWidgets('$scope, light and dark, top and scrolled', (tester) async {
      tester.view.devicePixelRatio = _dpr;
      tester.view.physicalSize = _size * _dpr;
      addTearDown(tester.view.reset);
      for (final dark in [false, true]) {
        final theme = dark ? 'dark' : 'light';
        await _mount(tester, dark);
        if (historic) {
          await tester.tap(find.byKey(const ValueKey('statistics-historic')));
          await _settle(tester);
        }
        await _png(tester, '${scope}_top_$theme');
        // The frame under the chart card, whole.
        await _scroll(tester, 430);
        await _png(tester, '${scope}_figures_$theme');
        // The orders at the end.
        await _scroll(tester, 2000);
        await _png(tester, '${scope}_orders_$theme');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
