// Gating audit, v2.2 (founder: "make sure the gatings work properly when
// stuff is not available from the backend"): the browse surfaces of
// Investing and Predictions added or changed this round, under a backend
// policy that withholds what they answer to, each of the four ways it can
// (a named region block, a platform rule, the switch off, coming soon),
// and under the swap cascade (a region block on swaps reaching the
// venues' trading and deposits).
//
//   * The Investing market map and the moving-now strip are drawn from
//     the browse universe, which the stock gate filters: no stock-linked
//     perpetual is a tile or a big card while `hyperliquid.stocks` denies.
//     The swap cascade withholds trading, not browsing: the map stays
//     whole and every new position is refused at the order slip.
//   * The category sheets: Sports (with Live and Esports) and Politics
//     (with Elections) go with their gates; with browsing withheld the
//     sheet lists nothing and shows the venue page's own notice, the
//     named-region copy carrying only the VPN sentence. A pick the policy
//     no longer offers reads as Trending on the page's pill.
//   * The Dollars page opens on Investing (founder, 7 November 2026), the
//     market map its second item, under the squares: with
//     `hyperliquid.browse` withheld it opens on Predictions (or Activity
//     with Predictions' browsing withheld too), and the Investing tab has
//     no map, no skeleton and no squares, only its notice. With
//     `hyperliquid.stocks` denied it still opens on Investing, the map in
//     its place with no stock-linked tile.
//   * Special US election events (the maps) and game markets reach the
//     market page only through the feeds the category gates filter, and
//     a bet on any of their lines still asks the category gate.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_map.dart';
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart';
import 'package:kute/screens/shared/investment_balance_header.dart'
    show InvestmentDiscoveryNotice;
import 'package:kute/screens/usd/investments_category_sheet.dart';
import 'package:kute/screens/usd/usd_account_screen.dart'
    show InvestmentsBody, InvestmentsTab, investmentsTabProvider;
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/services/polymarket/polymarket_category_gate.dart';
import 'package:kute/services/polymarket/special_event_map.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../helpers/offline_venue_overrides.dart';
import '../screens/hyperliquid/hl_market_map_fixture.dart';
import '../screens/hyperliquid/hl_trending_strip_fixture.dart'
    show hlFixtureMarket;
import '../screens/usd/investments_harness.dart';
import '../services/polymarket/special_event_fixtures.dart';
import 'investing_gating_policies.dart';

final _en = lookupAppLocalizations(const Locale('en'));

/// The fixture universe plus a pre-IPO perp and a tokenized stock (spot).
final _universe = [
  ...hlMarketMapFixture,
  hlFixtureMarket('NVDA', dex: 'xyz', category: 'stocks', vlm: 4e8),
  hlFixtureMarket('TSLA',
      category: 'stocks', spot: true, vlm: 3e5, wire: 'TSLA/USDC'),
];

List<HlMarket> get _perps => [
      for (final m in _universe)
        if (!m.isSpot) m
    ];
List<HlMarket> get _spots => [
      for (final m in _universe)
        if (m.isSpot) m
    ];

/// Reads the browse universe the Investing list, its strip and its map are
/// drawn from, under [policy].
Future<List<HlMarket>> _browseUniverse(
    RuntimeCapabilitiesService policy) async {
  final container = ProviderContainer(overrides: [
    hyperliquidPerpMarketsProvider.overrideWith((_) async => _perps),
    hyperliquidPerpCoreMarketsProvider.overrideWith((_) async => _perps),
    hyperliquidSpotMarketsProvider.overrideWith((_) async => _spots),
    runtimeCapabilitiesProvider.overrideWithValue(policy),
  ]);
  addTearDown(container.dispose);
  final sub = container.listen(hyperliquidBrowseUniverseProvider, (_, __) {});
  addTearDown(sub.close);
  await container.read(hyperliquidPerpMarketsProvider.future);
  await container.read(hyperliquidSpotMarketsProvider.future);
  return container.read(hyperliquidBrowseUniverseProvider).requireValue;
}

Future<RuntimeCapabilitiesService> _loaded(
    RuntimeCapabilitiesService policy) async {
  addTearDown(policy.dispose);
  expect(await policy.refresh(), isTrue);
  return policy;
}

PolymarketEvent _event(Map<String, dynamic> raw) =>
    PolymarketModel().parseEventsRaw([raw]).single;

PolymarketEvent _plain(String slug,
        {String category = 'other', List<String> tags = const []}) =>
    PolymarketEvent(
      id: slug,
      slug: slug,
      title: slug,
      volume: 1,
      volume24hr: 1,
      liquidity: 1,
      category: category,
      tags: tags,
      conditionId: 'cond-$slug',
      outcomes: const [
        PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'yes'),
        PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'no'),
      ],
    );

