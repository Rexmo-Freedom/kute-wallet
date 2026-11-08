// The Dollars Overview pill (founder, 4 November 2026: "On Dollars, like
// we do on the Bitcoin screen, have the first tab be the Activity screen …
// It must have the P&L below the 4 squares with the highest predictions and
// Hyperliquid bets."; renamed Overview on 8 November 2026): the biggest open
// positions as squares, biggest first, four at most; the P&L under them; the
// market map under that (dollars_default_tab_test.dart drives it); no list of
// actions; the empty state with nothing open and no map; and the bar, "See
// full portfolio and activity", pushing the Portfolio screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart'
    show HlFill, HlPerpPosition;
import 'package:kute/models/hyperliquid_model.dart' show HyperliquidCandle;
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/providers/open_pnl_history_provider.dart'
    show OpenPnlSources;
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart'
    show KuteTrendChart;
import 'package:kute/screens/shared/rolling_number_text.dart'
    show RollingNumberText;
import 'package:kute/theme/app_theme.dart' show AppColors;
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
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Activity;

import '../../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import '../hyperliquid/hl_market_map_fixture.dart';
import 'investments_harness.dart';

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
      'no Latest: the Investments actions are not listed here, they are the '
      'Portfolio\'s', (tester) async {
    await pumpInvestments(tester,
        history: Transaction(
          bitcoinTransactions: const [],
          sparkTransactions: const [],
          sparkUnclaimedDeposits: const [],
          polymarketTransactions: [
            for (var i = 1; i <= 7; i++) _bet('bet$i'),
          ],
        ));
    expect(find.byType(DollarsActivityTab), findsOneWidget);
    expect(find.text('Latest'), findsNothing);
    expect(find.text('Prediction · Yes'), findsNothing);
    expect(find.text(r'$5.00'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'the Overview pill: the four biggest positions as squares, biggest '
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

    // The Open P&L under the squares (no fills read here: the figure
    // alone, the chart folded; its line is driven below).
    final pnl = find.byKey(const ValueKey('dollars-pnl-strip'));
    expect(pnl, findsOneWidget);
    expect(tester.getTopLeft(pnl).dy, greaterThan(tester.getBottomLeft(squares).dy));
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('dollars-pnl-label'))).data,
        'Open profits');
    expect(find.text('Profits'), findsNothing);
    expect(find.byKey(const ValueKey('dollars-pnl-chart')), findsNothing);
    expect(find.byKey(const ValueKey('dollars-activity-empty')), findsNothing);

    // The bar on Overview: "See full portfolio and activity", the
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
      'one edge for every block: the squares, the P&L card and the map '
      'share the page\'s gutters, the heading 12 inside', (tester) async {
    // Founder, 5 November 2026 ("different size here"): a group card stood
    // 16 inside the squares and the P&L card. Dark, as the screenshot.
    final now = DateTime.now();
    await pumpInvestments(tester,
        dark: true,
        // Tall enough that the map is laid out.
        size: const Size(390, 2000),
        browseInvesting: true,
        overrides: [
          hyperliquidBrowseUniverseProvider
              .overrideWithValue(AsyncValue.data(hlMarketMapFixture)),
          hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
          hyperliquidSparklineStoreProvider.overrideWithValue(
              HlSparklineStore(fetch: (_) async => const [1, 2, 3])),
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
    // The card's face (its clip and the 1 px border around it), never a
    // margin around it: a Container's rect counts its margin.
    final map = tester
        .getRect(find
            .descendant(
                of: find.byKey(const ValueKey('hl-market-map')),
                matching: find.byType(ClipRRect))
            .first)
        .inflate(1);
    // The page's 16 gutters, one each side, for every block.
    final gutter = 16.w;
    for (final (name, r) in [
      ('squares', squares),
      ('P&L card', pnl),
      ('map', map),
    ]) {
      expect(r.left - list.left, moreOrLessEquals(gutter, epsilon: 0.5),
          reason: '$name left');
      expect(list.right - r.right, moreOrLessEquals(gutter, epsilon: 0.5),
          reason: '$name right');
    }
    expect(map.left, moreOrLessEquals(squares.left, epsilon: 0.5));
    expect(map.right, moreOrLessEquals(squares.right, epsilon: 0.5));
    // 12 under the P&L card, as the P&L card is under the squares.
    expect(map.top - pnl.bottom, moreOrLessEquals(12.h, epsilon: 1));
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
    // The heading 12 inside the blocks' edge (the Bitcoin home's "Latest"
    // and "Earlier"), over its block.
    final heading = tester.getRect(find.descendant(
        of: find.byKey(const ValueKey('dollars-activity-positions-heading')),
        matching: find.byType(Text)));
    expect(heading.left - squares.left, moreOrLessEquals(12.w, epsilon: 0.5));
    expect(heading.bottom, lessThanOrEqualTo(squares.top));
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'Open profits under the squares (founder, 6 November 2026): what the '
      'positions open now are winning, over the Positions chart\'s own line '
      'since each was opened, its last point that figure, the dashed line '
      'at zero; a tap opens the Portfolio on Positions', (tester) async {
    final now = DateTime.now();
    HlPerpPosition perp(String coin) => HlPerpPosition(
        coin: coin,
        szi: 1,
        entryPx: 100,
        positionValue: 102,
        unrealizedPnl: 2,
        returnOnEquity: 0,
        liquidationPx: null,
        marginUsed: 50,
        leverageType: 'cross',
        leverageValue: 2,
        maxLeverage: 40);
    // Each opened ten days back by one fill at 100.
    HlFill opened(String coin) => HlFill(
          coin: coin,
          px: 100,
          sz: 1,
          side: 'B',
          time: now.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
          closedPnl: 0,
          fee: 0,
          feeToken: 'USDC',
          oid: coin.hashCode,
          hash: '0xopen-$coin',
          dir: 'Open Long',
          cloid: null,
          startPosition: 0,
        );
    await pumpInvestments(tester,
        size: const Size(390, 1400),
        // Every coin at 102 throughout: +$2 each once opened.
        openPnlSources: OpenPnlSources(
          activity: (_) async => const [],
          candles: (_, wire, interval, window) async => [
            for (var t = now.subtract(window);
                t.isBefore(now);
                t = t.add(const Duration(hours: 1)))
              HyperliquidCandle(
                  openTime: t,
                  closeTime: t.add(const Duration(hours: 1)),
                  open: 102,
                  high: 102,
                  low: 102,
                  close: 102,
                  volume: 1),
          ],
          polyHistory: (_, __, ___) async => null,
        ),
        overrides: [
          hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
              HyperliquidTradingState(
                  isInitialized: true,
                  positions: [perp('BTC'), perp('ETH')],
                  recentFills: [opened('BTC'), opened('ETH')]))),
        ]);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final strip = find.byKey(const ValueKey('dollars-pnl-strip'));
    expect(strip, findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('dollars-pnl-label'))).data,
        'Open profits');
    expect(
        tester
            .widget<RollingNumberText>(
                find.byKey(const ValueKey('dollars-pnl-figure')))
            .text,
        r'+$4.00');
    final chart = tester.widget<KuteTrendChart>(
        find.byKey(const ValueKey('dollars-pnl-chart')));
    // The Positions chart's line on its range (ALL, the whole history:
    // from its lead-in a little before the opens ten days back, never a
    // flat month): zero before the opens, +$4 since, the figure last.
    expect(chart.values.first, 0);
    expect(chart.values.last, closeTo(4, 1e-9));
    expect(chart.times!.first.isBefore(now.subtract(const Duration(days: 10))),
        isTrue);
    expect(chart.times!.first.isAfter(now.subtract(const Duration(days: 12))),
        isTrue);
    expect(chart.values.where((v) => v == 0).length,
        lessThan(chart.values.length ~/ 4),
        reason: 'the flat lead-in is a short stretch, not most of the line');
    expect(chart.baseline, 0);
    expect(chart.zeroSplit, isTrue);
    expect(chart.live, isFalse);
    expect(chart.lineColor, AppColors.marketUp);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('nothing open and no map: one Sal "No open positions", no P&L card',
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

  group('the no-orphan rule (founder, 6 November 2026: "should the 3rd one '
      'be rectangular and not with this disposition?")', () {
    Future<void> mount(WidgetTester tester, int count) =>
        pumpInvestments(tester, size: const Size(390, 1400), overrides: [
          hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
                  HyperliquidTradingState(isInitialized: true, positions: [
                for (var i = 0; i < count; i++)
                  _perp(const ['BTC', 'ETH', 'SOL', 'HYPE', 'DOGE'][i],
                      500.0 - i * 100),
              ]))),
        ]);
    final squares = find.byKey(const ValueKey('dollars-activity-squares'));
    Finder inSquares(String key) =>
        find.descendant(of: squares, matching: find.byKey(ValueKey(key)));

    testWidgets(
        'one position: the full-width compact card, the logo left and the '
        'value with its P&L at the end; no square', (tester) async {
      await mount(tester, 1);
      expect(inSquares('portfolio-square'), findsNothing);
      final wide = inSquares('portfolio-wide');
      expect(wide, findsOneWidget);
      final list =
          tester.getRect(find.byKey(const ValueKey('dollars-activity-list')));
      final card = tester.getRect(wide);
      expect(list.width - card.width, moreOrLessEquals(32.w, epsilon: 0.5));
      // Compact: well under a square's height.
      expect(card.height, lessThan(110.h));
      // The name on the left, the value toward the end.
      final title = tester.getRect(find.descendant(
          of: wide, matching: find.byKey(const ValueKey('portfolio-row-title'))));
      final value = tester.getRect(find.descendant(
          of: wide, matching: find.byKey(const ValueKey('portfolio-row-value'))));
      expect(value.left, greaterThan(title.left));
      expect(value.center.dy, moreOrLessEquals(card.center.dy, epsilon: 6));
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets(
        'three: the two biggest squares side by side, the third the '
        'full-width card under them, never a lone half square',
        (tester) async {
      await mount(tester, 3);
      final cells = inSquares('portfolio-square');
      expect(cells, findsNWidgets(2));
      final a = tester.getRect(cells.at(0));
      final b = tester.getRect(cells.at(1));
      expect(a.top, moreOrLessEquals(b.top, epsilon: 0.5));
      final wide = tester.getRect(inSquares('portfolio-wide'));
      expect(wide.top, moreOrLessEquals(a.bottom + 10.w, epsilon: 0.5));
      expect(wide.left, moreOrLessEquals(a.left, epsilon: 0.5));
      expect(wide.right, moreOrLessEquals(b.right, epsilon: 0.5));
      // Biggest first: BTC and ETH squares, SOL the card.
      final rows = tester
          .widgetList<HlPositionRow>(
              find.descendant(of: squares, matching: find.byType(HlPositionRow)))
          .map((r) => (r.key! as ValueKey<String>).value)
          .toList();
      expect(rows, ['hl-BTC', 'hl-ETH', 'hl-SOL']);
      expect(
          find.descendant(
              of: inSquares('portfolio-wide'),
              matching: find.byType(HlPositionRow)),
          findsNothing,
          reason: 'the card is drawn by the row itself');
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('five: the four biggest as squares, two by two; no card',
        (tester) async {
      await mount(tester, 5);
      expect(inSquares('portfolio-square'), findsNWidgets(4));
      expect(inSquares('portfolio-wide'), findsNothing);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  });

  testWidgets(
      'an open-position square says what it is winning in money: "▲ \$0.61" '
      'over "5.4%" in the corner, the value the big number (founder, 6 '
      'November 2026)', (tester) async {
    await pumpInvestments(tester, overrides: [
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
          const HyperliquidTradingState(isInitialized: true, positions: [
            HlPerpPosition(
                coin: 'BTC',
                szi: 0.0001,
                entryPx: 100000,
                positionValue: 10.61,
                unrealizedPnl: 0.61,
                returnOnEquity: 0.054,
                liquidationPx: null,
                marginUsed: 11.3,
                leverageType: 'cross',
                leverageValue: 1,
                maxLeverage: 40),
          ]))),
    ]);
    final squares = find.byKey(const ValueKey('dollars-activity-squares'));
    String figure(String key) => tester
        .widget<RollingFigure>(find.descendant(
            of: squares, matching: find.byKey(ValueKey(key))))
        .text;
    expect(figure('portfolio-row-pnl-usd'), r'▲ $0.61');
    expect(figure('portfolio-row-pnl'), '5.4%');
    expect(figure('portfolio-row-value'), r'$11.91');
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  test('the bar sends the key the Portfolio button sent', () {
    expect(UsdAccountActionBar.portfolioActionId, 'portfolio');
  });
}
