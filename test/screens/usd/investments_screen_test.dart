// The Investments tab (one balance): the spending account's top strip is
// Bitcoin | Investments, and Investments carries Investing · Predictions
// · Portfolio as pills over the embedded screens (each pill wearing a
// glyph of the one icon family, a step bigger than the Home strip), the
// one-balance hero above them (no title; the balance opens nothing, nor
// does the compact bar's total, and no "Invested" under it: Balances
// carries it; the Portfolio is the third pill, with Balances (the
// positions under their venue), P&L charts and Activity under it), and the
// Receive / Send / search dock with the search scoped to the pill. Receive (the dock's, no door under the
// hero any more) opens the Dollars receive screen on its coin step, whose
// "From your Bitcoin" row opens the Investments deposit sheet. No
// venue Deposit or Withdraw exists anywhere inside it.
// The whole page scrolls as one on every pill, and the chrome collapses:
// the hero leaves, the pills condense into the compact pinned bar with a
// small copy of the total and a chevron that brings everything back, as
// does scrolling to the very top.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/active_shell_tab_provider.dart';
import 'package:kute/models/hyperliquid_market.dart'
    show HlOpenOrder, HlPerpPosition;
import 'package:kute/models/polymarket_model.dart' show Activity;
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_order_metadata_provider.dart';
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:kute/providers/refresh_everything_provider.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/home/shell_wallet_screen.dart'
    show kShellTopBarSpacing;
import 'package:kute/screens/hyperliquid/components/open_orders_sheet.dart'
    show HlOrderRow;
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/polymarket/components/open_orders_sheet.dart'
    show PolyOrderRow;
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart'
    show KutePill, KutePillSize, KutePillTabs;
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

import '../../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import 'investments_harness.dart';

Finder _pill(String label) => investmentsPill(label);

/// The Portfolio's section pills (not Balances' Move money pill).
final _sectionPills = find.byWidgetPredicate((w) =>
    w is KutePill &&
    w.key is ValueKey<String> &&
    (w.key! as ValueKey<String>).value.startsWith('portfolio-section-pill-'));

/// A Portfolio section pill, by its analytics key.
Finder _section(String key) =>
    find.byKey(ValueKey('portfolio-section-pill-$key'));

/// One prediction placed, a minute apart by [id]'s order.
PolymarketTransaction _bet(String id) {
  final at = DateTime.utc(2026, 10, 5, 12)
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

/// A resting Investing order.
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

/// A resting Predictions limit order.
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

/// One order resting at each venue.
List<Override> _restingOrders() => [
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
          const HyperliquidTradingState(
              isInitialized: true, openOrders: [_hlOrder]))),
      polymarketOpenOrdersProvider
          .overrideWith((_) => Stream.value(const [_pmOrder])),
      polymarketOrderMetadataProvider.overrideWith((_) async => const {}),
    ];

/// An Investing position held.
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

AppLocalizations _l10n(WidgetTester tester) =>
    tester.element(find.byType(InvestmentsBody)).l10n;

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(InvestmentsBody)));

