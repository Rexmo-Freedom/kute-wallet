// The Dollars tab (one balance; "Investments" in code): the spending
// account's top strip is Bitcoin | Dollars, and the page carries the
// one-balance hero (no title; the balance opens nothing, nor does the
// compact bar's total, and no "Invested" under it), ONE compact row of
// actions under it, Add · Send · Portfolio (the Bitcoin tab's squared
// buttons), and ONE pill row, Investing · Predictions, over the embedded
// venue browsers. The picked pill always shows what it holds ("Investing
// · Trending", the category in the quieter weight, a chevron in a filled
// circle at its end) and tapping it again opens the category sheet, a
// tile grid (investments_category_sheet.dart); the browsers draw no
// category row of their own in here.
// THE PORTFOLIO IS ITS OWN SCREEN (founder, 31 October 2026): the action
// row's third button pushes portfolio_screen.dart on `/portfolio`, with
// the app's back, no hero and no dock, and its own section pills,
// Portfolio (Balances: the shares block, then the positions under their
// venue) · P&L Charts · Activity; every old link that named a Portfolio
// section (`?tab=positions|portfolio|open|orders|statistics|charts|
// activity|balances`) opens that screen on the section, and the page's
// pill stays where it was. The section is kept for the session.
// The dock is the one quiet "Search or ask Sal" pill, scoped to the pill
// on screen; the Portfolio screen declares its own bar context instead.
// Add opens the Dollars receive screen on its coin step, whose "From your
// Bitcoin" row opens the Investments deposit sheet; Send opens the same
// sheet turned around. No venue Deposit or Withdraw exists anywhere
// inside it.
// The whole page scrolls as one on both pills, and the chrome collapses:
// the hero and the action row leave, the pills condense into the compact
// pinned bar with a small copy of the total and a chevron that brings
// everything back, as does scrolling to the very top.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:kute/providers/refresh_everything_provider.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show
        SearchCategory,
        searchMarketsOnlyProvider,
        searchWalletScopeProvider,
        selectedSearchCategoryProvider;
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
import 'package:kute/screens/portfolio/portfolio_screen.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarContextProvider, kuteBarTop;
import 'package:kute/screens/shared/kute_pill_tabs.dart'
    show KutePill, KutePillSize, KutePillTabs;
import 'package:kute/screens/shared/open_once.dart';
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

/// The Portfolio screen's section pills (not Balances' Move money pill).
final _sectionPills = find.byWidgetPredicate((w) =>
    w is KutePill &&
    w.key is ValueKey<String> &&
    (w.key! as ValueKey<String>).value.startsWith('portfolio-section-pill-'));

/// The Portfolio section on screen, by key (the picked section pill
/// names it).
String _sectionOn(WidgetTester tester) =>
    _container(tester).read(portfolioSectionProvider).key;

/// Picks a Portfolio section the way the Portfolio screen offers it: its
/// own section pills at the top of the list.
Future<void> pickSection(WidgetTester tester, String key) =>
    tapAndPump(tester, find.byKey(ValueKey('portfolio-section-pill-$key')));

/// Scrolls the pill strip alone, sideways, until [pill] can be tapped. The
/// picked pill carries its category ("Investing · Trending ⌄"), so on a
/// phone the other pill starts past the right edge of the side-scrolling
/// row; the harness's reveal (ensureVisible) would scroll the page's outer
/// scroll too, collapsing the header, which is not what a thumb does.
Future<void> _revealInStrip(WidgetTester tester, Finder pill) async {
  final strip = find.descendant(
      of: find.byType(KutePillTabs).first, matching: find.byType(Scrollable));
  for (var i = 0; i < 12 && pill.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(strip, const Offset(-80, 0), warnIfMissed: false);
    await _pumpFrames(tester, 3);
  }
  expect(pill.hitTestable(), findsOneWidget);
}

/// Picks the pill named [label] the way a thumb does: the strip scrolled
/// sideways if need be, then a tap. A pill already picked is left alone (a
/// tap on it opens its categories, which is not a pick).
Future<void> _tapPill(WidgetTester tester, String label) async {
  final pill = _pill(label);
  if (tester.widget<KutePill>(pill).selected) return;
  await _revealInStrip(tester, pill);
  await tester.tap(pill);
  await _pumpFrames(tester, 5);
}

/// The action row's Portfolio button, by its label (the Portfolio is no
/// pill: the only "Portfolio" on the page is this button).
Finder _portfolioAction(WidgetTester tester) => find.descendant(
    of: find.byType(UsdAccountActionRow),
    matching: find.text(_l10n(tester).walletPortfolioAction));

