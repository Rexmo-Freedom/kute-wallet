// The Dollars Overview shows what is being placed (founder, 9 November
// 2026: "On the Overview we must show exactly there what bets or
// investments are in progress of being implemented, as soon as they
// touch"), as ONE card from the accept to the listed position (founder,
// 10 November 2026, on 2.2.0 (98): "After the investment is placed, the old
// one stays there for a bit, until it eventually leaves. This can't be,
// show the actual one, with placing and when it's placed, we just show
// placed"): the order holds one slot, keyed by its position, drawn by the
// position's own row widget: "Placing" from the accept, placed the moment
// it fills (the fill's own figures), then the listed position in place,
// never a second or a stale card. A tap while it places opens its money
// journey; it counts toward the four; failed or cancelled, it goes.
// Predictions and Investing alike.
//
// A filled order hands over once (founder, 10 November 2026: sold, the
// Overview still showed "Prediction placed"): the position listing, or its
// sale, hands it over for good; the card waits for its position at most
// kDollarsFilledCardHold and leaves on time without another rebuild.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart'
    show HlFill, HlPerpPosition;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition, polymarketActivePositionsProvider;
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show HlPositionRow, PlacingBetRow, PolyPositionRow;
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/standing_order_journey.dart';
import 'package:kute/screens/usd/components/dollars_activity_tab.dart';
import 'package:kute/screens/usd/usd_account_screen.dart' show InvestmentsBody;
import 'package:kute/services/standing_orders/standing_orders_provider.dart';

import '../../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import 'investments_harness.dart';

HlPerpPosition _perp(String coin, double margin, {double szi = 1}) =>
    HlPerpPosition(
    coin: coin,
    szi: szi,
    entryPx: 100,
    positionValue: margin * 2,
    unrealizedPnl: 0,
    returnOnEquity: 0,
    liquidationPx: null,
    marginUsed: margin,
    leverageType: 'cross',
    leverageValue: 2,
    maxLeverage: 40);

/// The account's positions, changed by the test (a fill landing).
class _Trading extends PortfolioTestTrading {
  _Trading(super.initial);

  void land(List<HlPerpPosition> positions) => state = AsyncData(
      HyperliquidTradingState(isInitialized: true, positions: positions));
}

StandingOrder _prediction(
        {String id = 'so_p',
        StandingOrderState state = StandingOrderState.funding,
        DateTime? at}) =>
    StandingOrder(
      id: id,
      walletId: 'spending',
      venue: StandingOrderVenue.predictions,
      marketKey: 'tok-$id',
      marketTitle: 'Will it rain tomorrow?',
      sideLabel: 'Yes',
      isBuy: true,
      size: 19.23,
      approvedPrice: 0.52,
      amountUsd: 10,
      orderKind: 'market',
      state: state,
      createdAt: at ?? DateTime.now(),
      updatedAt: at ?? DateTime.now(),
    );

StandingOrder _investing(
        {StandingOrderState state = StandingOrderState.funding,
        String coin = 'ETH',
        String? positionCoin,
        bool isBuy = true}) =>
    StandingOrder(
      id: 'so_i',
      walletId: 'spending',
      venue: StandingOrderVenue.investing,
      marketKey: coin,
      positionCoin: positionCoin,
      marketTitle: '$coin · Perp',
      sideLabel: isBuy ? 'long' : 'short',
      isBuy: isBuy,
      size: 20,
      approvedPrice: 3000,
      amountUsd: 20,
      orderKind: 'market',
      state: state,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      leverage: 2,
      marketKind: 'perp',
    );

/// The Predictions positions the account lists, changed by the test (the
/// fill landing, the sale).
final _positions = StateProvider<List<PolymarketPosition>>((_) => const []);

PolymarketPosition _poly(String token) => PolymarketPosition(
    marketId: token,
    marketQuestion: 'Will it rain tomorrow?',
    outcome: 'Yes',
    size: 19.23,
    avgPrice: 0.52,
    currentPrice: 0.52,
    pnl: 0,
    pnlPercent: 0,
    isResolved: false,
    tokenId: token);

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState(live: false, prices: {});
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void pause() {}
  @override
  void resume() {}
}

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(InvestmentsBody, skipOffstage: false)));

