// lib/screens/shared/money_steps_view.dart
//
// The ONE widget that shows a money step graph ([MoneyStepGraph]) under a
// slip's or a sheet's button, and in an Activity detail: the MONEY
// JOURNEY (founder, 19 October 2026: "make sure we have Sal; make it fun
// and engaging"). A small map: the balances the money leaves are round
// STATIONS on the left (their own marks: ₿, $, Investing, Predictions),
// the balance it goes to is the station on the right, the places it
// passes through sit in between, and a winding ROAD joins each pair. Sal,
// the mascot, runs the biggest leg's road carrying a coin, hops as he
// lands, and waits at the destination waving the other legs' coins in
// (each on its own road, in its balance's colour); the road lights up
// gold behind every runner, the station ahead pulses while its step
// works, and a finished station turns gold with a pop and a burst. A leg
// with sub-legs (Investing → Bitcoin by HyperCore → Circle → Arbitrum →
// Bitcoin) has a WAYPOINT per sub-leg on its road, named, pulsing while
// that sub-leg runs, gold once done, its amount beside it once it
// changed. The destination's own sub-steps (Approving spend, Confirming
// balance, Placing $12 on Yes) are CHECKPOINTS listed under the map in
// the steps' tree look, each pulsing while it runs and turning gold with
// a check; the destination wears a "2/3" chip while they run. On top:
// the amount counting up, a status line in plain words naming the
// sub-phase at work ("Circle → Arbitrum", "Confirming balance"), and a
// thin progress bar with its percent (money arrived is about 60%, the
// order placed 100%). Success: Sal drops the coin into the last station,
// confetti rains over the map, Sal cheers; a stop: the station turns red
// and shakes, Sal sits down sad, and the surface's own line says where
// the money is. Sal is always there and always doing something (idling,
// sniffing, cheering, sulking), and a tap on him makes him jump. Every
// word a screen reader needs (each leg's line, each sub-leg's, each
// checkpoint's) is a real semantics node, in the final words.
//
// A record whose steps have all ended (an Activity detail) draws its
// final state, all gold with Sal sitting at the destination, and replays
// the journey once, quickly (~1.2 s), when the detail opens; never with
// haptics. The haptics for live changes are the ones every steps surface
// had: a selection click as Sal lands, a light tap as a step completes,
// the money-success beat at the end, the failure tap on a stop, only for
// changes seen live and deduped with the surface. Reduce Motion: the
// same states at once, no run, hop, burst, confetti or replay; the
// haptics still play.

import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/kute_state.dart';
import 'package:kute/screens/shared/kute_dog_rig.dart';
import 'package:kute/screens/shared/kute_mascot.dart' show kuteMascotPose;
import 'package:kute/screens/shared/kute_motion.dart' show kuteReduceMotion;
import 'package:kute/screens/shared/money_journey_plan.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/success_feedback.dart'
    show moneyFailureFeedback, moneyStepsSuccessFeedback;
import 'package:kute/theme/app_theme.dart';

export 'package:kute/screens/shared/money_journey_plan.dart'
    show MoneyStepLine, MoneyJourneyPlan, JourneyRoad, JourneyStation;

/// The balance's own name, as the portfolio names it.
String moneyPlaceName(AppLocalizations l10n, MoneyPlace place) =>
    switch (place) {
      MoneyPlace.bitcoin => l10n.bitcoin,
      MoneyPlace.dollars => l10n.portfolioBalanceDollars,
      MoneyPlace.predictions => l10n.predictions,
      MoneyPlace.investing => l10n.trading,
    };

/// The words of one step in its current state. [money] formats dollars
/// the screen's way; [placeLine] is the order's own line ("Placing $15 on
/// Yes"), which the slip words.
String moneyStepLine(
  AppLocalizations l10n,
  MoneyStep s,
  String Function(double usd) money, {
  String? placeLine,
}) {
  final done = s.status == MoneyStepStatus.done;
  switch (s.kind) {
    case MoneyStepKind.leg:
      final from = moneyPlaceName(l10n, s.from ?? MoneyPlace.dollars);
      if (s.status == MoneyStepStatus.fellBack) {
        // The real reason, never "busy" unless the refusal was transient.
        final via = l10n.portfolioBalanceDollars;
        return switch (MoneyFallBack.of(s.reason)) {
          MoneyFallBack.busy => l10n.moneyStepFellBack(from, via),
          MoneyFallBack.unavailable =>
            l10n.moneyStepRouteUnavailable(from, via),
          MoneyFallBack.tooSmall => l10n.moneyStepTooSmallDirect(from, via),
          MoneyFallBack.neutral => l10n.moneyStepViaDollars(from, via),
        };
      }
      if (s.status == MoneyStepStatus.failed) {
        return l10n.moneyStepMoveFailed(money(s.usd), from);
      }
      final to = s.to;
      if (to != null) {
        final dest = moneyPlaceName(l10n, to);
        return done
            ? l10n.moneyStepMovedFromTo(money(s.usd), from, dest)
            : l10n.moneyStepMovingFromTo(money(s.usd), from, dest);
      }
      return done
          ? l10n.moneyStepMovedFrom(money(s.usd), from)
          : l10n.moneyStepMovingFrom(money(s.usd), from);
    case MoneyStepKind.convert:
      return done ? l10n.moneyStepConverted : l10n.moneyStepConverting;
    case MoneyStepKind.approve:
      return done ? l10n.moneyStepApproved : l10n.moneyStepApproving;
    case MoneyStepKind.confirm:
      return done ? l10n.moneyStepConfirmed : l10n.moneyStepConfirming;
    case MoneyStepKind.credit:
      return done ? l10n.moneyStepCredited : l10n.moneyStepCrediting;
    case MoneyStepKind.buy:
      return done
          ? l10n.moneyStepBought(money(s.usd))
          : l10n.moneyStepBuying(money(s.usd));
    case MoneyStepKind.arrive:
      return done ? l10n.moneyStepArrived : l10n.moneyStepArriving;
    case MoneyStepKind.place:
      return placeLine ?? '';
  }
}

/// Whether a step is shown: a skipped one never is, and the conversion
/// and the allowance (needed only sometimes) only once the venue really
/// reported them (`ref: 'seen'`, `readinessPhaseStep`). Their steps start
/// with nothing to wait on, so "running" alone does not mean they are
/// needed: shown from the start, "Approving spend" spun under every bet,
/// even one whose allowance was long set.
bool moneyStepShown(MoneyStep s) {
  if (s.status == MoneyStepStatus.skipped) return false;
  if (s.kind == MoneyStepKind.convert || s.kind == MoneyStepKind.approve) {
    if (s.status == MoneyStepStatus.waiting) return false;
    if (s.status == MoneyStepStatus.running && s.ref != 'seen') return false;
  }
  return true;
}

/// The lines [graph] shows, in order: the legs, the readiness stage with
/// its sub-steps under [readyLabel], then the rest (the order, the
/// purchase, the arrival). Pure, so the order of lines is tested apart.
List<MoneyStepLine> moneyStepLines(
  AppLocalizations l10n,
  MoneyStepGraph graph,
  String Function(double usd) money, {
  String? readyLabel,
  String? placeLine,
}) {
  final lines = <MoneyStepLine>[];
  final readiness = graph.steps.where((s) => s.kind.readiness).toList();
  var readyShown = false;
  for (final s in graph.steps) {
    if (s.kind.readiness) {
      if (readyShown) continue;
      readyShown = true;
      // The stage reads what it shows: an allowance step that started but
      // was never needed does not spin it.
      final stage = stageStatusOf(readiness.where(moneyStepShown));
      if (stage == null) continue;
      if (readyLabel != null) {
        lines.add(MoneyStepLine(readyLabel, stage, id: 'ready'));
      }
      for (final r in readiness) {
        if (!moneyStepShown(r)) continue;
        lines.add(MoneyStepLine(moneyStepLine(l10n, r, money), r.status,
            sub: readyLabel != null, id: r.id));
      }
      continue;
    }
    if (!moneyStepShown(s)) continue;
    lines.add(MoneyStepLine(
        moneyStepLine(l10n, s, money, placeLine: placeLine), s.status,
        id: s.id));
  }
  return lines;
}

/// Which keys a [MoneyStepsView] gives its parts: its own, or those of the
/// slips' older stage lines ([MoneyStepsKeys.slip], `SlipFundingSteps`
/// without a graph), so every steps surface draws the one journey and
/// each still answers to its own names.
@immutable
class MoneyStepsKeys {
  const MoneyStepsKeys._(
      this.container, this.step, this.runningWord, this.slow, this.note);

  /// The whole view.
  final String container;

  /// Prefix of a line (`<step><id or index>`) and of its sign
  /// (`<step><state>-<index>`).
  final String step;

  /// The running sign's state word.
  final String runningWord;
  final String slow;
  final String note;

  static const MoneyStepsKeys money = MoneyStepsKeys._('money-steps',
      'money-step-', 'running', 'money-steps-slow', 'money-steps-note');
  static const MoneyStepsKeys slip = MoneyStepsKeys._('slip-funding-steps',
      'slip-funding-step-', 'active', 'slip-funding-slow', 'slip-funding-note');
}

/// The journey (see the file header) of [lines], laid out from [graph]
/// when the surface has it ([MoneyJourneyPlan.of]). [from] and [to] name
/// the stations when the graph does not (the slips' older stage lines);
/// [toLabel] names an outside destination (where a send went); [money]
/// formats the amount on top. [note] is the one plain line under the
/// checkpoints once something stopped (what happened and where the money
/// is); [slow] adds "Taking longer than usual".
///
/// [haptics] false leaves the feel to the surface (a band that already
/// plays each landing); [failureHaptic] false leaves the failure tap to a
/// caller that plays it for the same stop.
class MoneyStepsView extends StatefulWidget {
  const MoneyStepsView({
    super.key,
    required this.lines,
    this.graph,
    this.from,
    this.to,
    this.toLabel,
    this.money,
    this.slow = false,
    this.note,
    this.haptics = true,
    this.failureHaptic = true,
    this.keys = MoneyStepsKeys.money,
  });

  final List<MoneyStepLine> lines;
  final MoneyStepGraph? graph;
  final MoneyPlace? from;
  final MoneyPlace? to;
  final String? toLabel;
  final String Function(double usd)? money;
  final bool slow;
  final String? note;
  final bool haptics;
  final bool failureHaptic;
  final MoneyStepsKeys keys;