Future<void> _pumpFrames(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The small copy of the total the compact bar carries.
final _compactTotal = find.byKey(const ValueKey('investments-compact-total'));

/// The compact bar's chevron.
final _chevron = find.byKey(const ValueKey('investments-expand'));

/// The pill strip on screen: the large one in the expanded header, the
/// compact one in the collapsed bar (the other is offstage).
KutePillTabs _strip(WidgetTester tester) =>
    tester.widget<KutePillTabs>(find.byType(KutePillTabs).first);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'three pills in order, Investing · Predictions · Portfolio, each '
      'wearing its glyph of the one icon family, a step bigger, over the '
      'embedded browsers', (tester) async {
    await pumpInvestments(tester, earn: kEarnOn);
    final l10n = _l10n(tester);
    final strip = _strip(tester);
    expect(strip.items.map((i) => i.label),
        [l10n.trading, l10n.predictions, l10n.walletPortfolioAction]);
    expect(strip.items.map((i) => i.label),
        ['Investing', 'Predictions', 'Portfolio']);
    // The third pill reads Portfolio now, never Positions.
    expect(_pill(l10n.ledgerPositionsTitle), findsNothing);
    // The rising trend and the ring the top tabs used, the pie the
    // Portfolio wears; no venue logos.
    expect(strip.items.map((i) => i.icon), [
      Icons.trending_up_rounded,
      Icons.donut_large_rounded,
      Icons.pie_chart_rounded,
    ]);
    expect(strip.items.map((i) => i.leading), everyElement(isNull));
    expect(strip.size, KutePillSize.large);
    for (final label in strip.items.map((i) => i.label)) {
      expect(_pill(label), findsOneWidget, reason: label);
    }
    // The compact bar is not on screen at the top of the page.
    expect(_compactTotal, findsNothing);
    expect(_chevron, findsNothing);
    expect(tester.widget<KutePill>(_pill(l10n.trading)).selected, isTrue);
    expect(_container(tester).read(investmentsTabProvider),
        InvestmentsTab.investing);
    // Earn is no pill here (nor anywhere), whatever the capability says.
    expect(_pill('Earn'), findsNothing);
    expect(find.text('Earn', skipOffstage: false), findsNothing);

    // Both venue browsers are mounted from the start, embedded; the
    // Portfolio waits for its pill.
    expect(
        tester
            .widget<HyperliquidScreen>(find.byType(HyperliquidScreen))
            .embedded,
        isTrue);
    expect(
        tester
            .widget<PolymarketScreen>(
                find.byType(PolymarketScreen, skipOffstage: false))
            .embedded,
        isTrue);
    expect(
        find.byType(OpenInvestmentsScreen, skipOffstage: false), findsNothing);
    expect(
        find.byType(InvestmentsPortfolio, skipOffstage: false), findsNothing);

    // The one-balance hero, once, above the pills: no title, the total
    // with no arrow after it (it opens nothing), and nothing under it at
    // rest: Invested is Balances' row, never shown twice.
    final header =
        tester.widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader));
    expect(header.totalLabel, isNull);
    expect(find.text(l10n.investmentsTotal), findsNothing);
    expect(header.amountText, r'$25.00');
    expect(header.availableText, isNull);
    expect(find.text('${l10n.available} '), findsNothing);
    expect(header.investedText, isNull);
    expect(find.text('${l10n.betInvested} '), findsNothing);
    expect(find.text(l10n.betInvested), findsNothing);
    expect(find.byKey(const ValueKey('investments-balance-chevron')),
        findsNothing);
    expect(find.byKey(const ValueKey('investments-balance')), findsNothing);
    expect(find.byType(InvestmentBalanceHeader), findsOneWidget);
    expect(tester.getTopLeft(find.byType(PoolBalanceHeader)).dy,
        lessThan(tester.getTopLeft(find.byType(KutePillTabs).first).dy));
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'no venue Deposit or Withdraw anywhere and no door under the hero; '
      'the way in is the dock\'s Deposit, which opens the Dollars receive '
      'screen', (tester) async {
    final events = recordEvents();
    var receiveOpened = 0;
    UsdAccountActionBar.debugReceiveOpener = (_) => receiveOpened++;
    addTearDown(() => UsdAccountActionBar.debugReceiveOpener = null);
    await pumpInvestments(tester, earn: kEarnOn);
    final l10n = _l10n(tester);
    expect(find.byType(VenueDepositButton, skipOffstage: false), findsNothing);
    expect(find.byType(InvestmentActionBar, skipOffstage: false), findsNothing);
    // The dock's own Withdraw is the only one on the page.
    expect(find.text(l10n.withdraw, skipOffstage: false), findsOneWidget);
    expect(find.textContaining('Investing deposit', skipOffstage: false),
        findsNothing);
    expect(find.textContaining('Predictions deposit', skipOffstage: false),
        findsNothing);
    // The full-width door is gone: no button in the header, and the
    // door's label is nowhere on the page.
    expect(find.byType(AppButton, skipOffstage: false), findsNothing);
    expect(find.text(l10n.dollarDeposit, skipOffstage: false), findsNothing);
    // The pills sit right under the hero.
    expect(tester.getTopLeft(find.byType(KutePillTabs).first).dy,
        lessThan(tester.getBottomLeft(find.byType(PoolBalanceHeader)).dy + 40));

    // The dock: Deposit and Withdraw (Investments never says Receive or
    // Send), the Bitcoin dock's arrows and action keys, and the search
    // square.
    final bar =
        tester.widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
    expect(bar.actions.map((a) => a.label), [l10n.deposit, l10n.withdraw]);
    expect(bar.actions.map((a) => a.trackingId), ['receive', 'send']);
    expect(bar.actions.map((a) => a.icon),
        [Icons.south_west_rounded, Icons.north_east_rounded]);
    expect(bar.onSearch, isNotNull);
    expect(bar.source, 'usd');
    expect(find.text(l10n.deposit), findsOneWidget);
    expect(find.text(l10n.receive, skipOffstage: false), findsNothing);
    expect(find.text(l10n.send, skipOffstage: false), findsNothing);

    // Deposit opens the Dollars receive screen, with the Bitcoin dock's
    // quick-action key under this surface and the dock as the receive
    // flow's entry source.
    await tester.tap(find.text(l10n.deposit));
    await tester.pump();
    expect(receiveOpened, 1);
    expect(events.where((e) => e.$1 == 'quick_action_tapped').single.$2,
        {'action': 'receive', 'source': 'usd'});
    expect(TrackingService.takeEntrySource('usd_receive'), 'usd_dock');
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  test('the collapsed bar\'s pills are a notch up, still under the page\'s',
      () {
    const compact = KutePillSize.compact;
    expect(compact.font, 12);
    expect(compact.icon, 14);
    expect(compact.height, 32);
    expect(compact.height, lessThan(KutePillSize.large.height));
    expect(compact.font, lessThan(KutePillSize.large.font));
    // The bar grew with them, so nothing under it overlaps.
    expect(kInvestmentsCompactBarHeight, 6 + 20 + 6 + compact.height + 8);
  });

  test('the search square follows the pill', () {
    expect(UsdAccountActionBar.searchTarget(InvestmentsTab.investing),
        (category: SearchCategory.perpetuals, source: 'trading'));
    expect(UsdAccountActionBar.searchTarget(InvestmentsTab.predictions),
        (category: SearchCategory.predictions, source: 'predictions'));
    // Portfolio searches this account's activity.
    expect(UsdAccountActionBar.searchTarget(InvestmentsTab.positions),
        (category: null, source: 'usd'));
  });

  testWidgets(
      'a pill tap reports analytics_tab_selected and the venue open event, '
      'and Portfolio mounts on Balances', (tester) async {
    final events = recordEvents();
    await pumpInvestments(tester, earn: kEarnOn);
    final l10n = _l10n(tester);

    await tapPill(tester, l10n.predictions);
    expect(_container(tester).read(investmentsTabProvider),
        InvestmentsTab.predictions);
    expect(tester.widget<KutePill>(_pill(l10n.predictions)).selected, isTrue);
    expect(find.byType(PolymarketScreen), findsOneWidget);
    expect(events.where((e) => e.$1 == 'analytics_tab_selected').last.$2, {
      'tab': 'predictions',
      'from_tab': 'investing',
      'surface': 'investments'
    });
    expect(events.any((e) => e.$1 == 'polymarket_tab_opened'), isTrue);
    expect(events.any((e) => e.$1 == 'hyperliquid_tab_opened'), isFalse);

    // Re-tapping the pill on screen is not a new view.
    final before = events.length;
    await tapPill(tester, l10n.predictions);
    expect(events.length, before);

    await tapPill(tester, l10n.walletPortfolioAction);
    expect(find.byType(InvestmentsPortfolio), findsOneWidget);
    expect(_container(tester).read(portfolioSectionProvider),
        PortfolioSection.balances);
    expect(tester.widget<KutePill>(_section('balances')).selected, isTrue);
    expect(_section('positions'), findsNothing);
    // Balances: Buying power, the ring and Move money.
    expect(find.byKey(const ValueKey('portfolio-balance-overview')),
        findsOneWidget);
    // The Portfolio is a page under the pills, not the Portfolio screen:
    // no app bar, no back button.
    expect(find.byType(OpenInvestmentsScreen), findsNothing);
    expect(find.byType(KuteBackButton), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(events.where((e) => e.$1 == 'portfolio_opened'), isEmpty);
    // Still `positions` for the dashboards, with the section it opens on
    // (`balances`, where `positions` used to be).
    expect(events.where((e) => e.$1 == 'analytics_tab_selected').last.$2, {
      'tab': 'positions',
      'from_tab': 'predictions',
      'surface': 'investments',
      'sub': 'balances'
    });

    await tapPill(tester, l10n.trading);
    expect(events.any((e) => e.$1 == 'hyperliquid_tab_opened'), isTrue);
    expect(find.byType(HyperliquidScreen), findsOneWidget);
    // The Portfolio keeps its state behind the stack: one mount.
    expect(
        find.byType(InvestmentsPortfolio, skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('a link picks the pill, on mount and on a later link',
      (tester) async {
    final linked = ValueNotifier<InvestmentsTab?>(InvestmentsTab.predictions);
    addTearDown(linked.dispose);
    await pumpInvestments(tester,
        child: ValueListenableBuilder<InvestmentsTab?>(
            valueListenable: linked,
            builder: (_, tab, __) => UsdAccountScreen(initialTab: tab)));
    final l10n = _l10n(tester);
    expect(_container(tester).read(investmentsTabProvider),
        InvestmentsTab.predictions);
    expect(tester.widget<KutePill>(_pill(l10n.predictions)).selected, isTrue);

    // The page is updated in place on the next link (same route key).
    linked.value = InvestmentsTab.investing;
    await _pumpFrames(tester, 3);
    expect(_container(tester).read(investmentsTabProvider),
        InvestmentsTab.investing);
    expect(tester.widget<KutePill>(_pill(l10n.trading)).selected, isTrue);

    // No tab in the link: the pill stays where it was.
    linked.value = null;
    await _pumpFrames(tester, 3);
    expect(_container(tester).read(investmentsTabProvider),
        InvestmentsTab.investing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  test('the pill keys are the link and analytics vocabulary', () {
    expect(InvestmentsTab.values.map((t) => t.key),
        ['investing', 'predictions', 'positions']);
    for (final tab in InvestmentsTab.values) {
      expect(InvestmentsTab.fromKey(tab.key), tab);
      expect(investmentsTabLocation(tab), '/usd?tab=${tab.key}');
    }
    expect(PortfolioSection.forLink('investing'), isNull);
    expect(PortfolioSection.forLink('predictions'), isNull);
    expect(InvestmentsTab.fromKey(null), isNull);
    expect(PortfolioSection.forLink(null), isNull);
    expect(InvestmentsTab.fromKey('deposit'), isNull);
    // The old Earn pill's link lands on the first pill, never a blank.
    expect(InvestmentsTab.fromKey('earn'), isNull);
    // The Portfolio's sections, analytics and links alike.
    // No Positions section any more: Balances first.
    expect(PortfolioSection.values.map((s) => s.key),
        ['balances', 'charts', 'activity']);
    // The old Positions links (the section, the old Portfolio pill and its
    // Open tab) land on Balances, where the positions are; the old Orders
    // and Statistics tabs open P&L charts, where the orders are; Activity
    // opens Activity.
    for (final key in ['positions', 'portfolio', 'open']) {
      expect(InvestmentsTab.fromKey(key), InvestmentsTab.positions,
          reason: key);
      expect(PortfolioSection.forLink(key), PortfolioSection.balances,
          reason: key);
    }
    for (final key in ['orders', 'statistics', 'charts']) {
      expect(InvestmentsTab.fromKey(key), InvestmentsTab.positions,
          reason: key);
      expect(PortfolioSection.forLink(key), PortfolioSection.charts,
          reason: key);
    }
    expect(InvestmentsTab.fromKey('activity'), InvestmentsTab.positions);
    expect(PortfolioSection.forLink('activity'), PortfolioSection.activity);
    expect(InvestmentsTab.fromKey('balances'), InvestmentsTab.positions);
    expect(PortfolioSection.forLink('balances'), PortfolioSection.balances);
  });

  testWidgets(
      'a link to the old Activity tab opens the Portfolio pill on Activity, '
      'not the Portfolio screen; a later Positions link lands on Balances',
      (tester) async {
    final events = recordEvents();
    final linked = ValueNotifier<String?>('activity');
    addTearDown(linked.dispose);
    await pumpInvestments(tester,
        child: ValueListenableBuilder<String?>(
            valueListenable: linked,
            builder: (_, key, __) => UsdAccountScreen(
                initialTab: InvestmentsTab.fromKey(key),
                initialSection: PortfolioSection.forLink(key))));
    await _pumpFrames(tester, 6);
    final container = _container(tester);
    expect(container.read(investmentsTabProvider), InvestmentsTab.positions);
    expect(container.read(portfolioSectionProvider), PortfolioSection.activity);
    expect(tester.widget<KutePill>(_section('activity')).selected, isTrue);
    expect(find.byType(OpenInvestmentsScreen), findsNothing);
    expect(events.where((e) => e.$1 == 'portfolio_opened'), isEmpty);

    linked.value = 'positions';
    await _pumpFrames(tester, 6);
    expect(container.read(investmentsTabProvider), InvestmentsTab.positions);
    expect(container.read(portfolioSectionProvider), PortfolioSection.balances);
    expect(tester.widget<KutePill>(_section('balances')).selected, isTrue);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'the Portfolio\'s sections: Balances with Move money, P&L charts, '
      'Activity with the merged list; each switch is reported, and the '
      'section is kept for the session', (tester) async {
    final events = recordEvents();
    await pumpInvestments(tester,
        history: Transaction(
          bitcoinTransactions: const [],
          sparkTransactions: const [],
          sparkUnclaimedDeposits: const [],
          usdbTokenTransactions: const [],
          swapOrderTransactions: const [],
          polymarketTransactions: [_bet('bet0'), _bet('bet1')],
        ));
    final l10n = _l10n(tester);
    await tapPill(tester, l10n.walletPortfolioAction);

    // Three small pills, in order, Balances first and picked, then P&L
    // charts and Activity; no Positions pill.
    final pills = find.descendant(
        of: find.byType(InvestmentsPortfolio), matching: _sectionPills);
    expect(tester.widgetList<KutePill>(pills).map((p) => p.label), [
      l10n.portfolioSectionBalances,
      l10n.portfolioSectionPnlCharts,
      l10n.activity,
    ]);
    expect(tester.widgetList<KutePill>(pills).map((p) => p.label),
        ['Balances', 'P&L charts', 'Activity']);
    expect(find.text(l10n.ledgerPositionsTitle), findsNothing);
    expect(tester.widget<KutePill>(_section('balances')).selected, isTrue);
    expect(find.byKey(const ValueKey('statistics-overview')), findsNothing);
    // Balances: the bare ring, Buying power and its amount, and Move money
    // as a quiet link (no pill, no button, no Add money), which can be
    // tapped; no tagline, no Total investments.
    expect(find.byKey(const ValueKey('portfolio-balance-breakdown')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('portfolio-balance-ring')), findsOneWidget);
    final move = find.byKey(const ValueKey('portfolio-move-money'));
    expect(move.hitTestable(), findsOneWidget);
    expect(find.text(l10n.moveTransfer), findsOneWidget);
    expect(find.byType(AppButton), findsNothing);
    expect(find.text('Total investments'), findsNothing);
    expect(find.text('Ready for any trade or prediction'), findsNothing);
    expect(find.text(l10n.betInvested), findsNothing);

    // P&L charts: the chart, pair and figures; neither Balances nor the
    // activity.
    await tapAndPump(tester, _section('charts'));
    expect(events.where((e) => e.$1 == 'analytics_tab_selected').last.$2, {
      'tab': 'positions',
      'from_tab': 'positions',
      'surface': 'investments',
      'sub': 'charts',
      'from_sub': 'balances'
    });
    expect(find.byKey(const ValueKey('statistics-overview')), findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-balance-breakdown')),
        findsNothing);
    expect(find.byKey(const ValueKey('portfolio-move-money')), findsNothing);
    expect(find.byKey(const ValueKey('portfolio-activity-list')), findsNothing);

    // Activity: the merged list, all of it, with no "See all".
    await tapAndPump(tester, _section('activity'));
    expect(events.where((e) => e.$1 == 'analytics_tab_selected').last.$2, {
      'tab': 'positions',
      'from_tab': 'positions',
      'surface': 'investments',
      'sub': 'activity',
      'from_sub': 'charts'
    });
    expect(
        find.byKey(const ValueKey('portfolio-activity-list')), findsOneWidget);
    expect(find.text('Prediction · Yes'), findsNWidgets(2));
    expect(
        find.byKey(const ValueKey('portfolio-activity-see-all')), findsNothing);
    expect(find.byKey(const ValueKey('portfolio-balance-breakdown')),
        findsNothing);
    expect(find.byKey(const ValueKey('statistics-overview')), findsNothing);

    // Re-tapping the section on screen is not a new view.
    final before = events.length;
    await tapAndPump(tester, _section('activity'));
    expect(events.length, before);

    // Away and back: the Portfolio comes back on the section it was left
    // on, and says so.
    await tapPill(tester, l10n.trading);
    await tapPill(tester, l10n.walletPortfolioAction);
    expect(tester.widget<KutePill>(_section('activity')).selected, isTrue);
    expect(
        find.byKey(const ValueKey('portfolio-activity-list')), findsOneWidget);
    expect(events.where((e) => e.$1 == 'analytics_tab_selected').last.$2, {
      'tab': 'positions',
      'from_tab': 'investing',
      'surface': 'investments',
      'sub': 'activity'
    });
    expect(find.byType(OpenInvestmentsScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'View positions (openInvestmentsPositions) lands on Balances, where '
      'the positions are, whatever section was left open', (tester) async {
    // Investments is the tab on screen: no navigation, only the state.
    await pumpInvestments(tester, overrides: [
      activeShellTabProvider.overrideWith((_) => ActiveNavTab.usd),
    ]);
    final l10n = _l10n(tester);
    await tapPill(tester, l10n.walletPortfolioAction);
    await tapAndPump(tester, _section('activity'));
    await tapPill(tester, l10n.trading);
    openInvestmentsPositions(tester.element(find.byType(InvestmentsBody)));
    await _pumpFrames(tester, 4);
    final container = _container(tester);
    expect(container.read(investmentsTabProvider), InvestmentsTab.positions);
    expect(container.read(portfolioSectionProvider), PortfolioSection.balances);
    expect(tester.widget<KutePill>(_section('balances')).selected, isTrue);
    expect(find.byKey(const ValueKey('portfolio-balance-overview')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('statistics-overview')), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'Balances lists what is held under its venue, the Positions list\'s '
      'rows, under Invested', (tester) async {
    await pumpInvestments(tester, overrides: [
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
          const HyperliquidTradingState(
              isInitialized: true, positions: [_btcPosition]))),
    ]);
    final l10n = _l10n(tester);
    await tapPill(tester, l10n.walletPortfolioAction);
    expect(tester.widget<KutePill>(_section('balances')).selected, isTrue);
    expect(
        find.byKey(const ValueKey('portfolio-balances-list')), findsOneWidget);
    expect(
        find.descendant(
            of: find
                .byKey(const ValueKey('portfolio-balance-investing-positions')),
            matching: find.byType(HlPositionRow)),
        findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-positions-heading')),
        findsNothing);
    expect(
        find.descendant(
            of: find.byType(InvestmentsPortfolio),
            matching: find.text(l10n.ledgerPositionsTitle)),
        findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'P&L charts lists the resting orders at both venues under the chart, '
      'with the count and Cancel all; Balances does not; the switch is '
      'reported with sub: charts', (tester) async {
    final events = recordEvents();
    await pumpInvestments(tester, overrides: _restingOrders());
    final l10n = _l10n(tester);
    await tapPill(tester, l10n.walletPortfolioAction);

    // Balances: no orders.
    expect(
        find.byKey(const ValueKey('portfolio-orders-heading'),
            skipOffstage: false),
        findsNothing);
    expect(find.byType(HlOrderRow, skipOffstage: false), findsNothing);
    expect(find.byType(PolyOrderRow, skipOffstage: false), findsNothing);

    await tapAndPump(tester, _section('charts'));
    expect(_container(tester).read(portfolioSectionProvider),
        PortfolioSection.charts);
    expect(tester.widget<KutePill>(_section('charts')).selected, isTrue);
    expect(events.where((e) => e.$1 == 'analytics_tab_selected').last.$2, {
      'tab': 'positions',
      'from_tab': 'positions',
      'surface': 'investments',
      'sub': 'charts',
      'from_sub': 'balances'
    });
    expect(find.byKey(const ValueKey('statistics-overview')), findsOneWidget);
    // The orders block keeps its own heading, count and Cancel all.
    expect(
        find.byKey(const ValueKey('portfolio-orders-heading'),
            skipOffstage: false),
        findsOneWidget);
    expect(find.byType(HlOrderRow, skipOffstage: false), findsOneWidget);
    expect(find.byType(PolyOrderRow, skipOffstage: false), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('portfolio-orders-count'),
                skipOffstage: false))
            .data,
        '2');
    expect(
        find.byKey(const ValueKey('portfolio-orders-cancel-all'),
            skipOffstage: false),
        findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-balance-breakdown')),
        findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('nothing resting: P&L charts has no Orders heading',
      (tester) async {
    await pumpInvestments(tester);
    final l10n = _l10n(tester);
    await tapPill(tester, l10n.walletPortfolioAction);
    await tapAndPump(tester, _section('charts'));
    expect(find.byKey(const ValueKey('statistics-overview')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('portfolio-orders-heading'),
            skipOffstage: false),
        findsNothing);
    expect(
        find.byKey(const ValueKey('portfolio-orders-cancel-all'),
            skipOffstage: false),
        findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'nothing held: Balances has no position rows, each venue reads "No '
      'open positions"', (tester) async {
    await pumpInvestments(tester);
    final l10n = _l10n(tester);
    await tapPill(tester, l10n.walletPortfolioAction);
    expect(find.byKey(const ValueKey('portfolio-balance-overview')),
        findsOneWidget);
    expect(find.byType(PortfolioPositionRow), findsNothing);
    expect(find.text(l10n.portfolioNoOpenPositions), findsNWidgets(2));
    expect(find.byKey(const ValueKey('portfolio-positions-heading')),
        findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'a link to the old Orders tab opens the Portfolio pill on P&L charts, '
      'where the orders are; a later Positions link lands on Balances',
      (tester) async {
    final linked = ValueNotifier<String?>('orders');
    addTearDown(linked.dispose);
    await pumpInvestments(tester,
        overrides: _restingOrders(),
        child: ValueListenableBuilder<String?>(
            valueListenable: linked,
            builder: (_, key, __) => UsdAccountScreen(
                initialTab: InvestmentsTab.fromKey(key),
                initialSection: PortfolioSection.forLink(key))));
    await _pumpFrames(tester, 6);
    final container = _container(tester);
    expect(container.read(investmentsTabProvider), InvestmentsTab.positions);
    expect(container.read(portfolioSectionProvider), PortfolioSection.charts);
    expect(tester.widget<KutePill>(_section('charts')).selected, isTrue);
    expect(find.byType(HlOrderRow, skipOffstage: false), findsOneWidget);
    expect(find.byType(OpenInvestmentsScreen), findsNothing);

    linked.value = 'positions';
    await _pumpFrames(tester, 6);
    expect(container.read(portfolioSectionProvider), PortfolioSection.balances);
    expect(find.byType(HlOrderRow, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'the three section pills share one row on a 375-wide phone, no label cut',
      (tester) async {
    await pumpInvestments(tester, size: const Size(375, 812));
    await tapPill(tester, _l10n(tester).walletPortfolioAction);
    final pills = find.descendant(
        of: find.byType(InvestmentsPortfolio), matching: _sectionPills);
    expect(pills, findsNWidgets(3));
    final top = tester.getTopLeft(pills.at(0)).dy;
    for (var i = 0; i < 3; i++) {
      expect(tester.getTopLeft(pills.at(i)).dy, top);
      // Every label at its full width ("P&L charts" lost its "s" when the
      // pills were squeezed to fit).
      final label = tester.widget<KutePill>(pills.at(i)).label;
      final text = tester.renderObject<RenderParagraph>(
          find.descendant(of: pills.at(i), matching: find.text(label)));
      expect(
          text.size.width,
          greaterThanOrEqualTo(
              text.getMaxIntrinsicWidth(double.infinity) - 0.5),
          reason: label);
    }
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'the balance opens nothing: no arrow, and a tap on the total pushes '
      'no Portfolio and sends no event', (tester) async {
    final events = recordEvents();
    await pumpInvestments(tester);
    expect(find.byKey(const ValueKey('investments-balance-chevron')),
        findsNothing);
    await tester.tap(find
        .descendant(
            of: find.byType(PoolBalanceHeader),
            matching: find.byType(RollingNumberText))
        .first);
    await _pumpFrames(tester, 6);
    expect(find.byType(OpenInvestmentsScreen), findsNothing);
    expect(find.byType(KuteBackButton), findsNothing);
    expect(events.where((e) => e.$1 == 'investments_balance_tapped'), isEmpty);
    expect(events.where((e) => e.$1 == 'portfolio_opened'), isEmpty);
    expect(_container(tester).read(investmentsTabProvider),
        InvestmentsTab.investing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'with money on a rail the in-flight lines replace the split and open '
      'nothing either', (tester) async {
    final events = recordEvents();
    await pumpInvestments(tester,
        balance: const OneBalanceState(
            dollarsUsd: 25,
            investedUsd: 0,
            investingKnown: true,
            predictionsKnown: true,
            inFlight: [
              InFlightMove(
                  kind: InFlightKind.toVenue,
                  venue: OneBalanceVenue.predictions,
                  usd: 5,
                  order: InFlightOrder(
                      id: 'fo_bet',
                      venue: OneBalanceVenue.predictions,
                      orderUsd: 5,
                      side: 'Yes',
                      market: 'Lakers vs Celtics')),
            ]));
    final l10n = _l10n(tester);
    expect(find.textContaining(l10n.available), findsNothing);
    expect(find.byKey(const ValueKey('investments-balance-chevron')),
        findsNothing);
    await tester.tap(find.text(r'Placing $5.00 on Yes · Lakers vs Celtics'));
    await _pumpFrames(tester, 6);
    expect(find.byType(OpenInvestmentsScreen), findsNothing);
    expect(events.where((e) => e.$1 == 'investments_balance_tapped'), isEmpty);
    expect(events.where((e) => e.$1 == 'activity_history_opened'), isEmpty);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets("collapsed, the compact bar's total opens nothing either",
      (tester) async {
    final events = recordEvents();
    await pumpInvestments(tester);
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -400));
    await _pumpFrames(tester);
    expect(_compactTotal, findsOneWidget);
    await tester.tap(_compactTotal, warnIfMissed: false);
    await _pumpFrames(tester, 6);
    expect(find.byType(OpenInvestmentsScreen), findsNothing);
    expect(events.where((e) => e.$1 == 'investments_balance_tapped'), isEmpty);
    // Still collapsed: the total is no way back up either (the chevron
    // is).
    expect(_compactTotal, findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('the three large pills share one row on a 375-wide phone',
      (tester) async {
    await pumpInvestments(tester, size: const Size(375, 812));
    final strip = find.byType(KutePillTabs).first;
    expect(tester.widget<KutePillTabs>(strip).size, KutePillSize.large);
    final pills = find.descendant(of: strip, matching: find.byType(KutePill));
    expect(pills, findsNWidgets(3));
    // Side by side, each inside the strip, none wrapped or overflowing.
    final top = tester.getTopLeft(pills.at(0)).dy;
    for (var i = 0; i < 3; i++) {
      expect(tester.getTopLeft(pills.at(i)).dy, top);
      expect(tester.getBottomRight(pills.at(i)).dx,
          lessThanOrEqualTo(tester.getBottomRight(strip).dx + 0.01));
    }
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  for (final tab in InvestmentsTab.values) {
    testWidgets(
        'on ${tab.key}: scrolling collapses the chrome — the hero leaves, '
        'the compact bar pins with the small total, the pills and the '
        'chevron, the nav bar hides; the chevron and the very top expand '
        'it again; the pull refreshes', (tester) async {
      await pumpInvestments(tester, earn: kEarnOn);
      final l10n = _l10n(tester);
      final label = switch (tab) {
        InvestmentsTab.investing => l10n.trading,
        InvestmentsTab.predictions => l10n.predictions,
        InvestmentsTab.positions => l10n.walletPortfolioAction,
      };
      await tapPill(tester, label);
      expect(_container(tester).read(investmentsTabProvider), tab);
      final container = _container(tester);
      expect(find.byType(PoolBalanceHeader), findsOneWidget);
      expect(_compactTotal, findsNothing);
      final pillsTop = tester.getTopLeft(find.byType(KutePillTabs).first).dy;
      expect(container.read(navBarHiddenProvider), isFalse);

      // Scroll the content: the hero leaves, the compact bar is what
      // stays at the top of the page, the nav bar hides.
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -400));
      await _pumpFrames(tester);
      expect(find.byType(PoolBalanceHeader), findsNothing);
      expect(_strip(tester).size, KutePillSize.compact);
      expect(_pill(label), findsOneWidget);
      expect(tester.widget<KutePill>(_pill(label)).selected, isTrue);
      expect(tester.getTopLeft(find.byType(KutePillTabs).first).dy,
          lessThan(pillsTop));
      // The total, small, with no second line; the chevron at the right.
      expect(_compactTotal, findsOneWidget);
      final total = tester.widget<Text>(_compactTotal);
      expect(total.data, r'$25.00');
      expect(total.style!.fontSize, lessThan(20));
      expect(find.textContaining(l10n.available), findsNothing);
      expect(_chevron, findsOneWidget);
      expect(tester.getTopRight(_chevron).dx,
          greaterThan(tester.getTopRight(find.byType(KutePillTabs).first).dx));
      expect(container.read(navBarHiddenProvider), isTrue);

      // The chevron: everything returns, and so does the nav bar.
      await tester.tap(_chevron);
      await _pumpFrames(tester);
      expect(find.byType(PoolBalanceHeader), findsOneWidget);
      expect(_compactTotal, findsNothing);
      expect(_chevron, findsNothing);
      expect(_strip(tester).size, KutePillSize.large);
      expect(tester.getTopLeft(find.byType(KutePillTabs).first).dy, pillsTop);
      expect(container.read(navBarHiddenProvider), isFalse);

      // Collapsed again, then scrolled back to the very top by hand.
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -400));
      await _pumpFrames(tester);
      expect(find.byType(PoolBalanceHeader), findsNothing);
      expect(_compactTotal, findsOneWidget);
      await tester.drag(find.byType(NestedScrollView), const Offset(0, 400));
      await _pumpFrames(tester);
      expect(find.byType(PoolBalanceHeader), findsOneWidget);
      expect(_compactTotal, findsNothing);
      expect(tester.getTopLeft(find.byType(KutePillTabs).first).dy, pillsTop);
      expect(container.read(navBarHiddenProvider), isFalse);

      // Pull past the top: the page's one refresh indicator, reported
      // with the pill that was refreshed.
      // Let the last drag's bounce and the indicator's cancel finish:
      // the nav bar's room easing back in under the header restarts the
      // bounce once, so it ends a few frames later than it used to.
      await _pumpFrames(tester, 10);
      final events = recordEvents();
      await tester.drag(find.byType(NestedScrollView), const Offset(0, 300));
      await tester.pump();
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      await _pumpFrames(tester, 15);
      expect(
          events.where((e) =>
              e.$1 == 'pull_to_refresh_executed' &&
              e.$2?['screen'] == 'usd' &&
              e.$2?['tab'] == tab.key),
          hasLength(1));
      // Every pill runs the one shared "update everything" refresh, the
      // function Home's pull runs too.
      final refresh =
          container.read(refreshEverythingProvider) as RecordingRefresh;
      // (A short pill's list can already pull while scrolled back to the
      // top by hand above: every pull is the same call.)
      expect(refresh.triggers, isNotEmpty);
      expect(refresh.triggers.map((t) => (t.screen, t.tab)),
          everyElement(('usd', tab.key)));
      expect(refresh.runs, refresh.triggers.length);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  }

  testWidgets(
      'collapsed with the nav bar away, the compact bar sits under the '
      'status bar with no room kept for the bar; the room comes back with '
      'the bar', (tester) async {
    const statusBar = 47.0;
    tester.view.padding = const FakeViewPadding(top: statusBar);
    addTearDown(tester.view.resetPadding);
    await pumpInvestments(tester);
    final container = _container(tester);
    final padTop = 6.h;
    final barSpace = kShellTopBarSpacing.h;
    final pillsTop = tester.getTopLeft(find.byType(KutePillTabs).first).dy;
    // Expanded, the nav bar's room sits above the hero, as before.
    expect(tester.getTopLeft(find.byType(PoolBalanceHeader)).dy,
        greaterThanOrEqualTo(statusBar + barSpace - 0.5));

    await tester.drag(find.byType(NestedScrollView), const Offset(0, -400));
    await _pumpFrames(tester);
    expect(container.read(navBarHiddenProvider), isTrue);
    expect(_compactTotal, findsOneWidget);
    // The compact bar's top is the safe-area top, plus only its own air.
    final totalTop = tester.getTopLeft(_compactTotal).dy;
    expect(totalTop, moreOrLessEquals(statusBar + padTop, epsilon: 0.5));
    expect(totalTop, lessThan(statusBar + barSpace));

    // The bar comes back (a scroll the other way): the room returns with
    // it, so the bar never lands on the compact pills.
    container.read(navBarHiddenProvider.notifier).state = false;
    await _pumpFrames(tester, 4);
    expect(tester.getTopLeft(_compactTotal).dy,
        moreOrLessEquals(statusBar + barSpace + padTop, epsilon: 0.5));

    // Back at the very top, everything is where it started.
    await tester.tap(_chevron);
    await _pumpFrames(tester);
    expect(tester.getTopLeft(find.byType(KutePillTabs).first).dy, pillsTop);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('under Reduce Motion the room goes and comes back at once',
      (tester) async {
    await pumpInvestments(
      tester,
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: const UsdAccountScreen(),
        ),
      ),
    );
    final container = _container(tester);
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -400));
    await _pumpFrames(tester);
    expect(container.read(navBarHiddenProvider), isTrue);
    expect(tester.getTopLeft(_compactTotal).dy,
        moreOrLessEquals(6.h, epsilon: 0.5));
    container.read(navBarHiddenProvider.notifier).state = false;
    await tester.pump();
    await tester.pump();
    expect(tester.getTopLeft(_compactTotal).dy,
        moreOrLessEquals(kShellTopBarSpacing.h + 6.h, epsilon: 0.5));
    await unmountInvestments(tester);
  });

  testWidgets('the compact bar dims the total while a venue is still to answer',
      (tester) async {
    await pumpInvestments(tester,
        balance: const OneBalanceState(
            dollarsUsd: 25,
            investedUsd: 0,
            investingKnown: false,
            predictionsKnown: true));
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -400));
    await _pumpFrames(tester);
    final total = tester.widget<Text>(_compactTotal);
    expect(total.data, r'$25.00');
    final c = tester.element(_compactTotal).colors;
    expect(total.style!.color, c.textSecondary);
    // Dimmed and sweeping, as the hero is.
    expect(
        tester
            .widget<StaleShimmer>(find.ancestor(
                of: _compactTotal, matching: find.byType(StaleShimmer)))
            .stale,
        isTrue);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'under Reduce Motion the header snaps between its two states, with '
      'no blend and no scroll animation', (tester) async {
    await pumpInvestments(tester,
        child: Builder(
            builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: const UsdAccountScreen())));
    // A short scroll stays expanded (the whole header drawn, nothing of
    // the bar), and the scroll's end snaps back to the top.
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(NestedScrollView)));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(find.byType(PoolBalanceHeader), findsOneWidget);
    expect(_compactTotal, findsNothing);
    await gesture.up();
    await _pumpFrames(tester, 3);
    expect(find.byType(PoolBalanceHeader), findsOneWidget);
    expect(_compactTotal, findsNothing);

    // Past half way the bar is there at once, fully drawn.
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -400));
    await _pumpFrames(tester, 3);
    expect(find.byType(PoolBalanceHeader), findsNothing);
    expect(_compactTotal, findsOneWidget);
    final bar =
        find.ancestor(of: _compactTotal, matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(bar.first).opacity, 1.0);

    // The chevron jumps: expanded on the very next frame.
    await tester.tap(_chevron);
    await tester.pump();
    expect(find.byType(PoolBalanceHeader), findsOneWidget);
    expect(_compactTotal, findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });
}
