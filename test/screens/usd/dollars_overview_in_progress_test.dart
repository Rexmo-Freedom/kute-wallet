// The Dollars Overview shows what is being placed (founder, 9 November
// 2026: "On the Overview we must show exactly there what bets or
// investments are in progress of being implemented, as soon as they
// touch"): a standing order leads the squares from the accept, as the
// venue's own placing row with its stage in the compact words; a tap opens
// its money journey; it counts toward the four; filled, it holds its slot
// until the position lists and the position takes that slot; failed or
// cancelled, it goes. Predictions and Investing alike.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlPerpPosition;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show HlPositionRow, PlacingBetRow;
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/standing_order_journey.dart';
import 'package:kute/screens/usd/components/dollars_activity_tab.dart';
import 'package:kute/screens/usd/usd_account_screen.dart' show InvestmentsBody;
import 'package:kute/services/standing_orders/standing_orders_provider.dart';

import '../../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import 'investments_harness.dart';

HlPerpPosition _perp(String coin, double margin) => HlPerpPosition(
    coin: coin,
    szi: 1,
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
        String coin = 'ETH'}) =>
    StandingOrder(
      id: 'so_i',
      walletId: 'spending',
      venue: StandingOrderVenue.investing,
      marketKey: coin,
      marketTitle: '$coin · Perp',
      sideLabel: 'long',
      isBuy: true,
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

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(InvestmentsBody, skipOffstage: false)));

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  final squares = find.byKey(const ValueKey('dollars-activity-squares'));
  Finder inSquares(Finder f) => find.descendant(of: squares, matching: f);

  /// The keys of the squares' rows, in order.
  List<String> order(WidgetTester tester) => [
        for (final e in inSquares(find.byWidgetPredicate((w) =>
                w.key is ValueKey<String> &&
                ((w.key! as ValueKey<String>).value.startsWith('standing-') ||
                    (w.key! as ValueKey<String>).value.startsWith('hl-'))))
            .evaluate())
          (e.widget.key! as ValueKey<String>).value,
      ];

  group('pure', () {
    final now = DateTime(2026, 11, 9, 12);
    StandingOrder at(StandingOrder o, StandingOrderState s, Duration ago) =>
        o.copyWith(state: s, updatedAt: now.subtract(ago));

    test('open ones newest first; a fresh fill until its position lists; '
        'failed, cancelled and old fills never', () {
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
      expect(dollarsStandingShown(all, listed: {}, now: now),
          [b, a, filled]);
      expect(dollarsStandingShown(all, listed: {'poly-tok-f'}, now: now),
          [b, a],
          reason: 'the position took over');
      expect(
          dollarsStandingShown(all, listed: {}, now: now, investing: false),
          [a, filled]);
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
  });

  testWidgets(
      'a prediction leads the squares from the accept, its stage in the '
      'compact words; a tap opens its journey; it fails and goes',
      (tester) async {
    await pumpInvestments(tester, size: const Size(390, 1400), overrides: [
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
          HyperliquidTradingState(
              isInitialized: true, positions: [_perp('BTC', 500)]))),
    ]);
    expect(order(tester), ['hl-BTC']);
    final notifier = _container(tester).read(standingOrdersProvider.notifier);

    notifier.debugReplace([_prediction()]);
    await tester.pump();
    expect(order(tester), ['standing-so_p', 'hl-BTC']);
    final card = inSquares(find.byKey(const ValueKey('standing-so_p')));
    expect(find.descendant(of: card, matching: find.byType(PlacingBetRow)),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining('Moving money')),
        findsOneWidget);
    expect(
        find.descendant(
            of: card,
            matching: find.byWidgetPredicate(
                (w) => w is RollingFigure && w.text == r'$10.00')),
        findsOneWidget);
    // The existing square, two side by side.
    expect(inSquares(find.byKey(const ValueKey('portfolio-square'))),
        findsNWidgets(2));

    notifier.debugReplace([_prediction(state: StandingOrderState.posting)]);
    await tester.pump();
    expect(find.descendant(of: card, matching: find.textContaining('Placing')),
        findsOneWidget);
    notifier
        .debugReplace([_prediction(state: StandingOrderState.needsApproval)]);
    await tester.pump();
    expect(
        find.descendant(
            of: card, matching: find.textContaining('Needs your approval')),
        findsOneWidget);

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
    expect(order(tester), ['standing-so_i', 'standing-a', 'hl-BTC', 'hl-SOL']);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'Investing: the order leads from the accept ("Long · Moving money"); '
      'filled it holds its slot saying placed, then the position takes '
      'that same slot', (tester) async {
    late _Trading trading;
    await pumpInvestments(tester, size: const Size(390, 1400), overrides: [
      hyperliquidTradingProvider.overrideWith(() => trading = _Trading(
          HyperliquidTradingState(
              isInitialized: true, positions: [_perp('BTC', 500)]))),
    ]);
    final notifier = _container(tester).read(standingOrdersProvider.notifier);
    notifier.debugReplace([_investing()]);
    await tester.pump();
    expect(order(tester), ['standing-so_i', 'hl-BTC']);
    final card = inSquares(find.byKey(const ValueKey('standing-so_i')));
    expect(find.descendant(of: card, matching: find.text('Long · Moving money')),
        findsOneWidget);
    final slot = tester.getRect(card);

    // Filled, the position not read yet: the card stays, placed.
    notifier.debugReplace([_investing(state: StandingOrderState.filled)]);
    await tester.pump();
    expect(order(tester), ['standing-so_i', 'hl-BTC']);
    expect(find.descendant(of: card, matching: find.text('Long · Order placed')),
        findsOneWidget);

    // The position lists: it takes the card's slot, ahead of the bigger
    // BTC, so nothing moves.
    trading.land([_perp('BTC', 500), _perp('ETH', 20)]);
    await tester.pump();
    await tester.pump();
    expect(order(tester), ['hl-ETH', 'hl-BTC']);
    final eth = tester.widgetList<HlPositionRow>(inSquares(find.byType(HlPositionRow)))
        .map((r) => (r.key! as ValueKey<String>).value)
        .toList();
    expect(eth.first, 'hl-ETH');
    expect(
        tester.getRect(inSquares(find.byKey(const ValueKey('hl-ETH')))).topLeft,
        slot.topLeft);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });
}
