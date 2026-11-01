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
// (showKuteSearch). AS THE PRIMARY BUTTON IT RIDES ABOVE THE KEYBOARD
// instead (founder, 31 October 2026): at the keyboard's top plus
// [kBarKeyboardGap], full width, lifted on the sheet spring and back
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
// IN THE HEADER INSTEAD (founder, 31 October 2026; KuteBarPlacement): on
// the Hyperliquid and Polymarket market pages, the position pages and the
// multi-outcome event page the floating pill is away, and the page draws
// [KuteSalHeaderButton] beside its headline figure: a real button in the
// primary look, Sal's `share` face and the words "Send to a friend"
// (founder: it "should say share or send", then "should be more
// evident", then, 1 November 2026, "don't say share, say send to a
// friend"), opening
// the same Sal sheet (the context variant). It travels to the composer
// the way the pill does.
//
// THE PILL BECOMES THE COMPOSER (founder, 31 October 2026;
// search_morph.dart): a tap hands [showKuteSearch] the pill's rect
// ([KuteSearchMorphSource]) and the pill travels to the sheet's composer
// on the sheet spring, back again on close. While it travels and while
// the sheet is up the bar keeps its place and draws the pill transparent
// ([_morphed]; no slide, no hidden context, the keyboard inside the sheet
// ignored), so the return lands exactly where the pill rests and the
// pill is simply there again when it does.
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/app_router.dart' show AppRouter;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/search/components/search_morph.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_motion.dart'
    show KutePressable, kuteReduceMotion;
import 'package:kute/screens/shared/kute_dog_scenes.dart' show KuteDogGlance;
import 'package:kute/screens/shared/sal_reactions.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

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

  /// Opens the Sal sheet with [ctx]. With [pillContext] (the pill's own
  /// element) and motion on, the pill travels to the sheet's composer and
  /// back (search_morph.dart); the bar draws it transparent meanwhile.
  Future<void> _open(KuteBarContext ctx, [BuildContext? pillContext]) =>
      openKuteBarSheet(ctx, source: pillContext, travelling: (on) {
        if (mounted && _morphed != on) setState(() => _morphed = on);
      });

  /// A tap on the primary button acts on the LIVE top context, not the
  /// one drawn: a page that just enabled its action (the last digit typed)
  /// has written the stack, and the frame that redraws the bar may not
  /// have run yet. Nothing runs while the live action is off or busy.
  void _primaryTap() {
    final live = kuteBarTop(ref.read(kuteBarContextProvider));
    if (live == null || !live.isPrimary || !live.current) return;
    if (!live.enabled || live.busy || live.onPrimary == null) return;
    HapticFeedback.lightImpact();
    live.onPrimary!();
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
    // While the pill has become the Sal sheet's composer the bar holds
    // its place as it was: the sheet's keyboard, the hidden contexts the
    // sheet pushes and its own context changes do not move it (the pill
    // is transparent; its return lands where it rests).
    // A context placed in the page's header (KuteBarPlacement.header)
    // keeps the pill away: the page draws KuteSalHeaderButton instead.
    final morphed = _morphed;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboard = !morphed && inset > 0;
    // The primary button rides ABOVE the keyboard (founder, 31 October
    // 2026): a surface typing into a field keeps its Continue in reach,
    // the bar at the keyboard's top plus 12 px, full width, on the sheet
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
    final collapsed = _collapsed && !reduce;
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
        children: [...previous, if (current != null) current],
      ),
      child: ctx.isPrimary
          ? KuteBarPrimaryButton(
              key: const ValueKey('kute-bar-primary'),
              barContext: ctx,
              // The page's own Sal rows (Send to anyone on the Send to
              // step) stay one long press away.
              onAsk: () => _open(kuteBarAskContext(
                  ref.read(kuteBarContextProvider), ctx)),
              onPrimaryTap: _primaryTap,
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
                onTap: () => _open(ctx, pillContext),
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
                  // The pill's air; the primary button takes the
                  // screen's 16 px gutters.
                  padding: EdgeInsets.fromLTRB(ctx.isPrimary ? 16.w : 12.w, 0,
                      ctx.isPrimary ? 16.w : 12.w, 2.h),
                  // Centred; docked right while folded. As a primary
                  // button it grows to the full width on the chip spring
                  // (AnimatedSize; the pill's own elastic movement) and
                  // springs back to the pill.
                  child: AnimatedAlign(
                    alignment:
                        collapsed ? Alignment.centerRight : Alignment.center,
                    duration:
                        reduce ? Duration.zero : KuteMotion.chipDuration,
                    curve: KuteMotion.chip,
                    // The size tween of the morph; a zero-length
                    // AnimatedSize re-dirties itself in layout (a Flutter
                    // assertion), so Reduce Motion switches at once.
                    child: reduce
                        ? bar
                        : AnimatedSize(
                            duration: KuteMotion.chipDuration,
                            curve: KuteMotion.chip,
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
    );
  }
}

