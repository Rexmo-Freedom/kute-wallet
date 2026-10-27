// Render harness for the Investments market lists (the "lists light" pass,
// October 2026): Investing → Trending and Predictions → Trending (the BTC
// 5-minute card on top, markets under it) on the real Investments screen,
// at 390 x 1600 in the app's real themes and Inter, light and dark. Writes
// PNGs.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/market_lists_render_test.dart \
//     --dart-define=MARKET_LISTS_OUT=/tmp/market-lists

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
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/crypto_live_odds_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/providers/refresh_everything_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/usd_rewards_provider.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/services/polymarket/crypto_live_odds.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/portfolio_overrides.dart';
import '../screens/usd/investments_harness.dart'
    show
        InvestmentsTestPolicy,
        RecordingRefresh,
        RecordingRewardsApi,
        kEarnOff,
        kInvestmentsTestBalance;

const _out = String.fromEnvironment('MARKET_LISTS_OUT');
const _key = ValueKey('shot');
const _dpr = 3.0;
// Tall enough to show the list under the 5-minute card.
const _size = Size(390, 1600);

class _NoStars extends HlWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _NoPolyStars extends PolyWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _HlMids extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState();
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
}

/// No live Polymarket feed: the cards at the feed's own prices.
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

class _Odds extends CryptoLiveOddsNotifier {
  @override
  Map<String, CryptoLiveOdds> build() => const {};
  @override
  void watch(String token) {}
  @override
  void unwatch(String token) {}
}

/// A BTC 5-minute round in progress, its price a little above the strike.
class _Round extends CryptoPredictNotifier {
  @override
  Future<CryptoPredictState> build(String arg) async {
    final start = DateTime(2026, 10, 27, 15, 10);
    var px = 114180.0;
    return CryptoPredictState(
      asset: arg,
      currentPrice: 114236,
      priceToBeat: 114180,
      secondsRemaining: 163,
      event: Btc5MinEvent(
        slug: 'btc-updown-5m-1761577800',
        title: 'Bitcoin Up or Down',
        windowStartTime: start,
        endDate: start.add(const Duration(minutes: 5)),
        upPrice: 0.62,
        downPrice: 0.38,
      ),
      priceHistory: [
        for (var i = 0; i < 140; i++)
          BtcPriceSnapshot(
            timestamp: start.add(Duration(seconds: i)),
            price: px += ((i * 37) % 11 - 4.6) * 1.4,
          ),
      ],
    );
  }
}

class _Feed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) =>
      PolyFeedState(events: _events, done: true);
}

HlMarket _hl(String coin, double px, double prev, double vlm,
        {String category = 'crypto',
        HlMarketKind kind = HlMarketKind.perp,
        String? wire,
        bool hip3 = false}) =>
    HlMarket(
      coin: coin,
      wireCoin: wire ?? coin,
      assetId: 0,
      kind: kind,
      szDecimals: 2,
      maxLeverage: 20,
      onlyIsolated: false,
      markPx: px,
      midPx: px,
      prevDayPx: prev,
      dayNtlVlm: vlm,
      category: category,
      isHip3: hip3,
      dex: hip3 ? 'xyz' : '',
    );

final _universe = [
  _hl('BTC', 114236, 113100, 4e9),
  _hl('ETH', 4128.4, 4080, 2e9),
  _hl('HYPE', 47.912, 46.1, 9e8),
  _hl('SOL', 201.37, 205.2, 8e8),
  _hl('NVDA', 186.1, 183.9, 6e8,
      category: 'stocks', wire: 'xyz:NVDA', hip3: true),
  _hl('XRP', 2.6312, 2.598, 5e8),
  _hl('DOGE', 0.20514, 0.2101, 4e8),
  _hl('TSLA', 452.8, 447.2, 3e8,
      category: 'stocks', wire: 'xyz:TSLA', hip3: true),
  _hl('ZEC', 342.5, 330.1, 2e8),
  _hl('NEAR', 2.4512, 2.51, 1e8),
];

