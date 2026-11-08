// Predictions › Instant (founder, 8 November 2026) on the real Investments
// page, offline: Trending and Instant side by side on the sheet, the
// Instant card's line, the tap that picks the Instant pill page on the
// Dollars home (nothing pushed; "Predictions · Instant" on the pill), the
// filter and its memory, one card with one pair of buttons, the coins per
// length, own rounds, the cost (one round live; all gone behind another
// category, behind another Dollars pill and behind another tab), the gate.
// The helpers at the top are also the render harness's
// (test/audit/instant_render_test.dart); the card's own rules are
// test/screens/polymarket/instant_round_card_test.dart.


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/crypto_live_odds_provider.dart';
import 'package:kute/providers/crypto_next_round_provider.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_instant_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/polymarket/components/instant_pill_page.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show PolyPositionRow;
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/screens/shared/investment_balance_header.dart'
    show InvestmentDiscoveryNotice;
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/polymarket/crypto_live_odds.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart';
import 'package:kute/services/polymarket/instant_rounds.dart';
import 'package:kute/services/tracking_service.dart';

import '../usd/investments_harness.dart';

/// What the page has asked for, for the cost tests, and what the world
/// holds.
class InstantWorld {
  /// The clock the card reads.
  DateTime now = DateTime.now();

  /// The round notifiers alive right now, and every one ever built.
  final Set<CryptoRoundKey> liveRounds = {};
  final Set<CryptoRoundKey> builtRounds = {};

  /// Tokens registered on the market socket right now, with their count.
  final Map<String, int> socketTokens = {};

  /// Gamma's rounds ahead, by start (UTC seconds).
  final Map<int, Btc5MinEvent> ahead = {};

  /// The feed's rows per list.
  Map<PolyFeedQuery, List<PolymarketEvent>> feeds = {};
  Set<PolyFeedQuery> loading = {};
  List<PolymarketPosition> positions = const [];

  /// The last four rounds' results; null draws none.
  List<CryptoWindowResult>? Function(CryptoResultsKey key) results =
      (key) => [
            CryptoWindowResult(key.currentStart - 4 * key.minutes * 60, true),
            CryptoWindowResult(key.currentStart - 3 * key.minutes * 60, false),
            CryptoWindowResult(key.currentStart - 2 * key.minutes * 60, true),
            CryptoWindowResult(key.currentStart - key.minutes * 60, true),
          ];

  /// The Crypto row's chips.
  List<PolySub> cryptoSubs = const [
    PolySub('all', count: 48),
    PolySub('5m', count: 6),
    PolySub('15m', count: 6),
    PolySub('1h', count: 6),
    PolySub('4h', count: 6),
    PolySub('daily', count: 12),
  ];
  PolyInstantChoice choice = kPolyInstantDefault;

  /// Gamma has no event for the round in play (or only the one that ended).
  bool eventless = false;

  /// Whether the Dollars home can be seen: the shell's other tabs hide it
  /// with its tickers off ([_pumpPage] wraps the page in it).
  final ValueNotifier<bool> shown = ValueNotifier(true);

  int liveStart(int minutes) => polyRoundStartAt(now, minutes);
}

/// Gamma's event of the [minutes] round of [asset] starting at [start].
Btc5MinEvent roundEvent(String asset, int minutes, int start,
        {String? tokens, double up = 0.62}) =>
    Btc5MinEvent(
      slug: polyCryptoRoundSlug(asset, minutes, start),
      title: '$asset Up or Down',
      windowStartTime:
          DateTime.fromMillisecondsSinceEpoch(start * 1000, isUtc: true),
      endDate: DateTime.fromMillisecondsSinceEpoch(
          (start + minutes * 60) * 1000,
          isUtc: true),
      upPrice: up,
      downPrice: 1 - up,
      upTokenId: '${tokens ?? '$asset-$start'}-up',
      downTokenId: '${tokens ?? '$asset-$start'}-down',
      conditionId: '$asset-$start-cond',
    );

/// A round in play of [arg], its price a little above the strike, on the
/// world's clock.
class InstantRound extends CryptoRoundNotifier {
  InstantRound(this.world);
  final InstantWorld world;

