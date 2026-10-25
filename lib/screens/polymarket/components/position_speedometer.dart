// lib/screens/polymarket/components/position_speedometer.dart
//
// The open-position screen's speedometer: the held side's chance, 0 to
// 100%, on a 180° dial, for a Predictions bet that is still open (a live
// price, not settled). A settled position keeps the chance bar
// (position_chance_bar.dart).
//
// What it draws, the same for every market (Yes / No, Up / Down, a
// candidate, a team):
//   * a thin track, tinted soft green above the price paid and soft red
//     below it (the app's up / down colours at a low alpha); neutral when
//     the price paid is unknown. No outcome colours on the dial;
//   * ticks every 5% (longer every 10%) inside the track, the figures
//     0 / 25 / 50 / 75 / 100 inside those, in the tertiary text colour;
//   * a short bold tick across the track at the price paid, "You · 19%"
//     beside it, just outside the arc (polyChanceGaugeGeometry places it);
//   * a needle from the centre hub, both in the primary text colour, the
//     hub with an inner dot;
//   * the live chance, large, above the hub, "chance · live" under it,
//     on a plate of the screen's background over the needle, so the
//     needle passes behind the figures.
//
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
// centre reads "If No reaches" over that chance, a selection tick every
// 5% crossed (at most one per [kPolyNeedleTickGap]); [onExploreStart] / [onExplore] / [onExploreEnd] let the
// screen show what the position would be worth. On release the needle
// springs back to the live chance. Nothing here is logged; the screen
// logs the what-if once it is over.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, visibleForTesting;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
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

/// The track's zones, from the left: soft red below the price paid, soft
/// green above it (the app's down and up colours at a low alpha). One
/// neutral zone when the price paid is unknown.
List<({double from, double to, Color color})> polySpeedometerZones({
  required double? entry,
  required Color neutral,
  required bool dark,
}) {
  final alpha = dark ? 0.42 : 0.34;
  final e = entry;
  if (e == null || !(e > 0) || e >= 1) {
    return [(from: 0.0, to: 1.0, color: neutral)];
  }
  return [
    (from: 0.0, to: e, color: AppColors.marketDown.withValues(alpha: alpha)),
    (from: e, to: 1.0, color: AppColors.marketUp.withValues(alpha: alpha)),
  ];
}

/// Where everything of the dial sits, in the dial's own box.
typedef PolyChanceGaugeGeometry = ({
  Size size,
  Offset center,

  /// The track's centre line.
  double radius,
  double stroke,

  /// The entry tick's two ends, from the centre.
  double tickInner,
  double tickOuter,

  /// The entry tick's angle (canvas radians); null without one.
  double? tickAngle,

  /// The "You · 19%" tag; null without a tick or a tag.
  Rect? labelRect,
});

/// How high (sin of the angle) a tick still counts as at an end of the
/// arc: the first and last 10% of it.
final double _endBand = math.sin(math.pi * 0.1) + 1e-9;

