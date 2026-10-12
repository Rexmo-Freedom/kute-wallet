// The Investments tab (one balance): the spending account's top strip is
// Bitcoin | Investments, and Investments carries Investing · Predictions
// · Portfolio as pills over the embedded screens (each pill wearing a
// glyph of the one icon family, a step bigger than the Home strip), the
// one-balance hero above them, and the Deposit / Send / search dock with
// the search scoped to the pill. Deposit (the dock's, no door under the
// hero any more) opens the Investments deposit sheet; Receive lives in
// that sheet. No venue Deposit or Withdraw exists anywhere inside it.
// The whole page scrolls as one on every pill, and the chrome collapses:
// the hero leaves, the pills condense into the compact pinned bar with a
// small copy of the total and a chevron that brings everything back, as
// does scrolling to the very top.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show MoveLockedSide;
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
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
import 'package:kute/screens/shared/portfolio_tabs.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart';
import 'package:kute/screens/usd/components/usd_earn_chart.dart';
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
      'three pills in order, Investing first, each wearing its glyph of '
      'the one icon family, a step bigger, over the embedded browsers',
      (tester) async {
    await pumpInvestments(tester, earn: kEarnOn);
    final l10n = _l10n(tester);
    final strip = _strip(tester);
    expect(strip.items.map((i) => i.label),
        [l10n.trading, l10n.predictions, l10n.walletPortfolioAction]);
    // The rising trend and the ring the top tabs used, the pie the
    // Portfolio's dock action wears; no venue logos.
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
    // Earn is no pill here, whatever the capability says: it lives under
    // Portfolio › Statistics.
    expect(_pill(l10n.usdEarnTitle), findsNothing);
    expect(find.byType(UsdEarnChart, skipOffstage: false), findsNothing);

    // Both venue browsers are mounted from the start, embedded; the
    // Portfolio waits for its pill.
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

    // The one-balance hero, once, above the pills.
    final header =
        tester.widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader));
    expect(header.totalLabel, l10n.investmentsTotal);
    expect(header.amountText, r'$25.00');
    expect(find.byType(InvestmentBalanceHeader), findsOneWidget);
    expect(tester.getTopLeft(find.byType(PoolBalanceHeader)).dy,
        lessThan(tester.getTopLeft(find.byType(KutePillTabs).first).dy));
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'no venue Deposit or Withdraw anywhere and no door under the hero; '
      'the one way in is the dock\'s Deposit, which opens the Investments '
      'deposit sheet', (tester) async {
    final events = recordEvents();
    final opened = <MoveLockedSide>[];
    UsdAccountActionBar.debugDepositSheetOpener =
        (_, {required lockedSide}) async => opened.add(lockedSide);
    addTearDown(() => UsdAccountActionBar.debugDepositSheetOpener = null);
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

    // The dock: Deposit, Send, and the search square. No Receive: it is
    // the deposit sheet's first option.
    final bar =
        tester.widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
    expect(bar.actions.map((a) => a.label), [l10n.deposit, l10n.send]);
    expect(bar.actions.map((a) => a.trackingId), ['dollar_deposit', 'send']);
    expect(bar.actions.map((a) => a.icon),
        [Icons.south_west_rounded, Icons.north_east_rounded]);
    expect(bar.onSearch, isNotNull);
    expect(bar.source, 'usd');
    expect(find.text(l10n.deposit), findsOneWidget);
    expect(find.text(l10n.receive, skipOffstage: false), findsNothing);

    // Deposit opens the Dollars deposit door (destination pinned), with
    // the door's own quick-action event and the dock as the move's
    // entry source.
    await tester.tap(find.text(l10n.deposit));
    await tester.pump();
    expect(opened, [MoveLockedSide.depositToUsd]);
    expect(events.where((e) => e.$1 == 'quick_action_tapped').single.$2,
        {'action': 'dollar_deposit', 'source': 'usd'});
    expect(TrackingService.takeEntrySource('move'), 'usd_dock');
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  test('the search square follows the pill', () {
    expect(UsdAccountActionBar.searchTarget(InvestmentsTab.investing),
        (category: SearchCategory.perpetuals, source: 'trading'));
    expect(UsdAccountActionBar.searchTarget(InvestmentsTab.predictions),
        (category: SearchCategory.predictions, source: 'predictions'));
    // Portfolio searches this account's activity, as before.
    expect(UsdAccountActionBar.searchTarget(InvestmentsTab.portfolio),
        (category: null, source: 'usd'));
  });

  testWidgets(
      'a pill tap reports analytics_tab_selected and the venue open event, '
      'and Portfolio mounts the one Portfolio screen embedded',
      (tester) async {
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

    await tapPill(tester, l10n.walletPortfolioAction);
    final portfolio = tester
        .widget<OpenInvestmentsScreen>(find.byType(OpenInvestmentsScreen));
    expect(portfolio.embedded, isTrue);
    expect(portfolio.source, 'investments_tab');
    // The same strip, no app bar and no back button: the pills navigate.
    expect(find.byType(PortfolioTabs), findsOneWidget);
    expect(find.byType(KuteBackButton), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    // No third row: the Open tab is the one list.
    expect(find.byKey(const ValueKey('portfolio-filter-all')), findsNothing);
    expect(
        events.where((e) => e.$1 == 'portfolio_opened').single.$2,
        {'source': 'investments_tab', 'tab': 'open'});
    expect(
        events.where((e) => e.$1 == 'analytics_tab_selected').last.$2,
        {'tab': 'portfolio', 'from_tab': 'predictions', 'surface': 'investments'});

    await tapPill(tester, l10n.trading);
    expect(events.any((e) => e.$1 == 'hyperliquid_tab_opened'), isTrue);
    expect(find.byType(HyperliquidScreen), findsOneWidget);
    // The Portfolio keeps its state behind the stack: one mount, one
    // portfolio_opened.
    expect(find.byType(OpenInvestmentsScreen, skipOffstage: false),
        findsOneWidget);
    expect(events.where((e) => e.$1 == 'portfolio_opened'), hasLength(1));
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
        ['investing', 'predictions', 'portfolio']);
    for (final tab in InvestmentsTab.values) {
      expect(InvestmentsTab.fromKey(tab.key), tab);
      expect(investmentsTabLocation(tab), '/usd?tab=${tab.key}');
    }
    expect(InvestmentsTab.fromKey(null), isNull);
    expect(InvestmentsTab.fromKey('deposit'), isNull);
    // The old Earn pill's link lands on the first pill, never a blank.
    expect(InvestmentsTab.fromKey('earn'), isNull);
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
        InvestmentsTab.portfolio => l10n.walletPortfolioAction,
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
