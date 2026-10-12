// The Investments tab (one balance): the spending account's top strip is
// Bitcoin | Investments, and Investments carries Investing · Predictions
// · Portfolio as pills over the embedded screens (the two venue pills
// wearing the venues' own marks), the one-balance hero above them, the
// Investments deposit door (the dollar coin) under the hero, and the
// Receive / Send / search dock with the search scoped to the pill. No
// venue Deposit or Withdraw exists anywhere inside it. The whole page
// scrolls as one on every pill: the hero, the door and the pills scroll
// away with the content, the pills pinning at the top.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/asset_icon_provider.dart' show kUsdMarkAsset;
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart'
    show KutePill, KutePillTabs;
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/shared/portfolio_tabs.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart';
import 'package:kute/screens/usd/components/usd_earn_chart.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';

import 'investments_harness.dart';

Finder _pill(String label) => investmentsPill(label);

AppLocalizations _l10n(WidgetTester tester) =>
    tester.element(find.byType(InvestmentsBody)).l10n;

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(InvestmentsBody)));

/// The asset an SVG mark was loaded from.
String? _markAsset(Widget? leading) =>
    leading is SvgPicture && leading.bytesLoader is SvgAssetLoader
        ? (leading.bytesLoader as SvgAssetLoader).assetName
        : null;

Future<void> _pumpFrames(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'three pills in order, Investing first, the venue pills wearing the '
      'venues\' marks, over the embedded browsers', (tester) async {
    await pumpInvestments(tester, earn: kEarnOn);
    final l10n = _l10n(tester);
    final strip = tester.widget<KutePillTabs>(find.byType(KutePillTabs).first);
    expect(strip.items.map((i) => i.label),
        [l10n.trading, l10n.predictions, l10n.walletPortfolioAction]);
    // The Hyperliquid and Polymarket logos on their pills (the marks the
    // hub's wallet rows draw), nothing on Portfolio; no glyphs.
    expect(_markAsset(strip.items[0].leading), kInvestingMarkAsset);
    expect(_markAsset(strip.items[1].leading), kPredictionsMarkAsset);
    expect(strip.items[2].leading, isNull);
    expect(strip.items.map((i) => i.icon), everyElement(isNull));
    for (final label in strip.items.map((i) => i.label)) {
      expect(_pill(label), findsOneWidget, reason: label);
    }
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
      'no venue Deposit or Withdraw anywhere; the one door is the '
      'Investments deposit with the dollar coin', (tester) async {
    await pumpInvestments(tester, earn: kEarnOn);
    final l10n = _l10n(tester);
    expect(find.byType(VenueDepositButton, skipOffstage: false), findsNothing);
    expect(find.byType(InvestmentActionBar, skipOffstage: false), findsNothing);
    expect(find.text(l10n.withdraw, skipOffstage: false), findsNothing);
    expect(find.text(l10n.deposit, skipOffstage: false), findsNothing);
    expect(find.textContaining('Investing deposit', skipOffstage: false),
        findsNothing);
    expect(find.textContaining('Predictions deposit', skipOffstage: false),
        findsNothing);
    // The deposit door into Dollars, with the dollar coin it always wore
    // (the Investments arrow stays on the Move sheet's rows).
    expect(find.text(l10n.dollarDeposit), findsOneWidget);
    final door = tester.widget<AppButton>(
        find.widgetWithText(AppButton, l10n.dollarDeposit));
    expect(door.svgAsset, kUsdMarkAsset);
    expect(door.icon, isNull);

    // The dock: Receive, Send, and the search square.
    final bar =
        tester.widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
    expect(bar.actions.map((a) => a.label), [l10n.receive, l10n.send]);
    expect(bar.actions.map((a) => a.trackingId), ['receive', 'send']);
    expect(bar.onSearch, isNotNull);
    expect(bar.source, 'usd');
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
    expect(find.byKey(const ValueKey('portfolio-filter-all')), findsOneWidget);
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

  for (final tab in InvestmentsTab.values) {
    testWidgets(
        'on ${tab.key}: the whole page scrolls as one — the hero and the '
        'door scroll away, the pills pin, the nav bar hides; the pull '
        'refreshes', (tester) async {
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
      expect(find.text(l10n.dollarDeposit), findsOneWidget);
      final pillsTop = tester.getTopLeft(find.byType(KutePillTabs).first).dy;
      expect(container.read(navBarHiddenProvider), isFalse);

      // Scroll the content: the hero and the door leave, the pills stay
      // at the top of the page, the nav bar hides.
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -400));
      await _pumpFrames(tester);
      expect(find.byType(PoolBalanceHeader), findsNothing);
      expect(find.text(l10n.dollarDeposit), findsNothing);
      expect(_pill(label), findsOneWidget);
      expect(tester.widget<KutePill>(_pill(label)).selected, isTrue);
      expect(tester.getTopLeft(find.byType(KutePillTabs).first).dy,
          lessThan(pillsTop));
      expect(container.read(navBarHiddenProvider), isTrue);

      // Back to the top: everything returns, and so does the nav bar.
      await tester.drag(find.byType(NestedScrollView), const Offset(0, 400));
      await _pumpFrames(tester);
      expect(find.byType(PoolBalanceHeader), findsOneWidget);
      expect(find.text(l10n.dollarDeposit), findsOneWidget);
      expect(tester.getTopLeft(find.byType(KutePillTabs).first).dy, pillsTop);
      expect(container.read(navBarHiddenProvider), isFalse);

      // Pull past the top: the page's one refresh indicator.
      await tester.drag(find.byType(NestedScrollView), const Offset(0, 300));
      await tester.pump();
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      await _pumpFrames(tester, 15);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  }
}