  @override
  Future<CryptoPredictState> build(CryptoRoundKey arg) async {
    world.liveRounds.add(arg);
    world.builtRounds.add(arg);
    ref.onDispose(() => world.liveRounds.remove(arg));
    final startS = world.liveStart(arg.minutes);
    final start =
        DateTime.fromMillisecondsSinceEpoch(startS * 1000, isUtc: true);
    final base = switch (arg.asset) {
      'BTC' => 76000.0,
      'ETH' => 3120.0,
      'SOL' => 171.0,
      'XRP' => 2.31,
      'DOGE' => 0.0712,
      'BNB' => 612.0,
      _ => 77.4,
    };
    var px = base;
    final elapsed = world.now.difference(start).inSeconds;
    final step = arg.minutes <= 15 ? 1 : 60;
    return CryptoPredictState(
      asset: arg.asset,
      currentPrice: base * 1.0009,
      priceToBeat: base,
      secondsRemaining: world.eventless ? 0 : arg.minutes * 60 - elapsed,
      event: world.eventless
          ? null
          : roundEvent(arg.asset, arg.minutes, startS, tokens: arg.asset),
      priceHistory: [
        for (var t = -60; t <= elapsed; t += step)
          BtcPriceSnapshot(
            timestamp: start.add(Duration(seconds: t)),
            price: px += ((t * 37) % 11 - 4.6) * base * 0.00002,
          ),
      ],
    );
  }
}

class InstantPrices extends LivePriceNotifier {
  InstantPrices(this.world);
  final InstantWorld world;

  @override
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void registerCardTokens(List<String> tokens) {
    for (final t in tokens) {
      world.socketTokens[t] = (world.socketTokens[t] ?? 0) + 1;
    }
  }

  @override
  void unregisterCardTokens(List<String> tokens) {
    for (final t in tokens) {
      final n = (world.socketTokens[t] ?? 0) - 1;
      if (n <= 0) {
        world.socketTokens.remove(t);
      } else {
        world.socketTokens[t] = n;
      }
    }
  }

  @override
  void unsubscribeAll() {}
}

class InstantOdds extends CryptoLiveOddsNotifier {
  @override
  Map<String, CryptoLiveOdds> build() => const {};
  @override
  void watch(String token) {}
  @override
  void unwatch(String token) {}
}

class _Feed extends PolyFeedNotifier {
  _Feed(this.world);
  final InstantWorld world;

  @override
  PolyFeedState build(PolyFeedQuery arg) => PolyFeedState(
      done: true,
      loading: world.loading.contains(arg),
      events: world.feeds[arg] ?? const []);
}

class _Choice extends PolyInstantChoiceNotifier {
  _Choice(this.world);
  final InstantWorld world;

  @override
  PolyInstantChoice build() => world.choice;
  @override
  void pick(PolyInstantChoice next) => state = next;
}

class _NoPlacing extends PlacingPolymarketBetNotifier {
  @override
  List<PlacingBet> build() => const [];
}

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

/// The Instant card offline, on [world]: its round, the rounds ahead, the
/// results, the odds and the market socket. Other harnesses add these to
/// their own overrides when a test reaches the Instant page.
List<Override> instantCardOverrides(InstantWorld world) => [
      cryptoRoundProvider.overrideWith(() => InstantRound(world)),
      cryptoRecentResultsProvider
          .overrideWith((_, key) async => world.results(key) ?? const []),
      cryptoNextRoundProvider
          .overrideWith((_, key) async => world.ahead[key.start]),
      cryptoOddsClockProvider.overrideWithValue(() => world.now),
      cryptoLiveOddsProvider.overrideWith(InstantOdds.new),
      livePriceProvider.overrideWith(() => InstantPrices(world)),
    ];

/// The Predictions page and the Instant page offline, on [world].
List<Override> instantOverrides(InstantWorld world,
        {PolyBrowseSelection? selection}) =>
    [
      polyBrowseSelectionProvider
          .overrideWith((_) => selection ?? const PolyBrowseSelection()),
      polyBrowseFeedProvider.overrideWith(() => _Feed(world)),
      ...instantCardOverrides(world),
      cryptoPredictWindowsProvider.overrideWith((_, __) async => [5]),
      polyInstantChoiceProvider.overrideWith(() => _Choice(world)),
      polyCryptoSubsProvider
          .overrideWith((_) => Stream.value(world.cryptoSubs)),
      polyTopicSubsProvider
          .overrideWith((_, __) => Stream.value(const <PolySub>[])),
      sportsLiveProvider.overrideWith(_Sports.new),
      polymarketActivePositionsProvider.overrideWithValue(world.positions),
      placingPolymarketBetProvider.overrideWith(_NoPlacing.new),
      polyPositionEventProvider.overrideWith((_, __) => null),
    ];