  @override
  State<MoneyStepsView> createState() => _MoneyStepsViewState();
}

// The choreography's beats, in milliseconds.
const double _kPopDelay = 120; // a finished step's ring closes, then pops
const double _kPop = 320;
const double _kCheckDelay = 60;
const double _kCheckDraw = 220;
const double _kBurst = 420;
const double _kFinalBurst = 560;
const double _kDash = 350; // the runner's last stretch into the station
const double _kApproach = 1600; // the runner's way out while a leg works
const double _kHold = 0.72; // how far along he gets before it lands
const double _kHop = 300;
const double _kRingDraw = 500;
const double _kCountUp = 700;
const double _kShake = 300;
const double _kFadeIn = 200;
const double _kDim = 250;
const double _kConfetti = 1400;
const double _kCheer = 2700;
const double _kCoinDrop = 400;
const double _kWave = 760;
const double _kReplay = 1200;
const double _kBar = 500;
const double _kPing = 1100;
const double _kDimAlpha = 0.5;
// How long Sal keeps idling after the last moment before the clock
// rests (two idle loops); it runs on while any step runs.
const double _kIdleFor = 2.0 * kKuteDogIdleMs;

enum _Outcome { none, success, failure }

enum _Haptic { arrive, check, success, failure, tap }

/// One line's live moments (clock milliseconds), by line key.
class _Fx {
  _Fx(this.status);
  MoneyStepStatus status;
  double? runSince;
  double? doneAt;
  double? failedAt;

  /// How far its segment was lit when it ended (the runner dashes on
  /// from there).
  double litFrom = 0;
  double dashMs = _kDash;
  bool finalDone = false;
}

/// The view's look, in the screen's units and the surface's colours.
@immutable
class _Look {
  const _Look({
    required this.quiet,
    required this.done,
    required this.failed,
    required this.gold,
    required this.ping,
    required this.surface,
    required this.border,
    required this.success,
    required this.stationR,
    required this.waypointR,
    required this.coinR,
    required this.roadW,
    required this.salSize,
    required this.signR,
    required this.shake,
    required this.padX,
    required this.amountStyle,
    required this.direction,
  });

  final Color quiet;
  final Color done;
  final Color failed;
  final Color gold;
  final Color ping;
  final Color surface;
  final Color border;
  final Color success;
  final double stationR;
  final double waypointR;
  final double coinR;
  final double roadW;
  final double salSize;
  final double signR;
  final double shake;
  final double padX;
  final TextStyle amountStyle;
  final TextDirection direction;
}

/// Where everything sits on the map, for one size.
class _Geometry {
  _Geometry(
      this.size, this.stations, this.roads, this.metrics, this.waypoints);
  final Size size;
  final List<Offset> stations;
  final List<Path> roads;
  final List<PathMetric?> metrics;
  final List<List<Offset>> waypoints;

  static _Geometry of(MoneyJourneyPlan plan, Size size, _Look look) {
    final w = size.width;
    final h = size.height;
    final cols = math.max(1, plan.columns);
    final stations = <Offset>[
      for (final s in plan.stations)
        Offset(
          cols == 1
              ? w / 2
              : look.padX + s.column * (w - 2 * look.padX) / (cols - 1),
          s.rows == 1 ? h / 2 : h * (s.row + 1) / (s.rows + 1),
        ),
    ];
    final roads = <Path>[];
    final metrics = <PathMetric?>[];
    final waypoints = <List<Offset>>[];
    for (var i = 0; i < plan.roads.length; i++) {
      final r = plan.roads[i];
      final a = stations[r.from];
      final b = stations[r.to];
      final dx = b.dx - a.dx;
      // A gentle S on a level road, so it winds; a sweep otherwise.
      final wiggle = (b.dy - a.dy).abs() < 1
          ? (i.isEven ? 1 : -1) * math.min(12.0, h * 0.08)
          : 0.0;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx + dx * 0.45, a.dy + wiggle, b.dx - dx * 0.45,
            b.dy - wiggle, b.dx, b.dy);
      roads.add(path);
      final m = path.computeMetrics().firstOrNull;
      metrics.add(m);
      final n = r.segments.length;
      waypoints.add([
        for (var k = 0; k + 1 < n; k++)
          m?.getTangentForOffset(m.length * (k + 1) / n)?.position ??
              Offset.lerp(a, b, (k + 1) / n)!,
      ]);
    }
    return _Geometry(size, stations, roads, metrics, waypoints);
  }

  Offset along(int road, double t) {
    final m = metrics[road];
    if (m == null) return stations[road];
    return m.getTangentForOffset(m.length * _unit(t))?.position ??
        stations[road];
  }
}

/// What the painters read: the plan, every line's moments, Sal's, and
/// the outcome. Never rebuilt per frame.
class _Scene {
  MoneyJourneyPlan plan = const MoneyJourneyPlan(
      lines: [],
      stations: [],
      roads: [],
      checkpoints: [],
      chain: [],
      destination: null,
      columns: 0,
      totalUsd: null,
      headline: null,
      hasGraph: false,
      placeLine: null);
  final Map<String, _Fx> fx = {};
  List<String> keys = const [];
  bool live = false;
  bool still = false;
  late _Look look;
  _Geometry? geo;

  _Outcome outcome = _Outcome.none;
  double outcomeAt = 0;
  double? replayAt;
  double salEnterAt = 0;
  double? hopAt;
  double? jumpAt;
  double? waveAt;
  double? countFrom;
  Offset? lastSal;
  int spot = 0;

  /// The last moment anything happened: Sal's idle runs from it, and the
  /// clock rests [_kIdleFor] after it unless a step runs.
  double quietSince = 0;

  double barFrom = 0;
  double barTo = 0;
  double barAt = 0;
}

String _lineKey(MoneyStepLine l, int i) => l.id ?? '#$i';

/// The clock: seconds since the view first ticked, carried on across
/// pauses.
class _ClockSimulation extends Simulation {
  _ClockSimulation(this.start);
  final double start;
  @override
  double x(double time) => start + time;
  @override
  double dx(double time) => 1;
  @override
  bool isDone(double time) => false;
}

