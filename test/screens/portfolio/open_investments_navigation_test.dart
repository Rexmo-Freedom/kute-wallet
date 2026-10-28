// Positions and the Portfolio (owner decision October 2026). Positions,
// the Investments tab's third pill, is everything held now at both venues
// in ONE list, largest first whatever the venue, with the resting orders
// under their heading (one count, one Cancel all). The Portfolio, opened
// full screen from the Investments balance, a venue dock or a link, is one
// page: the P&L chart with its All · Investing · Predictions toggle, the
// Active | Historic pair over one allocation donut and one card of
// figures, then the Activity. No tabs, no total header, no deposit or
// withdrawal buttons.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/active_shell_tab_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show
        hyperliquidAccountMarketProvider,
        hyperliquidPerpMarketsProvider,
        hyperliquidSpotMarketsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show
        PolymarketPosition,
        polymarketActivePositionsProvider,
        polymarketClaimablePositionsProvider;
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_order_metadata_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/hyperliquid/components/open_orders_sheet.dart'
    show HlOrderRow;
import 'package:kute/screens/polymarket/components/open_orders_sheet.dart'
    show PolyOrderRow;
import 'package:kute/screens/portfolio/investments_portfolio.dart'
    show PortfolioSection, portfolioSectionProvider;
import 'package:kute/screens/portfolio/components/position_rows.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/providers/usd_rewards_provider.dart';
import 'package:kute/screens/portfolio/portfolio_activity.dart'
    show PortfolioActivitySliver;
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/models/usd_rewards_model.dart';
import 'package:kute/providers/portfolio_performance_provider.dart'
    show portfolioPerformanceProvider;
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart';
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/screens/shared/charts/kute_chart_range_pills.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/portfolio_tabs.dart';
import 'package:kute/screens/shared/trade_results_button.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

import '../../helpers/portfolio_overrides.dart';
import '../usd/investments_harness.dart' show RecordingRewardsApi;

const _btcPosition = HlPerpPosition(
    coin: 'BTC',
    szi: 0.1,
    entryPx: 60000,
    positionValue: 6000,
    unrealizedPnl: 0,
    returnOnEquity: 0,
    liquidationPx: null,
    marginUsed: 600,
    leverageType: 'cross',
    leverageValue: 10,
    maxLeverage: 40);

const _withPosition =
    HyperliquidTradingState(isInitialized: true, positions: [_btcPosition]);

/// A resting Investing order placed at second 1,000.
const _hlOrder = HlOpenOrder(
    coin: 'BTC',
    oid: 7,
    isBuy: true,
    limitPx: 50000,
    sz: 0.1,
    origSz: 0.1,
    timestamp: 1000 * 1000,
    cloid: null,
    reduceOnly: false,
    orderType: 'Limit',
    isTrigger: false,
    triggerPx: null);

const _withOrder =
    HyperliquidTradingState(isInitialized: true, openOrders: [_hlOrder]);

/// One Investing fill (an open of the BTC position), for the Activity.
final _withFill = HyperliquidTradingState(isInitialized: true, recentFills: [
  HlFill.fromJson({
    'coin': 'BTC',
    'tid': '1',
    'oid': 1,
    'hash': 'h1',
    'time':
        DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
    'startPosition': '0',
    'sz': '0.1',
    'px': '60000',
    'side': 'B',
    'closedPnl': '0',
    'fee': '1',
    'feeToken': 'USDC',
    'dir': 'Open Long',
  }),
]);

/// A resting Predictions order placed at second 2,000: newer than the
/// Investing one.
const _pmOrder = Order(
    id: 'pm-1',
    market: '0xmarket',
    assetId: '0xtoken',
    owner: '0xme',
    side: 'BUY',
    price: '0.40',
    originalSize: '10',
    sizeMatched: '0',
    outcome: 'Yes',
    timestamp: '2000');

final _placing = PlacingBet(
    placementId: 'p1',
    tokenId: 't1',
    marketQuestion: 'Will it rain tomorrow?',
    outcomeName: 'Yes',
    amount: 5,
    shares: 10,
    avgPrice: 0.5,
    startedAt: DateTime(2026, 10, 1));

