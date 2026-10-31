// lib/screens/home/components/kute_shell_bar.dart
//
// The bar over everything (founder, 31 October 2026; see
// kute_bar_context.dart): drawn once, above the root navigator (the
// MaterialApp builder's Stack, app_widget.dart), so it sits over pushed
// pages, modal barriers and sheets. It shows the topmost [KuteBarContext]
// on the stack while that context's route is current, else the default
// ("Search or ask Sal") over any page or sheet pushed over the tabs
// ([KuteBarRouteObserver.over]); with nothing over them (Home, Dollars
// draw their own pill in their dock) it is away. A hidden context or the
// keyboard slides it down ([KuteMotion.sheetOut]); it springs back when
// they go. Tapping it opens the Sal sheet with that context
// (showKuteSearch).
//
// NEVER OVER A SCREEN'S OWN ACTION ROW: a context's [actionRowHeight]
// lifts the bar above the page's pinned row, the lift animated on the
// sheet spring as the row appears or goes.
//
// MOVEMENT ON A MARKET PAGE (founder: "some kind of movement around the
// screen of this Share with your friends"):
//
//   * scrolling down, the pill folds into Sal alone, a 52 circle docked
//     at the bottom right ([KuteSalPill.collapsed]: the text slides out,
//     the width follows on the chip spring), so the content and the
//     buttons are clear; when the scroll has been still for
//     [kBarScrollIdle] or turns up, it springs back to the full centred
//     pill. The page's scroll reaches here through [kuteBarScroll];
//   * arriving on a market page the pill enters from the bottom on the
//     sheet spring and Sal plays the `share` clip once at 1.3x, then
//     loops ([KuteSalPill.salCue]);
//   * when the venue's live prices tick (the feed the page is already
//     watching), the pill gives a one-frame 2 px nudge that settles on
//     the press spring, so it feels attached to the market.
//
// Reduce Motion: the full pill, still, above the action row; it still
// slides in and out with the keyboard and the Sal sheet, at once.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/app_router.dart' show AppRouter;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart'
    show hyperliquidLivePricesProvider;
import 'package:kute/providers/polymarket_live_prices_provider.dart'
    show livePriceProvider;
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_motion.dart' show kuteReduceMotion;
import 'package:kute/theme/kute_motion.dart';

/// How long a market page's scroll stays still before the folded pill
/// opens again.
const Duration kBarScrollIdle = Duration(milliseconds: 600);

/// The nudge on a price tick, in logical pixels.
const double kBarTickNudge = 2;

class KuteShellBar extends ConsumerStatefulWidget {
  const KuteShellBar({super.key});

  @override
  ConsumerState<KuteShellBar> createState() => _KuteShellBarState();
}

