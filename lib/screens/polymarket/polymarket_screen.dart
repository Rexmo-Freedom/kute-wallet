import 'dart:async';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/screens/shared/kute_blur.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/services/polymarket/polymarket_price_source.dart'
    show CryptoPriceFeed;
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/shared/market_pair_button.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';

import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_user_channel_provider.dart';
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/polymarket/components/poly_category_icons.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/poly_feed_utils.dart';
import 'package:kute/screens/polymarket/group_landing_screen.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show showDepositSheet, MoveLockedSide;
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/home/components/btc_predict_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:intl/intl.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';

/// THE deposit door for Predictions (user decision: always the Move sheet,
/// never the legacy quote sheet). When a bet intent is parked waiting on
/// funds, its amount prefills the slider so the user lands on exactly the
/// conversion they need; the intent then auto-fires when the USDC arrives.
///
/// While the policy withholds `polymarket.deposit` the door opens nothing
/// and says why instead, in the shared unavailable sheet.
void _openPredictionsDeposit(BuildContext context, WidgetRef ref) {
  final decision =
      ref.read(runtimeCapabilitiesProvider).decision('polymarket.deposit');
  if (!decision.allowed || decision.comingSoon) {
    showCapabilityDecisionSheet(context, decision);
    return;
  }
  final intent = ref.read(pendingPolymarketBetProvider);
  showDepositSheet(
    context,
    lockedSide: MoveLockedSide.depositToPredictions,
    initialTargetUsd:
        (intent != null && intent.amount > 0) ? intent.amount : null,
  );
}

const Color _kPolyGreen = AppColors.marketUp;
const Color _kPolyRed = AppColors.marketDown;

/// The Live pill's "Streams" subcategory: games in play with a stream.
const String _kLiveStreams = 'streams';

/// The games in play of one league, and the pill that names it.
typedef _LiveGroup = ({PolySub sub, List<PolymarketEvent> games});

class PolymarketScreen extends ConsumerStatefulWidget {
  final bool autoShowDeposit;
  final bool autoShowWithdraw;
  const PolymarketScreen(
      {super.key, this.autoShowDeposit = false, this.autoShowWithdraw = false});

  @override
  ConsumerState<PolymarketScreen> createState() => _PolymarketScreenState();
}

class _PolymarketScreenState extends ConsumerState<PolymarketScreen> {
  double _bottomDockHeight = 0;
  void _onDockHeightChanged(double height) {
    if (mounted && (_bottomDockHeight - height).abs() > 0.5) {
      setState(() => _bottomDockHeight = height);
    }
  }

  final _scrollController = ScrollController();

  /// The list on screen, for paging from the scroll listener.
  PolyFeedQuery? _feedQuery;

  // Coarse scroll-depth thresholds (percent) already reported this
  // session, so `polymarketListScrolled` fires at most once per bucket
  // crossed. Only the bucketed depth leaves the device — never a raw
  // pixel/percent offset.
  final Set<int> _reportedScrollDepths = <int>{};

  bool _sportsConnected = false;

  /// Coarse browse-depth engagement on the Predictions list. Fires the
  /// (previously caller-less) `polymarketListScrolled` helper at most
  /// once per 25/50/75/100% threshold crossed. Only the bucketed depth
  /// is sent — the raw offset/extent never leaves the device.
  /// Also reads the next page of the list on screen when the person
  /// nears its end.
  void _onScroll() {
    _updateNavBarHidden();
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions || pos.maxScrollExtent <= 0) return;

    if (pos.extentAfter < 900) _loadMore();

