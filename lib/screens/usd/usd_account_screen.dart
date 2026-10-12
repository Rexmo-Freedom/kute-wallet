// lib/screens/usd/usd_account_screen.dart
//
// The Investments tab of the spending account (one balance, October
// 2026). Dollars is the only balance: Predictions (Polymarket) and
// Investing (Hyperliquid) are places money flows through for an order,
// not places it sits, so the strip no longer gives them tabs of their
// own. The top of the app is Bitcoin | Investments, and this screen holds
// everything the dollars do:
//
//   * the shared hero, [InvestmentBalanceHeader] in its one-balance mode:
//     the total (dollars plus the venues' open positions) over an
//     Available / Invested split, and, while anything is on a rail, the
//     in-flight lines in that split's place ("$5.00 moving to
//     Predictions", "$12.40 coming back from Investing", "Incoming
//     $20.00", "$0.60 unavailable until balancing completes"), so money in flight is never
//     hidden;
//   * one pill row under it, Investing · Predictions · Portfolio, the
//     same pills the Home strip uses a step bigger ([KutePillSize.large]),
//     each wearing a glyph of the one icon family the top tabs used
//     (rising trend, ring, pie), over an IndexedStack of the existing
//     screens in their embedded shape: the Hyperliquid and Polymarket
//     browsers with their own hero and dock taken out, and the one
//     Portfolio screen exactly as it is pushed (same tabs and
//     drill-down). Earn is a section of the Portfolio's Statistics tab
//     (open_investments_screen.dart), no longer a pill here;
//   * the dock — Deposit on the left, Send on the right, search in the
//     square — with the search scoped to the pill on screen: the venue's
//     own markets on Investing and Predictions, this account's activity
//     on Portfolio. Deposit is the ONE way to fund this balance (owner
//     decision, October 2026: the full-width door under the hero is
//     gone, the dock carries it): it opens the Investments deposit sheet,
//     whose From picker leads with Receive — the Dollars receive screen
//     the dock's own Receive used to open — over Bitcoin and Cash App.
//
// THE WHOLE PAGE SCROLLS AS ONE, on every pill, AND THE CHROME COLLAPSES
// (owner decision October 2026: "Investing and Predictions become the
// main thing"). The hero and the pills are ONE pinned
// [SliverPersistentHeader] of a [NestedScrollView]; the pill on screen is
// its body, and each embedded screen's own list scrolls inside it
// through the primary scroll controller. Scrolling down shrinks the
// header from its expanded height (measured from the hero and the large
// pills, so the in-flight lines never clip) to a compact
// pinned bar ([_InvestmentsCompactBar]): a small copy of the total over
// the same pills a step smaller, the one on screen highlighted, and a
// chevron at its right end. The total scales down and fades as it
// leaves, the bar fades in; a scroll that stops in between snaps to the
// nearer state. Scrolling back to the very top, or tapping the chevron
// (which scrolls there), expands everything again. Under Reduce Motion
// the two states switch at once, with no blend and no scroll animation.
// The bar never carries the hero's second line: the in-flight note is
// read in the expanded header. Pull-to-refresh is the page's one
// [RefreshIndicator] over the pill on screen, and the top nav bar's
// hide-on-scroll is driven from the page's scroll notifications, so the
// embedded screens carry neither.
//
// NO VENUE DEPOSIT OR WITHDRAW. Money only reaches a venue through an
// order funded from Dollars, and comes back on its own; the venue
// browsers mount with no funding doors, and the dock carries none.
//
// The Portfolio mounts on its first tap (`portfolio_opened` is a view,
// not a mount); the two venue browsers are mounted from the start, the
// way their shell branches were, so the Investing screen's session-long
// side-cars (the deposit→order auto-fire watcher, the user-events
// socket) keep running from app start.
//
// THE PILL IS SHARED STATE ([investmentsTabProvider]) so a deep link, a
// placed bet or Sal can open a pill from anywhere: `/hyperliquid` and
// `/polymarket` redirect here with `?tab=investing|predictions`
// ([investmentsTabLocation]), and the dock's Portfolio action on a venue
// screen switches the pill instead of pushing.
//
// Receive (the deposit sheet's first option) opens the coin picker off
// the Orchestra route list, pointed at this balance: whatever coin the
// money arrives in, dollars land. Send is its own screen
// (usd_send_screen.dart), pointed the other way. A Ledger
// account is not part of this: it keeps its own Investing and Predictions
// tabs of the strip, with its own screens, buttons and layout.
//
// The tab only ever renders for the spending account (see
// `shellShowsUsdTab` in shell_venue_tabs.dart) — a Bitcoin-only,
// watch-only, tracked, signer or Ledger account has no dollars.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAccountProvider;
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidUserFillsProvider;
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show showDepositSheet, MoveLockedSide;
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart';
import 'package:kute/screens/home/shell_wallet_screen.dart'
    show kShellTopBarSpacing;
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/kute_motion.dart' show kuteReduceMotion;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/usd/usd_send_screen.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Source key for every event this surface emits.
const String kUsdSurfaceSource = 'usd';