Future<void> _pump(WidgetTester tester,
    {required Widget home,
    HyperliquidTradingState state = const HyperliquidTradingState(),
    List<PlacingBet> placing = const [],
    List<Order> pmOrders = const [],
    PortfolioVenues venues = kPortfolioBothVenues,
    List<Override> overrides = const [],
    bool settle = true,
    int balancePrivacy = 0}) async {
  tester.view.physicalSize = const Size(400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        ...portfolioOverrides(trading: state, placing: placing, venues: venues),
        hyperliquidLiveMidProvider('BTC').overrideWith((_) => null),
        hyperliquidAccountMarketProvider('BTC').overrideWith((_) => null),
        // The order rows name their market off the venue's lists: none,
        // offline.
        hyperliquidPerpMarketsProvider.overrideWith((_) async => <HlMarket>[]),
        hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
        polymarketOpenOrdersProvider
            .overrideWith((_) => Stream.value(pmOrders)),
        polymarketOrderMetadataProvider.overrideWith((_) async => const {}),
        settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
            balancePrivacy: balancePrivacy))),
        ...overrides,
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
              splashFactory: NoSplash.splashFactory,
              fontFamily: 'Inter',
              extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      )));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _PendingTrading extends HyperliquidTradingNotifier {
  _PendingTrading(this.result);
  final Future<HyperliquidTradingState> result;

  @override
  Future<HyperliquidTradingState> build() => result;
}

/// A card's big figure ([PortfolioCardValue] rolls its digits, so the
/// text is not one Text widget).
Finder _figure(String text) =>
    find.byWidgetPredicate((w) => w is RollingFigure && w.text == text);

List<(String, Map<String, Object>?)> _events() {
  final events = <(String, Map<String, Object>?)>[];
  TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  addTearDown(() => TrackingService.debugTrackObserver = null);
  return events;
}

/// The venues' P&L series: Investing forty days old, Predictions twenty.
List<Override> _performance() {
  final now = DateTime.now().toUtc();
  DateTime ago(int days) => now.subtract(Duration(days: days));
  PortfolioPerformance series(List<(int, double)> points) =>
      PortfolioPerformance(
          points: [
            for (final (days, pnl) in points)
              PortfolioPnlPoint(timestamp: ago(days), pnlUsd: pnl)
          ],
          totalPnlUsd: points.last.$2,
          sourceLabel: '',
          basisLabel: 'P&L',
          coverageLabel: 'All time');
  return [
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.trading))
        .overrideWith((_) async => series([(40, -5), (10, 9), (2, 15)])),
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.predictions))
        .overrideWith((_) async => series([(20, 0), (1, 4)])),
  ];
}

/// The rewards ledger with two paid days (and one pending).
class _PaidRewardsApi extends RecordingRewardsApi {
  @override
  Future<PayoutHistoryResponse> getPayoutHistory(String pubkey,
      {int limit = 30, int offset = 0}) async {
    calls.add('payouts');
    RewardPayout payout(String day, int sats, String status) => RewardPayout(
        day: day,
        usdbBalanceDisplay: 25,
        rewardsBracket: 0,
        payoutSats: sats,
        status: status);
    return PayoutHistoryResponse(
        pubkey: 'pub',
        payouts: [
          payout('2026-10-10', 1000, 'paid'),
          payout('2026-10-11', 500, 'paid'),
          payout('2026-10-12', 300, 'pending'),
        ],
        total: 3);
  }
}

/// An open Polymarket position worth $50 (100 shares at 50¢).
const _pmPosition = PolymarketPosition(
    marketId: '0xm1',
    marketQuestion: 'Will it snow in May?',
    outcome: 'Yes',
    size: 100,
    avgPrice: 0.4,
    currentPrice: 0.5,
    pnl: 10,
    pnlPercent: 25,
    isResolved: false);

/// A small second Investing position: worth $10 (its margin, no P&L).
const _ethPosition = HlPerpPosition(
    coin: 'ETH',
    szi: 0.01,
    entryPx: 3000,
    positionValue: 30,
    unrealizedPnl: 0,
    returnOnEquity: 0,
    liquidationPx: null,
    marginUsed: 10,
    leverageType: 'cross',
    leverageValue: 3,
    maxLeverage: 25);

