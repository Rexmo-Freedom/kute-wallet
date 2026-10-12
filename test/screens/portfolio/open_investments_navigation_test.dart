// The one Portfolio screen (owner decision October 2026): the same screen
// from every door, both venues merged under All | Investing | Predictions
// pills, the spending account's bitcoin and dollars on top, no total
// header and no deposit or withdrawal buttons. Statistics (and Orders,
// Activity) switch venue with Investing | Predictions pills.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidAccountMarketProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/screens/portfolio/portfolio_wallet_rows.dart';
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/portfolio_tabs.dart';
import 'package:kute/screens/shared/trade_results_button.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/portfolio_overrides.dart';

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
    InvestmentsProduct? initialVenue,
    Widget? home,
    HyperliquidTradingState state = const HyperliquidTradingState(),
    List<PlacingBet> placing = const [],
    PortfolioVenues venues = kPortfolioBothVenues,
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
              OpenInvestmentsScreen(
                  source: 'test',
                  initialTab: initialTab,
                  initialVenue: initialVenue),
        ),
      )));
  await tester.pumpAndSettle();
}

/// A card's big figure ([PortfolioCardValue] rolls its digits, so the
/// text is not one Text widget).
Finder _figure(String text) =>
    find.byWidgetPredicate((w) => w is RollingFigure && w.text == text);

bool _selected(WidgetTester tester, String key) =>
    tester.widget<KutePill>(find.byKey(ValueKey(key))).selected;

