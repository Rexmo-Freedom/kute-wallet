import 'dart:async';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_blur.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/hyperliquid/components/hl_browse_labels.dart';
// Investing discovery. Positions, orders and fills live in Portfolio.

import 'package:kute/services/runtime_capabilities_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_config_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_user_events_provider.dart';
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show PolyAutoScrollRow;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class HyperliquidScreen extends ConsumerStatefulWidget {
  final bool autoShowDeposit;
  final bool autoShowWithdraw;
  const HyperliquidScreen({
    super.key,
    this.autoShowDeposit = false,
    this.autoShowWithdraw = false,
  });

  @override
  ConsumerState<HyperliquidScreen> createState() => _HyperliquidScreenState();
}

class _HyperliquidScreenState extends ConsumerState<HyperliquidScreen> {
  double _bottomDockHeight = 0;
  void _onDockHeightChanged(double height) {
    if (mounted && (_bottomDockHeight - height).abs() > 0.5) {
      setState(() => _bottomDockHeight = height);
    }
  }

  final _scrollController = ScrollController();

  /// Per-universe memo of [hlBrowseListForTab] and [hlSubsForTab]:
  /// filtering and sorting the whole universe on every scroll-driven
  /// rebuild was wasted work. Cleared when a new 30 s universe (a new list
  /// instance) lands.
  List<HlMarket>? _listedUniverse;
  final Map<(HlBrowseTab, HlBrowseSub), List<HlMarket>> _listCache = {};
  final Map<HlBrowseTab, List<HlBrowseSub>> _subsCache = {};

  /// The watchlist the cached lists were built from.
  List<String> _watchlist = const [];

  void _syncCaches(List<HlMarket> universe) {
    final watchlist = ref.read(hlWatchlistProvider);
    if (identical(_listedUniverse, universe) &&
        identical(_watchlist, watchlist)) {
      return;
    }
    _listedUniverse = universe;
    _watchlist = watchlist;
    _listCache.clear();
    _subsCache.clear();
  }

  List<HlMarket> _listFor(
      HlBrowseTab tab, HlBrowseSub sub, List<HlMarket> universe) {
    _syncCaches(universe);
    return _listCache.putIfAbsent(
        (tab, sub),
        () => hlBrowseListForTab(tab, universe,
            sub: sub, watchlist: _watchlist));
  }

  List<HlBrowseSub> _subsFor(HlBrowseTab tab, List<HlMarket> universe) {
    _syncCaches(universe);
    return _subsCache.putIfAbsent(tab, () => hlSubsForTab(tab, universe));
  }

  /// A category pill shows its list here, in place: nothing is pushed.
  void _onTab(HlBrowseTab tab) {
    HapticFeedback.selectionClick();
    final current = ref.read(hlBrowseSelectionProvider);
    if (tab == current.tab) return;
    TrackingService.track('hl_category_pill_tapped',
        params: {'section': tab.key});
    ref.read(hlBrowseSelectionProvider.notifier).state =
        current.copyWith(tab: tab);
  }

  /// A subcategory of the category on screen.
  void _onSub(HlBrowseSub sub) {
    HapticFeedback.selectionClick();
    final current = ref.read(hlBrowseSelectionProvider);
    if (sub == current.sub) return;
    TrackingService.track('hl_category_pill_tapped', params: {
      'section': current.tab.key,
      'subcategory': sub.key,
    });
    ref.read(hlBrowseSelectionProvider.notifier).state =
        current.copyWith(sub: sub);
  }

  /// Live-price notifier captured while `ref` is valid — dispose() must
  /// NOT call ref.read (unmounted ConsumerStatefulElement throws
  /// _assertNotDisposed; same crash-fix as PolymarketScreen).
  HlLivePricesNotifier? _livePrices;

