import 'dart:async';
import 'package:kute/screens/shared/kute_page_route.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/screens/shared/kute_blur.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/refresh_everything_provider.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/services/polymarket/polymarket_price_source.dart'
    show CryptoPriceFeed;
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';

import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_user_channel_provider.dart';
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/screens/polymarket/components/crypto_odds_scope.dart';
import 'package:kute/providers/crypto_live_odds_provider.dart';
import 'package:kute/providers/crypto_next_round_provider.dart';
import 'package:kute/screens/polymarket/components/crypto_round_card.dart';
import 'package:kute/screens/polymarket/components/crypto_round_strip.dart';
import 'package:kute/services/polymarket/crypto_round_strip.dart';
import 'package:kute/services/polymarket/crypto_live_odds.dart'
    show cryptoShownUp, cryptoOddsSane;
import 'package:kute/screens/polymarket/components/crypto_asset_logo.dart';
import 'package:kute/screens/polymarket/components/round_window_label.dart';
import 'package:kute/services/polymarket/crypto_next_round.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/shared/animations/premium_group_container.dart';
import 'package:kute/screens/shared/market_groups.dart';
import 'package:kute/screens/polymarket/components/poly_category_icons.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/poly_feed_utils.dart';
import 'package:kute/screens/polymarket/components/poly_game_days.dart';
import 'package:kute/screens/polymarket/components/top_markets_strip.dart';
import 'package:kute/screens/polymarket/group_landing_screen.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show kuteDockScrollClearance;
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show showDepositSheet, MoveLockedSide;
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/home/components/btc_predict_chart.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:intl/intl.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart'
    show placingPolymarketBetProvider;

