// lib/screens/polymarket/components/position_speedometer.dart
//
// The open-position screen's speedometer: the held side's chance, 0 to
// 100%, on a 180° dial, for a Predictions bet that is still open (a live
// price, not settled). A settled position keeps the chance bar
// (position_chance_bar.dart).
//
// What it draws, calm and the same for every market (Yes / No, Up /
// Down, a candidate, a team):
//   * a thin neutral track with round ends, three small ticks at 0, 50
//     and 100, no figures, no zones;
//   * the price paid as a small filled dot on the track;
//   * a thin needle from a small solid hub, both in the primary text
//     colour, short enough that its tip always stops below the chance;
//     at its tip a round grab knob in the same colour inside a faint ring
//     of it, so the needle reads as something to take hold of;
//   * the live chance, large, in the upper middle of the dial, so the
//     needle never crosses its digits.

// The needle is a car's tachometer needle: its angle is a spring
// ([kPolyNeedleSpring], slightly under-damped), so it accelerates,
// overshoots by a few percent of the move and settles. A new live price
// mid-motion retargets the spring from where the needle is AND how fast it
// is moving: never a restart, never a jump. It never leaves 0–100. On open
// it sweeps up from 0 to the live chance with the same spring, once the
// screen has slid in. Reduce Motion: no sweep and no overshoot, a 120 ms
// ease to each new price.
//
// Haptics: one tap each time the live chance shown changes (66.1% to
// 66.3%), the money journey's own step tap (money_steps_view.dart: a
// selection click, foreground only), at most one per [kPolyLiveTapGap]: a
// burst inside that gap plays one more tap at its end, never more. Never
// during the opening sweep, never while the screen is covered (its
// tickers muted) or the app is in the background. Haptics are always on
// (KuteHaptics) and, as on the journey, still play under Reduce Motion.
//
// Drag to explore: a finger on the dial (pan anywhere on it; a touch on
// the needle or the hub grabs it at once, elsewhere a sideways drag wins
// over the page's scroll) sets a hypothetical chance, whole percents. The
// chance reads that value with "If No reaches" over it, a selection tick
// every 5% crossed (at most one per [kPolyNeedleTickGap]);
// [onExploreStart] / [onExplore] / [onExploreEnd] let the screen show what
// the position would be worth. On release the needle
// springs back to the live chance. Nothing here is logged; the screen
// logs the what-if once it is over.
//
// Until the first drag on this device ([PolyDialDragMemory]; the screen
// passes [hintDrag]), the needle shows it can be moved: once, a moment
// after the opening sweep has settled, it leans a few degrees and springs
// back ([kPolyNeedleNudge]), no haptic; the screen writes a quiet "Drag
// the needle to see what it'd be worth" under the result. Reduce Motion:
// no lean, the knob and the line only.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, visibleForTesting;
import 'package:hive_ce/hive.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart'
    show formatPolyBoughtCents;
import 'package:kute/screens/polymarket/components/price_format.dart'
    show formatPolyChanceFigure;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/theme/app_theme.dart';

/// The needle's spring, on the 0..1 dial (one unit is the whole dial).
///
/// mass 1, stiffness 90, damping 13.3: natural frequency √90 ≈ 9.49 rad/s,
/// damping ratio 13.3 / (2·√90) ≈ 0.70. That overshoots by
/// e^(−ζπ/√(1−ζ²)) ≈ 4.6% of the move, peaks after ≈ 0.46 s and is within
/// 2% of the target after ≈ 0.6 s, within 1% after ≈ 0.7 s: a tachometer
/// needle that leans past and settles, never a wobble.
const SpringDescription kPolyNeedleSpring =
    SpringDescription(mass: 1, stiffness: 90, damping: 13.3);

/// When the spring counts as settled: a twentieth of a percent away and
/// barely moving.
const Tolerance kPolyNeedleTolerance =
    Tolerance(distance: 0.0005, velocity: 0.004);

/// Reduce Motion: a short ease to each new price instead of the spring.
const Duration kPolyNeedleReducedMotion = Duration(milliseconds: 120);