    final pct =
        ((pos.pixels / pos.maxScrollExtent) * 100).clamp(0, 100).round();
    for (final t in const [25, 50, 75, 100]) {
      if (pct >= t && _reportedScrollDepths.add(t)) {
        TrackingService.polymarketListScrolled(depthPct: t);
      }
    }
  }

  void _loadMore() {
    final q = _feedQuery;
    if (q == null) return;
    final feed = ref.read(polyBrowseFeedProvider(q));
    if (feed.done || feed.loading || feed.loadingMore) return;
    ref.read(polyBrowseFeedProvider(q).notifier).loadMore();
  }

  /// Last scroll offset + accumulated same-direction travel, feeding the
  /// nav-bar hide/reveal hysteresis below.
  double _navLastPixels = 0;
  double _navAccum = 0;

  /// Drive the persistent shell nav bar's hide/reveal from this tab's scroll.
  /// Reveal near the very top; otherwise only toggle after ~12px of travel
  /// in one direction (hysteresis) — the old per-tick direction flip made
  /// the bar flicker in and out on tiny finger reversals mid-scroll.
  void _updateNavBarHidden() {
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

  /// Root ProviderContainer captured while the element is live. `ref` is
  /// unusable inside [dispose] (Riverpod tears the element's ref down
  /// before `state.dispose()` runs on unmount — the prod Crashlytics fatal
  /// "Cannot use ref after the widget was disposed" at the old
  /// `ref.read(livePriceProvider...)` dispose line). The container itself
  /// outlives this widget (descendants unmount before the ProviderScope),
  /// so cleanup reads go through it instead.
  ProviderContainer? _container;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The widget can be disposed between initState and this post-frame
      // callback (fast navigation in/out of Predictions). Touching `ref`
      // after disposal throws `_assertNotDisposed`, so bail early.
      if (!mounted) return;
      // The 5-min BTC hero is the screen's above-the-fold anchor —
      // one event per screen mount, no market data attached.
      TrackingService.track('predict_hero_viewed');
      // Warm the builder code now so a slow connection has already
      // answered by the time the person places an order.
      unawaited(PolymarketBackendService.prefetchBuilderCode());
      _autoEnableTrading();
      if (widget.autoShowDeposit || widget.autoShowWithdraw) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          if (widget.autoShowDeposit) {
            _openPredictionsDeposit(context, ref);
          } else {
            _showWithdrawSheet(context, ref);
          }
        });
      }
      _setupSubscriptions();
    });
  }

  /// Subscribe to live prices and user channel reactively via ref.listen,
  /// so we never trigger side-effects inside build().
  void _setupSubscriptions() {
    // When trading state changes, subscribe position tokens to live prices + user channel.
    ref.listenManual(polymarketTradingProvider, (prev, next) {
      // A trading-state notification can land synchronously while this
      // widget is being unmounted (e.g. a `_silentRefresh` completing as
      // the user navigates away). Reading `ref` then throws
      // `_assertNotDisposed`, so guard on `mounted` before any `ref` use.
      if (!mounted) return;
      final state = next.valueOrNull;
      if (state == null || !state.isAuthenticated) return;

      final positionAssets = state.openPositions
          .map((p) => p.asset)
          .where((a) => a.isNotEmpty)
          .toList();

      if (positionAssets.isNotEmpty) {
        ref.read(livePriceProvider.notifier).addTokens(positionAssets);
        ref.read(userChannelProvider.notifier).subscribe(positionAssets);
      }
    }, fireImmediately: true);

    // NOTE: the 5-min Up/Down surfaces (hero banner + grid tiles)
    // register their own CLOB tokens via [LiveTokenScope], which also
    // re-registers on window rolls and releases on dispose — no
    // screen-level listenManual needed here.

    // Keep the user-channel WS provider alive for the whole screen
    // session WITHOUT rebuilding this 5000-line build on every frame it
    // emits (it used to be a bare ref.watch in build()).
    ref.listenManual(userChannelProvider, (_, __) {});
  }

  Future<void> _autoEnableTrading() async {
    final tradingState = ref.read(polymarketTradingProvider).valueOrNull;
    if (tradingState != null && tradingState.isAuthenticated) return;
    try {
      await ref.read(polymarketTradingProvider.notifier).enableTrading();
    } catch (_) {
      // Silent — user can retry via Top Up which also triggers enableTrading
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    // Close the live-price WebSocket when leaving Predictions. The notifier
    // calls `ref.keepAlive()` while subscribed (so scrolling the home
    // carousel doesn't tear it down), which means it would otherwise stay
    // connected — streaming price_change frames forever — after the user
    // navigates away. `unsubscribeAll` disconnects the socket and releases
    // the keepAlive link so the provider can auto-dispose.
    //
    // Read through the captured root container, NEVER `ref`: this runs
    // inside dispose, where the element's ref is already torn down (the
    // 1.3.8 prod fatal). Container beats the earlier captured-notifier
    // fix — a container read always resolves the CURRENT notifier, so a
    // provider rebuild between capture and dispose can't strand a stale
    // instance. try/catch as a last belt for full app-teardown where
    // even the container may already be disposed.
    try {
      _container?.read(livePriceProvider.notifier).unsubscribeAll();
    } catch (_) {}
    super.dispose();
  }

  // ───────────────────────── browse navigation ─────────────────────────

  /// Changes the list on screen.
  void _select(PolyBrowseSelection next) {
    ref.read(polyBrowseSelectionProvider.notifier).state = next;
  }

  /// The chip the selection's subcategory names, from the chips loaded.
  PolySub? _subFor(PolyBrowseSelection s, List<PolySub> subs) {
    for (final sub in subs) {
      if (sub.key == s.sub) return sub;
    }
    return null;
  }

  void _onPill(PolyPill pill) {
    HapticFeedback.selectionClick();
    final current = ref.read(polyBrowseSelectionProvider);
    if (pill == current.pill) return;
    TrackingService.track('category_pill_tapped',
        params: {'section': pill.key});
    _select(current.copyWith(pill: pill));
  }

  void _onSub(PolySub sub) {
    HapticFeedback.selectionClick();
    final current = ref.read(polyBrowseSelectionProvider);
    if (sub.key == current.sub) return;
    TrackingService.track('category_pill_tapped', params: {
      'section': current.pill.key,
      'subcategory': sub.route,
    });
    _select(current.copyWith(sub: sub.key));
  }

  /// "More": every category with its subcategories; a row shows its list.
  void _onMore(List<PolyPill> pills) {
    HapticFeedback.selectionClick();
    showPolyMoreSheet(
      context,
      pills: pills,
      selection: ref.read(polyBrowseSelectionProvider),
      onPick: (pill, sub) {
        final current = ref.read(polyBrowseSelectionProvider);
        if (pill == current.pill && sub.key == current.sub) return;
        TrackingService.track('category_pill_tapped', params: {
          'section': pill.key,
          'subcategory': sub.route,
        });
        _select(current.copyWith(pill: pill).copyWith(sub: sub.key));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final policy = ref.watch(runtimeCapabilitiesProvider);
    final canBrowse = policy.allows('polymarket.browse');

    // Watchlist leads the row once something is starred.
    final hasWatchlist = ref.watch(polyWatchlistProvider).isNotEmpty;
    final pills = [
      for (final p in PolyPill.values)
        if (polyPillOffered(p, policy) &&
            (p != PolyPill.watchlist || hasWatchlist))
          p
    ];
    var selection = ref.watch(polyBrowseSelectionProvider);
    if (!pills.contains(selection.pill)) {
      selection = selection.copyWith(pill: PolyPill.trending);
    }
    final pill = selection.pill;
    // The Live pill's list is the games in play; its subcategories are the
    // leagues playing right now, read off that same list.
    final liveEvents = canBrowse && pill == PolyPill.live
        ? ref
            .watch(polyBrowseFeedProvider(
                const PolyFeedQuery(pill: PolyPill.live)))
            .events
        : const <PolymarketEvent>[];
    final liveGroups = pill == PolyPill.live
        ? _liveGroups(liveEvents)
        : const <_LiveGroup>[];
    // "Streams": the games in play that can be watched, right after All.
    final anyStream = liveEvents.any((e) => e.hasLivestream);
    final subs = pill == PolyPill.live
        ? [
            if (liveGroups.length > 1 || anyStream) ...[
              const PolySub('all'),
              if (anyStream)
                PolySub(_kLiveStreams, label: l10n.polySubStreams),
              if (liveGroups.length > 1)
                for (final g in liveGroups) g.sub,
            ],
          ]
        : polySubsFor(ref, pill);
    // A league whose games have ended is no longer a choice.
    if (pill == PolyPill.live &&
        selection.sub != 'all' &&
        !subs.any((s) => s.key == selection.sub)) {
      selection = selection.copyWith(sub: 'all');
    }
    // A deep link names a tag or league by its readable segment.
    if (selection.sub.startsWith('route:')) {
      final route = selection.sub.substring(6);
      for (final s in subs) {
        if (s.route == route) selection = selection.copyWith(sub: s.key);
      }
    }
    final sub = _subFor(selection, subs) ?? PolySub(selection.sub);
    // Live always reads the one list of games in play; a league pill
    // narrows it on screen.
    final query = pill == PolyPill.live
        ? const PolyFeedQuery(pill: PolyPill.live)
        : selection.query;
    final fiveMinOnly = pill == PolyPill.crypto && selection.sub == '5m';
    final showHeroSection = pill == PolyPill.trending || fiveMinOnly;
    final showHeroPinned =
        pill == PolyPill.crypto && selection.sub == 'all';
    final isLiveList = pill == PolyPill.live ||
        (pill == PolyPill.sports && selection.sub == 'live');

    final feed = canBrowse && !fiveMinOnly
        ? ref.watch(polyBrowseFeedProvider(query))
        : const PolyFeedState(done: true);
    _feedQuery = canBrowse && !fiveMinOnly ? query : null;
    // Once the list on screen lands, the lists next to it are read too
    // (one at a time), so opening one of them paints at once.
    if (canBrowse && !fiveMinOnly) {
      ref.listen<PolyFeedState>(polyBrowseFeedProvider(query), (prev, next) {
        if (prev == null || !prev.loading || next.loading || next.failed) {
          return;
        }
        unawaited(PolyFeedPrefetch.run(
          PolyFeedPrefetch.queriesAround(
              selection: selection, pills: pills, subs: subs),
          (q) => ref.read(polyBrowseFeedProvider(q).notifier),
        ));
      });
    }

    // Join the sports live-score WS only while sports cards are listed —
    // once, not every build.
    final anySports = feed.events.any((e) => e.category == 'sports');
    if (anySports && !_sportsConnected) {
      _sportsConnected = true;
      Future.microtask(() {
        if (mounted) ref.read(sportsLiveProvider.notifier).connect();
      });
    } else if (!anySports) {
      _sportsConnected = false;
    }

    // A short first page leaves nothing to scroll: read on until the
    // list fills the screen or ends.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (pos.hasContentDimensions && pos.extentAfter < 900) _loadMore();
    });

    final title = (pill.isTopic || pill == PolyPill.live) &&
            selection.sub != 'all'
        ? polySubLabel(l10n, sub)
        : polyPillLabel(l10n, pill);
    // Games in play are listed under their leagues' own headings: the
    // list's heading would only sit on top of the first of them.
    final liveLeague = pill == PolyPill.live && selection.sub != 'all'
        ? selection.sub
        : null;
    final groupedLive = isLiveList && liveLeague == null;

    // NOTE: live CLOB prices and sports scores are watched PER CARD
    // inside [_PolyFeedCard] with narrow
    // selects — watching them here rebuilt this entire screen (every
    // sliver, every section) on every WS price tick, which is what made
    // the whole browse experience stutter.

    return Scaffold(
      // No AppBar — the custom inline header below reclaims the ~56px
      // a Material AppBar would eat, so the first market card lands
      // visibly higher on screen. PlatformSafeArea handles the notch.
      backgroundColor: context.isDark ? c.gradientBottom : c.background,
      // Tap anywhere outside the search field to dismiss the keyboard.
      // opaque hit behavior so taps on empty space still register
      // even though the Stack's gradient background has no tap targets.
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
                    // Clears the integrated top nav bar (avatar + tabs).
                    SliverToBoxAdapter(child: SizedBox(height: 64.h)),

                    // Hero balance, like the main screen (user decision:
                    // the balance lives at the top of each pool screen,
                    // above the ongoing bets, not on the bottom bar).
                    // Its own ConsumerWidget so balance/position/pending
                    // ticks rebuild ONLY the header, not the whole scroll
                    // view (the old inline Builder used the screen's ref).
                    const SliverToBoxAdapter(
                      child: InvestmentBalanceHeader(
                          product: InvestmentsProduct.predictions),
                    ),

                    if (!canBrowse)
                      const SliverToBoxAdapter(
                        child: InvestmentDiscoveryNotice(
                            capability: 'polymarket.browse'),
                      )
                    else ...[
                      // ── Categories: the side-scrolling pill strip under
                      // the balance, and under it the subcategories of
                      // the category on screen, in the same pills.
                      SliverToBoxAdapter(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 12.h),
                            PolyPillRow(
                              pills: pills,
                              selected: pill,
                              onSelect: _onPill,
                              onMore: () => _onMore(pills),
                            ),
                            if (subs.length > 1) ...[
                              SizedBox(height: 8.h),
                              PolySubRow(
                                pill: pill,
                                subs: subs,
                                selectedKey: selection.sub,
                                onSelect: _onSub,
                              ),
                            ],
                          ],
                        ),
                      ),

                      // The list under the pills fades in when the pill
                      // or the subcategory changes (never on a refresh);
                      // only an opacity runs, so paging and the scroll
                      // position are untouched.
                      SliverSelectionFade(
                        selection: (pill, selection.sub),
                        slivers: [
                          // ── "Crypto markets": section header first, then
                          // the BTC Up-or-Down hero card UNDER it (user
                          // decision). On the home and under Crypto › 5 Min;
                          // the other assets' card shows only under Crypto
                          // (user decision: not on the main screen).
                          if (showHeroSection)
                            ..._fiveMinuteSlivers(otherAssets: fiveMinOnly),

                          // ── The list's own heading.
                          if (!fiveMinOnly && !(groupedLive && feed.events.isNotEmpty))
                            SliverToBoxAdapter(child: _SectionHeader(label: title)),

                          // The hero alone pinned first under Crypto › All.
                          if (showHeroPinned) _heroSliver(),

                          if (!fiveMinOnly)
                            ..._feedSlivers(
                              feed,
                              query: query,
                              isLiveList: isLiveList,
                              liveLeague: liveLeague,
                            ),
                        ],
                      ),
                    ],
                    // Bottom clearance above the floating action bar.
                    SliverToBoxAdapter(
                        child: SizedBox(height: _bottomDockHeight + 24.h)),
                  ],
                ),
              ),
            ),

            // The integrated top nav bar now lives ONCE in the persistent nav
            // shell (lib/screens/app_shell.dart), mounted above all four tab
            // pages — no longer painted per-screen. The 64.h top sliver above
            // still clears its space; this screen's scroll listener drives its
            // hide/reveal via navBarHiddenProvider.

            // Hide the bottom nav when the keyboard is open — Scaffold's
            // default resizeToAvoidBottomInset shrinks the body by the
            // keyboard's height, which would otherwise float the pill
            // directly above the keyboard with a visible gap.
            // viewInsetsOf, not MediaQuery.of: the aspect-scoped lookup
            // rebuilds this screen when the KEYBOARD moves and at no other
            // time. The whole-data lookup it replaces made every padding,
            // text-scale and accessibility change rebuild the entire feed —
            // every sliver, every card, every LiveTokenScope — including
            // while a route above it was being popped.
            if (MediaQuery.viewInsetsOf(context).bottom == 0) ...[
              // Frosted blur layer behind the bottom nav — same effect
              // home uses so the pill reads as floating glass over the
              // feed instead of sitting flat on top of clipped content.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _bottomDockHeight + 12.h,
                child: IgnorePointer(
                  child: ClipRect(
                    child: KuteBlur(
                      // Match home's bottom-bar blur exactly (same size + sigma).
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
                  product: InvestmentsProduct.predictions,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "Crypto markets": the header with its window chips and the BTC Up or
  /// Down hero (live chart, strike line, countdown, live odds); with
  /// [otherAssets] (Crypto › 5 Min) the other assets in one card under it.
  List<Widget> _fiveMinuteSlivers({required bool otherAssets}) => [
        SliverToBoxAdapter(
          child: _SectionHeader(
            label: context.l10n.predictionsCryptoMarkets,
            trailing: const _CryptoWindowChips(),
          ),
        ),
        _heroSliver(),
        if (otherAssets)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: _MoreCryptoMarketsCard(
                onDeposit: () {
                  _openPredictionsDeposit(context, ref);
                },
              ),
            ),
          ),
      ];

  Widget _heroSliver() => SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
          child: RepaintBoundary(
            child: CryptoPredictBanner(
              config: kCryptoPredictAssets.first,
              showLiveIndicator: true,
              onDeposit: () {
                _openPredictionsDeposit(context, ref);
              },
            ),
          ),
        ),
      );

  /// The list itself: games in play grouped under their leagues,
  /// everything else as market cards (Breaking in the order of the day's
  /// biggest moves); a loading row while the next page reads.
  List<Widget> _feedSlivers(
    PolyFeedState feed, {
    required PolyFeedQuery query,
    required bool isLiveList,
    String? liveLeague,
  }) {
    if (feed.events.isEmpty) {
      if (feed.loading) {
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 8.h),
              child: SkeletonCardList(count: 3, height: 160.h),
            ),
          ),
        ];
      }
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 40.h),
            child: const _EmptyState(),
          ),
        ),
      ];
    }

    final List<Widget> body;
    if (isLiveList) {
      body = _liveSlivers(feed.events, only: liveLeague);
    } else {
      final open = feed.events.where((e) => !e.ended).toList(growable: false);
      final events = collapseByGameId(open);
      final siblings = siblingsByGameId(open);
      body = [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 8.h),
          sliver: SliverList.separated(
            itemCount: events.length,
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (_, i) {
              final market = events[i];
              return _PolyFeedCard(
                market: market,
                isSportsCategory: market.category == 'sports',
                matchSiblings: market.gameId != null
                    ? (siblings[market.gameId!] ?? const <PolymarketEvent>[])
                    : const <PolymarketEvent>[],
              );
            },
          ),
        ),
      ];
    }
    return [
      ...body,
      if (feed.loadingMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h),
            child: Center(
              child: LoadingAnimationWidget.staggeredDotsWave(
                color: context.colors.textTertiary,
                size: 28.sp,
              ),
            ),
          ),
        ),
    ];
  }

  /// The games in play by league, the league with the most games first.
  /// Games of a league Polymarket's league list does not name share one
  /// "Other" group.
  List<_LiveGroup> _liveGroups(List<PolymarketEvent> events) {
    final leagues = {
      for (final s in ref.watch(polySportsLeaguesProvider))
        if (s.seriesId != null) s.seriesId!: s,
    };
    final other = PolySub('other', label: context.l10n.betGroupOther);
    final groups = <String, _LiveGroup>{};
    for (final e in collapseByGameId(events)) {
      final sub = leagues[e.seriesId ?? ''] ?? other;
      (groups[sub.key] ??= (sub: sub, games: <PolymarketEvent>[]))
          .games
          .add(e);
    }
    // Stable: leagues with as many games keep the order of the list.
    final ordered = groups.values.toList();
    final index = {for (var i = 0; i < ordered.length; i++) ordered[i]: i};
    ordered.sort((a, b) {
      final byCount = b.games.length.compareTo(a.games.length);
      return byCount != 0 ? byCount : index[a]!.compareTo(index[b]!);
    });
    return ordered;
  }

  /// Games in play under their league headings; with [only] (a league's
  /// key) just that league's games, under no heading of their own.
  List<Widget> _liveSlivers(List<PolymarketEvent> events, {String? only}) {
    final slivers = <Widget>[];
    if (only == _kLiveStreams) {
      final streams = [
        for (final e in collapseByGameId(events))
          if (e.hasLivestream) e
      ];
      return [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          sliver: SliverList.separated(
            itemCount: streams.length,
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (_, i) => _PolyFeedCard(
              market: streams[i],
              isSportsCategory: true,
            ),
          ),
        ),
      ];
    }
    for (final group in _liveGroups(events)) {
      if (only != null && group.sub.key != only) continue;
      if (only == null) {
        slivers.add(SliverToBoxAdapter(
          child: _SectionHeader(label: polySubLabel(context.l10n, group.sub)),
        ));
      }
      slivers.add(SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        sliver: SliverList.separated(
          itemCount: group.games.length,
          separatorBuilder: (_, __) => SizedBox(height: 10.h),
          itemBuilder: (_, i) => _PolyFeedCard(
            market: group.games[i],
            isSportsCategory: true,
          ),
        ),
      ));
    }
    return slivers;
  }

  Future<void> _onRefresh() async {
    ref.invalidate(polymarketBalanceProvider);
    ref.invalidate(polymarketTradingProvider);
    // The list on screen and its chips; the other lists keep what they
    // hold. The 5-min hero/grid refresh themselves on a 10s cadence and
    // roll every 5 minutes, so they're deliberately left out.
    polyRefreshBrowse(
      query: _feedQuery,
      pill: ref.read(polyBrowseSelectionProvider).pill,
      invalidate: ref.invalidate,
    );
    // Wait a moment for providers to start refetching
    await Future.delayed(const Duration(milliseconds: 500));
  }

  void _showWithdrawSheet(BuildContext context, WidgetRef ref) {
    TrackingService.polymarketFundingAction('withdraw');
    showDepositSheet(context,
        lockedSide: MoveLockedSide.withdrawFromPredictions);
  }
}