/// The round of each of [assets] in play now at [minutes], with one ahead
/// of it, as the Crypto list of that length lists them.
List<PolymarketEvent> feedRounds(List<String> assets, int minutes,
    {DateTime? now}) {
  final start = polyRoundStartAt(now ?? DateTime.now(), minutes);
  final span = minutes * 60;
  PolymarketEvent row(String asset, int at) {
    final name = {
      'btc': 'Bitcoin',
      'eth': 'Ethereum',
      'sol': 'Solana',
      'xrp': 'XRP',
      'doge': 'Dogecoin',
      'bnb': 'BNB',
      'hype': 'HYPE',
      'zec': 'Zcash',
    }[asset]!;
    return PolymarketEvent(
      id: '$asset-$at',
      slug: polyCryptoRoundSlug(asset, minutes, at),
      title: '$name Up or Down - November 8, 7:00AM-7:15AM ET',
      volume: 50000,
      volume24hr: 40000,
      liquidity: 10000,
      category: 'crypto',
      conditionId: '$asset-$at',
      imageUrl: 'https://polymarket-upload.example/$asset.png',
      endDate: DateTime.fromMillisecondsSinceEpoch((at + span) * 1000,
          isUtc: true),
      outcomes: [
        PolymarketOutcome(name: 'Up', price: 0.53, tokenId: '$asset-$at-up'),
        PolymarketOutcome(name: 'Down', price: 0.47, tokenId: '$asset-$at-dn'),
      ],
    );
  }

  return [
    for (final a in assets) ...[row(a, start), row(a, start + span)],
  ];
}

Finder instantCard(String asset, [String length = '5m']) =>
    find.byKey(ValueKey('instant-card-$asset-$length'));

const instantTile = ValueKey('category-tile-instant');

const List<String> kSevenAssets = [
  'BTC',
  'ETH',
  'SOL',
  'XRP',
  'DOGE',
  'BNB',
  'HYPE'
];

/// A BTC round held by the person: the one in play.
PolymarketPosition heldRound({DateTime? now}) {
  final start = polyRoundStartAt(now ?? DateTime.now(), 5);
  return PolymarketPosition(
    marketId: 'held',
    marketQuestion: 'Bitcoin Up or Down - November 8, 7:00AM-7:05AM ET',
    outcome: 'Up',
    size: 12,
    avgPrice: 0.5,
    currentPrice: 0.62,
    pnl: 1.44,
    pnlPercent: 24,
    isResolved: false,
    tokenId: 'held-up',
    eventSlug: 'btc-updown-5m-$start',
  );
}

/// The Dollars home under the shell's Material, as on a phone, with its
/// tickers following [InstantWorld.shown] as the shell's hidden tabs do
/// (`Offstage` + `TickerMode`).
Future<void> _pumpPage(WidgetTester tester, InstantWorld world,
    {Size size = const Size(390, 844),
    bool browse = true,
    PolyBrowseSelection selection = const PolyBrowseSelection(),
    bool dark = false,
    Locale? locale}) async {
  await pumpInvestments(tester,
      size: size,
      dark: dark,
      locale: locale,
      browsePredictions: browse,
      browseInvesting: browse,
      child: ValueListenableBuilder<bool>(
        valueListenable: world.shown,
        builder: (_, shown, child) =>
            TickerMode(enabled: shown, child: child!),
        child: const Scaffold(body: UsdAccountScreen()),
      ),
      overrides: instantOverrides(world, selection: selection));
}

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(KutePillTabs).first));

/// The Investments page on Predictions, its sheet open.
Future<void> pumpPredictionsSheet(WidgetTester tester, InstantWorld world,
    {Size size = const Size(390, 844),
    bool browse = true,
    PolyBrowseSelection selection = const PolyBrowseSelection(),
    bool dark = false,
    Locale? locale}) async {
  await _pumpPage(tester, world,
      size: size,
      browse: browse,
      selection: selection,
      dark: dark,
      locale: locale);
  final l10n = _l10n(tester);
  // The pill once (Predictions), then again: its categories.
  for (var i = 0; i < 2; i++) {
    await tapAndPump(tester, investmentsPill(l10n.predictions));
    await _settle(tester);
  }
}

