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
//   * the Investments deposit door under it, wearing the dollar coin;
//   * one pill row under that, Investing · Predictions · Portfolio, the
//     same pills the Home strip uses, the two venue pills wearing the
//     venues' own marks (the Hyperliquid and Polymarket logos, as the
//     hub's wallet rows draw them), over an IndexedStack of the existing
//     screens in their embedded shape: the Hyperliquid and Polymarket
//     browsers with their own hero and dock taken out, and the one
//     Portfolio screen exactly as it is pushed (same tabs, filters and
//     drill-down). Earn is a section of the Portfolio's Statistics tab
//     (open_investments_screen.dart), no longer a pill here;
//   * the same dock as before — Receive on the left, Send on the right,
//     search in the square — with the search scoped to the pill on
//     screen: the venue's own markets on Investing and Predictions, this
//     account's activity on Portfolio.
//
// THE WHOLE PAGE SCROLLS AS ONE, on every pill. The hero, the deposit
// door and the pills are the header slivers of a [NestedScrollView]; the
// pill on screen is its body, and each embedded screen's own list
// scrolls inside it through the primary scroll controller, so scrolling
// the content scrolls the header away first, the way the Activity list
// does. The pills pin once they reach the top (the Portfolio's own tab
// strip pins the same way on the Ledger, see PortfolioTabsSliver): a
// list a screen deep can still change pill. Pull-to-refresh is the
// page's one [RefreshIndicator] over the pill on screen, and the top
// nav bar's hide-on-scroll is driven from the page's scroll
// notifications, so the embedded screens carry neither.
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
// Receive opens the coin picker off the Orchestra route list, pointed at
// this balance: whatever coin the money arrives in, dollars land. Send is
// its own screen (usd_send_screen.dart), pointed the other way. A Ledger
// account is not part of this: it keeps its own Investing and Predictions
// tabs of the strip, with its own screens, buttons and layout.
//
// The tab only ever renders for the spending account (see
// `shellShowsUsdTab` in shell_venue_tabs.dart) — a Bitcoin-only,
// watch-only, tracked, signer or Ledger account has no dollars.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/asset_icon_provider.dart' show kUsdMarkAsset;
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
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/usd/usd_send_screen.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Source key for every event this surface emits.
const String kUsdSurfaceSource = 'usd';

/// The venues' own marks, as the hub's wallet rows and the Move sheet's
/// rows draw them: the Investing pill wears the Hyperliquid logo, the
/// Predictions pill the Polymarket logo.
const String kInvestingMarkAsset = 'lib/assets/hyperliquid-logo.svg';
const String kPredictionsMarkAsset = 'lib/assets/polymarket-logo.svg';

/// The Investments pills, in strip order. [key] is the analytics value
/// and the `?tab=` query value, fixed English so a pill reads the same in
/// PostHog and in a link in every app language.
enum InvestmentsTab {
  investing('investing'),
  predictions('predictions'),
  portfolio('portfolio');

  const InvestmentsTab(this.key);

  final String key;

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

/// The hero, the deposit door and the pill row as the page's header
/// slivers; the pill's screen as its body (see the file header).
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

  /// The outer (header) scroll, for the nav bar's "near the top" reveal.
  final ScrollController _outer = ScrollController();

  /// Accumulated same-direction travel, feeding the nav-bar hide/reveal
  /// hysteresis below (the venue screens' own rule, run once here for
  /// every pill).
  double _navAccum = 0;

  @override
  void dispose() {
    _outer.dispose();
    super.dispose();
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
  bool _onScroll(ScrollNotification notification) {
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
    switch (ref.read(investmentsTabProvider)) {
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

    KutePillItem item(InvestmentsTab tab) => switch (tab) {
          InvestmentsTab.investing => KutePillItem(
              label: l10n.trading,
              leading: SvgPicture.asset(kInvestingMarkAsset,
                  width: 15.sp, height: 15.sp)),
          InvestmentsTab.predictions => KutePillItem(
              label: l10n.predictions,
              leading: SvgPicture.asset(kPredictionsMarkAsset,
                  width: 15.sp, height: 15.sp)),
          InvestmentsTab.portfolio =>
            KutePillItem(label: l10n.walletPortfolioAction),
        };

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
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const InvestmentBalanceHeader(
                    product: InvestmentsProduct.trading,
                    oneBalance: true,
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 10.h),
                    child: const _InvestmentsPrimaryActions(),
                  ),
                ],
              ),
            ),
            // The Home strip's pills, pinned once they reach the top.
            SliverPersistentHeader(
              pinned: true,
              delegate: _InvestmentsPillsDelegate(
                items: [for (final tab in tabs) item(tab)],
                selectedIndex: tabs.indexOf(selected),
                onTap: (i) => _pick(tabs[i]),
                extent: 34.h + 12.h,
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

/// The pill row as a pinned sliver header (PortfolioTabsSliver's shape):
/// the strip's own background so the list frosts under nothing, the row
/// on the Home strip's inset, 12.h of air under it.
class _InvestmentsPillsDelegate extends SliverPersistentHeaderDelegate {
  _InvestmentsPillsDelegate({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    required this.extent,
    required this.background,
  });

  final List<KutePillItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final double extent;
  final Color background;

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Container(
        color: background,
        padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
        child: KutePillTabs(
          items: items,
          selectedIndex: selectedIndex,
          onTap: onTap,
        ),
      );

  @override
  bool shouldRebuild(_InvestmentsPillsDelegate old) =>
      old.selectedIndex != selectedIndex ||
      old.extent != extent ||
      old.background != background ||
      old.items.length != items.length ||
      !_sameLabels(old.items, items);

  static bool _sameLabels(List<KutePillItem> a, List<KutePillItem> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].label != b[i].label) return false;
    }
    return true;
  }
}

/// The Investments deposit door, full width, with nothing beside it: the
/// ONE way to fund this balance. Every way of funding it is the same door
/// wearing the same name and the same mark — the dollar coin
/// ([kUsdMarkAsset]), as the Dollars deposit button wore it — opening
/// [MoveLockedSide.depositToUsd] with the destination pinned here and
/// the source left pickable, so bitcoin and Cash App (while the policy
/// offers it) are ways to pay for a deposit rather than doors of their
/// own. It is a deposit into Dollars, not into a venue: the venues have
/// no deposit door at all.
class _InvestmentsPrimaryActions extends StatelessWidget {
  const _InvestmentsPrimaryActions();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 12.h),
        child: AppButton(
          text: context.l10n.dollarDeposit,
          svgAsset: kUsdMarkAsset,
          onPressed: () {
            TrackingService.quickAction('dollar_deposit',
                source: kUsdSurfaceSource);
            TrackingService.markEntrySource('move', kUsdSurfaceSource);
            showDepositSheet(context, lockedSide: MoveLockedSide.depositToUsd);
          },
        ),
      );
}

/// The Investments dock — the Bitcoin dock's verbs in the Bitcoin dock's
/// order: Receive on the left, Send on the right, search in the square.
///
/// RECEIVE is live. The dollar token is a first-class Orchestra asset,
/// so the same reusable deposit address the Bitcoin screen mints for a
/// cross-asset receive can be minted pointed at the dollar balance
/// instead: the user picks which coin the money is coming in as —
/// bitcoin included, it is an ordinary source here — and Orchestra
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
            label: context.l10n.receive,
            trackingId: 'receive',
            // `usd_receive_opened` fires once from the screen's initState.
            onTap: () => context.pushNamed('receiveDollars'),
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
