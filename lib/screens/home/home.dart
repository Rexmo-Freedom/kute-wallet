import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/screens/polymarket/components/polymarket_error_copy.dart';
import 'package:kute/screens/shared/bitcoin_wallet_actions.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:kute/providers/auth_provider.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/claim_auto_fire.dart';
import 'package:kute/providers/pending_bet_autofire.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show showDepositSheet, MoveLockedSide;
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:kute/screens/shared/animated_balance.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/home_view_scope_provider.dart';
import 'package:kute/providers/kute_state_provider.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:kute/screens/polymarket/components/claim_placed_overlay.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_backup_provider.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/screens/analytics/components/money_flow_breakdown.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/screens/home/components/seed_unavailable_banner.dart';
import 'package:kute/screens/home/components/wallet_cards.dart';
import 'package:kute/screens/home/home_wallet_switcher.dart';
import 'package:kute/screens/activity/activity_history_screen.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/providers/background_sync_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/btc_amount_text.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/notifications/push_permission.dart';
import 'package:kute/services/tracking/latency_tracker.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:kute/providers/currency_conversions_provider.dart';

class Home extends ConsumerStatefulWidget {
  const Home({super.key});

  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _headerAnimController;
  late AnimationController _entranceController;
  double _lastScrollOffset = 0;
  double _scrollOffset = 0;
  bool _headerVisible = true;

  /// True once the big hero balance card has scrolled up past the
  /// pinned top bar. Drives a cross-fade in the floating top bar:
  /// the Sal mascot label fades out and a condensed balance fades in
  /// at the top-left. Recomputed on a boundary crossing only (in
  /// `_onScroll`) so we don't `setState` on every scroll frame.
  bool _balanceCollapsed = false;

  /// Design-spec offset (in ScreenUtil base px) past which the hero
  /// balance is treated as collapsed. Roughly the height of the spacer +
  /// hero headline so the condensed balance hands off right as the big
  /// one leaves view. Scaled with `.h` at the comparison site so the
  /// handoff tracks the (ScreenUtil-scaled) spacer/hero on short and tall
  /// devices alike rather than drifting against a raw logical-px value.
  static const double _kBalanceCollapseThreshold = 110.0;

  /// Coalesces the post-swap sync. Rapidly swiping through three or
  /// four wallets used to schedule one `BackgroundSyncService.restart()`
  /// per swap; only the last is meaningful (the user has settled on a
  /// wallet) but every prior one still fired, tearing down + reattaching
  /// Spark stream subs in series. Cancel any pending scheduled restart
  /// when a new swipe lands so only the final destination triggers the
  /// heavy work.
  Timer? _walletSwitchDebounce;

  /// Defers the once-per-install push prompt past the first-frame motion.
  Timer? _pushPermissionTimer;

  @override
  void initState() {
    super.initState();
    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Reduce Motion (WCAG 2.3.3): the staggered entrance fade/slide is
      // decorative. When the OS "reduce motion" toggle is on, jump the
      // controller straight to its end state so widgets render in their
      // final position with no transition.
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _entranceController.value = 1.0;
      } else {
        _entranceController.forward();
      }
      // Initialize Polymarket/USDC wallet in background during loading.
      // This ensures Safe deployment + token approvals are done before the user
      // tries to use predictions or USDC features.
      _initPolymarketAccount();

      // The one automatic push-permission ask: the first Home after
      // onboarding (wallet created or restored), once per install. Home
      // only mounts behind a wallet, so this never runs on the welcome or
      // PIN screens. Delayed past the entrance animation and the shell's
      // swipe hint so the system sheet does not land mid-motion; every
      // later mount is a no-op inside requestOnceFromHome.
      _pushPermissionTimer = Timer(const Duration(milliseconds: 2500), () {
        if (!mounted) return;
        unawaited(PushPermission.requestOnceFromHome());
      });

      // The "wallet switching" + "initial sync" overlays used to live
      // here as a compensating UX for the empty home that surfaced
      // while the first sync ran. With the per-wallet Hive
      // transaction cache (TransactionCacheCodec) hydrating the
      // Activity feed synchronously at boot AND viewedWalletId
      // driving display surfaces independently of the active-wallet
      // debounce, the home now paints fresh data instantly on every
      // swipe and on cold start. The overlays were just covering up
      // an old behaviour that no longer exists; deleting them avoids
      // the "loading wallet…" flash on a wallet that's already on
      // screen with cached data.

