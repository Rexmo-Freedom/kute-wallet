// The Predictions browse stays still while it updates (founder, 2
// November 2026, after the balance fix: "I just saw it jitter when it
// updated something. Happens I think every time it updates").
//
// The harness mounts the Investments page on Predictions over providers
// it can drive, scrolls into the list, then fires every live source in
// turn and all of them at once: the BTC 5m card's countdown, price, move
// against the target, odds, past rounds and the round rolling over; the
// market cards' and the strip's live chances; and the runtime policy's
// once-a-minute refresh. Every frame it records the scroll offset and the
// global top of the 5m card and of each market row on screen. Nothing may
// move.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
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
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/polymarket/crypto_live_odds.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/portfolio_overrides.dart';
import '../hyperliquid/hl_trending_strip_fixture.dart';
import 'investments_harness.dart'
    show
        InvestmentsTestPolicy,
        RecordingRefresh,
        RecordingRewardsApi,
        kEarnOff,
        kInvestmentsTestBalance;

class _NoStars extends HlWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _NoPolyStars extends PolyWatchlistNotifier {
  @override
  List<String> build() => const [];
}

/// The CLOB feed, driven by the test.
class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  void put(Map<String, double> prices) =>
      state = LivePriceState(prices: prices, live: true);
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void registerCardTokens(List<String> tokens) {}
  @override
  void unregisterCardTokens(List<String> tokens) {}
}

/// The 5m card's live Up chance, driven by the test.
class _Odds extends CryptoLiveOddsNotifier {
  @override
  Map<String, CryptoLiveOdds> build() => const {};
  void put(String token, double up) =>
      state = {token: CryptoLiveOdds(up, CryptoOddsSource.websocket)};
  @override
  void watch(String token) {}
  @override
  void unwatch(String token) {}
}

final _start = DateTime.utc(2026, 11, 2, 12, 0);

Btc5MinEvent _event(DateTime start, {double up = 0.62}) => Btc5MinEvent(
      slug: 'btc-updown-5m-${start.millisecondsSinceEpoch ~/ 1000}',
      title: 'Bitcoin Up or Down',
      windowStartTime: start,
      endDate: start.add(const Duration(minutes: 5)),
      upPrice: up,
      downPrice: 1 - up,
      upTokenId: 'up-${start.millisecondsSinceEpoch}',
      downTokenId: 'down-${start.millisecondsSinceEpoch}',
    );

List<BtcPriceSnapshot> _history(double base, int n) => [
      for (var i = 0; i < n; i++)
        BtcPriceSnapshot(
            timestamp: _start.add(Duration(seconds: i * 5)),
            price: base + (i % 7) * 6.0 - 12 + i),
    ];

final _round0 = CryptoPredictState(
  asset: 'BTC',
  currentPrice: 77777,
  priceToBeat: 77774,
  secondsRemaining: 154,
  priceHistory: _history(77770, 30),
  event: _event(_start),
);

/// The 5m round, driven by the test.
class _Round extends CryptoPredictNotifier {
  @override
  Future<CryptoPredictState> build(String arg) async => _round0;
  void put(CryptoPredictState s) => state = AsyncData(s);
}

/// The past rounds the card shows, per window, driven by the test.
final _pastRounds = StateProvider<List<CryptoWindowResult>>((_) => const [
      CryptoWindowResult(1, true),
      CryptoWindowResult(2, false),
      CryptoWindowResult(3, true),
      CryptoWindowResult(4, null),
    ]);

PolymarketEvent _market(int i, {double yes = 0.6}) => PolymarketEvent(
      id: 'm$i',
      slug: 'market-$i',
      title: 'Market number $i resolves Yes?',
      volume: 1e6 * (14 - i),
      volume24hr: 1e5 * (14 - i),
      liquidity: 1e5,
      category: 'politics',
      conditionId: 'm$i',
      endDate: DateTime(2026, 12, 31),
      oneDayPriceChange: i.isEven ? 0.04 : -0.02,
      outcomes: [
        PolymarketOutcome(name: 'Yes', price: yes, tokenId: 'y$i'),
        PolymarketOutcome(name: 'No', price: 1 - yes, tokenId: 'n$i'),
      ],
    );

/// An event with five outcomes: its card lists the three most likely,
/// re-ranked by the live chances.
final _election = PolymarketEvent(
  id: 'e1',
  slug: 'who-wins',
  title: 'Who wins the election?',
  volume: 3e6,
  liquidity: 1e5,
  category: 'politics',
  conditionId: 'e1',
  endDate: DateTime(2026, 12, 31),
  outcomes: [
    for (var k = 0; k < 5; k++)
      PolymarketOutcome(
          name: 'Candidate $k',
          price: 0.4 - k * 0.08,
          tokenId: 'c$k',
          noTokenId: 'cn$k',
          conditionId: 'cc$k'),
  ],
);

