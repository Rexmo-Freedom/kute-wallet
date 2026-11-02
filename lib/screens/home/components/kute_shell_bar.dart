// lib/screens/home/components/kute_shell_bar.dart
//
// The bar over everything (founder, 31 October 2026; see
// kute_bar_context.dart): drawn once, above the root navigator (the
// MaterialApp builder's Stack, app_widget.dart), so it sits over pushed
// pages, modal barriers and sheets. It shows the topmost [KuteBarContext]
// on the stack while that context's route is current, else the default
// ("Search or manage with AI") over any page or sheet pushed over the tabs
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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:kute/screens/shared/kute_morph_label.dart';
import 'package:kute/screens/shared/sal_reactions.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';
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
            ? KuteBarContext(label: context.l10n.searchOrManageAi)
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
              onAsk: () => _open(
                  kuteBarAskContext(ref.read(kuteBarContextProvider), ctx)),
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
                    // The pill's air; the primary button takes the
                    // screen's 16 px gutters.
                    padding: EdgeInsets.fromLTRB(ctx.isPrimary ? 16.w : 12.w, 0,
                        ctx.isPrimary ? 16.w : 12.w, 2.h),
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

/// THE FIGURE AND ITS SHARE BUTTON ON ONE ROW: [figure] in the width the
/// button leaves it, [share] (a [KuteSalHeaderButton], in whatever box
/// the page wraps it) at the row's end. The button is offered the room
/// the figure does not need at its natural width, so it says "Send to a
/// friend" where that fits beside the number and "Share" where it does
/// not (KuteSalHeaderButton.fittingLabel); then the figure takes the
/// rest, as the Expanded it was. [alignTop]: both at the row's top (the
/// page centres the button on the figure's first line itself); else
/// centred on each other.
class KuteFigureShareRow extends MultiChildRenderObjectWidget {
  KuteFigureShareRow({
    super.key,
    required Widget figure,
    required Widget share,
    this.gap = 8,
    this.alignTop = false,
  }) : super(children: [figure, share]);

  final double gap;
  final bool alignTop;

  /// The least the button is offered: room for "Share" whole.
  static double _minShare(BuildContext context) =>
      KuteSalHeaderButton.widthFor(context, context.l10n.share);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderKuteFigureShareRow(
          gap: gap, alignTop: alignTop, minShare: _minShare(context));

  @override
  void updateRenderObject(
      BuildContext context, RenderKuteFigureShareRow renderObject) {
    renderObject
      ..gap = gap
      ..alignTop = alignTop
      ..minShare = _minShare(context);
  }
}

class _FigureShareParentData extends ContainerBoxParentData<RenderBox> {}

/// The render object of [KuteFigureShareRow].
class RenderKuteFigureShareRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FigureShareParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FigureShareParentData> {
  RenderKuteFigureShareRow(
      {required double gap, required bool alignTop, required double minShare})
      : _gap = gap,
        _alignTop = alignTop,
        _minShare = minShare;

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  bool _alignTop;
  set alignTop(bool value) {
    if (value == _alignTop) return;
    _alignTop = value;
    markNeedsLayout();
  }

