// lib/screens/home/components/kute_shell_bar.dart
//
// The bar over everything (founder, 31 October 2026; see
// kute_bar_context.dart): drawn once, above the root navigator (the
// MaterialApp builder's Stack, app_widget.dart), so it sits over pushed
// pages, modal barriers and sheets. It shows the topmost [KuteBarContext]
// on the stack while that context's route is current, else the default
// ("Search or Manage with AI") over any page or sheet pushed over the tabs
// ([KuteBarRouteObserver.over]); with nothing over them (Home, Dollars
// draw their own pill in their dock) it is away. A hidden context or the
// keyboard slides it down ([KuteMotion.sheetOut]); it springs back when
// they go. Tapping it opens the Sal sheet with that context
// (showKuteSearch). AS THE PRIMARY BUTTON IT RIDES ABOVE THE KEYBOARD
// instead (founder, 31 October 2026): at the keyboard's top plus
// [kBarKeyboardGap], centred at its own width, lifted on the sheet spring and back
// down with the keys; a search or hidden context still slides under it.
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
//     loops ([KuteSalPill.salCue]). No nudge on a price tick (founder, 31
//     October 2026: jitter).
//
// THE TRADE ROW (founder, 4 November 2026: "I do not like the Send to a
// friend on the top right in Hyperliquid and Predictions. It must be a
// floating button"; kute_bar_trade_row.dart): on a market page the bar is
// the page's trade buttons, Invest | Short or Yes | No, as floating pills
// with the round Sal button at the row's end. An open position's Close
// or Sell primary carries the same round button at its right, and so does
// a slip's Place (THIS prediction to a friend, screens/share/slip_share
// .dart). The row never folds. A page with no trade pair (an event, a
// game) has the Sal pill, "Send to a friend", which folds into that same
// circle while the page scrolls (above). No page draws a header button
// any more.
//
// STRAIGHT INTO THE SEND (founder, 5 November 2026: "the other shares are
// just sharing the market, no picker"; "so we can take the user straight
// into that"): a context with its own action
// ([KuteBarContext.directAction], a market page's: the market send
// sheet) runs it on a tap of the pill or the round button; no Sal sheet
// in between. Only a context without one opens the Sal sheet.
//
// THE PILL BECOMES THE COMPOSER (founder, 31 October 2026;
// search_morph.dart): a tap hands [showKuteSearch] the pill's rect
// ([KuteSearchMorphSource]) and the pill travels to the sheet's composer
// on the sheet spring, back again on close. While it travels and while
// the sheet is up the bar keeps its place and draws the pill transparent
// ([_morphed]; no slide, no hidden context, the keyboard inside the sheet
// ignored), so the return lands exactly where the pill rests and the
// pill is simply there again when it does. Only while the sheet is ON
// TOP: a result's market page or its slip stacks over the sheet, and the
// bar is theirs meanwhile (their trade row, the slip's primary with its
// round share button), then holds the pill again when they close
// ([_searchCovered]; founder, 6 November 2026: "Predictions on search
// have no buy button on the bet slip").
//
// DARK IN LIGHT MODE, IN EVERY STATE (founder, 7 November 2026: "shoudn
// tthe button be black idk"; kute_bar_surface.dart): the pill, one line or
// two, the folded circle, the round share button, the primary button
// enabled, busy or disabled and a trade row's neutral pill all wear the
// primary's near-black fill with white words, a light hairline and a soft
// shadow, so a cross-fade between them never shows white; only a coloured
// button keeps its own colours. Dark mode keeps its white pill.
//
// Reduce Motion: the full pill, still, above the action row; it still
// slides in and out with the keyboard and the Sal sheet, at once, and the
// sheet opens plain: no travel.
//
// SAL REACTS (sal_reactions.dart): the pill's Sal plays the one-shot a
// hook asked for (money in, a fill, an error, a long load) and comes back
// to the context's clip; the bar only subscribes, and reports its own
// primary button's busy as a load.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/app_router.dart' show AppRouter;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/home/components/kute_bar_trade_row.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/search/components/search_morph.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_motion.dart'
    show KutePressable, kuteReduceMotion;
import 'package:kute/screens/shared/kute_morph_label.dart';
import 'package:kute/screens/shared/sal_reactions.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_bar_surface.dart';
import 'package:kute/theme/kute_motion.dart';
import 'package:kute/theme/kute_overlay_surface.dart';

/// How long a market page's scroll stays still before the folded pill
/// opens again.
const Duration kBarScrollIdle = Duration(milliseconds: 600);