/// One feed row. Its own ConsumerWidget (repo rule: lazy-list items that
/// read Theme must be standalone widget classes) watching ONLY this
/// card's slices of the live-price and sports
/// providers via narrow selects — so a WS tick repaints just the cards
/// it touches instead of the whole screen.
class _PolyFeedCard extends ConsumerWidget {
  final PolymarketEvent market;
  final bool isSportsCategory;

  /// Extra sub-markets for this match (Both Teams to Score, O/U,
  /// corners …) that `collapseByGameId` folded away. Surfaced as a
  /// "+N more markets" affordance opening the grouped match view.
  final List<PolymarketEvent> matchSiblings;

  const _PolyFeedCard({
    required this.market,
    required this.isSportsCategory,
    this.matchSiblings = const <PolymarketEvent>[],
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // -1 excludes the primary card itself from the count.
    final int extraMarketCount =
        matchSiblings.length > 1 ? matchSiblings.length - 1 : 0;

    // Until a live tick lands the card shows the feed's own outcome
    // prices. (A CLOB `simplified-markets` snapshot used to sit in
    // between: three sequential reads of ~470 KB on every open, listing
    // the oldest markets first, so it never held a card on this feed.)
    final cardLivePrices = <String, double>{};
    final cardDirections = <String, int>{};
    // Every visible card streams its outcome tokens over the CLOB WS.
    // [LiveTokenScope] below registers them post-frame on mount and
    // releases them on dispose (refcounted + LRU-capped in the
    // notifier), so the subscription set tracks the viewport instead of
    // growing with everything ever scrolled past. The narrow selects
    // here mean a price_change frame repaints only the cards whose
    // tokens moved.
    final outcomeTokenIds = <String>[];
    for (final o in market.outcomes) {
      final tokenId = o.tokenId;
      if (tokenId != null && tokenId.isNotEmpty) {
        outcomeTokenIds.add(tokenId);
        final lp =
            ref.watch(livePriceProvider.select((s) => s.prices[tokenId]));
        if (lp != null) cardLivePrices[tokenId] = lp;
        final dir = ref
            .watch(livePriceProvider.select((s) => s.priceDirection(tokenId)));
        if (dir != 0) cardDirections[tokenId] = dir;
      }
    }

    final matchUpdate = isSportsCategory
        ? ref.watch(sportsLiveProvider.select((m) => sportsUpdateFor(m,
            slug: market.slug,
            gameId: market.gameId,
            metadataGameId: market.metadataGameId)))
        : null;

    // A crypto Up-or-Down round reads as its asset and window ("Bitcoin ·
    // 15 Min") with the round's own time in the footer, instead of the
    // venue's "Bitcoin Up or Down - October 4, 10:15PM-10:30PM ET".
    final round = polyCryptoRoundOf(market.slug, endDate: market.endDate);
    final roundAsset =
        round == null ? null : polyCryptoRoundAssetName(market.title);

    return LiveTokenScope(
      tokens: outcomeTokenIds,
      child: RepaintBoundary(
        child: MarketCard(
          title: roundAsset == null
              ? market.title
              : '$roundAsset · '
                  '${polyRoundWindowLabel(context.l10n, round!.window)}',
          round: roundAsset == null
              ? null
              : (start: round!.start, end: round.end),
          imageUrl: market.imageUrl,
          outcomes: market.outcomes,
          volume: market.volume,
          volume24hr: market.volume24hr,
          category: market.category,
          startDate: market.startDate,
          gameStart: market.kickoff,
          endDate: market.endDate,
          active: market.active,
          closed: market.closed,
          ended: market.ended,
          livePrices: cardLivePrices,
          priceDirections: cardDirections,
          liveGame: isSportsCategory || matchUpdate != null
              ? PolyLiveGame.of(market, matchUpdate)
              : null,
          teams: market.teams,
          slug: market.slug,
          gameId: market.gameId,
          hasLivestream: market.hasLivestream,
          siblingMarketCount: extraMarketCount,
          dayMove: market.oneDayPriceChange,
          onMoreMarkets: extraMarketCount > 0
              ? () {
                  HapticFeedback.mediumImpact();
                  TrackingService.track('prediction_match_markets_opened',
                      params: {
                        if (market.category.isNotEmpty)
                          'category': market.category.toLowerCase(),
                      });
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) => GroupLandingScreen.events(
                        title: market.title,
                        events: matchSiblings,
                        slug: market.category,
                      ),
                    ),
                  );
                }
              : null,
          // The chart's history starts reading as the finger comes down.
          onTapDown: () => MarketDetailSheet.prefetch(market),
          onTap: () {
            HapticFeedback.mediumImpact();
            // polymarket_viewed (fired by show) carries source + category;
            // the old prediction_market_opened duplicated this same tap.
            MarketDetailSheet.show(
              context,
              event: market,
              onDeposit: () async {
                if (context.mounted) _openPredictionsDeposit(context, ref);
              },
              source: 'feed_card',
            );
          },
        ),
      ),
    );
  }
}

