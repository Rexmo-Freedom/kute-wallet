// lib/screens/shared/rubber_band_progress.dart
//
// The "rubber band" a waiting money action wears (founder request, 14
// October 2026): like the pull that turns on vanish mode in a chat, the
// block under the person's thumb is drawn upward with growing resistance
// as the action gets closer to done, breathes a little while a step
// waits, and on the answer lets go: a spring snap (overshoot, then
// settle) with a light tap when it worked, a soft release with no
// overshoot when it did not.
//
// One widget for every place that waits on money after the tap: the bet
// slip and the Investing ticket while a funded order runs, and the
// Bitcoin send after Send.
//
// Rules it keeps:
//   * felt, still tasteful: the tap takes a first pull at once
//     ([RubberBandProgress.firstPull] of full tension, eased in about
//     250 ms), then it keeps building with time toward
//     [RubberBandBusy.ceiling] over the action's expected duration, and
//     jumps forward when a real phase arrives. Full tension is
//     [RubberBandProgress.defaultMaxStretch] (13%) of the block's height;
//   * the snap is seen: a caller that leaves on success (closing a sheet,
//     pushing a receipt) waits on [RubberBand.settle] first, a bounded
//     [RubberBand.snapSettle] (none under Reduce Motion);
//   * the text stays crisp: the block is translated, never scaled;
//   * Reduce Motion: nothing moves, the block sits at rest;
//   * nothing ticks while its tickers are off (covered by a route), while
//     the app is in the background, or at rest;
//   * the app's springs ([SpringSimulation]) and haptics, no package.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart' show HapticFeedback;

/// How a [RubberBandProgress]'s action ended.
enum RubberBandOutcome {
  /// Still waiting: the band holds the tension [RubberBandProgress.progress]
  /// asks for.
  none,

  /// It worked: a spring snap back, overshoot then settle, and a light
  /// haptic.
  success,

  /// It did not: a soft release back to rest, no overshoot.
  failure,
}

/// The tension the band holds at [progress] (0..1), as a fraction of the
/// block's height: [progress] is the share of full tension, so it is
/// monotonic and the first pull reads as what it says. The build's
/// easing (with time, toward the ceiling) lives in [RubberBandBusy] and
/// the send's band. Public so the slips' tests can read the curve.
double rubberBandStretchFor(double progress,
    {double maxStretch = RubberBandProgress.defaultMaxStretch}) {
  final p = progress.isFinite ? progress.clamp(0.0, 1.0).toDouble() : 0.0;
  return maxStretch * p;
}

/// The tension a busy band holds [elapsed] after it last moved to [from]:
/// it eases from [from] toward [ceiling] (two thirds of the way by
/// [expected]) and never reaches it, so it keeps building. A [from] at or
/// past [ceiling] holds.
double rubberBandEasedProgress(
  double from,
  Duration elapsed, {
  required Duration expected,
  double ceiling = RubberBandBusy.defaultCeiling,
}) {
  if (from >= ceiling) return from;
  final tau = math.max(1, expected.inMilliseconds) / 1.1;
  final share = 1 - math.exp(-(math.max(0, elapsed.inMilliseconds) / tau));
  return from + (ceiling - from) * share;
}

/// What a call site waits on before it moves past a band's ending.
class RubberBand {
  RubberBand._();

  /// How long the success snap is given before the sheet closes or the
  /// confirmation covers it: the spring has come back, bounced past rest
  /// and nearly settled (what is left is under a pixel).
  static const Duration snapSettle = Duration(milliseconds: 360);

  /// How long the soft release is given on a failure, for a caller that
  /// leaves on one.
  static const Duration softSettle = Duration(milliseconds: 320);

  /// Lets the band at [context] play its ending before the caller moves
  /// on: completes after [snapSettle] for a success ([softSettle]
  /// otherwise), and at once when nothing would be seen (Reduce Motion,
  /// tickers off because a route covers it, the app in the background,
  /// an unmounted context). Bounded: it never waits on the animation
  /// itself.
  ///
  /// Set the band's outcome first (in the same frame), then:
  ///
  /// ```dart
  /// setState(() => _bandOutcome = RubberBandOutcome.success);
  /// await RubberBand.settle(context);
  /// if (!mounted) return;
  /// _close();
  /// ```
  static Future<void> settle(BuildContext context,
      {RubberBandOutcome outcome = RubberBandOutcome.success}) {
    if (!context.mounted || !animates(context)) return Future.value();
    return Future.delayed(
        outcome == RubberBandOutcome.success ? snapSettle : softSettle);
  }