/// The air between the keyboard's top and the primary button riding
/// above it (see the file header).
const double kBarKeyboardGap = 12;

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

  /// The pill is travelling to the Sal sheet's composer, or the sheet it
  /// became is up: the bar holds its place with the pill transparent (see
  /// the file header).
  bool _morphed = false;

  /// What the bar showed when it became the composer, its lift and
  /// whether it was a market's: held while the sheet is on top, and given
  /// back when a page or a slip opened over the sheet closes (meanwhile
  /// the bar is theirs; see [_searchCovered]), so the way back still
  /// lands on it.
  KuteBarContext? _heldLast;
  double _heldLift = 0;
  bool _heldMarket = false;

  /// The entry from the bottom when a market context takes over a bar
  /// that was already up (0 → 1 on the sheet spring; 1 at rest).
  late final AnimationController _entry = AnimationController(
      vsync: this, duration: KuteMotion.sheetInDuration, value: 1);

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
    // The load this bar reported ends with it.
    SalReactions.loading(_KuteShellBarState, false);
    super.dispose();
  }

  void _onRoutes() {
    if (mounted) setState(() {});
  }

  /// The page's scroll (see the file header): only a market page folds
  /// the pill (never its trade row), and never under Reduce Motion.
  void _onScroll() {
    if (!mounted || !_market || !_shown || kuteReduceMotion(context)) return;
    if (_last?.kind != KuteBarKind.search) return;
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

  /// Opens the Sal sheet with [ctx]. With [pillContext] (the pill's own
  /// element) and motion on, the pill travels to the sheet's composer and
  /// back (search_morph.dart); the bar draws it transparent meanwhile.
  Future<void> _open(KuteBarContext ctx, [BuildContext? pillContext]) =>
      openKuteBarSheet(ctx, source: pillContext, travelling: (on) {
        if (!mounted || _morphed == on) return;
        setState(() {
          _morphed = on;
          _heldLast = on ? _last : null;
          _heldLift = on ? _lift : 0;
          _heldMarket = on && _market;
        });
      });

  /// THE SEARCH SHEET ONLY HOLDS THE BAR WHILE IT IS ON TOP
  /// (kute_bar_context.dart): a result's market page or its slip stands
  /// on the sheet (they stack on the root navigator), and the bar is
  /// theirs, the trade row, the slip's primary and its round share
  /// button, whether the pill travelled to the composer or the sheet hid
  /// the bar. Founder, 6 November 2026: "Predictions on search have no
  /// buy button on the bet slip, and Hyperliquid the same".
  bool _searchCovered() => kuteSearchSheetCovered();

  /// The stack's top as the bar reads it: the search sheet's hidden
  /// context (the one with no route) gives way while the sheet is covered.
  KuteBarContext? _top(List<KuteBarContext> stack, {required bool covered}) =>
      kuteBarTop(covered
          ? [
              for (final c in stack)
                if (!(c.hidden && c.route == null)) c
            ]
          : stack);

  /// The round Sal button at the end of the bar's row (a trade row's, a
  /// position's beside Close or Sell, a slip's beside its Place, a
  /// receipt's beside its action): the brag card on an open position in
  /// profit, a slip's own send (THIS prediction), a receipt's card
  /// preview, else the page's own action (a market page sends the market,
  /// no Sal sheet in between); only a context with none opens the Sal
  /// sheet, the button travelling to the composer ([shareContext], its own
  /// element).
  void _shareTap(KuteBarShare share, BuildContext shareContext) {
    final direct = share.brag ??
        share.send ??
        share.open ??
        share.barContext?.directAction;
    if (direct != null) {
      HapticFeedback.lightImpact();
      direct();
      return;
    }
    final ctx = share.barContext;
    if (ctx != null) _open(ctx, shareContext);
  }

  /// The pill: the context's own action when it has one (a market or an
  /// event page sends the market at once; founder, 5 November 2026: "so
  /// we can take the user straight into that"), else the Sal sheet.
  void _pillTap(KuteBarContext ctx, BuildContext pillContext) {
    final direct = ctx.directAction;
    if (direct != null) {
      HapticFeedback.lightImpact();
      direct();
      return;
    }
    _open(ctx, pillContext);
  }

  /// A tap on the primary button acts on the LIVE top context, not the
  /// one drawn: a page that just enabled its action (the last digit typed)
  /// has written the stack, and the frame that redraws the bar may not
  /// have run yet. Nothing runs while the live action is off or busy.
  void _primaryTap() {
    final live = _top(ref.read(kuteBarContextProvider),
        covered: _searchCovered());
    if (live == null || !live.isPrimary || !live.current) return;
    if (!live.enabled || live.busy || live.onPrimary == null) return;
    HapticFeedback.lightImpact();
    live.onPrimary!();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = kuteReduceMotion(context);
    // A page or a slip over the search sheet: the bar is theirs (see
    // [_searchCovered]). The route observer's count and the stack both
    // move when one is pushed or popped, so the bar rebuilds then.
    final covered = _searchCovered();
    final stackTop =
        _top(ref.watch(kuteBarContextProvider), covered: covered);
    final over = KuteBarRouteObserver.over.value > 0;
    // The stack's top while its route is current; else the default: over
    // whatever is pushed, and on the tab roots themselves (the ONE pill of
    // the app; founder, 31 October 2026); nothing before the shell exists.
    final KuteBarContext? top = stackTop != null && stackTop.current
        ? stackTop
        : over || kuteShellMounted.value
            ? KuteBarContext(label: context.l10n.searchOrManageAi)
            : null;
    // While the pill has become the Sal sheet's composer the bar holds
    // its place as it was: the sheet's keyboard, the hidden contexts the
    // sheet pushes and its own context changes do not move it (the pill
    // is transparent; its return lands where it rests).
    // A context placed in the page's header (KuteBarPlacement.header)
    // keeps the pill away: the Investing position's market context, whose
    // control is the round Sal button beside Close position.
    // Only while the sheet is on top: covered, the bar is the covering
    // page's; back on top, it holds what it showed when it became the
    // composer, so the way back lands on it.
    final morphed = _morphed && !covered;
    if (morphed && _heldLast != null) {
      _last = _heldLast;
      _lift = _heldLift;
      _market = _heldMarket;
    }
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboard = !morphed && inset > 0;
    // The primary button rides ABOVE the keyboard (founder, 31 October
    // 2026): a surface typing into a field keeps its Continue in reach,
    // the bar at the keyboard's top plus 12 px, centred at its own width, on the sheet
    // spring. A search or hidden context still slides under it.
    final rides = keyboard && top != null && top.isPrimary && !top.hidden;
    final show = top != null &&
        (morphed || rides || (!top.hidden && !top.inHeader && !keyboard));
    // The lift follows what is shown: a bar sliding away, or one back on
    // a page without an action row, sits at the foot again (a kept lift
    // once left a popped market page's bar hanging over the tabs).
    if (!morphed) {
      _lift = show
          ? top.actionRowHeight + (rides ? inset + kBarKeyboardGap : 0)
          : 0;
    }
    if (show && !morphed) _last = top;
    final ctx = _last;
    if (ctx == null) return const SizedBox.shrink();

    // A market page's context arriving: Sal's intro, and the entry from
    // the bottom when the bar was already up (a bar just rising already
    // comes from there).
    final market = show && (morphed ? _market : top.market);
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

    final aiEnabled = ref.watch(aiEnabledProvider).valueOrNull ?? true;
    // Only the pill folds; a trade row or a button keeps its place.
    final collapsed = _collapsed && !reduce && ctx.kind == KuteBarKind.search;
    // A primary action busy for 2 s: Sal thinks (sal_reactions.dart; the
    // pill's Sal plays it).
    SalReactions.loading(_KuteShellBarState, show && ctx.isPrimary && ctx.busy);
    // The pill, or the primary button, cross-fading on the settle; the
    // folded circle keeps to the right.
    final Widget switcher = AnimatedSwitcher(
      duration: reduce ? Duration.zero : KuteMotion.settleDuration,
      switchInCurve: KuteMotion.settle,
      switchOutCurve: KuteMotion.settle,
      layoutBuilder: (current, previous) => Stack(
        alignment: collapsed ? Alignment.centerRight : Alignment.center,
        children: [
          ..._outgoingOnce(previous),
          if (current != null) current
        ],
      ),
      child: ctx.isTrade
          // A market page's trade pills and the round Sal button.
          ? KuteBarTradeRow(
              key: const ValueKey('kute-bar-trade-row'),
              barContext: ctx,
              salCue: _salCue,
              onShare: (shareContext) => _shareTap(ctx.share!, shareContext),
            )
          : ctx.isPrimary
          // The button, and a position's round Sal button at its right.
          ? Row(
              key: const ValueKey('kute-bar-primary'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: KuteBarPrimaryButton(
                    barContext: ctx,
                    // The page's own Sal rows (Send to anyone on the Send
                    // to step) stay one long press away.
                    onAsk: () => _open(kuteBarAskContext(
                        ref.read(kuteBarContextProvider), ctx)),
                    onPrimaryTap: _primaryTap,
                  ),
                ),
                KuteBarShareSlot(
                  share: ctx.share,
                  salCue: _salCue,
                  onTap: (shareContext) {
                    final share = ctx.share;
                    if (share != null) _shareTap(share, shareContext);
                  },
                ),
              ],
            )
          // The Builder's element is the pill's own box: its rect is
          // where the travel to the composer starts.
          : Builder(
              key: const ValueKey('kute-bar-pill'),
              builder: (pillContext) => KuteSalPill(
                label: ctx.label,
                sublabel: ctx.sublabel,
                clip: ctx.clip,
                aiEnabled: aiEnabled,
                collapsed: collapsed,
                salCue: _salCue,
                onTap: () => _pillTap(ctx, pillContext),
              ),
            ),
    );
    // Travelling, or the sheet it became is up: in place, transparent,
    // taking no taps; back at once when the travel has landed.
    final Widget bar = morphed
        ? IgnorePointer(
            key: const ValueKey('kute-bar-morphed'),
            child: Opacity(opacity: 0, child: switcher))
        : switcher;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      // Above the navigator, outside every page's Material: the theme's
      // text, never the error style (kute_overlay_surface.dart).
      child: KuteOverlaySurface(
        child: IgnorePointer(
          ignoring: !show,
          child: AnimatedSlide(
            key: const ValueKey('kute-shell-bar-slide'),
            offset: show ? Offset.zero : const Offset(0, 1.4),
            duration: reduce
                ? Duration.zero
                : (show
                    ? KuteMotion.sheetInDuration
                    : KuteMotion.sheetOutDuration),
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
                child: SafeArea(
                  top: false,
                  child: AnimatedPadding(
                    duration:
                        reduce ? Duration.zero : KuteMotion.sheetInDuration,
                    curve: KuteMotion.sheetIn,
                    // The pill's air; the primary button and the trade
                    // row take the screen's 16 px gutters.
                    padding: EdgeInsets.fromLTRB(
                        ctx.isPrimary || ctx.isTrade ? 16.w : 12.w,
                        0,
                        ctx.isPrimary || ctx.isTrade ? 16.w : 12.w,
                        2.h),
                    // Centred; docked right while folded. Pill to button
                    // and between the button's states the width springs
                    // on the chip spring (KuteMorphSize; the strip's own
                    // elastic movement): the button is only as wide as
                    // its words (KuteBarPrimaryButton). At once under
                    // Reduce Motion.
                    child: AnimatedAlign(
                      alignment:
                          collapsed ? Alignment.centerRight : Alignment.center,
                      duration:
                          reduce ? Duration.zero : KuteMotion.chipDuration,
                      curve: KuteMotion.chip,
                      child: KuteMorphSize(
                        alignment: collapsed
                            ? Alignment.centerRight
                            : Alignment.center,
                        child: bar,
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

/// The outgoing children of the bar's [AnimatedSwitcher], at most one per
/// key: the newest. The switcher keys each child by its kind (the pill,
/// the primary row, the trade row) and drops an outgoing one only when it
/// shares the INCOMING child's key, so a quick pill → button → pill →
/// button inside one cross-fade left two pills fading out under one key
/// (Flutter's "Duplicate keys found"): a slip whose Place opens the PIN
/// sheet within the cross-fade of the bar becoming Place, the pill
/// showing for the one frame before the sheet's Cancel lands on the
/// stack, then Cancel. The older of two is near the end of its fade and
/// simply goes.
List<Widget> _outgoingOnce(List<Widget> previous) {
  final seen = <Key>{};
  final kept = <Widget>[];
  for (final w in previous.reversed) {
    final key = w.key;
    if (key != null && !seen.add(key)) continue;
    kept.add(w);
  }
  return kept.reversed.toList();
}

/// Opens the Sal sheet with [ctx] over the root navigator. With [source]
/// (the element of the control that was tapped: the pill, the round Sal
/// button) and motion on, the control travels to the sheet's composer and
/// back (search_morph.dart); [travelling] is told when the control should
/// draw itself transparent (true) and when it is itself again (false).
Future<void> openKuteBarSheet(
  KuteBarContext ctx, {
  BuildContext? source,
  ValueChanged<bool>? travelling,
}) async {
  final navContext = AppRouter.rootNavigatorKey.currentContext;
  if (navContext == null) return;
  HapticFeedback.lightImpact();
  KuteSearchMorphSource? morph;
  final overlay = AppRouter.rootNavigatorKey.currentState?.overlay;
  if (source != null &&
      source.mounted &&
      overlay != null &&
      !kuteReduceMotion(source)) {
    final rect = KuteSearchMorph.rectOf(source.findRenderObject(), overlay);
    if (rect != null) {
      morph = KuteSearchMorphSource(
        rect: rect,
        label: ctx.label,
        // Where the control rests when the sheet closes (the pill may
        // have folded or moved meanwhile).
        rectNow: () => source.mounted
            ? KuteSearchMorph.rectOf(source.findRenderObject(), overlay)
            : null,
      );
    }
  }
  if (morph != null) travelling?.call(true);
  try {
    await showKuteSearch(
      navContext,
      initialCategory: ctx.category,
      searchFirst: true,
      searchHint: ctx.searchHint,
      source: ctx.source,
      barContext: ctx,
      initialQuestion: ctx.question,
      morph: morph,
    );
  } finally {
    if (morph != null) travelling?.call(false);
  }
}

/// THE BAR AS THE PRIMARY BUTTON, AN ADAPTIVE PILL (founder, 1 November
/// 2026; see KuteBarContext.primary). The button is only as wide as what
/// it says, like the search pill: Sal's 28 px face, the label and the
/// padding, at least [minWidth] and at most the screen less its 16 px
/// gutters, centred, [height] tall, fully rounded. It morphs from the
/// search pill and between its states with the Dollars strip's motion
/// (kute_pill_tabs.dart): the width springs on [KuteMotion.chip] (the
/// button's own words' room, which the shell bar's [KuteMorphSize]
/// tracks; never narrower than a word on it: THE WORDS NEVER CLIP, on
/// the state class), the old words slide up and out and the
/// new ones rise in from below ([KuteMorphLabel]), Sal's clip crossfades
/// ([KuteMorphFace]), the fill and ink change on the settle. The Sal pill
/// changes its words with the same pieces (kute_morph_label.dart). At once
/// under Reduce Motion.
///
/// THREE STATES, ON THE ONE DARK FILL IN LIGHT MODE (founder, 7 November
/// 2026; kute_bar_surface.dart: the fill, its light hairline and its soft
/// shadow in every state):
///   * DISABLED says the step to take ([KuteBarContext.disabledLabel]:
///     "Enter an amount", "Add who to send to"): in light mode on the dark
///     fill in the quieter disabled ink (white at 60%, still AA), Sal
///     `curious`; in dark mode the light pill look (surface, a hairline,
///     the textSecondary label). A tinted slip's own white button keeps
///     the light pill while off (never black on a tinted slip). Never the
///     greyed action. Taps do nothing.
///   * ENABLED is the action in the black look: textPrimary fill, white
///     words at w600 (dark mode: the white fill, the background's ink),
///     Sal `idle`. A tinted slip keeps its own [KuteBarPrimaryStyle]
///     (fill, ink, radius, weight), and so does every coloured action
///     (Close position's red, a claim's green).
///   * BUSY says the busy label ("Sending…"; longer words once the
///     room has grown to them, never cut), Sal plays
///     `think` (`search` at 1.4x until that clip is there), and a thin
///     shimmer sweeps left to right across the fill ([shimmerBand] of the
///     width, [shimmerPeriod] a loop, the ink at 12%). Taps are ignored.
///     Reduce Motion: no shimmer.
///
/// A tap runs [KuteBarContext.onPrimary] (through [onPrimaryTap], the
/// shell bar's check of the live context); a long press opens the Sal
/// sheet ([onAsk]).
class KuteBarPrimaryButton extends StatefulWidget {
  const KuteBarPrimaryButton(
      {super.key,
      required this.barContext,
      required this.onAsk,
      this.onPrimaryTap});

  final KuteBarContext barContext;
  final VoidCallback onAsk;

  /// Runs the tap against the live context (the shell bar's); null runs
  /// [barContext]'s own handler.
  final VoidCallback? onPrimaryTap;

  /// The button's height, its narrowest width, and the pill radius that
  /// follows from the height.
  static const double height = 52;
  static const double minWidth = 160;
  static final BorderRadius radius = BorderRadius.circular(height / 2);

  /// Sal's face and the padding before it and after the label.
  static const double salSize = 28;
  static const double paddingStart = 12;
  static const double paddingEnd = 20;

  /// The busy shimmer: a band this share of the width, once across per
  /// period.
  static const double shimmerBand = 0.3;
  static const Duration shimmerPeriod = Duration(milliseconds: 1200);

  /// The words' style on the button (the theme's face).
  static TextStyle labelStyle(BuildContext context,
          {FontWeight weight = FontWeight.w600}) =>
      KuteOverlaySurface.textStyle(context).copyWith(
        fontSize: 16.sp,
        fontWeight: weight,
        letterSpacing: -0.2,
        height: 1.2,
      );

  /// The button's width saying [label] at the current text scale (Sal,
  /// the words, the padding; at least [minWidth]). A page that pairs the
  /// bar with a pill of its own measures both with this.
  static double widthFor(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle(context)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    // The hairline's inset on both sides (a Container pads by its
    // decoration's border), at its widest.
    final width =
        paddingStart + salSize + 8.w + painter.width + paddingEnd + 2;
    painter.dispose();
    return math.max(minWidth, width.ceilToDouble() + 1);
  }

  /// The room a page leaves under its own last control so that control
  /// sits [gap] above the bar: the bar's height, its 2 px lift and, where
  /// the page runs to the screen's foot ([pageToFoot]: iOS screens that
  /// leave the home-indicator inset to the bar), that inset too.
  static double roomUnder(BuildContext context,
          {double gap = 12, bool pageToFoot = false}) =>
      height +
      2.h +
      gap +
      (pageToFoot ? MediaQuery.paddingOf(context).bottom : 0);

  @override
  State<KuteBarPrimaryButton> createState() => _KuteBarPrimaryButtonState();
}

/// A SECOND OPTION PAIRED WITH THE BAR (founder, 1 November 2026: the
/// Recover screen's account option over "Use your recovery phrase"): the
/// bar's own shape and height in the light pill look (white, surface in
/// dark; a hairline; textPrimary words at w600), its [leading] glyph or,
/// while [busy], a small spinner in its place; [width] wide (the page
/// gives it and the bar the wider of their two widths:
/// [KuteBarPrimaryButton.widthFor], [widthFor]), centred by the page. The
/// press spring; no tap while [busy] or without [onTap].
class KuteBarSecondaryPill extends StatelessWidget {
  const KuteBarSecondaryPill({
    super.key,
    required this.label,
    required this.leading,
    required this.onTap,
    this.busy = false,
    this.width,
  });

  final String label;
  final IconData leading;
  final VoidCallback? onTap;
  final bool busy;
  final double? width;

  static const double _glyph = 22;

  /// The pill's width saying [label] (its glyph, the words, the padding;
  /// at least [KuteBarPrimaryButton.minWidth]).
  static double widthFor(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
          text: label, style: KuteBarPrimaryButton.labelStyle(context)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = KuteBarPrimaryButton.paddingStart +
        KuteBarPrimaryButton.salSize +
        8.w +
        painter.width +
        KuteBarPrimaryButton.paddingEnd +
        // The hairline's inset on both sides, at its widest.
        2;
    painter.dispose();
    return math.max(KuteBarPrimaryButton.minWidth, width.ceilToDouble() + 1);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final enabled = onTap != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: KutePressable(
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onTap!();
                }
              : null,
          child: Container(
            key: const ValueKey('kute-bar-secondary-pill'),
            width: width,
            height: KuteBarPrimaryButton.height,
            padding: const EdgeInsetsDirectional.only(
              start: KuteBarPrimaryButton.paddingStart,
              end: KuteBarPrimaryButton.paddingEnd,
            ),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : c.surface,
              borderRadius: KuteBarPrimaryButton.radius,
              border: Border.all(
                  color: isLight ? c.border : c.borderSubtle,
                  width: isLight ? 1.0 : 0.5),
            ),
            child: Row(
              mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: KuteBarPrimaryButton.salSize,
                  height: KuteBarPrimaryButton.salSize,
                  child: Center(
                    child: busy
                        ? SizedBox(
                            key: const ValueKey('kute-bar-secondary-spinner'),
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: c.textPrimary),
                          )
                        : Icon(leading, size: _glyph, color: c.textPrimary),
                  ),
                ),
                SizedBox(width: 8.w),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KuteBarPrimaryButton.labelStyle(context)
                        .copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Words leaving the button, and the room they lay out in: the button
/// holds it until they are gone (see [_KuteBarPrimaryButtonState]).
class _LeavingWords {
  _LeavingWords(this.width);
  final double width;
  Timer? timer;
}

/// THE WORDS NEVER CLIP (founder, 6 November 2026: "text is clipping in
/// Investing when thinking on the button, bet slip sometimes"). The busy
/// words differ from the idle ones (the order slip's funded steps,
/// "Preparing your order", "Opening $12.00 Long BTC"; the bet slip's
/// "Placing order…"), and the width followed the words through the shell
/// bar's AnimatedSize, which clips while it catches up: the new words,
/// laid out whole at once, were cut at both ends while the box grew, and
/// longer words leaving a shorter label overflowed the pill's end. The
/// button now springs its own words' room ([_from] → [_to] on
/// [KuteMotion.chip], which the AnimatedSize then tracks frame for frame)
/// and orders the change so every word on the button has room:
///
///   * LONGER WORDS WAIT FOR THE ROOM: the room grows first and the words
///     swap in once it has reached them (the spring's first crossing,
///     about 120 ms); Sal's think and the shimmer start at once. A growth
///     under [_snapGrowth] swaps at once: the room steps up by it, inside
///     the pill's end padding.
///   * SHORTER WORDS SWAP AT ONCE and the room holds the leaving ones'
///     width until they are gone ([kMorphWordsOut]), then springs down.
///   * The room is never narrower than any word on screen
///     ([_roomNow]), whatever the spring does (its overshoot only adds
///     air), and never wider than the bar allows beside the round share
///     button: only words longer than that are cut short, with an
///     ellipsis, the last resort, and they leave cut short too.
///
/// Reduce Motion: the words and the width at once.
class _KuteBarPrimaryButtonState extends State<KuteBarPrimaryButton>
    with TickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
      vsync: this, duration: KuteBarPrimaryButton.shimmerPeriod);

  /// The words' room on the chip spring, from [_from] to [_to].
  late final AnimationController _room =
      AnimationController(vsync: this, duration: KuteMotion.chipDuration)
        ..value = 1
        ..addListener(_onRoom)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _onRoom();
        });
  double _from = 0;
  double _to = 0;

  /// A growth this small swaps at once (see the class header): the room
  /// steps up by it, half on each side, inside the 20 px end padding.
  static const double _snapGrowth = 12;

  /// The words on the button now, and the style they were measured in.
  String? _shown;
  TextStyle? _shownStyle;

  /// Longer words waiting for the room (see the class header).
  String? _pending;
  TextStyle? _pendingStyle;

  final List<_LeavingWords> _leaving = [];

  /// The words' widest room: the bar's width less Sal, the gap and the
  /// padding (beside the round share button when there is one), as the
  /// last layout gave it.
  double _roomMax = double.infinity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _widths.clear();
    _syncShimmer();
    _syncWords();
  }

  @override
  void didUpdateWidget(covariant KuteBarPrimaryButton old) {
    super.didUpdateWidget(old);
    _syncShimmer();
    _syncWords();
  }

  /// The shimmer runs while busy, never under Reduce Motion.
  void _syncShimmer() {
    final on = widget.barContext.busy && !kuteReduceMotion(context);
    if (on && !_shimmer.isAnimating) {
      // ignore: discarded_futures
      _shimmer.repeat();
    } else if (!on && _shimmer.isAnimating) {
      _shimmer.stop();
      _shimmer.value = 0;
    }
  }

  /// The words' style on the button (the ink is the build's).
  TextStyle _style(KuteBarContext ctx) {
    final live = ctx.actionable || ctx.busy;
    return KuteOverlaySurface.textStyle(context).copyWith(
      fontSize: 16.sp,
      fontWeight: live
          ? (ctx.style?.fontWeight ?? FontWeight.w600)
          : FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.2,
    );
  }

  /// The words' own widths, by words, weight and size, measured once
  /// (cleared when the text scale or the theme changes).
  final Map<(String, FontWeight?, double?), double> _widths = {};

  /// The room [words] take in [style], at most [_roomMax].
  double _need(String words, TextStyle style) {
    final width =
        _widths.putIfAbsent((words, style.fontWeight, style.fontSize), () {
      final painter = TextPainter(
        text: TextSpan(text: words, style: style),
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = painter.width.ceilToDouble() + 1;
      painter.dispose();
      return width;
    });
    return math.min(width, _roomMax);
  }

  /// Where the spring has the room now.
  double get _spring => _room.isCompleted
      ? _to
      : _from + (_to - _from) * KuteMotion.chip.transform(_room.value);

  /// The room now: the spring's, never narrower than a word on screen.
  double _roomNow() {
    var room = _spring;
    final shown = _shown;
    if (shown != null) room = math.max(room, _need(shown, _shownStyle!));
    for (final l in _leaving) {
      room = math.max(room, l.width);
    }
    return math.min(room, _roomMax);
  }

  /// Springs the room to [to] from where it stands now.
  void _springTo(double to) {
    if (kuteReduceMotion(context)) {
      _from = _to = to;
      _room.value = 1;
      return;
    }
    if (to == _to && (_room.isAnimating || _roomNow() == to)) return;
    _from = _roomNow();
    _to = to;
    // ignore: discarded_futures
    _room.forward(from: 0);
  }

  /// The words the context says now, swapped in as the class header has
  /// it.
  void _syncWords() {
    final ctx = widget.barContext;
    final words = ctx.primaryLabel;
    final style = _style(ctx);
    final shown = _shown;
    if (shown == null || kuteReduceMotion(context)) {
      // The first words, or Reduce Motion: at once.
      _clearLeaving();
      _pending = null;
      _shown = words;
      _shownStyle = style;
      _from = _to = _need(words, style);
      _room.value = 1;
      return;
    }
    if (words == shown) {
      // The same words (busy under the same label, a new ink or weight):
      // they stay put; the room follows a weight's few pixels.
      _pending = null;
      _shownStyle = style;
      if (_leaving.isEmpty) _springTo(_need(words, style));
      return;
    }
    final need = _need(words, style);
    if (need <= _roomNow() + _snapGrowth) {
      _swap(words, style);
    } else {
      // Longer words wait for the room.
      _pending = words;
      _pendingStyle = style;
      _springTo(need);
    }
  }

  /// The spring moved: the waiting words swap in once the room has
  /// reached them.
  void _onRoom() {
    final pending = _pending;
    if (pending == null || !mounted) return;
    if (_spring + 0.5 < _need(pending, _pendingStyle!) &&
        !_room.isCompleted) {
      return;
    }
    setState(() => _swap(pending, _pendingStyle!));
  }

  /// [words] on the button now; the old ones leave and keep their room
  /// until they are gone.
  void _swap(String words, TextStyle style) {
    final old = _shown;
    if (old != null) {
      final leaving = _LeavingWords(_need(old, _shownStyle!));
      leaving.timer = Timer(kMorphWordsOut, () {
        if (!mounted) return;
        setState(() {
          _leaving.remove(leaving);
          if (_leaving.isEmpty && _pending == null) {
            _springTo(_need(_shown!, _shownStyle!));
          }
        });
      });
      _leaving.add(leaving);
    }
    _shown = words;
    _shownStyle = style;
    _pending = null;
    _pendingStyle = null;
  }

  void _clearLeaving() {
    for (final l in _leaving) {
      l.timer?.cancel();
    }
    _leaving.clear();
  }

  @override
  void dispose() {
    _clearLeaving();
    _room.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ctx = widget.barContext;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final busy = ctx.busy;
    final enabled = ctx.actionable;
    // Live: the action, or the action running. Else the step to take.
    final live = enabled || busy;
    final style = ctx.style;
    // DARK IN LIGHT MODE IN EVERY STATE (founder, 7 November 2026;
    // kute_bar_surface.dart): the action, busy or not, and the step to take
    // all wear the one dark fill and its light hairline; only a style's own
    // colours differ. A tinted slip's own white button stays in the light
    // family while off (never black on a tinted slip; founder, 31 October
    // 2026), as dark mode does.
    final lightStyle = style != null && style.fill.computeLuminance() > 0.5;
    final darkSurface = KuteBarSurface.dark(context) &&
        (live ? style == null : !lightStyle);
    final Color fill;
    final Color ink;
    final Color border;
    if (darkSurface) {
      fill = KuteBarSurface.fill(context);
      ink = live ? KuteBarSurface.ink : KuteBarSurface.disabledInk;
      border = KuteBarSurface.edge;
    } else if (!live) {
      // The light pill (the search pill's own surface in dark mode), never
      // filled grey.
      fill = isLight ? Colors.white : c.surface;
      ink = c.textSecondary;
      border = isLight ? c.border : c.borderSubtle;
    } else if (style != null) {
      fill = style.fill;
      ink = style.foreground;
      border = Colors.transparent;
    } else {
      // Dark mode's action: the white fill, the background's ink.
      fill = c.textPrimary;
      ink = c.background;
      border = Colors.transparent;
    }
    // What the button is (read out at once), and the words it shows (they
    // may wait for the room; see the class header).
    final label = ctx.primaryLabel;
    final words = _shown ?? label;
    final reduce = kuteReduceMotion(context);
    final duration = reduce ? Duration.zero : KuteMotion.chipDuration;
    final radius = live
        ? (style?.radius ?? KuteBarPrimaryButton.radius)
        : KuteBarPrimaryButton.radius;
    final textStyle = _style(ctx).copyWith(color: ink);
    // Keyed by the words alone: the same words in another state (busy
    // under the same label) stay put, only their ink changes.
    final ValueKey<String> labelKey = ValueKey('primary-label|$words');

    // Sal: curious while the step is the person's, idle on the action,
    // thinking while it runs (search at 1.4x until `think` is there).
    final fallbackIcon = Icon(Icons.bolt_rounded, size: 22, color: ink);
    final Widget sal = busy
        ? SalReactionSprite(
            key: const ValueKey('primary-sal-think'),
            clip: 'think',
            size: KuteBarPrimaryButton.salSize,
            fallback: SalSprite(
              clip: 'search',
              size: KuteBarPrimaryButton.salSize,
              speed: 1.4,
              fallback: fallbackIcon,
            ),
          )
        : SalReactionSprite(
            key: ValueKey('primary-sal-${enabled ? ctx.clip : 'curious'}'),
            clip: enabled ? ctx.clip : 'curious',
            size: KuteBarPrimaryButton.salSize,
            fallback: fallbackIcon,
          );

    // Sal, the gap, the padding and the hairline's inset on both sides (a
    // Container pads by its decoration's border, at its widest).
    final fixed = KuteBarPrimaryButton.paddingStart +
        KuteBarPrimaryButton.salSize +
        8.w +
        KuteBarPrimaryButton.paddingEnd +
        2;

    final screen = MediaQuery.sizeOf(context).width;
    // Its own width, at least [KuteBarPrimaryButton.minWidth] and at most
    // the bar's (the screen's, less the round share button beside it: the
    // layout's, read by [_MaxWidthProbe]); exactly the pair's width beside
    // a page's own pill.
    final Widget button = _MaxWidthProbe(
      onMaxWidth: (max) => _roomMax =
          math.max(0, (ctx.pairedWidth ?? math.min(max, screen)) - fixed),
      child: AnimatedBuilder(
        animation: _room,
        builder: (context, _) {
          final room = _roomNow();
          final width = ctx.pairedWidth ??
              math.min(screen,
                  math.max(KuteBarPrimaryButton.minWidth, fixed + room));
          // The words: the old slide up and out, the new rise from below
          // (the pill's and the strip's cross-slide, kute_morph_label
          // .dart), in the room the button holds for them (the layout's
          // own width caps both, the leaving words laid out inside it).
          final Widget wordsBox = SizedBox(
            width: room,
            child: KuteMorphLabel(
              leavingInside: true,
              child: Text(
                words,
                key: labelKey,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
          );
          final Widget content = Padding(
            padding: const EdgeInsetsDirectional.only(
              start: KuteBarPrimaryButton.paddingStart,
              end: KuteBarPrimaryButton.paddingEnd,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                KuteMorphFace(child: sal),
                SizedBox(width: 8.w),
                Flexible(child: wordsBox),
              ],
            ),
          );
          return SizedBox(
            width: width,
            height: KuteBarPrimaryButton.height,
            child: AnimatedContainer(
              key: const ValueKey('kute-bar-primary-button'),
              duration: duration,
              // The fill, the ink's ground and the hairline change on the
              // settle: a decoration lerp never rides the spring
              // (kute_motion.dart). The width is the room's (above).
              curve: reduce ? Curves.linear : KuteMotion.settle,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: radius,
                border: Border.all(color: border, width: isLight ? 1.0 : 0.5),
                // The dark surface's lift; the same shadow, transparent,
                // on every other look (kute_bar_surface.dart).
                boxShadow: [KuteBarSurface.shadow(visible: darkSurface)],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    content,
                    if (busy && !reduce)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: _Shimmer(
                            animation: _shimmer,
                            color: ink.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    return KuteOverlaySurface(
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        excludeSemantics: true,
        child: KutePressable(
          enabled: enabled,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Always wired: the live context decides (see the shell bar's
            // _primaryTap); a drawn-disabled button whose action just came
            // on takes the tap. Disabled or busy, nothing runs.
            onTap: widget.onPrimaryTap ??
                (enabled
                    ? () {
                        HapticFeedback.lightImpact();
                        ctx.onPrimary!();
                      }
                    : null),
            onLongPress: widget.onAsk,
            child: button,
          ),
        ),
      ),
    );
  }
}

/// Reports the width its parent allows ([onMaxWidth], during layout,
/// nothing rebuilt) and is its child: the primary button's widest room
/// without building its content during layout.
class _MaxWidthProbe extends SingleChildRenderObjectWidget {
  const _MaxWidthProbe({required this.onMaxWidth, required super.child});

  final ValueChanged<double> onMaxWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMaxWidthProbe(onMaxWidth);

  @override
  void updateRenderObject(
          BuildContext context, _RenderMaxWidthProbe renderObject) =>
      renderObject.onMaxWidth = onMaxWidth;
}

class _RenderMaxWidthProbe extends RenderProxyBox {
  _RenderMaxWidthProbe(this.onMaxWidth);

  ValueChanged<double> onMaxWidth;

  @override
  void performLayout() {
    onMaxWidth(constraints.maxWidth);
    super.performLayout();
  }
}

/// The busy shimmer: a band [KuteBarPrimaryButton.shimmerBand] of the
/// width, [color] at its middle and clear at its edges, crossing the fill
/// from just off its left edge to just off its right once per period.
class _Shimmer extends StatelessWidget {
  const _Shimmer({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          final band = width * KuteBarPrimaryButton.shimmerBand;
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) => Transform.translate(
              offset: Offset(-band + (width + band) * animation.value, 0),
              child: child,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                key: const ValueKey('kute-bar-primary-shimmer'),
                width: band,
                height: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0),
                        color,
                        color.withValues(alpha: 0)
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}
