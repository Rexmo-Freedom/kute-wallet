// Predictions › Instant (founder, 8 November 2026) on the real Investments
// page, offline: Trending and Instant side by side on the sheet, the
// 5-minute card gone from Trending, the filter and its memory, one card per
// asset, only what is on screen subscribed, the gate, the deep link. The
// helpers at the top are also the render harness's
// (test/audit/instant_render_test.dart).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
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
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show PolyPositionRow;
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/screens/shared/investment_balance_header.dart'
    show InvestmentDiscoveryNotice;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/polymarket/crypto_live_odds.dart';
import 'package:kute/services/polymarket/instant_rounds.dart';
import 'package:kute/services/tracking_service.dart';

import '../usd/investments_harness.dart';

/// What the screen has asked for, for the cost tests.
class InstantWorld {
  /// The assets whose round notifier is alive right now.
  final Set<String> liveRounds = {};

  /// Every asset a round notifier was ever built for.
  final Set<String> builtRounds = {};

  /// Tokens registered on the market socket right now, with their count.
  final Map<String, int> socketTokens = {};

  /// The feed's rows per list.
  Map<PolyFeedQuery, List<PolymarketEvent>> feeds = {};
  Set<PolyFeedQuery> loading = {};
  List<PolymarketPosition> positions = const [];

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
}

/// A round in play of [arg], its price a little above the strike, on the
/// real clock.
class InstantRound extends CryptoPredictNotifier {
  InstantRound(this.world);
  final InstantWorld world;

  @override
  Future<CryptoPredictState> build(String arg) async {
    world.liveRounds.add(arg);
    world.builtRounds.add(arg);
    ref.onDispose(() => world.liveRounds.remove(arg));
    final span = 300;
    final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final startS = epoch ~/ span * span;
    final start = DateTime.fromMillisecondsSinceEpoch(startS * 1000, isUtc: true);
    final base = switch (arg) {
      'BTC' => 76000.0,
      'ETH' => 3120.0,
      'SOL' => 171.0,
      'XRP' => 2.31,
      'DOGE' => 0.0712,
      'BNB' => 612.0,
      _ => 77.4,
    };
    var px = base;
    return CryptoPredictState(
      asset: arg,
      currentPrice: base * 1.0009,
      priceToBeat: base,
      secondsRemaining: 163,
      event: Btc5MinEvent(
        slug: '${arg.toLowerCase()}-updown-5m-$startS',
        title: '$arg Up or Down',
        windowStartTime: start,
        endDate: start.add(const Duration(minutes: 5)),
        upPrice: 0.62,
        downPrice: 0.38,
        upTokenId: '$arg-up',
        downTokenId: '$arg-down',
        conditionId: '$arg-cond',
      ),
      priceHistory: [
        for (var i = 0; i < 90; i++)
          BtcPriceSnapshot(
            timestamp: start.add(Duration(seconds: i)),
            price: px += ((i * 37) % 11 - 4.6) * base * 0.00002,
          ),
      ],
    );
  }
}