  /// Whether a band at [context] moves at all.
  static bool animates(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return false;
    if (!TickerMode.valuesOf(context).enabled) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }
}

/// Pulls [child] upward with an elastic tension that grows with
/// [progress], and releases it on [outcome]. See the file header.
class RubberBandProgress extends StatefulWidget {
  const RubberBandProgress({
    super.key,
    required this.progress,
    required this.child,
    this.outcome = RubberBandOutcome.none,
    this.maxStretch = defaultMaxStretch,
    this.haptic = true,
    this.onReleased,
  });

  /// The share of the block's height the band may pull it at full
  /// tension.
  static const double defaultMaxStretch = 0.13;

  /// The share of full tension the tap takes at once (the [pullSpring]
  /// eases it in, most of the way by about 250 ms).
  static const double firstPull = 0.38;

  /// The breathing a waiting band keeps, as a share of the block's height.
  static const double breath = 0.008;

  /// One breath, in and out.
  static const Duration breathPeriod = Duration(milliseconds: 1600);

  /// The tension toward the next step: stiff and just under critical
  /// damping, so a first pull lands in about 250 ms and gives a little as
  /// it settles.
  static const SpringDescription pullSpring =
      SpringDescription(mass: 1, stiffness: 260, damping: 27);

  /// The snap on success: underdamped, so it overshoots past rest and
  /// settles within [RubberBand.snapSettle].
  static const SpringDescription snapSpring =
      SpringDescription(mass: 1, stiffness: 600, damping: 22);

  /// The release on failure: critically damped (2·√(k·m)), so it comes
  /// back to rest without passing it.
  static final SpringDescription softSpring =
      SpringDescription(mass: 1, stiffness: 150, damping: 2 * math.sqrt(150.0));

  /// How far along the action is, 0 (just tapped) to 1 (about to finish).
  final double progress;

  /// How it ended. Once it is not [RubberBandOutcome.none] the band lets
  /// go and stays at rest.
  final RubberBandOutcome outcome;

  /// The share of the block's height at full tension (about 12–14%).
  final double maxStretch;

  /// A light haptic as the band snaps on success.
  final bool haptic;

  /// Called once the band has come to rest after an outcome.
  final VoidCallback? onReleased;

  final Widget child;

  @override
  State<RubberBandProgress> createState() => RubberBandProgressState();
}

