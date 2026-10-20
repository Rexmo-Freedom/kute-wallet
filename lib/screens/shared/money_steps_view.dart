// lib/screens/shared/money_steps_view.dart
//
// The ONE widget that shows a money step graph ([MoneyStepGraph]) under a
// slip's or a sheet's button, and in an Activity detail: the MONEY
// JOURNEY, in the calm look the founder approved on 20 October 2026 (the
// earlier map read "childish and cheap"). One quiet row: the balances the
// money passes through are plain round STATIONS left to right (their own
// marks in their fixed brand colours, never theme tokens, so they read on
// a green Yes or red No slip as on a plain sheet: ₿ on orange, the
// Dollars (USDB) mark, the Investing and Predictions marks; no ring, no
// disc behind), several sources of one leg sit overlapped in their
// column, and a straight hairline CONNECTOR with a small chevron joins
// each column to the next. A station waits at 40% until the money is
// there (55% over the sheet's ink on a slip in a side colour, so it reads
// as a paler mark of its own colour), then shows in full; a small check
// sits on it once its part is
// done, a small red "!" where the money stopped. As a leg runs its
// connector fills orange from the left and the chevron turns orange when
// it lands; a leg's sub-legs (HyperCore → Circle → Arbitrum) are small
// rings on its connector that fill as the orange passes them. The
// destination's own sub-steps (converting, approving, confirming,
// placing, crediting) are a row of small dots under its name: a ring
// while waiting, a softly breathing dot while running, filled once done.
// ONE coin, in the currency of where the money is, glides along the
// running connector a little above it, rests above each station and
// cross-fades into that station's currency, and once everything is done
// sinks into the destination. Sal, small, walks the line behind the coin
// and waits beside the next station while it works. Under the row: one
// status line in the step's own words ("Moving $4.18 from Bitcoin",
// "Confirming balance", "Placed!", or the surface's line saying where
// the money is after a stop), "Taking longer than usual" quietly on its
// right. No progress bar (founder, 2026-10-20): the row already shows how
// far the money is, the status line says the rest. Every line (each leg,
// sub-leg and checkpoint) is a real semantics node in its final words:
// the status line is the current line itself, the others are there
// unseen.
//
// While a step runs and the money waits (held near the end of its
// connector for a bridge, or above the destination while its balance is
// confirmed) the row stays quietly alive, never with bursts, rings or
// borders: the parked coin hovers ±1.5 px, a soft light runs along the
// running connector's orange every ~1.6 s, Sal blinks and sniffs, and the
// working station breathes very slightly (97% to full). Only the row's
// own layers repaint for it.
//
// A record whose steps have all ended (an Activity detail) draws its
// final state at rest (the coin gone, every check on) and replays the
// journey once, quickly (~1.2 s), when the detail opens; never with
// haptics. The haptics for live changes are the ones every steps surface
// had: a selection click as the coin lands at a new station, a light tap
// as a step completes, the money-success beat at the end, the failure
// tap on a stop, only for changes seen live and deduped with the
// surface. Reduce Motion: the same states at once, no glide, walk,
// breath, idle activity or replay; the haptics still play.

import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/asset_icon_provider.dart' show kUsdMarkAsset;
import 'package:kute/screens/shared/side_tint_palette.dart' show isSideTinted;
import 'package:kute/screens/shared/kute_dog_rig.dart';
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
/// formats the graph's dollars. [note] is the one plain line once
/// something stopped (what happened and where the money is), said in the
/// status line; [slow] adds one calm line under it ("Taking longer than
/// expected…", [slowMoveAfter] says when).
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

// The motion's beats, in milliseconds.
const double _kTapDelay = 120; // a finished step's light tap
const double _kDash = 500; // a leg's last stretch into its station
const double _kApproach = 1800; // the fill's way out while a leg works
const double _kHold = 0.78; // how far it gets before the leg lands
const double _kStationFade = 300; // a station coming to full colour
const double _kBadgeFade = 250; // its check or "!" fading in
const double _kSettle = 360; // the coin rising onto a station it reached
const double _kSwap = 420; // the coin's cross-fade into a currency
const double _kSink = 500; // the coin sinking into the destination
const double _kBreath = 2400; // the running checkpoint's dot
const double _kWalk = 420; // one step of Sal's walk
const double _kSalEase = 200; // how quickly Sal closes on his mark
const double _kReplay = 1200;
const double _kPendingAlpha = 0.4;
const double _kPendingAlphaTinted = 0.55;
const double _kHover = 2000; // the parked coin's hover
const double _kGlint = 1600; // the light along a running connector
const double _kWorkBreath = 2400; // the working station's breath
// How long the clock runs on after the last moment (the dash, the
// cross-fade, the sink and Sal's last steps all fit in it); it
// runs on while any step runs.
const double _kRest = 2600;

/// The progress accent: the connectors' fill and the waypoints passed.
const Color _kAccent = Color(0xFFF29B2D);

enum _Outcome { none, success, failure }

enum _Haptic { arrive, check, success, failure }

/// One line's live moments (clock milliseconds), by line key.
class _Fx {
  _Fx(this.status);
  MoneyStepStatus status;
  double? runSince;
  double? doneAt;
  double? failedAt;

  /// How far its stretch was filled when it ended (the dash goes on from
  /// there).
  double litFrom = 0;
  double dashMs = _kDash;
}

/// The view's look, in the screen's units and the surface's colours.
@immutable
class _Look {
  const _Look({
    required this.track,
    required this.stopped,
    required this.failed,
    required this.background,
    required this.pendingAlpha,
    required this.pendingBase,
    required this.stationR,
    required this.waypointR,
    required this.dotR,
    required this.dotGap,
    required this.coinR,
    required this.coinLift,
    required this.gap,
    required this.chevron,
    required this.salSize,
    required this.rowY,
    required this.nameTop,
    required this.nameH,
    required this.dotsGap,
    required this.padX,
    required this.font,
  });

  /// The connectors' and the waiting rings' quiet tone.
  final Color track;

  /// A stopped leg's fill.
  final Color stopped;
  final Color failed;
  final Color background;

  /// A station's opacity until the money is there: a touch higher on a
  /// slip in a side colour, where 40% of a coloured mark sinks into it.
  final double pendingAlpha;

  /// What a waiting station's mark sits on, on a slip in a side colour
  /// (the sheet's ink); null elsewhere.
  final Color? pendingBase;
  final double stationR;
  final double waypointR;
  final double dotR;
  final double dotGap;
  final double coinR;

  /// How far above its line the coin travels.
  final double coinLift;

