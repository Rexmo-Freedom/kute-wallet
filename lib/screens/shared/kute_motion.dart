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
//
// Every one of them honours Reduce Motion: with it on, the end state is
// drawn at once.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kute/screens/shared/rolling_number_text.dart';

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

/// Cross-fades [child] when [state] changes (and only then: a new child
/// with the same [state] updates in place), easing the height between the
/// two when [animateSize]. The outgoing child takes no taps while it fades.
class ArrivalSwitcher extends StatelessWidget {
  /// What the block is showing (e.g. 'title' / 'teams', 'deposit' /
  /// 'trade'); not its data.
  final Object state;
  final Widget child;
  final AlignmentGeometry alignment;
  final bool animateSize;

  const ArrivalSwitcher({
    super.key,
    required this.state,
    required this.child,
    this.alignment = Alignment.topLeft,
    this.animateSize = true,
  });

  static Widget _fade(Widget child, Animation<double> animation) =>
      FadeTransition(
        opacity: animation,
        child: AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) => IgnorePointer(
            ignoring: animation.status == AnimationStatus.reverse ||
                animation.status == AnimationStatus.dismissed,
            child: child,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final duration = kuteMotion(context, kArrivalDuration);
    final switcher = AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: _fade,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(key: ValueKey<Object>(state), child: child),
    );
    if (!animateSize) return switcher;
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