/// Every list empty and read: nothing goes to the network.
class _EmptyFeed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) => const PolyFeedState(done: true);
}

class _NoSports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

/// The category sheet of [tab] over a page, under [policy] (the harness's
/// own policy replaced by it, for the providers and the singleton).
Future<void> _pumpSheet(
    WidgetTester tester, InvestmentsTab tab, RuntimeCapabilitiesService policy,
    {PolyBrowseSelection? selection}) async {
  // The universe as the provider filters it under [policy] (read on its
  // own above), loaded, as the Investing page behind the sheet keeps it.
  final universe = await _browseUniverse(policy);
  await pumpInvestments(
    tester,
    size: const Size(390, 1400),
    overrides: [
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      polyBrowseFeedProvider.overrideWith(_EmptyFeed.new),
      sportsLiveProvider.overrideWith(_NoSports.new),
      hyperliquidPerpMarketsProvider.overrideWith((_) async => _perps),
      hyperliquidPerpCoreMarketsProvider.overrideWith((_) async => _perps),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => _spots),
      hyperliquidBrowseUniverseProvider
          .overrideWith((_) => AsyncValue.data(universe)),
      hyperliquidBuilderMarketsMissingProvider.overrideWith((_) => false),
      if (selection != null)
        polyBrowseSelectionProvider.overrideWith((_) => selection),
    ],
    child: Scaffold(
      body: Consumer(
        builder: (context, ref, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(investmentsCategoryLabel(ref, context.l10n, tab),
                key: const ValueKey('pill-label')),
            TextButton(
              onPressed: () => showInvestmentsCategorySheet(context, ref, tab),
              child: const Text('Open categories'),
            ),
          ]),
        ),
      ),
    ),
  );
  RuntimeCapabilitiesService.debugInstance = policy;
}

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState();
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

