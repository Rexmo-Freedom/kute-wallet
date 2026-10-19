// lib/screens/shared/money_steps_view.dart
//
// The ONE widget that shows a money step graph ([MoneyStepGraph]) as the
// staged sub-steps under a slip's or a sheet's button: every leg on its
// own line, completing on its own ("Moving $8.00 from Bitcoin" → "Moved
// $8.00 from Bitcoin ✓"), the venue's readiness as a stage line with its
// sub-steps indented under it ("Getting your prediction ready" →
// "Converting to pUSD", "Confirming balance"), then the order ("Placing
// $15 on Yes") or the purchase ("Buying $5.00 of Bitcoin", "Arriving in
// Bitcoin"). The `SlipFundingSteps` look: the note's type and colours,
// its small spinner while running, a check once done, the slips' error
// sign when failed. No new chrome. The stage and its sub-steps read as a
// tree (founder, 19 October 2026): a thin connector in the lines' quiet
// colour from the stage's sign down, an elbow into each sub-step's sign
// (├, └ on the last), drawn behind the lines; nothing else changes.
// Live, the tree moves (founder, 19 October 2026: "more fun and better
// animation"; [MoneyStepsView]): Sal rides the line to the running step,
// rings draw, checks pop, the last one celebrates, a stop shakes, each
// with its haptic. Every steps surface draws this one tree: the bet and
// order slips (`SlipFundingSteps`, with or without a graph), Move money,
// Buy bitcoin and the Send's venue cash (`MoveStepsSection`), Rebalance,
// and the Activity details.

import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/kute_state.dart';
import 'package:kute/screens/shared/kute_dog_rig.dart';
import 'package:kute/screens/shared/kute_mascot.dart' show kuteMascotPose;
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/success_feedback.dart'
    show moneyFailureFeedback, moneyStepsSuccessFeedback;
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/shared/kute_motion.dart' show kuteReduceMotion;

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

/// One rendered line: its words, its state, and whether it is a
/// sub-step (indented under its stage).
@immutable
class MoneyStepLine {
  const MoneyStepLine(this.text, this.status, {this.sub = false, this.id});
  final String text;
  final MoneyStepStatus status;
  final bool sub;
  final String? id;
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
/// without a graph), so every steps surface draws the one tree and each
/// still answers to its own names.
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

/// The graph as the staged sub-steps (see the file header). [note] is
/// the one plain line under them once something stopped (what happened
/// and where the money is); [slow] adds "Taking longer than usual".
///
/// Live, the tree moves (founder, 19 October 2026: "more fun and better
/// animation"): Sal, the mascot, rides the line to the step running now
/// and hops as he lands there; the line he passed fills in a light done
/// colour behind him; the running step's ring draws itself and breathes;
/// a finished step's ring closes, then it pops into a filled circle with
/// a drawn check and a small burst; amounts count up the first time a
/// running line shows them. The last check pops bigger, Sal cheers and
/// hops away, and the tree's lines settle into the done colour. A stop
/// shakes its line, its sign fades in, and Sal sits there dimmed. Each
/// moment is felt: a selection click as Sal lands, a light tap per check,
/// the money-success beat on the last one ([moneyStepsSuccessFeedback]),
/// the failure tap on a stop ([moneyFailureFeedback]); only for changes
/// seen live, never for lines that were already done when the view
/// appeared. A record whose steps have all ended (an Activity detail)
/// draws its final state, still. Reduce Motion: the same states at once,
/// no glide, hop, burst or shake; the haptics still play.
///
/// [haptics] false leaves the feel to the surface (a band that already
/// plays each landing); [failureHaptic] false leaves the failure tap to a
/// caller that plays it for the same stop.
class MoneyStepsView extends StatefulWidget {
  const MoneyStepsView({
    super.key,
    required this.lines,
    this.slow = false,
    this.note,
    this.haptics = true,
    this.failureHaptic = true,
    this.keys = MoneyStepsKeys.money,
  });

  final List<MoneyStepLine> lines;
  final bool slow;
  final String? note;
  final bool haptics;
  final bool failureHaptic;
  final MoneyStepsKeys keys;