/// Fourteen plain markets (the strip takes the top ones, the rest list)
/// and the five-outcome event among them.
class _Feed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) => PolyFeedState(done: true, events: [
        for (var i = 0; i < 14; i++) ...[
          _market(i),
          if (i == 7) _election,
        ],
      ]);
}

/// Hyperliquid's mids socket, driven by the test.
class _HlPrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState();
  void put(Map<String, double> mids) => state = HlLivePriceState(mids: mids);
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

/// The Investing universe, re-read every 30 s in the app; the test swaps
/// it for one with the day's numbers moved.
final _universe = StateProvider<List<HlMarket>>((_) => hlTrendingFixture);

/// The policy service as the app wires it: the provider notifies its
/// dependents whenever the service does (the once-a-minute refresh).
class _LivePolicy extends InvestmentsTestPolicy {
  _LivePolicy()
      : super(kEarnOff, browsePredictions: true, browseInvesting: true);
  final _listeners = <VoidCallback>[];
  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);
  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
  void notify() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}

late _LivePolicy _policy;

Future<ProviderContainer> _pump(WidgetTester tester,
    {InvestmentsTab tab = InvestmentsTab.predictions}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  _policy = _LivePolicy();
  RuntimeCapabilitiesService.debugInstance = _policy;
  addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(dollars: 25),
      // The Activity pill (mounted under the venue pills) values Spark
      // receives at the bitcoin price: a price, without the rates' box.
      currentBtcUsdProvider.overrideWithValue(100000),
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
      runtimeCapabilitiesProvider.overrideWith((ref) {
        _policy.addListener(ref.notifyListeners);
        ref.onDispose(() => _policy.removeListener(ref.notifyListeners));
        return _policy;
      }),
      oneBalanceProvider.overrideWith((_) => kInvestmentsTestBalance),
      usdBalanceProvider.overrideWithValue(25),
      sparkIdentityPubkeyProvider.overrideWith((_) async => 'pub'),
      usdRewardsApiProvider.overrideWithValue(RecordingRewardsApi()),
      aiEnabledProvider.overrideWith((_) async => true),
      hyperliquidPerpMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      hyperliquidPerpCoreMarketsProvider
          .overrideWith((_) async => <HlMarket>[]),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      hlWatchlistProvider.overrideWith(_NoStars.new),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      polyWatchlistProvider.overrideWith(_NoPolyStars.new),
      polyBrowseFeedProvider.overrideWith(_Feed.new),
      cryptoPredictProvider.overrideWith(_Round.new),
      cryptoPredictWindowsProvider.overrideWith((_, __) async => [5]),
      cryptoRecentResultsProvider
          .overrideWith((ref, _) async => ref.watch(_pastRounds)),
      cryptoLiveOddsProvider.overrideWith(_Odds.new),
      livePriceProvider.overrideWith(_Prices.new),
      refreshEverythingProvider.overrideWith(RecordingRefresh.new),
      investmentsTabProvider.overrideWith((_) => tab),
      hyperliquidBrowseUniverseProvider
          .overrideWith((ref) => AsyncValue.data(ref.watch(_universe))),
      hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
      hyperliquidLivePricesProvider.overrideWith(_HlPrices.new),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'Inter',
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const UsdAccountScreen(),
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return ProviderScope.containerOf(
      tester.element(find.byType(UsdAccountScreen)));
}

final _card = find.byKey(const ValueKey('crypto-round-compact'));