class _MoneyStepsViewState extends State<MoneyStepsView>
    with SingleTickerProviderStateMixin {
  // The view's one controller: a clock every moment is timed against.
  late final AnimationController _clock =
      AnimationController.unbounded(vsync: this)..addListener(_onTick);
  final _Scene _scene = _Scene();
  final List<(double, _Haptic)> _events = [];
  double _busyUntil = 0;

  double get _now => _clock.value * 1000;

  bool _needsTick(double now) =>
      !_scene.still &&
      (_events.isNotEmpty ||
          now < _busyUntil ||
          _scene.plan.lines.any((l) => l.status == MoneyStepStatus.running));

  /// Something happened now: Sal has [_kIdleFor] of life from here.
  void _moment(double now) {
    _scene.quietSince = now;
    _busyUntil = math.max(_busyUntil, now + _kIdleFor);
  }

  @override
  void initState() {
    super.initState();
    _sync(first: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = kuteReduceMotion(context);
    if (still != _scene.still) {
      _scene.still = still;
      if (still) _scene.replayAt = null;
    }
    _kick();
  }

  @override
  void didUpdateWidget(MoneyStepsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(first: false);
    _kick();
  }

  @override
  void dispose() {
    _events.clear();
    _clock.dispose();
    super.dispose();
  }

  /// Runs the clock while something moves (Sal keeps idling a while after
  /// the last moment, and all along while a step runs); under Reduce
  /// Motion (or with tickers off) plays the pending haptics once this
  /// frame is drawn instead.
  void _kick() {
    final ticking = TickerMode.valuesOf(context).enabled;
    if (_scene.still || !ticking) {
      if (_clock.isAnimating) _clock.stop();
      if (_events.isEmpty) return;
      if (!ticking) {
        _events.clear();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _flush(_now, all: true);
      });
      return;
    }
    if (!_clock.isAnimating && _needsTick(_now)) {
      _clock.animateWith(_ClockSimulation(_clock.value));
    }
  }

  void _onTick() {
    final now = _now;
    _flush(now);
    if (!_needsTick(now)) _clock.stop();
  }

  void _schedule(double at, _Haptic h) => _events.add((at, h));

  /// Plays the haptics due by [now], one of each kind; a beat left behind
  /// while the view's tickers were off is dropped, not played late.
  void _flush(double now, {bool all = false}) {
    if (_events.isEmpty) return;
    final due = [
      for (final e in _events)
        if (all || e.$1 <= now) e
    ];
    if (due.isEmpty) return;
    _events.removeWhere(due.contains);
    final kinds = <_Haptic>{
      for (final e in due)
        if (all || now - e.$1 <= 1000) e.$2
    };
    for (final h in kinds) {
      _fire(h);
    }
  }

  void _fire(_Haptic h) {
    if (!widget.haptics && h != _Haptic.tap) return;
    try {
      switch (h) {
        case _Haptic.arrive || _Haptic.tap:
          if (KuteHaptics.isForeground) {
            unawaited(HapticFeedback.selectionClick());
          }
        case _Haptic.check:
          if (KuteHaptics.isForeground) {
            unawaited(HapticFeedback.lightImpact());
          }
        case _Haptic.success:
          if (KuteHaptics.isForeground) moneyStepsSuccessFeedback();
        case _Haptic.failure:
          if (widget.failureHaptic) unawaited(moneyFailureFeedback());
      }
    } catch (_) {
      // Haptics are best-effort.
    }
  }

  MoneyJourneyPlan _plan() => MoneyJourneyPlan.of(widget.lines,
      graph: widget.graph,
      from: widget.from,
      to: widget.to,
      toLabel: widget.toLabel,
      money: widget.money);

  /// Where Sal is along his chain at [now]: the index of the chain road
  /// he rides, or the chain's length once he reached its end.
  static int _spotOf(_Scene s, double now) {
    final chain = s.plan.chain;
    for (var i = 0; i < chain.length; i++) {
      if (_roadLit(s, s.plan.roads[chain[i]], now) < 1) return i;
    }
    return chain.length;
  }

  /// The journey's progress: money arrived weighs ~60% once there are
  /// checkpoints, the checkpoints the rest.
  static double _progressOf(_Scene s) {
    final plan = s.plan;
    double part(Iterable<int> lines) {
      var n = 0;
      var sum = 0.0;
      for (final i in lines) {
        n++;
        sum += switch (plan.lines[i].status) {
          MoneyStepStatus.done || MoneyStepStatus.skipped => 1.0,
          MoneyStepStatus.running => 0.5,
          _ => 0.0,
        };
      }
      return n == 0 ? 1 : sum / n;
    }

    final roads = [
      for (final r in plan.roads)
        if (r.line >= 0) ...r.segments
    ];
    final checks = plan.checkpoints;
    if (roads.isEmpty) return checks.isEmpty ? 0 : part(checks);
    if (checks.isEmpty) return part(roads);
    return 0.6 * part(roads) + 0.4 * part(checks);
  }

  /// Brings the scene up to [widget.lines]: records each live change's
  /// moment and schedules its haptic. The first build only records where
  /// things stand (and, for a record already ended, sets up the replay).
  void _sync({required bool first}) {
    final s = _scene;
    final now = _now;
    final plan = _plan();
    final lines = plan.lines;
    final keys = [for (var i = 0; i < lines.length; i++) _lineKey(lines[i], i)];
    final outcome = plan.anyFailed
        ? _Outcome.failure
        : plan.success
            ? _Outcome.success
            : _Outcome.none;

    var cameAlive = false;
    if (first) {
      s.live = plan.inProgress;
    } else if (!s.live && plan.inProgress) {
      // A record that runs again (a retry on the same surface).
      s.live = true;
      cameAlive = true;
      s.replayAt = null;
    }
    final animate = s.live;
    final spotBefore = first ? 0 : _spotOf(s, now);

    var checked = false;
    var landed = false;
    final justDone = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final k = keys[i];
      final fx = s.fx[k];
      if (fx == null) {
        final n = _Fx(l.status);
        if (animate && l.status == MoneyStepStatus.running) n.runSince = now;
        s.fx[k] = n;
        continue;
      }
      if (fx.status == l.status) continue;
      if (animate && !first) {
        switch (l.status) {
          case MoneyStepStatus.done || MoneyStepStatus.skipped:
            fx.litFrom = _segLit(s, fx, now);
            fx.doneAt = now;
            fx.dashMs = _kDash;
            fx.failedAt = null;
            checked = true;
            justDone.add(k);
          case MoneyStepStatus.running:
            fx.runSince = now;
            fx.doneAt = null;
            fx.failedAt = null;
          case MoneyStepStatus.failed:
            fx.litFrom = _segLit(s, fx, now);
            fx.failedAt = now;
            fx.doneAt = null;
          case MoneyStepStatus.waiting || MoneyStepStatus.fellBack:
            fx.doneAt = null;
            fx.failedAt = null;
        }
      }
      fx.status = l.status;
    }
    s.fx.removeWhere((k, _) => !keys.contains(k));
    s.plan = plan;
    s.keys = keys;
    s.geo = null;

    final progress = _progressOf(s);
    _moment(now);
    if (first) {
      s.barFrom = s.barTo = progress;
      s.barAt = now;
      s.outcome = outcome;
      s.outcomeAt = now;
      s.salEnterAt = now;
      s.countFrom = now;
      if (!s.live && !plan.inProgress && lines.isNotEmpty) {
        _setUpReplay(now);
      }
      s.spot = _spotOf(s, now);
      return;
    }
    if (progress != s.barTo) {
      s.barFrom = s.still ? progress : _barAt(s, now);
      s.barTo = progress;
      s.barAt = now;
    }
    if (!s.live) {
      s.outcome = outcome;
      return;
    }
    if (cameAlive) {
      s.outcome = _Outcome.none;
      s.outcomeAt = now;
      s.salEnterAt = now;
      s.countFrom = now;
    }

    if (outcome != s.outcome) {
      s.outcome = outcome;
      s.outcomeAt = now;
      switch (outcome) {
        case _Outcome.success:
          // The last check: a bigger pop and burst, and the success beat
          // in place of its light tap.
          final last = keys.lastWhere(justDone.contains, orElse: () => '');
          s.fx[last]?.finalDone = true;
          checked = false;
          _schedule(now + _kPopDelay, _Haptic.success);
        case _Outcome.failure:
          _schedule(now, _Haptic.failure);
        case _Outcome.none:
          break;
      }
    }

    // Sal lands somewhere new: the hop and its click once his dash ends.
    final spotAfter = _spotOf(s, now + _kDash + 1);
    if (spotAfter != spotBefore && spotAfter > s.spot) {
      s.hopAt = now + _kDash;
      landed = true;
    }
    s.spot = math.max(s.spot, spotBefore);
    // Another coin lands where he waits: he perks up.
    for (final k in justDone) {
      final i = keys.indexOf(k);
      final road = plan.roads.where((r) => r.line == i).firstOrNull;
      if (road == null || plan.chain.contains(plan.roads.indexOf(road))) {
        continue;
      }
      s.waveAt = now + _kDash;
    }
    if (landed && s.outcome == _Outcome.none) {
      _schedule(now + _kDash, _Haptic.arrive);
    }
    if (checked) _schedule(now + _kPopDelay, _Haptic.check);
  }

  /// A finished record opening: the roads light in order, then the
  /// checkpoints check, over about [_kReplay]; Sal rides along and sits.
  void _setUpReplay(double now) {
    final s = _scene;
    if (s.still) return;
    final plan = s.plan;
    final order = <String>[
      for (final r in plan.roads)
        if (r.line >= 0)
          for (final i in r.segments) s.keys[i],
      for (final i in plan.checkpoints) s.keys[i],
    ];
    if (order.isEmpty) return;
    final slot = _kReplay / order.length;
    s.replayAt = now;
    for (var n = 0; n < order.length; n++) {
      final fx = s.fx[order[n]];
      if (fx == null || !fx.status.satisfies) continue;
      fx.litFrom = 0;
      fx.doneAt = now + 150 + n * slot;
      fx.dashMs = math.max(slot, 120);
    }
    s.countFrom = now;
    s.barFrom = 0;
    s.barAt = now;
  }

  static double _barAt(_Scene s, double now) {
    if (s.still) return s.barTo;
    final span =
        s.replayAt != null && s.barAt == s.replayAt ? _kReplay : _kBar;
    final t = Curves.easeOutCubic.transform(_unit((now - s.barAt) / span));
    return s.barFrom + (s.barTo - s.barFrom) * t;
  }

  void _tapAt(Offset at) {
    final s = _scene;
    final sal = s.lastSal;
    if (sal == null) return;
    final reach = s.look.salSize * 1.3;
    if ((at - sal.translate(0, -s.look.salSize * 0.6)).distance > reach) {
      return;
    }
    s.jumpAt = _now;
    _moment(_now);
    _fire(_Haptic.tap);
    _kick();
  }

  double _shakeDx(String key) {
    final s = _scene;
    final at = s.fx[key]?.failedAt;
    if (s.still || at == null) return 0;
    return _shakeAt(s.look.shake, _now - at);
  }

  double _stationShake(int i) {
    final s = _scene;
    if (s.still) return 0;
    final at = _stationFailedAt(s, i);
    return at == null ? 0 : _shakeAt(s.look.shake, _now - at);
  }

  double _stationScale(int i) {
    final s = _scene;
    if (s.still) return 1;
    final at = _stationDoneAt(s, i);
    if (at == null || !at.isFinite) return 1;
    final e = _now - at - _kPopDelay;
    if (e < 0) return 1;
    final big = i == s.plan.destination && s.outcome == _Outcome.success;
    return _pop(_unit(e / _kPop), big ? 1.3 : 1.25, from: 0.6);
  }

  double? _countProgress() {
    final s = _scene;
    final from = s.countFrom;
    if (s.still || from == null) return null;
    return ((_now - from) / _kCountUp).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final keys = widget.keys;
    final s = _scene;
    final plan = s.plan;
    final lines = plan.lines;
    final direction = Directionality.of(context);
    s.look = _Look(
      quiet: c.textTertiary,
      done: c.textSecondary,
      failed: c.error,
      gold: KuteDogPalette.mascot.furLight,
      ping: c.textPrimary,
      surface: c.surfaceElevated,
      border: c.border,
      success: c.success,
      stationR: 14.r,
      waypointR: 4.5.r,
      coinR: 4.5.r,
      roadW: 2.5.r,
      salSize: 22.r,
      signR: 7.r,
      shake: 4.r,
      padX: 34.r,
      amountStyle: TextStyle(
          color: c.textSecondary, fontSize: 9.sp, fontWeight: FontWeight.w600),
      direction: direction,
    );
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);

    // ── The words on top ──
    // The status names the line at work (a stop, the sub-phase running)
    // when it is on the map (a leg, a sub-leg); a checkpoint listed under
    // the map speaks for itself there, in bold, so it is never said twice.
    final focus = plan.focus;
    final checkpoints = plan.checkpoints;
    String? status;
    if (s.outcome == _Outcome.success && plan.placeLine != null) {
      status = l10n.moneyJourneyPlaced;
    } else if (s.outcome == _Outcome.success && lines.isNotEmpty) {
      if (!checkpoints.contains(lines.length - 1)) status = lines.last.text;
    } else if (focus != null && !checkpoints.contains(focus)) {
      status = s.outcome == _Outcome.failure
          ? lines[focus].text
          : lines[focus].brief ?? lines[focus].text;
    }
    final headline = plan.headline;
    final pct = (s.barTo * 100).round().clamp(0, 100);
    final headlineStyle = TextStyle(
        color: c.textPrimary,
        fontSize: 15.sp,
        fontWeight: FontWeight.w700,
        height: 1.3);

    // ── The checkpoints under the map ──
    final anyFailed = plan.anyFailed;
    final destPlace = plan.destination == null
        ? null
        : plan.stations[plan.destination!].place;
    final checksRunning =
        checkpoints.any((i) => lines[i].status == MoneyStepStatus.running);

    Widget sign(int i, MoneyStepStatus status) {
      final (word, size) = switch (status) {
        MoneyStepStatus.failed => ('failed', 14.r),
        MoneyStepStatus.done || MoneyStepStatus.skipped => ('done', 14.r),
        MoneyStepStatus.fellBack => ('fellback', 14.r),
        MoneyStepStatus.running => (keys.runningWord, 12.r),
        MoneyStepStatus.waiting => ('waiting', 12.r),
      };
      return SizedBox.square(
          key: ValueKey('${keys.step}$word-$i'), dimension: size);
    }

    Widget checkpoint(int i) {
      final line = lines[i];
      final k = _lineKey(line, i);
      final style = TextStyle(
        color: switch (line.status) {
          MoneyStepStatus.failed || MoneyStepStatus.running => c.textPrimary,
          MoneyStepStatus.waiting => c.textTertiary,
          _ => c.textSecondary,
        },
        fontSize: (line.sub ? 12 : 13).sp,
        height: 1.35,
        fontWeight: line.status == MoneyStepStatus.running
            ? FontWeight.w600
            : FontWeight.w400,
      );
      return _Shake(
        clock: _clock,
        dx: () => _shakeDx(k),
        child: Padding(
          key: ValueKey('${keys.step}${line.id ?? i}'),
          padding: EdgeInsets.only(
              top: 3.h, bottom: 3.h, left: line.sub ? 22.w : 0),
          child: Row(
            children: [
              SizedBox(
                width: 22.w,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _SignPainter(s, k, _clock),
                      child: sign(i, line.status),
                    ),
                  ),
                ),
              ),
              Flexible(child: Text(line.text, style: style)),
            ],
          ),
        ),
      );
    }

    final checkList = <Widget>[];
    for (var n = 0; n < checkpoints.length; n++) {
      final i = checkpoints[n];
      final role = _treeRole(lines, checkpoints, n);
      final row = checkpoint(i);
      checkList.add(role == null
          ? row
          : CustomPaint(
              key: ValueKey('money-step-tree-${lines[i].id ?? i}'),
              painter: MoneyStepTreePainter(
                role: role,
                color: c.textTertiary,
                trunkX: 6.5.r,
                indent: 22.w,
                signHalf: 7.r,
              ),
              child: row,
            ));
    }

    return Padding(
      key: ValueKey(keys.container),
      padding: EdgeInsets.only(top: 10.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The amount, counting up, and the status in plain words.
          if (headline != null || status != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (headline != null) ...[
                  _CountUp(
                    clock: _clock,
                    progress: _countProgress,
                    text: headline,
                    style: base.merge(headlineStyle),
                    scaler: scaler,
                    direction: direction,
                    child: Text(headline,
                        key: const ValueKey('money-steps-amount'),
                        style: headlineStyle),
                  ),
                  SizedBox(width: 8.w),
                ],
                if (status != null)
                  Flexible(
                    child: Text(
                      status,
                      key: const ValueKey('money-steps-status'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: s.outcome == _Outcome.failure
                              ? c.textPrimary
                              : c.textSecondary,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                          height: 1.3),
                    ),
                  ),
              ],
            ),
          // The thin bar and its percent.
          Padding(
            padding: EdgeInsets.only(top: 6.h, bottom: 4.h),
            child: Row(
              children: [
                Expanded(
                  child: _Bar(
                    clock: _clock,
                    progress: () => _barAt(s, _now),
                    track: c.border,
                    fill: s.outcome == _Outcome.failure
                        ? c.error
                        : KuteDogPalette.mascot.furLight,
                    height: 3.r,
                  ),
                ),
                SizedBox(width: 8.w),
                Text('$pct%',
                    key: const ValueKey('money-steps-percent'),
                    style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
          // The map.
          if (plan.stations.isNotEmpty)
            LayoutBuilder(builder: (context, constraints) {
              final size = Size(constraints.maxWidth, 150.r);
              final geo = s.geo = _Geometry.of(plan, size, s.look);
              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (d) => _tapAt(d.localPosition),
                child: SizedBox(
                  key: const ValueKey('money-steps-map'),
                  width: size.width,
                  height: size.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                              painter: _MapPainter(s, _clock, geo)),
                        ),
                      ),
                      for (var i = 0; i < plan.stations.length; i++)
                        _station(context, i, geo, l10n, checksRunning),
                      for (var r = 0; r < plan.roads.length; r++)
                        ..._roadSemantics(r, geo, sign),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(
                                painter:
                                    MoneyJourneyPainter._(s, _clock, geo)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          // The checkpoints at the destination.
          if (checkList.isNotEmpty) ...[
            if (plan.hasGraph && destPlace != null)
              Padding(
                padding: EdgeInsets.only(top: 6.h, bottom: 2.h),
                child: Text(
                  l10n.moneyJourneyAt(moneyPlaceName(l10n, destPlace)),
                  key: const ValueKey('money-steps-checkpoints-title'),
                  style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.3),
                ),
              )
            else
              SizedBox(height: 4.h),
            ...checkList,
          ],
          if (widget.slow && !anyFailed)
            Padding(
              padding: EdgeInsets.only(top: 4.h, left: 22.w),
              child: Text(
                l10n.slipStepTakingLonger,
                key: ValueKey(keys.slow),
                style: TextStyle(
                    color: c.textTertiary, fontSize: 12.sp, height: 1.35),
              ),
            ),
          if (widget.note case final line?)
            Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: Text(
                line,
                key: ValueKey(keys.note),
                style: TextStyle(
                    color: c.textSecondary, fontSize: 13.sp, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }

  /// A station: its mark on a disc (gold once the money is there, red on
  /// a stop), its name under it, the "n of m arrived" or "k/n" chip under
  /// the destination. The pop and the shake are paint-only.
  Widget _station(BuildContext context, int i, _Geometry geo,
      AppLocalizations l10n, bool checksRunning) {
    final c = context.colors;
    final s = _scene;
    final plan = s.plan;
    final st = plan.stations[i];
    final at = geo.stations[i];
    final look = s.look;
    final r = look.stationR;
    final done = _stationDone(s, i);
    final failed = _stationFailedAt(s, i) != null;
    final fill = failed
        ? c.error.withValues(alpha: 0.22)
        : done
            ? look.gold.withValues(alpha: 0.38)
            : look.surface;
    final ring = failed
        ? c.error
        : done
            ? look.gold
            : look.border;
    final label = st.label ??
        (st.place == null ? l10n.recipient : moneyPlaceName(l10n, st.place!));
    String? chip;
    if (i == plan.destination) {
      final sources = plan.sourceRoads.where((r) => r.line >= 0).toList();
      final arrived =
          sources.where((r) => plan.lines[r.line].status.satisfies).length;
      if (sources.length > 1 && arrived < sources.length) {
        chip = l10n.moneyJourneyArrived(arrived, sources.length);
      } else if (checksRunning && plan.hasGraph) {
        // The steps themselves, not a stage line that only sums its own.
        final checks = [
          for (var n = 0; n < plan.checkpoints.length; n++)
            if (_treeRole(plan.lines, plan.checkpoints, n) !=
                MoneyStepTreeRole.parent)
              plan.checkpoints[n]
        ];
        final ok =
            checks.where((k) => plan.lines[k].status.satisfies).length;
        chip = '$ok/${checks.length}';
      }
    }
    final mark = switch (st.place) {
      MoneyPlace.bitcoin => Icon(Icons.currency_bitcoin_rounded,
          size: r * 1.3, color: KuteDogPalette.mascot.fur),
      MoneyPlace.dollars => Text('\$',
          style: TextStyle(
              color: c.success,
              fontSize: r * 1.15,
              fontWeight: FontWeight.w800,
              height: 1)),
      MoneyPlace.investing => SvgPicture.asset(
          'lib/assets/hyperliquid-logo.svg',
          width: r * 1.2,
          height: r * 1.2),
      MoneyPlace.predictions => SvgPicture.asset(
          'lib/assets/polymarket-logo.svg',
          width: r * 1.2,
          height: r * 1.2),
      null => Icon(Icons.arrow_outward_rounded,
          size: r * 1.2, color: c.textSecondary),
    };
    final labelW = 72.r;
    return Positioned(
      left: at.dx - labelW / 2,
      top: at.dy - r,
      width: labelW,
      child: Semantics(
        key: ValueKey('money-steps-station-${st.id}'),
        label: label,
        excludeSemantics: true,
        child: _Shake(
          clock: _clock,
          dx: () => _stationShake(i),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Scaled(
                clock: _clock,
                scale: () => _stationScale(i),
                child: Container(
                  width: r * 2,
                  height: r * 2,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                    border: Border.all(color: ring, width: 1.5),
                  ),
                  child: mark,
                ),
              ),
              SizedBox(height: 3.h),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: done || failed ? c.textPrimary : c.textSecondary,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                    height: 1.2),
              ),
              if (chip != null)
                Padding(
                  padding: EdgeInsets.only(top: 2.h),
                  child: Container(
                    key: const ValueKey('money-steps-chip'),
                    padding:
                        EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.h),
                    decoration: BoxDecoration(
                      color: look.surface,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: look.border, width: 1),
                    ),
                    child: Text(chip,
                        style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 9.sp,
                            fontWeight: FontWeight.w600,
                            height: 1.2)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The words of a road's leg line, and of each sub-leg, as semantics
  /// nodes on the map (over the road's middle, over each waypoint), each
  /// with the line's sign key, so a screen reader and the tests find
  /// "Moved $8.00 from Bitcoin" and "Circle → Arbitrum · $10.84".
  List<Widget> _roadSemantics(
      int r, _Geometry geo, Widget Function(int, MoneyStepStatus) sign) {
    final s = _scene;
    final plan = s.plan;
    final road = plan.roads[r];
    if (road.line < 0) return const [];
    final lines = plan.lines;
    Widget node(int i, Offset at, double w, double h) => Positioned(
          left: at.dx - w / 2,
          top: at.dy - h / 2,
          width: w,
          height: h,
          child: Semantics(
            key: ValueKey('money-steps-road-${lines[i].id ?? i}'),
            label: lines[i].text,
            container: true,
            child: ExcludeSemantics(child: sign(i, lines[i].status)),
          ),
        );
    final mid = geo.along(r, 0.5);
    return [
      node(road.line, mid, 40.r, 20.r),
      for (var k = 0; k < road.segments.length; k++)
        if (road.segments[k] != road.line)
          node(
              road.segments[k],
              k < geo.waypoints[r].length
                  ? geo.waypoints[r][k]
                  : geo.stations[road.to]
                      .translate(0, s.look.stationR + 8.r),
              20.r,
              20.r),
    ];
  }
}

/// Where checkpoint [n] of [checkpoints] sits in the steps' tree.
MoneyStepTreeRole? _treeRole(
    List<MoneyStepLine> lines, List<int> checkpoints, int n) {
  final i = checkpoints[n];
  final next = n + 1 < checkpoints.length ? lines[checkpoints[n + 1]] : null;
  if (lines[i].sub) {
    return next == null || !next.sub
        ? MoneyStepTreeRole.lastChild
        : MoneyStepTreeRole.child;
  }
  return next != null && next.sub ? MoneyStepTreeRole.parent : null;
}

/// Where line [i] of [lines] sits in the steps' tree; null when it is not
/// in one (a line with no sub-steps under it).
MoneyStepTreeRole? moneyStepTreeRole(List<MoneyStepLine> lines, int i) =>
    _treeRole(lines, [for (var k = 0; k < lines.length; k++) k], i);

/// Where a line sits in the steps' tree.
enum MoneyStepTreeRole {
  /// A stage line with sub-steps under it: the trunk starts below its
  /// sign.
  parent,

  /// A sub-step with more under it: the trunk runs through, with an
  /// elbow into its sign (├).
  child,

  /// The last sub-step: the trunk ends in its elbow (└).
  lastChild,
}

void _paintTreeBranch(Canvas canvas, Size size, MoneyStepTreeRole role,
    Paint paint, double trunkX, double indent, double signHalf) {
  final mid = size.height / 2;
  final gap = signHalf * 0.3;
  switch (role) {
    case MoneyStepTreeRole.parent:
      final top = mid + signHalf + gap;
      if (top < size.height) {
        canvas.drawLine(
            Offset(trunkX, top), Offset(trunkX, size.height), paint);
      }
    case MoneyStepTreeRole.child:
      canvas.drawLine(Offset(trunkX, 0), Offset(trunkX, size.height), paint);
      canvas.drawLine(
          Offset(trunkX, mid), Offset(indent - gap * 2, mid), paint);
    case MoneyStepTreeRole.lastChild:
      final corner = signHalf * 0.45;
      canvas.drawPath(
          Path()
            ..moveTo(trunkX, 0)
            ..lineTo(trunkX, mid - corner)
            ..quadraticBezierTo(trunkX, mid, trunkX + corner, mid)
            ..lineTo(indent - gap * 2, mid),
          paint);
  }
}

/// The thin connector of the checkpoints' tree, drawn in the lines' own
/// quiet colour behind one line: [trunkX] is the centre of the stage
/// line's sign, [indent] where a sub-step's sign starts, [signHalf] half
/// a sign's height (the trunk leaves a stage line just below it). No
/// box, no fill.
@visibleForTesting
class MoneyStepTreePainter extends CustomPainter {
  const MoneyStepTreePainter({
    required this.role,
    required this.color,
    required this.trunkX,
    required this.indent,
    required this.signHalf,
  });

  final MoneyStepTreeRole role;
  final Color color;
  final double trunkX;
  final double indent;
  final double signHalf;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    _paintTreeBranch(canvas, size, role, paint, trunkX, indent, signHalf);
  }

  @override
  bool shouldRepaint(MoneyStepTreePainter old) =>
      old.role != role ||
      old.color != color ||
      old.trunkX != trunkX ||
      old.indent != indent ||
      old.signHalf != signHalf;
}

// ─────────────────────────────────────────────────────────────────────
// Reading the scene
// ─────────────────────────────────────────────────────────────────────

/// How far one segment (a line's stretch of road) is lit at [now]: all
/// the way once done (dashed to from where it was), part of the way and
/// holding while it runs, where it stopped on a stop.
double _segLit(_Scene s, _Fx? f, double now) {
  if (f == null) return 0;
  switch (f.status) {
    case MoneyStepStatus.done || MoneyStepStatus.skipped:
      final at = f.doneAt;
      if (s.still || at == null) return 1;
      final e = now - at;
      if (e < 0) return f.litFrom;
      return f.litFrom +
          (1 - f.litFrom) *
              Curves.easeOutCubic.transform(_unit(e / f.dashMs));
    case MoneyStepStatus.running:
      final since = f.runSince;
      if (s.still || since == null) return _kHold;
      return _kHold *
          Curves.easeOutCubic.transform(_unit((now - since) / _kApproach));
    case MoneyStepStatus.failed:
      return f.litFrom;
    case MoneyStepStatus.waiting || MoneyStepStatus.fellBack:
      return 0;
  }
}

double _roadLit(_Scene s, JourneyRoad road, double now) {
  if (road.segments.isEmpty) return 1;
  var sum = 0.0;
  for (final i in road.segments) {
    sum += _segLit(s, s.fx[s.keys[i]], now);
  }
  return sum / road.segments.length;
}

/// Whether the money is at station [i]: every road into it is done
/// (and, for a source, every road out of it).
bool _stationDone(_Scene s, int i) {
  final plan = s.plan;
  final into = plan.roads.where((r) => r.to == i);
  final out = plan.roads.where((r) => r.from == i);
  if (into.isEmpty && out.isEmpty) {
    return plan.checkpoints.isNotEmpty &&
        plan.checkpoints.every((k) => plan.lines[k].status.satisfies);
  }
  bool ok(JourneyRoad r) => r.segments.every((k) =>
      plan.lines[k].status.satisfies ||
      plan.lines[k].status == MoneyStepStatus.fellBack);
  return into.isNotEmpty ? into.every(ok) : out.every(ok);
}

/// When station [i] turned gold (the latest of its roads' dashes), null
/// while it has not, negative infinity when it was before the view.
double? _stationDoneAt(_Scene s, int i) {
  if (!_stationDone(s, i)) return null;
  final plan = s.plan;
  var into = plan.roads.where((r) => r.to == i).toList();
  if (into.isEmpty) into = plan.roads.where((r) => r.from == i).toList();
  double? latest;
  if (into.isEmpty) {
    for (final k in plan.checkpoints) {
      final at = s.fx[s.keys[k]]?.doneAt;
      if (at != null) {
        latest = latest == null ? at : math.max(latest, at);
      }
    }
    return latest ?? double.negativeInfinity;
  }
  for (final r in into) {
    for (final k in r.segments) {
      final f = s.fx[s.keys[k]];
      final at = f?.doneAt;
      if (at == null) continue;
      final end = at + f!.dashMs - _kPopDelay;
      latest = latest == null ? end : math.max(latest, end);
    }
  }
  return latest ?? double.negativeInfinity;
}

/// When a stop reached station [i] (a road into it, or a checkpoint at
/// the destination, failed), null when none did.
double? _stationFailedAt(_Scene s, int i) {
  final plan = s.plan;
  double? at;
  void note(int k) {
    if (plan.lines[k].status != MoneyStepStatus.failed) return;
    at = s.fx[s.keys[k]]?.failedAt ?? double.negativeInfinity;
  }

  for (final r in plan.roads) {
    if (r.to != i) continue;
    for (final k in r.segments) {
      note(k);
    }
  }
  if (at == null && i == plan.destination) {
    for (final k in plan.checkpoints) {
      note(k);
    }
  }
  return at;
}

// ─────────────────────────────────────────────────────────────────────
// Motion helpers
// ─────────────────────────────────────────────────────────────────────

/// The pop: [from] up to [peak], then back to 1.
double _pop(double p, double peak, {double from = 0.5}) {
  if (p <= 0) return from;
  if (p >= 1) return 1;
  if (p < 0.55) {
    return from + (peak - from) * Curves.easeOutCubic.transform(p / 0.55);
  }
  return peak + (1 - peak) * Curves.easeInOut.transform((p - 0.55) / 0.45);
}

/// The stop's shake: two decaying cycles over [_kShake].
double _shakeAt(double amplitude, double e) {
  if (e < 0 || e >= _kShake) return 0;
  final p = e / _kShake;
  return amplitude * math.sin(2 * math.pi * 2 * p) * (1 - p);
}

double _unit(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0);

/// Deterministic 0..1 noise, so stars and confetti never boil.
double _noise(int seed) {
  final x = math.sin(seed * 12.9898) * 43758.5453;
  return x - x.floorToDouble();
}

KuteDogPose _withLift(KuteDogPose p, double lift) => KuteDogPose(
      headTilt: p.headTilt,
      headBob: p.headBob - 0.2 * lift,
      headLean: p.headLean,
      earLeft: p.earLeft + 0.25 * lift,
      earRight: p.earRight + 0.3 * lift,
      tail: p.tail,
      blink: p.blink,
      squash: p.squash + 0.04 * lift,
      bodyBob: p.bodyBob,
      lift: p.lift + lift,
      pawLeft: p.pawLeft - 0.25 * lift,
      pawRight: p.pawRight - 0.25 * lift,
      lookX: p.lookX,
      lookY: p.lookY,
      tongue: p.tongue,
    );

/// A runner's colour: its balance's own (the marks' colours).
Color _placeColor(MoneyPlace? place, _Look look) => switch (place) {
      MoneyPlace.bitcoin => KuteDogPalette.mascot.fur,
      MoneyPlace.dollars => look.success,
      MoneyPlace.investing => const Color(0xFF97FCE4),
      MoneyPlace.predictions => const Color(0xFF2E5CFF),
      null => look.done,
    };

// ─────────────────────────────────────────────────────────────────────
// The map's painters
// ─────────────────────────────────────────────────────────────────────

/// Behind the stations: the stars, the roads (quiet, lit gold behind
/// each runner), the waypoints (with their names and amounts), the pings
/// around the station at work and the bursts around one just reached.
class _MapPainter extends CustomPainter {
  _MapPainter(this._scene, this._clock, this._geo) : super(repaint: _clock);

  final _Scene _scene;
  final Animation<double> _clock;
  final _Geometry _geo;

  @override
  void paint(Canvas canvas, Size size) {
    final s = _scene;
    final look = s.look;
    final plan = s.plan;
    final now = _clock.value * 1000;
    final still = s.still;
    final geo = _geo;

    // ── Stars ──
    final star = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 16; i++) {
      final x = _noise(i * 3 + 1) * size.width;
      final y = _noise(i * 3 + 2) * size.height;
      final period = 1800 + _noise(i * 3 + 3) * 1600;
      final tw = still
          ? 0.5
          : 0.5 + 0.5 * math.sin(2 * math.pi * now / period + i * 1.7);
      star.color = look.quiet.withValues(alpha: 0.10 + 0.22 * tw);
      canvas.drawCircle(Offset(x, y), 0.9 + 0.7 * _noise(i + 40), star);
    }

    // ── Roads ──
    final quiet = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = look.roadW
      ..strokeCap = StrokeCap.round
      ..color = look.border;
    final lit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = look.roadW
      ..strokeCap = StrokeCap.round
      ..color = look.gold;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = look.roadW * 3
      ..strokeCap = StrokeCap.round
      ..color = look.gold.withValues(alpha: 0.18);
    final stopped = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = look.roadW
      ..strokeCap = StrokeCap.round
      ..color = look.failed.withValues(alpha: 0.55);
    for (var r = 0; r < plan.roads.length; r++) {
      final path = geo.roads[r];
      final m = geo.metrics[r];
      canvas.drawPath(path, quiet);
      if (m == null) continue;
      final road = plan.roads[r];
      final f = _roadLit(s, road, now);
      if (f > 0) {
        final part = m.extractPath(0, m.length * f);
        canvas.drawPath(part, glow);
        canvas.drawPath(part, lit);
      }
      // A stop on the road: its stretch in the failed colour.
      for (var k = 0; k < road.segments.length; k++) {
        if (plan.lines[road.segments[k]].status != MoneyStepStatus.failed) {
          continue;
        }
        final a = m.length * k / road.segments.length;
        final b = m.length * (k + 1) / road.segments.length;
        canvas.drawPath(m.extractPath(a, b), stopped);
      }
    }

    // ── Waypoints ──
    for (var r = 0; r < plan.roads.length; r++) {
      final road = plan.roads[r];
      for (var k = 0; k < road.waypoints.length; k++) {
        final wp = road.waypoints[k];
        final at = geo.waypoints[r][k];
        final line = plan.lines[wp.line];
        final fx = s.fx[s.keys[wp.line]];
        final done = line.status.satisfies;
        final failed = line.status == MoneyStepStatus.failed;
        final running = line.status == MoneyStepStatus.running;
        var scale = 1.0;
        if (done && !still && fx?.doneAt != null) {
          final e = now - fx!.doneAt! - _kPopDelay;
          scale = e < 0 ? 0.9 : _pop(_unit(e / _kPop), 1.4, from: 0.6);
        }
        final fill = failed
            ? look.failed
            : done
                ? look.gold
                : look.surface;
        final rim = failed
            ? look.failed
            : done
                ? look.gold
                : running
                    ? look.ping
                    : look.border;
        canvas.drawCircle(at, look.waypointR * scale, Paint()..color = fill);
        canvas.drawCircle(
            at,
            look.waypointR * scale,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = rim);
        if (running) _ping(canvas, at, look.waypointR + 2, now, still);
        if (done && !still) _burst(canvas, at, now, fx, look, small: true);
        // Its name under it; its amount above it once it is on its way.
        _label(
            canvas,
            wp.label,
            at.translate(0, look.waypointR + 2),
            look.amountStyle.copyWith(
                color: done ? look.done : look.quiet,
                fontWeight: FontWeight.w500),
            below: true);
        final amount = wp.amount;
        if (amount != null && (done || running)) {
          _label(canvas, amount, at.translate(0, -look.waypointR - 2),
              look.amountStyle.copyWith(color: done ? look.done : look.quiet),
              below: false);
        }
      }
    }

    // ── The stations at work, and the ones just reached ──
    final running = <int>{};
    for (final r in plan.roads) {
      if (r.segments
          .any((k) => plan.lines[k].status == MoneyStepStatus.running)) {
        running.add(r.to);
      }
    }
    final dest = plan.destination;
    if (dest != null &&
        plan.checkpoints
            .any((k) => plan.lines[k].status == MoneyStepStatus.running)) {
      running.add(dest);
    }
    for (var i = 0; i < plan.stations.length; i++) {
      final at = geo.stations[i];
      if (running.contains(i) && !_stationDone(s, i)) {
        _ping(canvas, at, look.stationR + 3, now, still);
      }
      final doneAt = _stationDoneAt(s, i);
      if (doneAt != null && !still && doneAt.isFinite) {
        final big = i == dest && s.outcome == _Outcome.success && s.live;
        final fx = _Fx(MoneyStepStatus.done)
          ..doneAt = big ? s.outcomeAt : doneAt
          ..finalDone = big;
        _burst(canvas, at, now, fx, look, small: false, radius: look.stationR);
      }
    }
  }

  void _ping(Canvas canvas, Offset at, double r, double now, bool still) {
    final look = _scene.look;
    if (still) {
      canvas.drawCircle(
          at,
          r + 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = look.ping.withValues(alpha: 0.5));
      return;
    }
    final p = (now % _kPing) / _kPing;
    canvas.drawCircle(
        at,
        r + 10 * Curves.easeOut.transform(p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * (1 - p) + 0.4
          ..color = look.ping.withValues(alpha: 0.55 * (1 - p)));
  }

  void _label(Canvas canvas, String text, Offset at, TextStyle style,
      {required bool below}) {
    if (text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: _scene.look.direction,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 64);
    tp.paint(canvas, at.translate(-tp.width / 2, below ? 0 : -tp.height));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_MapPainter old) => true;
}

/// A finished step's burst: six gold dots out from [at] (ten, bigger,
/// for the last one), right after its pop.
void _burst(Canvas canvas, Offset at, double now, _Fx? fx, _Look look,
    {required bool small, double? radius}) {
  final doneAt = fx?.doneAt;
  if (doneAt == null) return;
  final pe = now - doneAt - _kPopDelay;
  final span = fx!.finalDone ? _kFinalBurst : _kBurst;
  final bp = pe / span;
  if (bp < 0 || bp >= 1) return;
  final n = fx.finalDone ? 10 : 6;
  final base = radius ?? look.waypointR;
  final reach = (fx.finalDone ? 16.0 : 10.0) * (small ? 0.6 : 1);
  final dot = (fx.finalDone ? 2.0 : 1.6) * (small ? 0.7 : 1);
  final out = Curves.easeOutCubic.transform(bp);
  final paint = Paint()
    ..color = look.gold.withValues(alpha: math.pow(1 - bp, 1.4).toDouble());
  for (var j = 0; j < n; j++) {
    final a = -math.pi / 2 + 2 * math.pi * j / n + (j.isOdd ? 0.18 : -0.12);
    final d = base + reach * out;
    canvas.drawCircle(at + Offset(math.cos(a), math.sin(a)) * d,
        dot * (1 - 0.5 * bp), paint);
  }
}

/// Over the stations: the coins running the other roads, Sal with his,
/// and the confetti. One painter, repainted by the view's clock.
@visibleForTesting
class MoneyJourneyPainter extends CustomPainter {
  MoneyJourneyPainter._(this._scene, this._clock, this._geo)
      : super(repaint: _clock);

  final _Scene _scene;
  final Animation<double> _clock;
  final _Geometry _geo;

  double get _now => _clock.value * 1000;

  /// Whether Sal is drawn (he always is, once the map has a station).
  bool get travellerShown => _scene.plan.stations.isNotEmpty;

  /// Where Sal stands now, in the map's coordinates.
  Offset? get travellerAt => _scene.lastSal;

  /// The id of the road's leg line Sal rides now, null once he sits at
  /// a station (`#stage` on the stage road of a list without a graph).
  String? get travellerRoad {
    final s = _scene;
    final spot = _MoneyStepsViewState._spotOf(s, _now);
    if (spot >= s.plan.chain.length) return null;
    final road = s.plan.roads[s.plan.chain[spot]];
    return road.line < 0 ? '#stage' : s.plan.lines[road.line].id;
  }

  /// The station Sal is at or heading to, by id.
  String? get travellerStation {
    final s = _scene;
    final plan = s.plan;
    if (plan.stations.isEmpty) return null;
    final spot = _MoneyStepsViewState._spotOf(s, _now);
    if (plan.chain.isEmpty) {
      return plan.stations[plan.destination ?? 0].id;
    }
    final road =
        plan.roads[plan.chain[math.min(spot, plan.chain.length - 1)]];
    return plan.stations[road.to].id;
  }

  /// How far line [id]'s road (or stretch of road) is lit now, 0..1.
  double litOf(String id) {
    final s = _scene;
    final i = s.keys.indexOf(id);
    if (i < 0) return 0;
    final road = s.plan.roads.where((r) => r.line == i).firstOrNull;
    return road == null ? _segLit(s, s.fx[id], _now) : _roadLit(s, road, _now);
  }

  /// How far line [id] is shaken sideways now (a stop's shake).
  double shakeOf(String id) {
    final at = _scene.fx[id]?.failedAt;
    if (_scene.still || at == null) return 0;
    return _shakeAt(_scene.look.shake, _now - at);
  }

  /// Whether a finished record is replaying its journey now.
  bool get replaying {
    final at = _scene.replayAt;
    return at != null && _now < at + _kReplay + 600;
  }

  /// Whether Sal is mid-jump from a tap.
  bool get jumping {
    final at = _scene.jumpAt;
    return at != null && !_scene.still && _now - at < _kHop;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = _scene;
    final look = s.look;
    final plan = s.plan;
    final now = _now;
    final still = s.still;
    final geo = _geo;
    if (plan.stations.isEmpty) return;

    // ── The other legs' coins ──
    for (var r = 0; r < plan.roads.length; r++) {
      if (plan.chain.contains(r)) continue;
      final road = plan.roads[r];
      if (road.line < 0) continue;
      final f = _roadLit(s, road, now);
      if (f <= 0) continue;
      var alpha = 1.0;
      if (f >= 1) {
        final last = s.fx[s.keys[road.segments.last]];
        final at = last?.doneAt;
        if (still || at == null) continue;
        alpha = 1 - _unit((now - at - last!.dashMs) / 120);
        if (alpha <= 0) continue;
      }
      final at = geo.along(r, f);
      final bob = still ? 0.0 : 1.5 * math.sin(now / 90);
      _coin(canvas, at.translate(0, bob),
          _placeColor(plan.stations[road.from].place, look), alpha, now);
    }

    // ── Sal ──
    final spot = _MoneyStepsViewState._spotOf(s, now);
    Offset at;
    var riding = false;
    var moving = false;
    if (plan.chain.isEmpty) {
      at = geo.stations[plan.destination ?? 0];
    } else if (spot < plan.chain.length) {
      final r = plan.chain[spot];
      final road = plan.roads[r];
      final f = _roadLit(s, road, now);
      riding = f > 0;
      at = riding ? geo.along(r, f) : geo.stations[road.from];
      moving = !still && riding && _roadLit(s, road, now - 40) < f - 1e-4;
    } else {
      at = geo.stations[plan.roads[plan.chain.last].to];
    }
    if (!riding) at = at.translate(0, -look.stationR + 2);
    s.lastSal = at;
    _paintSal(canvas, at, now, riding: riding, moving: moving);

    // ── Confetti ──
    if (s.outcome == _Outcome.success && !still && s.live) {
      _confetti(canvas, size, now - s.outcomeAt - _kPopDelay);
    }
  }

  void _coin(Canvas canvas, Offset at, Color color, double alpha, double now) {
    final look = _scene.look;
    final spin =
        _scene.still ? 1.0 : (0.35 + 0.65 * math.cos(now / 110).abs());
    final r = look.coinR;
    final rect = Rect.fromCenter(center: at, width: r * 2 * spin, height: r * 2);
    canvas.drawOval(rect, Paint()..color = color.withValues(alpha: alpha));
    canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.5 * alpha));
  }

  void _paintSal(Canvas canvas, Offset at, double now,
      {required bool riding, required bool moving}) {
    final s = _scene;
    final look = s.look;
    final still = s.still;
    var alpha = 1.0;
    var coin = s.live || s.replayAt != null;
    Offset? coinTo;
    KuteDogPose pose;
    final anyRunning =
        s.plan.lines.any((l) => l.status == MoneyStepStatus.running);
    switch (s.outcome) {
      case _Outcome.success:
        final e = now - s.outcomeAt;
        if (!s.live) {
          // A record: sitting there, pleased.
          pose = still ? KuteDogPose.neutral : _happyIdle(now - s.quietSince);
          coin = s.replayAt != null && now < s.replayAt! + _kReplay + 150;
        } else if (still) {
          pose = kuteMascotPose(KuteState.winPrediction, 0);
          coin = false;
        } else if (e < _kCheer) {
          pose = kuteMascotPose(KuteState.winPrediction, e % 900);
          coin = e < _kCoinDrop;
          coinTo = s.plan.destination == null
              ? null
              : _geo.stations[s.plan.destination!];
        } else {
          pose = _happyIdle(now - s.quietSince);
          coin = false;
        }
      case _Outcome.failure:
        // Sorry about it: the confused tilt, slow, and dimmed.
        final e = still ? 750.0 : now - s.outcomeAt;
        pose = kuteMascotPose(KuteState.error, still ? e : e % 1500);
        alpha = still ? _kDimAlpha : 1 - (1 - _kDimAlpha) * _unit(e / _kDim);
        coin = false;
      case _Outcome.none:
        if (still) {
          pose = anyRunning
              ? kuteMascotPose(KuteState.loading, 420)
              : KuteDogPose.neutral;
        } else if (moving) {
          // Running down the road, coin in his mouth.
          final step = kuteWave(now, 160);
          pose = KuteDogPose(
            earLeft: -0.25,
            earRight: -0.2,
            tail: 0.4 * kuteWave(now, 180),
            bodyBob: -0.35 * math.max(0.0, kuteWave(now, 80)),
            pawLeft: 0.5 * math.max(0, step),
            pawRight: 0.5 * math.max(0, -step),
            lookX: -0.4,
          );
        } else if (riding) {
          // Jogging on the spot while the leg lands.
          final step = kuteWave(now, 260);
          pose = KuteDogPose(
            earLeft: -0.15,
            earRight: -0.1,
            tail: 0.3 * kuteWave(now, 300),
            bodyBob: -0.2 * math.max(0.0, kuteWave(now, 130)),
            pawLeft: 0.3 * math.max(0, step),
            pawRight: 0.3 * math.max(0, -step),
            lookX: -0.8,
            blink: kuteBlink(now % 3100, 2200),
          );
        } else if (s.waveAt != null && now - s.waveAt! < _kWave) {
          // Another coin lands: ears up, front end lifting.
          pose = kuteMascotPose(KuteState.incoming, now - s.waveAt!);
        } else if (anyRunning) {
          // Thinking while the step runs: he sniffs it over.
          pose = kuteMascotPose(KuteState.loading, now % 1700);
        } else {
          pose = kuteDogIdlePose((now - s.quietSince) % kKuteDogIdleMs);
        }
    }
    if (!still) {
      final hop = s.hopAt;
      if (hop != null && now >= hop && now < hop + _kHop) {
        pose = _withLift(pose, 2.4 * math.sin(math.pi * (now - hop) / _kHop));
      }
      final jump = s.jumpAt;
      if (jump != null && now >= jump && now < jump + _kHop) {
        pose =
            _withLift(pose, 2.8 * math.sin(math.pi * (now - jump) / _kHop));
      }
      alpha *= _unit((now - s.salEnterAt) / 180);
    }
    if (alpha <= 0) return;
    final size = look.salSize;
    final u = size / 16;
    final origin = at.translate(-8.5 * u, -15 * u);
    final bounds = Rect.fromCenter(
        center: at.translate(0, -size * 0.5),
        width: size * 2.2,
        height: size * 2.6);
    if (alpha < 1) {
      canvas.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    }
    paintKuteDog(canvas,
        origin: origin, unit: u, pose: pose, palette: KuteDogPalette.mascot);
    if (alpha < 1) canvas.restore();
    if (coin) {
      // The coin at his muzzle and, on success, dropping into the last
      // station.
      var c = at.translate(-6.5 * u, (-7.5 - pose.lift + pose.headBob) * u);
      var scale = 1.0;
      if (coinTo != null) {
        final t = Curves.easeInCubic
            .transform(_unit((now - s.outcomeAt) / _kCoinDrop));
        c = Offset.lerp(c, coinTo, t)!;
        scale = 1 - 0.5 * t;
      }
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(scale);
      _coin(canvas, Offset.zero, look.gold, alpha, now);
      canvas.restore();
    }
  }

  KuteDogPose _happyIdle(double since) {
    final p = kuteDogIdlePose(since % kKuteDogIdleMs);
    return KuteDogPose(
      headTilt: p.headTilt,
      headBob: p.headBob,
      headLean: p.headLean,
      earLeft: p.earLeft - 0.1,
      earRight: p.earRight - 0.1,
      tail: 0.3 + 0.35 * kuteWave(since, 420),
      blink: p.blink,
      squash: p.squash,
      bodyBob: p.bodyBob,
      lift: p.lift,
      pawLeft: p.pawLeft,
      pawRight: p.pawRight,
      lookX: p.lookX,
      lookY: p.lookY,
      tongue: math.max(p.tongue, 0.3),
    );
  }

  void _confetti(Canvas canvas, Size size, double e) {
    if (e < 0 || e > _kConfetti + 300) return;
    final look = _scene.look;
    final colors = [
      look.gold,
      KuteDogPalette.mascot.fur,
      const Color(0xFF2E5CFF),
      const Color(0xFF97FCE4),
      KuteDogPalette.mascot.bandana,
    ];
    for (var i = 0; i < 30; i++) {
      final start = _noise(i * 5 + 1) * 300;
      final life = 1000 + _noise(i * 5 + 2) * 400;
      final t = (e - start) / life;
      if (t < 0 || t >= 1) continue;
      final x0 = _noise(i * 5 + 3) * size.width;
      final sway = math.sin(t * 6 + i) * 8;
      final y = -8 + (size.height + 16) * Curves.easeIn.transform(t);
      final w = 4 + _noise(i * 5 + 4) * 3;
      canvas.save();
      canvas.translate(x0 + sway, y);
      canvas.rotate(t * (3 + _noise(i + 9) * 5));
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.55),
          Paint()
            ..color = colors[i % colors.length]
                .withValues(alpha: (1 - _unit((t - 0.7) / 0.3)) * 0.95));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(MoneyJourneyPainter old) => true;
}

/// A checkpoint's sign: a faint dot while waiting, a ring drawing itself
/// and breathing while it runs, the ring closing then popping into a gold
/// check with a small burst once done, the stop sign fading in on a
/// failure, the route-change arrow for a step done another way.
class _SignPainter extends CustomPainter {
  _SignPainter(this._scene, this._key, this._clock) : super(repaint: _clock);

  final _Scene _scene;
  final String _key;
  final Animation<double> _clock;

  @override
  void paint(Canvas canvas, Size size) {
    final s = _scene;
    final look = s.look;
    final fx = s.fx[_key];
    if (fx == null) return;
    final now = _clock.value * 1000;
    final c = size.center(Offset.zero);
    final still = s.still;
    final dot = Paint()..color = look.quiet.withValues(alpha: 0.6);
    switch (fx.status) {
      case MoneyStepStatus.waiting:
        canvas.drawCircle(c, 2, dot);
      case MoneyStepStatus.running:
        final draw = still || fx.runSince == null
            ? 1.0
            : Curves.easeOutCubic
                .transform(_unit((now - fx.runSince!) / _kRingDraw));
        final rot = still ? 0.0 : now / 1600 * 2 * math.pi;
        final breathe = still
            ? 1.0
            : 0.8 + 0.2 * (0.5 + 0.5 * math.sin(now / 1100 * 2 * math.pi));
        final r = size.width / 2 - 1;
        final sweep = 0.85 * draw * 2 * math.pi;
        if (sweep <= 0) return;
        canvas.drawArc(
            Rect.fromCircle(center: c, radius: r),
            -math.pi / 2 + rot,
            sweep,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..strokeCap = StrokeCap.round
              ..color = look.ping.withValues(alpha: look.ping.a * breathe));
      case MoneyStepStatus.done || MoneyStepStatus.skipped:
        final at = fx.doneAt;
        final e = still || at == null ? double.infinity : now - at;
        if (e < 0) {
          canvas.drawCircle(c, 2, dot);
          return;
        }
        if (e < _kPopDelay * 2) {
          final close = Curves.easeOut.transform(_unit(e / _kPopDelay));
          final fade = 1 - _unit((e - _kPopDelay) / _kPopDelay);
          canvas.drawArc(
              Rect.fromCircle(center: c, radius: size.width / 2 - 1),
              -math.pi / 2,
              (0.85 + 0.15 * close) * 2 * math.pi,
              false,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.6
                ..strokeCap = StrokeCap.round
                ..color = look.gold.withValues(alpha: fade));
        }
        if (e < _kPopDelay) return;
        final pe = e - _kPopDelay;
        final scale =
            _pop(_unit(pe / _kPop), fx.finalDone ? 1.32 : 1.25, from: 0.6);
        final r = look.signR * scale;
        canvas.drawCircle(
            c, r, Paint()..color = look.gold.withValues(alpha: 0.35));
        final draw = _unit((pe - _kCheckDelay) / _kCheckDraw);
        if (draw > 0) {
          final check = Path()
            ..moveTo(c.dx - 0.42 * r, c.dy + 0.02 * r)
            ..lineTo(c.dx - 0.12 * r, c.dy + 0.32 * r)
            ..lineTo(c.dx + 0.42 * r, c.dy - 0.28 * r);
          final paint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = KuteDogPalette.mascot.furDark;
          if (draw >= 1) {
            canvas.drawPath(check, paint);
          } else {
            for (final m in check.computeMetrics()) {
              canvas.drawPath(m.extractPath(0, m.length * draw), paint);
            }
          }
        }
        _burst(canvas, c, now, fx, look, small: true, radius: look.signR);
      case MoneyStepStatus.fellBack:
        _glyph(canvas, Icons.subdirectory_arrow_right, c, look.signR * 2,
            look.done);
      case MoneyStepStatus.failed:
        final at = fx.failedAt;
        final a = still || at == null ? 1.0 : _unit((now - at) / _kFadeIn);
        if (a <= 0) return;
        _glyph(canvas, Icons.error_outline_rounded, c, look.signR * 2,
            look.failed.withValues(alpha: look.failed.a * a));
    }
  }

  void _glyph(
      Canvas canvas, IconData icon, Offset c, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          inherit: false,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          height: 1,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_SignPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────
// Paint-only helpers
// ─────────────────────────────────────────────────────────────────────

/// Repaints on the clock when [value] changed since the last paint;
/// never rebuilds or relayouts.
abstract class _ClockProxy extends RenderProxyBox {
  _ClockProxy(this._clock);
  Listenable _clock;
  double _painted = 0;

  double value();

  set clock(Listenable v) {
    if (identical(v, _clock)) return;
    if (attached) _clock.removeListener(_tick);
    _clock = v;
    if (attached) _clock.addListener(_tick);
  }

  void _tick() {
    if (value() != _painted) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _clock.addListener(_tick);
  }

  @override
  void detach() {
    _clock.removeListener(_tick);
    super.detach();
  }
}

/// Shakes its child sideways while [dx] says so.
class _Shake extends SingleChildRenderObjectWidget {
  const _Shake({required this.clock, required this.dx, super.child});
  final Listenable clock;
  final double Function() dx;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderShake(clock, dx);

  @override
  void updateRenderObject(BuildContext context, _RenderShake renderObject) =>
      renderObject
        ..clock = clock
        ..dx = dx;
}

class _RenderShake extends _ClockProxy {
  _RenderShake(super.clock, this.dx);
  double Function() dx;

  @override
  double value() => dx();

  @override
  void paint(PaintingContext context, Offset offset) {
    _painted = dx();
    super.paint(context, offset.translate(_painted, 0));
  }
}

/// Scales its child about its centre by [scale] (a station's pop).
class _Scaled extends SingleChildRenderObjectWidget {
  const _Scaled({required this.clock, required this.scale, super.child});
  final Listenable clock;
  final double Function() scale;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScaled(clock, scale);

  @override
  void updateRenderObject(BuildContext context, _RenderScaled renderObject) =>
      renderObject
        ..clock = clock
        ..scale = scale;
}

class _RenderScaled extends _ClockProxy {
  _RenderScaled(super.clock, this.scale);
  double Function() scale;

  @override
  double value() => scale();

  @override
  void paint(PaintingContext context, Offset offset) {
    _painted = scale();
    if (_painted == 1 || child == null) {
      super.paint(context, offset);
      return;
    }
    final c = offset + size.center(Offset.zero);
    final m = Matrix4.translationValues(c.dx, c.dy, 0) *
        Matrix4.diagonal3Values(_painted, _painted, 1) *
        Matrix4.translationValues(-c.dx, -c.dy, 0) as Matrix4;
    context.pushTransform(needsCompositing, Offset.zero, m,
        (context, o) => super.paint(context, offset));
  }
}

/// The thin progress bar, its fill eased by the clock.
class _Bar extends LeafRenderObjectWidget {
  const _Bar({
    required this.clock,
    required this.progress,
    required this.track,
    required this.fill,
    required this.height,
  });
  final Listenable clock;
  final double Function() progress;
  final Color track;
  final Color fill;
  final double height;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBar(clock, progress, track, fill, height);

  @override
  void updateRenderObject(BuildContext context, _RenderBar renderObject) {
    renderObject
      ..clock = clock
      ..progress = progress
      ..track = track
      ..fill = fill;
    if (renderObject.height != height) {
      renderObject
        ..height = height
        ..markNeedsLayout();
    }
    renderObject.markNeedsPaint();
  }
}

class _RenderBar extends RenderBox {
  _RenderBar(this._clock, this.progress, this.track, this.fill, this.height);
  Listenable _clock;
  double Function() progress;
  Color track;
  Color fill;
  double height;
  double _painted = -1;

  set clock(Listenable v) {
    if (identical(v, _clock)) return;
    if (attached) _clock.removeListener(_tick);
    _clock = v;
    if (attached) _clock.addListener(_tick);
  }

  void _tick() {
    if (progress() != _painted) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _clock.addListener(_tick);
  }

  @override
  void detach() {
    _clock.removeListener(_tick);
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      Size(constraints.maxWidth.isFinite ? constraints.maxWidth : 100, height);

  @override
  void performResize() => size = computeDryLayout(constraints);

  @override
  void paint(PaintingContext context, Offset offset) {
    _painted = _unit(progress());
    final canvas = context.canvas;
    final r = Radius.circular(height / 2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(offset & size, r), Paint()..color = track);
    if (_painted > 0) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              offset & Size(math.max(height, size.width * _painted), height),
              r),
          Paint()..color = fill);
    }
  }
}

/// Counts the amounts in its line up from zero while [progress] runs
/// (0..1, null when not counting): the line's own text is painted with
/// the amounts at that point, ease-out. Paint only: the text widget, and
/// what a screen reader hears, stay the line's final words.
class _CountUp extends SingleChildRenderObjectWidget {
  const _CountUp({
    required this.clock,
    required this.progress,
    required this.text,
    required this.style,
    required this.scaler,
    required this.direction,
    super.child,
  });
  final Listenable clock;
  final double? Function() progress;
  final String text;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection direction;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCountUp(clock, progress, text, style, scaler, direction);

  @override
  void updateRenderObject(BuildContext context, _RenderCountUp renderObject) {
    renderObject
      ..clock = clock
      ..progress = progress
      ..text = text
      ..style = style
      ..scaler = scaler
      ..direction = direction;
  }
}

class _RenderCountUp extends RenderProxyBox {
  _RenderCountUp(this._clock, this.progress, this.text, this.style, this.scaler,
      this.direction);
  Listenable _clock;
  double? Function() progress;
  String text;
  TextStyle style;
  TextScaler scaler;
  TextDirection direction;
  bool _counting = false;

  set clock(Listenable value) {
    if (identical(value, _clock)) return;
    if (attached) _clock.removeListener(_tick);
    _clock = value;
    if (attached) _clock.addListener(_tick);
  }

  void _tick() {
    final p = progress();
    if ((p != null && p < 1) || _counting) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _clock.addListener(_tick);
  }

  @override
  void detach() {
    _clock.removeListener(_tick);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final p = progress();
    if (p == null || p >= 1 || child == null) {
      _counting = false;
      super.paint(context, offset);
      return;
    }
    _counting = true;
    final tp = TextPainter(
      text: TextSpan(
          text: moneyCountUpText(text, Curves.easeOutCubic.transform(p)),
          style: style),
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: size.width + 1);
    tp.paint(context.canvas, offset);
    tp.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────
// Counting amounts up
// ─────────────────────────────────────────────────────────────────────

final RegExp _amount =
    RegExp(r'(?<=[\$€£¥]\s?)\d(?:[\d,.]*\d)?|\d(?:[\d,.]*\d)?(?=\s?[€£])');

/// Whether [text] names an amount of money ("$5.30", "5,30 €").
bool moneyCountUpHasAmount(String text) => _amount.hasMatch(text);

/// [text] with each amount at [t] (0..1) of its value, written the way
/// it is written (its decimals and separators): "Moving $8.00" at 0.5 is
/// "Moving $4.00".
@visibleForTesting
String moneyCountUpText(String text, double t) {
  if (t >= 1) return text;
  return text.replaceAllMapped(_amount, (m) {
    final token = m.group(0)!;
    final dec = RegExp(r'^(.*?)([.,])(\d{1,2})$').firstMatch(token);
    String whole;
    String? decSep;
    var decimals = 0;
    if (dec != null && !dec.group(1)!.contains(dec.group(2)!)) {
      whole = dec.group(1)!;
      decSep = dec.group(2);
      decimals = dec.group(3)!.length;
    } else {
      whole = token;
    }
    final group = whole.contains(',')
        ? ','
        : whole.contains('.')
            ? '.'
            : null;
    final digits = whole.replaceAll(RegExp(r'[,.]'), '');
    final value =
        double.tryParse('$digits${decimals > 0 ? '.${dec!.group(3)}' : ''}');
    if (value == null) return token;
    final shown = (value * math.max(0, t)).toStringAsFixed(decimals);
    final parts = shown.split('.');
    var intPart = parts[0];
    if (group != null) {
      final b = StringBuffer();
      for (var i = 0; i < intPart.length; i++) {
        if (i > 0 && (intPart.length - i) % 3 == 0) b.write(group);
        b.write(intPart[i]);
      }
      intPart = b.toString();
    }
    return decimals > 0 ? '$intPart$decSep${parts[1]}' : intPart;
  });
}
