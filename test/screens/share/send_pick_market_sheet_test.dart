// Send a prediction or an investment from the dollar send (send_pick
// _market_sheet.dart; founder, 4 November 2026: "search the prediction
// you want and open it, use the stuff and design we already have"): the
// search sheet's line and rows, Trending predictions and Moving now while
// nothing is typed, the venues' own searches under Predictions and
// Investing once something is, Sal's sad face when nothing matches. A
// market tapped opens ITS PAGE (founder, 5 November 2026: the slip is the
// one place a prediction is composed; it sends with its round Sal
// button): the side is picked there, nothing chosen for the person, and
// the header says how it sends. A venue closed to this person is left
// out (the slip there could only send the market's card).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketSearchProvider;
import 'package:kute/screens/search/components/search_composer.dart';
import 'package:kute/screens/search/components/search_rows.dart';
import 'package:kute/screens/share/send_pick_market_sheet.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

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

/// The venues' searches: "lula" finds the Lula market, "tsla" a stock,
/// anything else nothing.
final _searches = [
  polymarketSearchProvider.overrideWith((ref, q) async =>
      q.toLowerCase().contains('lula') ? const [_lula] : const []),
  hyperliquidMarketSearchProvider.overrideWith((ref, q) async =>
      q.toLowerCase().contains('tsla')
          ? const [
              HlMarketSearchResult(
                coin: 'TSLA',
                wireCoin: 'xyz:TSLA',
                kind: HlMarketKind.perp,
                isStock: true,
                name: 'Tesla',
                category: 'stocks',
                iconUrl: null,
                markPx: 250,
                dayChangePct: 0.01,
              ),
            ]
          : const <HlMarketSearchResult>[]),
];

class _Launcher extends StatelessWidget {
  const _Launcher({this.senderLabel, this.recipientPhone});
  final String? senderLabel;
  final String? recipientPhone;

  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(
          onPressed: () => showSendPickMarketSheet(context,
              entrySource: 'dollar_send',
              senderLabel: senderLabel,
              recipientPhone: recipientPhone),
          child: const Text('Pick'),
        ),
      );
}

void main() {
  late ShareTestEnv env;
  late List<Object> opened;

  Future<void> policy({Set<String> blocked = const {}}) async {
    final service = runtimePolicyFixture(
        blocked: blocked,
        also: const {'polymarket.browse', 'hyperliquid.browse'});
    RuntimeCapabilitiesService.debugInstance = service;
    expect(await service.refresh(), isTrue);
  }

  setUp(() async {
    env = setUpShareTest();
    opened = [];
    await policy();
    SendPickMarketSheet.debugFeeds =
        (predictions: [_event], investing: [_market]);
    SendPickMarketSheet.debugOpenMarket = opened.add;
  });

  tearDown(() {
    tearDownShareTest();
    RuntimeCapabilitiesService.debugInstance = null;
    SendPickMarketSheet.debugFeeds = null;
    SendPickMarketSheet.debugOpenMarket = null;
  });

  Future<void> open(WidgetTester tester,
      {String? senderLabel, String? recipientPhone}) async {
    await pumpShareWidget(
        tester,
        env,
        _Launcher(senderLabel: senderLabel, recipientPhone: recipientPhone),
        overrides: _searches);
    await tester.tap(find.text('Pick'));
    await settle(tester);
    expect(find.byType(SendPickMarketSheet), findsOneWidget);
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(
        find.byKey(const ValueKey('send-pick-market-search')), text);
    await settle(tester);
  }

  testWidgets(
      'the search sheet\'s line and rows: Trending predictions and Moving '
      'now while nothing is typed; typing runs the venues\' searches under '
      'Predictions and Investing; nothing found is the empty state',
      (tester) async {
    await open(tester);
    expect(env.paramsOf('send_pick_market_opened').single,
        containsPair('source', 'send'));
    expect(find.byType(KuteSearchComposer), findsOneWidget);
    expect(find.text(_l10n.sendPickMarketSearchHint), findsOneWidget);
    expect(find.text(_l10n.searchHomeTrendingPredictions), findsOneWidget);
    expect(find.text(_l10n.searchHomeMovingNow), findsOneWidget);
    expect(find.widgetWithText(SearchPredictionRow, 'BTC 100k'),
        findsOneWidget);
    expect(find.byType(SearchInvestingRow), findsOneWidget);

    // A market the trending feed does not hold: the venue's search.
    await search(tester, 'lula');
    expect(find.text(_l10n.predictions), findsOneWidget);
    expect(
        find.widgetWithText(
            SearchPredictionRow, 'Will Lula win the 2026 election?'),
        findsOneWidget);
    expect(find.text('BTC 100k'), findsNothing);

    await search(tester, 'tsla');
    expect(find.text(_l10n.trading), findsOneWidget);
    expect(find.widgetWithText(SearchInvestingRow, 'Tesla'), findsOneWidget);

    await search(tester, 'zzz');
    expect(find.text(_l10n.sendPickMarketNoResults), findsOneWidget);
    expect(find.byType(SearchEmptyState), findsOneWidget);
  });

  testWidgets(
      'a prediction found by search opens its page, where the side is '
      'picked (nothing chosen here); the header says the slip sends it',
      (tester) async {
    await open(tester,
        senderLabel: 'Maria', recipientPhone: '+351 912 345 678');
    expect(find.text(_l10n.sendPickMarketHow), findsOneWidget);
    await search(tester, 'lula');
    await tester.tap(find.text('Will Lula win the 2026 election?'));
    await settle(tester);
    expect(env.paramsOf('send_pick_market_picked').single,
        {'venue': 'polymarket', 'searched': true});
    expect(opened.single, same(_lula));
    // No send of its own: the slip is where it is composed.
    expect(find.byKey(const ValueKey('send-pick-side-step')), findsNothing);
    expect(env.fake.calls, isEmpty);
    // Nothing identifying reaches an event.
    for (final e in env.events) {
      expect(e.$2?.values.map((v) => '$v').join(' ') ?? '',
          isNot(contains('912')));
    }
  });

  testWidgets('an investment opens its own page', (tester) async {
    await open(tester);
    await tester.tap(find.byType(SearchInvestingRow));
    await settle(tester);
    expect(env.paramsOf('send_pick_market_picked').single,
        {'venue': 'hyperliquid', 'searched': false});
    expect((opened.single as HlMarket).wireCoin, 'ETH');
  });

  testWidgets(
      'a venue closed to this person is left out: Predictions blocked, '
      'Investing only', (tester) async {
    await tester.runAsync(() => policy(blocked: {'polymarket.trade'}));
    expect(sendPickOffered(RuntimeCapabilitiesService.instance), isTrue);
    await open(tester);
    expect(find.text(_l10n.searchHomeTrendingPredictions), findsNothing);
    expect(find.byType(SearchPredictionRow), findsNothing);
    expect(find.byType(SearchInvestingRow), findsOneWidget);
  });

  test('both venues closed: nothing to send a prediction on', () async {
    await policy(blocked: {'polymarket.trade', 'hyperliquid.trade'});
    expect(sendPickOffered(RuntimeCapabilitiesService.instance), isFalse);
    await policy(blocked: {'hyperliquid.trade'});
    expect(sendPickOffered(RuntimeCapabilitiesService.instance), isTrue);
  });
}