/// Lays the dial out across [width]: a track of [outerRadius] and
/// [stroke], centred; the entry tick ([tick], 0 to 1 from the left)
/// running [overhang] past both edges of the track; the tag of [tag] size
/// pushed out from the tick's outer end by [gap], along the tick; and
/// [belowCenter] of room under the centre line (the hub). The box is as
/// tall as all of that, and no taller.
PolyChanceGaugeGeometry polyChanceGaugeGeometry({
  required double width,
  required double outerRadius,
  required double stroke,
  double overhang = 3,
  double gap = 2,
  double belowCenter = 0,
  double? tick,
  Size? tag,
}) {
  final radius = outerRadius - stroke / 2;
  final tickOuter = outerRadius + overhang;
  final tickInner = math.max(0.0, outerRadius - stroke - overhang);
  final tickAngle = tick == null ? null : polyGaugeAngle(tick);

  // Laid out about the centre first, then moved into the box.
  var top = -(tick == null ? outerRadius : tickOuter);
  var bottom = math.max(stroke / 2, belowCenter);
  Rect? label;
  if (tickAngle != null && tag != null) {
    final u = Offset(math.cos(tickAngle), math.sin(tickAngle));
    // The tag's nearest side touches a point just past the tick's end,
    // straight out from the centre: clear of the arc and the tick.
    final reach = tickOuter + gap;
    final push = tag.width / 2 * u.dx.abs() + tag.height / 2 * u.dy.abs();
    var c = u * (reach + push);
    final lowest = bottom - tag.height / 2;
    if (c.dy > lowest) c = Offset(c.dx, lowest);
    final half = width / 2;
    final minX = -half + tag.width / 2;
    final maxX = math.max(minX, half - tag.width / 2);
    var dx = c.dx.clamp(minX, maxX).toDouble();
    var dy = c.dy;
    if ((dx - c.dx).abs() > 0.5) {
      if (u.dy.abs() <= _endBand) {
        // Near an end: under the arc's end, just below the hub's line.
        dx = (u.dx.sign * radius).clamp(minX, maxX).toDouble();
        dy = math.max(stroke / 2, belowCenter) + gap + tag.height / 2;
      } else {
        // Higher up: lifted only as far as clears the arc and the tick.
        final near = math.max(0.0, dx.abs() - tag.width / 2);
        final clear =
            near >= reach ? 0.0 : math.sqrt(reach * reach - near * near);
        dy = math.min(dy, -(clear + tag.height / 2));
      }
    }
    label = Rect.fromCenter(
        center: Offset(dx, dy), width: tag.width, height: tag.height);
    top = math.min(top, label.top);
    bottom = math.max(bottom, label.bottom);
  }
  final center = Offset(width / 2, -top);
  return (
    size: Size(width, bottom - top),
    center: center,
    radius: radius,
    stroke: stroke,
    tickInner: tickInner,
    tickOuter: tickOuter,
    tickAngle: tickAngle,
    labelRect: label?.shift(center),
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

  _NeedleMode _mode = _NeedleMode.live;
  bool _reduceMotion = false;
  bool _started = false;
  Animation<double>? _routeAnimation;

  /// The hypothetical chance while dragging.
  double? _hypo;

  /// Where the dial sits, for the drag's angle.
  PolyChanceGaugeGeometry? _geometry;
  late final _DialPanRecognizer _pan;

  /// The needle's position (0..1), for tests.
  @visibleForTesting
  double get debugNeedle => _motion.position;

  @visibleForTesting
  double get debugNeedleVelocity => _motion.velocity;

  @visibleForTesting
  bool get debugSweeping => _mode == _NeedleMode.sweep;

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
    if (_mode == _NeedleMode.sweep || _mode == _NeedleMode.returning) {
      _mode = _NeedleMode.live;
    }
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

  static const double _overhang = 5;
  static const double _platePad = 2;
  static const double _gap = 4;

  static TextStyle _tagStyle(Color color) => TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final dark = context.isDark;
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final entry = widget.entry != null &&
            widget.entry! > 0 &&
            widget.entry! < 1
        ? widget.entry
        : null;
    final label =
        entry == null ? null : l10n.polyPosYouAt(formatPolyChanceFigure(entry));
    final labelStyle = _tagStyle(c.textSecondary);

    final hypo = _hypo;
    final shown = hypo ?? widget.chance;
    final figureText = formatPolyChanceFigure(shown);
    final full = l10n.betPercentChance(figureText);
    final figure = polyGaugeChanceParts(full, figureText).figure;
    final caption = l10n.polyPosChanceLive;
    final readout = l10n.polyPosIfReaches(widget.side);
    final smallStyle = TextStyle(
      color: c.textTertiary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.2,
    );
    // The readout sits on a plate of the screen's own background, over
    // the needle: the needle passes behind the figures, never through
    // them.
    Widget plate(Widget child) => DecoratedBox(
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: _platePad),
            child: child,
          ),
        );

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      Size? tag;
      if (label != null) {
        final tp = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout(maxWidth: w);
        tag = Size(math.min(w, tp.width + 4), tp.height + 2);
        tp.dispose();
      }
      final double outerRadius =
          (w / 2 - _overhang).clamp(math.min(60.0, w / 4), 190.0).toDouble();
      final stroke = (outerRadius * 0.05).clamp(6.0, 10.0).toDouble();
      final hub = (outerRadius * 0.055).clamp(7.0, 11.0).toDouble();
      final g = polyChanceGaugeGeometry(
        width: w,
        outerRadius: outerRadius,
        stroke: stroke,
        overhang: _overhang,
        gap: _gap,
        belowCenter: hub + 2,
        tick: entry,
        tag: tag,
      );
      _geometry = g;
      final inner = g.radius - stroke / 2;
      final figureSize = (outerRadius * 0.28).clamp(28.0, 50.0).toDouble();
      final figureStyle = TextStyle(
        color: c.textPrimary,
        fontSize: figureSize,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      final tp = TextPainter(
        text: TextSpan(text: caption, style: smallStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final smallH = tp.height;
      tp.dispose();
      // From the box's bottom: the caption just above the hub, the chance
      // on it, the drag's readout over the chance.
      // Each line's box carries its plate's padding ([_platePad] above
      // and below); the figure's plate overlaps the caption's, so the
      // needle never shows between them.
      final below = g.size.height - g.center.dy;
      final captionBottom = below + hub + 6;
      final captionH = smallH + 2 * _platePad;
      final figureBottom = captionBottom + captionH - 3;
      final figureH = scaler.scale(figureSize) * 1.05 + 2 * _platePad;
      final readoutBottom = figureBottom + figureH - 3;
      final textLeft = g.center.dx - inner * 0.6;
      final textWidth = inner * 1.2;
      final labelRect = g.labelRect;
      final semantics = label == null ? full : '$full, $label';
      final duration = _reduceMotion
          ? Duration.zero
          : Duration(milliseconds: hypo != null ? 120 : 250);

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
                        zones: polySpeedometerZones(
                            entry: entry, neutral: c.border, dark: dark),
                        tickColor: c.textTertiary,
                        entryColor: c.textPrimary,
                        // The app's own type (a painter inherits none).
                        labelStyle: DefaultTextStyle.of(context).style.merge(
                              TextStyle(
                                color: c.textTertiary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                height: 1.0,
                                decoration: TextDecoration.none,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                        textScaler: scaler,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      key: PolyPositionSpeedometer.needlePaintKey,
                      painter: PolySpeedometerNeedlePainter(
                        geometry: g,
                        needle: _needle,
                        hubRadius: hub,
                        color: c.textPrimary,
                        dot: dark ? c.background : c.surface,
                      ),
                    ),
                  ),
                  if (hypo != null)
                    Positioned(
                      key: PolyPositionSpeedometer.readoutKey,
                      left: textLeft,
                      width: textWidth,
                      bottom: readoutBottom,
                      height: captionH,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomCenter,
                        child: plate(Text(readout,
                            style: smallStyle.copyWith(color: c.textSecondary),
                            maxLines: 1,
                            softWrap: false)),
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
                      child: plate(RollingNumberText(
                        text: figure,
                        style: figureStyle,
                        duration: duration,
                      )),
                    ),
                  ),
                  if (hypo == null)
                    Positioned(
                      key: PolyPositionSpeedometer.captionKey,
                      left: textLeft,
                      width: textWidth,
                      bottom: captionBottom,
                      height: captionH,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomCenter,
                        child: plate(Text(caption,
                            style: smallStyle, maxLines: 1, softWrap: false)),
                      ),
                    ),
                  if (labelRect != null)
                    Positioned.fromRect(
                      key: PolyPositionSpeedometer.entryLabelKey,
                      rect: labelRect,
                      child: Center(
                        child: Text(
                          label!,
                          style: labelStyle,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
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

/// The still part of the dial: the tinted track, the ticks and their
/// figures, the bold tick at the price paid.
class PolySpeedometerDialPainter extends CustomPainter {
  PolySpeedometerDialPainter({
    required this.geometry,
    required this.zones,
    required this.tickColor,
    required this.entryColor,
    required this.labelStyle,
    required this.textScaler,
  });

  final PolyChanceGaugeGeometry geometry;
  final List<({double from, double to, Color color})> zones;
  final Color tickColor;
  final Color entryColor;
  final TextStyle labelStyle;
  final TextScaler textScaler;

  /// Where the 5% ticks start inside the track, and how long a 5% and a
  /// 10% tick are.
  static const double tickInset = 4;
  static const double minorLength = 6;
  static const double majorLength = 11;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final rect = Rect.fromCircle(center: g.center, radius: g.radius);
    for (var i = 0; i < zones.length; i++) {
      final z = zones[i];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = g.stroke
        // Round at the dial's two ends only; zones meet flat (the entry
        // tick sits on the seam).
        ..strokeCap = StrokeCap.butt
        ..isAntiAlias = true
        ..color = z.color;
      final start = polyGaugeAngle(z.from);
      final sweep = (z.to - z.from) * math.pi;
      if (sweep <= 0) continue;
      canvas.drawArc(rect, start, sweep, false, paint);
      // The round caps at the ends of the dial.
      final capPaint = Paint()
        ..color = z.color
        ..isAntiAlias = true;
      if (z.from <= 0) {
        canvas.drawArc(
            Rect.fromCircle(
                center: g.center + Offset(-g.radius, 0), radius: g.stroke / 2),
            0,
            math.pi,
            true,
            capPaint);
      }
      if (z.to >= 1) {
        canvas.drawArc(
            Rect.fromCircle(
                center: g.center + Offset(g.radius, 0), radius: g.stroke / 2),
            0,
            math.pi,
            true,
            capPaint);
      }
    }

    // Ticks every 5%, longer every 10%, inside the track.
    final inner = g.radius - g.stroke / 2 - tickInset;
    final minor = Paint()
      ..color = tickColor.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final major = Paint()
      ..color = tickColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (var i = 0; i <= 20; i++) {
      final a = polyGaugeAngle(i / 20);
      final u = Offset(math.cos(a), math.sin(a));
      final isMajor = i.isEven;
      final len = isMajor ? majorLength : minorLength;
      canvas.drawLine(g.center + u * inner, g.center + u * (inner - len),
          isMajor ? major : minor);
    }

    // 0 / 25 / 50 / 75 / 100, inside the ticks.
    final labelRadius = inner - majorLength - 5;
    for (final v in const [0, 25, 50, 75, 100]) {
      final tp = TextPainter(
        text: TextSpan(text: '$v', style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final a = polyGaugeAngle(v / 100);
      final u = Offset(math.cos(a), math.sin(a));
      // Pushed in from the label circle by its own half extent along the
      // radius, so every figure sits the same gap inside the ticks; at
      // the ends, its bottom on the hub's line.
      final push = tp.width / 2 * u.dx.abs() + tp.height / 2 * u.dy.abs();
      var c = g.center + u * (labelRadius - push);
      final maxY = g.center.dy - tp.height / 2;
      if (c.dy > maxY) c = Offset(c.dx, maxY);
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      tp.dispose();
    }

    // The price paid: a short bold tick across the track.
    final a = g.tickAngle;
    if (a != null) {
      final u = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        g.center + u * g.tickInner,
        g.center + u * g.tickOuter,
        Paint()
          ..color = entryColor
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(PolySpeedometerDialPainter old) =>
      old.geometry != geometry ||
      !_sameZones(old.zones, zones) ||
      old.tickColor != tickColor ||
      old.entryColor != entryColor ||
      old.labelStyle != labelStyle ||
      old.textScaler != textScaler;

  static bool _sameZones(List<({double from, double to, Color color})> a,
      List<({double from, double to, Color color})> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The needle and the hub, repainted on every frame of the spring
/// without rebuilding anything.
class PolySpeedometerNeedlePainter extends CustomPainter {
  PolySpeedometerNeedlePainter({
    required this.geometry,
    required this.needle,
    required this.hubRadius,
    required this.color,
    required this.dot,
  }) : super(repaint: needle);

  final PolyChanceGaugeGeometry geometry;
  final ValueListenable<double> needle;
  final double hubRadius;
  final Color color;

  /// The hub's inner dot: the screen's own surface.
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final a = polyGaugeAngle(needle.value);
    final u = Offset(math.cos(a), math.sin(a));
    final n = Offset(-u.dy, u.dx);
    // Tip just inside the ticks; a short tail behind the hub.
    final tipR = g.radius - g.stroke / 2 - 2;
    final tail = hubRadius * 1.6;
    final base = hubRadius * 0.42;
    final tip = g.center + u * tipR;
    final back = g.center - u * tail;
    final path = Path()
      ..moveTo(back.dx + n.dx * base * 0.8, back.dy + n.dy * base * 0.8)
      ..lineTo(tip.dx + n.dx * 0.9, tip.dy + n.dy * 0.9)
      ..lineTo(tip.dx - n.dx * 0.9, tip.dy - n.dy * 0.9)
      ..lineTo(back.dx - n.dx * base * 0.8, back.dy - n.dy * base * 0.8)
      ..close();
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);
    canvas.drawCircle(g.center, hubRadius, paint);
    canvas.drawCircle(
        g.center,
        hubRadius * 0.38,
        Paint()
          ..color = dot
          ..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(PolySpeedometerNeedlePainter old) =>
      old.geometry != geometry ||
      old.needle != needle ||
      old.hubRadius != hubRadius ||
      old.color != color ||
      old.dot != dot;
}