/// Opens the Portfolio the way the page offers it: the action row's
/// third button pushes the Portfolio screen over the page.
Future<void> openPortfolio(WidgetTester tester) async {
  await tapAndPump(tester, _portfolioAction(tester));
  expect(find.byType(PortfolioScreen), findsOneWidget);
}

/// The Portfolio screen's back: the Dollars page again, as it was left.
Future<void> closePortfolio(WidgetTester tester) async {
  await tapAndPump(tester, find.byType(KuteBackButton));
  expect(find.byType(PortfolioScreen), findsNothing);
}

/// The page under a router: the Portfolio is a screen pushed on
/// `/portfolio` (app_router.dart), so the tests that open it mount the
/// page in a GoRouter of their own. [page] builds the `/` route (the
/// whole [UsdAccountScreen] by default).
Widget _routed([WidgetBuilder? page]) {
  final build = page ?? (_) => const UsdAccountScreen();
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (context, _) => build(context)),
    // The back button's fallback when there is nothing to pop.
    GoRoute(path: '/usd', builder: (context, _) => build(context)),
    GoRoute(
        path: PortfolioScreen.route,
        builder: (_, __) => const PortfolioScreen()),
  ]);
  addTearDown(router.dispose);
  return MaterialApp.router(
    theme: ThemeData(
      fontFamily: 'Inter',
      splashFactory: NoSplash.splashFactory,
      extensions: [AppColorsExtension.light()],
    ),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
  );
}

/// [pumpInvestments] with the page under [_routed].
Future<void> pumpRouted(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Transaction? history,
  Size size = const Size(390, 844),
  WidgetBuilder? page,
}) =>
    pumpInvestments(tester,
        overrides: overrides,
        history: history,
        size: size,
        child: _routed(page));

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

/// Records the Predictions orders cancelled instead of reaching the venue.
class _CancellingPoly extends PolymarketTradingNotifier {
  _CancellingPoly(this.cancelled);
  final List<String> cancelled;

  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState();

  @override
  Future<void> cancelOrder(String orderId) async => cancelled.add(orderId);
}

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

/// The page's body, on screen or under the Portfolio screen.
Finder get _body => find.byType(InvestmentsBody, skipOffstage: false);

AppLocalizations _l10n(WidgetTester tester) => tester.element(_body).l10n;

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(_body));

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