/// The least time between two haptic ticks of a drag.
const Duration kPolyNeedleTickGap = Duration(milliseconds: 80);

/// The least time between two taps of the live chance changing.
const Duration kPolyLiveTapGap = Duration(milliseconds: 120);

/// The drag hint's lean: how far (a share of the dial) the needle leans
/// before springing back, and how long it leans.
const double kPolyNeedleNudge = 0.04;
const Duration kPolyNeedleNudgeHold = Duration(milliseconds: 260);

/// How long after the opening sweep settles (or the screen opens, without
/// a sweep) the needle leans.
const Duration kPolyNeedleNudgeDelay = Duration(milliseconds: 700);

/// Whether the dial has ever been dragged on this device: until then the
/// open-position screen hints that it can be ([PolyPositionSpeedometer.hintDrag]).
/// Kept in the app's settings box; a session flag covers a box not open.
class PolyDialDragMemory {
  PolyDialDragMemory._();

  static const String key = 'poly_position_dial_dragged';
  static bool _session = false;

  static bool get dragged {
    if (_session) return true;
    try {
      if (Hive.isBoxOpen('settings')) {
        return Hive.box('settings').get(key) == true;
      }
    } catch (_) {}
    return false;
  }

  static void noteDragged() {
    if (_session) return;
    _session = true;
    try {
      if (Hive.isBoxOpen('settings')) Hive.box('settings').put(key, true);
    } catch (_) {}
  }

  @visibleForTesting
  static void debugReset() => _session = false;
}

/// The angle of [fraction] (0 to 1 from the left) along the half circle
/// (canvas radians: π at the left end, 3π/2 at the top, 2π at the right).
double polyGaugeAngle(double fraction) =>
    math.pi + fraction.clamp(0.0, 1.0) * math.pi;

/// Whether moving from [from] to [to] (0..1) crosses a 5% mark.
bool polyNeedleCrossesMark(double from, double to) {
  int bucket(double x) => (x.clamp(0.0, 1.0) * 20 + 1e-9).floor();
  return bucket(from) != bucket(to);
}

/// [fraction] rounded to a whole percent.
double polyWholePercent(double fraction) =>
    (fraction.clamp(0.0, 1.0) * 100).round() / 100;

/// A 120 ms ease-out from [from] to [to], for Reduce Motion: no
/// overshoot.
class _EaseSimulation extends Simulation {
  _EaseSimulation(this.from, this.to, Duration duration)
      : _seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;

  final double from;
  final double to;
  final double _seconds;

  double _p(double t) => (t / _seconds).clamp(0.0, 1.0).toDouble();

  @override
  double x(double time) => from + (to - from) * Curves.easeOut.transform(_p(time));

  @override
  double dx(double time) {
    if (time >= _seconds) return 0;
    const h = 1e-4;
    return (x(time + h) - x(time)) / h;
  }

  @override
  bool isDone(double time) => time >= _seconds;
}

/// The needle's motion on the 0..1 dial: a spring toward a target,
/// retargeted from its current position and velocity. Pure, so it can be
/// stepped by hand.
class PolyNeedleMotion {
  PolyNeedleMotion({double position = 0, this.spring = kPolyNeedleSpring})
      : _x = position.clamp(0.0, 1.0).toDouble() {
    _target = _x;
  }

  final SpringDescription spring;
  double _x;
  double _v = 0;
  late double _target;
  Simulation? _sim;
  double _t = 0;

  /// Where the needle is, always within 0..1.
  double get position => _x;

  /// How fast it moves, in dials per second.
  double get velocity => _v;

  double get target => _target;

  bool get isMoving => _sim != null;

