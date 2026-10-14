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
//   * subtle: the most it ever moves is [RubberBandProgress.maxStretch]
//     of the block's own height (8%), building fastest near the end;
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
/// block's height: monotonic, and steepest at the end, so the last step
/// pulls hardest. Public so the slips' tests can read the curve.
double rubberBandStretchFor(double progress,
    {double maxStretch = RubberBandProgress.defaultMaxStretch}) {
  final p = progress.isFinite ? progress.clamp(0.0, 1.0).toDouble() : 0.0;
  return maxStretch * math.pow(p, 1.6).toDouble();
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
  static const double defaultMaxStretch = 0.08;

  /// The breathing a waiting band keeps, as a share of the block's height.
  static const double breath = 0.006;

  /// One breath, in and out.
  static const Duration breathPeriod = Duration(milliseconds: 1600);

  /// The tension toward the next step: a stiff, slightly underdamped
  /// spring, so it gives a little as it settles.
  static const SpringDescription pullSpring =
      SpringDescription(mass: 1, stiffness: 180, damping: 20);

  /// The snap on success: underdamped, so it overshoots past rest and
  /// settles.
  static const SpringDescription snapSpring =
      SpringDescription(mass: 1, stiffness: 420, damping: 14);

  /// The release on failure: critically damped (2·√(k·m)), so it comes
  /// back to rest without passing it.
  static final SpringDescription softSpring =
      SpringDescription(mass: 1, stiffness: 120, damping: 2 * math.sqrt(120.0));

  /// How far along the action is, 0 (just tapped) to 1 (about to finish).
  final double progress;

  /// How it ended. Once it is not [RubberBandOutcome.none] the band lets
  /// go and stays at rest.
  final RubberBandOutcome outcome;

  /// The share of the block's height at full tension (about 6–10%).
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
/// placement: signing, submitting, the venue's answer): while [busy] the
/// tension eases from a first pull toward [ceiling] over [expected]
/// (never reaching it, so it keeps building), or follows [progress] when
/// the caller knows it. When [busy] ends the band lets go with [outcome]:
/// [RubberBandOutcome.success] snaps with the light haptic; anything else
/// (an end the caller does not name) releases softly, with no overshoot.
///
/// Nothing ticks while idle: the easing reads the clock on a slow timer
/// that runs only while [busy], and the band itself rests.
class RubberBandBusy extends StatefulWidget {
  const RubberBandBusy({
    super.key,
    required this.busy,
    required this.child,
    this.progress,
    this.outcome,
    this.expected = const Duration(seconds: 4),
    this.ceiling = 0.85,
    this.enabled = true,
  });

  /// The action is running.
  final bool busy;

  /// The known progress (0..1), or null to ease by time.
  final double? progress;

  /// How the action ended, read once [busy] is false. Null releases
  /// softly.
  final RubberBandOutcome? outcome;

  /// How long the action usually takes.
  final Duration expected;

  /// What the eased tension approaches.
  final double ceiling;

  /// False draws [child] alone (an outer band already carries it).
  final bool enabled;

  final Widget child;

  @override
  State<RubberBandBusy> createState() => _RubberBandBusyState();
}

class _RubberBandBusyState extends State<RubberBandBusy> {
  Timer? _clock;
  DateTime? _since;
  double _eased = 0;

  /// Whether this band ever pulled: an idle button never "releases".
  bool _pulled = false;

  static const Duration _step = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(RubberBandBusy oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.busy != widget.busy || oldWidget.progress != widget.progress)
      _sync();
  }

  void _sync() {
    if (widget.busy) {
      _pulled = true;
      if (widget.progress == null) {
        _since ??= DateTime.now();
        _eased = _easedAt(Duration.zero);
        _clock ??= Timer.periodic(_step, (_) {
          if (!mounted) return;
          final since = _since;
          if (since == null) return;
          setState(() => _eased = _easedAt(DateTime.now().difference(since)));
        });
      } else {
        _stopClock();
      }
    } else {
      _stopClock();
    }
  }

  /// A first pull, then toward [RubberBandBusy.ceiling], two thirds of the
  /// way by [RubberBandBusy.expected].
  double _easedAt(Duration t) {
    final tau = widget.expected.inMilliseconds / 1.1;
    final share = 1 - math.exp(-(t.inMilliseconds / (tau <= 0 ? 1 : tau)));
    const first = 0.2;
    return first + (widget.ceiling - first) * share;
  }

  void _stopClock() {
    _clock?.cancel();
    _clock = null;
    _since = null;
  }

  @override
  void dispose() {
    _stopClock();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final RubberBandOutcome outcome;
    final double progress;
    if (widget.busy) {
      outcome = RubberBandOutcome.none;
      progress = widget.progress ?? _eased;
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