/// THE deposit door for Predictions (user decision: always the Move sheet,
/// never the legacy quote sheet). When a bet intent is parked waiting on
/// funds, its amount prefills the slider so the user lands on exactly the
/// conversion they need; the intent then auto-fires when the USDC arrives.
///
/// While the policy withholds `polymarket.deposit` the door opens nothing
/// and says why instead, in the shared unavailable sheet.
///
/// A refusal is asked again before it is shown ([confirmCapability]). A
/// region refusal's "Check connection" that finds the door open goes on
/// into the deposit.
Future<void> openPredictionsDeposit(
    BuildContext context, WidgetRef ref) async {
  final decision = await confirmCapability(
      ref.read(runtimeCapabilitiesProvider), 'polymarket.deposit');
  if (!context.mounted) return;
  if (!decision.allowed || decision.comingSoon) {
    if (!await showCapabilityDecisionSheet(context, decision,
            capability: 'polymarket.deposit') ||
        !context.mounted) {
      return;
    }
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

/// The round length, in minutes, of the Crypto page [selection] is on:
/// 5 Min, 15 Min, 1 Hour and 4 Hours are each the live round card of that
/// length and the other coins' rows; null for any other page.
int? polyCryptoPageMinutes(PolyBrowseSelection selection) =>
    selection.pill != PolyPill.crypto
        ? null
        : switch (selection.sub) {
            '5m' => 5,
            '15m' => 15,
            '1h' => 60,
            '4h' => 240,
            _ => null,
          };

/// The Live pill's "Streams" subcategory: games in play with a stream.
const String _kLiveStreams = 'streams';

/// The games in play of one league, and the pill that names it.
typedef _LiveGroup = ({PolySub sub, List<PolymarketEvent> games});

class PolymarketScreen extends ConsumerStatefulWidget {
  final bool autoShowDeposit;
  final bool autoShowWithdraw;

  /// Mounted inside the Investments tab (one balance): the market
  /// browser alone, with no room for the top bar, no hero of its own (the
  /// Investments hero sits above the pills), no dock and no blur band
  /// (the Investments dock is the host's), and no funding doors at all
  /// ([autoShowDeposit] / [autoShowWithdraw] are ignored: money reaches
  /// the venue only through an order).
  final bool embedded;

  const PolymarketScreen(
      {super.key,
      this.autoShowDeposit = false,
      this.autoShowWithdraw = false,
      this.embedded = false});

  /// A pull-to-refresh's part of its own: the list on screen read again.
  /// The account and everything else are the shared refresh
  /// (`refresh_everything_provider.dart`), run beside it by the screen's
  /// own indicator and the Investments page's (which hosts the embedded
  /// browser).
  static void refreshBrowse(WidgetRef ref) {
    final selection = ref.read(polyBrowseSelectionProvider);
    final pill = selection.pill;
    final canBrowse =
        ref.read(runtimeCapabilitiesProvider).allows('polymarket.browse');
    final fiveMinOnly = pill == PolyPill.crypto && selection.sub == '5m';
    // The list on screen and its chips; the other lists keep what they
    // hold. The round cards and rows refresh themselves on a 10s cadence
    // and roll with their rounds, so they're deliberately left out (the
    // longer lengths' "More markets" list under them is read again).
    polyRefreshBrowse(
      query: !canBrowse || fiveMinOnly
          ? null
          : pill == PolyPill.live
              ? const PolyFeedQuery(pill: PolyPill.live)
              : selection.query,
      pill: pill,
      invalidate: ref.invalidate,
    );
  }

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
    _onScrollMetrics(_scrollController.position);
  }

  /// The paging and depth rules on [pos], the list's metrics: read off
  /// the screen's own controller, or, embedded in the Investments page
  /// (where the list has no controller of its own), off the list's
  /// scroll notifications ([_onEmbeddedScroll]).
  void _onScrollMetrics(ScrollMetrics pos) {
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

  /// Embedded: every scroll update and every change of the list's size
  /// runs the paging and depth rules, so a short first page still reads
  /// on until the list fills the screen (the post-frame check the
  /// controller used to make).
  bool _onEmbeddedScroll(Notification notification) {
    if (notification is ScrollUpdateNotification && notification.depth == 0) {
      _onScrollMetrics(notification.metrics);
    } else if (notification is ScrollMetricsNotification &&
        notification.depth == 0) {
      _onScrollMetrics(notification.metrics);
    }
    return false;
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

  /// The category whose subcategories the one browse row shows, in place
  /// of the categories ([PolyDrillRow]); null shows the categories.
  PolyPill? _drilledInto;

  /// Sports one level further down: the sport whose leagues the row shows
  /// ("‹ Soccer", All, the leagues; [polySportLeagueSubsProvider]); null
  /// shows the sports.
  String? _drilledSport;

  /// A selection that names a subcategory other than its category's
  /// default (a deep link, a pick on "More") shows that category's row,
  /// so the chip that is on screen can be seen.
  static PolyPill? _drillFor(PolyBrowseSelection s) {
    final sub = s.subs[s.pill];
    return sub != null && sub != s.pill.defaultSub ? s.pill : null;
  }

  @override
  void initState() {
    super.initState();
    final initial = ref.read(polyBrowseSelectionProvider);
    _drilledInto = _drillFor(initial);
    // A link to a sport with leagues (predictions/sports/soccer) opens on
    // its league row, as the site's page does.
    if (initial.pill == PolyPill.sports && polySportHasLeagues(initial.sub)) {
      _drilledSport = initial.sub;
    }
    // Embedded, the list scrolls inside the Investments page, which
    // drives the nav bar itself; paging reads the notifications instead.
    if (!widget.embedded) _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The widget can be disposed between initState and this post-frame
      // callback (fast navigation in/out of Predictions). Touching `ref`
      // after disposal throws `_assertNotDisposed`, so bail early.
      if (!mounted) return;
      // Warm the builder code now so a slow connection has already
      // answered by the time the person places an order.
      unawaited(PolymarketBackendService.prefetchBuilderCode());
      _autoEnableTrading();
      if (widget.embedded) {
        // Inside Investments the CLOB notifier is born while the shell
        // tab is Investments, not Predictions, so it would start
        // pause-requested on every recreation and nothing would resume
        // it until the next tab switch. Held alive from this mount
        // instead (the screen lives as long as the shell), so the shell
        // policy's resume on the Predictions pill always finds it.
        ref.listenManual(livePriceProvider, (_, __) {});
      }
      if (!widget.embedded &&
          (widget.autoShowDeposit || widget.autoShowWithdraw)) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          if (widget.autoShowDeposit) {
            openPredictionsDeposit(context, ref);
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

  /// A category: its list, and its subcategories in place of the
  /// categories when it has any (the row stays put when it has none).
  void _onPill(PolyPill pill) {
    HapticFeedback.selectionClick();
    setState(() {
      _drilledInto = pill;
      _drilledSport = null;
    });
    final current = ref.read(polyBrowseSelectionProvider);
    if (pill == current.pill) return;
    TrackingService.track('category_pill_tapped',
        params: {'section': pill.key});
    _select(current.copyWith(pill: pill));
  }

  /// A subcategory: its list. A sport with leagues (Soccer, Tennis …)
  /// also drills the row one level further, into its leagues, the
  /// sport's own list on screen meanwhile (as a category does).
  void _onSub(PolySub sub) {
    HapticFeedback.selectionClick();
    final current = ref.read(polyBrowseSelectionProvider);
    if (current.pill == PolyPill.sports && polySportHasLeagues(sub.key)) {
      setState(() => _drilledSport = sub.key);
    }
    if (sub.key == current.sub) return;
    TrackingService.track('category_pill_tapped', params: {
      'section': current.pill.key,
      'subcategory': sub.route,
    });
    _select(current.copyWith(sub: sub.key));
  }

  /// The back pill: the categories again, the category still on screen
  /// at its default list (as when it is picked).
  void _onBack(PolyPill parent) {
    HapticFeedback.selectionClick();
    TrackingService.track('category_row_back_tapped', params: {
      'surface': 'predictions',
      'parent': parent.key,
    });
    setState(() {
      _drilledInto = null;
      _drilledSport = null;
    });
    final current = ref.read(polyBrowseSelectionProvider);
    if (current.sub != parent.defaultSub) {
      _select(current.copyWith(sub: parent.defaultSub));
    }
  }

  /// The league row's back pill ("‹ Soccer"): the sports again, the sport
  /// still on screen at its own list.
  void _onSportBack(String sport) {
    HapticFeedback.selectionClick();
    TrackingService.track('category_row_back_tapped', params: {
      'surface': 'predictions',
      'parent': PolyPill.sports.key,
      'subcategory': sport,
    });
    setState(() => _drilledSport = null);
    final current = ref.read(polyBrowseSelectionProvider);
    if (current.sub != sport) _select(current.copyWith(sub: sport));
  }

  /// The league row a selection made elsewhere (a deep link, the category
  /// sheet, "More") belongs on: the sport of a league that is not pinned
  /// on the Sports row itself; null for a chip of the Sports row.
  String? _sportDrillFor(PolyBrowseSelection s) {
    if (s.pill != PolyPill.sports) return null;
    var sub = s.subs[PolyPill.sports] ?? '';
    if (sub.startsWith('route:')) {
      final route = sub.substring(6);
      sub = ref
              .read(polySportsLeaguesProvider)
              .where((l) => l.route == route)
              .firstOrNull
              ?.key ??
          sub;
    }
    return polySportOfLeague(
        sub, ref.read(polySportsDirectoryProvider).valueOrNull ?? const []);
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
        if (mounted) {
          setState(() {
            _drilledInto = pill;
            // A sport with leagues opens on its league row.
            _drilledSport = pill == PolyPill.sports && polySportHasLeagues(sub.key)
                ? sub.key
                : null;
          });
        }
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
    ref.listen<PolyBrowseSelection>(polyBrowseSelectionProvider, (prev, next) {
      // Moving between the round lengths' pages (Crypto › 5 Min, 15 Min,
      // 1 Hour, 4 Hours) is the length change the card's chips used to
      // make: the same event, the same figures.
      final from = prev == null ? null : polyCryptoPageMinutes(prev);
      final to = polyCryptoPageMinutes(next);
      if (from != null && to != null && from != to) {
        TrackingService.track('crypto_window_changed',
            params: {'minutes': to, 'from_minutes': from});
      }
      final drill = _drillFor(next);
      // A pick drills in; the reset when the pill is left drills out.
      final reset = next.pill == PolyPill.trending && next.subs.isEmpty;
      if (drill != _drilledInto && (drill != null || reset)) {
        setState(() => _drilledInto = drill);
      }
      // A league picked elsewhere opens its sport's row; another pill, or
      // a chip of the Sports row itself, closes it.
      final sport = _sportDrillFor(next);
      if (sport != null && sport != _drilledSport) {
        setState(() => _drilledSport = sport);
      } else if (_drilledSport != null &&
          (next.pill != PolyPill.sports ||
              (PolySub(next.sub).seriesId == null &&
                  next.sub != _drilledSport))) {
        setState(() => _drilledSport = null);
      }
    });
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
    // A deep link names a tag or league by its readable segment (a
    // league by its Gamma `/sports` code, whichever row it is on).
    if (selection.sub.startsWith('route:')) {
      final route = selection.sub.substring(6);
      for (final s in [
        ...subs,
        if (pill == PolyPill.sports) ...ref.watch(polySportsLeaguesProvider),
      ]) {
        if (s.route == route) selection = selection.copyWith(sub: s.key);
      }
    }
    // Sports › a sport with leagues: the row one level further down, the
    // sport's chip reading All before its leagues.
    final sport = pill == PolyPill.sports ? _drilledSport : null;
    final leagueSubs = sport == null
        ? const <PolySub>[]
        : ref.watch(polySportLeagueSubsProvider(sport));
    // The one browse row shows the subcategories of the category drilled
    // into, while it has a row of them.
    final drilled = _drilledInto == pill && subs.length > 1;
    // A sport or a league: its games by day, then its other markets
    // (founder, 9 November 2026: "get rid of this props thing").
    final sportList = pill == PolyPill.sports &&
        (kPolySportGroups.contains(selection.sub) ||
            PolySub(selection.sub).seriesId != null);
    // Live always reads the one list of games in play; a league pill
    // narrows it on screen.
    final query = pill == PolyPill.live
        ? const PolyFeedQuery(pill: PolyPill.live)
        : selection.query;
    // Crypto › 5 Min, 15 Min, 1 Hour, 4 Hours: the live round card of that
    // length and the other coins' rows (founder, 12 November 2026: "the 15
    // min markets and 1 h and such [should] have the same live chart
    // design"); 5 Min is nothing else, the longer lengths keep the rest of
    // their list under the rows ("More markets").
    final roundMinutes = polyCryptoPageMinutes(selection);
    final fiveMinOnly = roundMinutes == 5;
    final showHeroSection = roundMinutes != null;
    final showHeroPinned = pill == PolyPill.crypto && selection.sub == 'all';
    // Where the round card is the point of the page; once per mount, no
    // market data attached.
    if (canBrowse && !_heroViewed && (showHeroSection || showHeroPinned)) {
      _heroViewed = true;
      Future.microtask(() => TrackingService.track('predict_hero_viewed'));
    }
    final isLiveList = pill == PolyPill.live ||
        (pill == PolyPill.sports && selection.sub == 'live');

    // The default view (Trending at its default list) opens on the strip;
    // its list is polymarket.com's own, whole, page after page, as any
    // other category's.
    final defaultView =
        pill == PolyPill.trending && selection.sub == pill.defaultSub;
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
    // list fills the screen or ends (embedded, the list's metrics
    // notifications do this, see [_onEmbeddedScroll]).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (pos.hasContentDimensions && pos.extentAfter < 900) _loadMore();
    });

    // Live › a league: just that league's games, under no heading.
    final liveLeague = pill == PolyPill.live && selection.sub != 'all'
        ? selection.sub
        : null;

    // NOTE: live CLOB prices and sports scores are watched PER CARD
    // inside [_PolyFeedCard] with narrow
    // selects — watching them here rebuilt this entire screen (every
    // sliver, every section) on every WS price tick, which is what made
    // the whole browse experience stutter.

    // The browser's own scroll view. Embedded in Investments it is the
    // body of that page's nested scroll: it takes the page's primary
    // (inner) controller so the hero and pills above it scroll away
    // first, the page's own indicator refreshes it, and its list runs
    // under the host's dock.
    final embedded = widget.embedded;
    final list = CustomScrollView(
                  controller: embedded ? null : _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  slivers: [
                    // Clears the integrated top nav bar (avatar + tabs).
                    if (!embedded)
                      SliverToBoxAdapter(child: SizedBox(height: 64.h)),

                    // Hero balance, like the main screen (user decision:
                    // the balance lives at the top of each pool screen,
                    // above the ongoing bets, not on the bottom bar).
                    // Its own ConsumerWidget so balance/position/pending
                    // ticks rebuild ONLY the header, not the whole scroll
                    // view (the old inline Builder used the screen's ref).
                    // Inside Investments the one-balance hero above the
                    // pills is the hero.
                    if (!embedded)
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
                      // ── Categories: ONE side-scrolling row of pills
                      // under the balance. A category with subcategories
                      // drills in: the row becomes "‹ Category" and its
                      // subcategories. Both filter the list below in place.
                      // Inside Investments the page's own pill carries
                      // the category (investments_category_sheet.dart).
                      if (!embedded)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(top: 4.h),
                          child: PolyDrillRow(
                            drilledInto: drilled ? (sport ?? pill) : null,
                            builder: (context, revealOnMount) => drilled &&
                                    sport != null
                                ? PolySubRow(
                                    pill: pill,
                                    subs: leagueSubs,
                                    selectedKey: selection.sub,
                                    onSelect: _onSub,
                                    onBack: () => _onSportBack(sport),
                                    backLabel:
                                        polySubLabel(l10n, PolySub(sport)),
                                    allKey: sport,
                                    revealOnMount: revealOnMount,
                                  )
                                : drilled
                                ? PolySubRow(
                                    pill: pill,
                                    subs: subs,
                                    // The site's groups, a divider between
                                    // them (Crypto, Finance); Live's row
                                    // is read off its list and stays flat.
                                    groups: pill == PolyPill.live
                                        ? null
                                        : polySubGroups(pill, subs),
                                    selectedKey: selection.sub,
                                    onSelect: _onSub,
                                    onBack: () => _onBack(pill),
                                    revealOnMount: revealOnMount,
                                  )
                                : PolyPillRow(
                                    pills: pills,
                                    selected: pill,
                                    onSelect: _onPill,
                                    onMore: () => _onMore(pills),
                                    revealOnMount: revealOnMount,
                                  ),
                          ),
                        ),
                      ),

                      // The list under the pills fades in when the pill
                      // or the subcategory changes (never on a refresh);
                      // only an opacity runs, so paging and the scroll
                      // position are untouched.
                      SliverSelectionFade(
                        selection: (pill, selection.sub),
                        slivers: [
                          // ── The BTC Up-or-Down hero card, under its window
                          // chips and no title (founder, October 2026).
                          // Under Crypto › 5 Min, with the other assets'
                          // card. Never on Trending any more (founder, 8
                          // November 2026): Crypto › 5 Min is its home.
              if (roundMinutes != null) ..._roundPageSlivers(roundMinutes),

                          // No heading over the list: the selected pill
                          // (or subcategory) already names it (October
                          // 2026).

                          // The hero alone pinned first under Crypto › All.
                          if (showHeroPinned) _heroSliver(),

              if (roundMinutes != null && !fiveMinOnly)
                ..._moreRoundMarketsSlivers(feed,
                    query: query, minutes: roundMinutes)
              else if (!fiveMinOnly)
                            ..._feedSlivers(
                              feed,
                              query: query,
                              isLiveList: isLiveList,
                              liveLeague: liveLeague,
                              defaultView: defaultView,
                              sportList: sportList,
                            ),
                        ],
                      ),
                    ],
                    // Bottom clearance above the floating action bar (the
                    // host's dock when embedded).
                    SliverToBoxAdapter(
                        child: SizedBox(
                            height: embedded
                                ? kuteDockScrollClearance(context)
                                : _bottomDockHeight + 24.h)),
                  ],
                );
    if (embedded) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: NotificationListener<Notification>(
          onNotification: _onEmbeddedScroll,
          child: list,
        ),
      );
    }
    final scroll = RefreshIndicator(
      onRefresh: _onRefresh,
      color: c.textPrimary,
      backgroundColor: c.surface,
      child: list,
    );

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
            PlatformSafeArea(child: scroll),

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

  /// Crypto › 5 Min, 15 Min, 1 Hour, 4 Hours: one page, polymarket.com's
  /// round page made for a phone (founder, 12 November 2026: "look at how
  /// it is on the polymarket website, make it better please"): the BTC
  /// round card of that length, full size ([CryptoRoundHeroCard]: "BTC 5
  /// min up or down card should be bigger"), the lengths as a row of pills,
  /// then the other coins' rows at the same length.
  List<Widget> _roundPageSlivers(int minutes) => [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
            child: RepaintBoundary(
              child: CryptoPredictBanner(
                key: ValueKey('crypto-round-page-$minutes'),
                config: kCryptoPredictAssets.first,
                roundMinutes: minutes,
                chartHeight: CryptoPredictBanner.kPageChartHeight,
                onDeposit: () {
                  openPredictionsDeposit(context, ref);
                },
            ),
          ),
        ),
        ),
        // The lengths, polymarket.com's "5 Min | 15 Min | 1 Hour" row: the
        // whole page switches, the same page the Crypto row's length
        // chips open.
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 10.h),
            child: _CryptoLengthTabs(
              selected: minutes,
              onSelect: (sub) => _onSub(PolySub(sub)),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: _MoreCryptoMarketsCard(
              minutes: minutes,
              onDeposit: () {
                openPredictionsDeposit(context, ref);
              },
            ),
          ),
        ),
      ];

  /// The rest of a longer length's list under its rows (Crypto › 15 Min,
  /// 1 Hour, 4 Hours): every market the list holds but the rounds the card
  /// and the rows already show (BTC, ETH, SOL and XRP at this length):
  /// the other coins' and metals' rounds and the hourly "above" markets,
  /// under "More markets". Nothing while there is nothing else.
  List<Widget> _moreRoundMarketsSlivers(PolyFeedState feed,
      {required PolyFeedQuery query, required int minutes}) {
    final shown = {for (final c in kCryptoPredictAssets) c.asset};
    bool onRows(PolymarketEvent e) {
      final round = polyCryptoRoundOf(e.slug, endDate: e.endDate);
      return round != null &&
          round.window.inMinutes == minutes &&
          shown.contains(polyRoundTicker(round.asset));
    }

    final rest = feed.copyWith(events: [
      for (final e in feed.events)
        if (!onRows(e)) e,
    ]);
    if (rest.events.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: _SectionHeader(
            key: const ValueKey('crypto-round-more-markets'),
            label: context.l10n.polyMoreMarkets),
      ),
      ..._feedSlivers(rest,
          query: query, isLiveList: false, source: 'feed_card'),
    ];
  }

  /// Once-per-mount flag of `predict_hero_viewed`.
  bool _heroViewed = false;

  Widget _heroSliver() => SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
          child: RepaintBoundary(
            child: CryptoPredictBanner(
              config: kCryptoPredictAssets.first,
              showLiveIndicator: true,
              compact: true,
              onDeposit: () {
                openPredictionsDeposit(context, ref);
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
    bool defaultView = false,
    String source = 'feed_card',
    bool sportList = false,
  }) {
    if (feed.events.isEmpty) {
      if (feed.loading) {
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 8.h),
              // The grouped card the list lands in, with skeleton rows.
              child: PremiumGroupContainer(
                child: SkeletonRowList(
                  count: 4,
                  padding: EdgeInsets.zero,
                  rowPadding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                ),
              ),
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
    } else if (sportList) {
      body = _sportSlivers(feed.events, source: source);
    } else {
      final open = feed.events.where((e) => !e.ended).toList(growable: false);
      final events = collapseByGameId(open);
      final siblings = siblingsByGameId(open);
      // The list's first Yes/No markets as big cards in a side-scrolling
      // strip, on the default view only (founder, 1 November 2026). The list
      // under it is polymarket.com's Trending in the site's order, without
      // the strip's markets (founder, 9 November 2026: no repeats).
      final split = polyTrendingSplit(
          defaultView ? polyTopMarkets(open) : const <PolymarketEvent>[],
          events);
      final top = split.top;
      final listed = split.listed;
      // Plain Yes/No markets share one grouped card like Home's
      // Activity; an event with many outcomes or a game keeps its own
      // card and breaks the group (founder, October 2026).
      body = [
        // No title over the strip (founder, 1 November 2026): the big
        // cards simply open the feed.
        if (top.isNotEmpty) ...[
          SliverToBoxAdapter(child: SizedBox(height: 8.h)),
          SliverToBoxAdapter(child: _topMarketsStrip(top)),
          SliverToBoxAdapter(child: SizedBox(height: 8.h)),
        ],
        SliverToBoxAdapter(child: SizedBox(height: 8.h)),
        ..._groupedSlivers(
            listed,
            (market) => (
                  isSportsCategory: market.category == 'sports',
                  siblings: market.gameId != null
                      ? (siblings[market.gameId!] ?? const <PolymarketEvent>[])
                      : const <PolymarketEvent>[],
                ),
            source: source),
        SliverToBoxAdapter(child: SizedBox(height: 8.h)),
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

  /// The Top markets strip: a card opens the market page as a list card
  /// does, marked as from the strip.
  Widget _topMarketsStrip(List<PolymarketEvent> top) => PolyTopMarketsStrip(
        markets: top,
        // The chart's history starts reading as the finger comes down.
        onOpenDown: MarketDetailSheet.prefetch,
        onOpen: (market) {
          HapticFeedback.mediumImpact();
          MarketDetailSheet.show(
            context,
            event: market,
            onDeposit: () async {
              if (context.mounted) openPredictionsDeposit(context, ref);
            },
            source: 'top_markets',
          );
        },
      );

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

  /// A sport's or a league's list, every market of it in one list
  /// (founder, 9 November 2026: "Why are we separating games and props?
  /// Get rid of this props thing"): the matches first, by day in kickoff
  /// order under the day's heading (the games in play first, under Live;
  /// poly_game_days.dart), each match one card with its other markets
  /// folded in; then everything else (season awards, outrights, player
  /// totals) under the Sports row's own "Futures" heading, the same
  /// heading the days wear, or with no heading when the list has no match.
  /// A list with nothing open reads as an empty category.
  List<Widget> _sportSlivers(List<PolymarketEvent> events,
      {String source = 'feed_card'}) {
    final open = events.where((e) => !e.ended).toList(growable: false);
    if (open.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 40.h),
            child: const _EmptyState(),
          ),
        ),
      ];
    }
    final split = polySplitGamesProps(open);
    final games = split.games;
    final siblings = siblingsByGameId(games);
    final locale = Localizations.localeOf(context).toString();
    final l10n = context.l10n;
    final slivers = <Widget>[];
    for (final day
        in polyGameDays(collapseByGameId(games), now: DateTime.now())) {
      final label = day.label(l10n, locale);
      if (label != null) {
        slivers.add(SliverToBoxAdapter(child: _SectionHeader(label: label)));
      } else {
        slivers.add(SliverToBoxAdapter(child: SizedBox(height: 8.h)));
      }
      slivers.addAll(_groupedSlivers(
          day.games,
          (market) => (
                isSportsCategory: true,
                siblings: market.gameId != null
                    ? (siblings[market.gameId!] ?? const <PolymarketEvent>[])
                    : const <PolymarketEvent>[],
              ),
          source: source));
    }
    if (split.props.isNotEmpty) {
      slivers.add(SliverToBoxAdapter(
          child: games.isEmpty
              ? SizedBox(height: 8.h)
              : _SectionHeader(label: l10n.polySubFutures)));
      slivers.addAll(_groupedSlivers(
          split.props,
          (_) => (isSportsCategory: true, siblings: const <PolymarketEvent>[]),
          source: source));
    }
    slivers.add(SliverToBoxAdapter(child: SizedBox(height: 8.h)));
    return slivers;
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
      return _groupedSlivers(streams, (_) => _kLiveRow);
    }
    for (final group in _liveGroups(events)) {
      if (only != null && group.sub.key != only) continue;
      if (only == null) {
        slivers.add(SliverToBoxAdapter(
          child: _SectionHeader(label: polySubLabel(context.l10n, group.sub)),
        ));
      }
      slivers.addAll(_groupedSlivers(group.games, (_) => _kLiveRow));
    }
    return slivers;
  }

  /// [events] as list slivers: runs of plain Yes/No markets in one
  /// grouped card, every other market its own card ([marketGroupSlivers]).
  /// [rowOf] says how a market's row reads its sport and its match's
  /// other markets.
  List<Widget> _groupedSlivers(
    List<PolymarketEvent> events,
    ({bool isSportsCategory, List<PolymarketEvent> siblings}) Function(
            PolymarketEvent market)
        rowOf, {
    String source = 'feed_card',
  }) =>
      marketGroupSlivers<PolymarketEvent>(
        context,
        items: events,
        groups: (e) => polyCardGroups(e.title, e.outcomes),
        dividerIndent: polyGroupRowIndent(),
        divider: polyGroupRowDivider,
        build: (market, inGroup) {
          final row = rowOf(market);
          return _PolyFeedCard(
            market: market,
            isSportsCategory: row.isSportsCategory,
            matchSiblings: row.siblings,
            inGroup: inGroup,
            source: source,
          );
        },
      );

  Future<void> _onRefresh() {
    PolymarketScreen.refreshBrowse(ref);
    return ref.read(refreshEverythingProvider)(
        const RefreshTrigger('polymarket'));
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
/// A game in play's row: a sports row, no other markets of its match.
const ({bool isSportsCategory, List<PolymarketEvent> siblings}) _kLiveRow =
    (isSportsCategory: true, siblings: <PolymarketEvent>[]);

class _PolyFeedCard extends ConsumerWidget {
  final PolymarketEvent market;
  final bool isSportsCategory;

  /// Extra sub-markets for this match (Both Teams to Score, O/U,
  /// corners …) that `collapseByGameId` folded away. Surfaced as a
  /// "+N more markets" affordance opening the grouped match view.
  final List<PolymarketEvent> matchSiblings;

  /// A row of a grouped list card ([MarketCard.inGroup]).
  final bool inGroup;

  /// Where the market page and the slip say they were opened from.
  final String source;

  const _PolyFeedCard({
    required this.market,
    required this.isSportsCategory,
    this.matchSiblings = const <PolymarketEvent>[],
    this.inGroup = false,
    this.source = 'feed_card',
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
          inGroup: inGroup,
          title: roundAsset == null
              ? market.displayTitle
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
                    KutePageRoute(
                      builder: (_) => GroupLandingScreen.events(
                        title: market.displayTitle,
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
                if (context.mounted) openPredictionsDeposit(context, ref);
              },
              source: source,
            );
          },
          // A pill opens the slip straight on its side (a Yes / No, an
          // outcome's Yes, a team), the way the market page's own buttons
          // do. Nothing is placed before Confirm there.
          onPickSide: (pick) => polyCardOpenSlip(
            context,
            event: market,
            pick: pick,
            onDeposit: () async {
              if (context.mounted) openPredictionsDeposit(context, ref);
            },
            source: source,
          ),
        ),
      ),
    );
  }
}