/// Mounts Positions, the Investments tab's third pill, on its own.
Future<void> _pumpPositions(WidgetTester tester,
        {HyperliquidTradingState state = const HyperliquidTradingState(),
        List<PlacingBet> placing = const [],
        List<Order> pmOrders = const [],
        List<PolymarketPosition> pmPositions = const [],
        PortfolioVenues venues = kPortfolioBothVenues}) =>
    _pump(tester,
        state: state,
        placing: placing,
        pmOrders: pmOrders,
        venues: venues,
        overrides: [
          polymarketActivePositionsProvider.overrideWith((_) => pmPositions),
          hyperliquidLiveMidProvider('ETH').overrideWith((_) => null),
          hyperliquidAccountMarketProvider('ETH').overrideWith((_) => null),
        ],
        home: const Scaffold(body: PortfolioPositions()));

/// The vertical position of [finder]'s top edge.
double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Portfolio loading cards', () {
    const venues = PortfolioVenues(trading: true, predictions: false);
    for (final fails in [false, true]) {
      testWidgets('performance shimmer becomes ${fails ? 'retry' : 'empty'}',
          (tester) async {
        final result = Completer<PortfolioPerformance>();
        await _pump(tester,
            home: const Scaffold(
                body: PortfolioStatisticsOverview(
                    trading: true, predictions: false)),
            venues: venues,
            settle: false,
            overrides: [
              portfolioPerformanceProvider(const PortfolioPerformanceRequest(
                      venue: PortfolioPerformanceVenue.trading))
                  .overrideWith((_) => result.future),
            ]);
        expect(find.byKey(const ValueKey('portfolio-performance-loading')),
            findsOneWidget);
        expect(find.byType(SkeletonBar), findsWidgets);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(NoActivityState), findsNothing);

        if (fails) {
          result.completeError(StateError('offline'));
        } else {
          result.complete(kPortfolioNoPerformance);
        }
        await tester.pumpAndSettle();
        expect(find.byType(SkeletonCardList), findsNothing);
        expect(find.byType(NoActivityState),
            fails ? findsNothing : findsOneWidget);
        expect(find.text('Retry'), fails ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    for (final fullscreen in [false, true]) {
      testWidgets(
          '${fullscreen ? 'full portfolio' : 'positions pill'} '
          'shows shimmer until positions arrive', (tester) async {
        final result = Completer<HyperliquidTradingState>();
        await _pump(tester,
            home: Scaffold(
                body: fullscreen
                    ? Consumer(
                        builder: (context, ref, _) => CustomScrollView(
                            slivers: portfolioPositionsSlivers(
                                context, ref, venues)))
                    : const PortfolioPositions()),
            venues: venues,
            settle: false,
            overrides: [
              hyperliquidTradingProvider
                  .overrideWith(() => _PendingTrading(result.future)),
            ]);
        // The rows' own shimmer: skeleton rows, not cards.
        expect(find.byType(SkeletonRowList), findsOneWidget);
        expect(find.byType(NoActivityState), findsNothing);

        result.complete(_withPosition);
        await tester.pumpAndSettle();
        expect(find.byType(SkeletonRowList), findsNothing);
        expect(find.byType(HlPositionRow), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Positions (the Investments pill)', () {
    testWidgets(
        'nothing held and nothing resting: the one Sal empty state, no '
        'Wallet section, no headings', (tester) async {
      await _pumpPositions(tester);
      expect(find.text('No positions yet'), findsOneWidget);
      expect(find.byType(NoActivityState), findsOneWidget);
      expect(find.text('Wallet'), findsNothing);
      expect(find.text('250,000 sats'), findsNothing);
      expect(_figure(r'$42.50'), findsNothing);
      expect(
          find.byKey(const ValueKey('portfolio-orders-heading')), findsNothing);
      expect(find.text('No open investments'), findsNothing);
      expect(find.text('No open predictions'), findsNothing);
      expect(find.textContaining('No resting orders.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'one merged list across both venues: no venue sections, positions '
        'largest first whatever the venue, then the orders under their '
        'heading, newest first, with one count and one Cancel all',
        (tester) async {
      await _pumpPositions(tester,
          state: const HyperliquidTradingState(
              isInitialized: true,
              positions: [_ethPosition, _btcPosition],
              openOrders: [_hlOrder]),
          pmPositions: const [_pmPosition],
          pmOrders: const [_pmOrder]);
      // No venue sections, no total, no tabs.
      expect(find.text('Investing'), findsNothing);
      expect(find.text('Predictions'), findsNothing);
      expect(find.textContaining('total'), findsNothing);
      expect(find.byType(PortfolioTabs), findsNothing);
      expect(find.text('No positions yet'), findsNothing);
      // BTC ($600) over the Predictions position ($50) over ETH ($10).
      final btc = find.byKey(const ValueKey('hl-BTC'));
      // The card writes its title whole, its first lines beside the
      // figure and the rest under it when it runs past: found by the
      // title it reads as.
      final snow = find.byWidgetPredicate(
          (w) =>
              (w is Text && w.data == 'Will it snow in May?') ||
              (w is Semantics && w.properties.label == 'Will it snow in May?'),
          description: 'the title "Will it snow in May?"');
      final eth = find.byKey(const ValueKey('hl-ETH'));
      expect(btc, findsOneWidget);
      expect(snow, findsOneWidget);
      expect(eth, findsOneWidget);
      expect(_top(tester, btc), lessThan(_top(tester, snow)));
      expect(_top(tester, snow), lessThan(_top(tester, eth)));
      // The orders under their heading, after every position.
      final heading = find.byKey(const ValueKey('portfolio-orders-heading'));
      await tester.scrollUntilVisible(find.byType(HlOrderRow), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(heading, findsOneWidget);
      expect(find.descendant(of: heading, matching: find.text('Orders')),
          findsOneWidget);
      expect(find.byType(PolyOrderRow), findsOneWidget);
      expect(find.byType(HlOrderRow), findsOneWidget);
      // The Predictions order was placed later: it leads.
      expect(_top(tester, find.byType(PolyOrderRow)),
          lessThan(_top(tester, find.byType(HlOrderRow))));
      expect(_top(tester, heading),
          lessThan(_top(tester, find.byType(PolyOrderRow))));
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('portfolio-orders-count')))
              .data,
          '2');
      expect(find.byKey(const ValueKey('portfolio-orders-cancel-all')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'settled results and bets on their way lead, ahead of larger '
        'positions', (tester) async {
      await _pumpPositions(tester, state: _withPosition, placing: [_placing]);
      expect(find.byType(HlPositionRow), findsOneWidget);
      expect(find.text('Will it rain tomorrow?'), findsOneWidget);
      expect(_top(tester, find.text('Will it rain tomorrow?')),
          lessThan(_top(tester, find.byType(HlPositionRow))));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a won, redeemable position reads Settled: no Claim button, no '
        '"Ready to claim" (the win is claimed automatically)', (tester) async {
      const won = PolymarketPosition(
          marketId: '0xwon',
          marketQuestion: 'Bitcoin Up or Down – October 20',
          outcome: 'Up',
          size: 4.67,
          avgPrice: 0.56,
          currentPrice: 1,
          pnl: 2.06,
          pnlPercent: 78.6,
          isResolved: true,
          won: true,
          tokenId: 'tok-up');
      await _pump(tester,
          overrides: [
            polymarketActivePositionsProvider.overrideWith((_) => const []),
            polymarketClaimablePositionsProvider
                .overrideWith((_) => const [won]),
          ],
          home: const Scaffold(body: PortfolioPositions()));
      // The state replaces the facts on the row's one line.
      expect(find.text('Up · Settled'), findsOneWidget);
      expect(find.textContaining('Ready to claim'), findsNothing);
      expect(find.textContaining('Claim'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'only orders resting: the Orders heading with its count and Cancel '
        'all, no empty state', (tester) async {
      await _pumpPositions(tester, state: _withOrder);
      expect(find.text('No positions yet'), findsNothing);
      expect(find.byKey(const ValueKey('portfolio-orders-heading')),
          findsOneWidget);
      expect(find.byType(HlOrderRow), findsOneWidget);
      expect(find.byKey(const ValueKey('portfolio-orders-cancel-all')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a venue gated off has no rows', (tester) async {
      await _pumpPositions(tester,
          state: _withPosition,
          placing: [_placing],
          venues: const PortfolioVenues(trading: false, predictions: true));
      expect(find.byType(HlPositionRow), findsNothing);
      expect(find.text('Will it rain tomorrow?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no venue at all: the one empty state', (tester) async {
      await _pumpPositions(tester,
          venues: const PortfolioVenues(trading: false, predictions: false));
      expect(find.text('No positions yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a placed order\'s "View positions" opens the Portfolio on Balances, '
        'where the positions are, pushing nothing', (tester) async {
      await _pump(tester,
          overrides: [
            activeShellTabProvider.overrideWith((_) => ActiveNavTab.usd),
          ],
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => openInvestmentsPositions(context),
                      child: const Text('View positions')))));
      final container =
          ProviderScope.containerOf(tester.element(find.byType(TextButton)));
      expect(container.read(investmentsTabProvider), InvestmentsTab.investing);
      await tester.tap(find.text('View positions'));
      await tester.pumpAndSettle();
      expect(container.read(investmentsTabProvider), InvestmentsTab.positions);
      expect(
          container.read(portfolioSectionProvider), PortfolioSection.balances);
      expect(find.byType(OpenInvestmentsScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the Portfolio screen (from the balance)', () {
    testWidgets(
        'its app bar and back, no total header, no deposit or withdrawal, '
        'no tabs: the chart, the pair, the donut and the figures, then the '
        'Activity at the bottom', (tester) async {
      final events = _events();
      await _pump(tester,
          state: _withFill,
          overrides: _performance(),
          home: const OpenInvestmentsScreen(source: 'test'));
      expect(find.text('Portfolio'), findsOneWidget);
      expect(find.byType(KuteBackButton), findsOneWidget);
      expect(find.byType(InvestmentBalanceHeader), findsNothing);
      expect(find.text('Investing total'), findsNothing);
      expect(find.text('Deposit'), findsNothing);
      expect(find.text('Withdraw'), findsNothing);
      expect(find.byType(InvestmentActionBar), findsNothing);
      expect(find.byType(TradeResultsButton), findsNothing);
      // The old tabs are gone.
      expect(find.byType(PortfolioTabs), findsNothing);
      expect(find.text('Statistics', skipOffstage: false), findsNothing);
      expect(find.text('Open', skipOffstage: false), findsNothing);
      // Top down.
      expect(find.byType(PortfolioStatisticsOverview), findsOneWidget);
      expect(find.byType(PortfolioPnlChart), findsOneWidget);
      final pair = find.byKey(const ValueKey('statistics-active'));
      expect(_top(tester, find.byType(PortfolioPnlChart)),
          lessThan(_top(tester, pair)));
      final heading = find.byKey(const ValueKey('portfolio-activity-heading'));
      await tester.scrollUntilVisible(heading, 200,
          scrollable: find
              .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable))
              .first);
      await tester.pumpAndSettle();
      expect(find.descendant(of: heading, matching: find.text('Activity')),
          findsOneWidget);
      expect(find.byType(PortfolioActivitySliver), findsOneWidget);
      expect(_top(tester, heading), greaterThan(_top(tester, pair)));
      expect(events.where((e) => e.$1 == 'portfolio_opened').single.$2,
          {'source': 'test'});
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'one P&L chart whose venue rows switch the series, headline and '
        'change', (tester) async {
      final events = _events();
      await _pump(tester,
          overrides: _performance(),
          home: const OpenInvestmentsScreen(source: 'test'));
      expect(find.byType(PortfolioStatistics), findsNothing);
      expect(find.byType(PortfolioPnlChart), findsOneWidget);
      // Active with nothing open: no chart (founder, 28 October 2026), the
      // venue rows stay to pick from; Historic charts.
      expect(find.byType(KuteLineChart), findsNothing);
      expect(find.byType(KuteRangePills), findsNothing);
      await tester
          .ensureVisible(find.byKey(const ValueKey('statistics-historic')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('statistics-historic')));
      await tester.pumpAndSettle();
      expect(events.last.$1, 'portfolio_allocation_view_changed');
      expect(events.last.$2, {'view': 'historic'});
      expect(find.byType(KuteLineChart), findsOneWidget);
      // The range row under the plot, 1W to ALL.
      expect(find.byType(KuteRangePills), findsOneWidget);
      expect(find.text('Profit and loss'), findsOneWidget);
      String headline() => tester
          .widget<RollingNumberText>(
              find.byKey(const ValueKey('statistics-pnl-headline')))
          .text;
      // All: the venues added on the moments either published,
      // Investing's 15 and Predictions' 4.
      expect(headline(), r'+$19.00');
      // No All · Investing · Predictions control: the venue rows in the
      // card pick the series.
      expect(find.byKey(const ValueKey('statistics-venue-all')), findsNothing);
      for (final venue in ['investing', 'predictions']) {
        expect(
            find.descendant(
                of: find.byType(PortfolioPnlChart),
                matching: find.byKey(ValueKey('pnl-venue-$venue-pick'))),
            findsOneWidget);
      }
      // No Earn, ever.
      expect(find.text('Earn', skipOffstage: false), findsNothing);

      double lineEnd() =>
          tester.widget<KuteLineChart>(find.byType(KuteLineChart)).values.last;
      expect(lineEnd(), 19);
      await tester
          .tap(find.byKey(const ValueKey('pnl-venue-predictions-pick')));
      await tester.pumpAndSettle();
      expect(headline(), r'+$4.00');
      // The row filters the line: Predictions' alone.
      expect(lineEnd(), 4);
      expect(events.last.$1, 'portfolio_statistics_venue_toggled');
      expect(events.last.$2, {'venue': 'polymarket'});

      // Back to Active: nothing open at Predictions, so no chart.
      await tester
          .ensureVisible(find.byKey(const ValueKey('statistics-active')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('statistics-active')));
      await tester.pumpAndSettle();
      expect(events.last.$1, 'portfolio_allocation_view_changed');
      expect(events.last.$2, {'view': 'active'});
      expect(find.byType(KuteLineChart), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'never traded and nothing in the Activity: the one empty state, no '
        'pills over nothing', (tester) async {
      await _pump(tester, home: const OpenInvestmentsScreen(source: 'test'));
      expect(find.byType(KuteLineChart), findsNothing);
      expect(
          find.byKey(const ValueKey('statistics-chart-empty')), findsOneWidget);
      expect(find.byType(NoActivityState), findsOneWidget);
      expect(find.byKey(const ValueKey('statistics-active')), findsNothing);
      expect(find.byKey(const ValueKey('portfolio-activity-heading')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without Predictions the chart is the Investing figure only',
        (tester) async {
      final events = _events();
      await _pump(tester,
          venues: const PortfolioVenues(trading: true, predictions: false),
          overrides: _performance(),
          home: const OpenInvestmentsScreen(source: 'test'));
      expect(find.byType(PortfolioPnlChart), findsOneWidget);
      expect(
          tester
              .widget<RollingNumberText>(
                  find.byKey(const ValueKey('statistics-pnl-headline')))
              .text,
          r'+$15.00');
      // One venue: no toggle (it would only say the headline again).
      expect(find.byKey(const ValueKey('statistics-venue-all')), findsNothing);
      // Nothing open: Historic charts it.
      await tester
          .ensureVisible(find.byKey(const ValueKey('statistics-historic')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('statistics-historic')));
      await tester.pumpAndSettle();
      // The scrub event names the one venue charted (a press on the plot).
      await tester.longPress(find.byWidgetPredicate((w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_KuteLinePainter'));
      await tester.pumpAndSettle();
      expect(
          events
              .where((e) => e.$1 == 'portfolio_performance_chart_scrubbed')
              .single
              .$2,
          {'venue': 'hyperliquid'});
      expect(events.where((e) => e.$1 == 'portfolio_performance_range_changed'),
          isEmpty);
      expect(tester.takeException(), isNull);
    });

    // Earn is shown nowhere (owner decision), whatever `usd.earn` says:
    // no figure, no chart, no heading, no rewards read, no `usd_earn_*`.
    for (final earnAllowed in [true, false]) {
      final label = earnAllowed ? 'usd.earn allowed' : 'usd.earn denied';

      testWidgets(
          '$label: with P&L there is no Earn figure and the rewards API is '
          'never read', (tester) async {
        final api = _PaidRewardsApi();
        final events = _events();
        await _pump(tester,
            overrides: [
              ..._performance(),
              usdEarnEnabledProvider.overrideWithValue(earnAllowed),
              sparkIdentityPubkeyProvider.overrideWith((_) async => 'pub'),
              usdRewardsApiProvider.overrideWithValue(api),
            ],
            home: const OpenInvestmentsScreen(source: 'test'));
        expect(find.byType(PortfolioPnlChart), findsOneWidget);
        expect(find.byKey(const ValueKey('statistics-active')), findsOneWidget);
        expect(find.text('Earn', skipOffstage: false), findsNothing);
        expect(find.textContaining('1,500 sats', skipOffstage: false),
            findsNothing);
        expect(find.byKey(const ValueKey('portfolio-statistics-earn')),
            findsNothing);
        expect(events.where((e) => e.$1.startsWith('usd_earn_')), isEmpty);
        expect(api.calls, isEmpty);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      });

      testWidgets('$label, nothing ever done: the one empty state, no Earn',
          (tester) async {
        final api = RecordingRewardsApi(estimatedSatsToday: 1234);
        final events = _events();
        await _pump(tester,
            overrides: [
              usdEarnEnabledProvider.overrideWithValue(earnAllowed),
              sparkIdentityPubkeyProvider.overrideWith((_) async => 'pub'),
              usdRewardsApiProvider.overrideWithValue(api),
            ],
            home: const OpenInvestmentsScreen(source: 'test'));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byKey(const ValueKey('statistics-chart-empty')),
            findsOneWidget);
        expect(find.byType(NoActivityState), findsOneWidget);
        expect(find.byType(KuteLineChart), findsNothing);
        expect(find.text('Earn', skipOffstage: false), findsNothing);
        expect(events.where((e) => e.$1.startsWith('usd_earn_')), isEmpty);
        expect(events.where((e) => e.$1 == 'usd_chart_range_changed'), isEmpty);
        expect(api.calls, isEmpty);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      });

      testWidgets('$label, no venue: the empty state, no Earn section',
          (tester) async {
        final api = RecordingRewardsApi();
        await _pump(tester,
            venues: const PortfolioVenues(trading: false, predictions: false),
            overrides: [
              usdEarnEnabledProvider.overrideWithValue(earnAllowed),
              sparkIdentityPubkeyProvider.overrideWith((_) async => 'pub'),
              usdRewardsApiProvider.overrideWithValue(api),
            ],
            home: const OpenInvestmentsScreen(source: 'test'));
        expect(find.byType(PortfolioStatisticsOverview), findsNothing);
        expect(find.byType(NoActivityState), findsOneWidget);
        expect(find.byKey(const ValueKey('portfolio-statistics-earn')),
            findsNothing);
        expect(find.text('Earn', skipOffstage: false), findsNothing);
        expect(api.calls, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    for (final product in InvestmentsProduct.values) {
      testWidgets(
          'the ${product.name} dock\'s Portfolio opens the Portfolio screen '
          'full screen', (tester) async {
        final events = _events();
        await _pump(tester,
            overrides: [
              activeShellTabProvider.overrideWith((_) => ActiveNavTab.usd),
            ],
            home: Scaffold(
                bottomNavigationBar: InvestmentActionBar(product: product)));
        expect(find.byType(OpenInvestmentsScreen), findsNothing);
        final container = ProviderScope.containerOf(
            tester.element(find.byType(InvestmentActionBar)));
        await tester.tap(find.text('Portfolio'));
        await tester.pumpAndSettle();
        expect(find.byType(OpenInvestmentsScreen), findsOneWidget);
        expect(
            container.read(investmentsTabProvider), InvestmentsTab.investing);
        expect(events.where((e) => e.$1 == 'portfolio_opened').single.$2, {
          'source': product == InvestmentsProduct.predictions
              ? 'dock_predictions'
              : 'dock_investing'
        });
        expect(find.text('Withdraw'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
