// Gating audit (fw36, founder: "make sure the gatings work properly when
// stuff is not available from the backend"): the market pages and their
// floating trade row, the slips they open, challenge and claim links,
// Send a prediction or investment, and every share that is not a send
// (the market page's round button, the search context cards, receipts,
// brags) under the four ways the backend withholds a capability: a swap
// country block and its cascade, a platform block, the master switch off,
// coming soon.
//
// The rules held here (company decisions):
//   * blocks come only from the backend policy; the copy names the
//     backend's regions and its one VPN sentence is "If this isn't where
//     you are, check your VPN settings.";
//   * a swap block cascades to Investing and Predictions trading and
//     deposits; exits (close, sell, cancel, withdraw) stay open;
//   * hiding markets by category (sports, politics, stock perps) is the
//     browse gates' intended job;
//   * the trade row's doors always open the slip, whose own gate explains
//     and re-checks at confirm (slip_entry_gating_test.dart);
//   * a share never carries money except Send to anyone, and a venue
//     closed to this person is never offered there to compose a pick.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/hyperliquid_search_provider.dart'
    show HlMarketSearchResult;
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show
        PolyFeedNotifier,
        PolyFeedQuery,
        PolyFeedState,
        polyBrowseFeedProvider,
        polymarketEventDetailsProvider,
        polymarketMarketHistoryProvider;
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart'
    show HlMarketDetailSheet;
import 'package:kute/screens/search/components/search_rows.dart';
import 'package:kute/screens/share/claim_screen.dart';
import 'package:kute/screens/search/unified_search_screen.dart'
    show UnifiedSearchSurface;
import 'package:kute/screens/share/send_pick_market_sheet.dart';
import 'package:kute/screens/share/send_pick_session.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/services/polymarket/polymarket_category_gate.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../helpers/hl_chart_edit_harness.dart';
import '../helpers/kute_bar_test_support.dart';
import '../helpers/shell_bar_harness.dart';
import '../screens/share/share_test_harness.dart';
import 'market_gating_fixtures.dart';

const _perp = HlMarket(
  coin: 'ETH',
  wireCoin: 'ETH',
  assetId: 1,
  kind: HlMarketKind.perp,
  szDecimals: 4,
  maxLeverage: 25,
  onlyIsolated: false,
  markPx: 3000,
  midPx: 3000,
  prevDayPx: 2900,
  dayNtlVlm: 1e9,
);

/// A stock-linked perpetual (the venue's own annotation).
const _stockPerp = HlMarket(
  coin: 'xyz:TSLA',
  wireCoin: 'xyz:TSLA',
  assetId: 110001,
  kind: HlMarketKind.perp,
  szDecimals: 2,
  maxLeverage: 10,
  onlyIsolated: true,
  markPx: 250,
  midPx: 250,
  prevDayPx: 245,
  dayNtlVlm: 1e8,
  category: 'stocks',
);

PolymarketEvent _event(String slug, String category) => PolymarketEvent(
      id: 'e-$slug',
      slug: slug,
      title: 'Market $slug',
      volume: 1000,
      liquidity: 1000,
      category: category,
      conditionId: 'c-$slug',
      outcomes: [
        PolymarketOutcome(name: 'Yes', price: 0.62, tokenId: '$slug-yes'),
        PolymarketOutcome(name: 'No', price: 0.38, tokenId: '$slug-no'),
      ],
    );

final _crypto = _event('btc-150k', 'crypto');
final _sports = _event('lakers-win', 'sports');
final _politics = _event('lula-wins', 'politics');

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

class _Feed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) =>
      PolyFeedState(events: [_crypto], done: true);
}