/// Live 5-min Up/Down crypto market banner. Mounted as the Predictions
/// screen's HERO card (BTC config: live Binance-fed chart, strike line,
/// countdown, live CLOB odds on the Up/Down buttons) and reused by
/// `FiveMinMarketDetailSheet` to surface the same widget in detail-sheet
/// form when a 5-min market is opened from the grid.
/// How old a CLOB live odds tick may be before [CryptoPredictBanner]
/// stops trusting it and falls back to the 10s Gamma poll. Generous
/// against a thin 5-min book's frame gaps, tight enough that a silently
/// dead feed (stalled socket, exhausted reconnects) hands over within
/// one window's opening seconds.
const _kLiveOddsMaxAge = Duration(seconds: 30);

/// Registers its subtree in [cryptoCardsOnScreenProvider] while
/// tickers are enabled there. A hidden shell branch turns tickers off
/// (`Offstage` + `TickerMode`), so a banner counts only while it can be
/// seen; the count is changed after the frame, never during build.
class _CryptoCardOnScreen extends ConsumerStatefulWidget {
  const _CryptoCardOnScreen({required this.child});

  final Widget child;

  @override
  ConsumerState<_CryptoCardOnScreen> createState() =>
      _CryptoCardOnScreenState();
}

class _CryptoCardOnScreenState extends ConsumerState<_CryptoCardOnScreen> {
  late final StateController<int> _cards =
      ref.read(cryptoCardsOnScreenProvider.notifier);
  bool _counted = false;