  /// Heads for [target] from where the needle is, at the speed it is
  /// moving ([velocity] instead, when given). [reduceMotion]: a short
  /// ease, no overshoot.
  void retarget(double target, {bool reduceMotion = false, double? velocity}) {
    _target = target.clamp(0.0, 1.0).toDouble();
    final v0 = velocity ?? _v;
    _t = 0;
    if (reduceMotion) {
      _v = 0;
      _sim = (_x - _target).abs() < 1e-9
          ? null
          : _EaseSimulation(_x, _target, kPolyNeedleReducedMotion);
    } else {
      _sim = SpringSimulation(spring, _x, _target, v0,
          tolerance: kPolyNeedleTolerance);
    }
    final sim = _sim;
    if (sim != null && sim.isDone(0)) _settle();
  }

  /// Puts the needle at [position], still.
  void jumpTo(double position) {
    _x = position.clamp(0.0, 1.0).toDouble();
    _target = _x;
    _v = 0;
    _sim = null;
  }

  void _settle() {
    _x = _target;
    _v = 0;
    _sim = null;
  }

  /// Moves [seconds] on. Returns whether the needle is still moving.
  bool advance(double seconds) {
    final sim = _sim;
    if (sim == null) return false;
    _t += seconds;
    if (sim.isDone(_t)) {
      _settle();
      return false;
    }
    var x = sim.x(_t);
    var v = sim.dx(_t);
    // The dial's stops: an overshoot past 0 or 100 rests on the stop (and
    // a retarget from there starts still).
    if (x <= 0) {
      x = 0;
      if (v < 0) v = 0;
    } else if (x >= 1) {
      x = 1;
      if (v > 0) v = 0;
    }
    _x = x;
    _v = v;
    return true;
  }
}

/// Where everything of the dial sits, in the dial's own box.
typedef PolySpeedometerGeometry = ({
  Size size,
  Offset center,

  /// The track's centre line.
  double radius,
  double stroke,

  /// The needle's length, from the hub's centre.
  double needle,
});

/// The track's width, the hub's and the entry dot's radius.
const double kPolySpeedometerStroke = 4;
const double kPolySpeedometerHub = 5;
const double kPolySpeedometerEntryDot = 4;

/// The grab knob at the needle's tip, and the faint ring around it.
const double kPolySpeedometerKnob = 6.5;
const double kPolySpeedometerKnobRing = 12;

/// Lays the dial out across [width]: the track as wide as it allows
/// (capped on tablets), room above it for the entry dot and below the
/// centre line for the hub; the needle under half the track's radius, so
/// the chance above it is never crossed.
PolySpeedometerGeometry polySpeedometerGeometry(double width) {
  const margin = kPolySpeedometerEntryDot + 2;
  final outer =
      (width / 2 - margin).clamp(math.min(60.0, width / 4), 190.0).toDouble();
  final radius = outer - kPolySpeedometerStroke / 2;
  final top = outer + margin - kPolySpeedometerStroke / 2;
  const below = kPolySpeedometerHub + 1;
  return (
    size: Size(width, top + below),
    center: Offset(width / 2, top),
    radius: radius,
    stroke: kPolySpeedometerStroke,
    needle: radius * 0.42,
  );
}

/// The figure of [full] (`betPercentChance` of [figure]) with its own
/// "%" ("75.8%", "75.8 %"), and the rest of the sentence ("chance",
/// "de chances", "Szansa", "確率").
({String figure, String caption}) polyGaugeChanceParts(
    String full, String figure) {
  final at = full.indexOf(figure);
  if (at < 0) return (figure: full, caption: '');
  final before = full.substring(0, at);
  var after = full.substring(at + figure.length);
  final pct = RegExp('^[   ]?%').firstMatch(after);
  final shown = '$figure${pct?.group(0) ?? ''}';
  after = after.substring(pct?.end ?? 0);
  final caption = '$before $after'.replaceAll(RegExp(r'\s+'), ' ').trim();
  return (figure: shown, caption: caption);
}

/// A pan that wins at once when it starts on the needle or the hub
/// ([grabs]); anywhere else on the dial it waits, as a pan does, so a
/// vertical drag still scrolls the page.
class _DialPanRecognizer extends PanGestureRecognizer {
  _DialPanRecognizer({super.debugOwner});