/// Where the deposit sheet is opened from when the dock's Deposit opens
/// it: the move flow's `entry_source`.
const String kUsdDockSource = 'usd_dock';

/// The compact pinned bar's height, in design units: the small total line
/// over the compact pills, with the bar's own air.
const double kInvestmentsCompactBarHeight = 6 + 20 + 6 + 28 + 8;

/// The expanded header's height until its first layout reports the real
/// one (design units): the hero with its split line and the large pills.
const double _kExpandedHeaderEstimate = 158;

/// The Investments pills, in strip order. [key] is the analytics value
/// and the `?tab=` query value, fixed English so a pill reads the same in
/// PostHog and in a link in every app language. [icon] is the pill's
/// glyph: the one icon family the top tabs used (rising trend, ring) and
/// the pie the Portfolio's dock action wears.
enum InvestmentsTab {
  investing('investing', Icons.trending_up_rounded),
  predictions('predictions', Icons.donut_large_rounded),
  portfolio('portfolio', Icons.pie_chart_rounded);

  const InvestmentsTab(this.key, this.icon);

  final String key;
  final IconData icon;

  /// The pill a link names, or null for an unknown or missing key (the
  /// old `earn` pill among them: Earn lives under Portfolio › Statistics).
  static InvestmentsTab? fromKey(String? key) {
    for (final tab in values) {
      if (tab.key == key) return tab;
    }
    return null;
  }
}

/// The pill on screen. Shared so a deep link, a placed bet or Sal can
/// open a pill from outside the screen; the screen writes it on a tap.
final investmentsTabProvider =
    StateProvider<InvestmentsTab>((_) => InvestmentsTab.investing);

/// The `/usd` location that opens on [tab]: what the venue routes
/// redirect to for the spending account.
String investmentsTabLocation(InvestmentsTab tab) => '/usd?tab=${tab.key}';

/// Shell branch: the spending account's Investments. Same chrome as the
/// other tab pages — screen gradient, the floating nav bar's room at the
/// top, the shared money dock at the bottom.
///
/// [initialTab] is the pill a link asked for (`/usd?tab=…`); null leaves
/// the pill where it was. Applied on mount and again whenever a new link
/// lands on the branch (the page is updated in place, never remounted).
///
/// The backup banner [ShellWalletScreen] carries above its body is
/// deliberately not repeated here: this IS the spending account, and Home
/// already shows that account its card.
class UsdAccountScreen extends ConsumerStatefulWidget {
  const UsdAccountScreen({super.key, this.initialTab});

  final InvestmentsTab? initialTab;

  @override
  ConsumerState<UsdAccountScreen> createState() => _UsdAccountScreenState();
}

class _UsdAccountScreenState extends ConsumerState<UsdAccountScreen> {
  @override
  void initState() {
    super.initState();
    _applyLinkedTab();
  }

  @override
  void didUpdateWidget(covariant UsdAccountScreen old) {
    super.didUpdateWidget(old);
    if (old.initialTab != widget.initialTab) _applyLinkedTab();
  }