/// The Instant page, picked from the sheet's card as the person does it.
Future<void> pumpInstant(WidgetTester tester, InstantWorld world,
    {Size size = const Size(390, 844),
    bool dark = false,
    Locale? locale}) async {
  await pumpPredictionsSheet(tester, world,
      size: size, dark: dark, locale: locale);
  await tester.tap(find.byKey(instantTile));
  await _settle(tester, 14);
  expect(find.byType(PolyInstantPage), findsOneWidget);
}

/// The Dollars home opened on Predictions › Instant (the remembered pick),
/// browsing allowed or not.
Future<void> pumpInstantPage(WidgetTester tester, InstantWorld world,
    {Size size = const Size(390, 844),
    bool browse = true,
    bool dark = false,
    Locale? locale}) async {
  await _pumpPage(tester, world,
      size: size,
      browse: browse,
      dark: dark,
      locale: locale,
      selection: const PolyBrowseSelection(pill: PolyPill.instant));
  await tapAndPump(tester, investmentsPill(_l10n(tester).predictions));
  await _settle(tester);
}

Finder tile(PolyPill p) => find.byKey(ValueKey('category-tile-${p.key}'));

void main() {
  late List<(String, Map<String, Object>?)> events;
  setUp(() {
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() => TrackingService.debugTrackObserver = null);

  group('the sheet', () {
    testWidgets(
        'Trending and Instant side by side, equal, above Topics; '
        'Instant says the lengths and nothing else', (tester) async {
      await pumpPredictionsSheet(tester, InstantWorld());
      final trending = tile(PolyPill.trending);
      final instant = find.byKey(instantTile);
      expect(trending, findsOneWidget);
      expect(instant, findsOneWidget,
          reason: 'one of the two cards, never a topic tile too');
      final a = tester.getRect(trending);
      final b = tester.getRect(instant);
      expect(a.top, b.top);
      expect(a.size, b.size, reason: 'two equal cards');
      expect(a.right, lessThan(b.left), reason: 'Trending, then Instant');
      final l10n = AppLocalizations.of(tester.element(trending));
      final topics = tester.getTopLeft(find.text(l10n.categoryGroupTopics));
      expect(a.bottom, lessThan(topics.dy));
      expect(tester.getTopLeft(tile(PolyPill.breaking)).dy,
          greaterThan(topics.dy));
      expect(find.text(l10n.predictionsInstant), findsOneWidget);
      expect(find.text(l10n.categoryInstantLengths), findsOneWidget);
      // No coin names, no clock (founder: "just the 5 min and such").
      expect(find.textContaining('BTC, ETH'), findsNothing);
      expect(find.byKey(const ValueKey('category-instant-next')), findsNothing);
      expect(find.textContaining('Next round'), findsNothing);
      await unmountInvestments(tester);
    });

    testWidgets(
        'a tap on Instant closes the sheet and picks the pill page; nothing '
        'is pushed; the Dollars pill reads Predictions · Instant',
        (tester) async {
      await pumpPredictionsSheet(tester, InstantWorld());
      final container = ProviderScope.containerOf(
          tester.element(find.byType(UsdAccountScreen)));
      final l10n = _l10n(tester);
      await tester.tap(find.byKey(instantTile));
      await _settle(tester, 14);
      expect(find.byKey(instantTile), findsNothing, reason: 'the sheet closed');
      expect(find.byType(PolyInstantPage), findsOneWidget);
      expect(find.byType(UsdAccountScreen), findsOneWidget,
          reason: 'still the Dollars home');
      expect(find.byType(KuteBackButton), findsNothing,
          reason: 'no screen pushed');
      expect(
          Navigator.of(tester.element(find.byType(UsdAccountScreen)),
                  rootNavigator: true)
              .canPop(),
          isFalse);
      expect(container.read(polyBrowseSelectionProvider).pill,
          PolyPill.instant);
      // Its item says so; whether a phone's row holds it is the fit test's
      // (investments_pill_fit_test.dart) and the renders', the test font
      // being far wider than Inter.
      final item = tester
          .widget<KutePillTabs>(find.byType(KutePillTabs).first)
          .items
          .firstWhere((i) => i.label == l10n.predictions);
      expect(item.detail, l10n.predictionsInstant,
          reason: 'drawn after the name as "Predictions · Instant"');
      expect(events.where((e) => e.$1 == 'category_pill_tapped').single.$2,
          {'section': 'instant'});
      expect(
          events.where((e) => e.$1 == 'predictions_instant_opened').single.$2,
          {'source': 'sheet'});
      await unmountInvestments(tester);
    });
  });

  testWidgets('the 5-minute card has left Trending', (tester) async {
    final world = InstantWorld();
    await _pumpPage(tester, world);
    final l10n = _l10n(tester);
    await tapAndPump(tester, investmentsPill(l10n.predictions));
    await _settle(tester);
    expect(find.byType(CryptoPredictBanner), findsNothing);
    expect(world.builtRounds, isEmpty, reason: 'no round read for Trending');
    expect(events.any((e) => e.$1 == 'predict_hero_viewed'), isFalse);
    await unmountInvestments(tester);
  });

  group('the page', () {
    testWidgets(
        'one card, one pair of buttons; Bitcoin five minutes first; '
        'a pick switches the card', (tester) async {
      final world = InstantWorld();
      await pumpInstant(tester, world);
      expect(instantCard('BTC'), findsOneWidget);
      expect(find.byKey(const ValueKey('crypto-round-up')), findsOneWidget,
          reason: 'one Up on the whole page');
      expect(find.byKey(const ValueKey('crypto-round-down')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('instant-round-strip')), findsOneWidget);
      expect(world.liveRounds, {(asset: 'BTC', minutes: 5)});
      // Every coin on offer at five minutes.
      for (final a in kSevenAssets) {
        expect(find.byKey(ValueKey('instant-asset-$a')), findsOneWidget);
      }
      await tapAndPump(
          tester, find.byKey(const ValueKey('instant-asset-SOL')));
      await _settle(tester);
      expect(instantCard('SOL'), findsOneWidget);
      expect(instantCard('BTC'), findsNothing);
      expect(find.byKey(const ValueKey('crypto-round-up')), findsOneWidget);
      expect(world.liveRounds, {(asset: 'SOL', minutes: 5)},
          reason: 'the Bitcoin card is gone, with its reads');
      final filter = events
          .lastWhere((e) => e.$1 == 'predictions_instant_filter_changed');
      expect(filter.$2, {'asset': 'SOL', 'length': '5m', 'changed': 'asset'});
      await unmountInvestments(tester);
    });

    testWidgets('a length: the venue\'s coins at it, the card at that length',
        (tester) async {
      final world = InstantWorld()
        ..feeds = {
          const PolyFeedQuery(pill: PolyPill.crypto, sub: '15m'):
              feedRounds(['eth', 'btc', 'sol', 'xrp'], 15),
        };
      await pumpInstant(tester, world);
      await tapAndPump(
          tester, find.byKey(const ValueKey('instant-length-15m')));
      await _settle(tester);
      expect(instantCard('BTC', '15m'), findsOneWidget);
      expect(instantCard('BTC'), findsNothing);
      expect(find.text('BTC up or down · 15m'), findsOneWidget);
      expect(world.liveRounds, {(asset: 'BTC', minutes: 15)});
      final filter = events
          .lastWhere((e) => e.$1 == 'predictions_instant_filter_changed');
      expect(
          filter.$2, {'asset': 'BTC', 'length': '15m', 'changed': 'length'});
      // The coins the venue runs at this length.
      expect(find.byKey(const ValueKey('instant-asset-XRP')), findsOneWidget);
      expect(find.byKey(const ValueKey('instant-asset-HYPE')), findsNothing);
      await unmountInvestments(tester);
    });

    testWidgets('a coin the app has no card for gets no chip', (tester) async {
      final world = InstantWorld()
        ..choice = const PolyInstantChoice(asset: 'BTC', length: '15m')
        ..feeds = {
          const PolyFeedQuery(pill: PolyPill.crypto, sub: '15m'):
              feedRounds(['btc', 'zec', 'eth'], 15),
        };
      await pumpInstant(tester, world);
      expect(find.byKey(const ValueKey('instant-asset-ETH')), findsOneWidget);
      expect(find.byKey(const ValueKey('instant-asset-ZEC')), findsNothing);
      await unmountInvestments(tester);
    });

    testWidgets('no event on the page: no 0:00:00, no 50%, one pair of buttons',
        (tester) async {
      final world = InstantWorld()
        ..eventless = true
        ..choice = const PolyInstantChoice(asset: 'BTC', length: '4h');
      await pumpInstant(tester, world);
      expect(instantCard('BTC', '4h'), findsOneWidget);
      expect(find.textContaining('0:00:00', findRichText: true), findsNothing);
      expect(find.textContaining('50%', findRichText: true), findsNothing);
      expect(find.byKey(const ValueKey('crypto-round-countdown-skeleton')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('crypto-round-up')), findsOneWidget);
      await unmountInvestments(tester);
    });

    testWidgets('a coin the venue does not run at a length says so',
        (tester) async {
      final world = InstantWorld()
        ..choice = const PolyInstantChoice(asset: 'BTC', length: '4h')
        ..feeds = {
          const PolyFeedQuery(pill: PolyPill.crypto, sub: '4h'):
              feedRounds(['eth', 'sol'], 240),
        };
      await pumpInstant(tester, world);
      expect(find.byKey(const ValueKey('instant-no-round')), findsOneWidget);
      expect(find.byKey(const ValueKey('crypto-round-up')), findsNothing);
      // Bitcoin stays on the row, so the person can pick a coin that runs.
      expect(find.byKey(const ValueKey('instant-asset-BTC')), findsOneWidget);
      expect(find.byKey(const ValueKey('instant-asset-ETH')), findsOneWidget);
      await unmountInvestments(tester);
    });

    testWidgets('a remembered length the venue dropped reads five minutes',
        (tester) async {
      final world = InstantWorld()
        ..choice = const PolyInstantChoice(asset: 'ETH', length: '1h')
        ..cryptoSubs = const [PolySub('all'), PolySub('5m'), PolySub('15m')];
      await pumpInstant(tester, world);
      expect(instantCard('ETH'), findsOneWidget);
      expect(find.byKey(const ValueKey('instant-length-1h')), findsNothing);
      await unmountInvestments(tester);
    });

    testWidgets('the four-hour card names the New York clock\'s round',
        (tester) async {
      final world = InstantWorld()
        ..choice = const PolyInstantChoice(asset: 'BTC', length: '4h');
      await pumpInstant(tester, world);
      expect(instantCard('BTC', '4h'), findsOneWidget);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(UsdAccountScreen)));
      final slug = container
          .read(cryptoRoundProvider((asset: 'BTC', minutes: 240)))
          .requireValue
          .event!
          .slug;
      // Four hours on the New York clock: 05, 09, 13, 17, 21, 01 UTC under
      // standard time (the rounds Gamma lists), never the UTC multiples.
      final start = polyCryptoRoundOf(slug)!.start;
      final et = start.add(Duration(hours: polyEasternOffsetHours(start)));
      expect(et.hour % 4, 0, reason: slug);
      expect(et.minute, 0);
      await unmountInvestments(tester);
    });
  });

  group('the memory', () {
    test('the last pick does not come back', () {
      var c = ProviderContainer();
      const pick = PolyInstantChoice(asset: 'SOL', length: '15m');
      c.read(polyInstantChoiceProvider.notifier).pick(pick);
      expect(c.read(polyInstantChoiceProvider), pick);
      c.read(polyInstantChoiceProvider.notifier).reset();
      expect(c.read(polyInstantChoiceProvider), kPolyInstantDefault);
      c.read(polyInstantChoiceProvider.notifier).pick(pick);
      c.dispose();
      c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(polyInstantChoiceProvider), kPolyInstantDefault);
    });

    test('a pick on the strip is per coin and length', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const a = PolyInstantChoice(asset: 'BTC', length: '5m');
      const b = PolyInstantChoice(asset: 'BTC', length: '15m');
      final sub = c.listen(polyInstantPickedRoundProvider(a), (_, __) {});
      c.read(polyInstantPickedRoundProvider(a).notifier).state = 1794153900;
      expect(c.read(polyInstantPickedRoundProvider(a)), 1794153900);
      expect(c.read(polyInstantPickedRoundProvider(b)), isNull);
      sub.close();
    });
  });

  group('the cost', () {
    testWidgets(
        'one round live for the card; another category stops it all',
        (tester) async {
      final world = InstantWorld();
      await pumpInstant(tester, world);
      expect(world.liveRounds, {(asset: 'BTC', minutes: 5)});
      expect(world.socketTokens.keys.toSet(), {'BTC-up', 'BTC-down'},
          reason: 'the round on show; nothing ahead is listed');
      final container = ProviderScope.containerOf(
          tester.element(find.byType(PolymarketScreen)));
      container.read(polyBrowseSelectionProvider.notifier).state =
          const PolyBrowseSelection();
      await _settle(tester, 12);
      expect(find.byType(PolyInstantPage), findsNothing);
      expect(world.liveRounds, isEmpty,
          reason: 'the read and its timers stop');
      expect(world.socketTokens, isEmpty,
          reason: 'its tokens leave the socket');
      await unmountInvestments(tester);
    });

    testWidgets('the rounds ahead that Gamma lists ride the socket too',
        (tester) async {
      final world = InstantWorld();
      final next = world.liveStart(5) + 300;
      world.ahead[next] = roundEvent('BTC', 5, next, tokens: 'next');
      await pumpInstant(tester, world);
      expect(world.socketTokens.keys.toSet(),
          {'BTC-up', 'BTC-down', 'next-up', 'next-down'});
      expect(world.liveRounds.length, 1);
      await unmountInvestments(tester);
    });

    testWidgets(
        'on another Dollars pill the card goes and its reads stop; back, '
        'Predictions opens on Trending, not Instant', (tester) async {
      final world = InstantWorld();
      await pumpInstant(tester, world);
      expect(world.liveRounds, {(asset: 'BTC', minutes: 5)});
      final l10n = _l10n(tester);
      await tapAndPump(tester, investmentsPill(l10n.trading));
      await _settle(tester, 8);
      expect(world.liveRounds, isEmpty, reason: 'no read behind the pill');
      expect(world.socketTokens, isEmpty, reason: 'no seat on the socket');
      expect(find.byKey(const ValueKey('instant-card-BTC-5m'),
              skipOffstage: false),
          findsNothing);
      await tapAndPump(tester, investmentsPill(l10n.predictions));
      await _settle(tester, 8);
      expect(find.byType(PolyInstantPage), findsNothing);
      expect(world.liveRounds, isEmpty);
      await unmountInvestments(tester);
    });

    testWidgets(
        'behind another tab of the shell the same: nothing runs hidden',
        (tester) async {
      final world = InstantWorld();
      await pumpInstant(tester, world);
      expect(world.liveRounds, {(asset: 'BTC', minutes: 5)});
      world.shown.value = false;
      await _settle(tester, 8);
      expect(world.liveRounds, isEmpty);
      expect(world.socketTokens, isEmpty);
      world.shown.value = true;
      await _settle(tester, 8);
      expect(world.liveRounds, {(asset: 'BTC', minutes: 5)});
      await unmountInvestments(tester);
    });
  });

  group('own rounds', () {
    testWidgets('a held round is not listed; the strip marks it',
        (tester) async {
      final world = InstantWorld()..positions = [heldRound()];
      await pumpInstant(tester, world);
      expect(find.byType(PolyPositionRow), findsNothing);
      expect(
          find.byKey(ValueKey('instant-round-held-${world.liveStart(5)}')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('crypto-round-up')), findsOneWidget);
      await unmountInvestments(tester);
    });
  });

  group('the gate', () {
    testWidgets('browsing withheld: the notice, nothing read', (tester) async {
      final world = InstantWorld()..positions = [heldRound()];
      await pumpInstantPage(tester, world, browse: false);
      expect(find.byType(InvestmentDiscoveryNotice), findsWidgets);
      expect(find.byType(PolyInstantPage), findsNothing);
      expect(find.byKey(const ValueKey('instant-filter-assets')), findsNothing);
      expect(find.byKey(const ValueKey('crypto-round-up')), findsNothing);
      expect(find.byType(PolyPositionRow), findsNothing);
      expect(world.builtRounds, isEmpty);
      // The Portfolio's own subscription for the holding stays, as anywhere.
      expect(world.socketTokens.keys.where((t) => t != 'held-up'), isEmpty);
      await unmountInvestments(tester);
    });

    testWidgets('browsing withheld: the sheet offers no Instant',
        (tester) async {
      await pumpPredictionsSheet(tester, InstantWorld(), browse: false);
      expect(find.byKey(instantTile), findsNothing);
      expect(tile(PolyPill.trending), findsNothing);
      await unmountInvestments(tester);
    });
  });
}