PolymarketOutcome _o(String name, double price, {String? id}) =>
    PolymarketOutcome(name: name, price: price, tokenId: id);

final _events = [
  PolymarketEvent(
    id: 'fed',
    slug: 'fed-decision-in-december',
    title: 'Fed decreases interest rates by 25 bps after December meeting?',
    volume: 48.2e6,
    liquidity: 1e6,
    category: 'finance',
    conditionId: 'fed',
    endDate: DateTime(2026, 12, 10),
    oneDayPriceChange: 0.03,
    outcomes: [_o('Yes', 0.71), _o('No', 0.29)],
  ),
  PolymarketEvent(
    id: 'trump',
    slug: 'who-will-trump-meet',
    title: 'Who will Trump meet in October?',
    volume: 3.1e6,
    liquidity: 1e5,
    category: 'politics',
    conditionId: 'trump',
    endDate: DateTime(2026, 10, 31),
    negRisk: true,
    outcomes: [
      for (final (n, p) in [
        ('Xi Jinping', 0.83),
        ('Vladimir Putin', 0.22),
        ('Kim Jong Un', 0.08),
        ('Narendra Modi', 0.07),
        ('Lula', 0.05),
        ('Javier Milei', 0.04),
      ])
        PolymarketOutcome(
            name: n,
            price: p,
            conditionId: n,
            tokenId: '$n-yes',
            noTokenId: '$n-no'),
    ],
  ),
  PolymarketEvent(
    id: 'btc150',
    slug: 'btc-150k-2026',
    title: 'Will Bitcoin reach \$150,000 by December 31?',
    volume: 12.7e6,
    liquidity: 1e5,
    category: 'crypto',
    conditionId: 'btc150',
    endDate: DateTime(2026, 12, 31),
    oneDayPriceChange: -0.02,
    outcomes: [_o('Yes', 0.14), _o('No', 0.86)],
  ),
  PolymarketEvent(
    id: 'nyc',
    slug: 'nyc-mayor',
    title: 'New York City Mayoral Election',
    volume: 410e6,
    liquidity: 1e6,
    category: 'politics',
    conditionId: 'nyc',
    endDate: DateTime(2026, 11, 4),
    negRisk: true,
    outcomes: [
      for (final (n, p) in [
        ('Zohran Mamdani', 0.93),
        ('Andrew Cuomo', 0.06),
        ('Curtis Sliwa', 0.01),
      ])
        PolymarketOutcome(
            name: n,
            price: p,
            conditionId: n,
            tokenId: '$n-yes',
            noTokenId: '$n-no'),
    ],
  ),
];

