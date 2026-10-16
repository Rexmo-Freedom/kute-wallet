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
//   * felt the whole time it runs: a continuous rumble with a ratchet
//     over it that rise with the band, until it is placed or fails, then
//     a whoosh and a double snap (or a soft tap); after 20 s of one
//     waiting step it drops to a soft heartbeat ([RubberBandHaptics], the
//     long-wait rule). The rumble stops at once when the band is covered, the app
//     leaves the foreground, under Reduce Motion and on dispose;
//   * the app's springs ([SpringSimulation]) and its own haptics bridge
//     ([ContinuousHaptics]: Core Haptics, Android's Vibrator), no new
//     package.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/haptic_lifecycle.dart';
import 'package:kute/services/kute_haptics.dart';

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

/// The pull's haptic, modelled on Instagram's vanish-mode pull (its
/// "sprocket"): a continuous rumble ([ContinuousHaptics]) that starts low
/// but felt the moment the action starts and rises with the band toward
/// full strength near placement, a ratchet of clicks over it that comes
/// faster and harder as the band tightens, and on success a whoosh into a
/// double snap ([ContinuousHaptics.snap]: the money-success pattern); a
/// soft tap on a release without. It plays the whole time the action
/// runs, holds included, until it is placed or fails.
///
/// The long-wait rule: a funded bet or order can wait 1-5 minutes for its
/// money to land, and a minutes-long rumble would be unbearable and drain
/// the battery. So after [longWait] of rumble in one waiting step it drops
/// to a heartbeat: one soft [ContinuousHaptics.pulse] every
/// [heartbeatPeriod] at the current level, no rumble, no ratchet. The next
/// step (a rise of at least [stepJump] in the band's progress at once)
/// brings the rumble and the ratchet back, through the final placing step.
abstract final class RubberBandHaptics {
  /// The rumble's strength at rest and at full tension.
  static const double startIntensity = 0.3;
  static const double fullIntensity = 1.0;

  /// The rumble's sharpness at rest and at full tension: a low, soft
  /// rumble that gets edgier as it tightens.
  static const double startSharpness = 0.1;
  static const double fullSharpness = 0.5;

  /// The ratchet's gap between two clicks at rest and at full tension:
  /// 5 clicks a second at the tap, about 16 at full.
  static const Duration ratchetSlow = Duration(milliseconds: 200);
  static const Duration ratchetFast = Duration(milliseconds: 60);

  /// A click's strength and sharpness at rest (both reach 1 at full).
  static const double tickStartIntensity = 0.35;
  static const double tickStartSharpness = 0.55;

  /// How long one waiting step keeps the rumble before the heartbeat.
  static const Duration longWait = Duration(seconds: 20);

  /// The heartbeat's beat, once the rumble has given way.
  static const Duration heartbeatPeriod = Duration(seconds: 1);

  /// A rise in the band's progress at least this big, at once, is a new
  /// step (a phase arriving), not the time build creeping on.
  static const double stepJump = 0.05;

  /// Kept for callers of the earlier stream of taps.
  static const double step = 0.025;
  static const Duration minGap = Duration(milliseconds: 28);
  static const double lightFrom = 0.35;
  static const double mediumFrom = 0.7;

  static double _lerp(double a, double b, double t) =>
      a + (b - a) * t.clamp(0.0, 1.0);

  /// The rumble's strength at [share] of the full stretch.
  static double intensityFor(double share) =>
      _lerp(startIntensity, fullIntensity, share);

  /// The rumble's sharpness at [share] of the full stretch.
  static double sharpnessFor(double share) =>
      _lerp(startSharpness, fullSharpness, share);

  /// The ratchet's gap at [share] of the full stretch.
  static Duration ratchetGapFor(double share) => Duration(
      microseconds: _lerp(ratchetSlow.inMicroseconds.toDouble(),
              ratchetFast.inMicroseconds.toDouble(), share)
          .round());

  /// One ratchet click at [share] of the full stretch ([owner]'s: only
  /// the strongest band ratchets when several pull at once).
  static void tick(double share, {Object? owner}) => ContinuousHaptics.tick(
      _lerp(tickStartIntensity, 1, share), _lerp(tickStartSharpness, 1, share),
      owner: owner);
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
    return HapticLifecycle.isForeground;
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
    this.failureTap = true,
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