  bool Function(Offset local)? grabs;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    final g = grabs;
    if (g != null && g(event.localPosition)) {
      resolvePointer(event.pointer, GestureDisposition.accepted);
    }
  }
}

/// What the needle is doing.
enum _NeedleMode {
  /// Still, or following the live price (the only motion that ticks).
  live,

  /// The opening sweep from 0.
  sweep,

  /// The drag hint's lean and spring back.
  nudge,

  /// Under the finger.
  drag,

  /// Springing back to the live price after a drag.
  returning,
}

class PolyPositionSpeedometer extends StatefulWidget {
  const PolyPositionSpeedometer({
    super.key,
    required this.chance,
    required this.side,
    this.entry,
    this.sweepOnOpen = true,
    this.hintDrag = false,
    this.onExploreStart,
    this.onExplore,
    this.onExploreEnd,
  });

  /// The held side's live chance (0 to 1).
  final double chance;

  /// The held side's name, for "If {side} reaches".
  final String side;

  /// The average price paid per share (0 to 1): the entry tick. Null when
  /// unknown.
  final double? entry;

  /// Sweep up from 0 on open (off under Reduce Motion).
  final bool sweepOnOpen;

  /// The dial has never been dragged: lean the needle once, a moment after
  /// it settles, to show it moves (off under Reduce Motion).
  final bool hintDrag;

  /// A drag on the dial began.
  final VoidCallback? onExploreStart;

  /// The hypothetical chance under the finger, whole percents.
  final ValueChanged<double>? onExplore;

  /// The drag ended at this hypothetical chance; the needle springs back.
  final ValueChanged<double>? onExploreEnd;

  static const dialKey = ValueKey('poly-speedometer');
  static const dialPaintKey = ValueKey('poly-speedometer-dial');
  static const needlePaintKey = ValueKey('poly-speedometer-needle');
  static const entryLabelKey = ValueKey('poly-speedometer-entry');
  static const figureKey = ValueKey('poly-speedometer-figure');
  static const captionKey = ValueKey('poly-speedometer-caption');
  static const readoutKey = ValueKey('poly-speedometer-readout');

  /// Test seam: stands in for the selection tick.
  @visibleForTesting
  static void Function()? debugSelectionTick;

  @override
  State<PolyPositionSpeedometer> createState() =>
      PolyPositionSpeedometerState();
}

