// The one Portfolio screen (owner decision October 2026): the same screen
// from every door, both venues on every tab with no third row to switch
// them — Open is one list of positions under the venues' plain names,
// Orders one merged list newest first, Statistics the venues' figures and
// Earn stacked under section headings — positions only (no Wallet
// section), no total header and no deposit or withdrawal buttons.

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
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_order_metadata_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/hyperliquid/components/open_orders_sheet.dart'
    show HlOrderRow;
import 'package:kute/screens/polymarket/components/open_orders_sheet.dart'
    show PolyOrderRow;
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/providers/usd_rewards_provider.dart';
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/portfolio/portfolio_orders.dart';
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/portfolio_tabs.dart';
import 'package:kute/screens/shared/trade_results_button.dart';
import 'package:kute/screens/usd/components/usd_earn_chart.dart';
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
    {int initialTab = 0,
    Widget? home,
    HyperliquidTradingState state = const HyperliquidTradingState(),
    List<PlacingBet> placing = const [],
    List<Order> pmOrders = const [],
    PortfolioVenues venues = kPortfolioBothVenues,
    List<Override> overrides = const [],
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
        polymarketOpenOrdersProvider.overrideWith((_) => Stream.value(pmOrders)),
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
          home: home ??
              OpenInvestmentsScreen(source: 'test', initialTab: initialTab),
        ),
      )));
  await tester.pumpAndSettle();
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

/// The venues of the Statistics sections on screen, top to bottom.
List<PortfolioPerformanceVenue> _statisticsVenues(WidgetTester tester) {
  final finder = find.byType(PortfolioStatistics);
  final sections = tester.widgetList<PortfolioStatistics>(finder).toList();
  final tops = [
    for (var i = 0; i < sections.length; i++)
      (tester.getTopLeft(finder.at(i)).dy, sections[i].venue)
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final t in tops) t.$2];
}

/// Every pill on screen belongs to the tab strip: no third row under it.
void _expectNoPillsBeyondTabs(WidgetTester tester) {
  final all = find.byType(KutePill).evaluate().length;
  final tabs = find
      .descendant(of: find.byType(PortfolioTabs), matching: find.byType(KutePill))
      .evaluate()
      .length;
  expect(all, tabs);
  expect(tabs, greaterThan(0));
}