  /// The pull's continuous haptic while the action runs
  /// ([RubberBandHaptics]: a rumble and a ratchet rising with the band, a
  /// heartbeat on a long wait), a whoosh and a double snap on success and a soft
  /// tap on a release without.
  final bool haptic;

  /// Whether a release without plays its soft tap. False for a band whose
  /// stop may be the person's own (the send's: a declined face scan, a
  /// stop for re-review), whose screen plays the failure tap itself when
  /// the send really failed (`moneyFailureFeedbackAfterBand`).
  final bool failureTap;

  /// Called once the band has come to rest after an outcome.
  final VoidCallback? onReleased;

  final Widget child;

  @override
  State<RubberBandProgress> createState() => RubberBandProgressState();
}

/// Public so tests can read the band's offset ([stretch]) and whether it
/// is ticking ([ticking]).
class RubberBandProgressState extends State<RubberBandProgress>
    with TickerProviderStateMixin {
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

  /// The haptic's clock: runs only while the pull is felt (the action
  /// running, the band in view, the app in front, motion allowed).
  late final Ticker _feel = createTicker(_onFeel);

  /// The haptic's clock now, and when the current step started on it.
  Duration _feelNow = Duration.zero;
  Duration _stepAt = Duration.zero;

  /// The last ratchet click and the last heartbeat beat.
  Duration? _clickAt;
  Duration? _beatAt;

  /// The long-wait rule has given the rumble way to the heartbeat.
  bool _heartbeat = false;

  /// The share of the full stretch the haptic follows: the band's, never
  /// going back while the action runs (the pull spring's give does not
  /// soften it).
  double _feltShare = 0;

  bool get _halted => _reduce || _tickerOff || !_foreground;

  /// Whether the pull is felt now.
  bool get _feels =>
      widget.haptic &&
      !_halted &&
      widget.outcome == RubberBandOutcome.none &&
      _target > 0;

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
  bool get ticking =>
      _level.isAnimating || _breath.isAnimating || _feel.isActive;

  /// Whether the pull's haptic is on (the rumble, or the heartbeat after
  /// a long wait) and which.
  @visibleForTesting
  bool get feeling => _feel.isActive;
  @visibleForTesting
  bool get heartbeat => _feel.isActive && _heartbeat;

  /// Breathing grows with the tension, never past the step it rides on.
  double get _breathScale =>
      (_target / widget.maxStretch).clamp(0.35, 1.0).toDouble();

  double get _target => widget.outcome == RubberBandOutcome.none
      ? rubberBandStretchFor(widget.progress, maxStretch: widget.maxStretch)
      : 0;

  @override
  void initState() {
    super.initState();
    _foreground = HapticLifecycle.isForeground;
    HapticLifecycle.foreground.addListener(_onForegroundChanged);
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
      _feltShare = 0;
    }
    if (!outcomeChanged &&
        widget.outcome == RubberBandOutcome.none &&
        widget.progress - oldWidget.progress >= RubberBandHaptics.stepJump &&
        _feel.isActive) {
      // A new step: the rumble comes back from a heartbeat, and the long
      // wait counts again from here.
      _newStep();
    }
    if (outcomeChanged ||
        oldWidget.progress != widget.progress ||
        oldWidget.maxStretch != widget.maxStretch) {
      _sync(fromOutcome: outcomeChanged);
    }
  }

  void _onForegroundChanged() {
    _foreground = HapticLifecycle.isForeground;
    _sync(fromOutcome: false);
  }

  /// The share of the full stretch the band holds now, for the haptic.
  double get _bandShare {
    if (widget.maxStretch <= 0) return 0;
    final v = _level.value / widget.maxStretch;
    return v.isFinite ? v.clamp(0.0, 1.0).toDouble() : 0.0;
  }

  /// Turns the pull's haptic on or off to match the band
  /// ([RubberBandHaptics]): on from the moment the action starts, off at
  /// once when it ends, when the band is covered, the app leaves the
  /// foreground or motion is reduced.
  void _syncFeel() {
    if (_feels) {
      if (_feel.isActive) return;
      _feelNow = Duration.zero;
      _stepAt = Duration.zero;
      _clickAt = null;
      _beatAt = null;
      _heartbeat = false;
      _feltShare = math.max(_feltShare, _bandShare);
      _rumble();
      _feel.start();
    } else {
      _stopFeel();
    }
  }

  /// Starts the rumble at the felt level, with a first click: the tap is
  /// felt at once.
  void _rumble() {
    ContinuousHaptics.start(RubberBandHaptics.intensityFor(_feltShare),
        RubberBandHaptics.sharpnessFor(_feltShare),
        owner: this);
    RubberBandHaptics.tick(_feltShare, owner: this);
    _clickAt = _feelNow;
  }

  void _stopFeel() {
    if (_feel.isActive) _feel.stop();
    _heartbeat = false;
    ContinuousHaptics.stop(owner: this);
  }

  void _newStep() {
    _stepAt = _feelNow;
    if (_heartbeat) {
      _heartbeat = false;
      _beatAt = null;
      _rumble();
    }
  }

  /// One frame of the pull's haptic: the rumble follows the band (about
  /// 30 updates a second, [ContinuousHaptics.updateGap]) and the ratchet
  /// clicks closer together as it tightens; after
  /// [RubberBandHaptics.longWait] in one step, a heartbeat instead.
  void _onFeel(Duration elapsed) {
    _feelNow = elapsed;
    _feltShare = math.max(_feltShare, _bandShare);
    final share = _feltShare;
    if (!_heartbeat && elapsed - _stepAt >= RubberBandHaptics.longWait) {
      // The long-wait rule: the rumble gives way to a soft heartbeat
      // until the next step.
      _heartbeat = true;
      _beatAt = elapsed;
      ContinuousHaptics.stop(owner: this);
    }
    if (_heartbeat) {
      final beat = _beatAt;
      if (beat == null || elapsed - beat >= RubberBandHaptics.heartbeatPeriod) {
        _beatAt = elapsed;
        ContinuousHaptics.pulse(RubberBandHaptics.intensityFor(share),
            at: elapsed);
      }
      return;
    }
    ContinuousHaptics.update(RubberBandHaptics.intensityFor(share),
        RubberBandHaptics.sharpnessFor(share),
        owner: this, at: elapsed);
    final click = _clickAt;
    if (click == null ||
        elapsed - click >= RubberBandHaptics.ratchetGapFor(share)) {
      _clickAt = elapsed;
      RubberBandHaptics.tick(share, owner: this);
    }
  }

  void _onLevelStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (widget.outcome != RubberBandOutcome.none && !_released) {
      _released = true;
      _level.value = 0;
      widget.onReleased?.call();
    }
  }

  /// Runs the band (and its haptic) toward what the widget asks for.
  void _sync({required bool fromOutcome}) {
    _syncBand(fromOutcome: fromOutcome);
    _syncFeel();
  }

  void _syncBand({required bool fromOutcome}) {
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
        if (widget.haptic && fromOutcome) {
          // The release is felt: the rumble stops, then the money-success
          // pattern (a whoosh into a double snap) when it went through,
          // one soft tap when it let go without. The success is the
          // money-success moment: the confirmation right after it does
          // not play it again.
          _stopFeel();
          if (success) {
            KuteHaptics.noteSuccessRelease();
            ContinuousHaptics.snap(owner: this);
          } else if (_level.value > 1e-3 && widget.failureTap) {
            // The failure moment: a failure tap asked for right after it
            // (`moneyFailureFeedback`) does not play it again.
            KuteHaptics.noteFailureRelease();
            ContinuousHaptics.softTap(owner: this);
          }
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
    HapticLifecycle.foreground.removeListener(_onForegroundChanged);
    _stopFeel();
    _feel.dispose();
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
/// [outcome] [RubberBandOutcome.success] snaps it with the heavy haptic,
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
    this.failureTap = true,
  });

  /// What the time build approaches.
  static const double defaultCeiling = 0.85;

  /// Whether a release without plays its soft tap
  /// ([RubberBandProgress.failureTap]). False for an action whose stop may
  /// be the person's own (a declined approval), whose screen plays the
  /// failure tap itself once the band has let go
  /// (`moneyFailureFeedbackAfterBand`).
  final bool failureTap;

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
      failureTap: widget.failureTap,
      child: widget.child,
    );
  }
}