/// Opens the Sal sheet with [ctx] over the root navigator. With [source]
/// (the element of the control that was tapped: the pill, the header
/// circle) and motion on, the control travels to the sheet's composer and
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

/// THE SHARE BUTTON BESIDE A PAGE'S BIG NUMBER (founder, 31 October 2026;
/// see the file header): a real button in the app's primary look (the
/// textPrimary fill, the mode's contrast ink), 40 tall, radius 20, 12
/// before Sal's `share` face at 26 and 16 after the words "Send to a
/// friend" (14, w600; founder, 1 November 2026: never "Share" here); the
/// press spring of every button. On the page's open it
/// enters on the sheet spring and pulses once (1.0 → 1.06 → 1.0; none
/// under Reduce Motion). Tapped, it opens the Sal sheet with
/// [barContext] (the context variant: Send the market / Send this
/// prediction) and travels to the composer as the pill does; transparent
/// while it travels and while the sheet is up. The page mounts it on the
/// headline figure's row, right-aligned and centred on the figure's first
/// line, inside the same [KuteBarContextScope] that declares the `header`
/// placement.
class KuteSalHeaderButton extends StatefulWidget {
  const KuteSalHeaderButton({super.key, required this.barContext});

  final KuteBarContext barContext;

  /// The button's height, Sal's side in it, and its padding before Sal
  /// and after the word.
  static const double height = 40;
  static const double salSize = 26;
  static const double paddingStart = 12;
  static const double paddingEnd = 16;

  /// The pulse on the page's open: once, to 1.06 and back.
  static const double pulseScale = 1.06;
  static const Duration pulseDuration = Duration(milliseconds: 360);

  @override
  State<KuteSalHeaderButton> createState() => _KuteSalHeaderButtonState();
}

