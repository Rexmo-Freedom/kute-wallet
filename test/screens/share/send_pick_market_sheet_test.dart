// Send a prediction or an investment from Send (send_pick_market_sheet.dart;
// founder, 7 November 2026: "this is still not the search one just adapted
// to sending, should be basically the same"). It IS the search sheet
// (unified_search_screen.dart) in send mode: the first steps' heading
// ("Pick a gift for Maria", "Pick a gift"; founder, 8 November 2026), the
// composer with Sal reading "Search predictions and investments", no
// Connect your own AI card, the
// same Moving now grid and Trending predictions with their gauges, the
// same results (markets only, never Transactions). A market tapped opens
// ITS PAGE in send mode (its slip's primary sends the pick; slip_share
// .dart, its own tests): the side is picked there, nothing chosen for the
// person. A venue closed to this person is left out (its slip could only
// send the market's card).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/search/components/search_composer.dart';
import 'package:kute/screens/search/components/search_rows.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/share/send_pick_market_sheet.dart';
import 'package:kute/screens/share/send_pick_session.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/receive_surface.dart'
    show SheetTitleHeader;
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/search_recent_store.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';

import '../../helpers/runtime_policy_fixture.dart';
import 'share_test_harness.dart';

final _l10n = AppLocalizationsEn();

const _event = PolymarketEvent(
  id: 'e1',
  slug: 'btc-100k',
  title: 'BTC 100k',
  volume: 1000,
  liquidity: 500,
  category: 'crypto',
  conditionId: 'c1',
  outcomes: [
    PolymarketOutcome(name: 'Yes', price: 0.3),
    PolymarketOutcome(name: 'No', price: 0.7),
  ],
);

/// Only the venue's search finds it: it is not in the trending feed.
const _lula = PolymarketEvent(
  id: 'e2',
  slug: 'lula-wins',
  title: 'Will Lula win the 2026 election?',
  volume: 1000,
  liquidity: 500,
  category: 'politics',
  conditionId: 'c2',
  outcomes: [
    PolymarketOutcome(name: 'Yes', price: 0.41),
    PolymarketOutcome(name: 'No', price: 0.59),
  ],
);

const _market = HlMarket(
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

const _tesla = HlMarketSearchResult(
  coin: 'TSLA',
  wireCoin: 'xyz:TSLA',
  kind: HlMarketKind.perp,
  isStock: true,
  name: 'Tesla',
  category: 'stocks',
  iconUrl: null,
  markPx: 250,
  dayChangePct: 0.01,
);

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

class _Feed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) =>
      const PolyFeedState(events: [_event], done: true);
}

/// The sheet's providers: the trending feed and the universe while nothing
/// is typed; "lula" finds the Lula market, "tsla" a stock, anything else
/// nothing.
final _overrides = <Override>[
  aiEnabledProvider.overrideWith((_) async => true),
  sportsLiveProvider.overrideWith(_Sports.new),
  unifiedSearchResultsProvider
      .overrideWith((_) async => UnifiedSearchResults.empty),
  globalMarketResultsProvider.overrideWith((ref) =>
      ref.watch(searchQueryProvider).toLowerCase().contains('lula')
          ? const AsyncValue.data([GlobalMarketSearchResult(_lula)])
          : const AsyncValue.data(<GlobalMarketSearchResult>[])),
  globalHyperliquidResultsProvider.overrideWith((ref) =>
      ref.watch(searchQueryProvider).toLowerCase().contains('tsla')
          ? const AsyncValue.data([_tesla])
          : const AsyncValue.data(<HlMarketSearchResult>[])),
  hyperliquidAllMarketsProvider.overrideWith((_) => []),
  hyperliquidBrowseUniverseProvider
      .overrideWith((_) => const AsyncValue.data([_market])),
  hyperliquidSparklineStoreProvider.overrideWith(
      (_) => HlSparklineStore(fetch: (_) async => const [1.0, 2.0, 3.0])),
  polyBrowseFeedProvider.overrideWith(_Feed.new),
];