  void _count(bool on) {
    if (on == _counted) return;
    _counted = on;
    Future.microtask(() => _cards.state += on ? 1 : -1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _count(TickerMode.valuesOf(context).enabled);
  }

  @override
  void dispose() {
    _count(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class CryptoPredictBanner extends ConsumerWidget {
  final CryptoAssetConfig config;
  final VoidCallback? onDeposit;
  final String? ledgerWalletId;

  /// #163 — when non-null, the banner loads the specific 5-min window
  /// whose start-epoch (UTC seconds, 300-aligned) is this value, via
  /// [cryptoPredictAtWindowProvider]. When null, it watches the
  /// legacy rolling [cryptoPredictProvider] (current window).
  final int? targetWindowEpoch;

  /// When true, the inner [BtcPredictChart] renders its pulsing
  /// "● Live" pill above the curve. Detail-sheet reuse leaves it off
  /// by default to keep the banner cleaner.
  final bool showLiveIndicator;

  const CryptoPredictBanner({
    super.key,
    required this.config,
    this.onDeposit,
    this.ledgerWalletId,
    this.targetWindowEpoch,
    this.showLiveIndicator = false,
  });

  List<PolymarketOutcome> _eventOutcomes(Btc5MinEvent? event) {
    if (event == null) {
      return [
        const PolymarketOutcome(name: 'Up', price: 0.50),
        const PolymarketOutcome(name: 'Down', price: 0.50),
      ];
    }
    return [
      PolymarketOutcome(
          name: 'Up',
          price: event.upPrice,
          tokenId: event.upTokenId,
          conditionId: event.conditionId),
      PolymarketOutcome(
          name: 'Down',
          price: event.downPrice,
          tokenId: event.downTokenId,
          conditionId: event.conditionId),
    ];
  }

  String _formatPrice(double? price) {
    if (price == null) return '—';
    if (price >= 1000) {
      return '\$${NumberFormat('#,##0', 'en_US').format(price.round())}';
    } else if (price >= 1) {
      return '\$${NumberFormat('#,##0.00', 'en_US').format(price)}';
    } else {
      return '\$${price.toStringAsFixed(4)}';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // Route to the window-scoped provider when the caller asked for a
    // specific upcoming round; otherwise keep the legacy current-window
    // provider so the rest of the app is unaffected.
    final predictAsync = targetWindowEpoch == null
        ? ref.watch(cryptoPredictProvider(config.asset))
        : ref.watch(cryptoPredictAtWindowProvider((
            asset: config.asset,
            epochSeconds: targetWindowEpoch,
          )));
    final predictState = predictAsync.asData?.value;
    final upPctPolled = predictState?.upPct ?? 50;
    final countdown = predictState?.countdownText ?? '05:00';
    final priceStr = _formatPrice(predictState?.currentPrice);

    // Don't render if event couldn't be loaded (asset not on Polymarket)
    if (predictAsync.hasError && !predictAsync.hasValue) {
      return const SizedBox.shrink();
    }

    // One-time #156 debug — log the token IDs the first time the
    // event lands so we can verify they're populated end-to-end. If
    // these come through null/empty the live-price subscription is a
    // no-op and the bar stays at the polled-stale 50/50.
    final debugListenable = targetWindowEpoch == null
        ? cryptoPredictProvider(config.asset)
        : cryptoPredictAtWindowProvider((
            asset: config.asset,
            epochSeconds: targetWindowEpoch,
          ));
    ref.listen<AsyncValue<CryptoPredictState>>(
      debugListenable,
      (prev, next) {
        final prevEvent = prev?.asData?.value.event;
        final nextEvent = next.asData?.value.event;
        if (prevEvent?.slug == nextEvent?.slug) return;
        if (nextEvent == null) return;
        assert(() {
          debugPrint(
              '[CryptoPredictBanner ${config.asset}] event=${nextEvent.slug} '
              'upTokenId=${nextEvent.upTokenId} '
              'downTokenId=${nextEvent.downTokenId} '
              'upPrice=${nextEvent.upPrice} downPrice=${nextEvent.downPrice}');
          return true;
        }());
      },
    );

    // --- LIVE odds wiring ---
    // The 10s polling cadence in CryptoPredictNotifier is too slow
    // for the up/down odds bar to feel alive. The [LiveTokenScope]
    // wrapping this banner (see the return below) subscribes the
    // event's up/down CLOB token IDs on the order-book WS
    // (livePriceProvider), re-registers them when the 5-min window
    // rolls to new tokens, and releases them on unmount.
    final upTokenId = predictState?.event?.upTokenId;
    final downTokenId = predictState?.event?.downTokenId;

    // Watch live prices for just this event's tokens — `.select`
    // narrows rebuilds so this banner only repaints when *its*
    // token prices move, not on every WS event for the wider app.
    // The CLOB price is trusted only while the feed reports live AND
    // this token ticked within [_kLiveOddsMaxAge]: a stalled feed
    // (dead socket, exhausted reconnects) otherwise pins the `??`
    // fallback off forever and the buttons freeze while the price
    // chart keeps moving — the polled Gamma odds below refresh every
    // 10s, so they take over within one staleness window. The 1s
    // countdown rebuild re-evaluates this gate even when no live
    // frame arrives to trigger it.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final liveUpPriceRaw = ref.watch(
      livePriceProvider.select((s) {
        if (upTokenId == null || !s.live) return null;
        final tickedAt = s.updatedAtMs[upTokenId];
        if (tickedAt == null ||
            nowMs - tickedAt > _kLiveOddsMaxAge.inMilliseconds) {
          return null;
        }
        return s.prices[upTokenId];
      }),
    );

    // Resolve "up" probability (0..1):
    //   1. live order-book mid if it's actually fresh
    //   2. polled state from the 10s notifier
    //   3. 0.50 fallback
    final livePctUp = liveUpPriceRaw ?? (upPctPolled / 100.0);
    final livePctUpClamped = livePctUp.clamp(0.0, 1.0);

    // Round window text — "May 21, 10:10-10:15AM ET" style. Falls back to
    // a generic "Live round" when the event isn't loaded yet.
    final event = predictState?.event;
    String roundText;
    if (event?.endDate != null) {
      // Gamma's startDate on these auto-created markets is the CREATION
      // timestamp (up to a day before the round), which produced labels
      // like "Aug 31, 9:44-9:40PM" on a live Sep 1 window. The real
      // open is parsed from the slug (windowStartTime); the end minus
      // five minutes is the fallback.
      final end = event!.endDate!.toLocal();
      final start = (event.windowStartTime ??
              event.endDate!.subtract(const Duration(minutes: 5)))
          .toLocal();
      final dateStr = DateFormat('MMM d').format(start);
      final startTime = DateFormat('h:mm').format(start);
      final endTime = DateFormat('h:mma').format(end);
      roundText = '$dateStr, $startTime-$endTime';
    } else {
      roundText = context.l10n.predictLiveRound;
    }
    final priceToBeat = predictState?.priceToBeat;
    final priceToBeatStr = _formatPrice(priceToBeat);
    final String? feedName = switch (predictState?.feed) {
      CryptoPriceFeed.binance => 'Binance',
      CryptoPriceFeed.coingecko => 'CoinGecko',
      _ => null,
    };
    // Per-asset brand color — was hard-coded to BTC orange for every
    // banner, which made ETH/SOL/XRP cards visually misread as BTC.
    final brandColor = config.brandColor;
    // Banner shows "Loading prices…" ONLY while we don't even have an
    // event slug yet. Previously the gate also required `currentPrice`
    // and `priceToBeat` — both fed by CoinGecko polling. When CoinGecko
    // rate-limited or returned empty, the banner stayed loading
    // indefinitely even though the event + CLOB WS odds were ready.
    // Now we render the moment the event lands; the BTC price block
    // falls back to a dash until the first poll/WS tick arrives but
    // the rest of the banner (countdown, Up/Down buttons, odds bar)
    // becomes interactive immediately.
    final isInitialLoading = predictState == null || predictState.event == null;

    // 5-minute markets resolve fast — the USDC-only funding gate
    // (PendingBetIntent.isShortMarket) keys off marketEndAt, so the
    // slip MUST receive it or a BTC→USDC swap could be offered on a
    // market that resolves before the swap lands. Fall back to the
    // slug-derived window start + 5 min when Gamma omitted endDate.
    final DateTime? marketEndAt = event?.endDate ??
        event?.windowStartTime?.add(const Duration(minutes: 5));

    // Counts this banner as on screen while its tickers run, so the
    // shared Chainlink feed also streams when it is shown outside the
    // Predictions tab.
    return _CryptoCardOnScreen(
        child: LiveTokenScope(
      tokens: [
        if (upTokenId != null && upTokenId.isNotEmpty) upTokenId,
        if (downTokenId != null && downTokenId.isNotEmpty) downTokenId,
      ],
      child: Container(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 14.h),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(color: c.borderSubtle, width: 0.5),
          boxShadow: context.isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: orange-rounded asset icon, title + date sub,
            // countdown pill on the right.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                config.isSvg
                    ? SizedBox(
                        width: 44.sp,
                        height: 44.sp,
                        child: SvgPicture.asset(
                          config.logoPath,
                          width: 40.sp,
                          height: 40.sp,
                          fit: BoxFit.contain,
                        ),
                      )
                    : Container(
                        width: 44.sp,
                        height: 44.sp,
                        decoration: BoxDecoration(
                          color: brandColor,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        alignment: Alignment.center,
                        child: Image.asset(
                          config.logoPath,
                          width: 30.sp,
                          height: 30.sp,
                        ),
                      ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.predictUpOrDown(config.asset, 5),
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          height: 1.15,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        roundText,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: brandColor.withValues(alpha: 0.14),
                    // Squared like the rest of the chip language, not a
                    // capsule (user decision).
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6.w,
                        height: 6.w,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 6.w),
                      Text(
                        countdown,
                        style: TextStyle(
                          color: brandColor,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 18.h),

            // Price to beat (hero number) + current live price. While the
            // event + first WS tick are still loading we show a softer
            // "Loading prices…" hint so the card never sits on "$—".
            if (isInitialLoading)
              // Skeleton mimicking the "Price to beat" hero number below
              // so the card keeps its loaded shape while prices stream in.
              KuteSkeleton(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SkeletonBar(88.w, 12.h),
                    SizedBox(height: 6.h),
                    SkeletonBar(150.w, 28.h, radius: 8.r),
                  ],
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Phantom-style hero: the LIVE price is the big number,
                  // the strike sits quietly beneath it. No duplicated
                  // "Price to beat" rows (the chart's own header is off).
                  // Both are Polymarket's own numbers; while its Chainlink
                  // feed is silent the price and chart come from a
                  // fallback, named in small type beside the price.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: RollingNumberText(
                          text: priceStr,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 30.sp,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.9,
                            height: 1.0,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      if (feedName != null) ...[
                        SizedBox(width: 6.w),
                        Text(
                          feedName,
                          style: TextStyle(
                            color: c.textTertiary,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    context.l10n.predictTargetPrice(priceToBeatStr),
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            SizedBox(height: 16.h),

            // Live chart with the target line.
            // While the price history is still seeding (the Chainlink
            // snapshot lands well under a second) show the line-chart skeleton
            // so the hero never paints an empty plot area.
            if ((predictState?.priceHistory.length ?? 0) < 2)
              const SkeletonLineChart(
                height: 200,
                padding: EdgeInsets.zero,
              )
            else
              BtcPredictChart(
                height: 200,
                externalHistory: predictState?.priceHistory,
                externalPriceToBeat: predictState?.priceToBeat,
                // Clip the plotted window to this round's elapsed span
                // so the live sweep always fills the card width instead
                // of bunching into the tail of a fixed 5-minute axis.
                roundStart: event?.windowStartTime,
                // The hero prints price + target itself; the chart adds
                // only the curve (no duplicate header, no Live pill —
                // the countdown pill already signals live).
                showLiveIndicator: false,
                showHeader: false,
              ),
            SizedBox(height: 10.h),

            // De-emphasized probability split below the chart. The Up /
            // Down CTAs now carry the live odds as their labels, so the
            // bar here is just a 3px supporting strip — no number
            // labels (those moved onto the buttons).
            TweenAnimationBuilder<double>(
              tween:
                  Tween<double>(begin: livePctUpClamped, end: livePctUpClamped),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              builder: (context, animatedUpFrac, _) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: animatedUpFrac.clamp(0.0, 1.0),
                    minHeight: 3.h,
                    backgroundColor: _kPolyRed.withValues(alpha: 0.16),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        _kPolyGreen.withValues(alpha: 0.75)),
                  ),
                );
              },
            ),
            SizedBox(height: 12.h),

            // Up / Down CTAs — taller (52h) and rounder (16r) to match
            // the new bet-slip button language. Labels now carry the
            // live odds inline (per #156) so the buttons ARE the
            // primary odds-display surface. Percentages are wrapped in
            // TweenAnimationBuilder so they roll smoothly between
            // order-book updates instead of jumping.
            Row(
              children: [
                Expanded(
                  child: MarketPairButton(
                    label: context.l10n.upLabel,
                    value: formatPolyChancePair(livePctUpClamped).first,
                    icon: Icons.arrow_upward_rounded,
                    iconDisc: true,
                    glow: true,
                    color: AppColors.marketUp,
                    // MarketPairButton fires its own haptic.
                    onTap: () {
                      final outcomes = _eventOutcomes(event);
                      final upIdx = outcomes
                          .indexWhere((o) => o.name.toLowerCase() == 'up');
                      BetSlipSheet.show(context,
                          marketQuestion:
                              event?.title ??
                                  context.l10n.predictUpOrDown(config.asset, 5),
                          marketSlug: event?.slug,
                          marketImage: event?.image,
                          outcomes: outcomes,
                          initialOutcomeIndex: upIdx >= 0 ? upIdx : 0,
                          // Required for the 5-minute USDC-only funding
                          // gate (isShortMarket) — without it the slip
                          // happily offers a BTC swap that can't land
                          // before the window resolves.
                          marketEndAt: marketEndAt,
                          marketCategory: 'crypto',
                          onDeposit: onDeposit,
                          ledgerWalletId: ledgerWalletId,
                          source: 'crypto_banner');
                    },
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: MarketPairButton(
                    label: context.l10n.downLabel,
                    value: formatPolyChancePair(livePctUpClamped).second,
                    icon: Icons.arrow_downward_rounded,
                    iconDisc: true,
                    glow: true,
                    color: AppColors.marketDown,
                    // MarketPairButton fires its own haptic.
                    onTap: () {
                      final outcomes = _eventOutcomes(event);
                      final downIdx = outcomes
                          .indexWhere((o) => o.name.toLowerCase() == 'down');
                      BetSlipSheet.show(context,
                          marketQuestion:
                              event?.title ??
                                  context.l10n.predictUpOrDown(config.asset, 5),
                          marketSlug: event?.slug,
                          marketImage: event?.image,
                          outcomes: outcomes,
                          initialOutcomeIndex: downIdx >= 0 ? downIdx : 0,
                          // See the Up button — 5-minute USDC-only gate.
                          marketEndAt: marketEndAt,
                          marketCategory: 'crypto',
                          onDeposit: onDeposit,
                          ledgerWalletId: ledgerWalletId,
                          source: 'crypto_banner');
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ));
  }
}

/// "5 Minute Markets" tile grid — every 5m asset EXCEPT BTC (the hero
/// already gives BTC the big square). Tiles are laid out two-up with the
/// odd remainder as a full-width strip, so the block reads as a varied
/// mosaic under the hero rather than a uniform list.
/// The window chips beside the section title: exactly the windows
/// Polymarket runs today for the hero asset, tapped to switch every
/// crypto card on the screen at once.
class _CryptoWindowChips extends ConsumerWidget {
  const _CryptoWindowChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final windows = ref
            .watch(
                cryptoPredictWindowsProvider(kCryptoPredictAssets.first.asset))
            .valueOrNull ??
        const [5];
    final selected = ref.watch(cryptoPredictWindowProvider);
    if (windows.length < 2) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final minutes in windows)
          Padding(
            padding: EdgeInsets.only(left: 6.w),
            child: GestureDetector(
              onTap: () {
                if (selected == minutes) return;
                HapticFeedback.selectionClick();
                TrackingService.track('crypto_window_changed',
                    params: {'minutes': minutes});
                ref.read(cryptoPredictWindowProvider.notifier).state = minutes;
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                decoration: BoxDecoration(
                  color: selected == minutes ? c.textPrimary : c.surface,
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: c.borderSubtle, width: 0.5),
                ),
                child: Text(
                  '${minutes}m',
                  style: TextStyle(
                    color: selected == minutes ? c.background : c.textPrimary,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The other crypto markets in one card under the hero, the way the open
/// predictions strip reads: a titled surface with one row per asset.
class _MoreCryptoMarketsCard extends StatelessWidget {
  final VoidCallback? onDeposit;
  const _MoreCryptoMarketsCard({this.onDeposit});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final others = kCryptoPredictAssets.skip(1).toList(growable: false);
    if (others.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 4.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.border.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < others.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.borderSubtle),
            _FiveMinTile(
                config: others[i],
                wide: true,
                bare: true,
                onDeposit: onDeposit),
          ],
        ],
      ),
    );
  }
}

/// One 5-minute Up/Down asset tile: logo, asset name, "5m" badge, live
/// MM:SS countdown and LIVE Up/Down odds (CLOB WS via the wrapping
/// [LiveTokenScope], gamma snapshot as fallback), plus a tiny live spot
/// price. Tapping opens [FiveMinMarketDetailSheet] for the asset.
class _FiveMinTile extends ConsumerWidget {
  final CryptoAssetConfig config;

  /// Full-width horizontal variant (the odd remainder row); false is the
  /// square-ish half-width tile.
  final bool wide;
  final VoidCallback? onDeposit;

  /// Rendered as a plain row inside a card that supplies its own chrome.
  final bool bare;

  const _FiveMinTile({
    required this.config,
    required this.wide,
    this.onDeposit,
    this.bare = false,
  });

  static String _formatSpot(double? price) {
    if (price == null) return '';
    if (price >= 1000) {
      return '\$${NumberFormat('#,##0', 'en_US').format(price.round())}';
    } else if (price >= 1) {
      return '\$${NumberFormat('#,##0.00', 'en_US').format(price)}';
    }
    return '\$${price.toStringAsFixed(4)}';
  }

  void _openDetail(BuildContext context, Btc5MinEvent? ev, int minutes) {
    HapticFeedback.mediumImpact();
    TrackingService.track('five_min_tile_tapped', params: {
      'asset': config.asset,
      'minutes': minutes,
    });
    // Thin PolymarketEvent shell for the detail sheet (it resolves the
    // asset config from slug/title). conditionId uses the event's OWN
    // market id when present — never the slug stand-in the home-rail
    // provider uses (scout gap #8).
    final event = PolymarketEvent(
      id: ev?.slug ?? '${config.asset.toLowerCase()}-updown-${minutes}m',
      slug: ev?.slug ?? '',
      title: ev?.title ?? context.l10n.predictUpOrDown(config.asset, minutes),
      imageUrl: ev?.image,
      volume: 0,
      volume24hr: 0,
      liquidity: 100000,
      category: 'crypto',
      endDate: ev?.endDate,
      conditionId: ev?.conditionId ?? '',
      outcomes: [
        PolymarketOutcome(
          name: 'Up',
          price: ev?.upPrice ?? 0.50,
          tokenId: ev?.upTokenId,
        ),
        PolymarketOutcome(
          name: 'Down',
          price: ev?.downPrice ?? 0.50,
          tokenId: ev?.downTokenId,
        ),
      ],
    );
    FiveMinMarketDetailSheet.show(context, event: event, onDeposit: onDeposit);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final predictAsync = ref.watch(cryptoPredictProvider(config.asset));
    final minutes = ref.watch(cryptoPredictWindowProvider);
    final st = predictAsync.asData?.value;
    final ev = st?.event;

    // Loading: keep the tile's exact footprint as a skeleton card so the
    // grid doesn't jump when the event lands.
    if (ev == null) {
      final skeleton = SkeletonCard(
        height: wide ? 92.h : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              SkeletonCircle(28.w),
              const Spacer(),
              SkeletonBar(48.w, 12.h),
            ]),
            const Spacer(),
            SkeletonBar(90.w, 14.h),
            SizedBox(height: 10.h),
            Row(children: [
              Expanded(child: SkeletonBar(double.infinity, 26.h)),
              SizedBox(width: 6.w),
              Expanded(child: SkeletonBar(double.infinity, 26.h)),
            ]),
          ],
        ),
      );
      return KuteSkeleton(
        child:
            wide ? skeleton : AspectRatio(aspectRatio: 1.15, child: skeleton),
      );
    }

    final upToken = ev.upTokenId;
    final downToken = ev.downTokenId;
    // Live CLOB odds via a narrowed select — the tile only repaints when
    // ITS up-token price moves.
    final liveUp = ref.watch(
      livePriceProvider.select(
        (s) => upToken != null ? s.prices[upToken] : null,
      ),
    );
    final upFrac = (liveUp ?? ev.upPrice).clamp(0.0, 1.0).toDouble();
    // Up and Down written off the one price, so they add up to 100.
    final odds = formatPolyChancePair(upFrac);
    final countdown = st?.countdownText ?? '--:--';
    final spot = _formatSpot(st?.currentPrice);

    Widget logo(double size) => config.isSvg
        ? SvgPicture.asset(
            config.logoPath,
            width: size,
            height: size,
            fit: BoxFit.contain,
          )
        : Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: config.brandColor,
              borderRadius: BorderRadius.circular(9.r),
            ),
            alignment: Alignment.center,
            child: Image.asset(
              config.logoPath,
              width: size * 0.68,
              height: size * 0.68,
            ),
          );

    // Quiet chip: neutral surface + hairline border. The red pulsing dot
    // stays as the only color (no pastel tint rule).
    Widget countdownPill() => Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: c.surfaceLight,
            border: Border.all(color: c.borderSubtle, width: 0.5),
            // Squared like the rest of the chip language (user decision).
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5.w,
                height: 5.w,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF4444),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 5.w),
              Text(
                countdown,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );

    // Direction entry buttons: solid market colors, no pastel tint
    // (app-wide rule).
    Widget oddsChip({required bool isUp, required String text}) {
      final accent = isUp ? _kPolyGreen : _kPolyRed;
      final onColor = contrastingOnColor(accent);
      return Container(
        padding: EdgeInsets.symmetric(vertical: 6.h),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 14.sp,
              color: onColor,
            ),
            SizedBox(width: 3.w),
            RollingNumberText(
              text: text,
              style: TextStyle(
                color: onColor,
                fontSize: 13.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          config.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 15.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          spot.isEmpty ? '${minutes}m' : '${minutes}m · $spot',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    final Widget body;
    if (wide) {
      body = Row(
        children: [
          logo(34.sp),
          SizedBox(width: 12.w),
          Expanded(child: nameBlock),
          SizedBox(width: 8.w),
          countdownPill(),
          SizedBox(width: 10.w),
          SizedBox(width: 74.w, child: oddsChip(isUp: true, text: odds.first)),
          SizedBox(width: 6.w),
          SizedBox(width: 74.w, child: oddsChip(isUp: false, text: odds.second)),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              logo(28.sp),
              const Spacer(),
              countdownPill(),
            ],
          ),
          const Spacer(),
          nameBlock,
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: oddsChip(isUp: true, text: odds.first)),
              SizedBox(width: 6.w),
              Expanded(child: oddsChip(isUp: false, text: odds.second)),
            ],
          ),
        ],
      );
    }

    if (bare) {
      return LiveTokenScope(
        tokens: [
          if (upToken != null && upToken.isNotEmpty) upToken,
          if (downToken != null && downToken.isNotEmpty) downToken,
        ],
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openDetail(context, ev, minutes),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
            child: body,
          ),
        ),
      );
    }
    final card = GestureDetector(
      onTap: () => _openDetail(context, ev, minutes),
      child: Container(
        height: wide ? 92.h : null,
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(color: c.borderSubtle, width: 0.5),
          boxShadow: context.isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: body,
      ),
    );

    return LiveTokenScope(
      tokens: [
        if (upToken != null && upToken.isNotEmpty) upToken,
        if (downToken != null && downToken.isNotEmpty) downToken,
      ],
      child: RepaintBoundary(
        child: wide ? card : AspectRatio(aspectRatio: 1.15, child: card),
      ),
    );
  }
}