  @override
  State<MoneyStepsView> createState() => _MoneyStepsViewState();
}

// The choreography's beats, in milliseconds.
const double _kRingClose = 120;
const double _kRingFade = 120;
const double _kPop = 320;
const double _kCheckDelay = 60;
const double _kCheckDraw = 220;
const double _kBurst = 420;
const double _kFinalBurst = 560;
const double _kArrive = 250; // the glide's spring first reaches the step
const double _kGlide = 900;
const double _kHop = 300;
const double _kRingDraw = 500;
const double _kCountUp = 600;
const double _kShake = 300;
const double _kFadeIn = 200;
const double _kDim = 250;
const double _kExit = 1000;
const double _kSettle = 500;
const double _kBusy = 1500;
const double _kDimAlpha = 0.35;

enum _Outcome { none, success, failure }

enum _Haptic { arrive, check, success, failure }

/// One line's live moments (clock milliseconds), by line id.
class _LineFx {
  _LineFx(this.status);
  MoneyStepStatus status;
  double? runSince;
  double? doneAt;
  bool doneBig = false;
  bool finalDone = false;
  double? failedAt;
  double? countFrom;
}

/// The view's look, in the screen's units and the surface's colours.
@immutable
class _Look {
  const _Look({
    required this.quiet,
    required this.done,
    required this.failed,
    required this.signR,
    required this.trunkX,
    required this.indent,
    required this.salSize,
    required this.salRing,
    required this.smallRing,
    required this.shake,
    required this.drop,
    required this.rise,
    required this.trail,
    required this.reach,
    required this.reachFinal,
    required this.dot,
    required this.dotFinal,
  });

  final Color quiet;
  final Color done;
  final Color failed;
  final double signR;
  final double trunkX;
  final double indent;
  final double salSize;
  final double salRing;
  final double smallRing;
  final double shake;
  final double drop;
  final double rise;
  final double trail;
  final double reach;
  final double reachFinal;
  final double dot;
  final double dotFinal;

  /// The light done colour the line fills in behind Sal.
  Color get light => Color.lerp(quiet, done, 0.55)!;
}

/// What the painter and the lines' paint-only effects read: the lines,
/// their moments, where each line sits, and the traveller.
class _Scene {
  List<MoneyStepLine> lines = const [];
  List<String> order = const [];
  final Map<String, _LineFx> fx = {};
  final Map<String, RenderBox> anchors = {};
  RenderBox? root;
  bool live = false;
  bool still = false;
  late _Look look;

  String? target;
  bool salShown = false;
  double salEnterAt = 0;
  double? glideAt;
  Offset? glideFrom;
  Offset? lastSal;
  Offset? exitFrom;
  _Outcome outcome = _Outcome.none;
  double outcomeAt = 0;
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

  @override
  void initState() {
    super.initState();
    _sync(first: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scene.still = kuteReduceMotion(context);
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

  bool _needsTick(double now) =>
      !_scene.still &&
      (_events.isNotEmpty ||
          now < _busyUntil ||
          _scene.fx.values.any((f) => f.status == MoneyStepStatus.running));

  /// Runs the clock while something moves; under Reduce Motion (or with
  /// tickers off) plays the pending haptics once this frame is drawn.
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

  static String? _targetOf(List<MoneyStepLine> lines, List<String> keys) {
    for (final want in const [
      MoneyStepStatus.failed,
      MoneyStepStatus.running,
      MoneyStepStatus.waiting,
    ]) {
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].status != want) continue;
        // A stage running: Sal rides on down to its sub-step at work.
        if (!lines[i].sub) {
          for (var j = i + 1; j < lines.length && lines[j].sub; j++) {
            if (lines[j].status == want) return keys[j];
          }
        }
        return keys[i];
      }
    }
    return null;
  }

  void _enter(String? target, double now) {
    final s = _scene;
    s.target = target;
    s.salShown = target != null;
    s.salEnterAt = now;
    s.glideAt = now;
    s.glideFrom = null;
    s.exitFrom = null;
  }