Future<ui.Image> _shoot(WidgetTester tester, bool dark,
    {required bool predictions}) async {
  final policy = InvestmentsTestPolicy(kEarnOff,
      browseInvesting: true, browsePredictions: true);
  RuntimeCapabilitiesService.debugInstance = policy;
  const balance = kInvestmentsTestBalance;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(dollars: balance.dollarsUsd),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          ))),
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      oneBalanceProvider.overrideWithValue(balance),
      usdBalanceProvider.overrideWithValue(balance.dollarsUsd),
      sparkIdentityPubkeyProvider.overrideWith((_) async => 'pub'),
      usdRewardsApiProvider.overrideWithValue(RecordingRewardsApi()),
      aiEnabledProvider.overrideWith((_) async => true),
      hyperliquidPerpMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      hyperliquidPerpCoreMarketsProvider
          .overrideWith((_) async => <HlMarket>[]),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      hyperliquidBrowseUniverseProvider
          .overrideWithValue(AsyncValue.data(_universe)),
      hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
      hyperliquidLivePricesProvider.overrideWith(_HlMids.new),
      hyperliquidSparklineStoreProvider.overrideWithValue(HlSparklineStore(
        // A smooth daily walk per coin, ending on today's close.
        fetch: (wire) async {
          final seed = wire.codeUnits.fold<int>(0, (a, b) => a + b);
          final drift = (seed % 5 - 2) * 0.35;
          return [
            for (var i = 0; i < 90; i++)
              100 +
                  drift * i +
                  6 * math.sin(i / (6 + seed % 4) + seed) +
                  2.5 * math.sin(i / 2.3 + seed * 0.7),
          ];
        },
      )),
      hlWatchlistProvider.overrideWith(_NoStars.new),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      polyWatchlistProvider.overrideWith(_NoPolyStars.new),
      polyBrowseFeedProvider.overrideWith(_Feed.new),
      cryptoPredictProvider.overrideWith(_Round.new),
      cryptoPredictWindowsProvider.overrideWith((_, __) async => [5, 15]),
      cryptoRecentResultsProvider.overrideWith((_, __) async => const []),
      cryptoLiveOddsProvider.overrideWith(_Odds.new),
      livePriceProvider.overrideWith(_Prices.new),
      refreshEverythingProvider.overrideWith(RecordingRefresh.new),
    ],
    child: ScreenUtilInit(
      // A phone's scale on the taller canvas: .h as on a 390 x 844 phone.
      designSize: Size(430, 932 * _size.height / 844),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const RepaintBoundary(
            key: _key, child: Scaffold(body: UsdAccountScreen())),
      ),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  if (predictions) {
    final l10n = AppLocalizations.of(
        tester.element(find.byType(KutePillTabs).first));
    await tester.tap(find.descendant(
        of: find.byType(KutePillTabs).first,
        matching: find.widgetWithText(KutePill, l10n.predictions)));
  }
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  return (await tester.runAsync(() => boundary.toImage(pixelRatio: _dpr)))!;
}

Future<void> _png(WidgetTester tester, ui.Image image, String name) =>
    tester.runAsync(() async {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });

void main() {
  if (_out.isEmpty) {
    test('market lists render', () {},
        skip: 'on demand: --dart-define=MARKET_LISTS_OUT=<dir>');
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
    // Text styled through GoogleFonts.inter(fontWeight: …) asks for a
    // family per weight ("Inter_700"): the nearest bundled cut for each.
    for (final w in FontWeight.values) {
      final file = w.value <= 400
          ? 'Regular'
          : w.value <= 600
              ? 'SemiBold'
              : 'Bold';
      await (FontLoader(GoogleFonts.inter(fontWeight: w).fontFamily!)
            ..addFont(rootBundle.load('lib/assets/fonts/Inter-$file.ttf')))
          .load();
    }
    // The category glyphs on imageless thumbnails.
    await (FontLoader('packages/bootstrap_icons/BootstrapIcons')
          ..addFont(rootBundle
              .load('packages/bootstrap_icons/fonts/BootstrapIcons.ttf')))
        .load();
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

  tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

  for (final (name, predictions) in [
    ('investing_trending', false),
    ('predictions_trending', true),
  ]) {
    for (final dark in [false, true]) {
      final shot = '${name}_${dark ? 'dark' : 'light'}';
      testWidgets(shot, (tester) async {
        tester.view.devicePixelRatio = _dpr;
        tester.view.physicalSize = _size * _dpr;
        addTearDown(tester.view.reset);
        final img = await _shoot(tester, dark, predictions: predictions);
        await _png(tester, img, shot);
        expect(tester.takeException(), isNull);
        // Back on Investing the 5-minute card counts itself off screen
        // while the scope is alive, so the unmount has nothing to count.
        if (predictions) {
          final l10n = AppLocalizations.of(
              tester.element(find.byType(KutePillTabs).first));
          await tester.tap(find.descendant(
              of: find.byType(KutePillTabs).first,
              matching: find.widgetWithText(KutePill, l10n.trading)));
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
      });
    }
  }
}
