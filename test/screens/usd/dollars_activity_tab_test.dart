// The Dollars Activity pill (founder, 4 November 2026: "On Dollars, like
// we do on the Bitcoin screen, have the first tab be the Activity screen …
// It must have the P&L below the 4 squares with the highest predictions and
// Hyperliquid bets."): the biggest open positions as squares, biggest
// first, four at most; the P&L under them; the latest Investments actions
// (fw2's ActivityScope.investments); the
// empty state with nothing open; and the bar, "See full portfolio and
// activity", pushing the Portfolio screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlPerpPosition;
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/screens/portfolio/components/balances_overview.dart'
    show BalancesVenueList;
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show HlPositionRow;
import 'package:kute/screens/shared/all_activity.dart'
    show ActivitySquareGrid;
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarContextProvider, kuteBarTop;
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/usd/components/dollars_activity_tab.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Activity;

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

PolymarketTransaction _bet(String id) {
  final at = DateTime.utc(2026, 11, 4, 12)
      .add(Duration(minutes: int.parse(id.substring(3))));
  return PolymarketTransaction(
    id: id,
    timestamp: at,
    activity: Activity(
      proxyWallet: '0xself',
      timestamp: at.millisecondsSinceEpoch ~/ 1000,
      conditionId: '0xrain',
      type: 'TRADE',
      size: 10,
      usdcSize: 5,
      transactionHash: '0x$id',
      side: 'BUY',
      asset: 'yes',
      outcomeIndex: 0,
      title: 'Will it rain tomorrow?',
      outcome: 'Yes',
      eventSlug: '',
    ),
  );
}

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(InvestmentsBody, skipOffstage: false)));

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  group('the squares', () {
    test('the biggest open positions, biggest first, four at most', () {
      // portfolioOpenRanked hands them biggest first.
      const ranked = ['poly-a', 'hl-ETH', 'hl-HYPE', 'poly-b', 'hl-BTC'];
      expect(dollarsActivitySquareIds(ranked),
          ['poly-a', 'hl-ETH', 'hl-HYPE', 'poly-b']);
      expect(dollarsActivitySquareIds(ranked.take(3).toList()),
          ['poly-a', 'hl-ETH', 'hl-HYPE']);
      expect(dollarsActivitySquareIds(const []), isEmpty);
    });

    test('each square is the position\'s own row, in the slices\' order', () {
      const a = SizedBox(key: ValueKey('hl-ETH'));
      const b = SizedBox(key: ValueKey('poly-a'));
      const c = SizedBox(key: ValueKey('hl-BTC'));
      final lists = [
        const BalancesVenueList(rows: [a, c]),
        const BalancesVenueList(rows: [b]),
      ];
      expect(
          dollarsActivitySquareRows(['poly-a', 'hl-ETH', 'gone'], lists),
          [b, a],
          reason: 'a slice whose row is not read yet leaves no hole');
    });
  });

  testWidgets(
      'Latest: the newest Investments actions, five at most, newest first, '
      'never a Bitcoin payment', (tester) async {
    await pumpInvestments(tester,
        history: Transaction(
          bitcoinTransactions: [
            BitcoinTransaction.fromCache(
                id: 'btc1',
                timestamp: DateTime.utc(2026, 11, 4, 13),
                isConfirmed: true,
                receivedSats: 1000,
                sentSats: 0),
          ],
          sparkTransactions: const [],
          sparkUnclaimedDeposits: const [],
          polymarketTransactions: [
            for (var i = 1; i <= 7; i++) _bet('bet$i'),
          ],
        ));
    final card = find.byKey(const ValueKey('dollars-activity-rows'));
    expect(card, findsOneWidget);
    expect(find.byKey(const ValueKey('dollars-activity-latest-heading')),
        findsOneWidget);
    expect(kDollarsActivityRows, 5);
    // Every row a prediction placed, five of the seven; the bitcoin
    // receive is not an Investments action.
    expect(
        find.descendant(of: card, matching: find.text('Prediction · Yes')),
        findsNWidgets(5));
    expect(find.descendant(of: card, matching: find.text(r'$5.00')),
        findsNWidgets(5));
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'the Activity pill: the four biggest positions as squares, biggest '
      'first, two by two, then the P&L card, and the bar opens the '
      'Portfolio', (tester) async {
    final events = recordEvents();
    final now = DateTime.now();
    await pumpInvestments(tester, overrides: [
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
              HyperliquidTradingState(isInitialized: true, positions: [
            _perp('BTC', 100),
            _perp('ETH', 500),
            _perp('SOL', 50),
            _perp('HYPE', 300),
            _perp('DOGE', 200),
          ]))),
      portfolioPerformanceProvider(const PortfolioPerformanceRequest(
              venue: PortfolioPerformanceVenue.trading))
          .overrideWith((_) async => PortfolioPerformance(
                points: [
                  PortfolioPnlPoint(
                      timestamp: now.subtract(const Duration(days: 20)),
                      pnlUsd: 10),
                  PortfolioPnlPoint(
                      timestamp: now.subtract(const Duration(days: 2)),
                      pnlUsd: 22.5),
                ],
                sourceLabel: '',
                basisLabel: 'P&L',
                coverageLabel: '',
              )),
    ]);
    expect(_container(tester).read(investmentsTabProvider),
        InvestmentsTab.activity);
    final squares = find.byKey(const ValueKey('dollars-activity-squares'));
    expect(squares, findsOneWidget);
    final rows = tester
        .widgetList<HlPositionRow>(
            find.descendant(of: squares, matching: find.byType(HlPositionRow)))
        .map((r) => (r.key! as ValueKey<String>).value)
        .toList();
    expect(rows, ['hl-ETH', 'hl-HYPE', 'hl-DOGE', 'hl-BTC'],
        reason: 'the four biggest, biggest first; SOL is the fifth');
    // Two by two: the first two side by side, the next two under them.
    final cells = find.descendant(of: squares, matching: find.byType(HlPositionRow));
    final first = tester.getRect(cells.at(0));
    final second = tester.getRect(cells.at(1));
    final third = tester.getRect(cells.at(2));
    expect(second.top, moreOrLessEquals(first.top, epsilon: 0.5));
    expect(second.left, greaterThan(first.right));
    expect(third.top, greaterThan(first.bottom));
    expect(third.left, moreOrLessEquals(first.left, epsilon: 0.5));
    expect(first.width, moreOrLessEquals(second.width, epsilon: 0.5));

    // The P&L under the squares: the range's P&L (the past month, $10 to
    // $22.50: +$12.50) on its card.
    final pnl = find.byKey(const ValueKey('dollars-pnl-strip'));
    expect(pnl, findsOneWidget);
    expect(tester.getTopLeft(pnl).dy, greaterThan(tester.getBottomLeft(squares).dy));
    expect(find.byKey(const ValueKey('dollars-pnl-chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('dollars-activity-empty')), findsNothing);

    // The bar on Activity: "See full portfolio and activity", the
    // Portfolio's own key under this surface.
    final bar = kuteBarTop(_container(tester).read(kuteBarContextProvider));
    expect(bar!.isPrimary, isTrue);
    expect(bar.label, 'See full portfolio and activity');
    expect(bar.disabledLabel, 'See full portfolio and activity');
    expect(bar.actionable, isTrue);
    // Its tap (the push and the event) is driven under a router in
    // investments_screen_test.dart (openPortfolio).
    expect(events.where((e) => e.$1 == 'quick_action_tapped'), isEmpty);

    // A venue pill: the search pill again, scoped to it.
    await tapPill(tester, 'Investing');
    final venueBar =
        kuteBarTop(_container(tester).read(kuteBarContextProvider));
    expect(venueBar!.isPrimary, isFalse);
    expect(venueBar.label, 'Search investments or Manage with AI');
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'one edge for every block: the squares, the P&L card and the Latest '
      'card share the page\'s gutters, the headings one line 12 inside',
      (tester) async {
    // Founder, 5 November 2026 ("different size here"): the Latest card
    // stood 16 inside the squares and the P&L card. Dark, as the screenshot.
    final now = DateTime.now();
    await pumpInvestments(tester,
        dark: true,
        // Tall enough that the Latest card is laid out.
        size: const Size(390, 2000),
        history: Transaction(
          bitcoinTransactions: const [],
          sparkTransactions: const [],
          sparkUnclaimedDeposits: const [],
          polymarketTransactions: [
            for (var i = 1; i <= 3; i++) _bet('bet$i'),
          ],
        ),
        overrides: [
          hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
                  HyperliquidTradingState(isInitialized: true, positions: [
                _perp('BTC', 100),
                _perp('ETH', 500),
                _perp('HYPE', 300),
              ]))),
          portfolioPerformanceProvider(const PortfolioPerformanceRequest(
                  venue: PortfolioPerformanceVenue.trading))
              .overrideWith((_) async => PortfolioPerformance(
                    points: [
                      PortfolioPnlPoint(
                          timestamp: now.subtract(const Duration(days: 20)),
                          pnlUsd: 10),
                      PortfolioPnlPoint(
                          timestamp: now.subtract(const Duration(days: 2)),
                          pnlUsd: 22.5),
                    ],
                    sourceLabel: '',
                    basisLabel: 'P&L',
                    coverageLabel: '',
                  )),
        ]);
    final list =
        tester.getRect(find.byKey(const ValueKey('dollars-activity-list')));
    final squares = tester.getRect(find.descendant(
        of: find.byKey(const ValueKey('dollars-activity-squares')),
        matching: find.byType(ActivitySquareGrid)));
    final pnl = tester.getRect(find.byKey(const ValueKey('dollars-pnl-strip')));
    // The card's face (its clip), never a margin around it: a Container's
    // rect counts its margin.
    final latest = tester.getRect(find
        .descendant(
            of: find.byKey(const ValueKey('dollars-activity-rows')),
            matching: find.byType(ClipRRect))
        .first);
    // The page's 16 gutters, one each side, for every block.
    final gutter = 16.w;
    for (final (name, r) in [
      ('squares', squares),
      ('P&L card', pnl),
      ('Latest card', latest),
    ]) {
      expect(r.left - list.left, moreOrLessEquals(gutter, epsilon: 0.5),
          reason: '$name left');
      expect(list.right - r.right, moreOrLessEquals(gutter, epsilon: 0.5),
          reason: '$name right');
    }
    expect(latest.left, moreOrLessEquals(squares.left, epsilon: 0.5));
    expect(latest.right, moreOrLessEquals(squares.right, epsilon: 0.5));
    expect(pnl.left, moreOrLessEquals(squares.left, epsilon: 0.5));
    expect(pnl.right, moreOrLessEquals(squares.right, epsilon: 0.5));
    // The squares' own cells reach the grid's edges.
    final cells = find.descendant(
        of: find.byKey(const ValueKey('dollars-activity-squares')),
        matching: find.byType(HlPositionRow));
    expect(tester.getRect(cells.at(0)).left,
        moreOrLessEquals(squares.left, epsilon: 0.5));
    expect(tester.getRect(cells.at(1)).right,
        moreOrLessEquals(squares.right, epsilon: 0.5));
    // Both headings on one line, 12 inside the blocks' edge (the Bitcoin
    // home's "Latest" and "Earlier"), each over its block.
    Rect heading(String key) => tester.getRect(find.descendant(
        of: find.byKey(ValueKey(key)), matching: find.byType(Text)));
    final positionsHeading = heading('dollars-activity-positions-heading');
    final latestHeading = heading('dollars-activity-latest-heading');
    expect(positionsHeading.left,
        moreOrLessEquals(latestHeading.left, epsilon: 0.5));
    expect(positionsHeading.left - squares.left,
        moreOrLessEquals(12.w, epsilon: 0.5));
    expect(positionsHeading.bottom, lessThanOrEqualTo(squares.top));
    expect(latestHeading.bottom, lessThanOrEqualTo(latest.top));
    expect(latestHeading.top, greaterThanOrEqualTo(pnl.bottom));
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('nothing open: one Sal "No open positions", no P&L card',
      (tester) async {
    await pumpInvestments(tester);
    expect(find.byKey(const ValueKey('dollars-activity-empty')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('dollars-activity-empty')),
            matching: find.byType(NoActivityState)),
        findsOneWidget);
    expect(find.text('No open positions'), findsOneWidget);
    expect(find.byKey(const ValueKey('dollars-activity-squares')), findsNothing);
    expect(find.byKey(const ValueKey('dollars-pnl-strip')), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('one position alone is one square across the whole width',
      (tester) async {
    await pumpInvestments(tester, overrides: [
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
          HyperliquidTradingState(
              isInitialized: true, positions: [_perp('BTC', 100)]))),
    ]);
    final squares = find.byKey(const ValueKey('dollars-activity-squares'));
    final row = find.descendant(of: squares, matching: find.byType(HlPositionRow));
    expect(row, findsOneWidget);
    final list = tester.getRect(find.byKey(const ValueKey('dollars-activity-list')));
    expect(tester.getSize(row).width, greaterThan(list.width * 0.8));
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  test('the bar sends the key the Portfolio button sent', () {
    expect(UsdAccountActionBar.portfolioActionId, 'portfolio');
  });
}
