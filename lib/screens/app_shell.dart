import 'package:kute/services/runtime_capabilities_service.dart';
// lib/screens/app_shell.dart
//
// The persistent navigation shell for the nav tab destinations
// (Home / Bank / USD / Trading / Predictions — Bank is hidden this
// release and USD holds its strip slot). Built on go_router's
// `StatefulShellRoute` with a custom [navigatorContainerBuilder] that lays
// the branch navigators out in a horizontally-swipeable [PageView]
// (instead of the default IndexedStack), so:
//
//   * ONE persistent [KuteTopNavBar] is mounted across all tabs — the
//     slide->expand indicator pill in action_pill.dart morphs for real when
//     the active index changes, because the bar is never remounted.
//   * the tab pages SWIPE horizontally.
//
// Every non-tab route (/settings, /affiliate, the confirm-send sub-routes,
// deep links, etc.) stays a top-level GoRoute OUTSIDE this shell and pushes
// full-screen over it, exactly as before.

import 'package:flutter/material.dart';
import 'package:kute/screens/hyperliquid/components/hl_trade_alerts_host.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/constants/feature_flags.dart';
import 'package:kute/providers/active_shell_tab_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/models/settings_model.dart' show WalletConfig;
import 'package:kute/providers/shell_wallet_provider.dart'
    show shellVenueOwnerProvider;
import 'package:kute/screens/home/components/kute_top_nav_bar.dart';
import 'package:kute/screens/home/shell_venue_tabs.dart'
    show shellShowsPredictionsTab, shellShowsTradingTab, shellShowsUsdTab;
import 'package:kute/services/once_flags_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The tab branches, in strip order. Index here IS the branch index in
/// the [StatefulShellRoute] AND the [PageView] page index.
///   0 = Home        (/home)
///   1 = Bank        (/bank)   — hidden this release, branch still mounted
///   2 = USD         (/usd)
///   3 = Trading     (/hyperliquid)
///   4 = Predictions (/polymarket)
///
/// This ordering mirrors the tab order the nav pill renders (Home, Bank,
/// Trading, Predictions) so a swipe left/right lands on the
/// visually-adjacent tab. The Earn tab (the Flashnet USDB product) was
/// removed entirely. The shell still keys off the [ActiveNavTab] the
/// pill reports rather than a raw strip index, so the mapping stays
/// explicit rather than positional.
const List<ActiveNavTab> _kShellTabs = [
  ActiveNavTab.home,
  ActiveNavTab.bank,
  ActiveNavTab.usd,
  ActiveNavTab.trading,
  ActiveNavTab.predictions,
];

/// The tabs the PAGER exposes to swipes, in strip order. When the Bank
/// tab is hidden ([showBankTab] false) its branch stays mounted (the
/// shell requires every branch alive) but gets NO page: a swipe from
/// Home lands directly on Investing, and '/bank' is unreachable by
/// gesture. Pager page indices are indices into THIS list; branch
/// indices remain indices into [_kShellTabs].
const List<ActiveNavTab> _kVisibleTabs = showBankTab
    ? _kShellTabs
    : [
        ActiveNavTab.home,
        // USD takes the slot the Bank tab used to hold.
        ActiveNavTab.usd,
        ActiveNavTab.trading,
        ActiveNavTab.predictions,
      ];

/// Branch index for a given tab. Must stay in lockstep with the branch
/// order in app_router.dart's [StatefulShellRoute].
int _branchIndexFor(ActiveNavTab tab) => _kShellTabs.indexOf(tab);

/// The tabs that belong to an owner and can be absent for one: Dollars and
/// the two venues. Home is always there; the hidden Bank branch has its
/// own rule.
const _ownedTabs = {
  ActiveNavTab.usd,
  ActiveNavTab.trading,
  ActiveNavTab.predictions,
};

/// The tabs the pager exposes for [wallet], which is exactly the set the
/// strip draws for it.
///
/// The strip has always dropped Dollars and the venues for a wallet that
/// owns neither, but the pager did not, so a swipe on a hardware wallet
/// still landed on the spending account's dollars and positions — money
/// that is not that wallet's. The gesture and the strip now read the
/// same two predicates, so a tab that is not drawn cannot be reached.
List<ActiveNavTab> _visibleTabsFor(WalletConfig? wallet) => [
      for (final tab in _kVisibleTabs)
        if (switch (tab) {
          ActiveNavTab.usd => shellShowsUsdTab(wallet),
          ActiveNavTab.trading => shellShowsTradingTab(wallet),
          ActiveNavTab.predictions => shellShowsPredictionsTab(wallet),
          _ => true,
        })
          tab,
    ];

