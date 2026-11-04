// Sending a prediction or an investment never picks the side for the
// person (founder, 4 November 2026: "it auto-selects No and such"). Send
// to anyone handed a market (send_pick.dart) opens on the side step: what
// is sent over every side it can send, none chosen; a tap is the choice,
// the amount follows with the pick over it and "Change" back to the
// sides; the link carries exactly the side tapped. A position's own side,
// a spot token (Long only) and a candidate's own Yes/No page (the
// candidate) have nothing to choose and open on the amount.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/screens/share/cards/share_card_preview.dart';
import 'package:kute/screens/share/send_pick.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/shared/market_pair_button.dart';

import '../../helpers/kute_bar_test_support.dart';
import 'share_test_harness.dart';

final _l10n = AppLocalizationsEn();

/// A Yes/No market where No leads (the old default picked "No").
const _snow = PolymarketEvent(
  id: 'e1',
  slug: 'snow-lisbon',
  title: 'Will it snow in Lisbon?',
  volume: 1000,
  liquidity: 500,
  category: 'weather',
  conditionId: 'c1',
  outcomes: [
    PolymarketOutcome(name: 'Yes', price: 0.12),
    PolymarketOutcome(name: 'No', price: 0.88),
  ],
);

/// Candidates, each its own Yes/No market, listed out of chance order.
const _election = PolymarketEvent(
  id: 'e2',
  slug: 'brazil-election',
  title: 'Brazil presidential election',
  volume: 1000,
  liquidity: 500,
  category: 'politics',
  conditionId: 'c2',
  outcomes: [
    PolymarketOutcome(name: 'Tarcísio', price: 0.31, noTokenId: 'tn'),
    PolymarketOutcome(name: 'Lula', price: 0.52, noTokenId: 'ln'),
    PolymarketOutcome(name: 'Ciro', price: 0.04, noTokenId: 'cn'),
  ],
);

/// A candidate's own Yes/No page, as the event page builds it.
const _lulaPage = PolymarketEvent(
  id: 'e2-Lula',
  slug: 'brazil-election',
  title: 'Lula',
  volume: 1000,
  liquidity: 500,
  category: 'politics',
  conditionId: 'c2',
  outcomes: [
    PolymarketOutcome(name: 'Yes', price: 0.52),
    PolymarketOutcome(name: 'No', price: 0.48),
  ],
  isSyntheticBinary: true,
);

HlMarket _hl(String coin, HlMarketKind kind) => HlMarket(
      coin: coin,
      wireCoin: kind == HlMarketKind.spot ? '@107' : coin,
      assetId: 1,
      kind: kind,
      szDecimals: 4,
      maxLeverage: 25,
      onlyIsolated: false,
      markPx: 3000,
      midPx: 3000,
      prevDayPx: 2900,
      dayNtlVlm: 1e9,
    );