  /// The least the button is offered, whatever the figure wants: room for
  /// "Share" whole.
  double _minShare;
  set minShare(double value) {
    if (value == _minShare) return;
    _minShare = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FigureShareParentData) {
      child.parentData = _FigureShareParentData();
    }
  }

  /// The figure's natural width; half the row when the figure cannot
  /// say (a layout builder inside it has no intrinsic size).
  double _figureNatural(RenderBox figure, double width) {
    try {
      return figure.getMaxIntrinsicWidth(double.infinity);
    } on FlutterError {
      return width / 2;
    } on AssertionError {
      return width / 2;
    }
  }

  @override
  void performLayout() {
    final figure = firstChild!;
    final share = childAfter(figure)!;
    final width = constraints.maxWidth;
    final natural = _figureNatural(figure, width);
    final shareMax =
        math.min(width, math.max(width - _gap - natural, _minShare));
    share.layout(BoxConstraints(maxWidth: shareMax), parentUsesSize: true);
    final figureWidth = math.max(0.0, width - _gap - share.size.width);
    figure.layout(BoxConstraints.tightFor(width: figureWidth),
        parentUsesSize: true);
    final height = math.max(figure.size.height, share.size.height);
    final figureData = figure.parentData! as _FigureShareParentData;
    final shareData = share.parentData! as _FigureShareParentData;
    figureData.offset =
        Offset(0, _alignTop ? 0 : (height - figure.size.height) / 2);
    shareData.offset = Offset(width - share.size.width,
        _alignTop ? 0 : (height - share.size.height) / 2);
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// THE SHARE BUTTON BESIDE A PAGE'S BIG NUMBER (founder, 31 October 2026;
/// see the file header): a real button in the app's primary look (the
/// textPrimary fill, the mode's contrast ink), 40 tall, radius 20, 12
/// before Sal's `share` face at 26 and 16 after the words "Send to a
/// friend" (14, w600; founder, 1 November 2026), or "Share" where those
/// do not fit beside the figure at the current text scale, never an
/// ellipsis ([fittingLabel], [KuteFigureShareRow]); the press spring of
/// every button. On the page's open it
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

  /// The words' style on the button.
  static TextStyle labelStyle(Color ink) => TextStyle(
        color: ink,
        fontSize: 14.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.2,
      );

  /// The words the button says in [maxWidth] (founder, 1 November 2026):
  /// "Send to a friend" where it fits whole beside the figure at the
  /// current text scale, else "Share"; never an ellipsis. Unbounded: the
  /// long words.
  static String fittingLabel(BuildContext context, double maxWidth) {
    final l10n = context.l10n;
    final long = l10n.shareHeaderLabel;
    if (!maxWidth.isFinite) return long;
    return widthFor(context, long) <= maxWidth ? long : l10n.share;
  }

  /// The button's width saying [words] at the current text scale.
  static double widthFor(BuildContext context, String words) {
    final painter = TextPainter(
      // The style the words inherit there (the theme's face) under the
      // button's own.
      text: TextSpan(
          text: words,
          style: DefaultTextStyle.of(context)
              .style
              .merge(labelStyle(Colors.black))),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = KuteSalHeaderButton.paddingStart +
        KuteSalHeaderButton.salSize +
        8 +
        painter.width +
        KuteSalHeaderButton.paddingEnd;
    painter.dispose();
    // A hair over, so the words are never cut by a rounding.
    return width.ceilToDouble() + 1;
  }


  @override
  State<KuteSalHeaderButton> createState() => _KuteSalHeaderButtonState();
}

class _KuteSalHeaderButtonState extends State<KuteSalHeaderButton>
    with TickerProviderStateMixin {
  bool _travelling = false;

  /// The entry (0 → 1 on the sheet spring), then the one pulse.
  late final AnimationController _entry =
      AnimationController(vsync: this, duration: KuteMotion.sheetInDuration);
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
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, box) =>
          _build(context, KuteSalHeaderButton.fittingLabel(context, box.maxWidth)));

  Widget _build(BuildContext context, String words) {
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
              words,
              key: const ValueKey('kute-sal-header-label'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KuteSalHeaderButton.labelStyle(ink),
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

/// THE BAR AS THE PRIMARY BUTTON, AN ADAPTIVE PILL (founder, 1 November
/// 2026; see KuteBarContext.primary). The button is only as wide as what
/// it says, like the search pill: Sal's 28 px face, the label and the
/// padding, at least [minWidth] and at most the screen less its 16 px
/// gutters, centred, [height] tall, fully rounded. It morphs from the
/// search pill and between its states with the Dollars strip's motion
/// (kute_pill_tabs.dart): the width springs on [KuteMotion.chip] (the
/// shell bar's [KuteMorphSize]), the old words slide up and out and the
/// new ones rise in from below ([KuteMorphLabel]), Sal's clip crossfades
/// ([KuteMorphFace]), the fill and ink change on the settle. The Sal pill
/// changes its words with the same pieces (kute_morph_label.dart). At once
/// under Reduce Motion.
///
/// THREE STATES:
///   * DISABLED says the step to take ([KuteBarContext.disabledLabel]:
///     "Enter an amount", "Add who to send to") in the LIGHT pill look:
///     white (surface in dark), a hairline, the textSecondary label, Sal
///     `curious`. Never a black or grey-filled bar. Taps do nothing.
///   * ENABLED is the action in the black look: textPrimary fill, the
///     mode's contrast label at w600, Sal `idle`. A tinted slip keeps its
///     own [KuteBarPrimaryStyle] (fill, ink, radius, weight).
///   * BUSY keeps the size, says the busy label ("Sending…"), Sal plays
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

class _KuteBarPrimaryButtonState extends State<KuteBarPrimaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
      vsync: this, duration: KuteBarPrimaryButton.shimmerPeriod);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncShimmer();
  }

  @override
  void didUpdateWidget(covariant KuteBarPrimaryButton old) {
    super.didUpdateWidget(old);
    _syncShimmer();
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

  @override
  void dispose() {
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
    final Color fill;
    final Color ink;
    final Color border;
    if (!live) {
      // The light pill (the search pill's own surface), never filled grey.
      fill = isLight ? Colors.white : c.surface;
      ink = c.textSecondary;
      border = isLight ? c.border : c.borderSubtle;
    } else if (style != null) {
      fill = style.fill;
      ink = style.foreground;
      border = Colors.transparent;
    } else {
      fill = c.textPrimary;
      ink = isLight ? Colors.white : c.background;
      border = Colors.transparent;
    }
    final label = ctx.primaryLabel;
    final reduce = kuteReduceMotion(context);
    final duration = reduce ? Duration.zero : KuteMotion.chipDuration;
    final radius = live
        ? (style?.radius ?? KuteBarPrimaryButton.radius)
        : KuteBarPrimaryButton.radius;
    final textStyle = KuteOverlaySurface.textStyle(context).copyWith(
      color: ink,
      fontSize: 16.sp,
      fontWeight:
          live ? (style?.fontWeight ?? FontWeight.w600) : FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.2,
    );
    // Keyed by the words alone: the same words in another state (busy
    // under the same label) stay put, only their ink changes.
    final ValueKey<String> labelKey = ValueKey('primary-label|$label');

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

    // The words: the old slide up and out, the new rise from below (the
    // pill's and the strip's cross-slide, kute_morph_label.dart). Only the
    // current words size the button; the leaving ones overflow it as they
    // go.
    final Widget words = KuteMorphLabel(
      child: Text(
        label,
        key: labelKey,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: textStyle,
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
          Flexible(child: words),
        ],
      ),
    );

    final Widget capsule = AnimatedContainer(
      key: const ValueKey('kute-bar-primary-button'),
      duration: duration,
      // The fill, the ink's ground and the hairline change on the settle:
      // a decoration lerp never rides the spring (kute_motion.dart).
      curve: reduce ? Curves.linear : KuteMotion.settle,
      height: KuteBarPrimaryButton.height,
      // Its own width, at least [KuteBarPrimaryButton.minWidth]; exactly
      // the pair's width beside a page's own pill. The free width is
      // capped at the screen's, never unbounded: a context that swaps
      // paired for free (a sheet over the onboarding pair) lerps between
      // two finite boxes (an unbounded one cannot be interpolated).
      constraints: ctx.pairedWidth != null
          ? BoxConstraints.tightFor(width: ctx.pairedWidth)
          : BoxConstraints(
              minWidth: KuteBarPrimaryButton.minWidth,
              maxWidth: MediaQuery.sizeOf(context).width,
            ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(color: border, width: isLight ? 1.0 : 0.5),
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
            child: capsule,
          ),
        ),
      ),
    );
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