  /// Brings the scene up to [widget.lines]: records each live change's
  /// moment and schedules its haptic. The first build only records where
  /// things stand.
  void _sync({required bool first}) {
    final s = _scene;
    final now = _now;
    final lines = widget.lines;
    final keys = [for (var i = 0; i < lines.length; i++) _lineKey(lines[i], i)];
    final inProgress = lines.any((l) => !l.status.ended);
    final failed = lines.any((l) => l.status == MoneyStepStatus.failed);
    final outcome = failed
        ? _Outcome.failure
        : !inProgress && lines.any((l) => l.status == MoneyStepStatus.done)
            ? _Outcome.success
            : _Outcome.none;

    var cameAlive = false;
    if (first) {
      s.live = inProgress;
    } else if (!s.live && inProgress) {
      // A record that runs again (a retry on the same surface).
      s.live = true;
      cameAlive = true;
    }
    final animate = s.live;

    var changed = false;
    var checked = false;
    final justDone = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final k = keys[i];
      final fx = s.fx[k];
      if (fx == null) {
        final n = _LineFx(l.status);
        // A line that shows up running counts its amount up and draws its
        // ring; one that shows up already ended just is.
        if (animate && !l.status.ended) {
          if (l.status == MoneyStepStatus.running) n.runSince = now;
          if (moneyCountUpHasAmount(l.text)) n.countFrom = now;
          changed = true;
        }
        s.fx[k] = n;
        continue;
      }
      if (fx.status == l.status) continue;
      if (animate && !first) {
        changed = true;
        switch (l.status) {
          case MoneyStepStatus.done || MoneyStepStatus.skipped:
            fx.doneAt = now;
            fx.doneBig = s.salShown && s.target == k;
            fx.failedAt = null;
            checked = true;
            justDone.add(k);
          case MoneyStepStatus.running:
            fx.runSince = now;
            fx.doneAt = null;
            fx.failedAt = null;
          case MoneyStepStatus.failed:
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
    s.lines = lines;
    s.order = keys;

    if (first) {
      s.outcome = outcome;
      s.outcomeAt = now;
      if (s.live) {
        _enter(_targetOf(lines, keys), now);
        _busyUntil = now + _kBusy;
      }
      return;
    }
    if (!s.live) {
      s.outcome = outcome;
      return;
    }
    if (cameAlive) {
      s.outcome = _Outcome.none;
      _enter(null, now);
    }

    if (outcome != s.outcome) {
      changed = true;
      s.outcome = outcome;
      s.outcomeAt = now;
      switch (outcome) {
        case _Outcome.success:
          // The last check: a bigger pop and burst, and the success beat
          // in place of its light tap.
          final last = keys.lastWhere(justDone.contains, orElse: () => '');
          s.fx[last]?.finalDone = true;
          s.exitFrom = null;
          checked = false;
          _schedule(now + _kRingClose, _Haptic.success);
        case _Outcome.failure:
          _schedule(now, _Haptic.failure);
        case _Outcome.none:
          break;
      }
    }

    if (s.outcome != _Outcome.success) {
      final next = _targetOf(lines, keys);
      if (next != s.target) {
        changed = true;
        if (!s.salShown || s.target == null) {
          _enter(next, now);
        } else {
          // Sal leaves once the step he sat on closed its ring.
          final leaving = s.fx[s.target!];
          final start = leaving?.doneAt == now ? now + _kRingClose : now;
          s.glideFrom = s.lastSal;
          s.glideAt = start;
          s.target = next;
          s.salShown = next != null;
          if (next != null && s.outcome == _Outcome.none) {
            _schedule(start + _kArrive, _Haptic.arrive);
          }
        }
      }
    }
    if (checked) _schedule(now + _kRingClose, _Haptic.check);
    if (changed) _busyUntil = math.max(_busyUntil, now + _kBusy);
  }

  double _shakeDx(String key) {
    final s = _scene;
    final at = s.fx[key]?.failedAt;
    if (s.still || at == null) return 0;
    return _shakeAt(s.look.shake, _now - at);
  }

  double? _countProgress(String key) {
    final s = _scene;
    final from = s.fx[key]?.countFrom;
    if (s.still || from == null) return null;
    return ((_now - from) / _kCountUp).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final keys = widget.keys;
    final lines = widget.lines;
    _scene.look = _Look(
      quiet: c.textTertiary,
      done: c.textSecondary,
      failed: c.textPrimary,
      signR: 7.r,
      trunkX: 6.5.r,
      indent: 22.w,
      salSize: 20.r,
      salRing: 12.r,
      smallRing: 6.r,
      shake: 4.r,
      drop: 16.r,
      rise: 14.r,
      trail: 2.2.r,
      reach: 9.r,
      reachFinal: 13.r,
      dot: 1.4.r,
      dotFinal: 1.7.r,
    );
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    Widget lead(int i, MoneyStepStatus status) {
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

    final anyFailed = lines.any((l) => l.status == MoneyStepStatus.failed);
    return Padding(
      key: ValueKey(keys.container),
      padding: EdgeInsets.only(top: 10.h),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          RepaintBoundary(
            child: _Anchor(
              scene: _scene,
              id: null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lines.length; i++)
                    _treeBranch(i, c.textTertiary, () {
                      final line = lines[i];
                      final k = _lineKey(line, i);
                      final style = TextStyle(
                        // The step running now reads at full weight and
                        // colour; the ones still to come stay quiet.
                        color: switch (line.status) {
                          MoneyStepStatus.failed ||
                          MoneyStepStatus.running =>
                            c.textPrimary,
                          MoneyStepStatus.waiting => c.textTertiary,
                          _ => c.textSecondary,
                        },
                        fontSize: (line.sub ? 12 : 13).sp,
                        height: 1.35,
                        fontWeight: line.status == MoneyStepStatus.running
                            ? FontWeight.w600
                            : FontWeight.w400,
                      );
                      return _Anchor(
                        scene: _scene,
                        id: k,
                        child: _Shake(
                          clock: _clock,
                          dx: () => _shakeDx(k),
                          child: Padding(
                            key: ValueKey('${keys.step}${line.id ?? i}'),
                            padding: EdgeInsets.only(
                                top: 3.h,
                                bottom: 3.h,
                                left: line.sub ? 22.w : 0),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 22.w,
                                  child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: lead(i, line.status)),
                                ),
                                Flexible(
                                  child: _CountUp(
                                    clock: _clock,
                                    progress: () => _countProgress(k),
                                    text: line.text,
                                    style: base.merge(style),
                                    scaler: scaler,
                                    direction: direction,
                                    child: Text(line.text, style: style),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }()),
                  if (widget.slow && !anyFailed)
                    Padding(
                      padding: EdgeInsets.only(top: 4.h, left: 22.w),
                      child: Text(
                        context.l10n.slipStepTakingLonger,
                        key: ValueKey(keys.slow),
                        style: TextStyle(
                            color: c.textTertiary,
                            fontSize: 12.sp,
                            height: 1.35),
                      ),
                    ),
                  if (widget.note case final line?)
                    Padding(
                      padding: EdgeInsets.only(top: 6.h),
                      child: Text(
                        line,
                        key: ValueKey(keys.note),
                        style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13.sp,
                            height: 1.35),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // The motion layer: signs, Sal, the fill, the trail and the
          // bursts, one painter on its own layer, repainted by the clock.
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: MoneyStepsMotionPainter._(_scene, _clock),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Line [i] with its part of the tree drawn behind it: a stage line
  /// that has sub-steps under it starts the connector below its sign;
  /// each sub-step carries it on, with an elbow into its own sign (├,
  /// └ on the last). Any other line is left as it is.
  Widget _treeBranch(int i, Color color, Widget row) {
    final lines = widget.lines;
    final role = moneyStepTreeRole(lines, i);
    if (role == null) return row;
    return CustomPaint(
      key: ValueKey('money-step-tree-${lines[i].id ?? i}'),
      painter: MoneyStepTreePainter(
        role: role,
        color: color,
        trunkX: 6.5.r,
        indent: 22.w,
        signHalf: 7.r,
      ),
      child: row,
    );
  }
}

/// Where line [i] of [lines] sits in the steps' tree; null when it is not
/// in one (a line with no sub-steps under it).
MoneyStepTreeRole? moneyStepTreeRole(List<MoneyStepLine> lines, int i) {
  if (lines[i].sub) {
    final last = i + 1 >= lines.length || !lines[i + 1].sub;
    return last ? MoneyStepTreeRole.lastChild : MoneyStepTreeRole.child;
  }
  if (i + 1 < lines.length && lines[i + 1].sub) {
    return MoneyStepTreeRole.parent;
  }
  return null;
}

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

/// The thin connector of the steps' tree, drawn in the lines' own quiet
/// colour behind one line: [trunkX] is the centre of the stage line's
/// sign, [indent] where a sub-step's sign starts, [signHalf] half a
/// sign's height (the trunk leaves a stage line just below it). No box,
/// no fill.
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
// Motion
// ─────────────────────────────────────────────────────────────────────

/// A soft spring (damping 0.6, a little under 10% overshoot) from 0 to 1
/// over [t] seconds; it first reaches 1 at about [_kArrive].
double _spring(double t) {
  const z = 0.6;
  const w = 11.1;
  final wd = w * math.sqrt(1 - z * z);
  return 1 -
      math.exp(-z * w * t) *
          (math.cos(wd * t) + (z * w / wd) * math.sin(wd * t));
}

/// The check's pop: 0.5 up to [peak], then back to 1.
double _pop(double p, double peak) {
  if (p <= 0) return 0.5;
  if (p >= 1) return 1;
  if (p < 0.55) {
    return 0.5 + (peak - 0.5) * Curves.easeOutCubic.transform(p / 0.55);
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

/// The route from [from] to [to] along the tree: out to the trunk at
/// [trunkX], along it, and into [to].
List<Offset> _route(Offset from, Offset to, double trunkX) {
  final pts = <Offset>[from];
  void add(Offset p) {
    if ((pts.last - p).distance > 0.01) pts.add(p);
  }

  add(Offset(trunkX, from.dy));
  add(Offset(trunkX, to.dy));
  add(to);
  return pts;
}

/// The point [s] of the way along [pts] (past the end along its last
/// segment, for the spring's overshoot).
Offset _along(List<Offset> pts, double s) {
  if (pts.length < 2) return pts.last;
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += (pts[i] - pts[i - 1]).distance;
  }
  if (total <= 0) return pts.last;
  var d = s * total;
  for (var i = 1; i < pts.length; i++) {
    final seg = pts[i] - pts[i - 1];
    final len = seg.distance;
    if (d <= len || i == pts.length - 1) {
      return pts[i - 1] + seg / len * d;
    }
    d -= len;
  }
  return pts.last;
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

/// The steps' motion layer (see [MoneyStepsView]): the fill behind Sal,
/// his trail, Sal himself, every line's sign (ring, check, stop sign,
/// route change) and the bursts. One painter, repainted by the view's
/// clock; the lines themselves never rebuild for it.
@visibleForTesting
class MoneyStepsMotionPainter extends CustomPainter {
  MoneyStepsMotionPainter._(this._scene, this._clock) : super(repaint: _clock);

  final _Scene _scene;
  final Animation<double> _clock;

  /// Whether Sal is drawn now.
  bool get travellerShown => _salAlive(_clock.value * 1000);

  /// The line Sal rides to (or sits at), by id.
  String? get travellerTarget => _scene.target;

  /// How far line [id] is shaken sideways now (a stop's shake).
  double shakeOf(String id) {
    final at = _scene.fx[id]?.failedAt;
    if (_scene.still || at == null) return 0;
    return _shakeAt(_scene.look.shake, _clock.value * 1000 - at);
  }

  bool _salAlive(double now) {
    final s = _scene;
    if (!s.live || !s.salShown || s.target == null) return false;
    if (s.outcome == _Outcome.success) {
      return !s.still && now < s.outcomeAt + _kExit;
    }
    return true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = _scene;
    final root = s.root;
    if (root == null || !root.attached) return;
    final look = s.look;
    final now = _clock.value * 1000;
    final still = s.still;

    final rows = <String, Rect>{};
    final nodes = <String, Offset>{};
    for (var i = 0; i < s.order.length && i < s.lines.length; i++) {
      final k = s.order[i];
      final box = s.anchors[k];
      if (box == null || !box.attached || !box.hasSize) continue;
      final o = box.localToGlobal(Offset.zero, ancestor: root);
      final r = o & box.size;
      rows[k] = r;
      final failedAt = s.fx[k]?.failedAt;
      final dx = still || failedAt == null
          ? 0.0
          : _shakeAt(look.shake, now - failedAt);
      nodes[k] = Offset(
          r.left + (s.lines[i].sub ? look.indent : 0) + look.signR + dx,
          r.center.dy);
    }

    // ── Sal's place ──
    Offset? sal;
    List<Offset>? route;
    double glideE = -1;
    final target = s.target;
    final to = target == null ? null : nodes[target];
    final salAlive = _salAlive(now) && to != null;
    if (salAlive) {
      if (s.outcome == _Outcome.success) {
        sal = s.exitFrom ??= s.lastSal ?? to;
      } else if (still) {
        sal = to;
      } else {
        final g = s.glideAt;
        if (g == null) {
          sal = to;
        } else if (now < g) {
          sal = s.glideFrom ?? to;
        } else {
          glideE = now - g;
          if (glideE >= _kGlide) {
            sal = to;
          } else {
            final from = s.glideFrom ?? to.translate(0, -look.drop);
            route = _route(from, to, rows[target]!.left + look.trunkX);
            sal = _along(route, _spring(glideE / 1000));
          }
        }
      }
      if (s.outcome != _Outcome.success) s.lastSal = sal;
    }

    // ── The line filling in behind him ──
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    double? fillY;
    var fillX = double.negativeInfinity;
    var settle = 0.0;
    if (s.outcome == _Outcome.success) {
      if (still || !s.live || now >= s.outcomeAt + _kRingClose) {
        fillY = double.infinity;
        settle =
            still || !s.live ? 1 : _unit((now - s.outcomeAt - 200) / _kSettle);
      } else if (sal != null) {
        fillY = sal.dy;
        fillX = sal.dx;
      }
    } else if (sal != null) {
      fillY = sal.dy;
      fillX = sal.dx;
    } else if (s.outcome == _Outcome.failure) {
      for (var i = 0; i < s.lines.length; i++) {
        if (s.lines[i].status == MoneyStepStatus.failed) {
          fillY = nodes[s.order[i]]?.dy;
          break;
        }
      }
    }
    if (fillY != null) {
      stroke.color = Color.lerp(look.light, look.done, settle)!;
      const far = 1e5;
      final clip = Path()
        ..addRect(Rect.fromLTRB(-far, -far, far, fillY))
        ..addRect(Rect.fromLTRB(
            -far, fillY - 2, fillX.isFinite ? fillX : -far, fillY + 2));
      canvas.save();
      if (fillY.isFinite) canvas.clipPath(clip);
      for (var i = 0; i < s.lines.length; i++) {
        final role = moneyStepTreeRole(s.lines, i);
        final r = rows[s.order[i]];
        if (role == null || r == null) continue;
        canvas.save();
        canvas.translate(r.left, r.top);
        _paintTreeBranch(
            canvas, r.size, role, stroke, look.trunkX, look.indent, look.signR);
        canvas.restore();
      }
      canvas.restore();
    }

    // ── His brief trail ──
    if (route != null && glideE >= 0 && glideE < 450) {
      final fade = 1 - _unit((glideE - 250) / 200);
      final dot = Paint()..style = PaintingStyle.fill;
      for (var k = 1; k <= 5; k++) {
        final te = glideE - k * 22;
        if (te < 0) break;
        final p = _along(route, _spring(te / 1000));
        dot.color = look.light
            .withValues(alpha: look.light.a * 0.55 * (1 - k / 6) * fade);
        canvas.drawCircle(p, look.trail * (1 - k / 7), dot);
      }
    }

    // ── Sal ──
    if (salAlive && sal != null) {
      _paintSal(canvas, sal, now, glideE);
    }

    // ── The signs ──
    for (var i = 0; i < s.lines.length; i++) {
      final k = s.order[i];
      final c = nodes[k];
      final fx = s.fx[k];
      if (c == null || fx == null) continue;
      switch (s.lines[i].status) {
        case MoneyStepStatus.running:
          final big = salAlive && k == target;
          _paintRing(
              canvas, c, big ? look.salRing : look.smallRing, now, fx.runSince);
        case MoneyStepStatus.done || MoneyStepStatus.skipped:
          _paintDone(canvas, c, now, fx);
        case MoneyStepStatus.fellBack:
          _glyph(canvas, Icons.subdirectory_arrow_right, c, look.signR * 2,
              look.done);
        case MoneyStepStatus.failed || MoneyStepStatus.waiting:
          break;
      }
    }
    // The stop's sign last, over a dimmed Sal.
    for (var i = 0; i < s.lines.length; i++) {
      if (s.lines[i].status != MoneyStepStatus.failed) continue;
      final k = s.order[i];
      final c = nodes[k];
      if (c == null) continue;
      final at = s.fx[k]?.failedAt;
      final a = still || at == null ? 1.0 : _unit((now - at) / _kFadeIn);
      if (a <= 0) continue;
      _glyph(canvas, Icons.error_outline_rounded, c, look.signR * 2,
          look.failed.withValues(alpha: look.failed.a * a));
    }
  }

  void _paintSal(Canvas canvas, Offset at, double now, double glideE) {
    final s = _scene;
    final look = s.look;
    final still = s.still;
    var alpha = 1.0;
    var rise = 0.0;
    KuteDogPose pose;
    switch (s.outcome) {
      case _Outcome.success:
        // Happy: he hops up and away as the last check pops.
        final e = now - s.outcomeAt;
        pose = kuteMascotPose(KuteState.winPrediction, e % 900);
        rise = look.rise *
            Curves.easeOutCubic.transform(_unit((e - _kRingClose) / 700));
        alpha = 1 - _unit((e - 500) / 500);
      case _Outcome.failure:
        // Sorry about it: the confused tilt, held, and dimmed.
        final e = still ? 750.0 : math.min(now - s.outcomeAt, 750.0);
        pose = kuteMascotPose(KuteState.error, e);
        alpha = still
            ? _kDimAlpha
            : 1 - (1 - _kDimAlpha) * _unit((now - s.outcomeAt) / _kDim);
      case _Outcome.none:
        final running = s.target != null &&
            s.fx[s.target!]?.status == MoneyStepStatus.running;
        if (still) {
          pose = running
              ? kuteMascotPose(KuteState.loading, 420)
              : KuteDogPose.neutral;
        } else if (glideE >= 0 && glideE < _kArrive) {
          // Trotting down the line.
          final step = kuteWave(now, 160);
          pose = KuteDogPose(
            earLeft: -0.25,
            earRight: -0.2,
            tail: 0.4 * kuteWave(now, 180),
            pawLeft: 0.5 * math.max(0, step),
            pawRight: 0.5 * math.max(0, -step),
          );
        } else if (running) {
          // Thinking while the step runs: he sniffs it over.
          pose = kuteMascotPose(KuteState.loading, now % 1700);
        } else {
          pose = kuteDogIdlePose(now % kKuteDogIdleMs);
        }
        if (!still && glideE >= _kArrive && glideE < _kArrive + _kHop) {
          // The hop as he lands, with the selection click.
          pose = _withLift(
              pose, 2.4 * math.sin(math.pi * (glideE - _kArrive) / _kHop));
        }
    }
    if (!still) alpha *= _unit((now - s.salEnterAt) / 180);
    if (alpha <= 0) return;
    final size = look.salSize;
    final u = size / 16;
    final origin = at.translate(-8.5 * u, -8.2 * u - rise);
    final bounds = Rect.fromCenter(
        center: at.translate(0, -rise), width: size * 2, height: size * 2.6);
    if (alpha < 1) {
      canvas.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    }
    paintKuteDog(canvas,
        origin: origin, unit: u, pose: pose, palette: KuteDogPalette.mascot);
    if (alpha < 1) canvas.restore();
  }

  void _paintRing(
      Canvas canvas, Offset c, double radius, double now, double? since) {
    final s = _scene;
    final still = s.still;
    final draw = still || since == null
        ? 1.0
        : Curves.easeOutCubic.transform(_unit((now - since) / _kRingDraw));
    final rot = still ? 0.0 : now / 1600 * 2 * math.pi;
    final breathe = still
        ? 1.0
        : 0.8 + 0.2 * (0.5 + 0.5 * math.sin(now / 1100 * 2 * math.pi));
    final r = radius + (still ? 0 : 0.35 * math.sin(now / 1100 * 2 * math.pi));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = s.look.done.withValues(alpha: s.look.done.a * breathe);
    final sweep = 0.85 * draw * 2 * math.pi;
    if (sweep <= 0) return;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2 + rot,
        sweep, false, paint);
  }

  void _paintDone(Canvas canvas, Offset c, double now, _LineFx fx) {
    final s = _scene;
    final look = s.look;
    final at = fx.doneAt;
    final e = s.still || at == null ? double.infinity : now - at;
    // The ring closes, then fades as the check pops.
    if (e < _kRingClose + _kRingFade) {
      final close = Curves.easeOut.transform(_unit(e / _kRingClose));
      final fade = 1 - _unit((e - _kRingClose) / _kRingFade);
      canvas.drawArc(
          Rect.fromCircle(
              center: c, radius: fx.doneBig ? look.salRing : look.smallRing),
          -math.pi / 2,
          (0.85 + 0.15 * close) * 2 * math.pi,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..color = look.done.withValues(alpha: look.done.a * fade));
    }
    if (e < _kRingClose) return;
    final pe = e - _kRingClose;
    final scale = _pop(_unit(pe / _kPop), fx.finalDone ? 1.32 : 1.18);
    final r = look.signR * scale;
    canvas.drawCircle(
        c, r, Paint()..color = look.done.withValues(alpha: look.done.a * 0.16));
    final draw = _unit((pe - _kCheckDelay) / _kCheckDraw);
    if (draw > 0) {
      final check = Path()
        ..moveTo(c.dx - 0.42 * r, c.dy + 0.02 * r)
        ..lineTo(c.dx - 0.12 * r, c.dy + 0.32 * r)
        ..lineTo(c.dx + 0.42 * r, c.dy - 0.28 * r);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = look.done;
      if (draw >= 1) {
        canvas.drawPath(check, paint);
      } else {
        for (final m in check.computeMetrics()) {
          canvas.drawPath(m.extractPath(0, m.length * draw), paint);
        }
      }
    }
    // A small burst, a bigger one for the last.
    final span = fx.finalDone ? _kFinalBurst : _kBurst;
    final bp = pe / span;
    if (bp >= 0 && bp < 1) {
      final n = fx.finalDone ? 10 : 6;
      final reach = fx.finalDone ? look.reachFinal : look.reach;
      final dot = fx.finalDone ? look.dotFinal : look.dot;
      final out = Curves.easeOutCubic.transform(bp);
      final paint = Paint()
        ..color = look.done
            .withValues(alpha: look.done.a * math.pow(1 - bp, 1.4).toDouble());
      for (var j = 0; j < n; j++) {
        final a = -math.pi / 2 + 2 * math.pi * j / n + (j.isOdd ? 0.18 : -0.12);
        final d = look.signR + reach * out;
        canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * d,
            dot * (1 - 0.5 * bp), paint);
      }
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

  // Rebuilt only when the view builds; the clock drives every frame.
  @override
  bool shouldRepaint(MoneyStepsMotionPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────
// Paint-only helpers for the lines
// ─────────────────────────────────────────────────────────────────────

/// Registers its box in the scene by line id ([id] null: the tree's own
/// box), so the painter knows where each line sits without a rebuild.
class _Anchor extends SingleChildRenderObjectWidget {
  const _Anchor({required this.scene, required this.id, super.child});
  final _Scene scene;
  final String? id;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAnchor(scene, id);

  @override
  void updateRenderObject(BuildContext context, _RenderAnchor renderObject) =>
      renderObject.rebind(scene, id);
}

class _RenderAnchor extends RenderProxyBox {
  _RenderAnchor(this._scene, this._id);
  _Scene _scene;
  String? _id;

  void _register() {
    final id = _id;
    if (id == null) {
      _scene.root = this;
    } else {
      _scene.anchors[id] = this;
    }
  }

  void _unregister() {
    final id = _id;
    if (id == null) {
      if (identical(_scene.root, this)) _scene.root = null;
    } else if (identical(_scene.anchors[id], this)) {
      _scene.anchors.remove(id);
    }
  }

  void rebind(_Scene scene, String? id) {
    if (identical(scene, _scene) && id == _id) return;
    if (attached) _unregister();
    _scene = scene;
    _id = id;
    if (attached) _register();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _register();
  }

  @override
  void detach() {
    _unregister();
    super.detach();
  }
}

/// Shakes its line sideways while [dx] says so: paint only, so the line
/// neither rebuilds nor moves for its semantics.
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

class _RenderShake extends RenderProxyBox {
  _RenderShake(this._clock, this.dx);
  Listenable _clock;
  double Function() dx;
  double _painted = 0;

  set clock(Listenable value) {
    if (identical(value, _clock)) return;
    if (attached) _clock.removeListener(_tick);
    _clock = value;
    if (attached) _clock.addListener(_tick);
  }

  void _tick() {
    if (dx() != _painted) markNeedsPaint();
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
    _painted = dx();
    super.paint(context, offset.translate(_painted, 0));
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
