// Send a prediction or an investment from the dollar send (send_pick
// _market_sheet.dart; founder, 4 November 2026: "search the prediction
// you want and open it, use the stuff and design we already have"): the
// search sheet's line and rows, Trending predictions and Moving now while
// nothing is typed, the venues' own searches under Predictions and
// Investing once something is, Sal's sad face when nothing matches. A
// market tapped opens to send with NO SIDE CHOSEN (Yes and No equal; Long
// and Short); the side tapped is the one on the link; a contact picked
// before rides along as the label, and the created row keeps the number
// for WhatsApp / SMS without it ever reaching the backend or an event.

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
import 'package:kute/screens/share/cards/share_card_preview.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/share/share_link_resend.dart';
import 'package:kute/screens/shared/market_pair_button.dart';
import 'package:kute/services/share_links_store.dart';

import '../../helpers/kute_bar_test_support.dart';
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
  final shared = <String>[];
  final launched = <Uri>[];

  setUp(() {
    env = setUpShareTest();
    shared.clear();
    launched.clear();
    ShareCardShare.debugSharer = (image, text) async {
      shared.add(text);
      return 'success';
    };
    debugShareLinkResendLauncher = (uri) async {
      launched.add(uri);
      return true;
    };
    SendPickMarketSheet.debugFeeds =
        (predictions: [_event], investing: [_market]);
  });

  tearDown(() {
    tearDownShareTest();
    debugShareLinkResendLauncher = null;
    SendPickMarketSheet.debugFeeds = null;
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
      'a prediction found by search opens to send with nothing chosen (Yes '
      'and No equal, no amount); No tapped is the side on the link, with the '
      'contact picked before; the row keeps the number for WhatsApp, the '
      'backend never sees it', (tester) async {
    await open(tester,
        senderLabel: 'Maria', recipientPhone: '+351 912 345 678');
    await search(tester, 'lula');
    await tester.tap(find.text('Will Lula win the 2026 election?'));
    await settle(tester);
    expect(env.paramsOf('send_pick_market_picked').single,
        {'venue': 'polymarket', 'searched': true});
    expect(find.byType(SendToAnyoneSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('send-pick-side-step')), findsOneWidget);
    final pair = tester
        .widgetList<MarketPairButton>(find.byType(MarketPairButton))
        .toList();
    expect(pair.map((b) => b.label), [_l10n.yes, _l10n.betNo]);
    expect(pair.map((b) => b.value), ['41%', '59%']);
    expect(find.byKey(const ValueKey('share-pick-line')), findsNothing);
    expect(kuteBarPrimary, findsNothing);

    await tester.tap(find.byKey(const ValueKey('send-pick-side-1')));
    await settle(tester);
    expect(find.text('No on Will Lula win the 2026 election?'),
        findsOneWidget);
    await tester.tap(find.text('1'));
    await settle(tester);
    await tester.tap(find.text('2'));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText(_l10n.continueLabel));
    await settle(tester);
    // The contact's first name is the label already.
    final field = tester.widget<TextField>(find.descendant(
        of: find.byKey(const ValueKey('share-name-field')),
        matching: find.byType(TextField)));
    expect(field.controller!.text, 'Maria');

    await tester.tap(kuteBarPrimaryWithText(_l10n.shareCreateLink));
    await settle(tester);
    await shareCardAndWait(tester, shared);
    final create = env.fake.calls.where((c) => c.$1 == 'create').single.$2;
    expect(create['kind'], 'dollars');
    expect(create['amountMinor'], 1200);
    expect(create['marketSlug'], 'lula-wins');
    expect(create['venue'], 'polymarket');
    expect(create['outcome'], 'No');
    expect(create['outcomeIndex'], 1);
    expect(create['side'], 'buy');
    expect(create['senderLabel'], 'Maria');
    expect(create.values.map((v) => '$v').join(' '), isNot(contains('912')));
    final row = ShareLinksStore.all().single;
    expect(row.recipientPhone, '+351 912 345 678');
    expect(row.label, 'Maria');
    for (final e in env.events) {
      expect(e.$2?.values.map((v) => '$v').join(' ') ?? '',
          isNot(contains('912')));
    }
    expect(shared.single, contains('Maria'));

    // The receipt: Send again via WhatsApp opens wa.me with the number and
    // the text; SMS the composer.
    await tester.tap(find.byKey(const ValueKey('share-again-whatsapp')));
    await settle(tester);
    expect(launched.single.host, 'wa.me');
    expect(launched.single.path, '/351912345678');
    expect(launched.single.queryParameters['text'], contains('Maria'));
    await tester.tap(find.byKey(const ValueKey('share-again-sms')));
    await settle(tester);
    expect(launched.last.scheme, 'sms');
    expect(launched.last.path, '+351912345678');
  });

  testWidgets(
      'an investment opens to send with Long and Short, equal, nothing '
      'chosen; Short tapped is the side on the link', (tester) async {
    await open(tester);
    await tester.tap(find.byType(SearchInvestingRow));
    await settle(tester);
    expect(find.text(_l10n.sendAnInvestment), findsOneWidget);
    final labels = tester
        .widgetList<MarketPairButton>(find.byType(MarketPairButton))
        .map((b) => b.label)
        .toList();
    expect(labels, [_l10n.longLabel, _l10n.shortLabel]);
    await tester.tap(find.byKey(const ValueKey('send-pick-side-1')));
    await settle(tester);
    expect(find.text('Short on Ethereum'), findsOneWidget);
    await tester.tap(find.text('5'));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText(_l10n.continueLabel));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText(_l10n.shareCreateLink));
    await settle(tester);
    await shareCardAndWait(tester, shared);
    final create = env.fake.calls.where((c) => c.$1 == 'create').single.$2;
    expect(create['venue'], 'hyperliquid');
    expect(create['side'], 'short');
    expect(create['outcome'], _l10n.shortLabel);
    expect(create['marketSlug'], 'ETH');
    expect(create['senderLabel'], isNull);
  });
}
