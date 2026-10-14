// The Investments tab (one balance): the spending account's top strip is
// Bitcoin | Investments, and Investments carries Investing · Predictions
// · Positions as pills over the embedded screens (each pill wearing a
// glyph of the one icon family, a step bigger than the Home strip), the
// one-balance hero above them (no title; the balance block opens the
// Portfolio full screen, as does the compact bar's total), and the
// Receive / Send / search dock with the search scoped to the pill. Receive (the dock's, no door under the
// hero any more) opens the Dollars receive screen on its coin step, whose
// "From your Bitcoin" row opens the Investments deposit sheet. No
// venue Deposit or Withdraw exists anywhere inside it.
// The whole page scrolls as one on every pill, and the chrome collapses:
// the hero leaves, the pills condense into the compact pinned bar with a
// small copy of the total and a chevron that brings everything back, as
// does scrolling to the very top.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/home/shell_wallet_screen.dart'
    show kShellTopBarSpacing;
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart'
    show KutePill, KutePillSize, KutePillTabs;
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import 'investments_harness.dart';

Finder _pill(String label) => investmentsPill(label);

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
      'three pills in order, Investing · Predictions · Positions, each '
      'wearing its glyph of the one icon family, a step bigger, over the '
      'embedded browsers', (tester) async {
    await pumpInvestments(tester, earn: kEarnOn);
    final l10n = _l10n(tester);
    final strip = _strip(tester);
    expect(strip.items.map((i) => i.label),
        [l10n.trading, l10n.predictions, l10n.ledgerPositionsTitle]);
    expect(strip.items.map((i) => i.label), ['Investing', 'Predictions',
        'Positions']);
    // No Portfolio pill any more: the balance opens the Portfolio.
    expect(_pill(l10n.walletPortfolioAction), findsNothing);
    // The rising trend and the ring the top tabs used, the pie the old
    // Portfolio pill wore; no venue logos.
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

    // Both venue browsers are mounted from the start, embedded; Positions
    // waits for its pill, and the Portfolio is a screen of its own.
    expect(tester.widget<HyperliquidScreen>(find.byType(HyperliquidScreen))
        .embedded, isTrue);
    expect(
        tester
            .widget<PolymarketScreen>(
                find.byType(PolymarketScreen, skipOffstage: false))
            .embedded,
        isTrue);
    expect(find.byType(OpenInvestmentsScreen, skipOffstage: false),
        findsNothing);
    expect(find.byType(PortfolioPositions, skipOffstage: false), findsNothing);

    // The one-balance hero, once, above the pills: no title, the total
    // alone over "Available $X · Invested $Y" and the chevron.
    final header =
        tester.widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader));
    expect(header.totalLabel, isNull);
    expect(find.text(l10n.investmentsTotal), findsNothing);
    expect(header.amountText, r'$25.00');
    expect(header.availableFirst, isTrue);
    expect(find.byKey(const ValueKey('investments-balance-chevron')),
        findsOneWidget);
    expect(
        tester
            .getTopLeft(find.text('${l10n.available} '))
            .dx,
        lessThan(tester.getTopLeft(find.text('${l10n.betInvested} ')).dx));
    expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('investments-balance-chevron')))
            .dx,
        greaterThan(tester.getTopLeft(find.text('${l10n.betInvested} ')).dx));
    expect(find.byType(InvestmentBalanceHeader), findsOneWidget);
    expect(tester.getTopLeft(find.byType(PoolBalanceHeader)).dy,
        lessThan(tester.getTopLeft(find.byType(KutePillTabs).first).dy));
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'no venue Deposit or Withdraw anywhere and no door under the hero; '
      'the way in is the dock\'s Receive, which opens the Dollars receive '
      'screen', (tester) async {
    final events = recordEvents();
    var receiveOpened = 0;
    UsdAccountActionBar.debugReceiveOpener = (_) => receiveOpened++;
    addTearDown(() => UsdAccountActionBar.debugReceiveOpener = null);
    await pumpInvestments(tester, earn: kEarnOn);
    final l10n = _l10n(tester);
    expect(find.byType(VenueDepositButton, skipOffstage: false), findsNothing);
    expect(find.byType(InvestmentActionBar, skipOffstage: false), findsNothing);
    expect(find.text(l10n.withdraw, skipOffstage: false), findsNothing);
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

    // The dock: Receive (the Bitcoin dock's label and arrow), Send, and
    // the search square. No Deposit.
    final bar =
        tester.widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
    expect(bar.actions.map((a) => a.label), [l10n.receive, l10n.send]);
    expect(bar.actions.map((a) => a.trackingId), ['receive', 'send']);
    expect(bar.actions.map((a) => a.icon),
        [Icons.south_west_rounded, Icons.north_east_rounded]);
    expect(bar.onSearch, isNotNull);
    expect(bar.source, 'usd');
    expect(find.text(l10n.receive), findsOneWidget);
    expect(find.text(l10n.deposit, skipOffstage: false), findsNothing);

    // Receive opens the Dollars receive screen, with the Bitcoin dock's
    // quick-action key under this surface and the dock as the receive
    // flow's entry source.
    await tester.tap(find.text(l10n.receive));
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
    // Positions searches this account's activity, as the old Portfolio
    // pill did.
    expect(UsdAccountActionBar.searchTarget(InvestmentsTab.positions),
        (category: null, source: 'usd'));
  });

  testWidgets(
      'a pill tap reports analytics_tab_selected and the venue open event, '
      'and Positions mounts the merged positions list', (tester) async {
    final events = recordEvents();
    await pumpInvestments(tester, earn: kEarnOn);
    final l10n = _l10n(tester);

    await tapPill(tester, l10n.predictions);
    expect(_container(tester).read(investmentsTabProvider),
        InvestmentsTab.predictions);
    expect(tester.widget<KutePill>(_pill(l10n.predictions)).selected, isTrue);
    expect(find.byType(PolymarketScreen), findsOneWidget);
    expect(
        events.where((e) => e.$1 == 'analytics_tab_selected').last.$2,
        {'tab': 'predictions', 'from_tab': 'investing', 'surface': 'investments'});
    expect(events.any((e) => e.$1 == 'polymarket_tab_opened'), isTrue);
    expect(events.any((e) => e.$1 == 'hyperliquid_tab_opened'), isFalse);

    // Re-tapping the pill on screen is not a new view.
    final before = events.length;
    await tapPill(tester, l10n.predictions);
    expect(events.length, before);

    await tapPill(tester, l10n.ledgerPositionsTitle);
    expect(find.byType(PortfolioPositions), findsOneWidget);
    // Nothing held, nothing resting: the Sal empty state.
    expect(find.text('No positions yet'), findsOneWidget);
    // Positions is a list under the pills, not the Portfolio screen: no
    // tabs of its own, no app bar, no back button.
    expect(find.byType(OpenInvestmentsScreen), findsNothing);
    expect(find.byType(KuteBackButton), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(events.where((e) => e.$1 == 'portfolio_opened'), isEmpty);
    expect(
        events.where((e) => e.$1 == 'analytics_tab_selected').last.$2,
        {'tab': 'positions', 'from_tab': 'predictions', 'surface': 'investments'});

    await tapPill(tester, l10n.trading);
    expect(events.any((e) => e.$1 == 'hyperliquid_tab_opened'), isTrue);
    expect(find.byType(HyperliquidScreen), findsOneWidget);
    // Positions keeps its state behind the stack: one mount.
    expect(find.byType(PortfolioPositions, skipOffstage: false),
        findsOneWidget);
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
      expect(investmentsLinkOpensPortfolio(tab.key), isFalse);
    }
    expect(InvestmentsTab.fromKey(null), isNull);
    expect(InvestmentsTab.fromKey('deposit'), isNull);
    // The old Earn pill's link lands on the first pill, never a blank.
    expect(InvestmentsTab.fromKey('earn'), isNull);
    // The old Portfolio links: the pill and its Open and Orders tabs are
    // Positions; Activity and Statistics open the Portfolio screen.
    for (final key in ['portfolio', 'open', 'orders']) {
      expect(InvestmentsTab.fromKey(key), InvestmentsTab.positions,
          reason: key);
      expect(investmentsLinkOpensPortfolio(key), isFalse, reason: key);
    }
    for (final key in ['activity', 'statistics']) {
      expect(InvestmentsTab.fromKey(key), isNull, reason: key);
      expect(investmentsLinkOpensPortfolio(key), isTrue, reason: key);
    }
  });

  testWidgets(
      'a link to the old Activity or Statistics tab opens the Portfolio '
      'screen over the tab', (tester) async {
    final events = recordEvents();
    await pumpInvestments(tester,
        child: const UsdAccountScreen(openPortfolio: true));
    await _pumpFrames(tester, 6);
    expect(find.byType(OpenInvestmentsScreen), findsOneWidget);
    expect(events.where((e) => e.$1 == 'portfolio_opened').single.$2,
        {'source': 'link'});
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'the balance block opens the Portfolio full screen, with its back; '
      'investments_balance_tapped reports the state', (tester) async {
    final events = recordEvents();
    await pumpInvestments(tester);
    expect(find.byType(OpenInvestmentsScreen), findsNothing);
    // The big number is part of the tap, not only the line under it.
    await tester.tap(find
        .descendant(
            of: find.byType(PoolBalanceHeader),
            matching: find.byType(RollingNumberText))
        .first);
    await _pumpFrames(tester, 6);
    expect(find.byType(OpenInvestmentsScreen), findsOneWidget);
    expect(find.byType(KuteBackButton), findsOneWidget);
    expect(events.where((e) => e.$1 == 'investments_balance_tapped').single.$2,
        {'state': 'normal', 'collapsed': false});
    expect(events.where((e) => e.$1 == 'portfolio_opened').single.$2,
        {'source': 'investments_balance'});
    // Back (a plain pop here: the harness has no router) returns to the
    // tab.
    Navigator.of(tester.element(find.byType(OpenInvestmentsScreen))).pop();
    await _pumpFrames(tester, 6);
    expect(find.byType(OpenInvestmentsScreen), findsNothing);
    expect(find.byType(InvestmentsBody), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'with money on a rail the in-flight lines replace the split and are '
      'still the door to the Portfolio', (tester) async {
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
                  usd: 5),
            ]));
    final l10n = _l10n(tester);
    expect(find.textContaining(l10n.available), findsNothing);
    expect(find.byKey(const ValueKey('investments-balance-chevron')),
        findsOneWidget);
    await tester.tap(find.text(r'$5.00 moving to Predictions'));
    await _pumpFrames(tester, 6);
    expect(find.byType(OpenInvestmentsScreen), findsOneWidget);
    expect(events.where((e) => e.$1 == 'investments_balance_tapped').single.$2,
        {'state': 'in_flight', 'collapsed': false});
    expect(events.where((e) => e.$1 == 'activity_history_opened'), isEmpty);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets("collapsed, the compact bar's total opens the Portfolio",
      (tester) async {
    final events = recordEvents();
    await pumpInvestments(tester);
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -400));
    await _pumpFrames(tester);
    expect(_compactTotal, findsOneWidget);
    await tester.tap(_compactTotal);
    await _pumpFrames(tester, 6);
    expect(find.byType(OpenInvestmentsScreen), findsOneWidget);
    expect(events.where((e) => e.$1 == 'investments_balance_tapped').single.$2,
        {'state': 'normal', 'collapsed': true});
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
        InvestmentsTab.positions => l10n.ledgerPositionsTitle,
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
    final gesture = await tester.startGesture(
        tester.getCenter(find.byType(NestedScrollView)));
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
    final bar = find.ancestor(of: _compactTotal, matching: find.byType(Opacity));
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