  /// Post-frame: provider writes are illegal while the tree is building.
  void _applyLinkedTab() {
    final tab = widget.initialTab;
    if (tab == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(investmentsTabProvider.notifier).state = tab;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.screenGradient(context),
      child: KuteDockHost(
        dockBuilder: (onHeightChanged) =>
            UsdAccountActionBar(onHeightChanged: onHeightChanged),
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The floating nav bar's room stays put, so the pinned
              // pills never slide under the bar when it reappears.
              SizedBox(height: kShellTopBarSpacing.h),
              const Expanded(child: InvestmentsBody()),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero and the pill row as the page's header slivers; the pill's
/// screen as its body (see the file header).
class InvestmentsBody extends ConsumerStatefulWidget {
  const InvestmentsBody({super.key});

  @override
  ConsumerState<InvestmentsBody> createState() => _InvestmentsBodyState();
}

class _InvestmentsBodyState extends ConsumerState<InvestmentsBody> {
  /// The pills opened at least once: the Portfolio mounts on its first
  /// tap and stays mounted after (the venue browsers are always mounted,
  /// see the file header).
  final Set<InvestmentsTab> _opened = {};

  /// The outer (header) scroll: the collapse, the chevron's way back up
  /// and the nav bar's "near the top" reveal all read it.
  final ScrollController _outer = ScrollController();

  /// Accumulated same-direction travel, feeding the nav-bar hide/reveal
  /// hysteresis below (the venue screens' own rule, run once here for
  /// every pill).
  double _navAccum = 0;

  /// The expanded header's height as its last layout measured it (the
  /// hero with whatever lines it carries and the large pills); zero
  /// until the first layout. The collapse runs over this minus the
  /// compact bar.
  double _expandedExtent = 0;

  /// The collapse's travel, as the last build sized it: the outer scroll
  /// offset at which the header is the compact bar.
  double _collapseRange = 0;

  @override
  void dispose() {
    _outer.dispose();
    super.dispose();
  }

  /// The expanded header's layout reported its height (post-frame, see
  /// [_MeasureHeight]): a different one resizes the sliver.
  void _onExpandedHeight(double height) {
    if (!mounted || (height - _expandedExtent).abs() < 0.5) return;
    setState(() => _expandedExtent = height);
  }

  /// Scrolls the page to the very top: the one state in which the whole
  /// header is on screen. Under Reduce Motion it jumps.
  void _expand() {
    if (!_outer.hasClients) return;
    HapticFeedback.selectionClick();
    if (kuteReduceMotion(context)) {
      _outer.jumpTo(0);
    } else {
      _outer.animateTo(0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic);
    }
  }

  /// A scroll that stops with the header between its two states finishes
  /// the collapse, or undoes it, towards the nearer one: the header is the
  /// hero or the compact bar, never a blend left on screen. Run after the
  /// scroll's own end notification, never from inside it.
  void _snap() {
    if (!mounted || !_outer.hasClients) return;
    final range = _collapseRange;
    final pixels = _outer.position.pixels;
    if (range <= 0 || pixels <= 0 || pixels >= range) return;
    final target = pixels < range / 2 ? 0.0 : range;
    if (kuteReduceMotion(context)) {
      _outer.jumpTo(target);
    } else {
      _outer.animateTo(target,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  void _pick(InvestmentsTab next) {
    final current = ref.read(investmentsTabProvider);
    if (next == current) return;
    HapticFeedback.selectionClick();
    // The strip's own event, as the Home pills and the old Balance | Earn
    // pair reported, so the existing tiles keep counting.
    TrackingService.track('analytics_tab_selected', params: {
      'tab': next.key,
      'from_tab': current.key,
      'surface': 'investments',
    });
    // The venue tabs' own open events, from the pills that open them now.
    switch (next) {
      case InvestmentsTab.investing:
        TrackingService.hyperliquidTabOpened();
      case InvestmentsTab.predictions:
        TrackingService.polymarketTabOpened();
      case InvestmentsTab.portfolio:
        break;
    }
    ref.read(investmentsTabProvider.notifier).state = next;
  }

  /// Whether [notification] comes from the pill on screen (or the page
  /// itself) rather than from a pill kept mounted behind the stack,
  /// whose list the nested scroll drags along: every pill is wrapped in
  /// a [TickerMode] that is on for the selected one only.
  static bool _fromVisiblePill(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final context = notification.context;
    return context == null || TickerMode.valuesOf(context).enabled;
  }

  /// Drive the persistent shell nav bar's hide/reveal from the page's
  /// scroll, whichever pill is scrolling. Reveal near the very top of the
  /// page; otherwise only toggle after ~12px of travel in one direction
  /// (hysteresis), the rule the venue screens used on their own lists.
  /// The outer scroll's end is also where the header snaps.
  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollEndNotification && notification.depth == 0) {
      Future<void>.microtask(_snap);
      return false;
    }
    if (notification is! ScrollUpdateNotification ||
        !_fromVisiblePill(notification)) {
      return false;
    }
    void setHidden(bool v) {
      if (ref.read(navBarHiddenProvider) != v) {
        ref.read(navBarHiddenProvider.notifier).state = v;
      }
    }

    final outerPixels = _outer.hasClients ? _outer.position.pixels : 0.0;
    if (outerPixels <= 24 && notification.metrics.pixels <= 24) {
      _navAccum = 0;
      setHidden(false);
      return false;
    }
    // Ignore the bounce region — overscroll rebound reads as a direction
    // flip and used to blink the bar.
    if (notification.metrics.outOfRange) return false;
    final delta = notification.scrollDelta ?? 0;
    if ((delta > 0 && _navAccum < 0) || (delta < 0 && _navAccum > 0)) {
      _navAccum = 0;
    }
    _navAccum += delta;
    if (_navAccum > 12) {
      setHidden(true);
    } else if (_navAccum < -12) {
      setHidden(false);
    }
    return false;
  }

  /// Pull-to-refresh: the pill on screen reads again, exactly what its
  /// own indicator used to do.
  Future<void> _refresh() async {
    final tab = ref.read(investmentsTabProvider);
    // Same event the Dollars screen sent before one balance (screen kept
    // as 'usd' for continuity), now with the pill that was refreshed.
    TrackingService.track('pull_to_refresh_executed',
        params: {'screen': 'usd', 'tab': tab.key});
    switch (tab) {
      case InvestmentsTab.investing:
        await HyperliquidScreen.refresh(ref.invalidate);
      case InvestmentsTab.predictions:
        await PolymarketScreen.refresh(ref);
      case InvestmentsTab.portfolio:
        ref.invalidate(hyperliquidAccountProvider);
        ref.invalidate(hyperliquidUserFillsProvider);
        ref.invalidate(polymarketTradingProvider);
        await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = ref.watch(investmentsTabProvider);
    _opened.add(selected);
    const tabs = InvestmentsTab.values;

    KutePillItem item(InvestmentsTab tab) => KutePillItem(
          label: switch (tab) {
            InvestmentsTab.investing => l10n.trading,
            InvestmentsTab.predictions => l10n.predictions,
            InvestmentsTab.portfolio => l10n.walletPortfolioAction,
          },
          icon: tab.icon,
        );

    final compactExtent = kInvestmentsCompactBarHeight.h;
    final expandedExtent = math.max(
        _expandedExtent > 0 ? _expandedExtent : _kExpandedHeaderEstimate.h,
        compactExtent);
    _collapseRange = expandedExtent - compactExtent;

    final c = context.colors;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: c.textPrimary,
        backgroundColor: c.surface,
        // The pull lands on the pill's own list (the nested scroll hands
        // the overscroll to the inner lists, every mounted one of them),
        // so the page listens to the visible pill's list, not to the
        // header, and not to the pills kept mounted behind the stack.
        notificationPredicate: (n) => n.depth > 0 && _fromVisiblePill(n),
        child: NestedScrollView(
          controller: _outer,
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          headerSliverBuilder: (context, _) => [
            // The hero and the pills as one collapsing header (see the
            // file header), pinned as the compact bar.
            SliverPersistentHeader(
              pinned: true,
              delegate: _InvestmentsHeaderDelegate(
                items: [for (final tab in tabs) item(tab)],
                selectedIndex: tabs.indexOf(selected),
                onTap: (i) => _pick(tabs[i]),
                onExpand: _expand,
                onExpandedHeight: _onExpandedHeight,
                figure: InvestmentBalanceHeader.oneBalanceFigure(ref),
                expandedExtent: expandedExtent,
                compactExtent: compactExtent,
                background: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
          ],
          body: IndexedStack(
            index: tabs.indexOf(selected),
            // Every pill keeps its state; only the one on screen ticks.
            children: [
              for (final tab in tabs)
                TickerMode(
                  enabled: tab == selected,
                  child: switch (tab) {
                    InvestmentsTab.investing =>
                      const HyperliquidScreen(embedded: true),
                    InvestmentsTab.predictions =>
                      const PolymarketScreen(embedded: true),
                    InvestmentsTab.portfolio => _opened.contains(tab)
                        ? const OpenInvestmentsScreen(
                            source: 'investments_tab', embedded: true)
                        : const SizedBox.shrink(),
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The collapsing header (see the file header): the hero and the large
/// pills at [expandedExtent], the compact bar at
/// [compactExtent], and the blend between them driven by the shrink
/// offset. The strip's own background, so the list frosts under nothing.
///
/// The expanded chrome is bottom-aligned in the shrinking box and
/// clipped, so it scrolls away the way it always did (the hero first,
/// the pills last) while it fades and the hero scales down; the compact
/// bar sits at the top and fades in. Whichever is under half way is the
/// one that takes taps and reads to assistive tech; the other is
/// offstage, with its state kept. The expanded chrome is laid out at its
/// own height whatever the box's, and reports that height
/// ([onExpandedHeight]) so the sliver's extent follows the hero's lines.
class _InvestmentsHeaderDelegate extends SliverPersistentHeaderDelegate {
  _InvestmentsHeaderDelegate({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    required this.onExpand,
    required this.onExpandedHeight,
    required this.figure,
    required this.expandedExtent,
    required this.compactExtent,
    required this.background,
  });

  final List<KutePillItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onExpand;
  final ValueChanged<double> onExpandedHeight;

  /// The total as the hero prints it, for the compact bar.
  final ({String text, bool stale}) figure;
  final double expandedExtent;
  final double compactExtent;
  final Color background;

  @override
  double get minExtent => compactExtent;
  @override
  double get maxExtent => math.max(expandedExtent, compactExtent);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final range = maxExtent - minExtent;
    var t = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    // Reduce Motion: the two states, nothing in between.
    if (kuteReduceMotion(context)) t = t < 0.5 ? 0.0 : 1.0;
    final expandedOn = t < 0.5;

    final expanded = Positioned.fill(
      child: Offstage(
        offstage: t >= 1,
        child: IgnorePointer(
          ignoring: !expandedOn,
          child: ExcludeSemantics(
            excluding: !expandedOn,
            child: OverflowBox(
              alignment: Alignment.bottomCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Opacity(
                opacity: 1 - t,
                child: _MeasureHeight(
                  onHeight: onExpandedHeight,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The total scales down towards the compact line's
                      // corner as it leaves.
                      Transform.scale(
                        scale: 1 - 0.6 * t,
                        alignment: Alignment.topLeft,
                        child: const InvestmentBalanceHeader(
                          product: InvestmentsProduct.trading,
                          oneBalance: true,
                        ),
                      ),
                      // The Home strip's pills, a step bigger, on the
                      // strip's inset with 12.h of air above (where the
                      // deposit door used to sit) and under them.
                      Padding(
                        padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 12.h),
                        child: KutePillTabs(
                          items: items,
                          selectedIndex: selectedIndex,
                          onTap: onTap,
                          size: KutePillSize.large,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final compact = Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: compactExtent,
      child: Offstage(
        offstage: t <= 0,
        child: IgnorePointer(
          ignoring: expandedOn,
          child: ExcludeSemantics(
            excluding: expandedOn,
            child: Opacity(
              opacity: t,
              child: _InvestmentsCompactBar(
                items: items,
                selectedIndex: selectedIndex,
                onTap: onTap,
                onExpand: onExpand,
                figure: figure,
              ),
            ),
          ),
        ),
      ),
    );

    return ColoredBox(
      color: background,
      child: ClipRect(
        child: Stack(children: [expanded, compact]),
      ),
    );
  }

  @override
  bool shouldRebuild(_InvestmentsHeaderDelegate old) =>
      old.selectedIndex != selectedIndex ||
      old.expandedExtent != expandedExtent ||
      old.compactExtent != compactExtent ||
      old.background != background ||
      old.figure != figure ||
      old.items.length != items.length ||
      !_sameLabels(old.items, items);

  static bool _sameLabels(List<KutePillItem> a, List<KutePillItem> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].label != b[i].label) return false;
    }
    return true;
  }
}

/// The collapsed header: the total in small text (the hero's figure, no
/// second line) over the same pills a step smaller, and a chevron at the
/// right end that expands everything again.
class _InvestmentsCompactBar extends StatelessWidget {
  const _InvestmentsCompactBar({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    required this.onExpand,
    required this.figure,
  });

  final List<KutePillItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onExpand;
  final ({String text, bool stale}) figure;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 20.h,
                  child: Padding(
                    padding: EdgeInsets.only(left: 4.w),
                    child: Text(
                      figure.text,
                      key: const ValueKey('investments-compact-total'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: figure.stale ? c.textSecondary : c.textPrimary,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        height: 1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 6.h),
                KutePillTabs(
                  items: items,
                  selectedIndex: selectedIndex,
                  onTap: onTap,
                  size: KutePillSize.compact,
                ),
              ],
            ),
          ),
          SizedBox(width: 4.w),
          GestureDetector(
            onTap: onExpand,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 36.w,
              height: 54.h,
              child: Icon(
                Icons.expand_more_rounded,
                key: const ValueKey('investments-expand'),
                size: 22.sp,
                color: c.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reports its child's laid-out height, after the frame, whenever it
/// changes: how the collapsing header learns the expanded chrome's size.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(
          BuildContext context, _RenderMeasureHeight renderObject) =>
      renderObject.onHeight = onHeight;
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (_reported == height) return;
    _reported = height;
    // Layout is no time to rebuild: report once the frame is drawn.
    SchedulerBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

/// The Investments dock, in the Bitcoin dock's shape: money in on the
/// left, Send on the right, search in the square.
///
/// DEPOSIT is the ONE way to fund this balance (owner decision, October
/// 2026, replacing the full-width door under the hero). It wears the
/// dock's inflow arrow — a dock action takes a glyph, so the dollar coin
/// the door wore stays on the sheet's own rows — and opens
/// [MoveLockedSide.depositToUsd] with the destination pinned here and
/// the source left pickable, so bitcoin and Cash App (while the policy
/// offers it) are ways to pay for a deposit rather than doors of their
/// own. It is a deposit into Dollars, not into a venue: the venues have
/// no deposit door at all. The dock emits the door's own
/// `quick_action_tapped` (`dollar_deposit`) under this surface's
/// source; the move flow's entry source is [kUsdDockSource].
///
/// RECEIVE moved into that sheet, as the first option of its From
/// picker: the Dollars receive screen (usd_receive_screen.dart) the
/// dock used to open itself. The dollar token is a first-class Orchestra
/// asset, so the same reusable deposit address the Bitcoin screen mints
/// for a cross-asset receive can be minted pointed at the dollar
/// balance instead: the user picks which coin the money is coming in as
/// — bitcoin included, it is an ordinary source here — and Orchestra
/// converts it on the way in. The picked coin's own deposit address is
/// what the QR shows; the dollars land on the wallet's Spark address.
///
/// SEND IS LIVE, through [UsdSendScreen] — its OWN screen, not the
/// Bitcoin send stepper. The three things that kept this button null
/// were all properties of `confirm_send.dart`, so the fix was to stop
/// going through it:
///
///  1. THE AMOUNT IS ONE INT OF SATOSHIS. `SendTx.amount` is the single
///     amount that stepper, its PSBT builder and every fee provider
///     read. The dollar send never writes `SendTx` at all: it parses the
///     typed string straight into six-decimal base units and keeps a
///     `BigInt` all the way to the SDK, so no price is consulted and no
///     `usd → sats → usd` round trip exists.
///  2. THE STEPPER SPENDS BITCOIN. Its cross-asset path pays out of the
///     bitcoin balance. The dollar screen imports no bitcoin dispatcher,
///     so there is nothing to fall back to: every failure ends in an
///     error on screen with the dollar balance untouched.
///  3. THERE WAS NO DOLLARS-ANCHORED SEND TABLE. `sendChainsFor` walks
///     the catalog out of the `sparkBtc` anchor row only.
///     `usdSendDestinations` (orchestra_usd_send_routes.dart) walks it
///     out of the DOLLAR row instead, live catalogue only, clipped to
///     the chains whose addresses the app can check.
///
/// The rail underneath is the one the venue deposits already proved:
/// `HotSettlement.prepareSpark` takes the token identifier from the
/// verified quote's own source asset and holds the SDK's echo to it by
/// equality, so a dollar send is a dollar payment or it is no payment.
///
/// SEARCH follows the pill: a venue pill searches that venue's own
/// markets, results first, exactly as the venue docks did; Portfolio
/// searches this account's activity, the dollar rows included.
///
/// Neither money verb may ever point at a venue's own pool: those are
/// different accounts, and they are on screen nowhere here.
class UsdAccountActionBar extends ConsumerWidget {
  const UsdAccountActionBar({super.key, this.onHeightChanged});

  final ValueChanged<double>? onHeightChanged;

  /// Test seam: what Deposit opens. Null opens the real sheet
  /// ([showDepositSheet]); a test swaps in a recorder so the dock can be
  /// driven without the sheet's providers behind it.
  @visibleForTesting
  static Future<void> Function(BuildContext context,
      {required MoveLockedSide lockedSide})? debugDepositSheetOpener;

  /// The dock's Deposit: the Investments deposit sheet pointed at this
  /// balance, entered from the dock.
  void _deposit(BuildContext context) {
    TrackingService.markEntrySource('move', kUsdDockSource);
    final open = debugDepositSheetOpener ?? showDepositSheet;
    // ignore: discarded_futures
    open(context, lockedSide: MoveLockedSide.depositToUsd);
  }

  /// What the square searches for [tab]: a venue's own markets, results
  /// first and under the venue's own source, or (null category) this
  /// account's activity under the Investments source.
  static ({SearchCategory? category, String source}) searchTarget(
          InvestmentsTab tab) =>
      switch (tab) {
        InvestmentsTab.investing => (
            category: SearchCategory.perpetuals,
            source: 'trading'
          ),
        InvestmentsTab.predictions => (
            category: SearchCategory.predictions,
            source: 'predictions'
          ),
        InvestmentsTab.portfolio => (
            category: null,
            source: kUsdSurfaceSource
          ),
      };

  void _search(BuildContext context, WidgetRef ref) {
    final tab = ref.read(investmentsTabProvider);
    final target = searchTarget(tab);
    final category = target.category;
    if (category == null) {
      // This account's activity, the dollar rows included: the spending
      // wallet's own transaction scope.
      showKuteSearch(
        context,
        source: target.source,
        walletId: pickSpendingWallet(ref.read(settingsProvider))?.id,
      );
      return;
    }
    showKuteSearch(
      context,
      initialCategory: category,
      searchFirst: true,
      searchHint: tab == InvestmentsTab.predictions
          ? context.l10n.searchPredictionsHint
          : context.l10n.searchInvestmentsHint,
      source: target.source,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => KuteBottomActionBar(
        source: kUsdSurfaceSource,
        onHeightChanged: onHeightChanged,
        actions: [
          KuteDockAction(
            icon: Icons.south_west_rounded,
            label: context.l10n.deposit,
            // The door's own action key, so the existing tiles keep
            // counting; the dock sends it under this surface's source.
            trackingId: 'dollar_deposit',
            onTap: () => _deposit(context),
          ),
          KuteDockAction(
            icon: Icons.north_east_rounded,
            label: context.l10n.send,
            trackingId: 'send',
            // `usd_send_opened` fires once from the screen's initState.
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => const UsdSendScreen(),
                ),
              );
            },
          ),
        ],
        onSearch: () => _search(context, ref),
      );
}

/// Reports the Investments tab opening for a deep link or a shortcut.
/// Kept next to the screen so callers don't re-derive the route name.
void trackUsdTabOpened(String source) {
  TrackingService.track('usd_tab_opened', params: {'source': source});
}