List<(String, Map<String, Object>?)> _events() {
  final events = <(String, Map<String, Object>?)>[];
  TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  addTearDown(() => TrackingService.debugTrackObserver = null);
  return events;
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
      'opens on All: the Wallet rows and one empty line when nothing is open',
      (tester) async {
    await _pump(tester);
    expect(_selected(tester, 'portfolio-filter-all'), isTrue);
    expect(_selected(tester, 'portfolio-filter-trading'), isFalse);
    expect(_selected(tester, 'portfolio-filter-predictions'), isFalse);
    expect(find.text('Wallet'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('portfolio-wallet-bitcoin')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('portfolio-wallet-dollars')), findsOneWidget);
    // 250,000 sats at $100,000 a bitcoin.
    expect(find.text('250,000 sats'), findsOneWidget);
    expect(_figure(r'$250.00'), findsOneWidget);
    expect(find.text('Dollars'), findsOneWidget);
    expect(_figure(r'$42.50'), findsOneWidget);
    // One combined line, no per-venue empty states, no venue sections.
    expect(find.text('No positions yet'), findsOneWidget);
    expect(find.text('No open investments'), findsNothing);
    expect(find.text('No open predictions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden balances mask both Wallet rows', (tester) async {
    await _pump(tester, balancePrivacy: 1);
    expect(find.text('250,000 sats'), findsNothing);
    expect(_figure(r'$250.00'), findsNothing);
    expect(_figure(r'$42.50'), findsNothing);
    // The bitcoin caption and both figures (the dollars carry no caption
    // in a dollar currency).
    expect(find.text(kPortfolioHiddenAmount), findsOneWidget);
    expect(_figure(kPortfolioHiddenAmount), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'All lists both venues under their plain names, with no total; the '
      'pills filter to one venue', (tester) async {
    await _pump(tester, state: _withPosition, placing: [_placing]);
    expect(find.text('Investing'), findsNWidgets(2)); // pill + section
    expect(find.text('Predictions'), findsNWidgets(2));
    expect(find.byType(HlPortfolioPositionCard), findsOneWidget);
    expect(find.text('Will it rain tomorrow?'), findsOneWidget);
    expect(find.text('No positions yet'), findsNothing);
    expect(find.textContaining('total'), findsNothing);

    final events = _events();
    await tester.tap(find.byKey(const ValueKey('portfolio-filter-trading')));
    await tester.pumpAndSettle();
    expect(find.byType(HlPortfolioPositionCard), findsOneWidget);
    expect(find.text('Will it rain tomorrow?'), findsNothing);
    expect(find.text('Wallet'), findsNothing);
    expect(events.last.$1, 'portfolio_tab_changed');
    expect(events.last.$2, {'tab': 'open', 'filter': 'trading'});

    await tester
        .tap(find.byKey(const ValueKey('portfolio-filter-predictions')));
    await tester.pumpAndSettle();
    expect(find.byType(HlPortfolioPositionCard), findsNothing);
    expect(find.text('Will it rain tomorrow?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a filtered venue with nothing open keeps its own empty state',
      (tester) async {
    await _pump(tester, state: _withPosition);
    // Nothing in Predictions: no section under All.
    expect(find.text('Predictions'), findsOneWidget); // the pill only
    await tester
        .tap(find.byKey(const ValueKey('portfolio-filter-predictions')));
    await tester.pumpAndSettle();
    expect(find.text('No open predictions'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('portfolio-filter-trading')));
    await tester.pumpAndSettle();
    expect(find.text('No open investments'), findsNothing);
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

  testWidgets(
      'a venue gated off loses its pill and its section; no Dollars row '
      'without a dollar account', (tester) async {
    await _pump(tester,
        state: _withPosition,
        placing: [_placing],
        venues: const PortfolioVenues(
            trading: false, predictions: true, dollars: false));
    expect(
        find.byKey(const ValueKey('portfolio-filter-trading')), findsNothing);
    expect(find.byKey(const ValueKey('portfolio-filter-predictions')),
        findsOneWidget);
    expect(find.text('Investing'), findsNothing);
    expect(find.byType(HlPortfolioPositionCard), findsNothing);
    expect(find.text('Will it rain tomorrow?'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('portfolio-wallet-bitcoin')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('portfolio-wallet-dollars')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no venue at all: the Wallet rows alone, no pills',
      (tester) async {
    await _pump(tester,
        venues: const PortfolioVenues(
            trading: false, predictions: false, dollars: false));
    expect(find.byKey(const ValueKey('portfolio-filter-all')), findsNothing);
    expect(
        find.byKey(const ValueKey('portfolio-wallet-bitcoin')), findsOneWidget);
    expect(find.text('No positions yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Statistics opens on Predictions and switches venue with the pills',
      (tester) async {
    await _pump(tester, initialTab: 3);
    PortfolioStatistics stats() =>
        tester.widget<PortfolioStatistics>(find.byType(PortfolioStatistics));
    expect(stats().venue, PortfolioPerformanceVenue.predictions);
    expect(_selected(tester, 'portfolio-statistics-predictions'), isTrue);

    final events = _events();
    await tester
        .tap(find.byKey(const ValueKey('portfolio-statistics-trading')));
    await tester.pumpAndSettle();
    expect(stats().venue, PortfolioPerformanceVenue.trading);
    expect(events.firstWhere((e) => e.$1 == 'portfolio_tab_changed').$2,
        {'tab': 'statistics', 'venue': 'trading'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('Statistics without Predictions is Investing, with no switch',
      (tester) async {
    await _pump(tester,
        initialTab: 3,
        venues: const PortfolioVenues(
            trading: true, predictions: false, dollars: true));
    expect(
        tester
            .widget<PortfolioStatistics>(find.byType(PortfolioStatistics))
            .venue,
        PortfolioPerformanceVenue.trading);
    expect(find.byKey(const ValueKey('portfolio-statistics-trading')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the requested tab and venue (a trade notification)',
      (tester) async {
    await _pump(tester,
        initialTab: 1, initialVenue: InvestmentsProduct.trading);
    final context = tester.element(find.byType(PortfolioTabs));
    expect(DefaultTabController.of(context).index, 1);
    expect(_selected(tester, 'portfolio-orders-trading'), isTrue);
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
    testWidgets('the ${product.name} dock opens the same Portfolio, on All',
        (tester) async {
      final events = _events();
      await _pump(tester,
          state: _withPosition,
          placing: [_placing],
          home: Scaffold(
              bottomNavigationBar: InvestmentActionBar(product: product)));
      expect(find.byType(OpenInvestmentsScreen), findsNothing);
      await tester.tap(find.text('Portfolio'));
      await tester.pumpAndSettle();
      final screen = tester
          .widget<OpenInvestmentsScreen>(find.byType(OpenInvestmentsScreen));
      expect(screen.initialTab, 0);
      expect(screen.initialVenue, isNull);
      expect(
          screen.source,
          product == InvestmentsProduct.trading
              ? 'dock_investing'
              : 'dock_predictions');
      expect(_selected(tester, 'portfolio-filter-all'), isTrue);
      // Both venues and the wallet, whichever dock opened it.
      expect(find.byType(HlPortfolioPositionCard), findsOneWidget);
      expect(find.text('Will it rain tomorrow?'), findsOneWidget);
      expect(find.byKey(const ValueKey('portfolio-wallet-bitcoin')),
          findsOneWidget);
      expect(find.text('Deposit'), findsNothing);
      expect(
          events.where((e) => e.$1 == 'portfolio_opened').single.$2?['source'],
          screen.source);
      expect(tester.takeException(), isNull);
    });
  }
}