/// Everything that must stay put: the 5m card's top and height, every
/// market row's top, the outer and inner scroll offsets.
Map<String, double> _layout(WidgetTester tester) {
  final out = <String, double>{};
  if (_card.evaluate().isNotEmpty) {
    out['5m card top'] = tester.getTopLeft(_card).dy;
    out['5m card height'] = tester.getSize(_card).height;
  }
  final strip = find.byType(HlMovingNowStrip);
  if (strip.evaluate().isNotEmpty) {
    out['squares top'] = tester.getTopLeft(strip).dy;
    out['squares height'] = tester.getSize(strip).height;
  }
  // The market map, Investing's second item (under the squares, over the
  // rows, founder 7 November 2026).
  final map = find.byKey(const ValueKey('hl-market-map'));
  if (map.evaluate().isNotEmpty) {
    out['map top'] = tester.getTopLeft(map).dy;
    out['map height'] = tester.getSize(map).height;
  }
  // Investing's rows by slot, not by market: the 30 s re-read may
  // re-rank them (the list is by volume), which swaps what a slot shows
  // but must never move the slots.
  final hl = [
    for (final e in find.byType(HlMarketCard).evaluate())
      if ((e.renderObject! as RenderBox).hasSize) e.renderObject! as RenderBox,
  ]..sort((a, b) => a
      .localToGlobal(Offset.zero)
      .dy
      .compareTo(b.localToGlobal(Offset.zero).dy));
  for (final (i, box) in hl.indexed) {
    out['hl slot $i'] = box.localToGlobal(Offset.zero).dy;
    out['hl slot $i height'] = box.size.height;
  }
  for (final e in find.byType(MarketCard).evaluate()) {
    final w = e.widget as MarketCard;
    final box = e.renderObject! as RenderBox;
    if (!box.hasSize) continue;
    out['row "${w.title}"'] = box.localToGlobal(Offset.zero).dy;
    out['row "${w.title}" height'] = box.size.height;
  }
  for (final s in find.byType(Scrollable).evaluate()) {
    final state = (s as StatefulElement).state as ScrollableState;
    if (state.widget.axis != Axis.vertical) continue;
    final p = state.position;
    if (!p.hasPixels) continue;
    out['scroll ${s.depth}'] = p.pixels;
  }
  return out;
}