/// The same slot: the same place and width. Its height follows its words,
/// which wrap rather than cut (founder, 10 November 2026, on 2.2.0 (99):
/// "on the overview the text is cut"), so "Prediction placed" may take a
/// line more than "Placing".
void expectSameSlot(Rect actual, Rect slot) {
  expect(actual.topLeft, slot.topLeft);
  expect(actual.width, slot.width);
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  final squares = find.byKey(const ValueKey('dollars-activity-squares'));
  Finder inSquares(Finder f) => find.descendant(of: squares, matching: f);

  /// The keys of the squares' cards, in order: every card is keyed by
  /// the position it is (or places into).
  List<String> order(WidgetTester tester) => [
        for (final e in inSquares(find.byWidgetPredicate((w) =>
                w.key is ValueKey<String> &&
                ((w.key! as ValueKey<String>).value.startsWith('poly-') ||
                    (w.key! as ValueKey<String>).value.startsWith('hl-'))))
            .evaluate())
          (e.widget.key! as ValueKey<String>).value,
      ];

  Finder text(String key, String words) => find.descendant(
      of: inSquares(find.byKey(ValueKey(key))),
      matching: find.textContaining(words));

  Finder figure(String key, String value) => find.descendant(
      of: inSquares(find.byKey(ValueKey(key))),
      matching:
          find.byWidgetPredicate((w) => w is RollingFigure && w.text == value));

  group('pure', () {
    final now = DateTime(2026, 11, 9, 12);
    StandingOrder at(StandingOrder o, StandingOrderState s, Duration ago) =>
        o.copyWith(state: s, updatedAt: now.subtract(ago));

    List<String?> ids(List<DollarsOverviewSlot> slots) =>
        [for (final s in slots) s.order?.id ?? s.id];

    test('one slot per order, newest first, keyed by its position; open '
        'ones always, a fresh fill until it hands over; failed, cancelled '
        'and old fills never; then the ranked positions', () {
      final a = at(_prediction(id: 'a'), StandingOrderState.funding,
          Duration.zero);
      final b = at(_investing(), StandingOrderState.posting, Duration.zero);
      final filled = at(_prediction(id: 'f'), StandingOrderState.filled,
          const Duration(minutes: 1));
      final old = at(_prediction(id: 'o'), StandingOrderState.filled,
          const Duration(minutes: 6));
      final failed = at(_prediction(id: 'x'), StandingOrderState.failed,
          Duration.zero);
      final cancelled = at(_prediction(id: 'c'), StandingOrderState.cancelled,
          Duration.zero);
      final all = [old, failed, cancelled, filled, a, b];
      final slots =
          dollarsOverviewSlots(['hl-BTC'], all, listed: {'hl-BTC'}, now: now);
      expect([for (final s in slots) s.id],
          ['hl-ETH', 'poly-tok-a', 'poly-tok-f', 'hl-BTC']);
      expect(ids(slots), ['so_i', 'a', 'f', 'hl-BTC']);
      expect(
          ids(dollarsOverviewSlots(const [], all,
              listed: {}, now: now, handedOver: {'f'})),
          ['so_i', 'a'],
          reason: 'handed over and not listed: its card never returns');
      expect(
          ids(dollarsOverviewSlots(const [], all,
              listed: {}, now: now, investing: false)),
          ['a', 'f']);
    });

    test('the slot is the position the order places into: the listed one, '
        'else the perp, or the spot holding for a spot order', () {
      final perp = _investing(coin: 'HYPE');
      final spot = StandingOrder.fromJson(
          {...perp.toJson(), 'marketKind': 'spot', 'leverage': 1})!;
      expect(dollarsStandingSlotId(perp, {}), 'hl-HYPE');
      expect(dollarsStandingSlotId(spot, {}), 'hl-spot-HYPE');
      expect(dollarsStandingSlotId(perp, {'hl-spot-HYPE'}), 'hl-spot-HYPE');
      expect(dollarsStandingSlotId(_prediction(id: 'p'), {}), 'poly-tok-p');
    });

    test('an order into a position already listed takes that position\'s '
        'slot: one slot, never two', () {
      final open = at(_investing(), StandingOrderState.posting, Duration.zero);
      final slots = dollarsOverviewSlots(['hl-BTC', 'hl-ETH'], [open],
          listed: {'hl-BTC', 'hl-ETH'}, now: now);
      expect([for (final s in slots) s.id], ['hl-ETH', 'hl-BTC']);
      expect(slots.first.order, open);
      expect(slots.last.order, isNull);
    });

    test('filled and listed: the listed slot says placed until the card '
        'hold; sold, or past the hold, the plain position', () {
      final filled = at(_prediction(id: 'f'), StandingOrderState.filled,
          const Duration(seconds: 30));
      final slots = dollarsOverviewSlots(['poly-tok-f'], [filled],
          listed: {'poly-tok-f'}, now: now, handedOver: {'f'});
      expect(slots.single.order, filled);
      expect(
          dollarsOverviewSlots(['poly-tok-f'], [filled],
                  listed: {'poly-tok-f'},
                  now: now,
                  handedOver: {'f'},
                  ended: {'f'})
              .single
              .order,
          isNull,
          reason: 'sold or being sold');
      expect(
          dollarsOverviewSlots(['poly-tok-f'], [filled],
                  listed: {'poly-tok-f'},
                  now: filled.updatedAt.add(kDollarsFilledCardHold),
                  handedOver: {'f'})
              .single
              .order,
          isNull,
          reason: 'past the card hold');
    });

    test('ended: a fill whose position is being sold or was sold after the '
        'accept', () {
      final filled = at(_prediction(id: 'f'), StandingOrderState.filled,
          const Duration(seconds: 30));
      expect(dollarsEndedOrders([filled]), isEmpty);
      expect(dollarsEndedOrders([filled], selling: {'poly-tok-f'}), ['f']);
      expect(
          dollarsEndedOrders([filled], soldAt: {
            'poly-tok-f': filled.createdAt.add(const Duration(seconds: 1))
          }),
          ['f']);
      expect(
          dollarsEndedOrders([filled], soldAt: {
            'poly-tok-f': filled.createdAt.subtract(const Duration(days: 1))
          }),
          isEmpty);
    });

    test('a fresh fill\'s position takes the first slot; the rest ranked',
        () {
      final filled = at(_investing(coin: 'SOL'), StandingOrderState.filled,
          const Duration(minutes: 1));
      expect(
          dollarsPinnedRanked(['hl-BTC', 'hl-ETH', 'hl-SOL'], [filled],
              now: now),
          ['hl-SOL', 'hl-BTC', 'hl-ETH']);
      expect(
          dollarsPinnedRanked(['hl-BTC', 'hl-SOL'], [
            at(_investing(coin: 'SOL'), StandingOrderState.filled,
                const Duration(minutes: 6))
          ], now: now),
          ['hl-BTC', 'hl-SOL'],
          reason: 'after the hold the ranking is back');
    });

    test('a filled card waits for its position at most the card hold, and '
        'once handed over never comes back', () {
      final filled = at(_prediction(id: 'f'), StandingOrderState.filled,
          const Duration(seconds: 30));
      expect(ids(dollarsOverviewSlots(const [], [filled], listed: {}, now: now)),
          ['f']);
      expect(
          dollarsOverviewSlots(const [], [filled],
              listed: {}, now: now, handedOver: {'f'}),
          isEmpty,
          reason: 'the position listed once, then was sold');
      expect(
          dollarsOverviewSlots(const [], [
            at(_prediction(id: 'f'), StandingOrderState.filled,
                kDollarsFilledCardHold)
          ], listed: {}, now: now),
          isEmpty,
          reason: 'past the card hold');
    });

    test('the card hands over when its position lists, is being sold or '
        'was sold after the accept', () {
      final filled = at(_prediction(id: 'f'), StandingOrderState.filled,
          const Duration(seconds: 30));
      final open = at(_prediction(id: 'o'), StandingOrderState.posting,
          Duration.zero);
      expect(dollarsHandingOver([filled, open], listed: {}), isEmpty);
      expect(
          dollarsHandingOver([filled, open],
              listed: {'poly-tok-f', 'poly-tok-o'}),
          ['f'],
          reason: 'an open order is never handed over');
      expect(dollarsHandingOver([filled], listed: {}, selling: {'poly-tok-f'}),
          ['f']);
      expect(
          dollarsHandingOver([filled],
              listed: {},
              soldAt: {
                'poly-tok-f': filled.createdAt.add(const Duration(seconds: 10))
              }),
          ['f']);
      expect(
          dollarsHandingOver([filled], listed: {}, soldAt: {
            'poly-tok-f': filled.createdAt.subtract(const Duration(days: 1))
          }),
          isEmpty,
          reason: 'a sale of an earlier position of the token');
    });

    test('a builder dex (HIP-3) perp: the slot is the coin the account '
        'holds it by ("hl-xyz:NVDA"), never the displayed "hl-NVDA"; filled '
        'and listed, ONE slot (2.2.0 (101): a Nvidia short showed its '
        'placed card beside the listed position)', () {
      final nvda = at(
          _investing(coin: 'NVDA', positionCoin: 'xyz:NVDA', isBuy: false),
          StandingOrderState.filled,
          const Duration(seconds: 10));
      expect(dollarsStandingPositionIds(nvda),
          ['hl-xyz:NVDA', 'hl-spot-NVDA']);
      expect(dollarsStandingSlotId(nvda, {}), 'hl-xyz:NVDA',
          reason: 'not listed yet: the row it will list under');
      final listed = {'hl-BTC', 'hl-xyz:NVDA'};
      final slots = dollarsOverviewSlots(['hl-xyz:NVDA', 'hl-BTC'], [nvda],
          listed: listed, now: now);
      expect([for (final s in slots) s.id], ['hl-xyz:NVDA', 'hl-BTC']);
      expect(slots.first.order, nvda,
          reason: 'the listed row says placed: the order draws no card of '
              'its own');
      expect(dollarsHandingOver([nvda], listed: listed), ['so_i']);
      expect(
          dollarsPinnedRanked(['hl-BTC', 'hl-xyz:NVDA'], [nvda], now: now),
          ['hl-xyz:NVDA', 'hl-BTC']);
      // Another dex's Nvidia is another position: the order keeps its own.
      expect(dollarsStandingSlotId(nvda, {'hl-io:NVDA'}), 'hl-xyz:NVDA');
      expect(dollarsHandingOver([nvda], listed: {'hl-io:NVDA'}), isEmpty);
    });

    test('an Investing order kept before the position coin was (the '
        'displayed coin only) still finds its builder dex position: never '
        'its own card beside it', () {
      final legacy = at(_investing(coin: 'NVDA', isBuy: false),
          StandingOrderState.filled, const Duration(seconds: 10));
      expect(dollarsStandingPlacesInto(legacy, 'hl-xyz:NVDA'), isTrue);
      expect(dollarsStandingPlacesInto(legacy, 'hl-NVDA'), isTrue);
      expect(dollarsStandingPlacesInto(legacy, 'hl-xyz:NVDAX'), isFalse);
      expect(dollarsStandingPlacesInto(legacy, 'hl-spot-xyz:NVDA'), isFalse);
      final listed = {'hl-BTC', 'hl-xyz:NVDA'};
      expect(dollarsStandingSlotId(legacy, listed), 'hl-xyz:NVDA');
      final slots = dollarsOverviewSlots(['hl-xyz:NVDA', 'hl-BTC'], [legacy],
          listed: listed, now: now, handedOver: {'so_i'});
      expect([for (final s in slots) s.id], ['hl-xyz:NVDA', 'hl-BTC']);
      expect(slots.first.order, legacy);
      // A spot order matches its holding only.
      final spot = StandingOrder.fromJson(
          {...legacy.toJson(), 'marketKind': 'spot', 'leverage': 1})!;
      expect(dollarsStandingPlacesInto(spot, 'hl-xyz:NVDA'), isFalse);
      expect(dollarsStandingSlotId(spot, {}), 'hl-spot-NVDA');
    });

    test('the position coin is kept with the order', () {
      final o = _investing(coin: 'NVDA', positionCoin: 'xyz:NVDA');
      expect(StandingOrder.fromJson(o.toJson())!.positionCoin, 'xyz:NVDA');
      expect(o.copyWith(state: StandingOrderState.filled).positionCoin,
          'xyz:NVDA');
      expect(
          StandingOrder.fromJson({...o.toJson()}..remove('positionCoin'))!
              .positionCoin,
          isNull);
    });

    test('Investing closes: a perp closing, or closed by a fill after the '
        'accept, ends its filled order', () {
      final nvda = at(
          _investing(coin: 'NVDA', positionCoin: 'xyz:NVDA', isBuy: false),
          StandingOrderState.filled,
          const Duration(seconds: 10));
      HlFill fill(String dir, DateTime at, {String coin = 'xyz:NVDA'}) =>
          HlFill(
              coin: coin,
              px: 180,
              sz: 0.06,
              side: 'B',
              time: at.millisecondsSinceEpoch,
              closedPnl: 0,
              fee: 0,
              feeToken: 'USDC',
              oid: 1,
              hash: '0x',
              dir: dir,
              cloid: null);
      final closedAt = nvda.createdAt.add(const Duration(seconds: 5));
      final closes = dollarsHlCloses([
        fill('Open Short', nvda.createdAt),
        fill('Close Short', closedAt),
        fill('Close Long', closedAt, coin: 'BTC'),
      ]);
      expect(closes.keys, {'hl-xyz:NVDA', 'hl-BTC'});
      expect(closes['hl-xyz:NVDA']!.millisecondsSinceEpoch,
          closedAt.millisecondsSinceEpoch);
      expect(dollarsEndedOrders([nvda], soldAt: closes), ['so_i']);
      expect(dollarsEndedOrders([nvda], selling: {'hl-xyz:NVDA'}), ['so_i']);
      expect(
          dollarsEndedOrders([nvda],
              soldAt: dollarsHlCloses([fill('Open Short', closedAt)])),
          isEmpty,
          reason: 'its own opening fill is no sale');
      expect(
          dollarsEndedOrders([nvda],
              soldAt: dollarsHlCloses([
                fill('Close Short',
                    nvda.createdAt.subtract(const Duration(days: 1)))
              ])),
          isEmpty,
          reason: 'an earlier position of the coin');
    });

    test('the next hold end: the card hold, then the slot hold, then none',
        () {
      final filled = at(_prediction(id: 'f'), StandingOrderState.filled,
          const Duration(seconds: 30));
      expect(dollarsNextHoldEnd([filled], now: now),
          filled.updatedAt.add(kDollarsFilledCardHold));
      expect(
          dollarsNextHoldEnd([filled],
              now: filled.updatedAt.add(kDollarsFilledCardHold)),
          filled.updatedAt.add(kDollarsFilledHold));
      expect(
          dollarsNextHoldEnd([filled],
              now: filled.updatedAt.add(kDollarsFilledHold)),
          isNull);
      expect(
          dollarsNextHoldEnd(
              [at(_prediction(), StandingOrderState.posting, Duration.zero)],
              now: now),
          isNull);
    });
  });

  testWidgets(
      'a prediction leads the squares from the accept as one card saying '
      'Placing; a tap opens its journey; it fails and goes', (tester) async {
    await pumpInvestments(tester, size: const Size(390, 1400), overrides: [
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
          HyperliquidTradingState(
              isInitialized: true, positions: [_perp('BTC', 500)]))),
    ]);
    expect(order(tester), ['hl-BTC']);
    final notifier = _container(tester).read(standingOrdersProvider.notifier);

    notifier.debugReplace([_prediction()]);
    await tester.pump();
    expect(order(tester), ['poly-tok-so_p', 'hl-BTC']);
    final card = inSquares(find.byKey(const ValueKey('poly-tok-so_p')));
    // The position row's look (PortfolioPositionRow), built from the order.
    expect(find.descendant(of: card, matching: find.byType(PlacingBetRow)),
        findsOneWidget);
    expect(text('poly-tok-so_p', 'Placing'), findsOneWidget);
    expect(find.textContaining('Moving money'), findsNothing);
    expect(figure('poly-tok-so_p', r'$10.00'), findsOneWidget);
    // The existing square, two side by side.
    expect(inSquares(find.byKey(const ValueKey('portfolio-square'))),
        findsNWidgets(2));
    // No spinner anywhere on it.
    expect(inSquares(find.byType(CircularProgressIndicator)), findsNothing);

    notifier.debugReplace([_prediction(state: StandingOrderState.posting)]);
    await tester.pump();
    expect(text('poly-tok-so_p', 'Placing'), findsOneWidget);
    notifier
        .debugReplace([_prediction(state: StandingOrderState.needsApproval)]);
    await tester.pump();
    expect(text('poly-tok-so_p', 'Needs your approval'), findsOneWidget);

    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(StandingOrderJourneySheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(StandingOrderJourneySheet))).pop();
    await tester.pump(const Duration(milliseconds: 600));

    notifier.debugReplace([_prediction(state: StandingOrderState.failed)]);
    await tester.pump();
    expect(order(tester), ['hl-BTC']);
    notifier.debugReplace([_prediction(state: StandingOrderState.cancelled)]);
    await tester.pump();
    expect(order(tester), ['hl-BTC']);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'nothing else open: the in-progress card alone, the full-width '
      'compact card, under the heading; never the empty Sal',
      (tester) async {
    await pumpInvestments(tester);
    expect(find.byKey(const ValueKey('dollars-activity-empty')), findsOneWidget);
    _container(tester)
        .read(standingOrdersProvider.notifier)
        .debugReplace([_prediction()]);
    await tester.pump();
    expect(find.byKey(const ValueKey('dollars-activity-empty')), findsNothing);
    expect(find.byKey(const ValueKey('dollars-activity-positions-heading')),
        findsOneWidget);
    expect(inSquares(find.byKey(const ValueKey('portfolio-wide'))),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('in progress counts toward the four, in-progress first',
      (tester) async {
    await pumpInvestments(tester, size: const Size(390, 1400), overrides: [
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
          HyperliquidTradingState(isInitialized: true, positions: [
            _perp('BTC', 500),
            _perp('SOL', 400),
            _perp('HYPE', 300),
            _perp('DOGE', 200),
          ]))),
    ]);
    expect(order(tester), ['hl-BTC', 'hl-SOL', 'hl-HYPE', 'hl-DOGE']);
    _container(tester).read(standingOrdersProvider.notifier).debugReplace([
      _prediction(id: 'a'),
      _investing(),
    ]);
    await tester.pump();
    expect(order(tester), ['hl-ETH', 'poly-tok-a', 'hl-BTC', 'hl-SOL']);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'Predictions, one card: Placing, then placed from the fill\'s own '
      'figures, then the listed position in the same slot saying placed, '
      'then its own line; sold, nothing comes back', (tester) async {
    var clock = DateTime.now();
    await pumpInvestments(tester, size: const Size(390, 1400), overrides: [
      dollarsOverviewClockProvider.overrideWithValue(() => clock),
      polymarketActivePositionsProvider
          .overrideWith((ref) => ref.watch(_positions)),
      livePriceProvider.overrideWith(_Prices.new),
    ]);
    final container = _container(tester);
    final notifier = container.read(standingOrdersProvider.notifier);
    const key = 'poly-tok-so_p';

    notifier.debugReplace([_prediction(at: clock)]);
    await tester.pump();
    expect(order(tester), [key]);
    expect(text(key, 'Placing'), findsOneWidget);
    final slot = tester.getRect(inSquares(find.byKey(const ValueKey(key))));

    // Filled, the position not read yet: the same card says placed at
    // once, with what the fill cost; never a placing card after the fill.
    notifier.debugReplace([
      _prediction(state: StandingOrderState.filled, at: clock)
          .copyWith(filledSize: 19.6, filledUsd: 9.8)
    ]);
    await tester.pump();
    expect(order(tester), [key]);
    expect(find.textContaining('placed'), findsNothing);
    expect(find.textContaining('Placing'), findsNothing);
    expect(figure(key, r'$9.80'), findsOneWidget);
    expectSameSlot(
        tester.getRect(inSquares(find.byKey(const ValueKey(key)))), slot);

    // The position lists: the slot is the position's own row, under the
    // same key, in the same place, still saying placed. One card.
    container.read(_positions.notifier).state = [_poly('tok-so_p')];
    await tester.pump();
    await tester.pump();
    expect(order(tester), [key]);
    expect(inSquares(find.byType(PolyPositionRow)), findsOneWidget);
    expect(inSquares(find.byType(PlacingBetRow)), findsNothing);
    expect(find.textContaining('placed'), findsNothing);
    expectSameSlot(
        tester.getRect(inSquares(find.byKey(const ValueKey(key)))), slot);

    // The card hold ends: the position's own line, nothing else changes.
    clock = clock.add(kDollarsFilledCardHold);
    await tester.pump(kDollarsFilledCardHold);
    await tester.pump();
    expect(order(tester), [key]);
    expect(find.textContaining('placed'), findsNothing);
    expect(inSquares(find.byType(PolyPositionRow)), findsOneWidget);

    // Sold: the position goes, and nothing comes back, here or after the
    // order is read again.
    container.read(_positions.notifier).state = const [];
    await tester.pump();
    await tester.pump();
    expect(order(tester), isEmpty);
    notifier.debugReplace([
      _prediction(state: StandingOrderState.filled)
          .copyWith(updatedAt: clock)
    ]);
    await tester.pump();
    expect(order(tester), isEmpty);
    expect(find.textContaining('placed'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'Investing, one card: the venue lists the position before the order\'s '
      'answer: the listed row itself says Placing (a tap opens the journey), '
      'then Order placed, then its own line; never a second card',
      (tester) async {
    var clock = DateTime.now();
    late _Trading trading;
    await pumpInvestments(tester, size: const Size(390, 1400), overrides: [
      dollarsOverviewClockProvider.overrideWithValue(() => clock),
      hyperliquidTradingProvider.overrideWith(() => trading = _Trading(
          HyperliquidTradingState(
              isInitialized: true, positions: [_perp('BTC', 500)]))),
    ]);
    final notifier = _container(tester).read(standingOrdersProvider.notifier);
    notifier.debugReplace([_investing()]);
    await tester.pump();
    expect(order(tester), ['hl-ETH', 'hl-BTC']);
    expect(text('hl-ETH', 'Long · Placing'), findsOneWidget);
    expect(figure('hl-ETH', r'$20.00'), findsOneWidget);
    final slot = tester.getRect(inSquares(find.byKey(const ValueKey('hl-ETH'))));

    // The venue lists ETH while the order still reads posting: the listed
    // row takes the slot and says Placing. Not two ETH cards.
    notifier.debugReplace([_investing(state: StandingOrderState.posting)]);
    trading.land([_perp('BTC', 500), _perp('ETH', 20)]);
    await tester.pump();
    await tester.pump();
    expect(order(tester), ['hl-ETH', 'hl-BTC']);
    expect(inSquares(find.byType(HlPositionRow)), findsNWidgets(2));
    expect(text('hl-ETH', 'Long · Placing'), findsOneWidget);
    expectSameSlot(
        tester.getRect(inSquares(find.byKey(const ValueKey('hl-ETH')))), slot);
    // Placing, its tap is the order's: the journey (Cancel lives there).
    await tester.tap(inSquares(find.byKey(const ValueKey('hl-ETH'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(StandingOrderJourneySheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(StandingOrderJourneySheet))).pop();
    await tester.pump(const Duration(milliseconds: 600));

    // It fills: the same row says placed at once.
    notifier.debugReplace([
      _investing(state: StandingOrderState.filled)
          .copyWith(updatedAt: clock, filledSize: 0.0133, filledUsd: 40)
    ]);
    await tester.pump();
    expect(order(tester), ['hl-ETH', 'hl-BTC']);
    expect(text('hl-ETH', 'Long · 1 ETH'), findsOneWidget);
    expect(find.textContaining('Placing'), findsNothing);

    // The card hold ends: the position's own line.
    clock = clock.add(kDollarsFilledCardHold);
    await tester.pump(kDollarsFilledCardHold);
    await tester.pump();
    expect(order(tester), ['hl-ETH', 'hl-BTC']);
    expect(find.textContaining('Order placed'), findsNothing);
    expect(text('hl-ETH', 'Long · 1 ETH'), findsOneWidget);

    // Closed: the position goes and nothing comes back.
    trading.land([_perp('BTC', 500)]);
    await tester.pump();
    await tester.pump();
    expect(order(tester), ['hl-BTC']);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'Investing, the fill before the listing: the order\'s card says Order '
      'placed with the fill\'s margin, then the position takes that same '
      'slot', (tester) async {
    late _Trading trading;
    await pumpInvestments(tester, size: const Size(390, 1400), overrides: [
      hyperliquidTradingProvider.overrideWith(() => trading = _Trading(
          HyperliquidTradingState(
              isInitialized: true, positions: [_perp('BTC', 500)]))),
    ]);
    final notifier = _container(tester).read(standingOrdersProvider.notifier);
    notifier.debugReplace([_investing()]);
    await tester.pump();
    final slot = tester.getRect(inSquares(find.byKey(const ValueKey('hl-ETH'))));
    notifier.debugReplace([
      _investing(state: StandingOrderState.filled)
          .copyWith(filledSize: 0.0133, filledUsd: 40)
    ]);
    await tester.pump();
    expect(order(tester), ['hl-ETH', 'hl-BTC']);
    expect(text('hl-ETH', 'Long · 0.0133 ETH'), findsOneWidget);
    expect(find.textContaining('placed'), findsNothing);
    // The margin at the fill: $40 notional at 2x.
    expect(figure('hl-ETH', r'$20.00'), findsOneWidget);

    trading.land([_perp('BTC', 500), _perp('ETH', 20)]);
    await tester.pump();
    await tester.pump();
    expect(order(tester), ['hl-ETH', 'hl-BTC']);
    expect(inSquares(find.byType(HlPositionRow)), findsNWidgets(2));
    expect(find.textContaining('placed'), findsNothing);
    expectSameSlot(
        tester.getRect(inSquares(find.byKey(const ValueKey('hl-ETH')))), slot);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  for (final positionCoin in const ['xyz:NVDA', null]) {
    testWidgets(
        'Investing, a builder dex (HIP-3) stock perp (position coin '
        '$positionCoin): ONE card, the order\'s, then the listed position '
        'in the same slot saying placed; never both (2.2.0 (101))',
        (tester) async {
      late _Trading trading;
      await pumpInvestments(tester, size: const Size(390, 1400), overrides: [
        hyperliquidTradingProvider.overrideWith(() => trading = _Trading(
            HyperliquidTradingState(
                isInitialized: true, positions: [_perp('BTC', 500)]))),
      ]);
      final notifier =
          _container(tester).read(standingOrdersProvider.notifier);
      final nvda = _investing(
          coin: 'NVDA', positionCoin: positionCoin, isBuy: false);
      notifier.debugReplace([
        nvda.copyWith(
            state: StandingOrderState.filled,
            updatedAt: DateTime.now(),
            filledSize: 0.06,
            filledUsd: 40)
      ]);
      await tester.pump();
      final slotKey = positionCoin == null ? 'hl-NVDA' : 'hl-xyz:NVDA';
      expect(order(tester), [slotKey, 'hl-BTC']);
      expect(text(slotKey, 'Short · 0.06 NVDA'), findsOneWidget);

      // The venue lists it under its dex-qualified coin.
      trading.land(
          [_perp('BTC', 500), _perp('xyz:NVDA', 20, szi: -0.06)]);
      await tester.pump();
      await tester.pump();
      expect(order(tester), ['hl-xyz:NVDA', 'hl-BTC']);
      expect(inSquares(find.byType(HlPositionRow)), findsNWidgets(2));
      expect(find.textContaining('placed'), findsNothing);
      expect(text('hl-xyz:NVDA', 'Short · 0.06 NVDA'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  }

  testWidgets(
      'a filled card whose position never lists leaves when its hold ends, '
      'with nothing else rebuilding the tab', (tester) async {
    var clock = DateTime.now();
    await pumpInvestments(tester, size: const Size(390, 1400), overrides: [
      dollarsOverviewClockProvider.overrideWithValue(() => clock),
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
          HyperliquidTradingState(
              isInitialized: true, positions: [_perp('BTC', 500)]))),
    ]);
    _container(tester).read(standingOrdersProvider.notifier).debugReplace(
        [_prediction(state: StandingOrderState.filled, at: clock)]);
    await tester.pump();
    expect(order(tester), ['poly-tok-so_p', 'hl-BTC']);

    clock = clock.add(kDollarsFilledCardHold - const Duration(seconds: 1));
    await tester.pump(kDollarsFilledCardHold - const Duration(seconds: 1));
    expect(order(tester), ['poly-tok-so_p', 'hl-BTC'],
        reason: 'still inside the hold');

    clock = clock.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(order(tester), ['hl-BTC'], reason: 'the hold ended on time');
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });
}