  @override
  void initState() {
    super.initState();
    // Drive the persistent shell nav bar's hide/reveal from this tab's
    // scroll.
    _scrollController.addListener(_onScrollNavBar);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Warm the builder settings now so a slow connection has already
      // answered by the time the person funds or places an order.
      unawaited(HyperliquidFundingService.prefetchBuilder());
      _livePrices = ref.read(hyperliquidLivePricesProvider.notifier);
      // Session-long side-cars, bootstrapped from this screen (NOT
      // Home): the deposit→order auto-fire watcher and the user-events
      // WS. listenManual keeps them alive for the screen's lifetime
      // WITHOUT rebuilding this whole build() on every event they emit
      // (they used to be bare ref.watch calls at the top of build).
      ref.listenManual(pendingHlOrderAutoFireProvider, (_, __) {});
      ref.listenManual(hyperliquidUserEventsProvider, (_, __) {});
      if (widget.autoShowDeposit || widget.autoShowWithdraw) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          if (widget.autoShowDeposit) {
            _showDeposit();
          } else {
            _showWithdraw();
          }
        });
      }
      _consumeAdvisorSlipIntent();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollNavBar);
    _scrollController.dispose();
    // Release the allMids socket + watch-set — uses the notifier
    // reference captured in initState, never `ref`.
    _livePrices?.unwatchAll();
    super.dispose();
  }

  /// Last scroll offset + accumulated same-direction travel, feeding the
  /// nav-bar hide/reveal hysteresis below.
  double _navLastPixels = 0;
  double _navAccum = 0;

  /// Drive the persistent shell nav bar's hide/reveal from this tab's scroll.
  /// Reveal near the very top; otherwise only toggle after ~12px of travel
  /// in one direction (hysteresis) — the old per-tick direction flip made
  /// the bar flicker in and out on tiny finger reversals mid-scroll.
  void _onScrollNavBar() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    void setHidden(bool v) {
      if (ref.read(navBarHiddenProvider) != v) {
        ref.read(navBarHiddenProvider.notifier).state = v;
      }
    }

    final delta = pos.pixels - _navLastPixels;
    _navLastPixels = pos.pixels;
    if (pos.pixels <= 24) {
      _navAccum = 0;
      setHidden(false);
      return;
    }
    // Ignore the bounce region — overscroll rebound reads as a direction
    // flip and used to blink the bar.
    if (pos.outOfRange) return;
    if ((delta > 0 && _navAccum < 0) || (delta < 0 && _navAccum > 0)) {
      _navAccum = 0;
    }
    _navAccum += delta;
    if (_navAccum > 12) {
      setHidden(true);
    } else if (_navAccum < -12) {
      setHidden(false);
    }
  }

  /// If Sal dropped a trade-ticket prefill on the way in, open the order
  /// slip for it once (post-frame) and clear the intent so a later rebuild
  /// or back-navigation doesn't reopen it. The slip runs its own gate/geo
  /// checks; we just resolve which market to show.
  void _consumeAdvisorSlipIntent() {
    final intent = ref.read(hlAdvisorSlipIntentProvider);
    if (intent == null) return;
    ref.read(hlAdvisorSlipIntentProvider.notifier).state = null;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      HlOrderSlipSheet.show(
        context,
        ref,
        market: intent.market,
        isLong: intent.isLong,
        source: 'advisor',
      );
    });
  }

  /// Deposit into the Hyperliquid trading account. Routes through the
  /// shared Move sheet locked to native HyperCore funding. Gated by remote config.
  void _showDeposit() {
    final decision =
        ref.read(runtimeCapabilitiesProvider).decision('hyperliquid.deposit');
    if (!decision.allowed || decision.comingSoon) {
      TrackingService.track('hyperliquid_funding_blocked',
          params: {'direction': 'deposit', 'reason': 'flag_off'});
      showCapabilityDecisionSheet(context, decision);
      return;
    }
    showDepositSheet(context, lockedSide: MoveLockedSide.depositToHyperliquid);
  }

  /// Withdraw spendable USDC out of the trading account back to Bitcoin via
  /// the Move sheet locked to the Trading-withdraw side. Gated by remote
  /// config.
  void _showWithdraw() {
    // An exit: only `hyperliquid.withdraw` itself can shut it.
    if (!ref.read(hyperliquidWithdrawalsEnabledProvider)) {
      TrackingService.track('hyperliquid_funding_blocked',
          params: {'direction': 'withdraw', 'reason': 'flag_off'});
      showCapabilityDecisionSheet(
          context,
          ref
              .read(runtimeCapabilitiesProvider)
              .decision('hyperliquid.withdraw'));
      return;
    }
    showDepositSheet(context,
        lockedSide: MoveLockedSide.withdrawFromHyperliquid);
  }

  Future<void> _onRefresh() async {
    ref.invalidate(hyperliquidPerpMarketsProvider);
    ref.invalidate(hyperliquidPerpCoreMarketsProvider);
    ref.invalidate(hyperliquidSpotMarketsProvider);
    ref.invalidate(hyperliquidAccountProvider);
    // Wait a moment for providers to start refetching.
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// The category pills on offer, hiding any whose list is empty. While
  /// the builder-dex markets are still to be read ([awaitingBuilder]) the
  /// categories made of them stay on offer, so their loading state can be
  /// seen.
  List<HlBrowseTab> _availableTabs(
      List<HlMarket> universe, bool awaitingBuilder) {
    if (universe.isEmpty) return const [];
    return [
      // Trending, Tradfi, then Crypto.
      for (final t in const [
        HlBrowseTab.watchlist,
        HlBrowseTab.trending,
        HlBrowseTab.tradfi,
        HlBrowseTab.crypto,
        HlBrowseTab.perps,
        HlBrowseTab.spot,
        HlBrowseTab.prelaunch,
      ])
        if ((awaitingBuilder && hlTabNeedsBuilderMarkets(t)) ||
            _listFor(t, HlBrowseSub.all, universe).isNotEmpty)
          t,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canBrowse =
        ref.watch(runtimeCapabilitiesProvider).allows('hyperliquid.browse');

    // The session-long side-cars (deposit→order auto-fire watcher +
    // user-events WS) are kept alive via listenManual in initState so
    // their events don't rebuild this whole screen.

    // The Watchlist pill leads the row once something is starred (its
    // list is empty before that, and an empty pill is hidden).
    ref.watch(hlWatchlistProvider);

    final universeAsync = ref.watch(hyperliquidBrowseUniverseProvider);
    final universe = universeAsync.valueOrNull ?? const <HlMarket>[];

    // The builder-dex markets could not be read and were never seen: a
    // category made of them shows its loading state, not a few spot rows.
    final buildersMissing = ref.watch(hyperliquidBuilderMarketsMissingProvider);

    final availableTabs = _availableTabs(universe, buildersMissing);
    final marketsLoading = universeAsync.isLoading;

    // The category on screen; one that has emptied falls back to Trending.
    var selection = ref.watch(hlBrowseSelectionProvider);
    if (availableTabs.isNotEmpty && !availableTabs.contains(selection.tab)) {
      selection = selection.copyWith(tab: HlBrowseTab.trending);
    }
    final tab = selection.tab;
    final awaitingBuilderMarkets =
        buildersMissing && hlTabNeedsBuilderMarkets(tab);
    // Its subcategories: none while its markets are still to be read.
    final subs = awaitingBuilderMarkets
        ? const <HlBrowseSub>[]
        : _subsFor(tab, universe);
    final sub = hlEffectiveSub(selection.sub, subs);
    final markets = _listFor(tab, sub, universe);

    return Scaffold(
      backgroundColor: context.isDark ? c.gradientBottom : c.background,
      // Tap anywhere outside the search field to dismiss the keyboard.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            Container(decoration: AppDecorations.screenGradient(context)),
            Positioned(
              top: -100.h,
              left: 0,
              right: 0,
              height: 400.h,
              child: Container(
                decoration: AppDecorations.ambientGlow(context),
              ),
            ),
            PlatformSafeArea(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                color: c.textPrimary,
                backgroundColor: c.surface,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  slivers: [
                    // Clears the integrated top nav bar.
                    SliverToBoxAdapter(child: SizedBox(height: 64.h)),

                    // Hero balance, like the main screen (user decision:
                    // the balance lives at the top of each pool screen,
                    // above the open positions, not on the bottom bar).
                    // Its own ConsumerWidget so account/vault/pending
                    // ticks rebuild ONLY the header, not the whole
                    // scroll view (the old inline closures used this
                    // screen's ref).
                    SliverToBoxAdapter(
                        child: const InvestmentBalanceHeader(
                            product: InvestmentsProduct.trading)),

                    // Categories: the side-scrolling pill strip under the
                    // balance and, under it, the subcategories of the
                    // category on screen, in the same pills. Both filter
                    // the list below in place, like Predictions.
                    if (canBrowse && availableTabs.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 12.h),
                            PolyAutoScrollRow(
                              height: 34.h,
                              itemCount: availableTabs.length,
                              selectedIndex: availableTabs.indexOf(tab),
                              itemBuilder: (context, i) => KutePill(
                                label: availableTabs[i]
                                    .localizedLabel(context.l10n),
                                selected: availableTabs[i] == tab,
                                onTap: () => _onTab(availableTabs[i]),
                              ),
                            ),
                            if (subs.length > 1) ...[
                              SizedBox(height: 8.h),
                              PolyAutoScrollRow(
                                // A new category starts its row afresh.
                                key: ValueKey('hl-subs-${tab.name}'),
                                height: 34.h,
                                itemCount: subs.length,
                                selectedIndex: subs.indexOf(sub),
                                itemBuilder: (context, i) => KutePill(
                                  label: subs[i].localizedLabel(context.l10n),
                                  selected: subs[i] == sub,
                                  onTap: () => _onSub(subs[i]),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                    // The category's list. While the universe first loads
                    // (nothing cached yet) show card skeletons shaped like
                    // HlMarketCard where the list will land.
                    if (!canBrowse)
                      const SliverToBoxAdapter(
                        child: InvestmentDiscoveryNotice(
                            capability: 'hyperliquid.browse'),
                      )
                    else if (marketsLoading && availableTabs.isEmpty)
                      SliverToBoxAdapter(
                        child: KuteSkeleton(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.w),
                            child: Column(
                              children: [
                                for (var i = 0; i < 5; i++) ...[
                                  if (i > 0) SizedBox(height: 12.h),
                                  SkeletonCard(
                                    radius: AppRadius.lg,
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 16.w, vertical: 16.h),
                                    child: Row(
                                      children: [
                                        SkeletonCircle(36.w),
                                        SizedBox(width: 12.w),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              SkeletonBar(90.w, 16.h),
                                              SizedBox(height: 6.h),
                                              SkeletonBar(60.w, 11.h),
                                            ],
                                          ),
                                        ),
                                        SkeletonBar(72.w, 16.h),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      )
                    else if (availableTabs.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyState(),
                      )
                    else ...[
                      // The list under the pills fades in when the pill
                      // or the subcategory changes (never on a refresh);
                      // only an opacity runs, so the scroll position is
                      // untouched.
                      SliverSelectionFade(
                        selection: (tab, sub),
                        slivers: [
                          // The list's own heading, as on Predictions.
                          SliverToBoxAdapter(
                            child: _HlSectionHeader(
                                label: tab.localizedLabel(context.l10n)),
                          ),
                          if (awaitingBuilderMarkets)
                            SliverToBoxAdapter(
                              child: SkeletonCardList(count: 5, height: 120.h),
                            )
                          else
                            // The whole list is in memory; the same self-
                            // subscribing [HlMarketCard]s build lazily as they
                            // scroll in, so every price on screen is live.
                            SliverPadding(
                              padding: EdgeInsets.symmetric(horizontal: 16.w),
                              sliver: SliverList.separated(
                                itemCount: markets.length,
                                separatorBuilder: (_, __) =>
                                    SizedBox(height: 12.h),
                                itemBuilder: (_, index) {
                                  final market = markets[index];
                                  return RepaintBoundary(
                                    child: HlMarketCard(
                                      key: ValueKey(
                                          'hl-${market.kind.name}-${market.wireCoin}'),
                                      market: market,
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                      // Clears the bottom action bar.
                      SliverToBoxAdapter(
                          child: SizedBox(height: _bottomDockHeight + 24.h)),
                    ],
                  ],
                ),
              ),
            ),

            // The integrated top nav bar now lives ONCE in the persistent
            // nav shell (lib/screens/app_shell.dart), mounted above all four
            // tab pages — no longer painted per-screen. The 64.h top sliver
            // above still clears its space; this screen's scroll listener
            // drives its hide/reveal via navBarHiddenProvider.

            // Hide the bottom nav when the keyboard is open — Scaffold's
            // resizeToAvoidBottomInset would otherwise float the pill
            // directly above the keyboard with a visible gap.
            if (MediaQuery.of(context).viewInsets.bottom == 0) ...[
              // Frosted blur behind the bottom nav (same as Home).
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _bottomDockHeight + 12.h,
                child: IgnorePointer(
                  child: ClipRect(
                    child: KuteBlur(
                      sigmaX: 4.0,
                      sigmaY: 4.0,
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: InvestmentActionBar(
                  onHeightChanged: _onDockHeightChanged,
                  product: InvestmentsProduct.trading,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

}

// ───────────────────────── empty state ─────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.candlestick_chart_rounded,
              color: c.textTertiary,
              size: 48.sp,
            ),
            SizedBox(height: 16.h),
            Text(
              context.l10n.hlNoMarketsNow,
              style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The list's heading, matching the Predictions screen's exactly: a bold
/// label, text only.
class _HlSectionHeader extends StatelessWidget {
  final String label;

  const _HlSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 18.h, 16.w, 10.h),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: c.textPrimary,
          fontSize: 22.sp,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}
