// lib/screens/shared/kute_motion.dart
//
// The small transitions the browse lists, the cards and the slips share,
// so a screen that changes state eases into it instead of snapping:
//
//   * [SliverSelectionFade] / [SelectionFade]: a list under pills fades
//     its new content in when the selection changes (never on a data
//     refresh). The list is neither rebuilt nor remounted by it: only an
//     opacity runs, so paging, scroll position and state are untouched.
//   * [ArrivalSwitcher]: a block that changes shape when its data lands
//     (a fallback title giving way to a game's rows, a button changing
//     what it does) cross-fades and eases its height.
//   * [RollingFigure]: a live figure on a card rolls the digits that
//     changed ([RollingNumberText]), and never rolls from another row's
//     value when a list hands the widget to another market.
//   * [ScorePulseText]: a score whose number changes pulses that number.
//   * [KuteStillWhenCovered]: a live screen with a slip open over it draws
//     its end states at once, as under Reduce Motion, until it is on top
//     again.
//   * [KutePressScale]: something tappable that is not a card or a button
//     (the Investments balance) gives the cards' press feedback.
//   * [KuteStaggerIn]: a list's first rows (markets, activity) fade and
//     rise in, 20 ms apart, the first time they are painted; a row past
//     the eighth, or one that arrives later, is drawn at once.
//   * [KutePressable]: THE press feedback (founder, 31 October 2026, after
//     Orchestra): 0.98 while held, back on the press spring
//     (KuteMotion.press, lib/theme/kute_motion.dart). Wrapped around a
//     pill, a soft row, an action button: a Listener only, so the child's
//     own tap, ink, hit area and semantics are untouched.
//   * [FoldAway] / [StepsReveal]: a slip or sheet whose money steps show
//     under its button folds its keypad and amount chips away (the
//     amount cannot change then) and the steps grow into that room and
//     fade in, so nothing above is squeezed, clipped or jumps.
//
// Every one of them honours Reduce Motion: with it on, the end state is
// drawn at once.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/kute_motion.dart';

/// Whether the person asked the system for less motion.
bool kuteReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// [duration], or none under Reduce Motion.
Duration kuteMotion(BuildContext context, Duration duration) =>
    kuteReduceMotion(context) ? Duration.zero : duration;

/// A list's fade when its pill changes.
const Duration kSelectionFadeDuration = Duration(milliseconds: 170);

/// A block's cross-fade when its data lands.
const Duration kArrivalDuration = Duration(milliseconds: 180);

/// A score's pulse.
const Duration kScorePulseDuration = Duration(milliseconds: 250);

/// Runs a fade-in each time [selection] changes; the first build and any
/// rebuild with the same selection draw at full opacity.
mixin _SelectionFadeController<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: kSelectionFadeDuration,
    value: 1,
  );
  late final Animation<double> opacity =
      CurvedAnimation(parent: _fade, curve: Curves.easeOut);

  void selectionChanged() {
    if (kuteReduceMotion(context)) {
      _fade.value = 1;
    } else {
      _fade.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }
}

/// The slivers of a list under pills, faded in when [selection] changes.
///
/// The slivers are laid out as one group ([SliverMainAxisGroup]) so a
/// lazy list inside keeps building only what is on screen; the fade is
/// an opacity on that group, so nothing is rebuilt or read again for it.
class SliverSelectionFade extends StatefulWidget {
  /// What the pills chose (a category, a subcategory). Data refreshes keep
  /// it equal and so never fade.
  final Object? selection;
  final List<Widget> slivers;

  const SliverSelectionFade({
    super.key,
    required this.selection,
    required this.slivers,
  });

  @override
  State<SliverSelectionFade> createState() => _SliverSelectionFadeState();
}

class _SliverSelectionFadeState extends State<SliverSelectionFade>
    with
        SingleTickerProviderStateMixin<SliverSelectionFade>,
        _SelectionFadeController<SliverSelectionFade> {
  @override
  void didUpdateWidget(SliverSelectionFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) selectionChanged();
  }

  @override
  Widget build(BuildContext context) => SliverFadeTransition(
        opacity: opacity,
        sliver: SliverMainAxisGroup(slivers: widget.slivers),
      );
}

/// A box's content faded in when [selection] changes. The child keeps its
/// element and its state: only an opacity runs.
class SelectionFade extends StatefulWidget {
  final Object? selection;
  final Widget child;