/// The live crypto Up/Down round card. Full size ([CryptoRoundHeroCard]) on
/// Predictions › Crypto › 5 Min, 15 Min, 1 Hour and 4 Hours, in the round's
/// own sheet (`FiveMinMarketDetailSheet`) and on Ledger Predictions;
/// compact ([CompactCryptoCard]) pinned under Crypto › All. Its buttons bet
/// the round in play until its cutoff, then the next round by themselves;
/// the full card's round row lets the person pick another
/// (crypto_next_round.dart, crypto_round_strip.dart).
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

  /// The Predictions browse's card (founder, 1 November 2026: the full
  /// card stood ~600 px tall over the list): about 180 px, the same data
  /// and actions in one header row (logo, title, past rounds as dots, the
  /// countdown pill), one price row (live price, its move against the
  /// target, the target), a 40 px sparkline with the dashed target line,
  /// and the Up / Down pills with their odds ([CompactCryptoCard]). The
  /// market page keeps the full card. On both the round on show is the one
  /// in play; the buttons bet it until its cutoff, then the next round
  /// (founder, 12 November 2026; crypto_next_round.dart), the line over
  /// them naming the round ("Now · Ends in 02:16", "Next · Starts in
  /// 01:12").
  final bool compact;

  /// Where the slip says it was opened from (`polymarket_bet_slip_opened`'s
  /// `source`, `polymarket_bet_placed`'s `entry_source`).
  final String slipSource;

  /// The round length the card shows, fixed: Predictions › Crypto › 5 Min,
  /// 15 Min, 1 Hour or 4 Hours and the round sheet opened from their rows,
  /// read from that length's own round feed ([cryptoRoundProvider], which
  /// draws a longer round's chart from its start). Null: the shared choice
  /// ([cryptoPredictWindowProvider]), five minutes for [targetWindowEpoch].
  final int? roundMinutes;

  /// The full card's chart height: 200 on the round sheet, shorter on the
  /// Crypto length pages ([kPageChartHeight]).
  final double chartHeight;

  /// The chart's height on the Crypto length pages' card (founder, 12
  /// November 2026: "BTC 5 min up or down card should be bigger"): about
  /// twice the list card's sparkline, so the card stands larger while the
  /// first coin's row still shows under it on a 393 pt phone.
  static const double kPageChartHeight = 104;

  const CryptoPredictBanner({
    super.key,
    required this.config,
    this.onDeposit,
    this.ledgerWalletId,
    this.targetWindowEpoch,
    this.showLiveIndicator = false,
    this.compact = false,
    this.slipSource = 'crypto_banner',
    this.roundMinutes,
    this.chartHeight = 200,
  });

  /// A round length written short, as the titles write it: "5m", "15m",
  /// "1h", "4h".
  static String lengthLabel(int minutes) =>
      minutes % 60 == 0 ? '${minutes ~/ 60}h' : '${minutes}m';

  static String _formatDiff(double diff) => formatCryptoRoundDiff(diff);

  /// The time until the next round starts, as the card's countdown writes
  /// it: "02:16" for the minutes-long rounds, "3:59:59" once a round is an
  /// hour or longer, never "239:59".
  static String _startsInText(int seconds, int minutes) =>
      cryptoRoundClockText(seconds, minutes);

  String _formatPrice(double? price) => formatCryptoRoundPrice(price);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Route to the window-scoped provider when the caller asked for a
    // specific upcoming round; otherwise keep the legacy current-window
    // provider so the rest of the app is unaffected.
    final fixed = roundMinutes;
    final ProviderListenable<AsyncValue<CryptoPredictState>> source =
        fixed != null
            ? cryptoRoundProvider((asset: config.asset, minutes: fixed))
            : targetWindowEpoch == null
                ? cryptoPredictProvider(config.asset)
                : cryptoPredictAtWindowProvider((
            asset: config.asset,
            epochSeconds: targetWindowEpoch,
                  ));
    final predictAsync = ref.watch(source);
    final predictState = predictAsync.asData?.value;
    // The window length on screen: the page's own, the shared choice for
    // the rolling card, five minutes for a specific window.
    final int minutes = fixed ??
        (targetWindowEpoch == null
        ? ref.watch(cryptoPredictWindowProvider)
            : 5);
    final countdown =
        _startsInText(predictState?.secondsRemaining ?? minutes * 60, minutes);
    final priceStr = _formatPrice(predictState?.currentPrice);

    // Don't render if event couldn't be loaded (asset not on Polymarket)
    if (predictAsync.hasError && !predictAsync.hasValue) {
      return const SizedBox.shrink();
    }

    // One-time #156 debug — log the token IDs the first time the
    // event lands so we can verify they're populated end-to-end. If
    // these come through null/empty the live-price subscription is a
    // no-op and the bar stays at the polled-stale 50/50.
    ref.listen<AsyncValue<CryptoPredictState>>(
      source,
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
    // The [LiveTokenScope] wrapping this banner (see the return below)
    // keeps the round on show's up/down CLOB tokens and the next round's
    // on the order-book socket, re-registering them when the window rolls
    // to new tokens; the [CryptoOddsScope] inside it registers the next
    // round's Up token with [cryptoLiveOddsProvider], whose change
    // repaints the buttons. Their odds are the next round's live book
    // ([polyNextRoundUp]), never Gamma's price.
    final upTokenId = predictState?.event?.upTokenId;
    final downTokenId = predictState?.event?.downTokenId;

    final event = predictState?.event;
    final priceToBeat = predictState?.priceToBeat;
    final priceToBeatStr = _formatPrice(priceToBeat);
    // How far the live price is from the price to beat, as polymarket.com
    // prints it beside the current price ("▲ $12.34"), in the market's
    // up/down colors.
    final currentPrice = predictState?.currentPrice;
    final double? diffToBeat = currentPrice != null && priceToBeat != null
        ? currentPrice - priceToBeat
        : null;
    // The round on show: the card's own event while it is one of this
    // length (it rolls forward a second or two after the clock), else the
    // clock's.
    final now = ref.read(cryptoOddsClockProvider)();
    final nowEpoch = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    final showing = predictState?.event;
    final shownFrom = showing?.windowStartTime;
    final shownTo = showing?.endDate;
    final liveStart = shownFrom != null &&
            shownTo != null &&
            shownTo.difference(shownFrom).inMinutes == minutes
        ? shownFrom.millisecondsSinceEpoch ~/ 1000
        : polyRoundStartAt(now, minutes);
    final nextStart = liveStart + minutes * 60;
    // The windows before this one, for the round row's dots.
    final resultsKey = predictState?.event == null
        ? null
        : (asset: config.asset, minutes: minutes, currentStart: liveStart);
    final pastResults = resultsKey == null
        ? const <CryptoWindowResult>[]
        : ref.watch(cryptoRecentResultsProvider(resultsKey)).valueOrNull ??
            carriedCryptoResults(
                resultsKey.asset, resultsKey.minutes, resultsKey.currentStart);

    // Where the buttons bet (founder, 12 November 2026: "the current bet
    // until some time and then it's the next one"; crypto_next_round.dart,
    // crypto_round_strip.dart): the round row under the chart offers the
    // round in play, the next and the one after; by default the buttons
    // stand on the round in play until its cutoff (two minutes into a
    // five-minute round, the last 3, 5 and 10 minutes of a 15-minute,
    // hourly and four-hour one), then on the next one by themselves. A tap
    // on a round overrides that until it starts (a round ahead) or reaches
    // its cutoff (the round in play). A round ahead is bet at its live book
    // once it has real prices, the round in play at its live odds; the line
    // over the buttons names the round ("Now · Ends in 02:16", "Next ·
    // Starts in 01:12", "· No prices yet" while it has none). A card of one
    // given window has no row and bets that window. The tap below bets the
    // round this very build painted.
    final hasStrip = targetWindowEpoch == null;
    final aheadStarts =
        hasStrip ? polyStripAheadStarts(liveStart, minutes) : const <int>[];
    final slugAsset = config.asset.toLowerCase();
    final ahead = <int, Btc5MinEvent?>{
      for (final start in aheadStarts)
        start: ref
            .watch(cryptoNextRoundProvider(
                (asset: slugAsset, minutes: minutes, start: start)))
            .valueOrNull,
    };
    // A new chance of a round ahead or of the round in play repaints; the
    // books are read here.
    for (final e in ahead.values) {
      final t = e?.upTokenId;
      ref.watch(
          cryptoLiveOddsProvider.select((s) => t == null ? null : s[t]?.up));
    }
    final liveUp = ref.watch(cryptoLiveOddsProvider
        .select((s) => upTokenId == null ? null : s[upTokenId]?.up));
    final books = ref.read(cryptoOddsBooksProvider);
    // The round in play can be bet only while it runs: Gamma answers with
    // the round that just ended until the next one is listed.
    final liveEvent = switch (showing) {
      final e? when e.endDate?.isAfter(now) ?? false => e,
      _ => null,
    };
    // The rounds the person holds or is buying, marked on the row: the
    // spending wallet's, so a Ledger's card marks none.
    final held = hasStrip && ledgerWalletId == null
        ? <String>{
            for (final b in ref.watch(placingPolymarketBetProvider))
              if (b.eventSlug case final s?) s.toLowerCase(),
            for (final p in ref.watch(polymarketActivePositionsProvider))
              if (p.eventSlug case final s?) s.toLowerCase(),
          }
        : const <String>{};
    final rounds = polyRoundStrip(
      asset: config.asset,
          minutes: minutes,
      now: now,
      past: pastResults,
      live: liveEvent,
      ahead: ahead,
      books: books.snapshot,
      heldSlugs: held,
      shownStart: liveStart,
    );
    final pickKey = (asset: config.asset, minutes: minutes);
    final picked =
        hasStrip ? ref.watch(cryptoPickedRoundProvider(pickKey)) : null;
    final int betStart = hasStrip
        ? polyRoundSelectedStart(rounds: rounds, now: now, picked: picked)
        : liveStart;
    final selected = rounds.firstWhere((r) => r.start == betStart);
    final onLive = selected.slot == PolyRoundSlot.live;
    // The chance on the buttons: the round in play's live odds (else
    // Gamma's polled price) while it takes bets; a round ahead's live book
    // once it has real prices. Null: the buttons are disabled.
    final double? betUp = !selected.selectable
        ? null
        : onLive
            ? polyCurrentRoundUp(
                event: liveEvent, start: liveStart, liveUp: liveUp)
            : (() {
                final t = selected.event?.upTokenId;
                final up = cryptoShownUp(t == null ? null : books.snapshot(t));
                return cryptoOddsSane(up) ? up : null;
              })();
    final Btc5MinEvent? betEvent = onLive ? liveEvent : selected.event;
    final canBet = betUp != null && betEvent != null;
    final double buttonsUpFrac = betUp ?? 0.5;
    final use24h = MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false;
    String clock(DateTime t) =>
        polyRoundClock(t, locale: context.l10n.localeName, use24h: use24h);
    DateTime at(int epoch) =>
        DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
    // The round the buttons bet on, by the same name the slip, the receipt
    // and the position carry; read out with each button.
    final String roundName = context.l10n.predictRoundWindow(
        config.asset, clock(at(betStart)), clock(at(betStart + minutes * 60)));
    // The line over the buttons: "Now · Ends in 02:16", "Next · Starts in
    // 01:12", "7:25 · Starts in 06:12"; "· No prices yet" while the round
    // has none.
    final String roundLine = switch (selected.slot) {
      PolyRoundSlot.live => context.l10n.predictRoundNow(context.l10n
          .predictEndsIn(_startsInText(nextStart - nowEpoch, minutes))),
      PolyRoundSlot.next => context.l10n.predictNextWindow(context.l10n
          .predictStartsIn(_startsInText(betStart - nowEpoch, minutes))),
      _ => '${clock(at(betStart))} · '
          '${context.l10n.predictStartsIn(_startsInText(betStart - nowEpoch, minutes))}',
    };
    final String nextLine = canBet
        ? roundLine
        : '$roundLine · ${context.l10n.predictRoundNoPricesYet}';

    void pick(PolyStripRound round) {
      TrackingService.track('predictions_instant_round_picked', params: {
        'which': polyRoundPickWhich(round),
        'length': lengthLabel(minutes),
        'seconds_to_start': round.start - nowEpoch,
      });
      ref.read(cryptoPickedRoundProvider(pickKey).notifier).state = round.start;
    }

    final String? feedName = switch (predictState?.feed) {
      CryptoPriceFeed.binance => 'Binance',
      CryptoPriceFeed.coingecko => 'CoinGecko',
      _ => null,
    };
    // The card paints the moment Gamma's event lands; the figures fall
    // back to a skeleton until the first price arrives.
    final isInitialLoading = predictState == null || predictState.event == null;

    // One slip door for every layout, on the round the buttons showed when
    // they were painted: the slip stays on it whatever the card does while
    // it is open, at the odds on the button. The round's end goes with it
    // (the short-round funding rules key off it), the round's own when
    // Gamma omitted it. [amount] fills the slip's amount in (a quick
    // amount): nothing is placed, funded or approved until Confirm there.
    void openSide(String side, {double? amount}) {
      final up = betUp;
      final target = betEvent;
      if (up == null || target == null) return;
      if (hasStrip) {
        ref.read(cryptoQuickSideProvider(pickKey).notifier).state = side;
      }
      final outcomes = [
        PolymarketOutcome(
            name: 'Up',
            price: up,
            tokenId: target.upTokenId,
            conditionId: target.conditionId),
        PolymarketOutcome(
            name: 'Down',
            price: 1 - up,
            tokenId: target.downTokenId,
            conditionId: target.conditionId),
      ];
      BetSlipSheet.show(context,
          marketQuestion: target.title.isNotEmpty
              ? target.title
              : context.l10n.predictUpOrDown(config.asset, minutes),
          marketSlug: target.slug,
          marketImage: target.image,
          outcomes: outcomes,
          initialOutcomeIndex: side == 'down' ? 1 : 0,
          initialAmountUsd: amount,
          marketEndAt: target.endDate ?? at(betStart + minutes * 60),
          marketCategory: 'crypto',
          onDeposit: onDeposit,
          ledgerWalletId: ledgerWalletId,
          source: slipSource);
    }

    // The round on show's tokens and the rounds ahead stay on the feed;
    // the scopes read their chances.
    final aheadTokens = [
      for (final e in ahead.values) ...[
        if (e?.upTokenId case final t? when t.isNotEmpty) t,
        if (e?.downTokenId case final t? when t.isNotEmpty) t,
      ],
    ];
    final liveTokens = [
      if (upTokenId != null && upTokenId.isNotEmpty) upTokenId,
      if (downTokenId != null && downTokenId.isNotEmpty) downTokenId,
      ...aheadTokens,
    ];
    Widget oddsScopes(Widget child) {
      var out = CryptoOddsScope(token: upTokenId, child: child);
      for (final e in ahead.values) {
        out = CryptoOddsScope(token: e?.upTokenId, child: out);
      }
      return out;
    }

    final diffText = diffToBeat == null
        ? null
        : '${diffToBeat >= 0 ? '▲' : '▼'} ${_formatDiff(diffToBeat.abs())}';

    if (compact) {
      return CryptoCardOnScreen(
          child: LiveTokenScope(
        tokens: liveTokens,
        child: oddsScopes(
          CompactCryptoCard(
            config: config,
            title: context.l10n
                .predictUpOrDownLength(config.asset, lengthLabel(minutes)),
            countdown: countdown,
            pastResults: pastResults,
            loading: isInitialLoading,
            priceText: priceStr,
            diffText: diffText,
            diffUp: (diffToBeat ?? 0) >= 0,
            targetText: context.l10n.predictTargetPrice(priceToBeatStr),
            history: predictState?.priceHistory,
            priceToBeat: priceToBeat,
            roundStart: event?.windowStartTime,
            upFrac: buttonsUpFrac,
            nextLabel: nextLine,
            window: roundName,
            buttonsEnabled: canBet,
            onUp: () => openSide('up'),
            onDown: () => openSide('down'),
          ),
        ),
      ));
    }

    // Counts this banner as on screen while its tickers run, so the
    // shared Chainlink feed also streams when it is shown outside the
    // Predictions tab.
    return CryptoCardOnScreen(
        child: LiveTokenScope(
      tokens: liveTokens,
      child: oddsScopes(
        CryptoRoundHeroCard(
          config: config,
          title: context.l10n
              .predictUpOrDownLength(config.asset, lengthLabel(minutes)),
          window: '${clock(at(liveStart))}–${clock(at(nextStart))}',
          loading: isInitialLoading,
          beatText: priceToBeatStr,
          currentText: priceStr,
          diffText: diffText,
          diffUp: (diffToBeat ?? 0) >= 0,
          countdown: predictState?.event == null ? null : countdown,
          feedName: feedName,
          history: predictState?.priceHistory,
          priceToBeat: priceToBeat,
          roundStart: at(liveStart),
          chartHeight: chartHeight,
          chartWindow:
              minutes > 5 ? Duration(minutes: minutes) : kBtcPredictChartWindow,
          strip: hasStrip
              ? CryptoRoundStrip(
                  rounds: rounds,
                  selectedStart: betStart,
                  onPick: pick,
                )
              : null,
          line: nextLine,
          upFrac: buttonsUpFrac,
          roundName: roundName,
          buttonsEnabled: canBet,
          onUp: () => openSide('up'),
          onDown: () => openSide('down'),
          // No quick amounts (founder, 12 November 2026: "the buttons on
          // the bottom, $5 win $x, do not have it").
          quick: const [],
          quickUp: true,
                        ),
                      ),
    ));
  }
}