      // Belt-and-suspenders wallet-switch sync. The switcher itself
      // already kicks a delayed restart, but if the SDK re-init is
      // slow (or the user pogos between wallets quickly) the home
      // can land on an empty balance/tx state because the sync
      // listener attached before the new SDK was ready. Watch the
      // active wallet ID — on any change, re-invalidate and kick a
      // fresh sync a few hundred ms later.
      ref.listenManual<String?>(
        settingsProvider.select((s) => s.activeWalletId),
        (prev, next) {
          if (prev == null || next == null || prev == next || !mounted) {
            return;
          }
          // Reset the foregrounded-card selection so the ambient tint +
          // glow don't carry stale state (e.g. "USDC blue" tint lingering
          // on a signer/hardware wallet that has no USDC card).
          ref.read(selectedWalletCardProvider.notifier).state =
              WalletCardType.bitcoin;
          // Reset the home-view scope. The carousel's spending sub-
          // pages set scope to 'all' / 'spending-btc' / 'spending-usdc';
          // if the user switches to a savings wallet via the wallet-
          // switcher sheet (NOT via the carousel), the scope would
          // carry forward and force `HomeAnalyticsWidget` to chart
          // the spending wallet's data on a hardware page.
          ref.read(homeViewScopeProvider.notifier).state = null;
          // Sync the viewed wallet to the new active. The carousel
          // updates `viewedWalletIdProvider` on swipe, but a sheet-
          // driven wallet switch bypasses the carousel — without
          // this, `viewedWalletBalanceProvider` keeps returning the
          // previous wallet's balance (the analytics widget then
          // shows the spending wallet's chart on a hardware page).
          ref.read(viewedWalletIdProvider.notifier).state = next;
          // Defer the heavy sync work past the swipe + first-paint of
          // the new wallet's cached state. Carousel transition is
          // ~240ms; previously we kicked sync at 400ms which left only
          // ~160ms of breathing room before BDK / Spark / Polymarket
          // refresh churn started cascading provider rebuilds — which
          // is exactly when the user's fingers are still moving and
          // the jitter is most noticeable. 700ms + post-frame puts the
          // sync after the new wallet's UI has painted from cache, so
          // any frame skips that follow are invisible.
          //
          // No explicit invalidate of balance/transaction providers
          // either: both already listen to `activeWalletId` with
          // `fireImmediately: true` and refresh themselves on change.
          // The previous `invalidate` calls disposed the live
          // notifiers, briefly emitting empty state to every consumer,
          // and the auto-listener immediately re-read the same cache
          // slot — double work and a visible flash.
          _walletSwitchDebounce?.cancel();
          _walletSwitchDebounce = Timer(const Duration(milliseconds: 700), () {
            if (!mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              BackgroundSyncService().restart();
            });
          });
        },
      );

      // The USDB auto-swap listeners are gone with the Flashnet Earn
      // product: the only rail that ever settled USDB into the wallet
      // (the Cash App onramp sheet) was already dead code, and with the
      // Flashnet AMM removed there is no swap path to run anyway.
    });
  }

  /// Initialize Polymarket account (Safe wallet + approvals) during loading.
  /// Runs silently in background — errors are swallowed.
  Future<void> _initPolymarketAccount() async {
    try {
      final settings = ref.read(settingsProvider);
      // Only for Spark wallets
      final wallet = settings.activeWallet;
      if (wallet == null || !wallet.isSparkWallet) return;

      // Passkey wallets never persist a seed; the resolver derives it on
      // demand through the wallet's own vintage and label, so a
      // multi-wallet user's Safe stays keyed to THIS wallet's seed.
      // Nothing resolves while the session is locked.
      final mnemonic = await resolveBip39MnemonicFor(wallet,
          access: SeedAccess.automatic, session: ref.read(seedSessionProvider));
      if (mnemonic == null || mnemonic.isEmpty) return;

      await provisionPolymarketAccount(
          mnemonic: mnemonic,
          walletId: wallet.id,
          evmDerivationVersion: wallet.evmDerivationVersion);
    } catch (_) {
      // Silent — will be retried when user opens Polymarket screen
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _headerAnimController.dispose();
    _entranceController.dispose();
    _walletSwitchDebounce?.cancel();
    _pushPermissionTimer?.cancel();
    super.dispose();
  }

  Animation<double> _staggered(int index) {
    const count = 6;
    final start = (index * 0.12).clamp(0.0, 0.6);
    final end = (start + (1.0 / count) + 0.3).clamp(start + 0.01, 1.0);
    return CurvedAnimation(
      parent: _entranceController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  /// Drive the persistent shell nav bar's hide/reveal from this screen's
  /// scroll. Mirrors the old KuteTopNavBar scroll logic exactly: reveal near
  /// the very top (so the bar can never get stuck hidden), hide on scroll
  /// DOWN (reverse), reveal on scroll UP (forward).
  void _updateNavBarHidden() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    void setHidden(bool v) {
      if (ref.read(navBarHiddenProvider) != v) {
        ref.read(navBarHiddenProvider.notifier).state = v;
      }
    }

    if (pos.pixels <= 24) {
      setHidden(false);
      return;
    }
    switch (pos.userScrollDirection) {
      case ScrollDirection.reverse:
        setHidden(true);
        break;
      case ScrollDirection.forward:
        setHidden(false);
        break;
      case ScrollDirection.idle:
        break;
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    _updateNavBarHidden();
    final offset = _scrollController.offset;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;
    // Reduce Motion (WCAG 2.3.3): the top-bar hide/reveal slide is a
    // decorative transition. When reduce-motion is on, snap the header
    // controller to its target instead of running the easeInOutCubic
    // slide — the bar still appears/disappears, just without the glide.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    void showHeader() => reduceMotion
        ? _headerAnimController.value = 1.0
        : _headerAnimController.forward();
    void hideHeader() => reduceMotion
        ? _headerAnimController.value = 0.0
        : _headerAnimController.reverse();

    // Cross-fade boundary: flip the condensed-balance flag only when we
    // cross the collapse threshold so the swap fires once, not per frame.
    final collapsed = offset > _kBalanceCollapseThreshold.h;
    final tintCrossed = (_scrollOffset <= 0 && offset > 0) ||
        (_scrollOffset > 0 && offset <= 0);
    if (tintCrossed || collapsed != _balanceCollapsed) {
      setState(() {
        _scrollOffset = offset;
        _balanceCollapsed = collapsed;
      });
    } else {
      _scrollOffset = offset;
    }

    // Reveal whenever we're near the top — covers wallet-switch
    // remounts that briefly reset the offset to 0 with the header
    // still in the hidden state.
    if (offset < 60 || offset < 0) {
      if (!_headerVisible) {
        _headerVisible = true;
        showHeader();
      }
      return;
    }

    // Once the hero balance has collapsed, the top bar carries the
    // pinned condensed balance — keep it on screen regardless of scroll
    // direction so the balance never slides away or hides entirely.
    if (_balanceCollapsed) {
      if (!_headerVisible) {
        _headerVisible = true;
        showHeader();
      }
      return;
    }

    // Sensitivity lowered from 5 → 2 so inertial scrolls on
    // shorter pages (hardware / watch-only / tracked, which have
    // less content) reliably exceed the threshold and trigger the
    // hide animation.
    if (delta > 2 && _headerVisible) {
      _headerVisible = false;
      hideHeader();
    } else if (delta < -2 && !_headerVisible) {
      _headerVisible = true;
      showHeader();
    }
  }

  // Scroll-metrics notifications fire when the scrollable's min/max
  // extents change without the user scrolling — e.g. Activity section
  // collapses and the content becomes shorter than the viewport. That
  // leaves the scroll offset clamped against a now-smaller maxExtent,
  // `_onScroll` never refires, and the hidden header stays hidden.
  // Catch it here and reveal the header when the scrollable can no
  // longer be scrolled past the reveal threshold (or content got
  // shorter than viewport entirely).
  bool _onScrollMetrics(ScrollMetricsNotification notification) {
    final metrics = notification.metrics;
    final shortContent = metrics.maxScrollExtent <= 0;
    final nearTop = metrics.pixels < 80;
    if ((shortContent || nearTop) && !_headerVisible) {
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      setState(() {
        _headerVisible = true;
        if (reduceMotion) {
          _headerAnimController.value = 1.0;
        } else {
          _headerAnimController.forward();
        }
      });
    }
    return false;
  }

  Future<void> _handleRefresh() async {
    // Pull-to-refresh: clear the stream-fresh guard so the next poll's
    // balance write is accepted, then run a full sync. Users hit this
    // when their balance looks wrong and they want a forced re-fetch.
    // Drive the mascot into `refreshing` while the sync is in flight.
    TrackingService.pullToRefreshExecuted(screen: 'home');
    ref.read(kuteStateProvider.notifier).setRefreshing(true);
    try {
      ref.read(balanceNotifierProvider.notifier).invalidateStreamFreshness();
    } catch (_) {}
    // Drop the cached predictions feed so the markets list re-fetches
    // alongside the balance/positions. `polymarketTradingProvider.refresh()`
    // (called by performFullUpdate) only re-pulls positions + USDC
    // balance — the events family lives on a separate fetch path.
    try {
      ref.invalidate(polymarketEventsProvider);
    } catch (_) {}
    // Fire the heavy sync but cap how long the spinner stays up. The
    // RefreshIndicator hides the moment THIS future resolves. We were
    // awaiting `performFullUpdate` directly — if any of its 8 inner
    // fetches silently hung (Breez SDK in a bad state, an external
    // API stuck), the spinner stuck with it. Capping at 4 s gives the
    // user a "we tried" affordance; the sync continues running in the
    // background and the cache notifier updates the UI when it lands.
    final syncFuture = () async {
      try {
        await ref
            .read(backgroundSyncNotifierProvider.notifier)
            .performFullUpdate();
      } catch (_) {}
    }();
    try {
      await syncFuture.timeout(const Duration(seconds: 4));
    } catch (_) {
      // Timeout — sync is still running, just stop blocking the
      // spinner. Provider notifications will update the UI when
      // results arrive.
    }
    // The user can pull-to-refresh then immediately navigate away (or the
    // wallet can switch) during the up-to-4s await above, disposing this
    // widget. Touching `ref` after that throws
    // `StateError: Cannot use "ref" after the widget was disposed`.
    if (!mounted) return;
    ref.read(kuteStateProvider.notifier).setRefreshing(false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // Pre-flush providers so child widgets don't trigger cascading
    // markNeedsBuild notifications on siblings during their first build.
    ref.read(balanceNotifierProvider);
    ref.read(transactionNotifierProvider);
    ref.read(polymarketTradingProvider);
    // Bootstrap the autonomous pending-bet watcher. It's a Provider, so
    // reading it once instantiates the long-lived listener that fires
    // a queued bet when USDC funds land — even if the user has
    // dismissed the PendingBetOverlay in the meantime.
    ref.read(pendingBetAutoFireProvider);
    // Autonomous claimer — redeems resolved Polymarket positions as
    // soon as they turn redeemable (user decision: auto-claim is back,
    // the Claim tap is no longer required).
    ref.read(claimAutoFireProvider);

    final (activeWallet, country) =
        ref.watch(settingsProvider.select((s) => (s.activeWallet, s.country)));

    if (activeWallet == null) {
      // No active wallet selected (boot before settings populated, or
      // every wallet was just deleted). Render an empty scaffold so
      // the screen exists; nothing to show until a wallet is chosen.
      return Scaffold(backgroundColor: c.background);
    }

    if (activeWallet.isSigner) {
      // Legacy air-gapped signer wallet (feature removed). The settings
      // loader snaps activeWalletId to a spending wallet on boot, so this
      // is only reachable on a device whose ONLY wallet is a signer.
      // Render the same empty scaffold as the no-wallet state.
      return Scaffold(backgroundColor: c.background);
    }

    final bool needsBackup =
        ref.watch(pendingSpendingWalletBackupProvider) != null;
    final bool isEuropeanUser = country != null &&
        ['AT', 'BE', 'DE', 'ES', 'FR', 'IT', 'NL', 'PT'].contains(country);

    // Milestone overlay disabled — milestones still claim silently
    // (the OnceFlagsService gates analytics events) but we don't
    // surface a slide-in card on the home screen. Per user direction:
    // no celebration UI on milestones.

    final bool isWatchOnly = activeWallet.isWatchOnly;
    final bool isHardware = activeWallet.isHardware;

    return Scaffold(
      extendBody: true,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // Top-of-screen pulsating red gradient. Only paints when
            // the active wallet is in savings mode (hardware /
            // watch-only / tracked) — see SavingsModeAppTopTint.
            // Sits BEHIND the SafeArea below so it tints the
            // status-bar zone + the wallet-switcher chip without
            // covering tap targets (IgnorePointer).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: const SavingsModeAppTopTint(),
            ),
            KuteDockHost(
              dockBuilder: (onHeightChanged) =>
                  HomeDock(onHeightChanged: onHeightChanged),
              body: SafeArea(
                bottom: false,
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: _onScrollMetrics,
                  child: RefreshIndicator(
                    onRefresh: _handleRefresh,
                    color: c.accent,
                    backgroundColor: c.surface,
                    edgeOffset: 68.h,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics()),
                      slivers: [
                        // Clears the integrated top nav bar. Sized to the nav's
                        // ~54.h content band + ~10.h breathing room (the scroll
                        // view already sits below the safe-area inset).
                        SliverToBoxAdapter(child: SizedBox(height: 64.h)),

                        // Predictions are NOT surfaced on the home screen
                        // — they live entirely in the dedicated Predictions
                        // tab so the home stays focused on the wallet
                        // (the primary surface for the vast majority of
                        // sessions).

                        const SliverToBoxAdapter(
                            child: SeedUnavailableBanner()),

                        if (needsBackup)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding:
                                  EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                              child: const SecurityActionCard(),
                            ),
                          ),

                        SliverToBoxAdapter(
                          child: _EntranceTransition(
                            animation: _staggered(0),
                            child: _WalletDeckWrapper(
                              isHardware: isHardware,
                              isWatchOnly: isWatchOnly,
                              isEuropean: isEuropeanUser,
                            ),
                          ),
                        ),

                        // Shared action row — Deposit / Receive / Send /
                        // Move / Pay Link, scoped to whichever card is
                        // currently selected (BTC, USDC, or a cold wallet).
                        // Lives outside the cards so the cards stay pure
                        // identity surfaces and the action row is the
                        // single shared affordance across all of them.
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                            child: _HomeActions(),
                          ),
                        ),

                        const _ActivitySection(),

                        // Clears the floating dock: KuteDockHost reports
                        // dock + 12.h as the bottom padding, plus 12.h.
                        SliverToBoxAdapter(
                            child: Builder(
                                builder: (context) => SizedBox(
                                    height:
                                        MediaQuery.paddingOf(context).bottom +
                                            12.h))),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // The integrated top nav bar now lives ONCE in the persistent
            // nav shell (lib/screens/app_shell.dart), mounted above all four
            // tab pages — it is no longer painted per-screen here. The
            // 64.h top sliver above still clears the space it occupies, and
            // this screen's scroll listener drives its hide/reveal through
            // navBarHiddenProvider (see _onScroll).

            // The Ask Sal dock (frost band + pill + "+") is mounted by
            // KuteDockHost above, shared with every other dock host.
          ],
        ),
      ),
    );
  }
}