class _KuteSalHeaderButtonState extends State<KuteSalHeaderButton>
    with TickerProviderStateMixin {
  bool _travelling = false;

  /// The entry (0 → 1 on the sheet spring), then the one pulse.
  late final AnimationController _entry = AnimationController(
      vsync: this, duration: KuteMotion.sheetInDuration);
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: KuteSalHeaderButton.pulseDuration);
  late final Animation<double> _pulseScale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: KuteSalHeaderButton.pulseScale)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 1),
    TweenSequenceItem(
        tween: Tween(begin: KuteSalHeaderButton.pulseScale, end: 1.0)
            .chain(CurveTween(curve: KuteMotion.settle)),
        weight: 1),
  ]).animate(_pulse);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (kuteReduceMotion(context)) {
      _entry.value = 1;
      return;
    }
    // ignore: discarded_futures
    _entry.forward().then((_) {
      if (mounted) _pulse.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _entry.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final ctx = widget.barContext;
    final ink = isLight ? Colors.white : c.background;
    final Widget button = Container(
      key: const ValueKey('kute-sal-header-button'),
      height: KuteSalHeaderButton.height,
      padding: const EdgeInsetsDirectional.only(
        start: KuteSalHeaderButton.paddingStart,
        end: KuteSalHeaderButton.paddingEnd,
      ),
      decoration: BoxDecoration(
        color: c.textPrimary,
        borderRadius: BorderRadius.circular(KuteSalHeaderButton.height / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SalSprite(
            clip: ctx.clip,
            size: KuteSalHeaderButton.salSize,
            fallback: SalSprite(
                clip: 'happy',
                size: KuteSalHeaderButton.salSize,
                fallback: KuteDogGlance(size: 22, color: ink)),
          ),
          const SizedBox(width: 8),
          // Loose in a min-size Row: the pill is its natural width wherever
          // the page gives it room, and where a page bounds it (a game
          // sheet's title row) the words shorten with an ellipsis instead
          // of the row overflowing.
          Flexible(
            child: Text(
              context.l10n.shareHeaderLabel,
              key: const ValueKey('kute-sal-header-label'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: ctx.label,
      excludeSemantics: true,
      child: KutePressable(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _travelling
              ? null
              : () => openKuteBarSheet(ctx, source: context, travelling: (on) {
                    if (mounted && _travelling != on) {
                      setState(() => _travelling = on);
                    }
                  }),
          // The entry: from a touch below and small, on the sheet
          // spring; then the pulse, once. ONE Opacity: the entry's fade
          // and the travel's transparency (the morph test reads it).
          child: AnimatedBuilder(
            animation: Listenable.merge([_entry, _pulse]),
            child: button,
            builder: (context, child) {
              final t = KuteMotion.sheetIn.transform(_entry.value);
              return Opacity(
                opacity: _travelling ? 0 : t.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, 8 * (1 - t)),
                  child: Transform.scale(
                    scale: (0.9 + 0.1 * t) * _pulseScale.value,
                    child: child,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// THE BAR AS THE PRIMARY BUTTON (founder, 31 October 2026; see
/// KuteBarContext.primary): the screen's 16 px gutters, 56 tall, a PILL
/// like the Sal pill it grows out of (founder, 1 November 2026: the big
/// black buttons, Send bitcoin, the slips' Place, wear the pill's shape
/// and its spring, the button filling the pill's space), the app's
/// primary fill (textPrimary, the mode's contrast label, w600 16), Sal's
/// 28 px face at the left: `curious` while the action is
/// not available (no amount yet), `idle` when it is, `search` at 1.4x
/// while busy. Disabled: the surface fill, a hairline and the quiet
/// label; not tappable. Busy: the label beside the progress ring; taps
/// ignored. A tap runs [KuteBarContext.onPrimary]; a long press (600 ms)
/// opens the Sal sheet ([onAsk]) so asking Sal stays available.
///
/// On a tinted slip the context carries the slip's own button look
/// ([KuteBarContext.style]; founder: never black on the green or red
/// slip): its fill, ink, radius and weight, the whole button at 0.35
/// while not available, as the slip's CTA was.
class KuteBarPrimaryButton extends StatelessWidget {
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

  /// The button's height, and the pill radius that follows from it.
  static const double height = 56;
  static final BorderRadius radius = BorderRadius.circular(height / 2);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ctx = barContext;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final busy = ctx.busy;
    final enabled = ctx.enabled && !busy && ctx.onPrimary != null;
    final live = enabled || busy;
    final style = ctx.style;
    final Color fill;
    final Color ink;
    if (style != null) {
      fill = live ? style.fill : (style.disabledFill ?? style.fill);
      ink = live
          ? style.foreground
          : (style.disabledForeground ?? style.foreground);
    } else {
      fill = live ? c.textPrimary : c.surfaceLight;
      ink = live ? (isLight ? Colors.white : c.background) : c.textTertiary;
    }
    // A styled button with no disabled colours of its own fades whole.
    final faded = style != null && !live && style.disabledFill == null;
    final clip = busy ? 'search' : (enabled ? 'idle' : 'curious');
    final label = busy ? (ctx.busyLabel ?? ctx.label) : ctx.label;
    final reduce = kuteReduceMotion(context);
    return Semantics(
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
          // on takes the tap.
          onTap: onPrimaryTap ??
              (enabled
                  ? () {
                      HapticFeedback.lightImpact();
                      ctx.onPrimary!();
                    }
                  : null),
          onLongPress: onAsk,
          child: AnimatedOpacity(
            opacity: faded ? 0.35 : 1,
            duration: reduce ? Duration.zero : KuteMotion.chipDuration,
            child: AnimatedContainer(
            key: const ValueKey('kute-bar-primary-button'),
            duration: reduce ? Duration.zero : KuteMotion.chipDuration,
            curve: reduce ? Curves.linear : KuteMotion.chip,
            height: KuteBarPrimaryButton.height,
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 14.w),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: style?.radius ?? KuteBarPrimaryButton.radius,
              border: Border.all(
                color: live || style != null
                    ? Colors.transparent
                    : (isLight ? c.border : c.borderSubtle),
                width: isLight ? 1.0 : 0.5,
              ),
            ),
            child: Row(
              children: [
                SalReactionSprite(
                  key: ValueKey('primary-sal-$clip'),
                  clip: clip,
                  size: 28,
                  speed: busy ? 1.4 : 1.0,
                  fallback: Icon(Icons.bolt_rounded, size: 22, color: ink),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: 16.sp,
                      fontWeight: style?.fontWeight ?? FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (busy) ...[
                  SizedBox(width: 10.w),
                  SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: ink),
                  ),
                ],
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}