class _Prices extends LivePriceNotifier {
  _Prices(this.world);
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

class _Odds extends CryptoLiveOddsNotifier {
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

/// The Predictions page offline, on [world].
List<Override> instantOverrides(InstantWorld world,
        {PolyBrowseSelection? selection}) =>
    [
      polyBrowseSelectionProvider
          .overrideWith((_) => selection ?? const PolyBrowseSelection()),
      polyBrowseFeedProvider.overrideWith(() => _Feed(world)),
      cryptoPredictProvider.overrideWith(() => InstantRound(world)),
      cryptoRecentResultsProvider.overrideWith((_, __) async => const []),
      cryptoPredictWindowsProvider.overrideWith((_, __) async => [5]),
      cryptoNextRoundProvider.overrideWith((_, __) async => null),
      cryptoLiveOddsProvider.overrideWith(_Odds.new),
      livePriceProvider.overrideWith(() => _Prices(world)),
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

/// The round of [asset] in play now at [minutes], with one ahead of it, as
/// the feed lists them.
List<PolymarketEvent> feedRounds(List<String> assets, int minutes) {
  final span = minutes * 60;
  final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final start = epoch ~/ span * span;
  PolymarketEvent row(String asset, int at, int i) {
    final name = {
      'btc': 'Bitcoin',
      'eth': 'Ethereum',
      'sol': 'Solana',
      'xrp': 'XRP',
      'doge': 'Dogecoin',
      'bnb': 'BNB',
      'hype': 'HYPE',
    }[asset]!;
    return PolymarketEvent(
      id: '$asset-$at',
      slug: '$asset-updown-${minutes}m-$at',
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
    for (final a in assets) ...[
      row(a, start, 0),
      row(a, start + span, 1),
    ],
  ];
}

const instantSelection = PolyBrowseSelection(pill: PolyPill.instant);

Finder instantCard(String asset) =>
    find.byKey(ValueKey('instant-card-$asset'));

const List<String> kSevenAssets = [
  'BTC',
  'ETH',
  'SOL',
  'XRP',
  'DOGE',
  'BNB',
  'HYPE'
];

/// A BTC round held by the person.
PolymarketPosition heldRound() {
  final span = 300;
  final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final start = epoch ~/ span * span;
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

Future<void> pumpInstant(WidgetTester tester, InstantWorld world,
    {Size size = const Size(390, 844),
    bool browse = true,
    PolyBrowseSelection selection = instantSelection,
    bool dark = false,
    Locale? locale}) async {
  await pumpInvestments(tester,
      size: size,
      dark: dark,
      locale: locale,
      browsePredictions: browse,
      browseInvesting: browse,
      // Under the shell's Material, as on a phone.
      child: const Scaffold(body: UsdAccountScreen()),
      overrides: instantOverrides(world, selection: selection));
  final l10n = AppLocalizations.of(
      tester.element(find.byType(KutePillTabs).first));
  await tapAndPump(tester, investmentsPill(l10n.predictions));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens the sheet from the picked Predictions pill.
Future<void> openPredictionsSheet(WidgetTester tester) async {
  final l10n = AppLocalizations.of(
      tester.element(find.byType(KutePillTabs).first));
  await tapAndPump(tester, investmentsPill(l10n.predictions));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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
    testWidgets('Trending and Instant side by side, equal, above Topics',
        (tester) async {
      final world = InstantWorld();
      await pumpInstant(tester, world,
          selection: const PolyBrowseSelection());
      await openPredictionsSheet(tester);
      final trending = tile(PolyPill.trending);
      final instant = tile(PolyPill.instant);
      expect(trending, findsOneWidget);
      expect(instant, findsOneWidget);
      final a = tester.getRect(trending);
      final b = tester.getRect(instant);
      expect(a.top, b.top);
      expect(a.size, b.size, reason: 'two equal cards');
      expect(a.right, lessThan(b.left), reason: 'Trending, then Instant');
      final l10n = AppLocalizations.of(tester.element(trending));
      final topics = tester.getTopLeft(find.text(l10n.categoryGroupTopics));
      expect(a.bottom, lessThan(topics.dy));
      // Nothing of the grid above the label; no topic is Instant twice.
      expect(tester.getTopLeft(tile(PolyPill.breaking)).dy,
          greaterThan(topics.dy));
      expect(find.text(l10n.polyPillInstant), findsOneWidget);
      expect(find.text(l10n.categoryInstantAssets('BTC', 'ETH')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('category-instant-next')),
          findsOneWidget);
      await unmountInvestments(tester);
    });

    for (final (picked, other) in [
      (PolyPill.trending, PolyPill.instant),
      (PolyPill.instant, PolyPill.trending),
    ]) {
      testWidgets('the picked look on ${picked.key}', (tester) async {
        final world = InstantWorld();
        await pumpInstant(tester, world,
            selection: PolyBrowseSelection(pill: picked));
        await openPredictionsSheet(tester);
        double ring(PolyPill p) => (tester
                .widget<AnimatedContainer>(find.descendant(
                    of: tile(p), matching: find.byType(AnimatedContainer)))
                .decoration as BoxDecoration)
            .border!
            .top
            .width;
        expect(ring(picked), 1.5);
        expect(ring(other), lessThan(1.5));
        await unmountInvestments(tester);
      });
    }

    testWidgets('a tap on Instant closes the sheet and shows its page',
        (tester) async {
      final world = InstantWorld();
      await pumpInstant(tester, world,
          selection: const PolyBrowseSelection());
      await openPredictionsSheet(tester);
      await tester.tap(tile(PolyPill.instant));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tile(PolyPill.instant), findsNothing);
      expect(find.byKey(const ValueKey('instant-filter-assets')),
          findsOneWidget);
      expect(instantCard('BTC'), findsOneWidget);
      expect(
          events.any((e) =>
              e.$1 == 'category_pill_tapped' &&
              e.$2?['section'] == 'instant'),
          isTrue);
      await unmountInvestments(tester);
    });
  });

  testWidgets('the 5-minute card has left Trending', (tester) async {
    final world = InstantWorld();
    await pumpInstant(tester, world, selection: const PolyBrowseSelection());
    expect(find.byType(CryptoPredictBanner), findsNothing);
    expect(world.builtRounds, isEmpty, reason: 'no round read for Trending');
    expect(events.any((e) => e.$1 == 'predict_hero_viewed'), isFalse);
    await unmountInvestments(tester);
  });

  group('the filter', () {
    testWidgets('Bitcoin five minutes first, a pick moves its card first',
        (tester) async {
      final world = InstantWorld();
      await pumpInstant(tester, world, size: const Size(390, 2000));
      double top(String a) => tester.getTopLeft(instantCard(a)).dy;
      expect(top('BTC'), lessThan(top('ETH')));
      expect(
          tester.widget<CryptoPredictBanner>(find.descendant(
              of: instantCard('BTC'),
              matching: find.byType(CryptoPredictBanner))),
          isA<CryptoPredictBanner>()
              .having((c) => c.compact, 'compact', isTrue)
              .having((c) => c.slipSource, 'slipSource', 'instant'));
      await tapAndPump(
          tester, find.byKey(const ValueKey('instant-asset-SOL')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(top('SOL'), lessThan(top('BTC')));
      expect(top('BTC'), lessThan(top('ETH')), reason: 'the rest keep order');
      final filter =
          events.lastWhere((e) => e.$1 == 'predictions_instant_filter_changed');
      expect(filter.$2,
          {'asset': 'SOL', 'length': '5m', 'changed': 'asset'});
      await unmountInvestments(tester);
    });

    testWidgets('a length with a list: its cards, one round per asset',
        (tester) async {
      final world = InstantWorld()
        ..feeds = {
          const PolyFeedQuery(pill: PolyPill.crypto, sub: '15m'):
              feedRounds(['eth', 'btc', 'sol', 'xrp'], 15),
        };
      await pumpInstant(tester, world, size: const Size(390, 2000));
      await tapAndPump(
          tester, find.byKey(const ValueKey('instant-length-15m')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CryptoPredictBanner), findsNothing,
          reason: 'the five-minute cards are gone');
      expect(find.byType(MarketCard), findsNWidgets(4),
          reason: 'one per asset, not one per window');
      expect(find.text('Bitcoin · 15 Min'), findsOneWidget);
      final filter =
          events.lastWhere((e) => e.$1 == 'predictions_instant_filter_changed');
      expect(filter.$2,
          {'asset': 'BTC', 'length': '15m', 'changed': 'length'});
      // The assets the venue runs at this length.
      expect(find.byKey(const ValueKey('instant-asset-XRP')), findsOneWidget);
      expect(find.byKey(const ValueKey('instant-asset-HYPE')), findsNothing);
      await unmountInvestments(tester);
    });

    testWidgets('a length with nothing in it says so', (tester) async {
      final world = InstantWorld()
        ..choice = const PolyInstantChoice(asset: 'BTC', length: '4h');
      await pumpInstant(tester, world);
      final l10n = AppLocalizations.of(
          tester.element(find.byType(KutePillTabs).first));
      expect(find.text(l10n.predictNoOpenMarketsCategory), findsOneWidget);
      expect(find.byKey(const ValueKey('instant-filter-lengths')),
          findsOneWidget);
      await unmountInvestments(tester);
    });

    testWidgets('a remembered length the venue dropped reads five minutes',
        (tester) async {
      final world = InstantWorld()
        ..choice = const PolyInstantChoice(asset: 'ETH', length: '1h')
        ..cryptoSubs = const [PolySub('all'), PolySub('5m'), PolySub('15m')];
      await pumpInstant(tester, world, size: const Size(390, 2000));
      expect(instantCard('ETH'), findsOneWidget);
      expect(find.byKey(const ValueKey('instant-length-1h')), findsNothing);
      expect(tester.getTopLeft(instantCard('ETH')).dy,
          lessThan(tester.getTopLeft(instantCard('BTC')).dy));
      await unmountInvestments(tester);
    });
  });

  group('the memory', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('instant_choice');
      Hive.init(dir.path);
    });
    tearDown(() async {
      await Hive.deleteBoxFromDisk(PolyInstantChoiceNotifier.boxName);
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('the last pick comes back, a broken one reads the default', () async {
      var c = ProviderContainer();
      addTearDown(() => c.dispose());
      expect(c.read(polyInstantChoiceProvider), kPolyInstantDefault);
      await Hive.openBox<String>(PolyInstantChoiceNotifier.boxName);
      const pick = PolyInstantChoice(asset: 'SOL', length: '15m');
      c.read(polyInstantChoiceProvider.notifier).pick(pick);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      c.dispose();

      c = ProviderContainer();
      expect(c.read(polyInstantChoiceProvider), pick);
      c.dispose();

      await Hive.box<String>(PolyInstantChoiceNotifier.boxName)
          .put('choice', '{"asset":"SOL","length":"3d"}');
      c = ProviderContainer();
      expect(c.read(polyInstantChoiceProvider), kPolyInstantDefault);
    });
  });

  group('the cost', () {
    testWidgets('only the cards on screen are built and subscribed',
        (tester) async {
      final world = InstantWorld();
      await pumpInstant(tester, world);
      // A phone's height holds some of the seven, never all.
      final shown = world.liveRounds.length;
      expect(shown, 3);
      expect(world.liveRounds.contains('HYPE'), isFalse);
      expect(world.socketTokens.length, shown * 2,
          reason: 'an up and a down token per card on screen');
      expect(find.byType(CryptoPredictBanner), findsNWidgets(shown));
      await unmountInvestments(tester);
    });

    testWidgets('a card scrolled away stops, a card scrolled in starts',
        (tester) async {
      final world = InstantWorld();
      await pumpInstant(tester, world);
      expect(world.liveRounds.contains('BTC'), isTrue);
      final browser = find.byType(PolymarketScreen);
      await tester.drag(browser, const Offset(0, -1500), warnIfMissed: false);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(world.liveRounds.contains('BTC'), isFalse,
          reason: 'the read and its timers stop');
      expect(world.socketTokens.containsKey('BTC-up'), isFalse,
          reason: 'its tokens leave the socket');
      expect(world.liveRounds.contains('HYPE'), isTrue);
      expect(world.liveRounds.length, lessThanOrEqualTo(4),
          reason: 'with the hero scrolled away, a phone holds four at most');
      expect(world.socketTokens.length, world.liveRounds.length * 2);
      await unmountInvestments(tester);
    });

    testWidgets('a hidden pill stops it all; back, its place is kept',
        (tester) async {
      final world = InstantWorld();
      await pumpInstant(tester, world);
      final shown = world.liveRounds.toSet();
      expect(shown, isNotEmpty);
      final l10n = AppLocalizations.of(
          tester.element(find.byType(KutePillTabs).first));
      await tapAndPump(tester, investmentsPill(l10n.trading));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(world.liveRounds, isEmpty, reason: 'no read behind the pill');
      expect(world.socketTokens, isEmpty, reason: 'no seat on the socket');
      await tapAndPump(tester, investmentsPill(l10n.predictions));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(world.liveRounds, shown);
      await unmountInvestments(tester);
    });

    testWidgets('leaving Instant stops all of it', (tester) async {
      final world = InstantWorld();
      await pumpInstant(tester, world);
      expect(world.liveRounds, isNotEmpty);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(PolymarketScreen)));
      container.read(polyBrowseSelectionProvider.notifier).state =
          const PolyBrowseSelection();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(world.liveRounds, isEmpty);
      expect(world.socketTokens, isEmpty);
      await unmountInvestments(tester);
    });
  });

  group('own rounds', () {
    testWidgets('on the position rows, above the cards', (tester) async {
      final world = InstantWorld()..positions = [heldRound()];
      await pumpInstant(tester, world);
      final own = find.byType(PolyPositionRow);
      expect(own, findsOneWidget);
      expect(tester.getTopLeft(own).dy,
          lessThan(tester.getTopLeft(instantCard('BTC')).dy));
      await unmountInvestments(tester);
    });

    testWidgets('a held market that is no round stays off', (tester) async {
      final world = InstantWorld()
        ..positions = [
          const PolymarketPosition(
            marketId: 'fed',
            marketQuestion: 'Fed cuts?',
            outcome: 'Yes',
            size: 3,
            avgPrice: 0.4,
            currentPrice: 0.5,
            pnl: 0.3,
            pnlPercent: 25,
            isResolved: false,
            tokenId: 'fed-yes',
            eventSlug: 'fed-decision-in-december',
          ),
        ];
      await pumpInstant(tester, world);
      expect(find.byType(PolyPositionRow), findsNothing);
      await unmountInvestments(tester);
    });
  });

  group('the gate', () {
    testWidgets('browsing withheld: the notice, nothing read', (tester) async {
      final world = InstantWorld()..positions = [heldRound()];
      await pumpInstant(tester, world, browse: false);
      expect(find.byType(InvestmentDiscoveryNotice), findsWidgets);
      expect(find.byType(CryptoPredictBanner), findsNothing);
      expect(find.byKey(const ValueKey('instant-filter-assets')), findsNothing);
      expect(find.byType(PolyPositionRow), findsNothing);
      expect(world.builtRounds, isEmpty);
      // The Portfolio's own subscription for the holding stays, as anywhere.
      expect(world.socketTokens.keys.where((t) => t != 'held-up'), isEmpty);
      await unmountInvestments(tester);
    });

    testWidgets('browsing withheld: the sheet offers no Instant',
        (tester) async {
      final world = InstantWorld();
      await pumpInstant(tester, world,
          browse: false, selection: const PolyBrowseSelection());
      await openPredictionsSheet(tester);
      expect(tile(PolyPill.instant), findsNothing);
      expect(tile(PolyPill.trending), findsNothing);
      await unmountInvestments(tester);
    });
  });

  group('the list reads', () {
    test('Instant reads no list of its own and is no neighbour to prefetch',
        () {
      expect(
          polyFeedSourceParams(const PolyFeedQuery(pill: PolyPill.instant)),
          isEmpty);
      final around = PolyFeedPrefetch.queriesAround(
        selection: const PolyBrowseSelection(pill: PolyPill.trending),
        pills: const [PolyPill.trending, PolyPill.instant],
        subs: const [],
      );
      expect(around, isEmpty);
    });
  });
}