/// Switches the Portfolio to tab [index] through its own controller.
Future<void> _openTab(WidgetTester tester, int index) async {
  final context = tester.element(find.byType(PortfolioTabs));
  DefaultTabController.of(context).animateTo(index);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'no total header, no deposit or withdrawal, no dock: the tabs over '
      'the merged list', (tester) async {
    await _pump(tester);
    expect(find.text('Portfolio'), findsOneWidget);
    expect(find.byType(InvestmentBalanceHeader), findsNothing);
    expect(find.text('Investing total'), findsNothing);
    expect(find.text('Predictions total'), findsNothing);
    expect(find.text('Deposit'), findsNothing);
    expect(find.text('Withdraw'), findsNothing);
    expect(find.byType(InvestmentActionBar), findsNothing);
    expect(find.byType(TradeResultsButton), findsNothing);
    expect(find.text('Statistics', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Open is one list with no filter row: positions only, one empty '
      'line when nothing is open', (tester) async {
    await _pump(tester);
    // No third row under the tabs: the tab pills are the only pills.
    expect(find.byKey(const ValueKey('portfolio-filter-all')), findsNothing);
    _expectNoPillsBeyondTabs(tester);
    // No Wallet section: the account's bitcoin and dollars are not
    // positions (they live in the Investments hero).
    expect(find.text('Wallet'), findsNothing);
    expect(find.text('250,000 sats'), findsNothing);
    expect(_figure(r'$250.00'), findsNothing);
    expect(find.text('Investments'), findsNothing);
    expect(_figure(r'$42.50'), findsNothing);
    // One combined line, no per-venue empty states, no venue sections.
    expect(find.text('No positions yet'), findsOneWidget);
    expect(find.text('No open investments'), findsNothing);
    expect(find.text('No open predictions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Open lists both venues under their plain names, with no total and '
      'nothing to switch', (tester) async {
    final events = _events();
    await _pump(tester, state: _withPosition, placing: [_placing]);
    expect(find.text('Investing'), findsOneWidget); // the section only
    expect(find.text('Predictions'), findsOneWidget);
    expect(find.byType(HlPortfolioPositionCard), findsOneWidget);
    expect(find.text('Will it rain tomorrow?'), findsOneWidget);
    expect(find.text('No positions yet'), findsNothing);
    expect(find.textContaining('total'), findsNothing);
    // The Investing section above the Predictions one.
    expect(tester.getTopLeft(find.text('Investing')).dy,
        lessThan(tester.getTopLeft(find.text('Predictions')).dy));
    expect(find.byKey(const ValueKey('portfolio-filter-trading')),
        findsNothing);
    expect(events.where((e) => e.$1 == 'portfolio_tab_changed'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a venue with nothing open has no section', (tester) async {
    await _pump(tester, state: _withPosition);
    expect(find.text('Investing'), findsOneWidget);
    expect(find.text('Predictions'), findsNothing);
    expect(find.text('No open predictions'), findsNothing);
    expect(find.byType(HlPortfolioPositionCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Open tab is the plain position list: no category donut',
      (tester) async {
    await _pump(tester, state: _withPosition);
    expect(find.byType(HlPortfolioPositionCard), findsOneWidget);
    expect(find.byType(KuteDonutChart), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a venue gated off loses its section', (tester) async {
    await _pump(tester,
        state: _withPosition,
        placing: [_placing],
        venues: const PortfolioVenues(trading: false, predictions: true));
    expect(find.text('Investing'), findsNothing);
    expect(find.byType(HlPortfolioPositionCard), findsNothing);
    expect(find.text('Predictions'), findsOneWidget);
    expect(find.text('Will it rain tomorrow?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no venue at all: the one quiet line', (tester) async {
    await _pump(tester,
        venues: const PortfolioVenues(trading: false, predictions: false));
    expect(find.byKey(const ValueKey('portfolio-filter-all')), findsNothing);
    expect(find.text('No positions yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Orders is one merged list of both venues\' open orders, newest '
      'first, each its venue\'s own row, with one count and one Cancel all',
      (tester) async {
    await _pump(tester,
        initialTab: 1, state: _withOrder, pmOrders: const [_pmOrder]);
    expect(find.byType(PortfolioOpenOrders), findsOneWidget);
    expect(find.byType(HlOrderRow), findsOneWidget);
    expect(find.byType(PolyOrderRow), findsOneWidget);
    // The Predictions order was placed later: it leads.
    expect(tester.getTopLeft(find.byType(PolyOrderRow)).dy,
        lessThan(tester.getTopLeft(find.byType(HlOrderRow)).dy));
    expect(find.text('2'), findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-orders-cancel-all')),
        findsOneWidget);
    // No switch, no second title.
    expect(find.byKey(const ValueKey('portfolio-orders-trading')),
        findsNothing);
    expect(find.byKey(const ValueKey('portfolio-orders-predictions')),
        findsNothing);
    expect(find.text('Open orders'), findsNothing);
    _expectNoPillsBeyondTabs(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Orders with nothing resting at either venue is one quiet line',
      (tester) async {
    await _pump(tester, initialTab: 1);
    expect(find.textContaining('No resting orders.'), findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-orders-cancel-all')),
        findsNothing);
    _expectNoPillsBeyondTabs(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Statistics stacks Investing then Predictions under section '
      'headings, each with its own figures, and nothing to switch',
      (tester) async {
    final events = _events();
    await _pump(tester, initialTab: 3);
    expect(_statisticsVenues(tester), [
      PortfolioPerformanceVenue.trading,
      PortfolioPerformanceVenue.predictions,
    ]);
    final investing = find.byKey(const ValueKey('portfolio-statistics-trading'));
    final predictions =
        find.byKey(const ValueKey('portfolio-statistics-predictions'));
    expect(investing, findsOneWidget);
    expect(predictions, findsOneWidget);
    expect(tester.getTopLeft(investing).dy,
        lessThan(tester.getTopLeft(predictions).dy));
    // No Earn section while the backend does not allow it.
    expect(find.byKey(const ValueKey('portfolio-statistics-earn')),
        findsNothing);
    expect(find.byType(UsdEarnChart, skipOffstage: false), findsNothing);
    // Each section keeps its own Active | Historic pair.
    expect(find.byKey(const ValueKey('statistics-active')), findsNWidgets(2));
    expect(events.where((e) => e.$1 == 'portfolio_tab_changed'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Statistics without Predictions is the Investing section only',
      (tester) async {
    await _pump(tester,
        initialTab: 3,
        venues: const PortfolioVenues(trading: true, predictions: false));
    expect(_statisticsVenues(tester), [PortfolioPerformanceVenue.trading]);
    expect(find.byKey(const ValueKey('portfolio-statistics-predictions')),
        findsNothing);
    expect(find.byKey(const ValueKey('portfolio-statistics-earn')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Statistics ends with Earn while the backend allows it: the chart '
      'under its heading, mounted as it comes on screen', (tester) async {
    final api = RecordingRewardsApi(estimatedSatsToday: 1234);
    final events = _events();
    await _pump(tester, initialTab: 3, overrides: [
      usdEarnEnabledProvider.overrideWithValue(true),
      sparkIdentityPubkeyProvider.overrideWith((_) async => 'pub'),
      usdRewardsApiProvider.overrideWithValue(api),
    ]);
    // Bring the end of the list on screen whatever the figures take.
    await tester.drag(
        find.byType(PortfolioStatistics).first, const Offset(0, -800));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final earn = find.byKey(const ValueKey('portfolio-statistics-earn'));
    expect(earn, findsOneWidget);
    expect(find.byType(UsdEarnChart), findsOneWidget);
    expect(tester.getTopLeft(earn).dy,
        greaterThan(tester.getTopLeft(find.byType(PortfolioStatistics).last).dy));
    expect(api.calls, contains('summary'));
    expect(events.where((e) => e.$1 == 'usd_earn_opened'), hasLength(1));
    expect(events.where((e) => e.$1 == 'portfolio_tab_changed'), isEmpty);
    // Unmount with the chart's countdown stopped.
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the requested tab (a trade notification)',
      (tester) async {
    await _pump(tester, initialTab: 1);
    final context = tester.element(find.byType(PortfolioTabs));
    expect(DefaultTabController.of(context).index, 1);
    expect(find.text('Open orders'), findsNothing);
    expect(find.textContaining('No resting orders.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening reports portfolio_opened with its source, once',
      (tester) async {
    final events = _events();
    await _pump(tester, initialTab: 3);
    final opened = events.where((e) => e.$1 == 'portfolio_opened').toList();
    expect(opened, hasLength(1));
    expect(opened.single.$2, {'source': 'test', 'tab': 'statistics'});
  });

  for (final product in InvestmentsProduct.values) {
    testWidgets(
        'the ${product.name} dock switches the Investments Portfolio pill, '
        'pushing nothing', (tester) async {
      final events = _events();
      await _pump(tester,
          state: _withPosition,
          placing: [_placing],
          overrides: [
            activeShellTabProvider.overrideWith((_) => ActiveNavTab.usd),
          ],
          home: Scaffold(
              bottomNavigationBar: InvestmentActionBar(product: product)));
      expect(find.byType(OpenInvestmentsScreen), findsNothing);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(InvestmentActionBar)));
      expect(container.read(investmentsTabProvider), InvestmentsTab.investing);
      await tester.tap(find.text('Portfolio'));
      await tester.pumpAndSettle();
      expect(container.read(investmentsTabProvider), InvestmentsTab.portfolio);
      // The Portfolio lives on the Investments tab: no second copy.
      expect(find.byType(OpenInvestmentsScreen), findsNothing);
      expect(events.where((e) => e.$1 == 'portfolio_opened'), isEmpty);
      expect(find.text('Withdraw'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'embedded (the Investments Portfolio pill): the same tabs, lists and '
      'drill-down with no app bar and no back button', (tester) async {
    final events = _events();
    await _pump(tester,
        state: _withPosition,
        placing: [_placing],
        home: const Scaffold(
            body: OpenInvestmentsScreen(
                source: 'investments_tab', embedded: true)));
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(KuteBackButton), findsNothing);
    // No title of its own: the Investments pill names it.
    expect(find.text('Portfolio'), findsNothing);
    expect(find.byType(PortfolioTabs), findsOneWidget);
    expect(find.byType(InvestmentBalanceHeader), findsNothing);
    expect(find.text('Deposit'), findsNothing);
    expect(find.text('Withdraw'), findsNothing);
    expect(
        events.where((e) => e.$1 == 'portfolio_opened').single.$2,
        {'source': 'investments_tab', 'tab': 'open'});

    // Open: both venues, no Wallet section, no filter row.
    expect(find.byKey(const ValueKey('portfolio-filter-all')), findsNothing);
    expect(find.text('Wallet'), findsNothing);
    expect(find.byType(HlPortfolioPositionCard), findsOneWidget);
    expect(find.text('Will it rain tomorrow?'), findsOneWidget);

    // The same tabs and drill-down: Statistics with both sections, each
    // with its own Active | Historic pair.
    await _openTab(tester, 3);
    expect(_statisticsVenues(tester), [
      PortfolioPerformanceVenue.trading,
      PortfolioPerformanceVenue.predictions,
    ]);
    await tester.tap(find.byKey(const ValueKey('statistics-historic')).first);
    await tester.pumpAndSettle();
    expect(events.last.$1, 'portfolio_tab_changed');
    expect(events.last.$2, {'tab': 'statistics', 'subtab': 'historic'});
    expect(tester.takeException(), isNull);
  });
}