  const SelectionFade({super.key, required this.selection, required this.child});

  @override
  State<SelectionFade> createState() => _SelectionFadeState();
}

class _SelectionFadeState extends State<SelectionFade>
    with
        SingleTickerProviderStateMixin<SelectionFade>,
        _SelectionFadeController<SelectionFade> {
  @override
  void didUpdateWidget(SelectionFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) selectionChanged();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: opacity, child: widget.child);
}

/// How long a keypad takes to fold away for the money's steps, and the
/// steps to grow in.
const Duration kStepsRoomDuration = Duration(milliseconds: 250);

/// Folds [child] away while [folded]: its height eases to nothing as it
/// fades (ease-out, [kStepsRoomDuration]; at once under Reduce Motion),
/// and back the same way. A slip's keypad and amount chips give their
/// room to the money's steps this way while those show: the amount cannot
/// change then. Once folded the child leaves the tree (no taps, nothing
/// read out); while it moves it takes no taps.
class FoldAway extends StatelessWidget {
  const FoldAway({super.key, required this.folded, required this.child});

  final bool folded;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: folded ? 0 : 1),
        duration: kuteMotion(context, kStepsRoomDuration),
        curve: Curves.easeOut,
        child: child,
        builder: (context, open, child) {
          if (open <= 0) return const SizedBox.shrink();
          return ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: open,
              child: IgnorePointer(
                ignoring: open < 1,
                child: Opacity(opacity: open, child: child),
              ),
            ),
          );
        },
      );
}

/// The money's steps under a button ([child], null while there are none):
/// they grow into their room and fade in when they appear, rather than
/// popping in, and their room eases away when they go. At once under
/// Reduce Motion.
class StepsReveal extends StatelessWidget {
  const StepsReveal({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final duration = kuteMotion(context, kStepsRoomDuration);
    final shown = child;
    final body = shown == null
        ? const SizedBox(width: double.infinity)
        : TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: duration,
            curve: Curves.easeOut,
            child: shown,
            builder: (context, v, child) =>
                Opacity(opacity: v, alwaysIncludeSemantics: true, child: child),
          );
    // No AnimatedSize of no duration (see [ArrivalSwitcher]).
    if (duration == Duration.zero) return body;
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: body,
    );
  }
}

/// How long a [ArrivalSwitcher.sequential] swap takes: the old child out
/// in the first half, the new one in over the second.
const Duration kSequentialSwapDuration = Duration(milliseconds: 240);

/// Cross-fades [child] when [state] changes (and only then: a new child
/// with the same [state] updates in place), easing the height between the
/// two when [animateSize]. The outgoing child takes no taps while it fades.
///
/// [sequential] never shows the two at once: the old child fades out
/// first, then the new one fades in ([kSequentialSwapDuration]). For two
/// things drawn in the same place with words on them (a slip's button
/// becoming another button), where a cross-fade lays one label over the
/// other.
class ArrivalSwitcher extends StatelessWidget {
  /// What the block is showing (e.g. 'title' / 'teams', 'deposit' /
  /// 'trade'); not its data.
  final Object state;
  final Widget child;
  final AlignmentGeometry alignment;
  final bool animateSize;
  final bool sequential;

  const ArrivalSwitcher({
    super.key,
    required this.state,
    required this.child,
    this.alignment = Alignment.topLeft,
    this.animateSize = true,
    this.sequential = false,
  });

  /// Opaque only past the animation's midpoint: run forward the new child
  /// stays hidden for the first half, run in reverse the old one is gone
  /// by the half.
  static final Animatable<double> _secondHalf =
      CurveTween(curve: const Interval(0.5, 1, curve: Curves.easeOut));

  static Widget _fadeSequential(Widget child, Animation<double> animation) =>
      _fade(child, animation.drive(_secondHalf), gate: animation);