/// The two venue pills: the page's whole strip (the Portfolio is a screen).
const _venuePills = [InvestmentsTab.investing, InvestmentsTab.predictions];

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // The Portfolio screen is pushed once at a time; a test that ends
    // with it open never pops it.
    OpenOnce.reset();
  });

  testWidgets(
      'two pills in order, Investing · Predictions, the picked one carrying '
      'its category and the menu chevron, a step bigger, over the embedded '
      'browsers; the Portfolio is no pill', (tester) async {
    await pumpInvestments(tester, earn: kEarnOn);
    final l10n = _l10n(tester);
    final strip = _strip(tester);
    // Two names share the row. The picked pill carries what it holds (the
    // category, the default's own name included: founder, 31 October
    // 2026, "it should be more clear that we have much more context
    // here") and the chevron in its circle; the other its name alone. One
    // row, nothing under it.
    expect(strip.items.map((i) => i.label), [l10n.trading, l10n.predictions]);
    expect(strip.items.map((i) => i.label), ['Investing', 'Predictions']);
    expect(strip.items.first.detail, l10n.hlPillTrending);
    expect(strip.items.first.menu, isTrue);
    expect(strip.items.last.detail, isNull);
    expect(strip.items.last.menu, isFalse);
    // The Portfolio is no pill (the action row's third button, its own
    // screen), and nothing reads Positions.
    expect(_pill(l10n.walletPortfolioAction), findsNothing);
    expect(_pill(l10n.ledgerPositionsTitle), findsNothing);
    expect(find.text(l10n.walletPortfolioAction), findsOneWidget);
    expect(find.byType(PortfolioScreen), findsNothing);
    // No glyphs and no venue logos: the names share the row with the
    // category.
    expect(strip.items.map((i) => i.icon), everyElement(isNull));
    expect(strip.items.map((i) => i.leading), everyElement(isNull));
    expect(strip.size, KutePillSize.large);
    expect(strip.scroll, isTrue);
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
    // Portfolio is nowhere on the page (it waits for its screen).
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
    // with no arrow after it (it opens nothing), and only "Invested" under
    // it at rest (founder, 28 October 2026).
    final header =
        tester.widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader));
    expect(header.totalLabel, isNull);
    expect(find.text(l10n.investmentsTotal), findsNothing);
    expect(header.amountText, r'$25.00');
    expect(header.availableText, isNull);
    expect(header.investedText, isNotNull);
    expect(find.text('${l10n.available} '), findsNothing);
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
      'no venue Deposit or Withdraw anywhere; the actions are one row '
      'under the hero, Add · Send · Portfolio, the dock is search alone, '
      'and Add opens the Dollars receive screen', (tester) async {
    final events = recordEvents();
    var receiveOpened = 0;
    UsdAccountActionBar.debugReceiveOpener = (_) => receiveOpened++;
    addTearDown(() => UsdAccountActionBar.debugReceiveOpener = null);
    await pumpInvestments(tester, earn: kEarnOn);
    final l10n = _l10n(tester);
    expect(find.byType(VenueDepositButton, skipOffstage: false), findsNothing);
    expect(find.byType(InvestmentActionBar, skipOffstage: false), findsNothing);
    // No bank words anywhere: the verbs say what happens.
    expect(find.text(l10n.withdraw, skipOffstage: false), findsNothing);
    expect(find.text(l10n.deposit, skipOffstage: false), findsNothing);
    expect(find.textContaining('Investing deposit', skipOffstage: false),
        findsNothing);
    expect(find.textContaining('Predictions deposit', skipOffstage: false),
        findsNothing);
    // The full-width door is gone: no button in the header, and the
    // door's label is nowhere on the page.
    expect(find.byType(AppButton, skipOffstage: false), findsNothing);
    expect(find.text(l10n.dollarDeposit, skipOffstage: false), findsNothing);

    // The action row under the hero: Add, Send and Portfolio, three equal
    // squared buttons (founder, 31 October 2026), the Bitcoin dock's
    // arrows and the Portfolio's pie, each once on the page; then the
    // pills. The action keys stay `receive` and `send` so the events read
    // as before; Portfolio sends `portfolio`, the Home card's key.
    final row = find.byType(UsdAccountActionRow);
    expect(row, findsOneWidget);
    expect(tester.getTopLeft(row).dy,
        greaterThan(tester.getBottomLeft(find.byType(PoolBalanceHeader)).dy - 1));
    final actions = UsdAccountActionBar.moneyActions(tester.element(row));
    expect(actions.map((a) => a.label),
        [l10n.investmentsAdd, l10n.send, l10n.walletPortfolioAction]);
    expect(actions.map((a) => a.trackingId), ['receive', 'send', 'portfolio']);
    expect(actions.map((a) => a.icon), [
      Icons.south_west_rounded,
      Icons.north_east_rounded,
      Icons.pie_chart_rounded
    ]);
    expect(find.text(l10n.investmentsAdd), findsOneWidget);
    expect(find.text(l10n.send), findsOneWidget);
    expect(find.text(l10n.walletPortfolioAction), findsOneWidget);
    expect(find.text(l10n.receive, skipOffstage: false), findsNothing);
    expect(tester.getTopLeft(find.byType(KutePillTabs).first).dy,
        greaterThan(tester.getBottomLeft(row).dy));

    // The dock: no money verbs, the one quiet door to search and Sal.
    final bar =
        tester.widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
    expect(bar.actions, isEmpty);
    expect(bar.onSearch, isNotNull);
    expect(find.byKey(const ValueKey('dock-search-pill')), findsOneWidget);

    // Add opens the Dollars receive screen, with the Bitcoin dock's
    // quick-action key under this surface and the dock as the receive
    // flow's entry source.
    await tester.tap(find.text(l10n.investmentsAdd));
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
    // Portfolio (Positions) searches everything: All, never this
    // account's past transactions alone.
    expect(UsdAccountActionBar.searchTarget(InvestmentsTab.positions),
        (category: SearchCategory.all, source: 'usd'));
  });

  testWidgets(
      'the dock searches the pill on screen, the venue\'s own markets; the '
      'Portfolio screen has no dock and declares its own bar, search and '
      'Sal under its own source', (tester) async {
    final events = recordEvents();
    await pumpRouted(tester);
    final l10n = _l10n(tester);
    final container = _container(tester);

    // The Portfolio screen: no dock of its own (Add and Send are not
    // repeated there); the shell-level bar reads its context instead.
    await openPortfolio(tester);
    expect(
        find.descendant(
            of: find.byType(PortfolioScreen),
            matching: find.byType(KuteBottomActionBar)),
        findsNothing);
    final top = kuteBarTop(container.read(kuteBarContextProvider));
    expect(top, isNotNull);
    expect(top!.label, l10n.searchOrAskSalShort);
    expect(top.source, 'portfolio');
    await closePortfolio(tester);
    expect(kuteBarTop(container.read(kuteBarContextProvider))?.source,
        isNot('portfolio'));

    // The page's dock: one search pill, scoped to the pill on screen (the
    // Investing markets, results first, under the venue's own source).
    final bar =
        tester.widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
    bar.onSearch!();
    await tester.pump();
    expect(container.read(selectedSearchCategoryProvider),
        SearchCategory.perpetuals);
    // Not the wallet-scoped history.
    expect(container.read(searchWalletScopeProvider), isNull);
    expect(container.read(searchMarketsOnlyProvider), isNot(isNull));
    expect(events.where((e) => e.$1 == 'search_opened').single.$2,
        {'source': 'trading', 'initial_category': 'perpetuals'});
    await unmountInvestments(tester);
  });

  testWidgets(
      'a pill tap reports analytics_tab_selected and the venue open event; '
      'a re-tap opens the category sheet; the action row\'s Portfolio '
      'pushes the Portfolio screen on Balances', (tester) async {
    final events = recordEvents();
    await pumpRouted(tester);
    final l10n = _l10n(tester);

    await _tapPill(tester, l10n.predictions);
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
    // The picked pill now carries what it holds: Predictions · Trending.
    expect(tester.widget<KutePill>(_pill(l10n.predictions)).detail,
        l10n.polyPillTrending);
    expect(tester.widget<KutePill>(_pill(l10n.predictions)).menu, isTrue);
    expect(tester.widget<KutePill>(_pill(l10n.trading)).detail, isNull);

    // Re-tapping the pill on screen is not a new view: it opens the
    // section's categories to pick from, the tile grid (every topic a
    // tile, the venue's artwork), with the sheet's circled close.
    final before =
        events.where((e) => e.$1 == 'analytics_tab_selected').length;
    await tapAndPump(tester, _pill(l10n.predictions));
    expect(find.text(l10n.polyPillPolitics), findsOneWidget);
    expect(find.byType(KuteCloseButton), findsOneWidget);
    expect(events.where((e) => e.$1 == 'analytics_tab_selected').length,
        before);
    expect(events.last.$1, 'category_sheet_opened');
    expect(events.last.$2, {'surface': 'investments', 'section': 'predictions'});
    await tapAndPump(tester, find.byType(KuteCloseButton));
    expect(find.text(l10n.polyPillPolitics), findsNothing);

    // The Portfolio: the action row's button, the Home card's key under
    // this surface, pushes the Portfolio screen, which mounts on Balances
    // with the app's standard back; no pill event, no extra event of its
    // own.
    await openPortfolio(tester);
    expect(find.byType(InvestmentsPortfolio), findsOneWidget);
    expect(_container(tester).read(portfolioSectionProvider),
        PortfolioSection.balances);
    expect(_sectionOn(tester), 'balances');
    // Balances: the shares block over the positions.
    expect(find.byKey(const ValueKey('portfolio-balance-overview')),
        findsOneWidget);
    expect(find.byType(OpenInvestmentsScreen), findsNothing);
    expect(find.byType(KuteBackButton), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(events.where((e) => e.$1 == 'portfolio_opened'), isEmpty);
    expect(events.where((e) => e.$1 == 'analytics_tab_selected').length,
        before);
    expect(events.where((e) => e.$1 == 'quick_action_tapped').last.$2,
        {'action': 'portfolio', 'source': 'usd'});

    // Back: the page as it was left, Predictions still picked.
    await closePortfolio(tester);
    expect(_container(tester).read(investmentsTabProvider),
        InvestmentsTab.predictions);
    expect(find.byType(InvestmentsPortfolio, skipOffstage: false),
        findsNothing);

    await _tapPill(tester, l10n.trading);
    expect(events.any((e) => e.$1 == 'hyperliquid_tab_opened'), isTrue);
    expect(find.byType(HyperliquidScreen), findsOneWidget);
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
    // opens Activity. `positions` stays the Portfolio's key (the screen's
    // link and its analytics `tab`).
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
      'a link to the old Activity tab opens the Portfolio screen on '
      'Activity over the page, whose pill stays; a later Positions link '
      'lands the open screen on Balances, with no second copy',
      (tester) async {
    final events = recordEvents();
    final linked = ValueNotifier<String?>('activity');
    addTearDown(linked.dispose);
    await pumpRouted(tester,
        page: (_) => ValueListenableBuilder<String?>(
            valueListenable: linked,
            builder: (_, key, __) => UsdAccountScreen(
                initialTab: InvestmentsTab.fromKey(key),
                initialSection: PortfolioSection.forLink(key))));
    await _pumpFrames(tester, 6);
    final container = _container(tester);
    expect(find.byType(PortfolioScreen), findsOneWidget);
    // The page under it keeps its pill: Portfolio is no pill to pick.
    expect(container.read(investmentsTabProvider), InvestmentsTab.investing);
    expect(container.read(portfolioSectionProvider), PortfolioSection.activity);
    expect(_sectionOn(tester), 'activity');
    expect(find.byKey(const ValueKey('portfolio-section-activity')),
        findsOneWidget);
    expect(find.byType(OpenInvestmentsScreen), findsNothing);
    expect(events.where((e) => e.$1 == 'portfolio_opened'), isEmpty);

    linked.value = 'positions';
    await _pumpFrames(tester, 6);
    expect(find.byType(PortfolioScreen), findsOneWidget);
    expect(container.read(investmentsTabProvider), InvestmentsTab.investing);
    expect(container.read(portfolioSectionProvider), PortfolioSection.balances);
    expect(_sectionOn(tester), 'balances');
    expect(find.byKey(const ValueKey('portfolio-balance-overview')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'the Portfolio screen\'s sections: Balances with the shares block, '
      'P&L charts, Activity with the merged list; each switch is reported, '
      'and the section is kept for the session', (tester) async {
    final events = recordEvents();
    await pumpRouted(tester,
        history: Transaction(
          bitcoinTransactions: const [],
          sparkTransactions: const [],
          sparkUnclaimedDeposits: const [],
          usdbTokenTransactions: const [],
          swapOrderTransactions: const [],
          polymarketTransactions: [_bet('bet0'), _bet('bet1')],
        ));
    final l10n = _l10n(tester);
    await openPortfolio(tester);

    // The screen's own section pills, three, inside the Portfolio; the
    // screen's title reads Portfolio, nothing reads Positions.
    expect(
        find.descendant(
            of: find.byType(InvestmentsPortfolio), matching: _sectionPills),
        findsNWidgets(3));
    expect(
        find.descendant(
            of: find.byType(AppBar),
            matching: find.text(l10n.walletPortfolioAction)),
        findsOneWidget);
    expect(find.text(l10n.ledgerPositionsTitle), findsNothing);
    expect(_sectionOn(tester), 'balances');
    expect(find.byKey(const ValueKey('statistics-overview')), findsNothing);
    // Balances: the shares block (founder, 31 October 2026: "Portfolio is
    // just open positions. On top, instead of the balance, show the
    // shares with the pie chart on the left"): the ring with the shares
    // as rows, no Available to invest, no Move money, no button, no
    // tagline, no Total investments.
    expect(find.byKey(const ValueKey('portfolio-balance-breakdown')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('portfolio-balance-ring')), findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-share-buyingPower')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-move-money')), findsNothing);
    expect(find.byKey(const ValueKey('portfolio-balance-split-toggle')),
        findsNothing);
    expect(find.text(l10n.moveTransfer), findsNothing);
    expect(find.text(l10n.portfolioBuyingPower), findsNothing);
    expect(find.byType(AppButton), findsNothing);
    expect(find.text('Total investments'), findsNothing);
    expect(find.text('Ready for any trade or prediction'), findsNothing);
    expect(find.text(l10n.betInvested), findsNothing);

    // P&L charts: the one card, Historic only (founder, 28 October 2026:
    // no Active | Historic pair); neither Balances nor the activity.
    await pickSection(tester, 'charts');
    expect(events.where((e) => e.$1 == 'analytics_tab_selected').last.$2, {
      'tab': 'positions',
      'from_tab': 'positions',
      'surface': 'investments',
      'sub': 'charts',
      'from_sub': 'balances'
    });
    expect(find.byKey(const ValueKey('statistics-overview')), findsOneWidget);
    expect(find.byKey(const ValueKey('statistics-active')), findsNothing);
    expect(find.byKey(const ValueKey('statistics-historic')), findsNothing);
    expect(
        find.byKey(const ValueKey('statistics-allocation-ring')), findsNothing);
    expect(find.byKey(const ValueKey('portfolio-balance-breakdown')),
        findsNothing);
    expect(find.byKey(const ValueKey('portfolio-move-money')), findsNothing);
    expect(find.byKey(const ValueKey('portfolio-activity-list')), findsNothing);

    // Activity: the merged list, all of it, with no "See all".
    await pickSection(tester, 'activity');
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

    // Re-picking the section on screen is not a new view.
    final before =
        events.where((e) => e.$1 == 'analytics_tab_selected').length;
    await pickSection(tester, 'activity');
    expect(events.where((e) => e.$1 == 'analytics_tab_selected').length,
        before);

    // Away and back: the Portfolio comes back on the section it was left
    // on. Opening the screen is no pill switch, so no strip event.
    await closePortfolio(tester);
    await openPortfolio(tester);
    expect(_sectionOn(tester), 'activity');
    expect(
        find.byKey(const ValueKey('portfolio-activity-list')), findsOneWidget);
    expect(events.where((e) => e.$1 == 'analytics_tab_selected').length,
        before);
    expect(find.byType(OpenInvestmentsScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'View positions (openInvestmentsPositions) opens the Portfolio screen '
      'on Balances, where the positions are, whatever section was left open',
      (tester) async {
    // Investments is the tab on screen: no shell navigation, the screen
    // is pushed over it.
    await pumpRouted(tester, overrides: [
      activeShellTabProvider.overrideWith((_) => ActiveNavTab.usd),
    ]);
    await openPortfolio(tester);
    await pickSection(tester, 'activity');
    await closePortfolio(tester);
    openInvestmentsPositions(tester.element(_body));
    await _pumpFrames(tester, 4);
    final container = _container(tester);
    expect(find.byType(PortfolioScreen), findsOneWidget);
    expect(container.read(portfolioSectionProvider), PortfolioSection.balances);
    expect(_sectionOn(tester), 'balances');
    expect(find.byKey(const ValueKey('portfolio-balance-overview')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('statistics-overview')), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'Balances lists what is held under its venue, the Positions list\'s '
      'rows, under the shares', (tester) async {
    await pumpRouted(tester, overrides: [
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
          const HyperliquidTradingState(
              isInitialized: true, positions: [_btcPosition]))),
    ]);
    final l10n = _l10n(tester);
    await openPortfolio(tester);
    expect(_sectionOn(tester), 'balances');
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
      'P&L charts lists the resting orders under the one block, each '
      'venue\'s under its small heading, Predictions then Investing, with no '
      'Orders title and no count; one quiet Cancel all after the last; a '
      'row\'s Cancel runs the venue\'s cancel; Balances lists none; the '
      'switch is reported with sub: charts', (tester) async {
    final events = recordEvents();
    final cancelled = <String>[];
    await pumpRouted(tester, overrides: [
      ..._restingOrders(),
      polymarketTradingProvider.overrideWith(() => _CancellingPoly(cancelled)),
    ]);
    final l10n = _l10n(tester);
    await openPortfolio(tester);

    // Balances: no orders.
    expect(find.byType(HlOrderRow, skipOffstage: false), findsNothing);
    expect(find.byType(PolyOrderRow, skipOffstage: false), findsNothing);

    await pickSection(tester, 'charts');
    expect(_container(tester).read(portfolioSectionProvider),
        PortfolioSection.charts);
    expect(_sectionOn(tester), 'charts');
    expect(events.where((e) => e.$1 == 'analytics_tab_selected').last.$2, {
      'tab': 'positions',
      'from_tab': 'positions',
      'surface': 'investments',
      'sub': 'charts',
      'from_sub': 'balances'
    });
    expect(find.byKey(const ValueKey('statistics-overview')), findsOneWidget);
    // No Orders heading, no count, no button.
    expect(
        find.byKey(const ValueKey('portfolio-orders-heading'),
            skipOffstage: false),
        findsNothing);
    expect(
        find.byKey(const ValueKey('portfolio-orders-count'),
            skipOffstage: false),
        findsNothing);
    expect(
        find.text(l10n.portfolioTabOrders, skipOffstage: false), findsNothing);
    expect(find.byType(AppButton, skipOffstage: false),
        findsNWidgets(2)); // the rows' own Cancel buttons
    // Each venue's order under its small heading, under the block (the
    // card with the venue rows and the chart), never inside it: the
    // Predictions order first, then the Investing order.
    final predictions =
        find.byKey(const ValueKey('pnl-venue-predictions-orders'));
    final investing = find.byKey(const ValueKey('pnl-venue-investing-orders'));
    final card = find.byKey(const ValueKey('statistics-pnl-card'));
    expect(
        find.descendant(
            of: card,
            matching: find.byKey(const ValueKey('pnl-venue-predictions'))),
        findsOneWidget);
    // The resting orders stay below the card.
    expect(tester.getTopLeft(predictions).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(card).dy));
    expect(
        find.descendant(
            of: card, matching: find.byType(PolyOrderRow, skipOffstage: false)),
        findsNothing);
    expect(
        find.descendant(
            of: card, matching: find.byType(HlOrderRow, skipOffstage: false)),
        findsNothing);
    for (final (venue, name) in [
      ('predictions', l10n.predictions),
      ('investing', l10n.trading)
    ]) {
      expect(
          tester
              .widget<Text>(find.byKey(ValueKey('pnl-orders-heading-$venue'),
                  skipOffstage: false))
              .data,
          name);
    }
    final scrollable = find
        .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.byType(PolyOrderRow), 200,
        scrollable: scrollable);
    await _pumpFrames(tester);
    expect(
        find.descendant(of: predictions, matching: find.byType(PolyOrderRow)),
        findsOneWidget);
    expect(tester.getTopLeft(find.byType(PolyOrderRow)).dy,
        greaterThan(tester.getBottomLeft(card).dy));
    expect(find.descendant(of: predictions, matching: find.byType(HlOrderRow)),
        findsNothing);
    await tester.scrollUntilVisible(find.byType(HlOrderRow), 200,
        scrollable: scrollable);
    await _pumpFrames(tester);
    expect(find.descendant(of: investing, matching: find.byType(HlOrderRow)),
        findsOneWidget);
    expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('pnl-venue-predictions')))
            .dy,
        lessThan(tester
            .getTopLeft(find.byKey(const ValueKey('pnl-venue-investing')))
            .dy));
    expect(tester.getTopLeft(find.byType(PolyOrderRow)).dy,
        lessThan(tester.getTopLeft(find.byType(HlOrderRow)).dy));
    // Orders at both venues: one quiet Cancel all text link after the last
    // venue's orders, no button.
    final cancelAll = find.byKey(const ValueKey('portfolio-orders-cancel-all'));
    await tester.scrollUntilVisible(cancelAll, 200, scrollable: scrollable);
    await _pumpFrames(tester);
    expect(cancelAll, findsOneWidget);
    expect(find.descendant(of: cancelAll, matching: find.byType(AppButton)),
        findsNothing);
    expect(find.descendant(of: cancelAll, matching: find.text('Cancel all')),
        findsOneWidget);
    expect(tester.getTopLeft(cancelAll).dy,
        greaterThan(tester.getBottomLeft(find.byType(HlOrderRow)).dy - 0.5));
    expect(find.byKey(const ValueKey('portfolio-balance-breakdown')),
        findsNothing);

    // The row's own Cancel runs the venue's cancel for that order.
    await tester.scrollUntilVisible(find.byType(PolyOrderRow), -200,
        scrollable: scrollable);
    await _pumpFrames(tester);
    await tester.tap(find.descendant(
        of: find.byType(PolyOrderRow), matching: find.text(l10n.cancel)));
    await _pumpFrames(tester);
    expect(cancelled, ['pm-1']);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'orders at one venue only: that venue\'s rows, no Cancel all link',
      (tester) async {
    await pumpRouted(tester, overrides: [
      hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
          const HyperliquidTradingState(
              isInitialized: true, openOrders: [_hlOrder]))),
    ]);
    await openPortfolio(tester);
    await pickSection(tester, 'charts');
    expect(find.byType(HlOrderRow, skipOffstage: false), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('pnl-venue-investing-orders'),
                skipOffstage: false),
            matching: find.byType(HlOrderRow, skipOffstage: false)),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('portfolio-orders-cancel-all'),
            skipOffstage: false),
        findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('nothing resting: P&L charts has no Orders heading',
      (tester) async {
    await pumpRouted(tester);
    await openPortfolio(tester);
    await pickSection(tester, 'charts');
    expect(find.byKey(const ValueKey('statistics-overview')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('portfolio-orders-heading'),
            skipOffstage: false),
        findsNothing);
    expect(
        find.byKey(const ValueKey('portfolio-orders-cancel-all'),
            skipOffstage: false),
        findsNothing);
    expect(
        find.byKey(const ValueKey('pnl-venue-investing-orders'),
            skipOffstage: false),
        findsNothing);
    expect(
        find.byKey(const ValueKey('pnl-venue-predictions-orders'),
            skipOffstage: false),
        findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'nothing held: Balances has no position rows, one Sal "No open '
      'positions" state', (tester) async {
    await pumpRouted(tester);
    final l10n = _l10n(tester);
    await openPortfolio(tester);
    expect(find.byKey(const ValueKey('portfolio-balance-overview')),
        findsOneWidget);
    expect(find.byType(PortfolioPositionRow), findsNothing);
    // Nothing open anywhere: Sal's empty state once, not two empty venues.
    expect(find.text(l10n.portfolioNoOpenPositions), findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-balance-no-positions')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-positions-heading')),
        findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'a link to the old Orders tab opens the Portfolio screen on P&L '
      'charts, where the orders are; a later Positions link lands it on '
      'Balances', (tester) async {
    final linked = ValueNotifier<String?>('orders');
    addTearDown(linked.dispose);
    await pumpRouted(tester,
        overrides: _restingOrders(),
        page: (_) => ValueListenableBuilder<String?>(
            valueListenable: linked,
            builder: (_, key, __) => UsdAccountScreen(
                initialTab: InvestmentsTab.fromKey(key),
                initialSection: PortfolioSection.forLink(key))));
    await _pumpFrames(tester, 6);
    final container = _container(tester);
    expect(find.byType(PortfolioScreen), findsOneWidget);
    expect(container.read(investmentsTabProvider), InvestmentsTab.investing);
    expect(container.read(portfolioSectionProvider), PortfolioSection.charts);
    expect(_sectionOn(tester), 'charts');
    expect(find.byType(HlOrderRow, skipOffstage: false), findsOneWidget);
    expect(find.byType(OpenInvestmentsScreen), findsNothing);

    linked.value = 'positions';
    await _pumpFrames(tester, 6);
    expect(find.byType(PortfolioScreen), findsOneWidget);
    expect(container.read(portfolioSectionProvider), PortfolioSection.balances);
    expect(find.byType(HlOrderRow, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'the Portfolio screen: the app\'s back under a Portfolio title, no '
      'dock, and three section pills, Portfolio · P&L Charts · Activity, '
      'the one on screen marked; back lands on the page, its pill untouched',
      (tester) async {
    await pumpRouted(tester, size: const Size(375, 812));
    final l10n = _l10n(tester);
    await openPortfolio(tester);
    expect(
        find.descendant(
            of: find.byType(AppBar),
            matching: find.text(l10n.walletPortfolioAction)),
        findsOneWidget);
    expect(find.byType(KuteBackButton), findsOneWidget);
    expect(find.byType(KuteBottomActionBar), findsNothing);
    expect(find.byKey(const ValueKey('dock-search-pill')), findsNothing);
    // The screen's own section pills; the page's venue pills stay under
    // it, offstage.
    expect(_sectionPills, findsNWidgets(3));
    expect(tester.widgetList<KutePill>(_sectionPills).map((p) => p.label), [
      l10n.portfolioSectionBalances,
      l10n.portfolioSectionPnlCharts,
      l10n.activity
    ]);
    expect(tester.widgetList<KutePill>(_sectionPills).map((p) => p.selected),
        [true, false, false]);
    expect(find.byType(KutePillTabs), findsNothing);
    await pickSection(tester, 'activity');
    expect(_sectionOn(tester), 'activity');
    expect(tester.widgetList<KutePill>(_sectionPills).map((p) => p.selected),
        [false, false, true]);

    // Back: the page, Investing still picked, no Portfolio left mounted.
    await closePortfolio(tester);
    expect(find.byType(KutePillTabs), findsWidgets);
    expect(tester.widget<KutePill>(_pill(l10n.trading)).selected, isTrue);
    expect(_container(tester).read(investmentsTabProvider),
        InvestmentsTab.investing);
    expect(find.byType(InvestmentsPortfolio, skipOffstage: false),
        findsNothing);
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
    expect(find.byType(PortfolioScreen), findsNothing);
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
    expect(find.byType(PortfolioScreen), findsNothing);
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
    expect(find.byType(PortfolioScreen), findsNothing);
    expect(events.where((e) => e.$1 == 'investments_balance_tapped'), isEmpty);
    // Still collapsed: the total is no way back up either (the chevron
    // is).
    expect(_compactTotal, findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'the two large pills share one row on a 375-wide phone, at their '
      'natural width, no label cut, the picked one reading its category',
      (tester) async {
    await pumpInvestments(tester, size: const Size(375, 812));
    final l10n = _l10n(tester);
    final strip = find.byType(KutePillTabs).first;
    expect(tester.widget<KutePillTabs>(strip).size, KutePillSize.large);
    final pills = find.descendant(
        of: strip, matching: find.byType(KutePill), skipOffstage: false);
    expect(pills, findsNWidgets(2));
    // Side by side on one line (the row scrolls sideways if the picked
    // pill's category makes it long), every label at its full width: the
    // name, then " · " and the category in the quieter weight on the
    // picked pill, in one line of text.
    final top = tester.getTopLeft(pills.at(0)).dy;
    for (var i = 0; i < 2; i++) {
      expect(tester.getTopLeft(pills.at(i)).dy, top);
      final pill = tester.widget<KutePill>(pills.at(i));
      final plain = pill.detail == null
          ? pill.label
          : '${pill.label} · ${pill.detail}';
      final text = tester.renderObject<RenderParagraph>(find.descendant(
          of: pills.at(i),
          matching: find.text(plain, skipOffstage: false)));
      expect(text.size.width,
          greaterThanOrEqualTo(text.getMaxIntrinsicWidth(double.infinity) - 0.5),
          reason: plain);
    }
    expect(tester.widget<KutePill>(pills.at(0)).detail, l10n.hlPillTrending);
    expect(find.text('${l10n.trading} · ${l10n.hlPillTrending}'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  for (final tab in _venuePills) {
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
      await _tapPill(tester, label);
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
      expect(find.text('${l10n.available} '), findsNothing);
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