/// The quick amounts under the round card's buttons, in dollars.
const List<double> kCryptoQuickAmounts = [5, 25, 100];

/// The round lengths as one row of equal pills ("5 Min", "15 Min", "1 Hour",
/// "4 Hours"), the page's own length picked: a tap switches the whole page
/// (Crypto › that length). Never cut: where the four do not fit (a narrow
/// phone, large text) they shrink together, as one row.
class _CryptoLengthTabs extends StatelessWidget {
  const _CryptoLengthTabs({required this.selected, required this.onSelect});

  /// The page's length in minutes.
  final int selected;

  /// The Crypto subcategory of the length tapped ('5m', '15m', '1h', '4h').
  final void Function(String sub) onSelect;

  static const List<(String, int)> _lengths = [
    ('5m', 5),
    ('15m', 15),
    ('1h', 60),
    ('4h', 240),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const size = KutePillSize.compact;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final chipHeight = 2 * size.vPad.h +
        2 * (isLight ? 1.0 : 0.5) +
        MediaQuery.textScalerOf(context).scale(size.font.sp);
    final height = math.max(size.height + 4.0, chipHeight + 4);
    final c = context.colors;
    final restingFill = context.isDark ? c.surface : c.surfaceLight;
    return SizedBox(
      key: const ValueKey('crypto-round-lengths'),
      height: height,
      child: LayoutBuilder(builder: (context, box) {
        final gap = 6.w;
        var each = 44.0;
        for (final (sub, _) in _lengths) {
          each = math.max(
              each,
              KutePill.naturalWidth(context,
                      item:
                          KutePillItem(label: polySubLabel(l10n, PolySub(sub))),
                      selected: true,
                      size: size) ??
                  each);
        }
        final need = each * _lengths.length + gap * (_lengths.length - 1);
        final row = Row(
                  children: [
            for (var i = 0; i < _lengths.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(
                child: KutePill(
                  key: ValueKey('crypto-round-length-${_lengths[i].$1}'),
                  label: polySubLabel(l10n, PolySub(_lengths[i].$1)),
                  selected: _lengths[i].$2 == selected,
                  fillWidth: true,
                  restingFill: restingFill,
                  size: size,
                  onTap: () {
                    if (_lengths[i].$2 == selected) return;
                    onSelect(_lengths[i].$1);
                  },
                          ),
                        ),
                      ],
                    ],
                );
        if (need <= box.maxWidth) return row;
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SizedBox(width: need, height: height, child: row),
        );
      }),
    );
  }
}