  static Widget _fade(Widget child, Animation<double> animation,
          {Animation<double>? gate}) =>
      FadeTransition(
        opacity: animation,
        child: AnimatedBuilder(
          animation: gate ?? animation,
          child: child,
          builder: (context, child) => IgnorePointer(
            ignoring: (gate ?? animation).status == AnimationStatus.reverse ||
                (gate ?? animation).status == AnimationStatus.dismissed,
            child: child,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final duration = kuteMotion(
        context, sequential ? kSequentialSwapDuration : kArrivalDuration);
    // Sequential runs linear, the easing inside each half: an eased
    // controller would bend the halves into each other and overlap them.
    final switcher = AnimatedSwitcher(
      duration: duration,
      switchInCurve: sequential ? Curves.linear : Curves.easeOut,
      switchOutCurve: sequential ? Curves.linear : Curves.easeOut,
      transitionBuilder: sequential ? _fadeSequential : _fade,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(key: ValueKey<Object>(state), child: child),
    );
    // Under Reduce Motion the size snaps with the content: an AnimatedSize
    // of no duration would notify its listeners inside its own layout and
    // re-dirty itself there (a Flutter assertion), so none is used.
    if (!animateSize || duration == Duration.zero) return switcher;
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeInOut,
      alignment: alignment,
      child: switcher,
    );
  }
}

/// A live figure that rolls the digits that changed. [identity] names
/// what the figure belongs to (a market, an outcome): a list that hands
/// the widget to another one starts it afresh instead of rolling from the
/// other one's value.
class RollingFigure extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Object? identity;

  const RollingFigure({
    super.key,
    required this.text,
    required this.style,
    this.identity,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        label: text,
        excludeSemantics: true,
        child: KeyedSubtree(
          key: ValueKey<Object?>(identity),
          child: RollingNumberText(
            text: text,
            style: style,
            duration: kuteMotion(context, const Duration(milliseconds: 250)),
          ),
        ),
      );
}

/// A score written as runs of digits and the text between them ("2-1",
/// "6-3, 3-6"). When a run's number changes it pulses: up about 8% and
/// back. Never on the first build, and never when [identity] changes (a
/// list handing the widget to another game).
class ScorePulseText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Object? identity;
  final TextAlign? textAlign;

  const ScorePulseText({
    super.key,
    required this.text,
    required this.style,
    this.identity,
    this.textAlign,
  });

  static final _runs = RegExp(r'\d+|\D+');

  @override
  Widget build(BuildContext context) {
    final runs = _runs.allMatches(text).map((m) => m.group(0)!).toList();
    if (runs.length <= 1 && (runs.isEmpty || !_isNumber(runs.first))) {
      return Text(text, maxLines: 1, style: style, textAlign: textAlign);
    }
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < runs.length; i++)
            _isNumber(runs[i])
                ? _PulseRun(
                    key: ValueKey<int>(i),
                    text: runs[i],
                    style: style,
                    identity: identity,
                  )
                : Text(runs[i], maxLines: 1, style: style),
        ],
      ),
    );
  }

  static bool _isNumber(String run) =>
      run.isNotEmpty && run.codeUnitAt(0) >= 0x30 && run.codeUnitAt(0) <= 0x39;
}

class _PulseRun extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Object? identity;

  const _PulseRun({
    super.key,
    required this.text,
    required this.style,
    required this.identity,
  });

  @override
  State<_PulseRun> createState() => _PulseRunState();
}

class _PulseRunState extends State<_PulseRun>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: kScorePulseDuration);

  /// 1 → 1.08 → 1, easing out of the start and into the end.
  late final Animation<double> _scale = _pulse
      .drive(_PulseTween().chain(CurveTween(curve: Curves.easeInOut)));

  @override
  void didUpdateWidget(_PulseRun oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity == widget.identity &&
        oldWidget.text != widget.text &&
        !kuteReduceMotion(context)) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: _scale,
        child: Text(widget.text, maxLines: 1, style: widget.style),
      );
}

class _PulseTween extends Animatable<double> {
  @override
  double transform(double t) => 1 + 0.08 * math.sin(math.pi * t);
}

/// A screen with another route over it (a slip, a picker) draws its end
/// states at once, the way Reduce Motion does, until it is on top again.
///
/// A slip leaves the live screen it was opened from on stage, dimmed behind
/// its barrier and still following the feed. Each tick there started a
/// tick's transitions (a price's roll and flash, a chart's glide and
/// pulse), so the screen under the slip animated on most frames: an
/// Investing market ticks about eight times a second and each tick moved
/// its screen for most of a second. That work shared every frame with the
/// slip sliding and scrolling on top. Covered, the screen still updates on
/// each tick, in one frame, with nothing left running after it.
///
/// It goes still the moment a route covers it (so the sheet slides in over
/// a still screen too) and moves again the moment it is on top. Switching
/// rebuilds only what reads the motion setting, a few dozen widgets, fewer
/// than one tick rebuilds. Wrap the screen's whole page in it, always (the
/// wrapper never changes shape, so nothing under it is rebuilt from scratch
/// when it switches).
class KuteStillWhenCovered extends StatelessWidget {
  final Widget child;