class PolyPositionSpeedometerState extends State<PolyPositionSpeedometer>
    with SingleTickerProviderStateMixin {
  late final PolyNeedleMotion _motion;
  late final Ticker _ticker;
  late final ValueNotifier<double> _needle;
  Duration _lastElapsed = Duration.zero;

  /// The live tap's gap: running after a tap; a change inside it leaves
  /// one more tap for its end.
  Timer? _liveTapGap;
  bool _liveTapPending = false;

  /// The drag tick's gap: a crossing inside it is dropped.
  Timer? _dragTickGap;

  /// The drag hint: the wait before the lean, then the lean's hold.
  Timer? _nudgeTimer;
  bool _nudged = false;

  _NeedleMode _mode = _NeedleMode.live;
  bool _reduceMotion = false;
  bool _started = false;
  Animation<double>? _routeAnimation;

  /// The hypothetical chance while dragging.
  double? _hypo;

  /// Where the dial sits, for the drag's angle.
  PolySpeedometerGeometry? _geometry;
  late final _DialPanRecognizer _pan;

  /// The needle's position (0..1), for tests.
  @visibleForTesting
  double get debugNeedle => _motion.position;

  @visibleForTesting
  double get debugNeedleVelocity => _motion.velocity;

  @visibleForTesting
  bool get debugSweeping => _mode == _NeedleMode.sweep;

  @visibleForTesting
  bool get debugNudging => _mode == _NeedleMode.nudge;

  @visibleForTesting
  bool get debugNudged => _nudged;

  @override
  void initState() {
    super.initState();
    _motion = PolyNeedleMotion(position: 0);
    _needle = ValueNotifier(0);
    _ticker = createTicker(_onTick);
    _pan = _DialPanRecognizer(debugOwner: this)
      ..grabs = _grabs
      ..onStart = _onPanStart
      ..onUpdate = _onPanUpdate
      ..onEnd = _onPanEnd
      ..onCancel = _onPanCancel;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!_started) {
      _started = true;
      final live = widget.chance.clamp(0.0, 1.0).toDouble();
      if (_reduceMotion || !widget.sweepOnOpen) {
        _jump(live);
        _scheduleNudge();
      } else {
        _jump(0);
        // Once the screen has slid in, so the sweep is seen.
        final anim = ModalRoute.of(context)?.animation;
        if (anim == null || anim.status == AnimationStatus.completed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _startSweep();
          });
        } else {
          _routeAnimation = anim..addStatusListener(_onRouteStatus);
        }
      }
    }
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = null;
    if (mounted) _startSweep();
  }

  /// The drag hint's lean, once, [kPolyNeedleNudgeDelay] from now: only
  /// while the dial has never been dragged, never under Reduce Motion.
  void _scheduleNudge() {
    if (_nudged || !widget.hintDrag || _reduceMotion) return;
    _nudgeTimer?.cancel();
    _nudgeTimer = Timer(kPolyNeedleNudgeDelay, _nudge);
  }

  void _nudge() {
    _nudgeTimer = null;
    if (!mounted || _nudged || !widget.hintDrag || _reduceMotion) return;
    if (_mode != _NeedleMode.live || _motion.isMoving) return;
    // Covered by another screen: not seen, so not spent.
    if (!TickerMode.valuesOf(context).enabled) return;
    _nudged = true;
    _mode = _NeedleMode.nudge;
    final live = widget.chance.clamp(0.0, 1.0).toDouble();
    // Toward the roomier side, so the lean is never lost on a stop.
    final lean = live > 0.5 ? -kPolyNeedleNudge : kPolyNeedleNudge;
    _retarget(live + lean);
    _nudgeTimer = Timer(kPolyNeedleNudgeHold, () {
      _nudgeTimer = null;
      if (!mounted || _mode != _NeedleMode.nudge) return;
      _retarget(widget.chance);
    });
  }

  void _startSweep() {
    if (_mode == _NeedleMode.drag) return;
    _mode = _NeedleMode.sweep;
    _retarget(widget.chance);
  }

  @override
  void didUpdateWidget(PolyPositionSpeedometer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chance == widget.chance) return;
    if (formatPolyChanceFigure(oldWidget.chance) !=
        formatPolyChanceFigure(widget.chance)) {
      _onLiveChanceShown();
    }
    switch (_mode) {
      case _NeedleMode.drag:
        // The finger has it; the release springs back to the new price.
        break;
      case _NeedleMode.sweep:
        if (_ticker.isActive || _routeAnimation == null) {
          _retarget(widget.chance);
        }
      case _NeedleMode.nudge:
        // A new price ends the lean: straight to it.
        _nudgeTimer?.cancel();
        _nudgeTimer = null;
        _mode = _NeedleMode.returning;
        _retarget(widget.chance);
      case _NeedleMode.returning:
        _retarget(widget.chance);
      case _NeedleMode.live:
        _retarget(widget.chance);
    }
  }

  /// The live chance shown changed: one tap, unless a tap played less
  /// than [kPolyLiveTapGap] ago (then one at the gap's end). Not during
  /// the sweep, nor while a drag shows its own chance.
  void _onLiveChanceShown() {
    if (_mode == _NeedleMode.sweep || _mode == _NeedleMode.drag) return;
    if (_liveTapGap != null) {
      _liveTapPending = true;
      return;
    }
    _liveTap();
  }

  void _liveTap() {
    // Covered by another screen (its tickers muted): nothing to feel.
    if (!TickerMode.valuesOf(context).enabled) return;
    _selectionTick();
    _liveTapGap = Timer(kPolyLiveTapGap, () {
      _liveTapGap = null;
      if (!mounted || !_liveTapPending) return;
      _liveTapPending = false;
      if (_mode == _NeedleMode.sweep || _mode == _NeedleMode.drag) return;
      _liveTap();
    });
  }

  @override
  void dispose() {
    _nudgeTimer?.cancel();
    _liveTapGap?.cancel();
    _dragTickGap?.cancel();
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _ticker.dispose();
    _needle.dispose();
    _pan.dispose();
    super.dispose();
  }

  void _jump(double x) {
    _ticker.stop();
    _motion.jumpTo(x);
    _needle.value = _motion.position;
  }

  /// Heads for [target] from where the needle is and how fast it moves.
  void _retarget(double target, {double? velocity}) {
    _motion.retarget(target,
        reduceMotion: _reduceMotion, velocity: velocity);
    _needle.value = _motion.position;
    if (_motion.isMoving) {
      if (!_ticker.isActive) {
        _lastElapsed = Duration.zero;
        _ticker.start();
      }
    } else {
      _ticker.stop();
      _settled();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    final moving = _motion.advance(dt.inMicroseconds / 1e6);
    _needle.value = _motion.position;
    if (!moving) {
      _ticker.stop();
      _settled();
    }
  }

  void _settled() {
    final swept = _mode == _NeedleMode.sweep;
    if (swept || _mode == _NeedleMode.returning) {
      _mode = _NeedleMode.live;
    }
    // Back from the lean (its hold over): live again.
    if (_mode == _NeedleMode.nudge && _nudgeTimer == null) {
      _mode = _NeedleMode.live;
    }
    if (swept) _scheduleNudge();
  }

  /// The money journey's step tap (money_steps_view.dart): a selection
  /// click, in the foreground only.
  static void _selectionTick() {
    if (!KuteHaptics.isForeground) return;
    final seam = PolyPositionSpeedometer.debugSelectionTick;
    if (seam != null) {
      seam();
      return;
    }
    unawaited(HapticFeedback.selectionClick());
  }

  // ─── Drag ─────────────────────────────────────────────────────────

  /// The chance (0..1) at [local] on the dial: by the angle from the
  /// hub; below the hub's line, the nearer end.
  double _fractionAt(Offset local) {
    final g = _geometry;
    if (g == null) return _motion.position;
    final d = local - g.center;
    if (d.dy >= 0) return d.dx < 0 ? 0 : 1;
    return ((math.atan2(d.dy, d.dx) + math.pi) / math.pi)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// A touch on the needle (near its line) or the hub grabs it at once.
  bool _grabs(Offset local) {
    final g = _geometry;
    if (g == null) return false;
    final d = local - g.center;
    final r = d.distance;
    if (r < 44) return true;
    if (r > g.radius + 24 || d.dy > 12) return false;
    final a = polyGaugeAngle(_motion.position);
    final u = Offset(math.cos(a), math.sin(a));
    final along = d.dx * u.dx + d.dy * u.dy;
    final across = (d.dx * u.dy - d.dy * u.dx).abs();
    return along > 0 && across < 28;
  }

  void _onPanStart(DragStartDetails details) {
    _nudgeTimer?.cancel();
    _nudgeTimer = null;
    _nudged = true;
    _ticker.stop();
    _mode = _NeedleMode.drag;
    final f = _fractionAt(details.localPosition);
    _motion.jumpTo(f);
    _needle.value = f;
    final h = polyWholePercent(f);
    setState(() => _hypo = h);
    widget.onExploreStart?.call();
    widget.onExplore?.call(h);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_mode != _NeedleMode.drag) return;
    final before = _motion.position;
    final f = _fractionAt(details.localPosition);
    _motion.jumpTo(f);
    _needle.value = f;
    if (polyNeedleCrossesMark(before, f) && _dragTickGap == null) {
      _selectionTick();
      _dragTickGap = Timer(kPolyNeedleTickGap, () => _dragTickGap = null);
    }
    final h = polyWholePercent(f);
    if (h != _hypo) {
      setState(() => _hypo = h);
      widget.onExplore?.call(h);
    }
  }

  void _release() {
    if (_mode != _NeedleMode.drag) return;
    final h = _hypo ?? polyWholePercent(_motion.position);
    setState(() => _hypo = null);
    _mode = _NeedleMode.returning;
    _retarget(widget.chance, velocity: 0);
    widget.onExploreEnd?.call(h);
  }

  void _onPanEnd(DragEndDetails details) => _release();
  void _onPanCancel() => _release();

  // ─── Build ────────────────────────────────────────────────────────

  /// The room between the needle's reach and the chance's baseline:
  /// clear of the knob's ring.
  static const double _figureGap = kPolySpeedometerKnobRing + 3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final entry = widget.entry != null &&
            widget.entry! > 0 &&
            widget.entry! < 1
        ? widget.entry
        : null;

    final hypo = _hypo;
    final shown = hypo ?? widget.chance;
    final figureText = formatPolyChanceFigure(shown);
    final full = l10n.betPercentChance(figureText);
    final figure = polyGaugeChanceParts(full, figureText).figure;
    final readout = l10n.polyPosIfReaches(widget.side);
    final smallStyle = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.2,
    );

    return LayoutBuilder(builder: (context, constraints) {
      final g = polySpeedometerGeometry(constraints.maxWidth);
      _geometry = g;
      final figureSize = (g.radius * 0.27).clamp(28.0, 48.0).toDouble();
      final figureStyle = TextStyle(
        color: c.textPrimary,
        fontSize: figureSize,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      final tp = TextPainter(
        text: TextSpan(text: readout, style: smallStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final smallH = tp.height;
      tp.dispose();
      // From the box's bottom: the chance's baseline just past the
      // needle's reach, the drag's line over it.
      final below = g.size.height - g.center.dy;
      final figureBottom = below + g.needle + _figureGap;
      final figureH = scaler.scale(figureSize) * 1.05;
      final readoutBottom = figureBottom + figureH + 2;
      final textWidth = g.radius * 1.1;
      final textLeft = g.center.dx - textWidth / 2;
      final duration = _reduceMotion
          ? Duration.zero
          : Duration(milliseconds: hypo != null ? 120 : 250);
      final semantics = entry == null
          ? full
          : '$full, ${l10n.polyPosSinceBoughtAt(formatPolyBoughtCents(entry))}';

      return Semantics(
        container: true,
        label: semantics,
        child: ExcludeSemantics(
          child: Listener(
            onPointerDown: (e) => _pan.addPointer(e),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              key: PolyPositionSpeedometer.dialKey,
              width: g.size.width,
              height: g.size.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      key: PolyPositionSpeedometer.dialPaintKey,
                      painter: PolySpeedometerDialPainter(
                        geometry: g,
                        entry: entry,
                        trackColor: c.border,
                        tickColor: c.textTertiary,
                        entryColor: c.textSecondary,
                        ringColor: c.background,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      key: PolyPositionSpeedometer.needlePaintKey,
                      painter: PolySpeedometerNeedlePainter(
                        geometry: g,
                        needle: _needle,
                        color: c.textPrimary,
                        ringColor: c.background,
                      ),
                    ),
                  ),
                  if (hypo != null)
                    Positioned(
                      key: PolyPositionSpeedometer.readoutKey,
                      left: textLeft,
                      width: textWidth,
                      bottom: readoutBottom,
                      height: smallH,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomCenter,
                        child: Text(readout,
                            style: smallStyle, maxLines: 1, softWrap: false),
                      ),
                    ),
                  Positioned(
                    key: PolyPositionSpeedometer.figureKey,
                    left: textLeft,
                    width: textWidth,
                    bottom: figureBottom,
                    height: figureH,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomCenter,
                      child: RollingNumberText(
                        text: figure,
                        style: figureStyle,
                        duration: duration,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// The still part of the dial: the thin track, the ticks at 0, 50 and
/// 100, the dot at the price paid.
class PolySpeedometerDialPainter extends CustomPainter {
  PolySpeedometerDialPainter({
    required this.geometry,
    required this.entry,
    required this.trackColor,
    required this.tickColor,
    required this.entryColor,
    required this.ringColor,
  });

  final PolySpeedometerGeometry geometry;

  /// The price paid (0 to 1); null without one.
  final double? entry;
  final Color trackColor;
  final Color tickColor;
  final Color entryColor;

  /// Around the entry dot: the screen's background, so it sits clear on
  /// the track.
  final Color ringColor;

  /// The three ticks, as fractions of the dial.
  static const ticks = [0.0, 0.5, 1.0];
  static const double tickLength = 6;

  /// Where the entry dot sits, in the dial's box; null without one.
  Offset? get entryDot {
    final e = entry;
    if (e == null) return null;
    final a = polyGaugeAngle(e);
    return geometry.center +
        Offset(math.cos(a), math.sin(a)) * geometry.radius;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    canvas.drawArc(
      Rect.fromCircle(center: g.center, radius: g.radius),
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = g.stroke
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true
        ..color = trackColor,
    );
    final tick = Paint()
      ..color = tickColor.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final inner = g.radius - g.stroke / 2 - 4;
    for (final f in ticks) {
      final a = polyGaugeAngle(f);
      final u = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
          g.center + u * inner, g.center + u * (inner - tickLength), tick);
    }
    final dot = entryDot;
    if (dot != null) {
      canvas.drawCircle(dot, kPolySpeedometerEntryDot + 1.5,
          Paint()..color = ringColor..isAntiAlias = true);
      canvas.drawCircle(dot, kPolySpeedometerEntryDot,
          Paint()..color = entryColor..isAntiAlias = true);
    }
  }

  @override
  bool shouldRepaint(PolySpeedometerDialPainter old) =>
      old.geometry != geometry ||
      old.entry != entry ||
      old.trackColor != trackColor ||
      old.tickColor != tickColor ||
      old.entryColor != entryColor ||
      old.ringColor != ringColor;
}

/// The needle, the hub and the grab knob at the tip, repainted on every
/// frame of the spring without rebuilding anything.
class PolySpeedometerNeedlePainter extends CustomPainter {
  PolySpeedometerNeedlePainter({
    required this.geometry,
    required this.needle,
    required this.color,
    required this.ringColor,
  }) : super(repaint: needle);

  final PolySpeedometerGeometry geometry;
  final ValueListenable<double> needle;
  final Color color;

  /// Between the knob and its ring: the screen's background, so the knob
  /// sits clear of the faint ring.
  final Color ringColor;

  static const double width = 2.5;

  /// Where the needle's tip (the knob's centre) is, in the dial's box.
  Offset get tip {
    final a = polyGaugeAngle(needle.value);
    return geometry.center +
        Offset(math.cos(a), math.sin(a)) * geometry.needle;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final t = tip;
    // The knob's faint ring: a soft disc of the needle's colour, its edge
    // a touch firmer.
    canvas.drawCircle(t, kPolySpeedometerKnobRing,
        Paint()..color = color.withValues(alpha: 0.07)..isAntiAlias = true);
    canvas.drawCircle(
        t,
        kPolySpeedometerKnobRing - 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.16)
          ..isAntiAlias = true);
    // A thin straight line from the hub's centre to the knob; then the
    // hub, a small solid disc, and the knob, a larger one with a hairline
    // of the background around it.
    canvas.drawLine(geometry.center, t, paint);
    canvas.drawCircle(geometry.center, kPolySpeedometerHub,
        Paint()..color = color..isAntiAlias = true);
    canvas.drawCircle(t, kPolySpeedometerKnob + 1.5,
        Paint()..color = ringColor..isAntiAlias = true);
    canvas.drawCircle(t, kPolySpeedometerKnob,
        Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(PolySpeedometerNeedlePainter old) =>
      old.geometry != geometry ||
      old.needle != needle ||
      old.color != color ||
      old.ringColor != ringColor;
}