  /// How far short of a station a connector stops.
  final double gap;
  final double chevron;
  final double salSize;

  /// The stations' centre line, from the map's top (room above it for the
  /// coin and Sal).
  final double rowY;

  /// The names' top, below the icons.
  final double nameTop;
  final double nameH;

  /// From the names' bottom to the checkpoints' dots.
  final double dotsGap;
  final double padX;

  /// The surface's text style (the coin's "$" is written in its font).
  final TextStyle font;

  /// Where the coin rests above a station at [x].
  Offset restAbove(double x) => Offset(x, rowY - stationR - 2.5 - coinR);
}

/// Where everything sits in the row, for one size.
class _Geometry {
  _Geometry(this.size, this.stations, this.columnX, this.gaps, this.gapRoad,
      this.dotsY);
  final Size size;

  /// Each station's icon centre.
  final List<Offset> stations;
  final List<double> columnX;

  /// Each column gap's connector, its start and end x.
  final List<(double, double)> gaps;

  /// The road each gap's connector shows: the coin's (its chain) where
  /// it passes, else the first road across.
  final List<int?> gapRoad;
  final double dotsY;

  static _Geometry of(MoneyJourneyPlan plan, Size size, _Look look) {
    final w = size.width;
    final cols = math.max(1, plan.columns);
    final r = look.stationR;
    final step = 2 * r * 0.62;
    final columnX = [
      for (var c = 0; c < cols; c++)
        cols == 1 ? w / 2 : look.padX + c * (w - 2 * look.padX) / (cols - 1),
    ];
    final rows = List<int>.filled(cols, 1);
    for (final st in plan.stations) {
      rows[_col(st, cols)] = math.max(rows[_col(st, cols)], st.rows);
    }
    final stations = <Offset>[
      for (final st in plan.stations)
        Offset(
            columnX[_col(st, cols)] - (st.rows - 1) * step / 2 + st.row * step,
            look.rowY),
    ];
    double extent(int c) => r + (rows[c] - 1) * step / 2;
    final gaps = [
      for (var g = 0; g + 1 < cols; g++)
        (
          columnX[g] + extent(g) + look.gap,
          columnX[g + 1] - extent(g + 1) - look.gap,
        ),
    ];
    bool crosses(JourneyRoad road, int g) =>
        _col(plan.stations[road.from], cols) <= g &&
        g < _col(plan.stations[road.to], cols);
    final gapRoad = <int?>[
      for (var g = 0; g < gaps.length; g++)
        plan.chain.where((i) => crosses(plan.roads[i], g)).firstOrNull ??
            [
              for (var i = 0; i < plan.roads.length; i++)
                if (crosses(plan.roads[i], g)) i
            ].firstOrNull,
    ];
    final dotsY = look.nameTop + look.nameH + look.dotsGap + look.dotR;
    return _Geometry(size, stations, columnX, gaps, gapRoad, dotsY);
  }

  static int _col(JourneyStation st, int cols) => st.column.clamp(0, cols - 1);

  int colOf(MoneyJourneyPlan plan, int station) =>
      _col(plan.stations[station], columnX.length);

  /// The gap and how far along it road [road] is at [f] (0..1) of its
  /// way, null for a road that crosses no gap.
  (int, double)? gapAt(MoneyJourneyPlan plan, JourneyRoad road, double f) {
    final c0 = colOf(plan, road.from);
    final m = colOf(plan, road.to) - c0;
    if (m <= 0) return null;
    final t = _unit(f) * m;
    final j = math.min(t.floor(), m - 1);
    return (c0 + j, t - j);
  }

  /// The x of road [road]'s line at [f] of its way.
  double tipX(MoneyJourneyPlan plan, JourneyRoad road, double f) {
    final at = gapAt(plan, road, f);
    if (at == null) return stations[road.to].dx;
    final (x0, x1) = gaps[at.$1];
    return x0 + (x1 - x0) * at.$2;
  }