/// The send-mode search sheet's feeds: the trending prediction and the
/// Investing mover, nothing searched.
final _sendPickFeeds = <Override>[
  aiEnabledProvider.overrideWith((_) async => true),
  sportsLiveProvider.overrideWith(_Sports.new),
  unifiedSearchResultsProvider
      .overrideWith((_) async => UnifiedSearchResults.empty),
  globalMarketResultsProvider.overrideWith(
      (ref) => const AsyncValue.data(<GlobalMarketSearchResult>[])),
  globalHyperliquidResultsProvider.overrideWith(
      (ref) => const AsyncValue.data(<HlMarketSearchResult>[])),
  hyperliquidAllMarketsProvider.overrideWith((_) => []),
  hyperliquidBrowseUniverseProvider
      .overrideWith((_) => const AsyncValue.data([_perp])),
  hyperliquidSparklineStoreProvider.overrideWith(
      (_) => HlSparklineStore(fetch: (_) async => const [1.0, 2.0, 3.0])),
  polyBrowseFeedProvider.overrideWith(_Feed.new),
];

/// The targets each denial is aimed at when it is not the swap block: new
/// positions on both venues.
const _trading = {'hyperliquid.trade', 'polymarket.trade'};

void main() {
  tearDown(uninstallMarketGatingPolicy);

  group('the trade row\'s doors: what the slips ask when they open', () {
    for (final how in MarketDenial.values) {
      test(
          '${how.label}: Invest / Short and Yes / No are refused with the '
          'backend\'s words; every exit stays open', () async {
        final policy = await installMarketGatingPolicy(how, targets: _trading);

        // Investing: the order slip's open gate (hlOpenCapabilities).
        await expectLater(
            policy.ensureAllAllowed(hlOpenCapabilities(_perp)),
            throwsA(isA<CapabilityUnavailableException>()
                .having((e) => e.capability, 'capability', 'hyperliquid.trade')
                .having((e) => e.decision.messageIn(marketGatingEn), 'message',
                    how.message)));
        // Predictions: the bet slip's open gate.
        await expectLater(
            policy.ensureAllAllowed(polymarketBetCapabilities('crypto', [])),
            throwsA(isA<CapabilityUnavailableException>()
                .having((e) => e.capability, 'capability', 'polymarket.trade')
                .having((e) => e.decision.messageIn(marketGatingEn), 'message',
                    how.message)));

        final trade = policy.decision('hyperliquid.trade');
        expect(trade.regionRestricted, how == MarketDenial.swapCountryBlock);
        expect(trade.deviceRestricted, how == MarketDenial.platform);
        expect(trade.comingSoon, how == MarketDenial.comingSoon);
        if (how == MarketDenial.swapCountryBlock) {
          // The cascade names the swap master and its regions: the slip's
          // sheet title and its one VPN sentence.
          expect(trade.blockedBy, kSwapMaster);
          expect(trade.regionTitleIn(marketGatingEn), kGatingNamedTitle);
          expect(trade.bodyIn(marketGatingEn), kGatingVpnSentence);
        }
        // Never advice to use a VPN, whatever the denial.
        expect(trade.messageIn(marketGatingEn).toLowerCase(),
            isNot(contains('use a vpn')));

        // Exits: close, sell, cancel, withdraw.
        for (final exit in kVenueExits) {
          expect(policy.allows(exit), isTrue, reason: exit);
          await policy.ensureAllowed(exit);
        }
      });
    }

    test(
        'a stock perp asks the stock gate on top; a plain perp and a '
        'prediction outside sports and politics do not', () {
      expect(hlOpenCapabilities(_perp), ['hyperliquid.trade']);
      expect(hlOpenCapabilities(_stockPerp),
          ['hyperliquid.trade', 'hyperliquid.stocks']);
      expect(
          polymarketBetCapabilities('crypto', const []), ['polymarket.trade']);
      expect(polymarketBetCapabilities('sports', const []),
          ['polymarket.trade', kPolymarketSportsCapability]);
      expect(polymarketBetCapabilities('politics', const []),
          ['polymarket.trade', kPolymarketPoliticsCapability]);
    });
  });

  group('the browse gates hide by category (intended), never by the swap block',
      () {
    for (final how in MarketDenial.values
        .where((h) => h != MarketDenial.swapCountryBlock)) {
      test('${how.label} on the category gates: those markets go', () async {
        final policy = await installMarketGatingPolicy(how, targets: {
          'hyperliquid.stocks',
          kPolymarketSportsCapability,
          kPolymarketPoliticsCapability,
        });
        expect(hlMarketOfferedUnderPolicy(_stockPerp, policy), isFalse);
        expect(hlMarketOfferedUnderPolicy(_perp, policy), isTrue);
        expect(polymarketEventOffered(_sports, policy), isFalse);
        expect(polymarketEventOffered(_politics, policy), isFalse);
        expect(polymarketEventOffered(_crypto, policy), isTrue);
        expect(polymarketEventsOffered([_crypto, _sports, _politics], policy),
            [_crypto]);
        expect(
            hlMarketsOfferedUnderPolicy([_perp, _stockPerp], policy), [_perp]);
      });
    }

    test(
        'the swap country block leaves every market browsable: the slip '
        'explains instead', () async {
      final policy =
          await installMarketGatingPolicy(MarketDenial.swapCountryBlock);
      expect(hlMarketOfferedUnderPolicy(_stockPerp, policy), isTrue);
      expect(polymarketEventOffered(_sports, policy), isTrue);
      expect(policy.allows('hyperliquid.browse'), isTrue);
      expect(policy.allows('polymarket.browse'), isTrue);
    });
  });

  group('Send a prediction or investment (send_pick_market_sheet.dart)', () {
    for (final how in MarketDenial.values) {
      test('${how.label} on both venues: nothing to compose a pick on',
          () async {
        final policy = await installMarketGatingPolicy(how, targets: _trading);
        expect(sendPickOffered(policy), isFalse);
      });
      if (how == MarketDenial.swapCountryBlock) continue;
      test('${how.label} on Predictions only: Investing is still offered',
          () async {
        final policy =
            await installMarketGatingPolicy(how, targets: {'polymarket.trade'});
        expect(sendPickOffered(policy), isTrue);
      });
    }

    for (final how in MarketDenial.values) {
      final region = how == MarketDenial.swapCountryBlock;
      test(
          '${how.label} on both venues: the What step\'s gift '
          '${region ? 'stays, a tap saying why' : 'is gone'}', () async {
        final policy = await installMarketGatingPolicy(how, targets: _trading);
        expect(sendGiftShown(policy), region);
        expect(sendPickRegionBlock(policy)?.capability,
            region ? 'polymarket.trade' : null);
      });
    }

    test('Predictions fail open on an unknown location: the pick is offered',
        () async {
      final policy = await installMarketGatingPolicy(null, overrides: {
        'polymarket.trade': {'allowed': false, 'reason': 'country_unknown'},
        'polymarket.deposit': {'allowed': false, 'reason': 'country_unknown'},
        'hyperliquid.trade': {'allowed': false, 'reason': 'disabled'},
      });
      expect(policy.allows('polymarket.trade'), isTrue);
      expect(policy.allows('polymarket.deposit'), isTrue);
      expect(sendPickOffered(policy), isTrue);
    });

    group('the sheet', () {
      late ShareTestEnv env;
      setUp(() {
        env = setUpShareTest();
        OpenOnce.reset();
        SendPickSession.debugOpenMarket = (_) {};
      });
      tearDown(() {
        tearDownShareTest();
        SendPickSession.debugOpenMarket = null;
      });

      Future<void> open(WidgetTester tester) async {
        await pumpShareWidget(
            tester,
            env,
            Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showSendPickMarketSheet(context,
                      entrySource: 'dollar_send'),
                  child: const Text('Pick'),
                ),
              ),
            ),
            overrides: _sendPickFeeds);
        await tester.tap(find.text('Pick'));
        await settle(tester);
        await settle(tester);
        // The search sheet in send mode.
        expect(find.byType(UnifiedSearchSurface), findsOneWidget);
      }

      testWidgets(
          'a backend that cascades the swap block to Investing only: the '
          'Investing rows go, Predictions stay', (tester) async {
        await tester.runAsync(() => installMarketGatingPolicy(null, overrides: {
              'hyperliquid.trade': {
                'allowed': false,
                'reason': 'country_blocked',
                'blockedBy': kSwapMaster,
                'regions': kGatingRegions,
              },
            }));
        await open(tester);
        expect(find.byType(SearchPredictionRow), findsOneWidget);
        expect(find.byType(SearchMoverGrid), findsNothing);
      });

      testWidgets('coming soon on Predictions: only Investing is listed',
          (tester) async {
        await tester.runAsync(() => installMarketGatingPolicy(
            MarketDenial.comingSoon,
            targets: {'polymarket.trade'}));
        await open(tester);
        expect(find.byType(SearchPredictionRow), findsNothing);
        expect(find.byType(SearchMoverGrid), findsOneWidget);
      });
    });
  });

  group('claim and challenge links (claim_screen.dart)', () {
    late ShareTestEnv env;
    late List<ClaimPickOpening> opened;

    ShareLink link(String slug,
            {ShareLinkStatus status = ShareLinkStatus.open,
            bool challenge = false}) =>
        ShareLink(
          id: 'lnk_gate',
          kind: ShareLinkKind.dollars,
          amountMinor: 1000,
          senderLabel: 'Ana',
          marketSlug: slug,
          venue: 'polymarket',
          outcome: 'Yes',
          outcomeIndex: 0,
          side: 'buy',
          status: status,
          rawStatus: status.name,
          expiresAt: DateTime.now().add(const Duration(days: 7)),
          challenge: challenge,
        );

    setUp(() {
      env = setUpShareTest();
      opened = [];
      ClaimScreen.debugDestination = (_) async => 'spark1recipient';
      ClaimScreen.debugOpenPick = opened.add;
    });
    tearDown(() {
      tearDownShareTest();
      ClaimScreen.debugDestination = null;
      ClaimScreen.debugOpenPick = null;
    });

    Future<void> pump(WidgetTester tester) =>
        pumpShareWidget(tester, env, const ClaimScreen(id: 'lnk_gate'),
            cardVenues: false,
            overrides: [
              polymarketEventDetailsProvider
                  .overrideWith((ref, slug) async => slug == _crypto.slug
                      ? _crypto
                      : slug == _sports.slug
                          ? _sports
                          : null),
              polymarketMarketHistoryProvider
                  .overrideWith((ref, key) async => const []),
              hyperliquidPerpMarketsProvider
                  .overrideWith((ref) async => const <HlMarket>[]),
              hyperliquidSpotMarketsProvider
                  .overrideWith((ref) async => const <HlMarket>[]),
            ]);

    Future<void> claimAndArrive(WidgetTester tester, ShareLink paid) async {
      await tester.tap(kuteBarPrimaryWithText('Claim'));
      await settle(tester);
      env.fake.seed(paid);
      await tester.pump(ClaimScreen.paidPollInterval);
      await settle(tester);
    }

    testWidgets(
        'under the swap country block the money still claims (a plain '
        'Spark receive) and the pick opens the slip, whose gate explains',
        (tester) async {
      await tester.runAsync(
          () => installMarketGatingPolicy(MarketDenial.swapCountryBlock));
      env.fake.seed(link(_crypto.slug));
      await pump(tester);
      await claimAndArrive(
          tester, link(_crypto.slug, status: ShareLinkStatus.paid));
      expect(env.fake.calls.where((c) => c.$1 == 'claim'), hasLength(1));
      expect(env.fake.claimDestinations['lnk_gate'], 'spark1recipient');
      await tester.tap(kuteBarPrimaryWithText('Place the prediction'));
      await settle(tester);
      // The slip, never a placement: BetSlipSheet.show runs its own open
      // gate and the confirm re-check.
      expect(opened.single, (outcomeIndex: 0, market: false));
    });

    for (final how in MarketDenial.values
        .where((h) => h != MarketDenial.swapCountryBlock)) {
      testWidgets(
          '${how.label} on sports: a sports pick opens no slip, the market '
          'route decides', (tester) async {
        await tester.runAsync(() => installMarketGatingPolicy(how,
            targets: {kPolymarketSportsCapability}));
        env.fake.seed(link(_sports.slug, challenge: true));
        await pump(tester);
        await claimAndArrive(tester,
            link(_sports.slug, status: ShareLinkStatus.paid, challenge: true));
        await tester.tap(kuteBarPrimaryWithText('Take the other side'));
        await settle(tester);
        expect(opened.single, (outcomeIndex: null, market: true));
      });
    }
  });

  group('the market page (hl market_detail_sheet.dart)', () {
    setUpAll(() {
      Hive.init(Directory.systemTemp.createTempSync('gating-hl-page').path);
    });
    setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

    for (final how in MarketDenial.values) {
      testWidgets(
          '${how.label}: Invest and Short still draw (the slip explains); '
          'the round button sends the market only, no money', (tester) async {
        await tester
            .runAsync(() => installMarketGatingPolicy(how, targets: _trading));
        installShellBar();
        await pumpHlEditSheet(tester, appBuilder: shellBarBuilder);
        await pumpBar(tester);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byKey(const ValueKey('kute-bar-trade-invest')),
            findsOneWidget);
        expect(
            find.byKey(const ValueKey('kute-bar-trade-short')), findsOneWidget);
        final ctx =
            scopeContext(tester, within: find.byType(HlMarketDetailSheet));
        expect(ctx.isTrade, isTrue);
        // The market's own Send to a friend context: the market send
        // sheet (share_market_sheet.dart), never a pick, never money.
        expect(ctx.share!.barContext!.market, isTrue);
        expect(ctx.share!.brag, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 6));
      });
    }
  });

  group('source guards', () {
    String source(String path) => File(path)
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    Iterable<File> dartFiles(String dir) => Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    test(
        'only Send to anyone creates a funded share link: market, search, '
        'receipt and brag shares carry the card and the link only', () {
      final creators = [
        for (final f in dartFiles('lib'))
          if (RegExp(r'shareLinksApiProvider\)\s*\.create\(')
              .hasMatch(source(f.path)))
            f.path,
      ];
      expect(creators, ['lib/screens/share/send_to_anyone_sheet.dart']);
      for (final path in [
        'lib/screens/share/share_market_sheet.dart',
        'lib/screens/share/receipt_share.dart',
        'lib/screens/shared/kute_share_actions.dart',
        'lib/screens/home/components/kute_bar_trade_row.dart',
        ...dartFiles('lib/screens/share/brag').map((f) => f.path),
        ...dartFiles('lib/screens/share/cards').map((f) => f.path),
      ]) {
        expect(source(path), isNot(contains('shareLinksApiProvider')),
            reason: path);
      }
    });

    test(
        'every slip opens through its show(), which runs the open gate; no '
        'share or trade-row file places an order itself', () {
      final direct = [
        for (final f in dartFiles('lib'))
          if (!f.path.endsWith('order_slip_sheet.dart') &&
              !f.path.endsWith('bet_slip_sheet.dart') &&
              RegExp(r'(^|[^A-Za-z_.])(HlOrderSlipSheet|BetSlipSheet)\(')
                  .hasMatch(source(f.path)))
            f.path,
      ];
      expect(direct, isEmpty,
          reason: 'a slip built outside show() skips its Ledger gate');
      for (final path in [
        ...dartFiles('lib/screens/share').map((f) => f.path),
        'lib/screens/home/components/kute_bar_trade_row.dart',
        'lib/screens/shared/kute_bar_context.dart',
        'lib/screens/shared/kute_share_actions.dart',
      ]) {
        final text = source(path);
        expect(text, isNot(contains('hyperliquidTradingProvider')),
            reason: path);
        expect(text, isNot(contains('polymarketTradingProvider')),
            reason: path);
      }
    });
  });
}