  const KuteStillWhenCovered({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final covered = !(ModalRoute.isCurrentOf(context) ?? true);
    return MediaQuery(
      data: media.copyWith(disableAnimations: media.disableAnimations || covered),
      child: child,
    );
  }
}

/// The app's press feedback (AppCard's): the child eases to 97% while a
/// finger is down, a light haptic on the tap. Under Reduce Motion the
/// child never scales. Read in build, never in initState.
class KutePressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const KutePressScale({super.key, required this.child, required this.onTap});

  @override
  State<KutePressScale> createState() => _KutePressScaleState();
}

class _KutePressScaleState extends State<KutePressScale> {
  bool _pressed = false;

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = kuteReduceMotion(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: reduceMotion ? null : (_) => _press(true),
      onTapUp: reduceMotion ? null : (_) => _press(false),
      onTapCancel: reduceMotion ? null : () => _press(false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      // Down quick and plain, up on the press spring (KuteMotion).
      child: AnimatedScale(
        scale: _pressed && !reduceMotion ? 0.97 : 1.0,
        duration: reduceMotion
            ? Duration.zero
            : (_pressed ? KuteMotion.pressInDuration : KuteMotion.pressDuration),
        curve: _pressed ? Curves.easeOut : KuteMotion.press,
        child: widget.child,
      ),
    );
  }
}

/// The app's press feedback on anything already tappable: the child eases
/// to [KuteMotion.pressScale] while a finger is down and springs back
/// ([KuteMotion.press]) on release. A [Listener] under the child's own
/// gesture handling, so its tap, ink, hit area and semantics are exactly
/// as they were; a finger that moves on (a scroll) lets go at once. Under
/// Reduce Motion nothing moves. [enabled] false: nothing moves either (a
/// disabled button).
class KutePressable extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const KutePressable({super.key, required this.child, this.enabled = true});

  @override
  State<KutePressable> createState() => _KutePressableState();
}

class _KutePressableState extends State<KutePressable> {
  bool _down = false;
  Offset? _start;

  /// Travel past which the touch is a drag, not a press.
  static const double _slop = 10;

  void _set(bool value) {
    if (_down != value && mounted) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final still = !widget.enabled || kuteReduceMotion(context);
    final pressed = _down && !still;
    return Listener(
      onPointerDown: still
          ? null
          : (e) {
              _start = e.position;
              _set(true);
            },
      onPointerMove: still
          ? null
          : (e) {
              final start = _start;
              if (start != null && (e.position - start).distance > _slop) {
                _set(false);
              }
            },
      onPointerUp: still ? null : (_) => _set(false),
      onPointerCancel: still ? null : (_) => _set(false),
      child: AnimatedScale(
        scale: pressed ? KuteMotion.pressScale : 1.0,
        duration: still
            ? Duration.zero
            : (pressed ? KuteMotion.pressInDuration : KuteMotion.pressDuration),
        curve: pressed ? Curves.easeOut : KuteMotion.press,
        child: widget.child,
      ),
    );
  }
}

/// How many rows of a list stagger in, and the step between them.
const int kStaggerRows = 8;
const Duration kStaggerStep = Duration(milliseconds: 20);

/// A row's arrival on first paint (founder, 31 October 2026): opacity and
/// a 10 px rise, settled on the app's settle easing, starting
/// [kStaggerStep] times [index] after the first row. Rows at [index]
/// [kStaggerRows] or more, and every row under Reduce Motion, are drawn
/// at once. Runs once per mount: a rebuild with new data does not replay.
class KuteStaggerIn extends StatefulWidget {
  final int index;
  final Widget child;

  const KuteStaggerIn({super.key, required this.index, required this.child});

  @override
  State<KuteStaggerIn> createState() => _KuteStaggerInState();
}

class _KuteStaggerInState extends State<KuteStaggerIn>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (widget.index >= kStaggerRows || kuteReduceMotion(context)) return;
    final c = AnimationController(
        vsync: this, duration: KuteMotion.settleDuration);
    _controller = c;
    Future<void>.delayed(kStaggerStep * widget.index, () {
      if (mounted && !c.isAnimating && c.value == 0) c.forward();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return widget.child;
    final curved = CurvedAnimation(parent: c, curve: KuteMotion.settle);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 10 * (1 - curved.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
