import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidAccountMarketProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart';
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/investment_balances_provider.dart';
import 'package:kute/providers/pending_pool_deposits_provider.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/shared/portfolio_tabs.dart';
import 'package:kute/screens/shared/trade_results_button.dart';
import 'package:kute/theme/app_theme.dart';

class _Trading extends HyperliquidTradingNotifier {
  _Trading([this.initial = const HyperliquidTradingState()]);
  final HyperliquidTradingState initial;

  @override
  Future<HyperliquidTradingState> build() async => initial;
}

Future<void> _pump(WidgetTester tester,
    {int initialTab = 0,
    Widget? home,
    HyperliquidTradingState state = const HyperliquidTradingState()}) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        hyperliquidTradingProvider.overrideWith(() => _Trading(state)),
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
            reviewDone: true))),
        investmentBalancesProvider(InvestmentsProduct.trading).overrideWith(
            (_) => const InvestmentBalances(
                available: 150, portfolio: 0, total: 150)),
        pendingTradingDepositUsdProvider.overrideWith((_) => 0),
        pendingTradingWithdrawalUsdProvider.overrideWith((_) => 0),
        hyperliquidUserFillsProvider.overrideWith((_) async => []),
        tradeNotificationsProvider.overrideWith((_) => Stream.value([])),
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
                  product: InvestmentsProduct.trading, initialTab: initialTab),
        ),
      )));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets('empty portfolio only offers position management views',
      (tester) async {
    await _pump(tester);
    expect(find.text('Portfolio'), findsOneWidget);
    expect(find.text('No open investments'), findsOneWidget);
    expect(find.text('Build portfolio'), findsNothing);
    // Earn belongs to the dollar balance now; Investing does not offer it.
    expect(find.text('Earn'), findsNothing);
    // The header leads with the Investing total and splits it underneath.
    expect(find.text('Investing total'), findsOneWidget);
    expect(find.textContaining('Available'), findsOneWidget);
    // Four pills side-scroll at natural width; Statistics may sit past the
    // right edge of a narrow phone.
    expect(find.text('Statistics', skipOffstage: false), findsOneWidget);
    expect(
        tester
            .widget<InvestmentBalanceHeader>(
                find.byType(InvestmentBalanceHeader))
            .showDepositButton,
        isFalse);
    expect(find.byType(TradeResultsButton), findsNothing);
    expect(find.text('Browse markets'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    // The dock carries Deposit and Withdraw, and its square chip searches
    // this venue instead of adding (Ask Sal lives in the search sheet).
    expect(find.text('Deposit'), findsOneWidget);
    expect(find.text('Withdraw'), findsOneWidget);
    expect(find.text('Ask Sal anything'), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('the Open tab is the plain position list: no category donut',
      (tester) async {
    await _pump(tester,
        state: const HyperliquidTradingState(
          isInitialized: true,
          positions: [
            HlPerpPosition(
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
                maxLeverage: 40),
          ],
        ));
    expect(find.byType(HlPortfolioPositionCard), findsOneWidget);
    // The donut lives at the bottom of Statistics only.
    expect(find.byType(KuteDonutChart), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('the venue dock\'s Portfolio opens the portfolio screen',
      (tester) async {
    await _pump(tester,
        home: const Scaffold(
            bottomNavigationBar:
                InvestmentActionBar(product: InvestmentsProduct.trading)));
    expect(find.byType(OpenInvestmentsScreen), findsNothing);
    await tester.tap(find.text('Portfolio'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenInvestmentsScreen), findsOneWidget);
    // On the portfolio screen the dock is Deposit and Withdraw again.
    expect(find.text('Deposit'), findsOneWidget);
    expect(find.text('Withdraw'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('portfolio shortcut opens requested Orders tab', (tester) async {
    await _pump(tester, initialTab: 1);
    final context = tester.element(find.byType(PortfolioTabs));
    expect(DefaultTabController.of(context).index, 1);
    // The Orders pill is the tab's title; the embedded list adds no second
    // "Open orders" heading.
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Open orders'), findsNothing);
    expect(find.textContaining('No resting orders.'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('History'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'the dock floats over the list as on Home: the list runs under the '
      'frost band and only its last row stops clear of the dock',
      (tester) async {
    await _pump(tester,
        state: const HyperliquidTradingState(
          isInitialized: true,
          positions: [
            HlPerpPosition(
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
                maxLeverage: 40),
          ],
        ));
    // Home's mount: the dock is KuteDockHost's.
    final dock = find.byType(InvestmentActionBar);
    expect(
        find.descendant(of: find.byType(KuteDockHost), matching: dock),
        findsOneWidget);
    final dockTop = tester.getTopLeft(dock).dy;
    final screenBottom = tester.view.physicalSize.height;
    // The list reaches the bottom of the screen, under the dock...
    final list = find
        .ancestor(
            of: find.byType(HlPortfolioPositionCard),
            matching: find.byType(ListView))
        .first;
    expect(tester.getBottomLeft(list).dy, screenBottom);
    expect(tester.getBottomLeft(list).dy, greaterThan(dockTop));
    // ...and its own bottom room clears the dock and the frost band.
    final padding =
        tester.widget<ListView>(list).padding!.resolve(TextDirection.ltr);
    expect(padding.bottom, greaterThan(screenBottom - dockTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty tab centres its line above the dock, not behind it',
      (tester) async {
    await _pump(tester);
    final dockTop = tester.getTopLeft(find.byType(InvestmentActionBar)).dy;
    expect(tester.getBottomLeft(find.text('No open investments')).dy,
        lessThan(dockTop));
    expect(tester.takeException(), isNull);
  });
}