/// Runs [update] then pumps [frames] frames, failing on the first frame
/// where anything moved, naming what moved and by how much.
Future<void> _still(WidgetTester tester, String source,
    FutureOr<void> Function() update,
    {int frames = 8}) async {
  final before = _layout(tester);
  await update();
  for (var f = 0; f < frames; f++) {
    await tester.pump(const Duration(milliseconds: 16));
    final now = _layout(tester);
    final moved = <String>[
      for (final k in before.keys)
        if (now.containsKey(k) && (now[k]! - before[k]!).abs() > 0.01)
          '$k ${(now[k]! - before[k]!).toStringAsFixed(2)} px',
    ];
    expect(moved, isEmpty, reason: '$source, frame $f: ${moved.join(', ')}');
  }
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final scrolled in [false, true]) {
    testWidgets(
        '${scrolled ? 'scrolled into the list' : 'at the top'}: every live '
        'update leaves the 5m card and the rows where they are',
        (tester) async {
      final container = await _pump(tester);
      if (scrolled) {
        await tester.drag(
            find.byType(NestedScrollView), const Offset(0, -420));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      expect(find.byType(MarketCard), findsWidgets);
      final round =
          container.read(cryptoPredictProvider('BTC').notifier) as _Round;
      final odds = container.read(cryptoLiveOddsProvider.notifier) as _Odds;
      final prices = container.read(livePriceProvider.notifier) as _Prices;
      var s = _round0;
      void put(CryptoPredictState next) => round.put(s = next);

      // The countdown, once a second, through the minute boundaries.
      for (final left in [153, 100, 60, 59, 10, 9, 1, 0]) {
        await _still(tester, 'countdown $left',
            () => put(s.copyWith(secondsRemaining: left)));
      }
      // The live price and its move against the target, every width.
      for (final (price, target) in [
        (77777.0, 77774.0),
        (77774.004, 77774.0),
        (77700.0, 77774.0),
        (101234.0, 77774.0),
        (9999.0, 77774.0),
        (77774.0, 77774.0),
      ]) {
        await _still(
            tester,
            'price $price vs $target',
            () => put(s.copyWith(
                currentPrice: price,
                priceToBeat: target,
                priceHistory: [
                  ...s.priceHistory,
                  BtcPriceSnapshot(
                      timestamp: s.priceHistory.last.timestamp
                          .add(const Duration(seconds: 1)),
                      price: price),
                ])));
      }
      // The odds, from the book.
      for (final up in [0.5, 0.185, 0.08, 0.005, 0.999, 0.62]) {
        await _still(tester, 'odds $up',
            () => odds.put(s.event!.upTokenId!, up));
      }
      // The past rounds: one settles, none known, all known.
      for (final rounds in [
        const [
          CryptoWindowResult(1, true),
          CryptoWindowResult(2, false),
          CryptoWindowResult(3, true),
          CryptoWindowResult(4, false),
        ],
        const <CryptoWindowResult>[],
        const [CryptoWindowResult(1, null)],
      ]) {
        await _still(tester, 'past rounds ${rounds.length}',
            () => container.read(_pastRounds.notifier).state = rounds);
      }
      // The round rolls over: a new event, no target yet, then the target.
      final next = _start.add(const Duration(minutes: 5));
      await _still(
          tester,
          'rollover',
          () => put(CryptoPredictState(
                asset: 'BTC',
                currentPrice: s.currentPrice,
                priceToBeat: null,
                secondsRemaining: 300,
                priceHistory: s.priceHistory,
                event: _event(next, up: 0.5),
              )),
          frames: 20);
      await _still(tester, 'new target',
          () => put(s.copyWith(priceToBeat: 77790.5)), frames: 20);
      // The market cards' and the strip's chances, from the CLOB feed.
      for (final yes in [0.6, 0.005, 0.999, 0.5, 0.185]) {
        await _still(
            tester,
            'chances $yes',
            () => prices.put({
                  for (var i = 0; i < 14; i++) ...{
                    'y$i': yes,
                    'n$i': 1 - yes,
                  },
                  // The election's leaders trade places.
                  for (var k = 0; k < 5; k++)
                    'c$k': ((k * 7 + (yes * 100).round()) % 5) * 0.2 + 0.001,
                }),
            frames: 12);
      }
      // The policy's once-a-minute refresh, nothing in it changed.
      await _still(tester, 'policy refresh', _policy.notify, frames: 12);
      // All of it at once, a few seconds of it.
      await _still(tester, 'burst', () async {
        for (var t = 0; t < 6; t++) {
          put(s.copyWith(
              secondsRemaining: 299 - t,
              currentPrice: 77790.5 + (t.isEven ? 1234.5 : -0.4),
              priceHistory: [
                ...s.priceHistory,
                BtcPriceSnapshot(
                    timestamp: s.priceHistory.last.timestamp
                        .add(const Duration(seconds: 1)),
                    price: 77790.5 + t),
              ]));
          odds.put(s.event!.upTokenId!, t.isEven ? 0.07 : 0.93);
          prices.put({
            for (var i = 0; i < 14; i++) ...{
              'y$i': t.isEven ? 0.003 : 0.997,
              'n$i': t.isEven ? 0.997 : 0.003,
            }
          });
          _policy.notify();
          await tester.pump(const Duration(milliseconds: 16));
        }
      }, frames: 30);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    });
  }

  for (final scrolled in [false, true]) {
    testWidgets(
        'Investing, ${scrolled ? 'scrolled into the list' : 'at the top'}: '
        'live mids, the 30 s re-read and the policy refresh move nothing',
        (tester) async {
      final container = await _pump(tester, tab: InvestmentsTab.investing);
      if (scrolled) {
        await tester.drag(
            find.byType(NestedScrollView), const Offset(0, -420));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      // At the top the squares and the market map (the tab's second
      // item) fill the screen; scrolled into the list, the rows.
      if (scrolled) {
        expect(find.byType(HlMarketCard), findsWidgets);
      } else {
        expect(find.byType(HlMovingNowStrip), findsOneWidget);
        expect(find.byKey(const ValueKey('hl-market-map')), findsOneWidget);
      }
      final mids = container.read(hyperliquidLivePricesProvider.notifier)
          as _HlPrices;
      final coins = [for (final m in hlTrendingFixture) m.coin];

      // Mids from the socket, every width a price can take.
      for (final px in [100.0, 0.000123, 123456.78, 99.99, 1.0, 100000.0]) {
        await _still(tester, 'mids $px',
            () => mids.put({for (final c in coins) c: px}),
            frames: 12);
      }
      // The 30 s re-read: volumes, previous-day prices and liquidity
      // moved (a thin market thickens, a busy one thins).
      for (final k in [1, 2, 3]) {
        await _still(
            tester,
            're-read $k',
            () => container.read(_universe.notifier).state = [
                  for (final (i, m) in hlTrendingFixture.indexed)
                    HlMarket(
                      coin: m.coin,
                      wireCoin: m.wireCoin,
                      assetId: m.assetId,
                      kind: m.kind,
                      szDecimals: m.szDecimals,
                      maxLeverage: m.maxLeverage,
                      onlyIsolated: m.onlyIsolated,
                      markPx: m.markPx * (1 + k / 100),
                      midPx: m.midPx * (1 + k / 100),
                      prevDayPx: (i + k).isEven ? m.prevDayPx : 0,
                      dayNtlVlm: (i + k) % 3 == 0 ? 10 : m.dayNtlVlm,
                      category: m.category,
                      dex: m.dex,
                      isHip3: m.isHip3,
                      annotatedName: m.annotatedName,
                      unitAssetName: m.unitAssetName,
                    ),
                ],
            frames: 12);
      }
      await _still(tester, 'policy refresh', _policy.notify, frames: 12);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    });
  }
}