// [activeShellTabProvider] used to live here; it moved to
// providers/active_shell_tab_provider.dart (with [ActiveNavTab]) so the
// live-price notifiers can read the active tab at creation time without
// importing this file — which imports them.

/// Applies the per-tab live-data policy for [tab]:
///   * Hyperliquid live-price socket — Trading only. Goes through
///     [HlLivePricesNotifier.pause]/[resume], so a pause is deferred while
///     an `acquire`d consumer is still visible somewhere else.
///   * Polymarket CLOB socket — Predictions only. `addTokens` keeps accruing
///     the wanted set while paused, so [LivePriceNotifier.resume]
///     re-subscribes everything on return.
///   * Trading provider visibility flag — Home AND Predictions, because the
///     Home tab surfaces Polymarket-derived tiles fed by its silent refresh.
///
/// The `ref.exists` guards keep this from instantiating autoDispose
/// providers nothing is watching yet (a cold read of the trading provider
/// would kick its whole async build). Idempotent — every target API no-ops
/// when already in the requested state. Shared by the shell's tab switch and
/// the app-level foreground resume so both stay in lockstep.
void applyShellTabLivePolicy(WidgetRef ref, ActiveNavTab tab) {
  if (ref.exists(hyperliquidLivePricesProvider)) {
    final hl = ref.read(hyperliquidLivePricesProvider.notifier);
    if (tab == ActiveNavTab.trading) {
      hl.resume();
    } else {
      hl.pause();
    }
  }
  if (ref.exists(livePriceProvider)) {
    final clob = ref.read(livePriceProvider.notifier);
    if (tab == ActiveNavTab.predictions) {
      clob.resume();
    } else {
      clob.pause();
    }
  }
  if (ref.exists(polymarketTradingProvider)) {
    ref.read(polymarketTradingProvider.notifier).setPolymarketVisible(
        tab == ActiveNavTab.home || tab == ActiveNavTab.predictions);
  }
}

/// Suspends every live-price socket regardless of tab OR acquire refcount —
/// the app is leaving the foreground, so even an `acquire`d surface (bet
/// slip, order slip, pro chart) must stop streaming. Goes through
/// `suspendForBackground`, which sidesteps the pause/acquire bookkeeping a
/// plain `pause()` defers on; [resumeShellLiveSockets] undoes it on the way
/// back in. The trading provider's visibility flag is deliberately left
/// alone: its silent refresh already self-gates on the app lifecycle state.
void pauseShellLiveSockets(WidgetRef ref) {
  if (ref.exists(hyperliquidLivePricesProvider)) {
    ref.read(hyperliquidLivePricesProvider.notifier).suspendForBackground();
  }
  if (ref.exists(livePriceProvider)) {
    ref.read(livePriceProvider.notifier).suspendForBackground();
  }
}

/// Clears the background suspension on foreground resume. Must run AFTER
/// [applyShellTabLivePolicy] has re-stamped the per-tab pause/resume state:
/// each notifier then reconnects only if its feed is still wanted — an
/// `acquire`d consumer is outstanding or its owning tab is the active one —
/// so an acquired sheet gets its prices back even when its owning tab is
/// not the tab being resumed.
void resumeShellLiveSockets(WidgetRef ref) {
  if (ref.exists(hyperliquidLivePricesProvider)) {
    ref.read(hyperliquidLivePricesProvider.notifier).resumeFromBackground();
  }
  if (ref.exists(livePriceProvider)) {
    ref.read(livePriceProvider.notifier).resumeFromBackground();
  }
}

class AppShell extends ConsumerStatefulWidget {
  /// The shell provided by go_router — drives branch switching and exposes
  /// [StatefulNavigationShell.currentIndex].
  final StatefulNavigationShell navigationShell;

  /// The branch navigators, one per tab, laid out in the [PageView].
  final List<Widget> children;

  const AppShell({
    super.key,
    required this.navigationShell,
    required this.children,
  });

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  /// Continuous page position (0..branches-1). Replaces the PageView's
  /// PageController: the lazy PageView viewport PARKED off-screen branch
  /// navigators in the sliver keep-alive bucket (go_router's branch
  /// proxies are wantKeepAlive), leaving GlobalKey-owned subtrees in the
  /// exact detached-but-alive state that intermittently trips Flutter's
  /// '_elements.contains(element)' reclaim assert on route pops (the Sal
  /// Send red screen). The custom pager below keeps ALL branches mounted
  /// (Offstage when far), per go_router's custom-container guidance.
  late final AnimationController _page;