/// Public so tests can read the band's offset ([stretch]) and whether it
/// is ticking ([ticking]).
class RubberBandProgressState extends State<RubberBandProgress>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// The tension, as a share of the block's height (unbounded: the snap
  /// overshoots below 0).
  late final AnimationController _level =
      AnimationController.unbounded(vsync: this);

  /// The breathing, 0..1 and back, while a step waits.
  late final AnimationController _breath = AnimationController(
      vsync: this, duration: RubberBandProgress.breathPeriod);

  bool _reduce = false;
  bool _tickerOff = false;
  bool _foreground = true;
  bool _released = false;

  bool get _halted => _reduce || _tickerOff || !_foreground;

  /// The band's offset now, as a share of the block's height (positive
  /// pulls up).
  @visibleForTesting
  double get stretch {
    if (_halted) return 0;
    final breathing = _breath.isAnimating
        ? RubberBandProgress.breath *
            math.sin(_breath.value * math.pi) *
            _breathScale
        : 0.0;
    return _level.value + breathing;
  }

  /// Whether anything is ticking.
  @visibleForTesting
  bool get ticking => _level.isAnimating || _breath.isAnimating;

  /// Breathing grows with the tension, never past the step it rides on.
  double get _breathScale =>
      (_target / widget.maxStretch).clamp(0.35, 1.0).toDouble();

  double get _target => widget.outcome == RubberBandOutcome.none
      ? rubberBandStretchFor(widget.progress, maxStretch: widget.maxStretch)
      : 0;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _level.addStatusListener(_onLevelStatus);
    // Built already ended (a slip reopened on a finished order): at rest,
    // nothing to let go of.
    _released = widget.outcome != RubberBandOutcome.none;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _tickerOff = !TickerMode.valuesOf(context).enabled;
    _sync(fromOutcome: false);
  }

  @override
  void didUpdateWidget(RubberBandProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    final outcomeChanged = oldWidget.outcome != widget.outcome;
    if (outcomeChanged && widget.outcome == RubberBandOutcome.none) {
      // A new action on the same block.
      _released = false;
    }
    if (outcomeChanged ||
        oldWidget.progress != widget.progress ||
        oldWidget.maxStretch != widget.maxStretch) {
      _sync(fromOutcome: outcomeChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync(fromOutcome: false);
  }

  void _onLevelStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (widget.outcome != RubberBandOutcome.none && !_released) {
      _released = true;
      _level.value = 0;
      widget.onReleased?.call();
    }
  }

  /// Runs the band toward what the widget asks for.
  void _sync({required bool fromOutcome}) {
    if (_halted) {
      // Still: at rest, nothing ticking. An ending still reports itself.
      if (_level.isAnimating) _level.stop();
      if (_breath.isAnimating) _breath.stop();
      _level.value = 0;
      if (widget.outcome != RubberBandOutcome.none && !_released) {
        _released = true;
        if (fromOutcome) {
          final done = widget.onReleased;
          if (done != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => done());
          }
        }
      }
      return;
    }
    switch (widget.outcome) {
      case RubberBandOutcome.none:
        final target = _target;
        if ((target - _level.value).abs() > 1e-6) {
          _level.animateWith(SpringSimulation(RubberBandProgress.pullSpring,
              _level.value, target, _level.velocity,
              tolerance: const Tolerance(distance: 1e-4, velocity: 1e-3)));
        }
        if (target > 0) {
          if (!_breath.isAnimating) _breath.repeat(reverse: true);
        } else if (_breath.isAnimating) {
          _breath.stop();
        }
      case RubberBandOutcome.success:
      case RubberBandOutcome.failure:
        if (_breath.isAnimating) _breath.stop();
        if (_released) {
          if (_level.isAnimating) _level.stop();
          _level.value = 0;
          return;
        }
        if (!fromOutcome && _level.isAnimating) return;
        final success = widget.outcome == RubberBandOutcome.success;
        if (success && widget.haptic && fromOutcome) {
          HapticFeedback.lightImpact();
        }
        final from = _level.value;
        if (from.abs() < 1e-4 && !success) {
          // Nothing to let go of.
          _level.value = 0;
          _released = true;
          final done = widget.onReleased;
          if (done != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => done());
          }
          return;
        }
        _level.animateWith(SpringSimulation(
          success
              ? RubberBandProgress.snapSpring
              : RubberBandProgress.softSpring,
          from,
          0,
          // The snap leaves with a kick toward rest; the soft release
          // starts still.
          success ? -math.max(from, 0.02) * 6 : 0,
          tolerance: const Tolerance(distance: 1e-4, velocity: 1e-3),
        ));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _level.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_halted) return widget.child;
    return AnimatedBuilder(
      animation: Listenable.merge([_level, _breath]),
      child: widget.child,
      // Translated, never scaled: the text inside stays crisp.
      builder: (context, child) => FractionalTranslation(
        translation: Offset(0, -stretch),
        child: child,
      ),
    );
  }
}

/// A [RubberBandProgress] for a wait whose phases cannot all be seen (a
/// placement: signing, submitting, the venue's answer).
///
/// While [busy] the band takes the first pull at once
/// ([RubberBandProgress.firstPull]) and keeps building with time toward
/// [ceiling] over [expected] (never reaching it). A phase the caller does
/// see ([progress]) jumps it forward, and the build goes on from there:
/// the tension never goes back while the action runs.
///
/// [outcome] [RubberBandOutcome.success] snaps it with the light haptic,
/// even while [busy] is still up, so a caller can keep its in-flight
/// guards armed while the snap plays ([RubberBand.settle]) and close
/// after. When [busy] ends without a success the band releases softly,
/// with no overshoot.
///
/// Nothing ticks while idle: the build's clock runs only while [busy]
/// (and never under Reduce Motion), on this widget's own ticker, so a
/// covering route or the background stops it too.
class RubberBandBusy extends StatefulWidget {
  const RubberBandBusy({
    super.key,
    required this.busy,
    required this.child,
    this.progress,
    this.outcome,
    this.expected = const Duration(seconds: 4),
    this.ceiling = defaultCeiling,
    this.enabled = true,
  });

  /// What the time build approaches.
  static const double defaultCeiling = 0.85;

  /// The action is running.
  final bool busy;

  /// The last phase the caller saw (0..1), or null for time alone. The
  /// band holds at least this much.
  final double? progress;