/// Loading row rendered at the top of Active Predictions while a bet is
/// being placed. Clears automatically once the real CLOB-sourced position
/// matching the same tokenId appears (`ref.listen` in the parent) or the
/// placement errors out (auto-cleared after a short window by the
/// notifier).

/// Row rendered at the top of Active Predictions for a resolved, unclaimed
/// winning position. Replaces the old auto-claim flow — the user has to
/// tap "Claim" explicitly so they can see what's being paid out. While
/// the on-chain redemption is in flight the button shows a loader; if
/// anything throws we surface the error so the user can retry instead of
/// silently leaving the bet stuck.
class _ClaimablePositionRow extends ConsumerStatefulWidget {
  final PolymarketPosition position;

  const _ClaimablePositionRow({required this.position});

  @override
  ConsumerState<_ClaimablePositionRow> createState() =>
      _ClaimablePositionRowState();
}

class _ClaimablePositionRowState extends ConsumerState<_ClaimablePositionRow> {
  bool _claiming = false;

  Future<void> _handleClaim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    HapticFeedback.mediumImpact();
    final pos = widget.position;
    TrackingService.polymarketRedeemInitiated(
        marketId: pos.marketId, trigger: 'manual', surface: 'home');
    final navigator = Navigator.of(context, rootNavigator: true);
    try {
      final credited =
          await ref.read(polymarketTradingProvider.notifier).redeemPosition(
                conditionId: pos.marketId,
                trigger: 'manual',
                surface: 'home',
              );
      if (!mounted) return;
      // Success haptic fires in the overlay's entrance (the shared
      // choke point for the Apple Pay two-beat) — not here.
      // Full-screen success overlay (matches the convert/sell pattern).
      // Snackbar wasn't celebratory enough for a winning claim.
      pushClaimPlacedOverlay(
        navigator: navigator,
        marketQuestion: pos.marketQuestion,
        outcome: pos.outcome,
        amountUsd: credited,
      );
    } catch (e) {
      // redeemPosition reports its own failures; this covers anything
      // thrown before/around it, once.
      if (!PolymarketTradingNotifier.redeemFailureTracked(e)) {
        TrackingService.polymarketRedeemFailed(
          marketId: pos.marketId,
          reason: TrackingService.errorCategory(e),
          trigger: 'manual',
          surface: 'home',
        );
      }
      if (!mounted) return;
      setState(() => _claiming = false);
      showMessageSnackBar(
        context: context,
        message: polymarketErrorCopy(context, e),
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pos = widget.position;
    final won = pos.won ?? (pos.currentPrice >= 0.99);
    const accent = Color(0xFF47C97A);
    // Crest-first via the shared resolver (sports positions carry the
    // generic ball as marketImage); PolyCrestImage because crest URLs are
    // frequently .svg, which raster-only Image.network can't decode.
    final image = positionCrestImage(ref, pos);
    final iconFallback = Center(
      child: Icon(Icons.emoji_events_rounded, color: accent, size: 20.sp),
    );

    return Container(
      color: c.surface,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Row(
        children: [
          Container(
            width: 40.sp,
            height: 40.sp,
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(10.r),
            ),
            clipBehavior: Clip.antiAlias,
            child: image != null && image.isNotEmpty
                ? PolyCrestImage(
                    url: image,
                    size: 40.sp,
                    radius: 10.r,
                    fallback: iconFallback,
                  )
                : iconFallback,
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pos.marketQuestion,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 6.h),
                Row(
                  children: [
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Text(
                        won ? 'WON' : 'RESOLVED',
                        style: TextStyle(
                          color: accent,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    SizedBox(width: 6.w),
                    Flexible(
                      child: Text(
                        pos.outcome,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: _claiming ? null : _handleClaim,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 34.sp,
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(6.r),
              ),
              alignment: Alignment.center,
              child: _claiming
                  ? SizedBox(
                      width: 16.sp,
                      height: 16.sp,
                      child: LoadingAnimationWidget.staggeredDotsWave(
                        color: Colors.white,
                        size: 16.sp,
                      ),
                    )
                  : Text(
                      context.l10n.claim,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivitySection extends ConsumerWidget {
  const _ActivitySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Activity follows the active wallet — same source as the
    // dedicated History screen so what the user sees here matches
    // what they see on the tap-in. Hardware-mode Polymarket filtering
    // happens inside TransactionList itself.
    final activeWallet =
        ref.watch(settingsProvider.select((s) => s.activeWallet));
    final isSavings = (activeWallet?.isHardware ?? false) ||
        (activeWallet?.isWatchOnly ?? false) ||
        (activeWallet?.isExternalAddress ?? false);
    final hasTransactions = ref.watch(transactionNotifierProvider.select((t) {
      final list = t.homeTransactionsSorted;
      if (!isSavings) return list.isNotEmpty;
      return list.any((tx) =>
          tx is! PolymarketTransaction &&
          tx is! PolymarketUsdcReceive &&
          tx is! UsdbTokenTransaction);
    }));
    // Polymarket positions live on the per-user Safe — not per-wallet.
    // Surface them on every carousel page so the user always sees
    // their open bets. `.select(.isNotEmpty)` so every list mutation
    // doesn't rebuild this gate — only transitions across the empty
    // boundary do.
    final hasActivePositions = ref
        .watch(polymarketActivePositionsProvider.select((p) => p.isNotEmpty));
    final hasClaimablePositions = ref.watch(
        polymarketClaimablePositionsProvider.select((p) => p.isNotEmpty));
    final hasPlacing =
        ref.watch(placingPolymarketBetProvider.select((p) => p.isNotEmpty));
    // Hot Predictions activity belongs to Spending Wallet; it cannot suppress
    // the empty state of an unrelated Jade/Ledger/watch-only Bitcoin account.
    final hasPredictionsOnCurrentWallet = !isSavings &&
        (hasActivePositions || hasClaimablePositions || hasPlacing);

    final showEmptyState = !hasTransactions && !hasPredictionsOnCurrentWallet;
    // While the Breez SDK is still connecting and there is nothing to
    // show, render shimmer transaction rows instead of the empty state
    // (or a blank list) — the wallet is waking up, not empty. Savings
    // wallets don't ride Breez, so they keep their immediate render.
    final breezWaking =
        !isSavings && showEmptyState && ref.watch(breezSDKProvider).isLoading;

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Always render the Activity section header — even when
          // there are no transactions yet. An empty wallet shows the
          // header + a small empty-state below; gating the header on
          // tx-present made the home feel anchorless for new wallets.
          // ONE merged section behind a pill strip (user decision):
          // Activity | Balance | Breakdown (plus whatever the wallet
          // scope adds) — the old stacked Activity header + separate
          // analytics block are gone. No Price on the main screen
          // (owner decision). Breakdown is the spending wallet's money
          // in and out by kind, so only the hot Spark wallet gets it.
          // The activity child is pre-resolved here because its
          // skeleton/empty states hang off Home-local providers.
          RepaintBoundary(
            child: HomeAnalyticsWidget(
              surface: 'home',
              showPrice: false,
              breakdownChild: homeBreakdownChild(activeWallet),
              onSeeAllActivity: () =>
                  showActivityHistory(context, source: 'home'),
              activityChild: breezWaking
                  ? const _ActivitySkeleton()
                  : showEmptyState
                      ? const NoActivityState()
                      : const RepaintBoundary(
                          child: TransactionList(emptyState: NoActivityState()),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer placeholder for the hero balance while the Breez SDK is
/// still connecting and no cached balance exists. Mirrors the Receive
/// screen's QR shimmer palette so "loading" reads the same everywhere.
class _HeroBalanceSkeleton extends StatelessWidget {
  const _HeroBalanceSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 4.h),
      child: KuteSkeleton(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonCircle(40.w),
                SizedBox(width: 10.w),
                SkeletonBar(180.w, 44.h, radius: 12.r),
              ],
            ),
            SizedBox(height: 8.h),
            SkeletonBar(90.w, 16.h, radius: 8.r),
          ],
        ),
      ),
    );
  }
}

/// Shimmer placeholder rows for the Activity section while the Breez
/// SDK connects — the wallet is waking up, not empty, so we show the
/// shape of the transaction rows that are (possibly) about to appear
/// instead of the empty state or a blank gap.
class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonRowList(count: 3);
  }
}

/// Combines the Bitcoin wallet card + Convert swap button + USD balance card
/// into one sliver so the floating button can visually overlap both cards
/// (Stack with Clip.none doesn't cross sliver boundaries cleanly).
/// Wraps the main wallet balance card with peek-from-behind tabs
/// for the user's other wallets (Monzo-style multi-account deck).
/// Peek tabs render with a slight upward offset so their top edge
/// is visible above the front card. Tapping a peek tab switches
/// the active wallet, which causes the front card to repopulate
/// with that wallet's balance.
class _WalletDeckWrapper extends ConsumerWidget {
  final bool isHardware;
  final bool isWatchOnly;
  final bool isEuropean;

  const _WalletDeckWrapper({
    required this.isHardware,
    required this.isWatchOnly,
    required this.isEuropean,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeWallet =
        ref.watch(settingsProvider.select((s) => s.activeWallet));
    // Reduce Motion (WCAG 2.3.3): the card-swap slide/scale/fade is a
    // decorative transition between wallets. Collapse it to an instant
    // swap when reduce-motion is on.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    // Always-BTC architecture: every wallet — spending or savings —
    // renders the plain Bitcoin card with the simple cross-fade. The
    // old `_SpendingDeck` BTC↔USDC peek-and-swap is gone. USDC dust
    // (sub-Orchestra-minimum residual from claims) lives on the
    // Portfolio Split tab, never on the home card.
    return AnimatedSwitcher(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: _deckTransition,
      child: KeyedSubtree(
        key: ValueKey('front-${activeWallet?.id ?? 'none'}'),
        child: const _BitcoinAccountFront(),
      ),
    );
  }

  /// Card-swap transition — Monzo-style lateral card switch.
  ///
  /// For the incoming child `anim` runs 0→1; for the outgoing child
  /// (wrapped in `ReverseAnimation` by `AnimatedSwitcher`) it runs 1→0.
  /// A single tween therefore produces a symmetric pair of motions
  /// that travel along the same lateral axis but at different times:
  ///   - Incoming: enters from ~64dp to the right, slides into place
  ///     while scaling 0.95→1.0 and fading 0→1.
  ///   - Outgoing: drifts ~64dp to the right out of the slot, scales
  ///     1.0→0.95, fades 1→0.
  ///
  /// Curve: `easeOutCubic` — fast leading edge, gentle settle. The
  /// duration is brisk (~460ms) so the swap feels responsive to the
  /// tap, matching Monzo's account-switcher cadence.
  static Widget _deckTransition(Widget child, Animation<double> anim) {
    final eased = CurvedAnimation(
      parent: anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return AnimatedBuilder(
      animation: eased,
      builder: (context, _) {
        final t = eased.value.clamp(0.0, 1.0);
        // Lateral travel: 64dp offset from the slot, snapping into
        // place. Short distance = quick read; long enough that the
        // motion registers as a swap, not a flicker.
        final dx = (1.0 - t) * 64.0;
        // Scale: subtle 0.95 → 1.0. Just enough that the landing card
        // visibly "claims" the slot.
        final scale = 0.95 + 0.05 * t;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Lightweight descriptor for one peek in the unified deck. Kept
/// as a plain data class so the deck-building loop in
/// `_WalletDeckWrapper.build` can flatten BTC + USDC + cold wallets
/// into a single ordered list before painting the Stack.

/// Neutral peek card surfaced above the active spending asset.
/// Mirrors the Monzo summary tile shape but with the home's white
/// surface chrome (no brand-color fill, per the latest direction).
///
/// Stateful so the peek can render an explicit tactile press scale
/// while the finger is down. Earlier the swap animation kicked in
/// purely on the active-card slot which read as "the wrong thing is
/// reacting to my tap." A 0.96 compress on tap-down anchors the
/// feedback to the actual touched element.
/// Full-bleed Bitcoin front card used when BTC is the active spending
/// asset. Mirrors the USDC card layout so the two read as siblings,
/// but with Bitcoin orange accent + ₿ icon + sats-native balance.
class _BitcoinAccountFront extends ConsumerStatefulWidget {
  const _BitcoinAccountFront();

  @override
  ConsumerState<_BitcoinAccountFront> createState() =>
      _BitcoinAccountFrontState();
}

class _BitcoinAccountFrontState extends ConsumerState<_BitcoinAccountFront>
    with SingleTickerProviderStateMixin {
  // Pulse animation fires whenever the sats balance changes — same
  // semantics the old card-chrome had (`SparkWalletCard._pulseController`).
  // 350 ms scale + soft glow flash on the headline so an inbound
  // payment is visually acknowledged without being noisy.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  int _prevSats = -1;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Reduce Motion (WCAG 2.3.3): the balance-change pulse (scale + glow
    // flash) is a decorative one-shot acknowledgement, not information.
    // Skip firing it when the OS reduce-motion toggle is on.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final balanceState = ref.watch(balanceNotifierProvider);
    final btcSats =
        balanceState.sparkBitcoinbalance + balanceState.onChainBtcBalance;
    // Wallet still waking up: while the Breez SDK is connecting AND we
    // have nothing cached to show (a genuinely-zero fresh wallet or a
    // cold boot before the balance cache hydrates), render a shimmer
    // skeleton instead of a blank/0 hero. Same treatment as the QR
    // placeholder on Receive, adapted to the balance (user decision).
    // Once the SDK resolves, a real 0 renders as a real 0. Watching is
    // subscribe-only here: `completeUnlock` primes the connect on every
    // unlock path, so this never initiates it.
    final breezWaking = ref.watch(breezSDKProvider).isLoading;
    if (breezWaking && btcSats == 0) {
      return const _HeroBalanceSkeleton();
    }
    // First real balance of this process (once; the key is consumed).
    // `source` says whether the cached balance or the live SDK got the
    // number on screen. Deferred to after paint; no amount is sent.
    if (LatencyTracker.isRunning(LatencyKeys.balanceLoaded)) {
      final source = breezWaking ? 'cache' : 'sdk';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        LatencyTracker.stop(LatencyKeys.balanceLoaded,
            params: {'source': source});
      });
    }
    // Reduce-motion guards the decorative balance-change pulse (nav).
    if (!reduceMotion && _prevSats >= 0 && btcSats != _prevSats) {
      _pulse.forward(from: 0);
    }
    _prevSats = btcSats;
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    final selectedCurrency =
        ref.watch(settingsProvider.select((s) => s.currency));
    final isBalanceVisible =
        ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final fiatPerBtc =
        ref.watch(selectedCurrencyProvider(selectedCurrency)).toDouble();
    final rawBtcFiat = (btcSats / 1e8) * fiatPerBtc;
    // Guard against a non-finite conversion (NaN/Infinity) — e.g. rates
    // not yet loaded on a cold first-login, or a 0/garbage rate.
    // `NumberFormat.format` THROWS on NaN/Infinity, which crashes the
    // home balance header exactly while it renders with a blank balance.
    final btcFiat = rawBtcFiat.isFinite ? rawBtcFiat : 0.0;
    final fiatStr = isBalanceVisible
        ? NumberFormat.simpleCurrency(name: selectedCurrency, decimalDigits: 2)
            .format(btcFiat)
        : '••••••••';
    final btcNumberStr =
        isBalanceVisible ? btcSats.toFormattedString(btcFormat) : '••••••••';
    // Hero balance: Bitcoin logo on the left, the BTC/sats amount as
    // the big 56.sp headline, fiat value as the small secondary line
    // directly underneath. The unit suffix ("sats" / "BTC") used to
    // trail the number — removed per spec; the BTC icon on the left
    // already signals the unit, and the digits read cleaner on their
    // own. FittedBox keeps long BTC-format strings ('0.00 002 511')
    // from overflowing the row. Matches the wallet-detail and
    // portfolio total balance card hierarchy: bitcoin = hero, fiat =
    // small line below.
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 4.h),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.mediumImpact();
          // Reports `home_balance_visibility_toggled` (from/to level,
          // never an amount); every tap advances the cycle one step.
          cycleBalancePrivacyTracked(ref, surface: 'home_hero');
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo + digits hug each other as one tight unit. No mirror
            // SizedBox on the right — the Row sizes to its content and
            // is centered horizontally by the parent Column. FittedBox
            // still scales the number down when the BTC format string
            // grows long.
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                final t = _pulse.value;
                final scale = 1.0 + (math.sin(t * math.pi) * 0.05);
                return Transform.scale(
                  scale: scale,
                  child: child,
                );
              },
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // BIP-177: lead the balance with a typographic ₿ prefix
                    // (matching the Send screen) rather than a separate orange
                    // circle glued to the number — modern + consistent app-wide.
                    Text(
                      '₿',
                      style: TextStyle(
                        fontSize: 44.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.0,
                        height: 1.0,
                        color: c.textPrimary,
                      ),
                    ),
                    SizedBox(width: 2.w),
                    AnimatedBtcAmountText(
                      text: btcNumberStr,
                      dim: isBalanceVisible,
                      style: TextStyle(
                        fontSize: 56.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.4,
                        height: 1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: c.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                      brightColor: c.textPrimary,
                      dimColor: c.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 6.h),
            AnimatedBalance(
              text: fiatStr,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Monzo-style action pill — white background, brand text/icon,
/// stadium shape. Used at the bottom of the BTC and USDC front
/// cards for "Add money / Send / ..." style actions.

/// Coming-soon placeholder for the future Bank Account & Card spending
/// surface (KYC required). Tapping fires a coming-soon snack and a
/// Shared home action row. Sits below the wallet card stack; the
/// chips act on whichever card is currently foregrounded (asset =
/// `selectedWalletCardProvider`, wallet = `activeWallet`).
///
/// Spending wallet — BTC selected:
///   Deposit (BTC wallet picker) | Receive (Bitcoin Network) |
///   Send | Move | Pay Link
/// Spending wallet — USDC selected:
///   Deposit (move sheet) | Receive (Polygon Network) | Send |
///   Move | Pay Link
/// Cold wallet (software / hardware / watch-only):
///   Receive | Send — Send routes through the wallet's own BDK scope
///   (software wallets sign locally, hardware and watch-only sign
///   externally). Scan stays off: the smart scanner targets spending.
/// Tracked address / paired signer:
///   Receive (only) — nothing to sign with. Tap a disabled chip →
///   snackbar prompts to switch to the spending account.
/// Home's floating dock: the card's two money verbs and the search square.
/// Public so the dock can be mounted on its own (KuteDockHost, tests).
class HomeDock extends StatelessWidget {
  final ValueChanged<double>? onHeightChanged;
  const HomeDock({super.key, this.onHeightChanged});

  @override
  Widget build(BuildContext context) =>
      _HomeActions(bottomBar: true, onHeightChanged: onHeightChanged);
}

class _HomeActions extends ConsumerWidget {
  final bool bottomBar;
  final ValueChanged<double>? onHeightChanged;
  const _HomeActions({this.bottomBar = false, this.onHeightChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeWallet =
        ref.watch(settingsProvider.select((s) => s.activeWallet));
    final selectedAsset = ref.watch(selectedWalletCardProvider);
    final isCold = activeWallet != null &&
        (activeWallet.isBitcoinSoftware ||
            activeWallet.isHardware ||
            activeWallet.isWatchOnly ||
            activeWallet.isExternalAddress);
    final isUsdc = !isCold && selectedAsset == WalletCardType.usdc;
    void fundPredictions(bool deposit) {
      if (activeWallet == null ||
          ref.read(settingsProvider).activeWalletId != activeWallet.id) {
        showMessageSnackBar(
            context: context,
            message: context.l10n.walletActionsWalletChanged,
            error: true);
        return;
      }
      final decision = ref
          .read(runtimeCapabilitiesProvider)
          .decision('polymarket.${deposit ? 'deposit' : 'withdraw'}');
      if (!decision.allowed) {
        TrackingService.track('feature_unavailable_shown', params: {
          'feature': deposit ? 'predictions_deposit' : 'predictions_withdraw',
          'reason': decision.regionRestricted
              ? 'region_restricted'
              : 'capability_disabled',
          'surface': 'home_dock',
        });
        showCapabilityDecisionSheet(context, decision);
        return;
      }
      showDepositSheet(context,
          lockedSide: deposit
              ? MoveLockedSide.depositToPredictions
              : MoveLockedSide.withdrawFromPredictions);
    }

    if (bottomBar) {
      // Home's dock verbs follow the card it is showing: Send and Receive on
      // the bitcoin cards, Portfolio and Withdraw on the Predictions (USDC)
      // card, whose Deposit is the top button (owner decision: each job has
      // one home).
      final source = isUsdc ? 'home_predictions' : 'home';
      return KuteBottomActionBar(
        source: source,
        onHeightChanged: onHeightChanged,
        actions: activeWallet == null
            ? const []
            : isUsdc
                ? [
                    KuteDockAction(
                        icon: Icons.pie_chart_rounded,
                        label: context.l10n.walletPortfolioAction,
                        trackingId: 'portfolio',
                        strongIcon: true,
                        onTap: () => Navigator.of(context, rootNavigator: true)
                            .push(MaterialPageRoute(
                                builder: (_) => const OpenInvestmentsScreen(
                                    product: InvestmentsProduct.predictions)))),
                    KuteDockAction(
                        icon: Icons.north_east_rounded,
                        label: context.l10n.withdraw,
                        trackingId: 'withdraw',
                        onTap: () => fundPredictions(false)),
                  ]
                : bitcoinWalletDockActions(context, ref, activeWallet),
        // The square is search, scoped to the card: everything on the
        // bitcoin cards, the prediction markets on the Predictions card.
        // The same results-first sheet every venue dock opens (searchFirst):
        // only the category differs. On the bitcoin cards it used to open
        // the Sal intro instead, which read as a different screen.
        onSearch: activeWallet == null
            ? null
            : () => showKuteSearch(context,
                source: source,
                initialCategory: isUsdc
                    ? SearchCategory.predictions
                    : SearchCategory.all,
                searchFirst: true,
                searchHint:
                    isUsdc ? context.l10n.searchPredictionsHint : null),
      );
    }
    if (activeWallet == null) return const SizedBox.shrink();
    if (!isUsdc) {
      return BitcoinWalletPrimaryActions(wallet: activeWallet, source: 'home');
    }
    // The Predictions card's top button is the venue's own Deposit button,
    // the one the Predictions tab wears; Portfolio is in the dock below.
    // Build was asked to go from Predictions and this row was the last
    // place it survived. The builder screen and its route stay.
    return VenueDepositButton(
        product: InvestmentsProduct.predictions,
        source: 'home_predictions',
        onTap: () => fundPredictions(true));
  }
}

class _EntranceTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const _EntranceTransition({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) {
        return Opacity(
          opacity: animation.value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1.0 - animation.value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