class _Launcher extends StatelessWidget {
  const _Launcher({this.senderLabel, this.onResult});
  final String? senderLabel;
  final ValueChanged<bool?>? onResult;

  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(
          onPressed: () async {
            final sent = await showSendPickMarketSheet(context,
                entrySource: 'dollar_send',
                senderLabel: senderLabel,
                recipientPhone:
                    senderLabel == null ? null : '+351 912 345 678');
            onResult?.call(sent);
          },
          child: const Text('Pick'),
        ),
      );
}

void main() {
  // Moving now lists only markets with a logo of their own: the movers'
  // logos are known.
  setUp(() {
    for (final m in [_market]) {
      HlIconAvailability.debugSeed(m);
    }
  });
  tearDown(HlIconPrefetch.debugReset);
  late ShareTestEnv env;
  late List<Object> opened;

  Future<void> policy({Set<String> blocked = const {}}) async {
    final service = runtimePolicyFixture(
        blocked: blocked,
        also: const {'polymarket.browse', 'hyperliquid.browse'});
    RuntimeCapabilitiesService.debugInstance = service;
    expect(await service.refresh(), isTrue);
  }

  setUpAll(
      () async => expect(await AdvisorInputGuard.isSafe('lula'), isTrue));

  setUp(() async {
    env = setUpShareTest();
    opened = [];
    await policy();
    SendPickSession.debugOpenMarket = opened.add;
    SearchRecentStore.entries.value = const [];
    // A sheet a test left open never closed its OpenOnce slot.
    OpenOnce.reset();
  });

  tearDown(() {
    tearDownShareTest();
    RuntimeCapabilitiesService.debugInstance = null;
    SendPickSession.debugOpenMarket = null;
    SearchRecentStore.entries.value = const [];
  });

  Future<void> open(WidgetTester tester,
      {String? senderLabel, ValueChanged<bool?>? onResult}) async {
    await pumpShareWidget(
        tester, env, _Launcher(senderLabel: senderLabel, onResult: onResult),
        overrides: _overrides);
    await tester.tap(find.text('Pick'));
    await settle(tester);
    await settle(tester);
    expect(find.byType(UnifiedSearchSurface), findsOneWidget);
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(
        find.descendant(
            of: find.byType(KuteSearchComposer),
            matching: find.byType(TextField)),
        text);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
      'the search sheet in send mode: the first steps heading, the composer '
      'with Sal, no Connect your own AI; Moving now and Trending predictions '
      'while nothing is typed; typing runs the same searches, markets only',
      (tester) async {
    await open(tester);
    expect(env.paramsOf('send_pick_market_opened').single,
        containsPair('source', 'send'));
    // The first steps' heading says what it is, once: no chip, no subtitle.
    expect(find.widgetWithText(SheetTitleHeader, _l10n.sendPickSheetTitle),
        findsOneWidget);
    expect(find.byKey(const ValueKey('send-pick-chip')), findsNothing);
    expect(find.text(_l10n.sendPickChipFriend), findsNothing);
    // The title and the search line share one left edge.
    expect(
        tester.getTopLeft(find.byType(KuteSearchComposer)).dx,
        moreOrLessEquals(
            tester.getTopLeft(find.text(_l10n.sendPickSheetTitle)).dx,
            epsilon: 0.5));
    expect(find.text(_l10n.sendPickMarket), findsNothing);
    expect(find.text(_l10n.sendPickMarketHow), findsNothing);
    // The search sheet's own composer, Sal in it, the hint adapted.
    final composer =
        tester.widget<KuteSearchComposer>(find.byType(KuteSearchComposer));
    expect(composer.aiEnabled, isTrue);
    expect(composer.hint, _l10n.sendPickSearchHint);
    expect(find.byKey(const ValueKey('search-home-connect-ai')), findsNothing);
    expect(find.text(_l10n.searchHomeMovingNow), findsOneWidget);
    expect(find.byType(SearchMoverGrid), findsOneWidget);
    // No way out of the send to Investing.
    expect(find.text(_l10n.seeAll), findsNothing);
    expect(find.text(_l10n.searchHomeTrendingPredictions), findsOneWidget);
    expect(find.widgetWithText(SearchPredictionRow, 'BTC 100k'),
        findsOneWidget);

    // A market the trending feed does not hold: the venue's search.
    await search(tester, 'lula');
    expect(
        find.widgetWithText(
            SearchPredictionRow, 'Will Lula win the 2026 election?'),
        findsOneWidget);
    expect(find.text('BTC 100k'), findsNothing);

    await search(tester, 'tsla');
    expect(find.widgetWithText(SearchInvestingRow, 'Tesla'), findsOneWidget);

    await search(tester, 'zzz');
    expect(find.byType(SearchEmptyState), findsOneWidget);
  });

  testWidgets(
      'a prediction found by search opens its page in send mode, where the '
      'side is picked (nothing chosen here); the heading names the contact',
      (tester) async {
    await open(tester, senderLabel: 'Maria');
    expect(find.widgetWithText(SheetTitleHeader, 'Pick a gift for Maria'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('send-pick-chip')), findsNothing);
    await search(tester, 'lula');
    await tester.tap(find.text('Will Lula win the 2026 election?'));
    await settle(tester);
    expect(env.paramsOf('send_pick_market_picked').single,
        {'venue': 'polymarket', 'searched': true});
    expect(opened.single, same(_lula));
    expect(env.fake.calls, isEmpty);
    // Nothing identifying reaches an event.
    for (final e in env.events) {
      final values = e.$2?.values.map((v) => '$v').join(' ') ?? '';
      expect(values, isNot(contains('912')));
      expect(values, isNot(contains('Maria')));
    }
  });

  testWidgets('the heading\'s X closes the sheet, as a send not made',
      (tester) async {
    bool? result;
    await open(tester, senderLabel: 'Maria', onResult: (r) => result = r);
    await tester.tap(find.byKey(SheetTitleHeader.closeKey));
    await settle(tester);
    expect(find.byType(UnifiedSearchSurface), findsNothing);
    expect(result, isFalse);
  });

  testWidgets('an investment from Moving now opens its own page',
      (tester) async {
    await open(tester);
    await tester.tap(find
        .descendant(
            of: find.byType(SearchMoverGrid), matching: find.text('ETH'))
        .first);
    await settle(tester);
    expect(env.paramsOf('send_pick_market_picked').single,
        {'venue': 'hyperliquid', 'searched': false});
    expect((opened.single as HlMarket).wireCoin, 'ETH');
  });

  testWidgets(
      'a refused trade lists on: Predictions refused, both venues listed; '
      'the market\'s slip says why', (tester) async {
    await tester.runAsync(() => policy(blocked: {'polymarket.trade'}));
    expect(sendPickOffered(RuntimeCapabilitiesService.instance), isTrue);
    await open(tester);
    expect(find.text(_l10n.searchHomeTrendingPredictions), findsOneWidget);
    expect(find.byType(SearchPredictionRow), findsWidgets);
    expect(find.byType(SearchMoverGrid), findsOneWidget);
  });

  testWidgets(
      'a venue whose browse is closed is left out, as the plain search leaves '
      'it: Predictions shut, Investing only', (tester) async {
    await tester.runAsync(() => policy(blocked: {'polymarket.browse'}));
    expect(sendPickOffered(RuntimeCapabilitiesService.instance), isTrue);
    await open(tester);
    expect(find.text(_l10n.searchHomeTrendingPredictions), findsNothing);
    expect(find.byType(SearchPredictionRow), findsNothing);
    expect(find.byType(SearchMoverGrid), findsOneWidget);
    await search(tester, 'lula');
    expect(find.byType(SearchPredictionRow), findsNothing);
  });

  testWidgets('closed without a send: the Send screen stays (false)',
      (tester) async {
    bool? result;
    await open(tester, onResult: (r) => result = r);
    Navigator.of(tester.element(find.byType(UnifiedSearchSurface))).pop();
    await settle(tester);
    expect(result, isFalse);
  });

  test('both venues\' browse closed: nothing to list; trade never counts',
      () async {
    await policy(blocked: {'polymarket.browse', 'hyperliquid.browse'});
    expect(sendPickOffered(RuntimeCapabilitiesService.instance), isFalse);
    await policy(blocked: {'hyperliquid.browse'});
    expect(sendPickOffered(RuntimeCapabilitiesService.instance), isTrue);
    await policy(blocked: {'polymarket.trade', 'hyperliquid.trade'});
    expect(sendPickOffered(RuntimeCapabilitiesService.instance), isTrue);
  });
}