  /// How the action ended. [RubberBandOutcome.success] snaps (even while
  /// [busy]); anything else is read once [busy] is false, and releases
  /// softly.
  final RubberBandOutcome? outcome;

  /// How long the action usually takes.
  final Duration expected;

  /// What the time build approaches.
  final double ceiling;

  /// False draws [child] alone (an outer band already carries it).
  final bool enabled;

  final Widget child;

  @override
  State<RubberBandBusy> createState() => RubberBandBusyState();
}

/// Public so tests can read the built [progress] and whether the build's
/// clock is [easing].
class RubberBandBusyState extends State<RubberBandBusy>
    with SingleTickerProviderStateMixin {
  /// The build's clock: 0..1 over [_span], since the band last moved to
  /// [_from].
  late final AnimationController _clock = AnimationController(vsync: this)
    ..addListener(_onClock);

  /// Where the current build started from.
  double _from = 0;

  /// The tension the band is given now (share of full tension).
  double _eased = 0;

  /// Whether this band ever pulled: an idle button never "releases".
  bool _pulled = false;

  /// A success arrived while still busy: the band has let go.
  bool _snapped = false;

  bool _reduce = false;

  /// The built progress now.
  @visibleForTesting
  double get progress => _eased;

  /// Whether the build's clock is ticking.
  @visibleForTesting
  bool get easing => _clock.isAnimating;

  /// Long enough that the build has all but reached the ceiling.
  Duration get _span => widget.expected * 4;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync(starting: false);
  }

  @override
  void didUpdateWidget(RubberBandBusy oldWidget) {
    super.didUpdateWidget(oldWidget);
    final starting = widget.busy && !oldWidget.busy;
    if (starting) _snapped = false;
    if (widget.busy &&
        !starting &&
        widget.outcome == RubberBandOutcome.success &&
        oldWidget.outcome != RubberBandOutcome.success) {
      // It worked; the caller keeps busy up while the snap plays.
      _snapped = true;
    }
    if (oldWidget.busy != widget.busy ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.progress != widget.progress ||
        oldWidget.outcome != widget.outcome ||
        oldWidget.expected != widget.expected) {
      _sync(starting: starting);
    }
  }

  void _sync({required bool starting}) {
    if (!widget.enabled) {
      // An outer band carries this wait: nothing pulls here, so nothing
      // here lets go either.
      _stop();
      _pulled = false;
      return;
    }
    if (!widget.busy || _snapped) {
      _stop();
      return;
    }
    final phase = widget.progress ?? 0;
    if (!_pulled || starting) {
      // The tap: the first pull at once, and the build from there.
      _pulled = true;
      _restart(math.max(RubberBandProgress.firstPull, phase));
      return;
    }
    if (phase > _eased + 1e-6) {
      // A phase ahead of the clock: jump to it and build on from there.
      _restart(phase);
      return;
    }
    if (_reduce) {
      _stop();
    } else if (!_clock.isAnimating && _clock.value < 1) {
      // Reduce Motion turned off mid-wait: the build picks up again.
      _clock
        ..duration = _span
        ..forward();
    }
  }

  void _restart(double from) {
    _from = from;
    _eased = from;
    if (_reduce) {
      // Nothing moves under Reduce Motion, so nothing needs to tick.
      _stop();
      return;
    }
    _clock
      ..duration = _span
      ..forward(from: 0);
  }

  void _stop() {
    if (_clock.isAnimating) _clock.stop();
  }

  void _onClock() {
    final elapsed = _span * _clock.value;
    final next = rubberBandEasedProgress(_from, elapsed,
        expected: widget.expected, ceiling: math.max(widget.ceiling, _from));
    // A step at a time: the band's spring smooths between them, and the
    // block is not rebuilt every frame.
    if (next - _eased >= 0.01 || (!_clock.isAnimating && next > _eased)) {
      setState(() => _eased = next);
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final RubberBandOutcome outcome;
    final double progress;
    if (widget.busy && !_snapped) {
      outcome = RubberBandOutcome.none;
      progress = _eased;
    } else if (_pulled) {
      outcome = widget.outcome == RubberBandOutcome.success
          ? RubberBandOutcome.success
          : RubberBandOutcome.failure;
      progress = 0;
    } else {
      outcome = RubberBandOutcome.none;
      progress = 0;
    }
    return RubberBandProgress(
      progress: progress,
      outcome: outcome,
      child: widget.child,
    );
  }
}