  /// Where the coin is on road [road] at [f] of its way: just above the
  /// line, coming down from above the station it leaves, and over any
  /// column it passes.
  Offset coinOnRoad(
      MoneyJourneyPlan plan, JourneyRoad road, double f, _Look look) {
    final at = gapAt(plan, road, f);
    final from = look.restAbove(stations[road.from].dx);
    if (at == null) {
      return Offset.lerp(from, look.restAbove(stations[road.to].dx), _unit(f))!;
    }
    final (g, local) = at;
    final (x0, x1) = gaps[g];
    final line = Offset(x0 + (x1 - x0) * local, look.rowY - look.coinLift);
    final c0 = colOf(plan, road.from);
    final last = colOf(plan, road.to) - 1;
    final start = g == c0 ? from : look.restAbove(columnX[g]);
    // Into the last station it stays on the line: it settles above the
    // station once the leg landed ([MoneyJourneyPainter]).
    if (local >= 0.5 && g == last) return line;
    final end = look.restAbove(columnX[g + 1]);
    final near = local < 0.5 ? local : 1 - local;
    final blend = Curves.easeInOut.transform(1 - _unit(near / 0.15));
    return Offset.lerp(line, local < 0.5 ? start : end, blend)!;
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
  int spot = 0;

  // Sal: where he stands (x on the map), when he was last painted, and
  // whether he was walking then.
  double? salX;
  double salPaintedAt = 0;
  bool salWalking = false;

  // The coin's hover, 0..1, and when it was last painted.
  double hover = 0;
  double hoverPaintedAt = 0;
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

  /// Something happened now: the clock runs on [_kRest] from here.
  void _moment(double now) => _busyUntil = math.max(_busyUntil, now + _kRest);

  @override
  void initState() {
    super.initState();
    _loadUsdMark();
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

  /// Runs the clock while something moves (a while after the last moment,
  /// and all along while a step runs); under Reduce Motion (or with
  /// tickers off) plays the pending haptics once this frame is drawn
  /// instead.
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
    if (!widget.haptics) return;
    try {
      switch (h) {
        case _Haptic.arrive:
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

    _moment(now);
    if (first) {
      s.outcome = outcome;
      s.outcomeAt = now;
      if (!s.live && !plan.inProgress && lines.isNotEmpty) {
        _setUpReplay(now);
      }
      s.spot = _spotOf(s, now);
      return;
    }
    if (!s.live) {
      s.outcome = outcome;
      return;
    }
    if (cameAlive) {
      s.outcome = _Outcome.none;
      s.outcomeAt = now;
    }

    if (outcome != s.outcome) {
      s.outcome = outcome;
      s.outcomeAt = now;
      switch (outcome) {
        case _Outcome.success:
          // The last check: the success beat in place of its light tap.
          checked = false;
          _schedule(now + _kTapDelay, _Haptic.success);
        case _Outcome.failure:
          _schedule(now, _Haptic.failure);
        case _Outcome.none:
          break;
      }
    }

    // The coin lands somewhere new on its way: a click once its dash ends.
    final spotAfter = _spotOf(s, now + _kDash + 1);
    final landed = spotAfter != spotBefore && spotAfter > s.spot;
    s.spot = math.max(s.spot, spotBefore);
    if (landed && s.outcome == _Outcome.none) {
      _schedule(now + _kDash, _Haptic.arrive);
    }
    if (checked) _schedule(now + _kTapDelay, _Haptic.check);
  }

  /// A finished record opening: the connectors fill in order, then the
  /// checkpoints fill, over about [_kReplay]; the coin and Sal go along.
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
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final keys = widget.keys;
    final s = _scene;
    final plan = s.plan;
    final lines = plan.lines;
    final scaler = MediaQuery.textScalerOf(context);
    final stationR = 14.r;
    s.look = _Look(
      track: c.textTertiary.withValues(alpha: 0.4),
      stopped: c.textTertiary,
      failed: c.error,
      background: c.background,
      pendingAlpha: isSideTinted(c) ? _kPendingAlphaTinted : _kPendingAlpha,
      pendingBase: isSideTinted(c) ? c.textPrimary : null,
      stationR: stationR,
      waypointR: 3.2.r,
      dotR: 3.2.r,
      dotGap: 11.r,
      coinR: 6.5.r,
      coinLift: 9.r,
      gap: 12.r,
      chevron: 3.5.r,
      salSize: 20.r,
      rowY: 30.r,
      nameTop: 30.r + stationR + 4.r,
      nameH: scaler.scale(11.sp) * 1.2,
      dotsGap: 5.r,
      padX: 44.r,
      font: DefaultTextStyle.of(context).style,
    );

    // ── The one status line ──
    // The line at work says itself, in place: the status line IS that
    // line's text, every other line sits there unseen for a screen
    // reader. Words that are no line's own (the surface's line after a
    // stop, "Placed!", a sub-leg's short words) take the place instead.
    final focus = plan.focus;
    int? shown;
    String? status;
    if (widget.note != null) {
      status = widget.note;
    } else if (s.outcome == _Outcome.success && lines.isNotEmpty) {
      if (plan.placeLine != null) {
        status = l10n.moneyJourneyPlaced;
      } else if (lines.last.brief case final brief?) {
        // An Activity detail's compact line ("Bitcoin → Dollars · $9.87")
        // says only its amount: the row above already names the places.
        status = brief;
      } else {
        shown = lines.length - 1;
      }
    } else if (focus != null) {
      final brief = lines[focus].brief;
      if (s.outcome != _Outcome.failure && brief != null) {
        status = brief;
      } else {
        shown = focus;
      }
    }
    final statusStyle = TextStyle(
        color: s.outcome == _Outcome.failure ? c.textPrimary : c.textSecondary,
        fontSize: 13.sp,
        fontWeight: FontWeight.w500,
        height: 1.3);

    Widget sign(int i, MoneyStepStatus status) {
      final word = switch (status) {
        MoneyStepStatus.failed => 'failed',
        MoneyStepStatus.done || MoneyStepStatus.skipped => 'done',
        MoneyStepStatus.fellBack => 'fellback',
        MoneyStepStatus.running => keys.runningWord,
        MoneyStepStatus.waiting => 'waiting',
      };
      return SizedBox.shrink(key: ValueKey('${keys.step}$word-$i'));
    }

    Widget words(int i, {required bool visible}) {
      final line = lines[i];
      return Opacity(
        opacity: visible ? 1 : 0,
        alwaysIncludeSemantics: true,
        child: Semantics(
          key: ValueKey('${keys.step}${line.id ?? i}'),
          container: true,
          child: Row(
            children: [
              sign(i, line.status),
              Flexible(
                child: Text(line.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: statusStyle),
              ),
            ],
          ),
        ),
      );
    }

    final slow = widget.slow && !plan.anyFailed;
    return Padding(
      key: ValueKey(keys.container),
      padding: EdgeInsets.only(top: 4.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The row of stations.
          if (plan.stations.isNotEmpty)
            LayoutBuilder(builder: (context, constraints) {
              final look = s.look;
              final hasDots =
                  plan.destination != null && _dots(plan).isNotEmpty;
              final size = Size(
                  constraints.maxWidth,
                  look.nameTop +
                      look.nameH +
                      (hasDots ? look.dotsGap + 2 * look.dotR : 0) +
                      2.r);
              final geo = s.geo = _Geometry.of(plan, size, look);
              // Its own layer: the stations' fades and the working one's
              // breath repaint the row, never the sheet around it.
              return RepaintBoundary(
                child: SizedBox(
                  key: const ValueKey('money-steps-map'),
                  width: size.width,
                  height: size.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child:
                              CustomPaint(painter: _MapPainter(s, _clock, geo)),
                        ),
                      ),
                      ..._names(context, geo, l10n, scaler),
                      // Right to left, so the left one of an overlapped
                      // column sits on top.
                      for (final i in [
                        for (var i = 0; i < plan.stations.length; i++) i
                      ]..sort((a, b) =>
                          geo.stations[b].dx.compareTo(geo.stations[a].dx)))
                        _station(context, i, geo, l10n),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(
                                painter: MoneyJourneyPainter._(s, _clock, geo)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          // The status line, then, once the move runs longer than
          // expected, its own quiet line under it.
          Padding(
            padding: EdgeInsets.only(top: 6.h),
            child: SizedBox(
              width: double.infinity,
              child: Stack(
                key: const ValueKey('money-steps-words'),
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < lines.length; i++)
                    if (i == shown)
                      words(i, visible: true)
                    else
                      Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: words(i, visible: false)),
                  if (status != null)
                    Text(
                      status,
                      key: ValueKey(widget.note != null
                          ? keys.note
                          : 'money-steps-status'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: statusStyle,
                    )
                  else if (shown == null)
                    Text('', style: statusStyle),
                ],
              ),
            ),
          ),
          if (slow)
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: Text(
                l10n.slipStepTakingLonger,
                key: ValueKey(keys.slow),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.textTertiary, fontSize: 12.sp, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }

  String _nameOf(AppLocalizations l10n, JourneyStation st) =>
      st.label ??
      (st.place == null ? l10n.recipient : moneyPlaceName(l10n, st.place!));

  /// The names under each column: one station's own, or an overlapped
  /// column's together ("Bitcoin · Dollars"), else the first and how
  /// many more ("Bitcoin +2") when that does not fit. Quiet grey until
  /// the money is there. The stations' semantics name them, so these are
  /// only seen.
  List<Widget> _names(BuildContext context, _Geometry geo,
      AppLocalizations l10n, TextScaler scaler) {
    final c = context.colors;
    final s = _scene;
    final plan = s.plan;
    final look = s.look;
    final w = geo.size.width;
    final cols = geo.columnX.length;
    final out = <Widget>[];
    for (var col = 0; col < cols; col++) {
      final members = [
        for (var i = 0; i < plan.stations.length; i++)
          if (geo.colOf(plan, i) == col) i
      ]..sort((a, b) => plan.stations[a].row.compareTo(plan.stations[b].row));
      if (members.isEmpty) continue;
      final x = geo.columnX[col];
      // Its room: from halfway to the column before (or the row's start)
      // to halfway to the next (or the row's end), so names never meet.
      // Centred under its icon when it fits there, else moved in from
      // the row's edge (a long name or large text at an end of the row
      // is not cut short).
      final lo = col == 0 ? 0.0 : (geo.columnX[col - 1] + x) / 2 + 3.r;
      final hi = col == cols - 1 ? w : (x + geo.columnX[col + 1]) / 2 - 3.r;
      final room = math.max(0.0, hi - lo);
      final style = TextStyle(
          color: members.any((i) => _stationArrivedAt(s, i) != null)
              ? c.textSecondary
              : c.textTertiary,
          fontSize: 11.sp,
          fontWeight: FontWeight.w500,
          height: 1.2);
      final names = [for (final i in members) _nameOf(l10n, plan.stations[i])];
      // Measured in the style the Text draws in (the surface's font).
      final drawn = DefaultTextStyle.of(context).style.merge(style);
      double widthOf(String text) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: drawn),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final width = tp.width;
        tp.dispose();
        return width;
      }

      var label = names.join(' · ');
      // An overlapped column's names together only when they fit
      // centred under it; else the first and how many more.
      final centred = math.min(room, 2 * math.min(x - lo, hi - x));
      if (names.length > 1 && widthOf(label) > centred) {
        label = '${names.first} +${names.length - 1}';
      }
      final width = math.min(widthOf(label).ceilToDouble() + 2, room);
      out.add(Positioned(
        left: (x - width / 2).clamp(lo, math.max(lo, hi - width)),
        top: look.nameTop,
        width: width,
        child: ExcludeSemantics(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: style),
        ),
      ));
    }
    return out;
  }

  /// A station: its own mark on its own colour, at 40% until the money is
  /// there, with a small check once its part is done or a small red "!"
  /// where the money stopped. The fades are paint-only.
  Widget _station(
      BuildContext context, int i, _Geometry geo, AppLocalizations l10n) {
    final s = _scene;
    final st = s.plan.stations[i];
    final at = geo.stations[i];
    final look = s.look;
    final r = look.stationR;
    final d = 2 * r;
    Widget disc(Color color, Widget mark) => DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(child: mark),
        );
    final icon = switch (st.place) {
      MoneyPlace.bitcoin => disc(
          KuteDogPalette.mascot.fur,
          Icon(Icons.currency_bitcoin_rounded,
              size: r * 1.35, color: Colors.white)),
      MoneyPlace.dollars =>
        SvgPicture.asset(kUsdMarkAsset, width: d, height: d),
      MoneyPlace.investing => ClipOval(
          child: SvgPicture.asset('lib/assets/hyperliquid-logo.svg',
              width: d, height: d, fit: BoxFit.cover)),
      MoneyPlace.predictions =>
        SvgPicture.asset('lib/assets/polymarket-logo.svg', width: d, height: d),
      null => disc(
          _kOutsideGrey,
          Icon(Icons.arrow_outward_rounded,
              size: r * 1.2, color: Colors.white)),
    };
    final failed = _stationFailedAt(s, i) != null;
    final done = !failed && _stationDoneAt(s, i) != null;
    final badgeR = 5.5.r;
    const ring = 1.5;
    Widget? badge;
    if (failed || done) {
      badge = Container(
        key: ValueKey('money-steps-station-${failed ? 'failed' : 'done'}'
            '-${st.id}'),
        width: 2 * (badgeR + ring),
        height: 2 * (badgeR + ring),
        padding: const EdgeInsets.all(ring),
        decoration:
            BoxDecoration(color: look.background, shape: BoxShape.circle),
        child: DecoratedBox(
          decoration: BoxDecoration(
              color: failed ? AppColors.error : const Color(0xFFF2F4F7),
              shape: BoxShape.circle),
          child: Center(
            child: Icon(
                failed ? Icons.priority_high_rounded : Icons.check_rounded,
                size: badgeR * 1.45,
                color: failed ? Colors.white : const Color(0xFF1D2024)),
          ),
        ),
      );
    }
    final corner = r + r * 0.72 - badgeR - ring;
    return Positioned(
      left: at.dx - r,
      top: at.dy - r,
      width: d,
      height: d,
      child: Semantics(
        key: ValueKey('money-steps-station-${st.id}'),
        label: _nameOf(l10n, st),
        excludeSemantics: true,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // A background-coloured gap where icons overlap.
            Positioned(
              left: -ring,
              top: -ring,
              width: d + 2 * ring,
              height: d + 2 * ring,
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: look.background, shape: BoxShape.circle)),
            ),
            // On a slip in a side colour a waiting mark sits on the
            // sheet's ink, so it reads as a paler mark of its own colour
            // rather than sinking into the green or red.
            if (look.pendingBase case final base?)
              Positioned.fill(
                child: _Fade(
                  clock: _clock,
                  opacity: () =>
                      1 -
                      _fadeIn(s, _stationArrivedAt(s, i), _now, _kStationFade),
                  scale: () => _stationScale(s, i, _now),
                  child: DecoratedBox(
                      decoration:
                          BoxDecoration(color: base, shape: BoxShape.circle)),
                ),
              ),
            Positioned.fill(
              child: _Fade(
                clock: _clock,
                opacity: () => _stationAlpha(s, i, _now),
                scale: () => _stationScale(s, i, _now),
                child: icon,
              ),
            ),
            if (badge != null)
              Positioned(
                left: corner,
                top: d - corner - 2 * (badgeR + ring),
                child: _Fade(
                  clock: _clock,
                  opacity: () => _badgeAlpha(s, i, _now),
                  child: badge,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Reading the scene
// ─────────────────────────────────────────────────────────────────────

/// How far one segment (a line's stretch of a connector) is filled at
/// [now]: all the way once done (gliding there from where it was), most
/// of the way and holding while it runs, where it stopped on a stop.
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
              Curves.easeInOutCubic.transform(_unit(e / f.dashMs));
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

/// Where the coin is along its chain at [now]: the index of the chain
/// road it travels, or the chain's length once it reached its end.
int _spotOf(_Scene s, double now) {
  final chain = s.plan.chain;
  for (var i = 0; i < chain.length; i++) {
    if (_roadLit(s, s.plan.roads[chain[i]], now) < 1) return i;
  }
  return chain.length;
}

/// When road [road] landed (its fill reached the end): negative infinity
/// when it had before the view, null while it has not.
double? _roadArrivedAt(_Scene s, JourneyRoad road) {
  double? latest;
  for (final k in road.segments) {
    if (!s.plan.lines[k].status.satisfies) return null;
    final f = s.fx[s.keys[k]];
    final at =
        f?.doneAt == null ? double.negativeInfinity : f!.doneAt! + f.dashMs;
    latest = latest == null ? at : math.max(latest, at);
  }
  return latest ?? double.negativeInfinity;
}

/// When the money reached station [i] (the first road into it landed):
/// negative infinity when it was there before the view (a source), null
/// while not yet.
double? _stationArrivedAt(_Scene s, int i) {
  final into = s.plan.roads.where((r) => r.to == i);
  if (into.isEmpty) return double.negativeInfinity;
  double? first;
  for (final r in into) {
    final at = _roadArrivedAt(s, r);
    if (at != null) first = first == null ? at : math.min(first, at);
  }
  return first;
}

/// When station [i] finished its part, null while it has not: the
/// destination once every road into it and every checkpoint did, any
/// other once every road out of it landed.
double? _stationDoneAt(_Scene s, int i) {
  final plan = s.plan;
  double? latest;
  void note(double? at) =>
      latest = latest == null ? at : math.max(latest!, at!);
  if (i == plan.destination) {
    for (final r in plan.roads.where((r) => r.to == i)) {
      final at = _roadArrivedAt(s, r);
      if (at == null) return null;
      note(at);
    }
    for (final k in plan.checkpoints) {
      final status = plan.lines[k].status;
      if (status == MoneyStepStatus.fellBack) continue;
      if (!status.satisfies) return null;
      note(s.fx[s.keys[k]]?.doneAt ?? double.negativeInfinity);
    }
    return latest;
  }
  final out = plan.roads.where((r) => r.from == i);
  for (final r in out) {
    final at = _roadArrivedAt(s, r);
    if (at == null) return null;
    note(at);
  }
  return latest;
}

/// When a stop reached station [i] (a road out of it, or a checkpoint at
/// the destination, failed), null when none did.
double? _stationFailedAt(_Scene s, int i) {
  final plan = s.plan;
  double? at;
  void note(int k) {
    if (plan.lines[k].status != MoneyStepStatus.failed) return;
    at = s.fx[s.keys[k]]?.failedAt ?? double.negativeInfinity;
  }

  for (final r in plan.roads) {
    if (r.from != i) continue;
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

/// A fade from [at] over [span], for [now]: 0 before, 1 after (and at
/// once under Reduce Motion or for a moment before the view).
double _fadeIn(_Scene s, double? at, double now, double span) {
  if (at == null) return 0;
  if (s.still || !at.isFinite) return 1;
  return _unit((now - at) / span);
}

double _stationAlpha(_Scene s, int i, double now) =>
    s.look.pendingAlpha +
    (1 - s.look.pendingAlpha) *
        _fadeIn(s, _stationArrivedAt(s, i), now, _kStationFade);

double _badgeAlpha(_Scene s, int i, double now) => _fadeIn(
    s, _stationFailedAt(s, i) ?? _stationDoneAt(s, i), now, _kBadgeFade);

/// Whether checkpoint line [i] shows done at [now] (a replay fills them
/// in order).
bool _doneBy(_Scene s, int i, double now) {
  if (!s.plan.lines[i].status.satisfies) return false;
  final at = s.fx[s.keys[i]]?.doneAt;
  return s.still || at == null || now >= at;
}

/// Whether the journey idles: a step runs, seen live, and nothing has
/// ended yet. The coin hovers, a glint runs along the running connector,
/// Sal sniffs and blinks and the working station breathes. Never under
/// Reduce Motion, and never in a record at rest.
bool _idle(_Scene s) =>
    !s.still &&
    s.live &&
    s.outcome == _Outcome.none &&
    s.plan.lines.any((l) => l.status == MoneyStepStatus.running);

bool _roadRuns(MoneyJourneyPlan plan, JourneyRoad road) =>
    road.segments.any((k) => plan.lines[k].status == MoneyStepStatus.running);

/// The station the money waits on while the journey idles: where the
/// running leg goes (the coin's own first), else the destination while
/// one of its checkpoints runs.
int? _workingStation(_Scene s) {
  if (!_idle(s)) return null;
  final plan = s.plan;
  for (final i in plan.chain) {
    if (_roadRuns(plan, plan.roads[i])) return plan.roads[i].to;
  }
  for (final r in plan.roads) {
    if (_roadRuns(plan, r)) return r.to;
  }
  final cps = plan.checkpoints;
  if (cps.any((k) => plan.lines[k].status == MoneyStepStatus.running)) {
    return plan.destination;
  }
  return null;
}

/// Station [i]'s size now: the working one breathes very slightly
/// (97% to full, from full), every other one sits still.
double _stationScale(_Scene s, int i, double now) {
  if (_workingStation(s) != i) return 1;
  return 1 - 0.03 * (0.5 - 0.5 * math.cos(2 * math.pi * now / _kWorkBreath));
}

/// The checkpoints drawn as dots under the destination: every one but a
/// stage line with its sub-steps under it (they are its dots). A lone
/// checkpoint draws none: the status line already names it.
List<int> _dots(MoneyJourneyPlan plan) {
  final cps = plan.checkpoints;
  final dots = [
    for (var n = 0; n < cps.length; n++)
      if (plan.lines[cps[n]].sub ||
          n + 1 >= cps.length ||
          !plan.lines[cps[n + 1]].sub)
        cps[n]
  ];
  return dots.length < 2 ? const [] : dots;
}

double _unit(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0);

/// The Dollars mark's own green ([kUsdMarkAsset]'s disc).
const Color _kDollarsGreen = Color(0xFF00875A);

/// The Dollars mark ([kUsdMarkAsset]) as a picture, for the coin in
/// Dollars: loaded once for the app's life. Until it is, the coin is its
/// colours and a "\$".
PictureInfo? _usdMark;
bool _usdMarkLoading = false;

void _loadUsdMark() {
  if (_usdMark != null || _usdMarkLoading) return;
  _usdMarkLoading = true;
  unawaited(vg
      .loadPicture(const SvgAssetLoader(kUsdMarkAsset), null)
      .then<void>((p) => _usdMark = p, onError: (Object _) {
    _usdMarkLoading = false;
  }));
}

/// An outside destination's (a recipient's) quiet grey.
const Color _kOutsideGrey = Color(0xFF8E8E93);

/// A balance's own colour (its station's, its coin's). Fixed brand
/// colours, never the theme's: a slip in a side colour turns its status
/// inks into the one contrast ink, and a white Dollars disc with a white
/// "\$" on a green Yes slip was a blank.
Color _placeColor(MoneyPlace? place) => switch (place) {
      MoneyPlace.bitcoin => KuteDogPalette.mascot.fur,
      MoneyPlace.dollars => _kDollarsGreen,
      MoneyPlace.investing => const Color(0xFF97FCE4),
      MoneyPlace.predictions => const Color(0xFF2E5CFF),
      null => _kOutsideGrey,
    };

// ─────────────────────────────────────────────────────────────────────
// The painters
// ─────────────────────────────────────────────────────────────────────

/// Behind the stations: the connectors (quiet, filling orange as their
/// leg runs, a chevron at each end), the waypoints on them, and the
/// destination's checkpoint dots.
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
    final geo = _geo;
    final y = look.rowY;
    Paint stroke(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final track = stroke(look.track);
    final bg = Paint()..color = look.background;
    final idle = _idle(s);

    // ── Connectors and their waypoints ──
    for (var g = 0; g < geo.gaps.length; g++) {
      final (x0, x1) = geo.gaps[g];
      if (x1 - x0 < 2 * look.chevron) continue;
      final r = geo.gapRoad[g];
      final road = r == null ? null : plan.roads[r];
      var local = 0.0;
      var stopped = false;
      if (road != null) {
        final at = geo.gapAt(plan, road, _roadLit(s, road, now));
        if (at != null) {
          local = at.$1 > g ? 1 : (at.$1 < g ? 0 : at.$2);
        }
        stopped = road.segments
            .any((k) => plan.lines[k].status == MoneyStepStatus.failed);
      }
      final lit = stroke(stopped ? look.stopped : _kAccent);
      canvas.drawLine(Offset(x0, y), Offset(x1, y), track);
      if (local > 0) {
        final xl = x0 + (x1 - x0) * local;
        canvas.drawLine(Offset(x0, y), Offset(xl, y), lit);
        if (idle && !stopped && _roadRuns(plan, road!)) {
          _glint(canvas, x0, xl, y, now);
        }
      }
      final ch = look.chevron;
      canvas.drawPath(
          Path()
            ..moveTo(x1 - ch, y - ch)
            ..lineTo(x1, y)
            ..lineTo(x1 - ch, y + ch),
          local >= 1 ? lit : track);
      if (road == null) continue;
      final n = road.segments.length;
      for (var k = 0; k < road.waypoints.length; k++) {
        final frac = (k + 1) / n;
        final at = geo.gapAt(plan, road, frac);
        if (at == null || at.$1 != g) continue;
        final c = Offset(x0 + (x1 - x0) * at.$2, y);
        final line = plan.lines[road.waypoints[k].line];
        final failed = line.status == MoneyStepStatus.failed;
        final passed = !failed && local >= at.$2 - 1e-6;
        canvas.drawCircle(c, look.waypointR, bg);
        canvas.drawCircle(
            c,
            look.waypointR,
            stroke(failed
                ? look.failed
                : passed
                    ? _kAccent
                    : look.track));
        if (passed) {
          canvas.drawCircle(
              c, look.waypointR * 0.42, Paint()..color = _kAccent);
        }
      }
    }

    // ── The destination's checkpoints ──
    final dest = plan.destination;
    if (dest == null) return;
    final dots = _dots(plan);
    if (dots.isEmpty) return;
    final color = _placeColor(plan.stations[dest].place);
    final x = geo.stations[dest].dx - (dots.length - 1) * look.dotGap / 2;
    for (var n = 0; n < dots.length; n++) {
      final i = dots[n];
      final c = Offset(x + n * look.dotGap, geo.dotsY);
      final status = plan.lines[i].status;
      if (status == MoneyStepStatus.failed) {
        canvas.drawCircle(c, look.dotR, Paint()..color = look.failed);
      } else if (_doneBy(s, i, now)) {
        canvas.drawCircle(c, look.dotR, Paint()..color = color);
      } else if (status == MoneyStepStatus.running) {
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color;
        canvas.drawCircle(c, look.dotR - 0.6, p);
        final breath = s.still
            ? 1.0
            : 0.35 +
                0.65 * (0.5 + 0.5 * math.sin(2 * math.pi * now / _kBreath));
        canvas.drawCircle(c, look.dotR * 0.45,
            Paint()..color = color.withValues(alpha: breath));
      } else {
        canvas.drawCircle(
            c,
            look.dotR - 0.6,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = look.track);
      }
    }
  }

  /// A short soft light running along a running connector's orange, out
  /// from the left every [_kGlint], resting a moment between runs.
  static void _glint(
      Canvas canvas, double x0, double xl, double y, double now) {
    final len = xl - x0;
    if (len < 12) return;
    final p = (now % _kGlint) / (_kGlint * 0.75);
    if (p >= 1) return;
    final half = math.min(8.0, len / 3);
    final cx = x0 - half + (len + 2 * half) * Curves.easeInOut.transform(p);
    final a = math.max(x0, cx - half);
    final b = math.min(xl, cx + half);
    if (b - a < 1) return;
    final glow = Colors.white.withValues(alpha: 0.6 * math.sin(math.pi * p));
    canvas.drawLine(
        Offset(a, y),
        Offset(b, y),
        Paint()
          ..strokeWidth = 1.5
          ..shader = LinearGradient(colors: [
            glow.withValues(alpha: 0),
            glow,
            glow.withValues(alpha: 0),
          ]).createShader(Rect.fromLTRB(cx - half, y - 1, cx + half, y + 1)));
  }

  @override
  bool shouldRepaint(_MapPainter old) => true;
}

/// Over the stations: Sal walking the line and the one coin. One painter,
/// repainted by the view's clock.
@visibleForTesting
class MoneyJourneyPainter extends CustomPainter {
  MoneyJourneyPainter._(this._scene, this._clock, this._geo)
      : super(repaint: _clock);

  final _Scene _scene;
  final Animation<double> _clock;
  final _Geometry _geo;

  double get _now => _clock.value * 1000;

  /// Whether Sal is drawn (he always is, once the row has a station).
  bool get travellerShown => _scene.plan.stations.isNotEmpty;

  /// Where Sal stands now (his feet on the line), in the map's
  /// coordinates.
  Offset? get travellerAt {
    final x = _scene.salX;
    return x == null ? null : Offset(x, _scene.look.rowY);
  }

  /// Whether Sal was walking at the last paint.
  bool get walking => _scene.salWalking;

  /// The id of the leg line the coin travels now, null once it rests at
  /// a station (`#stage` on the stage road of a list without a graph).
  String? get travellerRoad {
    final s = _scene;
    final spot = _spotOf(s, _now);
    if (spot >= s.plan.chain.length) return null;
    final road = s.plan.roads[s.plan.chain[spot]];
    return road.line < 0 ? '#stage' : s.plan.lines[road.line].id;
  }

  /// The station the coin is at or heading to, by id.
  String? get travellerStation {
    final s = _scene;
    final plan = s.plan;
    if (plan.stations.isEmpty) return null;
    final spot = _spotOf(s, _now);
    if (plan.chain.isEmpty) {
      return plan.stations[plan.destination ?? 0].id;
    }
    final road = plan.roads[plan.chain[math.min(spot, plan.chain.length - 1)]];
    return plan.stations[road.to].id;
  }

  /// The coin now (where, in which currency, how opaque), null once it
  /// sank into the destination.
  ({Offset at, MoneyPlace? place, double alpha})? get coin {
    final c = _coin(_now);
    return c == null ? null : (at: c.at, place: c.place, alpha: c.alpha);
  }

  /// How far line [id]'s connector (or stretch of it) is filled now,
  /// 0..1.
  double litOf(String id) {
    final s = _scene;
    final i = s.keys.indexOf(id);
    if (i < 0) return 0;
    final road = s.plan.roads.where((r) => r.line == i).firstOrNull;
    return road == null ? _segLit(s, s.fx[id], _now) : _roadLit(s, road, _now);
  }

  /// Whether a finished record is replaying its journey now.
  bool get replaying {
    final at = _scene.replayAt;
    return at != null && _now < at + _kReplay + 600;
  }

  ({Offset at, MoneyPlace? place, double alpha, double scale})? _coin(
      double now) {
    final s = _scene;
    final plan = s.plan;
    final look = s.look;
    final geo = _geo;
    if (plan.stations.isEmpty) return null;
    if (s.outcome == _Outcome.success &&
        (s.still || (!s.live && s.replayAt == null))) {
      return null;
    }
    // Where it is: on the road it travels, or resting above the station
    // it reached (cross-fading into that station's currency as it lands).
    int station;
    JourneyRoad? via;
    Offset? on;
    MoneyPlace? place;
    final chain = plan.chain;
    final spot = _spotOf(s, now);
    if (chain.isEmpty) {
      station = plan.destination ?? 0;
    } else if (spot < chain.length) {
      final road = plan.roads[chain[spot]];
      final f = _roadLit(s, road, now);
      station = road.from;
      if (f > 0) {
        on = geo.coinOnRoad(plan, road, f, look);
        place = plan.stations[road.from].place;
      } else if (spot > 0) {
        via = plan.roads[chain[spot - 1]];
      }
    } else {
      via = plan.roads[chain.last];
      station = via.to;
    }
    var at = on ?? look.restAbove(geo.stations[station].dx);
    place ??= plan.stations[station].place;
    var alpha = 1.0;
    var scale = 1.0;
    final arrived = via == null ? null : _roadArrivedAt(s, via);
    if (on == null && via != null && arrived != null && !s.still) {
      // Just landed: from the line's end up above the station, fading
      // to ~40% and back as it turns into the station's currency.
      final settle = _unit((now - arrived) / _kSettle);
      if (settle < 1) {
        at = Offset.lerp(geo.coinOnRoad(plan, via, 1, look), at,
            Curves.easeInOut.transform(settle))!;
      }
      final t = (now - arrived) / _kSwap;
      if (t >= 0 && t < 1) {
        alpha = 1 - 0.6 * math.sin(math.pi * t);
        if (t < 0.5) place = plan.stations[via.from].place;
      }
    }
    // Done: it sinks into the destination and is gone.
    if (s.outcome == _Outcome.success && on == null) {
      var start = math.max(s.outcomeAt, arrived ?? double.negativeInfinity);
      for (final k in plan.checkpoints) {
        final d = s.fx[s.keys[k]]?.doneAt;
        if (d != null) start = math.max(start, d);
      }
      final t = _unit((now - start - 150) / _kSink);
      if (t >= 1) return null;
      final e = Curves.easeIn.transform(t);
      at = Offset(at.dx, at.dy + (look.rowY - at.dy) * e);
      alpha *= 1 - e;
      scale = 1 - 0.4 * e;
    }
    return (at: at, place: place, alpha: alpha, scale: scale);
  }

  /// Sal's mark: on the line a little behind the coin while its leg
  /// runs, never past ~78% of the leg (beside the next station, where he
  /// waits while it works); at the start of the first line before it
  /// leaves; beside the destination when nothing travels.
  double _salTarget(double now) {
    final s = _scene;
    final plan = s.plan;
    final look = s.look;
    final geo = _geo;
    final half = look.salSize * 0.45;
    if (plan.chain.isEmpty) {
      final dest = geo.stations[plan.destination ?? 0];
      return dest.dx - look.stationR - look.gap - half;
    }
    var k = 0;
    for (var i = 0; i < plan.chain.length; i++) {
      if (_roadLit(s, plan.roads[plan.chain[i]], now) > 0) k = i;
    }
    final road = plan.roads[plan.chain[k]];
    final f = _roadLit(s, road, now);
    final behind = look.coinR + half + 4;
    final start = geo.tipX(plan, road, 0) + half;
    final x = math.min(
        geo.tipX(plan, road, f) - behind, geo.tipX(plan, road, _kHold));
    return math.max(start, x);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = _scene;
    final look = s.look;
    final now = _now;
    final still = s.still;
    if (s.plan.stations.isEmpty) return;

    // ── Sal ──
    final target = _salTarget(now);
    final was = s.salX;
    var x = target;
    if (was != null && !still) {
      final dt = math.max(0.0, now - s.salPaintedAt);
      x = was + (target - was) * (1 - math.exp(-dt / _kSalEase));
      if ((target - x).abs() < 0.3) x = target;
    }
    final walking = !still && was != null && (x - was).abs() > 0.05;
    s.salX = x;
    s.salPaintedAt = now;
    s.salWalking = walking;
    final u = look.salSize / 16;
    KuteDogPose pose;
    if (still) {
      pose = KuteDogPose.neutral;
    } else if (walking) {
      final step = kuteWave(now, _kWalk);
      pose = KuteDogPose(
        bodyBob: -(1.2 / u) * step.abs(),
        pawLeft: 0.6 * math.max(0.0, step),
        pawRight: 0.6 * math.max(0.0, -step),
      );
    } else if (_idle(s)) {
      // Waiting with the money: a blink every 3 s, a small sniff (the
      // head dips and comes back) and a lazy tail.
      pose = KuteDogPose(
        blink: kuteBlink(now % 3000, 2200),
        headBob: 0.45 * kutePulse(now % 3600, 900, 1500),
        headTilt: 0.05 * kuteWave(now, 3600),
        tail: 0.14 * kuteWave(now, 1100),
      );
    } else {
      pose = KuteDogPose(blink: kuteBlink(now % 4200, 3000));
    }
    paintKuteDog(canvas,
        origin: Offset(x - 8 * u, look.rowY - 0.75 - 15 * u),
        unit: u,
        pose: pose,
        palette: KuteDogPalette.mascot);

    // ── The coin ──
    final c = _coin(now);
    // Parked while a step runs (above a station, or held near the end of
    // its connector), it hovers ±1.5 px; the hover eases in and out so
    // it never jumps.
    final dt = math.max(0.0, now - s.hoverPaintedAt);
    s.hoverPaintedAt = now;
    var parked = false;
    if (c != null && _idle(s)) {
      final before = _coin(now - 80);
      parked = before != null && (before.at - c.at).distance < 0.4;
    }
    s.hover += ((parked ? 1.0 : 0.0) - s.hover) * (1 - math.exp(-dt / 300));
    if (still) s.hover = 0;
    if (c == null || c.alpha <= 0) return;
    final hover =
        s.hover * 1.5 * math.sin(2 * math.pi * (now % _kHover) / _kHover);
    final r = look.coinR * c.scale;
    final at = c.at.translate(0, hover);
    final fill = _placeColor(c.place);
    final a = c.alpha;
    canvas.drawCircle(
        at.translate(0, 1),
        r,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.16 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    // In Dollars it is the Dollars mark itself, scaled down.
    final mark = c.place == MoneyPlace.dollars ? _usdMark : null;
    if (mark != null && mark.size.width > 0 && mark.size.height > 0) {
      final box = Rect.fromCircle(center: at, radius: r);
      if (a < 1) {
        canvas.saveLayer(
            box.inflate(1), Paint()..color = Colors.white.withValues(alpha: a));
      } else {
        canvas.save();
      }
      canvas
        ..translate(box.left, box.top)
        ..scale(box.width / mark.size.width, box.height / mark.size.height)
        ..drawPicture(mark.picture)
        ..restore();
      return;
    }
    canvas.drawCircle(at, r, Paint()..color = fill.withValues(alpha: a));
    canvas.drawCircle(
        at,
        r - 1.3 * c.scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.white.withValues(alpha: 0.35 * a));
    final ink = c.place == MoneyPlace.investing
        ? const Color(0xFF0E2422)
        : Colors.white;
    final glyph = switch (c.place) {
      MoneyPlace.bitcoin => Icons.currency_bitcoin_rounded,
      null => Icons.arrow_outward_rounded,
      _ => null,
    };
    final tp = TextPainter(
      text: TextSpan(
        text: glyph == null ? '\$' : String.fromCharCode(glyph.codePoint),
        style: TextStyle(
          inherit: false,
          fontFamily: glyph?.fontFamily ?? look.font.fontFamily,
          fontFamilyFallback:
              glyph == null ? look.font.fontFamilyFallback : null,
          package: glyph?.fontPackage,
          fontSize: r * (glyph == null ? 1.25 : 1.4),
          fontWeight: FontWeight.w800,
          height: 1,
          color: ink.withValues(alpha: a),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(MoneyJourneyPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────
// Paint-only helpers
// ─────────────────────────────────────────────────────────────────────

/// Paints its child at [opacity] (and [scale] about its centre, when
/// given), repainting on the clock when either changed since the last
/// paint; never rebuilds or relayouts.
class _Fade extends SingleChildRenderObjectWidget {
  const _Fade(
      {required this.clock, required this.opacity, this.scale, super.child});
  final Listenable clock;
  final double Function() opacity;
  final double Function()? scale;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFade(clock, opacity, scale);

  @override
  void updateRenderObject(BuildContext context, _RenderFade renderObject) {
    renderObject
      ..clock = clock
      ..opacity = opacity
      ..scale = scale
      ..markNeedsPaint();
  }
}

class _RenderFade extends RenderProxyBox {
  _RenderFade(this._clock, this.opacity, this.scale);
  Listenable _clock;
  double Function() opacity;
  double Function()? scale;
  double _painted = -1;
  double _paintedScale = 1;
  final LayerHandle<TransformLayer> _transform = LayerHandle();

  set clock(Listenable v) {
    if (identical(v, _clock)) return;
    if (attached) _clock.removeListener(_tick);
    _clock = v;
    if (attached) _clock.addListener(_tick);
  }

  double _scaleNow() => scale?.call() ?? 1;

  void _tick() {
    if (opacity() != _painted || _scaleNow() != _paintedScale) {
      markNeedsPaint();
    }
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
  void dispose() {
    _transform.layer = null;
    super.dispose();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  void _paintFaded(PaintingContext context, Offset offset) {
    layer = context.pushOpacity(offset, (_painted * 255).round(), super.paint,
        oldLayer: layer as OpacityLayer?);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _painted = _unit(opacity());
    _paintedScale = _scaleNow();
    if (child == null || _painted <= 0) {
      layer = null;
      _transform.layer = null;
      return;
    }
    if (_paintedScale == 1) {
      _transform.layer = null;
      _paintFaded(context, offset);
      return;
    }
    final k = _paintedScale;
    final c = size.center(Offset.zero);
    final m = Matrix4.diagonal3Values(k, k, 1)
      ..setTranslationRaw(c.dx * (1 - k), c.dy * (1 - k), 0);
    _transform.layer = context.pushTransform(
        needsCompositing, offset, m, _paintFaded,
        oldLayer: _transform.layer);
  }
}