/// The whole Dollars page under [policy], its Investing tab over the map's
/// universe as [policy] filters it, Predictions' feeds empty. Returns the
/// pill it opened on.
Future<InvestmentsTab> _pumpDollars(
    WidgetTester tester, RuntimeCapabilitiesService policy) async {
  final universe = await _browseUniverse(policy);
  await pumpInvestments(
    tester,
    policy: policy,
    size: const Size(390, 2400),
    overrides: [
      ...offlineVenueOverrides,
      polyBrowseFeedProvider.overrideWith(_EmptyFeed.new),
      sportsLiveProvider.overrideWith(_NoSports.new),
      hyperliquidBrowseUniverseProvider
          .overrideWith((_) => AsyncValue.data(universe)),
      hyperliquidBuilderMarketsMissingProvider.overrideWith((_) => false),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidSparklineStoreProvider.overrideWithValue(
          HlSparklineStore(fetch: (_) async => const [1, 2, 3])),
    ],
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return ProviderScope.containerOf(
          tester.element(find.byType(InvestmentsBody, skipOffstage: false)))
      .read(investmentsTabProvider);
}

final _map = find.byKey(const ValueKey('hl-market-map'), skipOffstage: false);
final _mapBones =
    find.byKey(const ValueKey('hl-market-map-loading'), skipOffstage: false);
final _squares = find.byType(HlMovingNowStrip, skipOffstage: false);

Future<void> _openSheet(WidgetTester tester) =>
    tapAndPump(tester, find.text('Open categories'));

Finder _tile(String key) => find.byKey(ValueKey('category-tile-$key'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    AffiliateService.debugSessionToken = 'audit-session';
  });
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  group('Investing market map and moving-now strip', () {
    test('everything allowed: stock perps are tiles', () async {
      final universe = await _browseUniverse(await _loaded(auditPolicy()));
      final entries = hlMarketMapEntries(universe);
      expect(entries.where((e) => isHlStockPerp(e.market)), isNotEmpty);
    });

    for (final denial in AuditDenial.values) {
      test(
          'hyperliquid.stocks ${denial.name}: no stock-linked perpetual on '
          'the map, the strip or the list; the rest stays', () async {
        final policy =
            await _loaded(auditDenying(const ['hyperliquid.stocks'], denial));
        expect(policy.allows('hyperliquid.stocks'), isFalse);
        final universe = await _browseUniverse(policy);
        expect(universe.where(isHlStockPerp), isEmpty);
        // The spot token is a share, not a perpetual: it stays listed.
        expect(universe.where((m) => m.isSpot && m.coin == 'TSLA'), isNotEmpty);
        final entries = hlMarketMapEntries(universe);
        expect(entries.where((e) => isHlStockPerp(e.market)), isEmpty);
        expect(entries.map((e) => e.market.coin),
            containsAll(['BTC', 'ETH', 'XYZ100']));
        expect(
            hlTrendingStrip(universe, universe).where(isHlStockPerp), isEmpty);
        // A held stock perp is still closable: the exit is not the gate.
        expect(policy.allows('hyperliquid.close'), isTrue);
      });
    }

    test(
        'swap country block: browsing is untouched (the whole map), new '
        'positions are refused with the named regions, exits open', () async {
      final policy = await _loaded(auditSwapCountryBlock());
      final open = await _browseUniverse(await _loaded(auditPolicy()));
      final universe = await _browseUniverse(policy);
      expect(hlMarketMapEntries(universe).map((e) => e.id),
          hlMarketMapEntries(open).map((e) => e.id));
      final btc = universe.firstWhere((m) => m.coin == 'BTC');
      await expectLater(
          policy.ensureAllAllowed(hlOpenCapabilities(btc)),
          throwsA(isA<CapabilityUnavailableException>().having(
              (e) => e.decision.messageIn(_en),
              'message',
              '$kAuditRegionTitle\n$kAuditVpnLine')));
      for (final exit in kAuditExits) {
        expect(policy.allows(exit), isTrue, reason: exit);
      }
    });

    test('no policy at all: the stock gate fails closed, browsing stays',
        () async {
      final unread = auditPolicy();
      addTearDown(unread.dispose);
      final universe = await _browseUniverse(unread);
      expect(universe.where(isHlStockPerp), isEmpty);
      expect(hlMarketMapEntries(universe), isNotEmpty);
      for (final exit in kAuditExits) {
        expect(unread.allows(exit), isTrue, reason: '$exit offline');
      }
    });
  });

  group('the Dollars page and its market map', () {
    testWidgets(
        'everything allowed: the page opens on Investing, the map second '
        'under the squares', (tester) async {
      final policy = auditPolicy();
      expect(await policy.refresh(), isTrue);
      expect(await _pumpDollars(tester, policy), InvestmentsTab.investing);
      expect(_squares, findsOneWidget);
      expect(_map, findsOneWidget);
      expect(tester.getTopLeft(_map).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(_squares).dy));
      await unmountInvestments(tester);
      policy.dispose();
    });

    for (final denial in AuditDenial.values) {
      testWidgets(
          'hyperliquid.browse ${denial.name}: the page opens on '
          'Predictions; Investing has no map, no skeleton, no squares, '
          'only its notice', (tester) async {
        final policy = auditDenying(const ['hyperliquid.browse'], denial);
        expect(await policy.refresh(), isTrue);
        expect(policy.allows('polymarket.browse'), isTrue);
        expect(await _pumpDollars(tester, policy), InvestmentsTab.predictions);
        expect(_map, findsNothing);
        expect(_mapBones, findsNothing);
        expect(_squares, findsNothing);
        final notices = tester.widgetList<InvestmentDiscoveryNotice>(
            find.byType(InvestmentDiscoveryNotice, skipOffstage: false));
        expect(notices.map((n) => n.capability),
            contains('hyperliquid.browse'));
        await unmountInvestments(tester);
        policy.dispose();
      });

      testWidgets(
          'both venues\' browsing ${denial.name}: the page opens on '
          'Activity, no map anywhere', (tester) async {
        final policy = auditDenying(
            const ['hyperliquid.browse', 'polymarket.browse'], denial);
        expect(await policy.refresh(), isTrue);
        expect(await _pumpDollars(tester, policy), InvestmentsTab.activity);
        expect(_map, findsNothing);
        expect(_mapBones, findsNothing);
        await unmountInvestments(tester);
        policy.dispose();
      });

      testWidgets(
          'hyperliquid.stocks ${denial.name}: the page still opens on '
          'Investing, the map second with no stock-linked tile',
          (tester) async {
        final policy = auditDenying(const ['hyperliquid.stocks'], denial);
        expect(await policy.refresh(), isTrue);
        expect(await _pumpDollars(tester, policy), InvestmentsTab.investing);
        expect(_map, findsOneWidget);
        final painter = tester
            .widgetList<CustomPaint>(
                find.descendant(of: _map, matching: find.byType(CustomPaint)))
            .map((p) => p.painter)
            .whereType<HlMarketMapPainter>()
            .single;
        final stocks = {
          for (final m in _universe)
            if (isHlStockPerp(m)) hlMarketMapId(m)
        };
        expect(stocks, isNotEmpty);
        final tiles = {for (final t in painter.layout.tiles) t.id};
        expect(tiles.intersection(stocks), isEmpty);
        expect(painter.layout.tiles, isNotEmpty);
        await unmountInvestments(tester);
        policy.dispose();
      });
    }
  });

  group('category sheets', () {
    for (final denial in AuditDenial.values) {
      testWidgets(
          'polymarket.sports ${denial.name}: no Sports, Live or Esports '
          'tile; Politics stays', (tester) async {
        final policy = auditDenying(const ['polymarket.sports'], denial);
        expect(await policy.refresh(), isTrue);
        await _pumpSheet(tester, InvestmentsTab.predictions, policy);
        await _openSheet(tester);
        for (final p in [PolyPill.sports, PolyPill.live, PolyPill.esports]) {
          expect(_tile(p.key), findsNothing, reason: p.key);
        }
        expect(_tile(PolyPill.politics.key), findsOneWidget);
        await unmountInvestments(tester);
        policy.dispose();
      });

      testWidgets(
          'polymarket.politics ${denial.name}: no Politics or Elections '
          'tile; Sports stays', (tester) async {
        final policy = auditDenying(const ['polymarket.politics'], denial);
        expect(await policy.refresh(), isTrue);
        await _pumpSheet(tester, InvestmentsTab.predictions, policy);
        await _openSheet(tester);
        expect(_tile(PolyPill.politics.key), findsNothing);
        expect(_tile(PolyPill.elections.key), findsNothing);
        expect(_tile(PolyPill.sports.key), findsOneWidget);
        await unmountInvestments(tester);
        policy.dispose();
      });

      for (final (tab, browse) in const [
        (InvestmentsTab.predictions, 'polymarket.browse'),
        (InvestmentsTab.investing, 'hyperliquid.browse'),
      ]) {
        testWidgets(
            '$browse ${denial.name}: the sheet lists no categories, logos '
            'or numbers; the venue page\'s notice says why', (tester) async {
          final policy = auditDenying([browse], denial);
          expect(await policy.refresh(), isTrue);
          await _pumpSheet(tester, tab, policy);
          await _openSheet(tester);
          final notice =
              find.byKey(const ValueKey('category-sheet-browse-withheld'));
          expect(notice, findsOneWidget);
          expect(tester.widget<InvestmentDiscoveryNotice>(notice).capability,
              browse);
          expect(_tile('trending'), findsNothing);
          expect(find.byType(HlCoinIcon), findsNothing);
          final message = policy.decision(browse).messageIn(_en);
          expect(find.text(message), findsOneWidget);
          if (denial == AuditDenial.country) {
            expect(message, '$kAuditRegionTitle\n$kAuditVpnLine');
            expect(message, isNot(contains('use a VPN')));
          }
          await unmountInvestments(tester);
          policy.dispose();
        });
      }
    }

    testWidgets(
        'Investing, hyperliquid.stocks denied: no stock perp logo on any '
        'tile; the categories stay', (tester) async {
      final policy =
          auditDenying(const ['hyperliquid.stocks'], AuditDenial.country);
      expect(await policy.refresh(), isTrue);
      await _pumpSheet(tester, InvestmentsTab.investing, policy);
      await _openSheet(tester);
      expect(_tile('trending'), findsOneWidget);
      final stockCoins = {
        for (final m in _universe)
          if (isHlStockPerp(m)) m.coin
      };
      final logos = tester
          .widgetList<HlCoinIcon>(find.byType(HlCoinIcon))
          .map((w) => w.wireCoin ?? w.coin);
      expect(logos, isNotEmpty);
      for (final m in _universe.where(isHlStockPerp)) {
        expect(logos, isNot(contains(m.wireCoin)), reason: m.wireCoin);
      }
      expect(stockCoins, isNotEmpty);
      await unmountInvestments(tester);
      policy.dispose();
    });

    testWidgets(
        'swap country block: browsing stays, every topic is a tile '
        '(trading is refused at the slip)', (tester) async {
      final policy = auditSwapCountryBlock();
      expect(await policy.refresh(), isTrue);
      await _pumpSheet(tester, InvestmentsTab.predictions, policy);
      await _openSheet(tester);
      for (final p in [
        PolyPill.trending,
        PolyPill.politics,
        PolyPill.sports,
        PolyPill.crypto,
      ]) {
        expect(_tile(p.key), findsOneWidget, reason: p.key);
      }
      expect(find.byKey(const ValueKey('category-sheet-browse-withheld')),
          findsNothing);
      await unmountInvestments(tester);
      policy.dispose();
    });

    testWidgets(
        'a Sports pick the policy withdraws reads as the browser shows it: '
        'Filter (Trending), never "Sports"', (tester) async {
      final policy =
          auditDenying(const ['polymarket.sports'], AuditDenial.masterOff);
      expect(await policy.refresh(), isTrue);
      await _pumpSheet(tester, InvestmentsTab.predictions, policy,
          selection: const PolyBrowseSelection(pill: PolyPill.sports));
      expect(tester.widget<Text>(find.byKey(const ValueKey('pill-label'))).data,
          _en.categoryFilterPrompt);
      await _openSheet(tester);
      expect(_tile(PolyPill.sports.key), findsNothing);
      await unmountInvestments(tester);
      policy.dispose();

      final open = auditPolicy();
      expect(await open.refresh(), isTrue);
      await _pumpSheet(tester, InvestmentsTab.predictions, open,
          selection: const PolyBrowseSelection(pill: PolyPill.sports));
      expect(tester.widget<Text>(find.byKey(const ValueKey('pill-label'))).data,
          _en.polyPillSports);
      await unmountInvestments(tester);
      open.dispose();
    });
  });

  group('special election maps and game markets', () {
    final specials = [
      buildYourMapSenateRaw(),
      senateComboMsScMtRaw(),
      balanceOfPowerRaw(),
      trumpStateVisitsRaw(),
    ].map(_event).toList();
    final game = _plain('lal-bos', category: 'sports', tags: const ['nba']);
    final crypto = _plain('btc-100k', category: 'crypto');

    test('the fixtures are drawn as maps and classify as politics', () {
      for (final e in specials) {
        expect(polySpecialEventOf(e), isNotNull, reason: e.slug);
        expect(polymarketCategoryCapability(e.category, e.tags),
            kPolymarketPoliticsCapability,
            reason: e.slug);
      }
      expect(polymarketCategoryCapability(game.category, game.tags),
          kPolymarketSportsCapability);
    });

    for (final denial in AuditDenial.values) {
      test(
          'polymarket.politics ${denial.name}: no special map reaches a '
          'feed; a bet on any of its states is refused', () async {
        final policy =
            await _loaded(auditDenying(const ['polymarket.politics'], denial));
        expect(polymarketEventsOffered([...specials, game, crypto], policy),
            [game, crypto]);
        for (final e in specials) {
          await expectLater(
              policy.ensureAllAllowed(
                  polymarketBetCapabilities(e.category, e.tags)),
              throwsA(isA<CapabilityUnavailableException>().having(
                  (x) => x.capability,
                  'capability',
                  kPolymarketPoliticsCapability)),
              reason: e.slug);
        }
        // Held election positions stay sellable and claimable.
        expect(policy.allows('polymarket.close'), isTrue);
      });

      test(
          'polymarket.sports ${denial.name}: no game reaches a feed or a '
          'pill; its lines\' bets are refused', () async {
        final policy =
            await _loaded(auditDenying(const ['polymarket.sports'], denial));
        expect(polymarketEventsOffered([game, crypto, ...specials], policy),
            [crypto, ...specials]);
        for (final p in [PolyPill.sports, PolyPill.live, PolyPill.esports]) {
          expect(polyPillOffered(p, policy), isFalse, reason: p.key);
        }
        // A "More markets" line keeps the game's category on its slip.
        await expectLater(
            policy.ensureAllAllowed(
                polymarketBetCapabilities(game.category, const [])),
            throwsA(isA<CapabilityUnavailableException>()));
        expect(policy.allows('polymarket.close'), isTrue);
      });
    }

    test(
        'swap country block: maps and games stay browsable; every bet is '
        'refused with the named regions; sells stay open', () async {
      final policy = await _loaded(auditSwapCountryBlock());
      expect(polymarketEventsOffered([...specials, game], policy),
          [...specials, game]);
      for (final e in [...specials, game]) {
        await expectLater(
            policy.ensureAllAllowed(
                polymarketBetCapabilities(e.category, e.tags)),
            throwsA(isA<CapabilityUnavailableException>()
                .having((x) => x.capability, 'capability', 'polymarket.trade')
                .having(
                    (x) => x.decision.blockedBy, 'blockedBy', 'orchestra.swap')
                .having((x) => x.decision.regionTitleIn(_en), 'title',
                    kAuditRegionTitle)),
            reason: e.slug);
      }
      await policy.ensureAllowed('polymarket.close');
      await policy.ensureAllowed('polymarket.cancel');
      await policy.ensureAllowed('polymarket.withdraw');
    });
  });
}