  int _pageTransition = 0;
  late int _lastBranch;
  List<ActiveNavTab> _lastVisibleTabs = const [];

  Future<void> _animatePage(int target,
      {bool settle = false, Duration? duration}) async {
    final transition = ++_pageTransition;
    try {
      await _page
          .animateTo(
            target.toDouble(),
            duration: duration ?? const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || transition != _pageTransition) return;
    if (settle) _onPageSettled(target);
  }

  /// The tabs this wallet can reach by gesture. Read, not watched, from
  /// the drag handlers; [build] watches it.
  List<ActiveNavTab> get _tabs =>
      _visibleTabsFor(ref.read(shellVenueOwnerProvider));

  /// Pager page index for a branch index; -1 when that branch has no page
  /// (the hidden Bank branch, or a tab this wallet does not own).
  int _pageIndexForBranch(int branchIndex) =>
      _tabs.indexOf(_kShellTabs[branchIndex]);

  /// The highest page index the pager can settle on right now. The
  /// controller keeps the widest possible range, because its bounds are
  /// fixed at construction and the tab set is not.
  double get _maxPage =>
      (_tabs.length - 1).clamp(0, _kVisibleTabs.length - 1).toDouble();

  @override
  void initState() {
    super.initState();
    _lastBranch = widget.navigationShell.currentIndex;
    _page = AnimationController(
      vsync: this,
      lowerBound: 0,
      upperBound: (_kVisibleTabs.length - 1).toDouble(),
      value: _pageIndexForBranch(widget.navigationShell.currentIndex)
          .clamp(0, _kVisibleTabs.length - 1)
          .toDouble(),
      duration: const Duration(milliseconds: 320),
    );
    // Stamp the initial tab and apply its live-socket policy once mounted
    // (post-frame: provider writes are illegal while the tree is building).
    // Matters for deep links that land the shell on a non-Home branch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tab = _kShellTabs[widget.navigationShell.currentIndex];
      ref.read(activeShellTabProvider.notifier).state = tab;
      applyShellTabLivePolicy(ref, tab);
      _maybePlaySwipeHint(tab);
    });
  }

  /// One-time "elastic band" peek on the very first shell mount (i.e.
  /// right after wallet creation): the pager pulls a little toward the
  /// next tab and springs back, so the user learns Home is not the only
  /// screen (user decision: once, ever). Skipped under Reduce Motion, when
  /// the shell did not land on Home, or if the user starts dragging.
  void _maybePlaySwipeHint(ActiveNavTab tab) {
    if (tab != ActiveNavTab.home) return;
    if (_tabs.length < 2) return;
    // Platform dispatcher, not MediaQuery.of: this runs from a post-frame
    // callback, and a whole-MediaQuery lookup here would subscribe the
    // SHELL to every metrics change for the rest of the session.
    if (WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      return;
    }
    if (!OnceFlagsService.claimOnce('shell_swipe_hint_v1')) return;
    Future<void>.delayed(const Duration(milliseconds: 900), () async {
      if (!mounted ||
          _page.value != 0 ||
          _page.isAnimating ||
          widget.navigationShell.currentIndex !=
              _branchIndexFor(ActiveNavTab.home)) {
        return;
      }
      TrackingService.track('shell_swipe_hint_shown');
      await _page.animateTo(
        0.22,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
      if (!mounted || _page.value < 0.2) return; // user grabbed it
      HapticFeedback.selectionClick();
      await _page.animateTo(
        0,
        duration: const Duration(milliseconds: 720),
        curve: Curves.elasticOut,
      );
    });
  }

  @override
  void didUpdateWidget(covariant AppShell old) {
    super.didUpdateWidget(old);
    final target = widget.navigationShell.currentIndex;
    final branchChanged = _lastBranch != target;
    _lastBranch = target;
    // On a tab change, reveal the nav bar: a freshly-shown tab should start
    // with the bar visible rather than inherit the previous tab's hidden
    // state; that tab's own scroll listener re-hides it as the user scrolls.
    // Deferred so we don't mutate a provider mid-build.
    if (branchChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(navBarHiddenProvider)) {
          ref.read(navBarHiddenProvider.notifier).state = false;
        }
        // Tab switched: remember it for the lifecycle handler and swap the
        // live sockets over — pause what the outgoing tab needed, resume
        // what the incoming one does. Rapid switches just re-apply; every
        // call is idempotent so the last one wins.
        final tab = _kShellTabs[target];
        ref.read(activeShellTabProvider.notifier).state = tab;
        applyShellTabLivePolicy(ref, tab);
      });
    }
    // The branch changed underneath us — either from a nav-bar tab tap
    // (goBranch below) or from an external `context.go('/polymarket')`.
    // Bring the PageView to the new branch's page if it isn't already there.
    final targetPage = _pageIndexForBranch(target);
    if (targetPage < 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pageIndexForBranch(widget.navigationShell.currentIndex) < 0) {
          widget.navigationShell.goBranch(_branchIndexFor(ActiveNavTab.home));
        }
      });
      return;
    }
    if (branchChanged || (_page.value - targetPage).abs() > 0.001) {
      _animatePage(targetPage);
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  /// Nav-bar tab tap → switch the go_router branch. The pill reports the
  /// tapped [ActiveNavTab] (never a raw strip index, which drifts as the
  /// tab set changes). `initialLocation: false` so re-tapping the ACTIVE
  /// tab does NOT reset that branch to its initial location (preserves a
  /// pushed sub-route within the branch's own navigator). The pill only ever
  /// calls this for a DIFFERENT tab — its "already active" affordances (the
  /// Predictions/Trading deposit menus) it handles itself. The PageView is
  /// synced in [didUpdateWidget] once `currentIndex` updates.
  void _selectTab(ActiveNavTab tab) {
    final index = _branchIndexFor(tab);
    if (index < 0) return;
    final page = _pageIndexForBranch(index);
    if (page < 0) return;
    _animatePage(page);
    final reselected = index == widget.navigationShell.currentIndex;
    // Every tab landing reports itself (user decision: all main
    // screens tracked). Enum names stay the internal vocabulary
    // ('trading'), matching the source params used everywhere. A tap on
    // the tab already showing is not a new view: it pops the branch back
    // to its root, so it reports as a reselect instead of a duplicate
    // screen view.
    if (reselected) {
      TrackingService.track('shell_tab_reselected', params: {'tab': tab.name});
    } else {
      TrackingService.screenView('tab_${tab.name}');
      _trackTabChanged(tab, method: 'tap');
    }
    widget.navigationShell.goBranch(
      index,
      initialLocation: reselected,
    );
  }

  /// Commit a completed swipe. Cancelled or superseded animations never
  /// reach this callback, so a late swipe cannot undo a newer tab selection.
  void _onPageSettled(int index) {
    // The settled index is a PAGE index (visible tabs); map to branch.
    final tabs = _tabs;
    if (index < 0 || index >= tabs.length) return;
    final branch = _branchIndexFor(tabs[index]);
    if (branch == widget.navigationShell.currentIndex) return;
    // Swipe landings count as tab views too (taps go via _selectTab).
    TrackingService.screenView('tab_${tabs[index].name}');
    _trackTabChanged(tabs[index], method: 'swipe');
    widget.navigationShell.goBranch(branch);
  }

  /// `shell_tab_changed`: the `$screen` view cannot say HOW the user got
  /// to a tab, so tap vs swipe and the tab they left ride this event.
  /// Callers invoke it only for a real branch change (a re-tap reports
  /// `shell_tab_reselected`; a swipe that springs back never settles).
  void _trackTabChanged(ActiveNavTab to, {required String method}) {
    TrackingService.track('shell_tab_changed', params: {
      'from_tab': _kShellTabs[widget.navigationShell.currentIndex].name,
      'to_tab': to.name,
      'method': method,
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // sizeOf, never MediaQuery.of: the aspect-scoped lookup depends on the
    // viewport SIZE only. The whole-data lookup this replaced registered
    // the shell as a dependent of every MediaQuery aspect, so each keyboard
    // show and hide rebuilt this element — and with it the Stack holding
    // all four branch navigators, mid-pop, while the keyboard was going
    // away. Nothing here needs viewInsets.
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 0) return;
    // A finger wins over any in-flight programmatic peek/animation.
    ++_pageTransition;
    if (_page.isAnimating) _page.stop();
    _page.value = (_page.value - d.primaryDelta! / width).clamp(0.0, _maxPage);
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    // Fling past ±300 px/s advances a page in the fling direction;
    // otherwise snap to the nearest page — PageScrollPhysics feel.
    int target;
    if (velocity.abs() > 300) {
      target = velocity < 0 ? _page.value.ceil() : _page.value.floor();
    } else {
      target = _page.value.round();
    }
    target = target.clamp(0, _maxPage.toInt());
    final distance = (_page.value - target).abs();
    _animatePage(target,
        settle: true,
        duration: Duration(
          milliseconds: (120 + 200 * distance).clamp(120, 320).round(),
        ));
  }

  Widget _branchPage(int branch, int visibleIndex, double page) {
    final shown = visibleIndex >= 0 && (visibleIndex - page).abs() < 1.0;
    return Offstage(
      key: ValueKey(_kShellTabs[branch]),
      offstage: !shown,
      child: TickerMode(
        enabled: shown,
        child: FractionalTranslation(
          translation: Offset(visibleIndex < 0 ? 0 : visibleIndex - page, 0),
          child: widget.children[branch],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int currentIndex = widget.navigationShell.currentIndex;
    // Watched, so switching to a wallet that owns fewer tabs rebuilds the
    // pager with its shorter set.
    final visible = _visibleTabsFor(ref.watch(shellVenueOwnerProvider));
    // A Ledger's venue tabs exist only while Ledger Investing / Ledger
    // Predictions are on (their runtime capabilities); watched, so an admin
    // switch adds or drops them live. A tab that disappears while open
    // (a direct link, a wallet switch, a remote switch-off) falls back to
    // Home below, with no sheet: the venue is simply not there.
    ref.watch(runtimeCapabilitiesProvider);
    if (!listEquals(_lastVisibleTabs, visible)) {
      _lastVisibleTabs = List.of(visible);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = _pageIndexForBranch(widget.navigationShell.currentIndex);
        ++_pageTransition;
        _page.stop();
        _page.value = target < 0 ? 0 : target.toDouble();
        if (target < 0) {
          widget.navigationShell.goBranch(_branchIndexFor(ActiveNavTab.home));
        }
      });
    } else if (_ownedTabs.contains(_kShellTabs[currentIndex]) &&
        !visible.contains(_kShellTabs[currentIndex])) {
      // A direct link into a tab this owner does not have (a Ledger's
      // Investing or Predictions while its capability is off) leaves the
      // tab list unchanged, so the fallback above never runs and the
      // branch would sit blank. Send it home too.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final index = widget.navigationShell.currentIndex;
        if (_ownedTabs.contains(_kShellTabs[index]) &&
            !_tabs.contains(_kShellTabs[index])) {
          widget.navigationShell.goBranch(_branchIndexFor(ActiveNavTab.home));
        }
      });
    }

    return Scaffold(
      // Theme-appropriate base (matches screenGradient's light-mode
      // c.background) so a tab SWIPE never flashes the dark root behind the
      // pages in light mode. The branch screens paint their own gradient on
      // top; this only shows in the transient gap during the slide.
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          // Hyperliquid trade alerts (fills, TP/SL, liquidation risk,
          // venue cancels) as in-app banners on every tab. Paints nothing.
          const HlTradeAlertsHost(child: SizedBox.shrink()),
          // The four branch navigators, swipeable and ALL MOUNTED (no
          // lazy viewport, no keep-alive parking — see the _page doc).
          // Far pages sit Offstage with tickers muted; a drag reveals
          // the neighbor. An inner horizontal scrollable (e.g. a
          // category pill strip) still wins the gesture arena when the
          // drag starts on it, same as with the PageView.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onHorizontalDragCancel: () {
              final target =
                  _pageIndexForBranch(widget.navigationShell.currentIndex);
              if (target >= 0) _animatePage(target);
            },
            child: AnimatedBuilder(
              animation: _page,
              builder: (context, _) {
                final page = _page.value;
                return Stack(
                  children: [
                    for (var b = 0; b < widget.children.length; b++)
                      _branchPage(b, visible.indexOf(_kShellTabs[b]), page),
                  ],
                );
              },
            ),
          ),

          // The ONE persistent top nav bar. Reads the shell's current index
          // for its active tab, routes taps back through [_selectTab] (not
          // `context.go`) so the branch switches without a remount.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: KuteTopNavBar(
              activeTab: _kShellTabs[currentIndex],
              onSelectTab: _selectTab,
            ),
          ),
        ],
      ),
    );
  }
}