class _KuteShellBarState extends ConsumerState<KuteShellBar>
    with TickerProviderStateMixin {
  /// The last context shown, kept while the bar slides away.
  KuteBarContext? _last;

  /// The lift above the action row, kept while the bar slides away.
  double _lift = 0;

  /// Whether the last build showed the bar, and since when.
  bool _shown = false;
  DateTime? _shownAt;

  /// Whether the last build showed a market page's context.
  bool _market = false;

  /// Folded to the circle (a market page scrolling down).
  bool _collapsed = false;
  Timer? _idle;

  /// Bumped when a market page's context arrives: Sal's `share` intro.
  int _salCue = 0;

  /// The entry from the bottom when a market context takes over a bar
  /// that was already up (0 → 1 on the sheet spring; 1 at rest).
  late final AnimationController _entry = AnimationController(
      vsync: this, duration: KuteMotion.sheetInDuration, value: 1);

  /// The tick's nudge (0 → 1 on the press spring; 1 at rest).
  late final AnimationController _nudge = AnimationController(
      vsync: this, duration: KuteMotion.pressDuration, value: 1);

  @override
  void initState() {
    super.initState();
    KuteBarRouteObserver.over.addListener(_onRoutes);
    kuteShellMounted.addListener(_onRoutes);
    kuteBarScroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    KuteBarRouteObserver.over.removeListener(_onRoutes);
    kuteShellMounted.removeListener(_onRoutes);
    kuteBarScroll.removeListener(_onScroll);
    _idle?.cancel();
    _entry.dispose();
    _nudge.dispose();
    super.dispose();
  }

  void _onRoutes() {
    if (mounted) setState(() {});
  }

  /// The page's scroll (see the file header): only a market page folds
  /// the pill, and never under Reduce Motion.
  void _onScroll() {
    if (!mounted || !_market || !_shown || kuteReduceMotion(context)) return;
    switch (kuteBarScroll.last) {
      case KuteBarScroll.down:
        _idle?.cancel();
        _idle = Timer(kBarScrollIdle, _expand);
        if (!_collapsed) setState(() => _collapsed = true);
      case KuteBarScroll.up:
        _expand();
      case KuteBarScroll.idle:
        if (_collapsed) _idle ??= Timer(kBarScrollIdle, _expand);
    }
  }

  void _expand() {
    _idle?.cancel();
    _idle = null;
    if (_collapsed && mounted) setState(() => _collapsed = false);
  }

  /// A price tick: one nudge at a time (a fast feed gets one per spring).
  void _tick() {
    if (!mounted || _nudge.isAnimating) return;
    _nudge.forward(from: 0);
  }

  void _open(KuteBarContext ctx) {
    final navContext = AppRouter.rootNavigatorKey.currentContext;
    if (navContext == null) return;
    HapticFeedback.lightImpact();
    // ignore: discarded_futures
    showKuteSearch(
      navContext,
      initialCategory: ctx.category,
      searchFirst: true,
      searchHint: ctx.searchHint,
      source: ctx.source,
      barContext: ctx,
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduce = kuteReduceMotion(context);
    final stackTop = kuteBarTop(ref.watch(kuteBarContextProvider));
    final over = KuteBarRouteObserver.over.value > 0;
    // The stack's top while its route is current; else the default: over
    // whatever is pushed, and on the tab roots themselves (the ONE pill of
    // the app; founder, 31 October 2026); nothing before the shell exists.
    final KuteBarContext? top = stackTop != null && stackTop.current
        ? stackTop
        : over || kuteShellMounted.value
            ? KuteBarContext(label: context.l10n.searchOrAskSalShort)
            : null;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final show = top != null && !top.hidden && !keyboard;
    // The lift follows what is shown: a bar sliding away, or one back on
    // a page without an action row, sits at the foot again (a kept lift
    // once left a popped market page's bar hanging over the tabs).
    _lift = show ? top.actionRowHeight : 0;
    if (show) _last = top;
    final ctx = _last;
    if (ctx == null) return const SizedBox.shrink();

    // A market page's context arriving: Sal's intro, and the entry from
    // the bottom when the bar was already up (a bar just rising already
    // comes from there).
    final market = show && top.market;
    if (market && !_market) {
      _salCue++;
      final settled = _shownAt != null &&
          DateTime.now().difference(_shownAt!) > KuteMotion.sheetInDuration;
      if (_shown && settled && !reduce) _entry.forward(from: 0);
    }
    if (!market && _collapsed) _expand();
    if (show && !_shown) _shownAt = DateTime.now();
    _shown = show;
    _market = market;

    // The venue's live feed, only while the page has it open: a tick
    // nudges the pill.
    if (market && !reduce) {
      switch (top.category) {
        case SearchCategory.predictions:
          if (ref.exists(livePriceProvider)) {
            ref.listen(livePriceProvider, (_, __) => _tick());
          }
        case SearchCategory.perpetuals:
          if (ref.exists(hyperliquidLivePricesProvider)) {
            ref.listen(hyperliquidLivePricesProvider, (_, __) => _tick());
          }
        default:
          break;
      }
    }

    final aiEnabled = ref.watch(aiEnabledProvider).valueOrNull ?? true;
    final collapsed = _collapsed && !reduce;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !show,
        child: AnimatedSlide(
          key: const ValueKey('kute-shell-bar-slide'),
          offset: show ? Offset.zero : const Offset(0, 1.4),
          duration: reduce
              ? Duration.zero
              : (show ? KuteMotion.sheetInDuration : KuteMotion.sheetOutDuration),
          curve: show ? KuteMotion.sheetIn : KuteMotion.sheetOut,
          // Above the page's action row, on the sheet spring.
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: _lift),
            duration: reduce ? Duration.zero : KuteMotion.sheetInDuration,
            curve: KuteMotion.sheetIn,
            builder: (context, lift, child) => Transform.translate(
              offset: Offset(0, -lift),
              child: child,
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1.4),
                end: Offset.zero,
              ).animate(
                  CurvedAnimation(parent: _entry, curve: KuteMotion.sheetIn)),
              child: AnimatedBuilder(
                animation: _nudge,
                builder: (context, child) => Transform.translate(
                  offset: Offset(
                      0,
                      -kBarTickNudge *
                          (1 - KuteMotion.press.transform(_nudge.value))),
                  child: child,
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 2.h),
                    // Centred; docked right while folded.
                    child: AnimatedAlign(
                      alignment: collapsed
                          ? Alignment.centerRight
                          : Alignment.center,
                      duration:
                          reduce ? Duration.zero : KuteMotion.sheetInDuration,
                      curve: KuteMotion.sheetIn,
                      child: KuteSalPill(
                        label: ctx.label,
                        sublabel: ctx.sublabel,
                        clip: ctx.clip,
                        aiEnabled: aiEnabled,
                        collapsed: collapsed,
                        salCue: _salCue,
                        onTap: () => _open(ctx),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