/// Section header used above feed groups: the title, with controls at
/// its right where a section has them (the window chips).
class _SectionHeader extends StatelessWidget {
  final String label;

  /// Controls at the right of the title, such as the window chips.
  final Widget? trailing;

  const _SectionHeader({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 18.h, 16.w, 10.h),
      child: Row(
        children: [
          Expanded(
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
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// In-search loading affordance. A labelled "Searching" state reads more
/// intentionally than a bare spinner when the user is actively typing — they
/// know the app is fetching, not stalled. Centres the staggered dots + the
/// live query echo.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // A browsed category with no open markets gets a neutral compass —
    // it's not a search miss, just an empty surface right now.
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              BootstrapIcons.compass,
              color: c.textTertiary,
              size: 48.sp,
            ),
            SizedBox(height: 16.h),
            Text(
              context.l10n.predictNoOpenMarketsCategory,
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

/// Hero card surfaced at the top of the Predictions listing. Pulls
/// the top market for the active category and renders a live mini
/// chart so the user lands on something animated and current
/// instead of a static grid of cards. Tapping opens the detail sheet.
class HeroEventCard extends ConsumerStatefulWidget {
  final PolymarketEvent event;
  final Map<String, double> livePrices;
  final VoidCallback onTap;
  const HeroEventCard({
    super.key,
    required this.event,
    required this.livePrices,
    required this.onTap,
  });

  @override
  ConsumerState<HeroEventCard> createState() => HeroEventCardState();
}

class HeroEventCardState extends ConsumerState<HeroEventCard> {
  String? _activeTokenId;

  @override
  void initState() {
    super.initState();
    _resolveActiveToken();
  }

  @override
  void didUpdateWidget(covariant HeroEventCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The hero lives at the fixed list slot (index 0) with no Key, so when a
    // refresh swaps in a different top market Flutter reuses this State and
    // initState does NOT re-run. Recompute the chart token here so the mini
    // chart / chance % follow the new event instead of plotting the old
    // market's token.
    if (oldWidget.event.id != widget.event.id) {
      _resolveActiveToken();
    }
  }

  void _resolveActiveToken() {
    final tokens = widget.event.outcomes
        .where((o) => o.tokenId != null && o.tokenId!.isNotEmpty)
        .map((o) => o.tokenId!)
        .toList();
    if (widget.event.isBinary) {
      final yes = widget.event.outcomes
          .where((o) => o.name.toLowerCase() == 'yes')
          .firstOrNull;
      _activeTokenId =
          yes?.tokenId ?? (tokens.isNotEmpty ? tokens.first : null);
    } else {
      _activeTokenId = null;
      final sorted = [...widget.event.outcomes]
        ..sort((a, b) => b.price.compareTo(a.price));
      for (final o in sorted) {
        if (o.tokenId != null && o.tokenId!.isNotEmpty) {
          _activeTokenId = o.tokenId;
          break;
        }
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (tokens.isNotEmpty) {
        ref.read(livePriceProvider.notifier).addTokens(tokens);
      }
    });
  }

  double _liveYes() {
    final event = widget.event;
    final yes =
        event.outcomes.where((o) => o.name.toLowerCase() == 'yes').firstOrNull;
    if (yes?.tokenId != null) {
      final live = widget.livePrices[yes!.tokenId!];
      if (live != null) return live;
    }
    return event.yesPrice;
  }

  String _formatPct(double p) => formatPolyChance(p);

  String _formatEndsIn(DateTime? end) {
    if (end == null) return '';
    final diff = end.difference(DateTime.now());
    final l10n = context.l10n;
    if (diff.isNegative) return l10n.betClosed;
    if (diff.inDays >= 365) {
      return l10n.coinMapAgeShortYears((diff.inDays / 365).floor());
    }
    if (diff.inDays >= 30) {
      return l10n.coinMapAgeShortMonths((diff.inDays / 30).floor());
    }
    if (diff.inDays >= 1) return l10n.coinMapAgeShortDays(diff.inDays);
    if (diff.inHours >= 1) return l10n.coinMapAgeShortHours(diff.inHours);
    return l10n.durationShortMinutes(diff.inMinutes);
  }

  Widget _buildFallbackIcon(AppColorsExtension c) {
    // Route the hero (most prominent card on the surface) through the same
    // category-glyph fallback every MarketCard uses, so an imageless or
    // failed-image hero shows a real crypto/sports/politics icon instead of
    // a coloured letter or '?'. Unknown categories resolve to a compass.
    final tint = polyCategoryTint(widget.event.category, c.textSecondary);
    return Container(
      width: 44.w,
      height: 44.w,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Center(
        child: Icon(
          polyCategoryGlyph(widget.event.category),
          color: tint,
          size: 24.sp,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final event = widget.event;
    final isBinary = event.isBinary;

    double heroProb;
    String heroLabel;
    if (isBinary) {
      heroProb = _liveYes();
      heroLabel = 'Yes';
    } else {
      final sorted = [...event.outcomes].map((o) {
        final live = o.tokenId != null ? widget.livePrices[o.tokenId!] : null;
        return (name: o.name, price: live ?? o.price);
      }).toList()
        ..sort((a, b) => b.price.compareTo(a.price));
      heroProb = sorted.isNotEmpty ? sorted.first.price : 0.0;
      heroLabel = sorted.isNotEmpty ? sorted.first.name : '';
    }

    final accent = isBinary ? const Color(0xFF1FA663) : const Color(0xFF3B82F6);

    final liveData = _activeTokenId != null
        ? ref.watch(
            polymarketLiveChartProvider(
              (tokenId: _activeTokenId!, interval: 'max'),
            ),
          )
        : const <PolymarketPricePoint>[];
    final isLoading = _activeTokenId == null
        ? false
        : ref
            .watch(
              polymarketMarketHistoryProvider(
                (tokenId: _activeTokenId!, interval: 'max'),
              ),
            )
            .isLoading;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(color: c.borderSubtle, width: 0.5),
          boxShadow: context.isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 12.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.endDate != null || !event.hasStarted)
                Builder(builder: (_) {
                  // Accurate status line. THREE states, never a blanket "Live":
                  //   * genuinely in-play (live score/period, not ended) →
                  //     "Live · Ends in X" with the pulse dot.
                  //   * not yet started (future startDate) → neutral
                  //     "Starts in X", no pulse dot.
                  //   * started-but-not-in-play (a normal non-sports market
                  //     that's open) → "Ends in X", no pulse dot, no "Live".
                  // A not-started event with a missing startDate is treated as
                  // NOT started so it can't falsely read as live.
                  final notStarted =
                      !event.hasStarted && event.startDate != null;
                  final inPlay = event.isInPlay;
                  final String statusText;
                  if (notStarted) {
                    statusText = context.l10n
                        .predictStartsIn(_formatEndsIn(event.startDate));
                  } else if (inPlay) {
                    statusText = context.l10n
                        .predictLiveEndsIn(_formatEndsIn(event.endDate));
                  } else {
                    statusText = context.l10n
                        .predictEndsIn(_formatEndsIn(event.endDate));
                  }
                  return Row(
                    children: [
                      if (inPlay) ...[
                        Container(
                          width: 7.w,
                          height: 7.w,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 6.w),
                      ],
                      Text(
                        statusText,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  );
                }),
              SizedBox(height: 14.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    // SVG-aware: Polymarket serves some artwork as SVG.
                    child: event.imageUrl != null
                        ? PolyCrestImage(
                            url: event.imageUrl!,
                            size: 44.w,
                            radius: 12.r,
                            fallback: _buildFallbackIcon(c),
                          )
                        : _buildFallbackIcon(c),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      event.title,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 17.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Expanded so long candidate names like "Will Alex
                  // Zdan be the Republican nominee for Senate in New
                  // Jersey?" can't overflow the card horizontally.
                  // Was previously unconstrained inside a plain Row,
                  // letting the leading subtitle run past the card's
                  // right edge ("RIGHT OVERFLOWED BY 63 PIXELS").
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isBinary
                              ? context.l10n.predictYesChance
                              : context.l10n.predictOutcomeLeading(heroLabel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.textTertiary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          _formatPct(heroProb),
                          style: TextStyle(
                            color: accent,
                            fontSize: 36.sp,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.1,
                            height: 1.0,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              SizedBox(
                height: 88.h,
                width: double.infinity,
                child: isLoading && liveData.length < 2
                    ? SkeletonLineChart(height: 88.h, padding: EdgeInsets.zero)
                    : liveData.length < 2
                        ? const SizedBox.shrink()
                        : CustomPaint(
                            painter: _HeroSparklinePainter(
                              data: liveData.map((p) => p.price).toList(),
                              color: accent,
                              isDark: context.isDark,
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroSparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final bool isDark;

  _HeroSparklinePainter({
    required this.data,
    required this.color,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final w = size.width;
    final h = size.height;
    final stepX = w / (data.length - 1);

    double minV = data.first;
    double maxV = data.first;
    for (final v in data) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final span = (maxV - minV).abs() < 0.001 ? 0.05 : (maxV - minV);
    const padFrac = 0.12;
    double y(double v) {
      final n = ((v - minV) / span).clamp(0.0, 1.0);
      return h * (1 - padFrac) - n * h * (1 - 2 * padFrac);
    }

    final pts = List<Offset>.generate(
        data.length, (i) => Offset(i * stepX, y(data[i])));

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
    } else {
      for (int i = 0; i < pts.length - 1; i++) {
        final p0 = i == 0 ? pts[0] : pts[i - 1];
        final p1 = pts[i];
        final p2 = pts[i + 1];
        final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];
        final c1 =
            Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
        final c2 =
            Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(pts.last, 4, Paint()..color = color);
    canvas.drawCircle(
        pts.last, 2, Paint()..color = isDark ? Colors.black : Colors.white);
  }

  @override
  bool shouldRepaint(covariant _HeroSparklinePainter old) =>
      old.data != data || old.color != color;
}

// EOF

/// Up / Down button for the 5-min crypto banner. Replaces the earlier
/// flat ElevatedButton with a richer two-line layout: an icon disc on
/// the left (white-on-color stamp of the direction arrow), the label
/// and big percentage stacked on the right. Subtle outer border + a
/// faint inner shadow on light mode give the button physical depth
/// rather than the previous "flat-color brick" look.
// The Up/Down badge CTA now renders via the shared MarketPairButton
// (disc icon + glow + rolling percentage line).