void main() {
  late ShareTestEnv env;
  late List<String> shared;

  setUp(() {
    env = setUpShareTest();
    shared = [];
    ShareCardShare.debugSharer = (image, text) async {
      shared.add(text);
      return 'success';
    };
  });

  tearDown(tearDownShareTest);

  Future<void> open(WidgetTester tester, SendPickMarket market) =>
      pumpShareWidget(tester, env,
          SendToAnyoneSheet(kind: ShareLinkKind.dollars, market: market));

  Future<void> typeAmount(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await settle(tester);
  }

  Future<Map<String, Object?>> createLink(WidgetTester tester) async {
    await tester.tap(kuteBarPrimaryWithText(_l10n.continueLabel));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText(_l10n.shareCreateLink));
    await settle(tester);
    await shareCardAndWait(tester, shared);
    return env.fake.calls.where((c) => c.$1 == 'create').single.$2;
  }

  testWidgets(
      'a Yes/No market where No leads: the side step shows the market over '
      'Yes and No as the page\'s pair, equal, nothing chosen and no amount; '
      'No tapped is No on the amount step, Change goes back, Yes tapped is '
      'the side the link carries', (tester) async {
    await open(tester, SendPickMarket.prediction(_snow));
    expect(find.text(_l10n.sendAPrediction), findsOneWidget);
    expect(find.text(_l10n.sendPickSideSub), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('send-pick-market-header')),
            matching: find.text('Will it snow in Lisbon?')),
        findsOneWidget);
    final buttons = tester
        .widgetList<MarketPairButton>(find.byType(MarketPairButton))
        .toList();
    expect(buttons.map((b) => b.label), [_l10n.yes, _l10n.betNo]);
    expect(buttons.map((b) => b.value), ['12%', '88%']);
    // No keypad, no pick and no Continue until a side is tapped.
    expect(find.text('5'), findsNothing);
    expect(find.byKey(const ValueKey('share-pick-line')), findsNothing);
    expect(kuteBarPrimary, findsNothing);

    await tester.tap(find.byKey(const ValueKey('send-pick-side-1')));
    await settle(tester);
    expect(find.text('No on Will it snow in Lisbon?'), findsOneWidget);
    expect(find.text('88% chance'), findsOneWidget);
    expect(find.text(_l10n.sendPickAmountSub), findsOneWidget);
    expect(env.paramsOf('send_pick_side_picked').single,
        {'venue': 'polymarket', 'side': 'buy', 'sides': 2});

    // Change: back to the two sides, still nothing chosen.
    await tester.tap(find.byKey(const ValueKey('share-pick-change')));
    await settle(tester);
    expect(find.byKey(const ValueKey('send-pick-side-step')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('send-pick-side-0')));
    await settle(tester);
    expect(find.text('Yes on Will it snow in Lisbon?'), findsOneWidget);

    await typeAmount(tester, '12');
    final create = await createLink(tester);
    expect(create['marketSlug'], 'snow-lisbon');
    expect(create['venue'], 'polymarket');
    expect(create['outcome'], 'Yes');
    expect(create['outcomeIndex'], 0);
    expect(create['side'], 'buy');
    expect(create['amountMinor'], 1200);
  });

  testWidgets(
      'a market of candidates: one row per outcome, the biggest chance '
      'first, none chosen; the row tapped is the outcome sent with its own '
      'index', (tester) async {
    await open(tester, SendPickMarket.prediction(_election));
    expect(find.text(_l10n.sendPickOutcomeSub), findsOneWidget);
    expect(find.byType(MarketPairButton), findsNothing);
    final rows = [
      for (var i = 0; i < 3; i++)
        tester.getTopLeft(find.byKey(ValueKey('send-pick-outcome-$i'))).dy
    ];
    expect(rows, orderedEquals([...rows]..sort()));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('send-pick-outcome-0')),
            matching: find.text('Lula')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('send-pick-outcome-1')));
    await settle(tester);
    expect(find.text('Tarcísio on Brazil presidential election'),
        findsOneWidget);
    await typeAmount(tester, '5');
    final create = await createLink(tester);
    expect(create['outcome'], 'Tarcísio');
    expect(create['outcomeIndex'], 0);
  });

  testWidgets(
      'a candidate\'s own Yes/No page sends the candidate: no side step, '
      'the event names it on the link', (tester) async {
    final market = SendPickMarket.prediction(_lulaPage);
    expect(market.needsSide, isFalse);
    await open(tester, market);
    expect(find.byKey(const ValueKey('send-pick-side-step')), findsNothing);
    expect(find.text('Lula on Lula'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-pick-change')), findsNothing);
    await typeAmount(tester, '5');
    final create = await createLink(tester);
    expect(create['outcome'], 'Lula');
    expect(create.containsKey('outcomeIndex'), isFalse);
  });

  testWidgets(
      'Investing: a perp offers Long and Short as the pair, equal; a spot '
      'token has Long alone and opens on the amount', (tester) async {
    await open(tester,
        SendPickMarket.investing(_hl('ETH', HlMarketKind.perp), l10n: _l10n));
    expect(find.text(_l10n.sendAnInvestment), findsOneWidget);
    final labels = tester
        .widgetList<MarketPairButton>(find.byType(MarketPairButton))
        .map((b) => b.label)
        .toList();
    expect(labels, [_l10n.longLabel, _l10n.shortLabel]);
    await tester.tap(find.byKey(const ValueKey('send-pick-side-1')));
    await settle(tester);
    expect(find.text('Short on Ethereum'), findsOneWidget);
    await typeAmount(tester, '5');
    final create = await createLink(tester);
    expect(create['venue'], 'hyperliquid');
    expect(create['outcome'], _l10n.shortLabel);
    expect(create['side'], 'short');
    expect(create['marketSlug'], 'ETH');

    final spot =
        SendPickMarket.investing(_hl('HYPE', HlMarketKind.spot), l10n: _l10n);
    expect(spot.sides.map((s) => s.side), ['long']);
    expect(spot.needsSide, isFalse);
  });

  testWidgets(
      'a position\'s own side is the pick: straight to the amount, "Send '
      'this prediction", no Change', (tester) async {
    final market = SendPickMarket.prediction(_snow,
        chosen: const SendPickSide(
            label: 'No', side: 'buy', index: 1, chance: 0.88));
    await open(tester, market);
    expect(find.text(_l10n.sendThisPrediction), findsOneWidget);
    expect(find.byKey(const ValueKey('send-pick-side-step')), findsNothing);
    expect(find.text('No on Will it snow in Lisbon?'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-pick-change')), findsNothing);
  });

  test('the sides of a market are never ordered or chosen by the lead', () {
    final sides = sendPickPredictionSides(_snow);
    expect(sides.map((s) => s.label), ['Yes', 'No']);
    expect(SendPickMarket.prediction(_snow).chosen, isNull);
    expect(sendPickSidesLine(_l10n, SendPickMarket.prediction(_snow)),
        'Yes 12% · No 88%');
    expect(sendPickWireIsSpot('@107'), isTrue);
    expect(sendPickWireIsSpot('PURR/USDC'), isTrue);
    expect(sendPickWireIsSpot('xyz:XYZ100'), isFalse);
    expect(sendPickWireIsSpot('BTC'), isFalse);
  });
}