/// The other crypto markets in one card under the hero, the way the open
/// predictions strip reads: a titled surface with one row per asset.
class _MoreCryptoMarketsCard extends StatelessWidget {
  final VoidCallback? onDeposit;

  /// The page's round length: every row is that coin's round of it.
  final int minutes;
  const _MoreCryptoMarketsCard({required this.minutes, this.onDeposit});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final others = kCryptoPredictAssets.skip(1).toList(growable: false);
    if (others.isEmpty) return const SizedBox.shrink();
    // The hero's own card (CompactCryptoCard) and its 14 inset, so the
    // rows' logos stand under the hero's (founder, 12 November 2026:
    // consistent spacing).
    return Container(
      key: const ValueKey('crypto-more-rounds'),
      padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 4.h),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < others.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.borderSubtle),
            _FiveMinTile(
                config: others[i],
                minutes: minutes,
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

  /// The round length of the page the row is on.
  final int minutes;

  const _FiveMinTile({
    required this.config,
    required this.minutes,
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
    FiveMinMarketDetailSheet.show(context,
        event: event, onDeposit: onDeposit, minutes: minutes);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final predictAsync =
        ref.watch(cryptoRoundProvider((asset: config.asset, minutes: minutes)));
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
    // The chips are the round the coin's card would bet (founder, 12
    // November 2026; crypto_next_round.dart): the round in play until its
    // cutoff, at its live odds, then the next one, at its live book odds
    // once it has real prices, the chips dimmed with no figure until then.
    // The clock is the round in play's time left.
    final now = ref.read(cryptoOddsClockProvider)();
    final shownFrom = ev.windowStartTime;
    final shownTo = ev.endDate;
    final liveStart = shownFrom != null &&
            shownTo != null &&
            shownTo.difference(shownFrom).inMinutes == minutes
        ? shownFrom.millisecondsSinceEpoch ~/ 1000
        : polyRoundStartAt(now, minutes);
    final nextStart = liveStart + minutes * 60;
    final next = ref
        .watch(cryptoNextRoundProvider((
          asset: config.asset.toLowerCase(),
          minutes: minutes,
          start: nextStart,
        )))
        .valueOrNull;
    final nextUpToken = next?.upTokenId;
    final nextDownToken = next?.downTokenId;
    // Narrowed select: the row repaints only when ITS next Up chance moves.
    ref.watch(cryptoLiveOddsProvider
        .select((s) => nextUpToken == null ? null : s[nextUpToken]?.up));
    final books = ref.read(cryptoOddsBooksProvider);
    final nextUp = polyNextRoundUp(
      next: next,
      start: nextStart,
      upBook: nextUpToken == null ? null : books.snapshot(nextUpToken),
      downBook: nextDownToken == null ? null : books.snapshot(nextDownToken),
      now: now,
    );
    final rolled = polyRoundButtonsRolled(
        liveStart: liveStart, minutes: minutes, now: now);
    final liveUp = rolled
        ? null
        : ref.watch(cryptoLiveOddsProvider
            .select((s) => upToken == null ? null : s[upToken]?.up));
    final betUp = rolled
        ? nextUp
        : polyCurrentRoundUp(event: ev, start: liveStart, liveUp: liveUp);
    // Up and Down written off the one price, so they add up to 100.
    final odds = betUp == null ? null : formatPolyChancePair(betUp);
    final countdown = st == null
        ? '--:--'
        : cryptoRoundClockText(st.secondsRemaining, minutes);
    final spot = _formatSpot(st?.currentPrice);

    // Every coin the same circle (crypto_asset_logo.dart; founder, 12
    // November 2026: XRP's bare X stood oversized beside the discs).
    Widget logo(double size) => CryptoAssetLogo(config: config, size: size);

    final countdownStyle = TextStyle(
      color: c.textPrimary,
      fontSize: 12.sp,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Time left as a plain figure (no chip): the red live dot is the only
    // colour, the clock in the primary text colour.
    Widget countdownPill() => Padding(
          padding: EdgeInsets.symmetric(vertical: 4.h),
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
              Text(countdown, maxLines: 1, style: countdownStyle),
            ],
          ),
        );

    TextStyle oddsStyle(Color color) => TextStyle(
          color: color,
          fontSize: 13.sp,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    // Direction entry buttons: solid market colors, no pastel tint
    // (app-wide rule). Without the next round's prices: the arrow alone,
    // dimmed as a disabled pair button is (0.35).
    Widget oddsChip({required bool isUp, required String? text}) {
      final accent = isUp ? _kPolyGreen : _kPolyRed;
      final onColor = contrastingOnColor(accent);
      return Opacity(
        key: ValueKey('five-min-chip-${config.asset}-${isUp ? 'up' : 'down'}'),
        opacity: text == null ? 0.35 : 1,
        child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(10.r),
        ),
        padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 6.w),
        // Whole at any text size: the arrow and the figure shrink together
        // rather than run past the chip.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isUp
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 14.sp,
                color: onColor,
              ),
              if (text != null) ...[
                SizedBox(width: 3.w),
                RollingNumberText(text: text, style: oddsStyle(onColor)),
              ],
            ],
          ),
        ),
      ),
      );
    }

    final nameStyle = TextStyle(
      color: c.textPrimary,
      fontSize: 15.sp,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
    );
    final spotStyle = TextStyle(
      color: c.textTertiary,
      fontSize: 12.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // "Ethereum up or down · 5m", polymarket.com's own row; its live price
    // under it.
    final nameText = context.l10n.predictUpOrDownLength(
        config.displayName, CryptoPredictBanner.lengthLabel(minutes));
    final spotText = spot.isEmpty ? '—' : spot;
    // The name and the price under it. In the row (wide) neither is ever
    // cut: a line too long for its room wraps (founder, 12 November 2026).
    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          nameText,
          maxLines: wide ? null : 1,
          overflow: wide ? null : TextOverflow.ellipsis,
          style: nameStyle,
        ),
        SizedBox(height: 2.h),
        Text(
          spotText,
          maxLines: wide ? null : 1,
          overflow: wide ? null : TextOverflow.ellipsis,
          style: spotStyle,
        ),
      ],
    );

    final Widget body;
    if (wide) {
      // One row while everything fits whole on it: the coin (the hero's
      // 32 logo, under it), its name and price, the time left, Up and
      // Down. Where it does not (a narrow phone, large text) the row
      // wraps, never cuts: the coin, its name and the time left on the
      // first line, Up and Down across the second. Measured with every
      // digit as wide as the widest, so a tick never flips the shape.
      body = LayoutBuilder(builder: (context, box) {
        double widthOf(String text, TextStyle style) {
          final painter = TextPainter(
            text: TextSpan(
                text: text.replaceAll(RegExp(r'\d'), '0'),
                style: DefaultTextStyle.of(context).style.merge(style)),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final logoSize = 32.sp;
        final names = math.max(
            widthOf(nameText, nameStyle), widthOf(spotText, spotStyle));
        final clock = 10.w + widthOf(countdown, countdownStyle);
        // A chip holds its arrow and "100.0%" whole.
        final chip = math.max(
            74.w,
            14.sp +
                3.w +
                widthOf('100.0%', oddsStyle(c.textPrimary)) +
                12.w +
                2);
        final oneRow = logoSize +
                12.w +
                names +
                8.w +
                clock +
                10.w +
                chip * 2 +
                6.w +
                1 <=
            box.maxWidth;
        if (oneRow) {
          return Row(
            children: [
              logo(logoSize),
              SizedBox(width: 12.w),
              Expanded(child: nameBlock),
              SizedBox(width: 8.w),
              countdownPill(),
              SizedBox(width: 10.w),
              SizedBox(
                  width: chip, child: oddsChip(isUp: true, text: odds?.first)),
              SizedBox(width: 6.w),
              SizedBox(
                  width: chip,
                  child: oddsChip(isUp: false, text: odds?.second)),
            ],
          );
        }
        return Column(
          key: const ValueKey('five-min-row-wrapped'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                logo(logoSize),
                SizedBox(width: 12.w),
                Expanded(child: nameBlock),
                SizedBox(width: 8.w),
                countdownPill(),
              ],
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                Expanded(child: oddsChip(isUp: true, text: odds?.first)),
                SizedBox(width: 6.w),
                Expanded(child: oddsChip(isUp: false, text: odds?.second)),
              ],
            ),
          ],
        );
      });
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
              Expanded(child: oddsChip(isUp: true, text: odds?.first)),
              SizedBox(width: 6.w),
              Expanded(child: oddsChip(isUp: false, text: odds?.second)),
            ],
          ),
        ],
      );
    }

    final tokens = [
      if (upToken != null && upToken.isNotEmpty) upToken,
      if (downToken != null && downToken.isNotEmpty) downToken,
      if (nextUpToken case final t? when t.isNotEmpty) t,
      if (nextDownToken case final t? when t.isNotEmpty) t,
    ];
    if (bare) {
      return LiveTokenScope(
        tokens: tokens,
        child: CryptoOddsScope(
          token: nextUpToken,
          child: CryptoOddsScope(
            token: upToken,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openDetail(context, ev, minutes),
            child: Padding(
              key: ValueKey('five-min-row-${config.asset}'),
              padding: EdgeInsets.symmetric(vertical: 10.h),
              child: body,
              ),
            ),
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
      tokens: tokens,
      child: CryptoOddsScope(
        token: nextUpToken,
        child: CryptoOddsScope(
          token: upToken,
        child: RepaintBoundary(
          child: wide ? card : AspectRatio(aspectRatio: 1.15, child: card),
          ),
        ),
      ),
    );
  }
}

/// A league's heading over its games in play (Live). The only title left
/// in the lists: without it, games of different leagues would run
/// together.
class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({super.key, required this.label});

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
                      event.displayTitle,
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
