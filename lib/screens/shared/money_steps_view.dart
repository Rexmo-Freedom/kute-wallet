// lib/screens/shared/money_steps_view.dart
//
// The ONE widget that shows a money step graph ([MoneyStepGraph]) under a
// slip's or a sheet's button, and in an Activity detail: the MONEY
// JOURNEY, in the calm look the founder approved on 20 October 2026 (the
// earlier map read "childish and cheap"), its connectors redrawn as the
// "B2 · rounded elbows" wireframe on 27 October 2026 (the slanted legs
// and chevrons did not look like a proper payment flow); the ARROW
// TRACK of 1 November 2026 (a bold orange bar with an arrowhead, 44 px
// marks) went the same day: "not fintech like; make it fintech with
// Blender", "must be 2026 fintech like with Sal". 2026 FINTECH WITH SAL:
// large quiet whitespace, one thin neutral line, tiny matte stations,
// no boxes, chevrons or tints, and the big 3D Sal as the one character
// (a transfer screen's progress, with our dog). One quiet row: the
// balances the money passes through are small round STATIONS left to
// right (`stationR` 5.5: 11 px dots on the line, in the theme's neutral
// inks only: a hairline ring on the surface until the money is there,
// a solid `textPrimary` dot once it is, with a tiny check in the
// surface's colour once its part is done, a small red "!" where the
// money stopped; never a brand colour, never a disc of colour), joined
// by TRACKS: a thin rounded line about 2.5 px thick (`_Look.trackH`) in
// a hairline neutral grey (`_Look.track`), its travelled part solid
// `textPrimary` (`_Look.fill`; a quiet grey where the leg stopped), that
// simply ends at the station it goes into (no arrowhead, nothing past
// the dot). Still never a diagonal. The station a leg runs to (or the
// destination while its own sub-steps run) is the one live thing on
// the line besides Sal: a soft 1 px ring pulses out from it slowly
// ([_kWorkBreath], on the settle curve, low alpha). The names under
// the stations stay in the small quiet caption style, the one the
// money is heading to in `textPrimary` semibold; a leg's amount is in
// tabular figures. The coin wears the balance's mark as ever (the one
// brand colour on the row). Sal is big (`salSize` 64: the 3D clips
// drawn in a 64 px box, crisp from the sheets' 128 px cells), standing
// ON the line with his feet on its top edge, walking it with the coin
// in his mouth, waiting with it at his paws, dropping it into the
// destination; the coin ([coinR] 9) rides clear of the line. The row
// has room above the line for him (`rowY` 52); the status line under
// the row and the sub-step dots under the destination are as they
// were, in the same neutral inks. The pixel-rig fallback (before the
// sheets decode) keeps a smaller box (`rigSize`).
// One source: one straight horizontal track from its station to the
// next. Legs from
// several balances run at once (founder, 25 October 2026): their
// stations stack in their column, each on its own row with a small gap;
// each leg runs straight along its own row, turns with a rounded
// right-angle corner (~8 px) and runs vertically to ONE merge point on
// the destination's centre line (the legs' round ends meet), and one
// straight shared line goes on from there into the destination, like
// an org chart. Each leg fills from its own station along its own path
// (round its corner) at its own pace; the shared line fills once every
// leg landed.
// Under each
// source, at the start of its leg, its amount in small quiet type
// ("$4.18"). The status line says the legs together ("Moving $4.18
// from Bitcoin and $5.00 from Investing"), then the destination's first
// dot waits for all of it ("Waiting for both to arrive") before anything
// there (the conversion, the order) runs. A station is a hairline ring
// until the money is there, then a solid dot; its check comes once its
// part is done, a small red "!" where the money stopped. A leg's
// sub-legs (HyperCore → Circle → Arbitrum) are small notches in its
// track (a dot in the surface's colour on the line) that fill in as the
// travelled part passes them. While the destination's own sub-steps run
// (converting, approving, confirming, placing, crediting) the pulse
// sits on it, and nothing else there asks for attention; done, the
// pulse goes and the check comes. Those
// sub-steps are a row of small dots under its name: a ring while
// waiting, a softly breathing dot while running, filled once done.
// ONE coin, wearing the mark of the balance the money is in (the same
// mark as that station: never a bare "$"), rides the running
// track a little above it, rests above each station on the way and
// cross-fades into that station's currency; it never parks at a merge
// point (on a leg into one it stops before the corner and fades out
// once the leg landed), and at a destination with sub-steps it sinks in
// as the pulse takes over (else once everything is done; or in Sal's
// mouth while he waits with it, below). Sal, small,
// walks the line behind the coin and waits there while it works, never
// at the merge point: once the money is all there he walks on along the
// line (round the corner, along the shared line) and waits beside the
// destination, left of its pulse, while it works. While the money waits
// on a running step he waits in a mood that follows how long the wait
// has lasted (founder, 27 October 2026; [SalMood]): fetch (0–8 s, he
// walks up to the parked coin and sits with it in his mouth like a
// ball, wearing its mark, a wag every 2 s; he carries it on to the
// destination when the money goes on there), sniff the trail (8–25 s,
// the coin at his paws, nose down, padding back and forth along the
// line with small puffs), settle in (25 s on, with "Taking longer than
// usual": lying, chin on his paws, a breath every 3 s, ears up and a
// small "!" when the step reports news). Drawn as pixel-sprite frames
// at ~8 fps in short beats with rests. On confirm a little hop and he
// drops the coin in; on a stop he stays still in the pose he was in.
// Reduce Motion: one still pose per mood at the same thresholds; a
// record replayed at rest has no moods. As the 3D Sal (31 October 2026)
// each mood rotates the clips of the second batch's `waiting` group
// (fetch: pace, sniff the trail, dig; sniff: sniff the trail, think;
// settle: sit, point; a success jumps then wags; a failure shakes its
// head then is sad), never the same twice in a row, on the same mood
// timing ([_paintSalSprite]). THE COIN IN THE RENDER (founder, "Sal
// moving around and taking the actual thing and putting it in another
// place"; 1 November 2026): once the coin clips are decoded and their
// per-frame anchors read ([_salCarries]: body_pickup, body_carry,
// body_drop, rendered from the Blender rig with an orange coin in them),
// Sal takes the coin up from the floor at the station it leaves as its
// leg starts (body_pickup, standing still for it), walks the line with
// it in his mouth (body_carry instead of body_walk; the travelled line
// ends where he is, and he walks, never dashes), and where he lets it go
// he stops and sets it down (body_drop; at the destination once its own
// sub-steps are done, or where a leg lands with nothing more to do
// there), the moods and the cheer after it as before. The coin is then
// the render's: the painted coin gives way to it, and the balance's mark
// is drawn on it at the frame's anchor (about 1.2 of its radius tall,
// squashed as it is foreshortened, none lying flat). Reduce Motion: no
// pick-up or drop, the held pose (body_carry's first frame) at once.
// Until the clips are in (or without them) the painted coin glides and
// he fetches it, as below. One continuous performance (sal_sprite.dart's
// rule): a parked mood's clip gives way at its loop's boundary (a one-shot
// once through), the two cells dissolve for 120 ms, and every clip he can
// wear is decoded once when the view mounts, so no switch waits on a
// read; into or out of a walk, a hop or a stop the switch is at once
// (still dissolved). Under the row: one
// status line in the step's own
// words ("Moving $4.18 from Bitcoin", "Confirming balance", "Placed!",
// or the surface's line saying where the money is after a stop),
// "Taking longer than usual" quietly under it. No progress bar (founder,
// 2026-10-20): the row already shows how far the money is, the status
// line says the rest. Every line (each leg, sub-leg and checkpoint) is a
// real semantics node in its final words: the status line is the
// current line itself, the others are there unseen.
//
// While a step runs and the money waits (held near the end of its
// connector for a bridge) the row stays quietly alive, never with
// bursts or borders: the parked coin hovers ±1.5 px, Sal blinks and
// sniffs, and the station a leg runs to (the destination while it
// works) pulses its soft ring. Only the row's own layers repaint for it.
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

import 'package:kute/screens/shared/sal_sprite.dart';
import 'dart:async' show Timer, unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/asset_icon_provider.dart'
    show kBitcoinMarkAsset, kUsdMarkAsset;
import 'package:kute/screens/shared/kute_dog_rig.dart';
import 'package:kute/screens/shared/kute_motion.dart' show kuteReduceMotion;
import 'package:kute/screens/shared/money_journey_plan.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/success_feedback.dart'
    show moneyFailureFeedback, moneyStepsSuccessFeedback;
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart' show KuteMotion;

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
    case MoneyStepKind.gather:
      // The legs converging on the venue: "both" for two.
      final n = math.max(2, s.after.length);
      return done ? l10n.moneyStepGathered(n) : l10n.moneyStepGathering(n);
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
const double _kHover = 2000; // the parked coin's hover
const double _kWorkBreath = 2400; // the live station's pulse
// How long the clock runs on after the last moment (the dash, the
// cross-fade, the sink and Sal's last steps all fit in it); it
// runs on while any step runs.
const double _kRest = 2600;

// Sal's waiting moods (founder, 27 October 2026): drawn as pixel-sprite
// frames at ~8 fps ([_kSprite]) in short beats with rests between them.
const double _kSprite = 125; // one frame of a mood
const double _kSniffAt = 8000; // fetch → sniff the trail
const double _kSettleAt = 25000; // → settle in (with "Taking longer")
const double _kFetchBeat = 2000; // a wag (5 frames) every 2 s
const double _kSniffBeat = 3000; // pad back and forth (12 frames), pause
const double _kSettleBeat = 3000; // a breath (3 frames) every 3 s
const double _kPerk = 1000; // ears up and a "!" on news
const double _kPickUp = 3 * _kSprite; // the coin into his mouth
const double _kHop = 480; // the hop on confirm
const double _kDrop = 520; // the coin dropped into the station
const double _kHeldScale = 0.7; // the coin in his mouth or at his paws

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
    required this.ink,
    required this.stopped,
    required this.failed,
    required this.background,
    required this.fill,
    required this.stationR,
    required this.trackH,
    required this.pulseReach,
    required this.waypointR,
    required this.dotR,
    required this.dotGap,
    required this.coinR,
    required this.coinLift,
    required this.gap,
    required this.tipGap,
    required this.corner,
    required this.rowGap,
    required this.salSize,
    required this.rigSize,
    required this.rowY,
    required this.nameTop,
    required this.nameH,
    required this.amountTop,
    required this.amountH,
    required this.dotsGap,
    required this.padX,
    required this.font,
  });

  /// The lines' hairline grey (the untravelled part, a waiting station's
  /// ring, a waiting checkpoint's).
  final Color track;

  /// Sal's "!" and his sniff puffs.
  final Color ink;

  /// A stopped leg's fill.
  final Color stopped;
  final Color failed;
  final Color background;

  /// The surface's ink: a line's travelled part, a station the money is
  /// there at, a checkpoint done, the pulse.
  final Color fill;

  /// A station's dot: half of its ~11 px.
  final double stationR;

  /// The line's thickness (thin: about 2.5 px).
  final double trackH;

  /// How far past a station's edge its pulse ring reaches at its widest.
  final double pulseReach;
  final double waypointR;
  final double dotR;
  final double dotGap;
  final double coinR;

  /// How far above its line the coin travels.
  final double coinLift;

  /// How far past a station's edge a track starts (0: its round cap
  /// meets the dot).
  final double gap;

  /// From a track's end to the station's edge it goes into (0: the line
  /// simply ends at the dot).
  final double tipGap;

  /// A leg's rounded corner on its way to a merge point.
  final double corner;

  /// Between two stations stacked in one column.
  final double rowGap;

  /// The 3D Sal's box (the sheets' cell, 16 units; his feet at 15 of
  /// them, so he stands about 13/16 of it tall).
  final double salSize;

  /// Half of what he takes across the track (the body spans about 9 of
  /// the cell's 16 units), for where he stops short of things.
  double get salHalf => salSize * 0.3;

  /// The pixel rig's box, while the sheets decode: smaller, so its 16
  /// units stay chunky rather than crude.
  final double rigSize;

  /// The stations' centre line, from the map's top (room above it for the
  /// coin and Sal).
  final double rowY;

  /// The names' top, below the icons.
  final double nameTop;
  final double nameH;

  /// A leg's amount (legs from several balances): from its line's
  /// centre to its top, and its height with the gap under it (the
  /// column's names go under the lowest one).
  final double amountTop;
  final double amountH;

  /// Legs from several balances: the names' top, from the column's
  /// lowest row's centre line.
  double get stackedNameDy => amountTop + amountH;

  /// From the names' bottom to the checkpoints' dots.
  final double dotsGap;
  final double padX;

  /// The surface's text style (the coin's "$" is written in its font).
  final TextStyle font;

  /// Where the coin rests above a station at [x].
  Offset restAbove(double x) => Offset(x, rowY - stationR - 2.5 - coinR);
}

/// One road's own line in a row with parallel legs ([_Geometry.branches]):
/// straight along its source's row and, into a merge point on another
/// row, round one corner and vertically into it (the corners drawn in
/// short steps, so the fill and the coin follow them like any line).
class _RoadPath {
  _RoadPath(this.points, {double? coinStop}) {
    var sum = 0.0;
    cum.add(0);
    for (var i = 1; i < points.length; i++) {
      sum += (points[i] - points[i - 1]).distance;
      cum.add(sum);
    }
    _coinStop = coinStop;
  }
  final List<Offset> points;
  final List<double> cum = [];
  double? _coinStop;
  double get length => cum.last;
  Offset get start => points.first;
  Offset get end => points.last;

  /// How far along the coin (and Sal behind it) may go, 0..1: before a
  /// corner, or short of a merge point, never on it.
  double get coinStop =>
      length <= 0 ? 1 : _unit((_coinStop ?? length) / length);

  /// The point [f] (0..1) of the way along.
  Offset at(double f) {
    final d = _unit(f) * length;
    for (var i = 1; i < points.length; i++) {
      if (d <= cum[i] || i == points.length - 1) {
        final seg = cum[i] - cum[i - 1];
        final t = seg <= 0 ? 1.0 : _unit((d - cum[i - 1]) / seg);
        return Offset.lerp(points[i - 1], points[i], t)!;
      }
    }
    return end;
  }

  /// How far along (0..1) its point nearest [p] is.
  double fractionNear(Offset p) {
    if (length <= 0) return 1;
    var best = double.infinity;
    var at = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final d = points[i] - a;
      final len2 = d.dx * d.dx + d.dy * d.dy;
      final t = len2 <= 0
          ? 0.0
          : (((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / len2)
              .clamp(0.0, 1.0);
      final dist = (p - (a + d * t)).distance;
      if (dist < best) {
        best = dist;
        at = cum[i - 1] + (cum[i] - cum[i - 1]) * t;
      }
    }
    return at / length;
  }

  /// The line from its start to [f] of the way.
  Path upTo(double f) {
    final d = _unit(f) * length;
    final p = Path()..moveTo(start.dx, start.dy);
    for (var i = 1; i < points.length; i++) {
      if (d >= cum[i]) {
        p.lineTo(points[i].dx, points[i].dy);
        continue;
      }
      final q = at(f);
      p.lineTo(q.dx, q.dy);
      break;
    }
    return p;
  }
}

/// The steps a rounded corner is drawn in.
const int _kArcSteps = 10;

/// The arc about [c] of radius [r] from angle [t0] to [t1], without its
/// first point.
Iterable<Offset> _arc(Offset c, double r, double t0, double t1) sync* {
  for (var k = 1; k <= _kArcSteps; k++) {
    final t = t0 + (t1 - t0) * k / _kArcSteps;
    yield c + Offset(math.cos(t), math.sin(t)) * r;
  }
}

/// A leg from [a] to [m]: right along [a]'s row, one rounded right-angle
/// corner of [corner], then straight up or down into [m] (a merge point
/// on its station's row); straight when [m] is on [a]'s row. With [end],
/// a second rounded corner onto [m]'s row and on to [end] (a leg into a
/// station of its own on another row). Never a diagonal.
List<Offset> _elbowPoints(Offset a, Offset m, double corner, {Offset? end}) {
  final dy = m.dy - a.dy;
  if (dy.abs() < 0.5) return [a, end ?? m];
  final sign = dy.sign;
  final r = math.max(
      0.0,
      math.min(math.min(corner, end == null ? dy.abs() : dy.abs() / 2),
          m.dx - a.dx));
  final pts = <Offset>[
    a,
    Offset(m.dx - r, a.dy),
    ..._arc(Offset(m.dx - r, a.dy + sign * r), r, -sign * math.pi / 2, 0),
  ];
  if (end == null) return [...pts, m];
  return [
    ...pts,
    Offset(m.dx, m.dy - sign * r),
    ..._arc(Offset(m.dx + r, m.dy - sign * r), r, math.pi, sign * math.pi / 2),
    end,
  ];
}

/// Where everything sits in the row, for one size.
class _Geometry {
  _Geometry(this.size, this.stations, this.columnX, this.gaps, this.gapRoad,
      this.dotsY,
      {this.paths = const [], this.trunks = const {}, this.branchRows = 1});
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

  /// Legs from several balances run at once: each station on its own row
  /// and each road its own line ([paths], by road), into one merge point
  /// before the station they go to, and from there one shared line into
  /// it ([trunks], by station). Otherwise one row and one connector per
  /// column gap.
  final List<_RoadPath?> paths;
  final Map<int, _RoadPath> trunks;
  final int branchRows;
  bool get branches => paths.isNotEmpty;

  /// The rows a plan needs: more than one when a column holds several
  /// stations (legs from several balances).
  static int rowsOf(MoneyJourneyPlan plan) {
    var rows = 1;
    for (final st in plan.stations) {
      rows = math.max(rows, st.rows);
    }
    return rows;
  }

  /// From one row's centre line to the next: the stations of one column
  /// each on their own row, a small gap between them.
  static double rowStep(_Look look) => 2 * look.stationR + look.rowGap;

  /// The row's height for [plan] (the map above the status line), less
  /// its bottom margin.
  static double heightOf(MoneyJourneyPlan plan, _Look look, bool hasDots) {
    final rows = plan.columns > 1 ? rowsOf(plan) : 1;
    final dots = hasDots ? look.dotsGap + 2 * look.dotR : 0.0;
    if (rows <= 1) return look.nameTop + look.nameH + dots;
    final span = (rows - 1) * rowStep(look);
    return math.max(look.rowY + span + look.stackedNameDy + look.nameH,
        look.nameTop + span / 2 + look.nameH + dots);
  }

  /// Where the coin rests above station [i].
  Offset restAt(_Look look, int i) {
    final c = stations[i];
    return Offset(c.dx, c.dy - look.stationR - 2.5 - look.coinR);
  }

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
    if (rowsOf(plan) > 1 && cols > 1) {
      return _branched(plan, size, look, columnX, cols);
    }
    final stations = <Offset>[
      for (final st in plan.stations)
        Offset(
            columnX[_col(st, cols)] - (st.rows - 1) * step / 2 + st.row * step,
            look.rowY),
    ];
    double extent(int c) => r + (rows[c] - 1) * step / 2;
    // Each gap's track: from the column's edge to the next's.
    final gaps = [
      for (var g = 0; g + 1 < cols; g++)
        (
          columnX[g] + extent(g) + look.gap,
          columnX[g + 1] - extent(g + 1) - look.tipGap,
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

  /// Legs from several balances at once: every source on its own row (the
  /// column's rows centred on the row's middle), a station passed on the
  /// way on the row of the leg that feeds it, the destination on the
  /// middle. Each road is its own hairline along its source's row; into
  /// a station several roads go to, it turns with a rounded corner in the
  /// last gap and runs vertically into one merge point on the station's
  /// row, and one shared line goes on from there into the station.
  static _Geometry _branched(MoneyJourneyPlan plan, Size size, _Look look,
      List<double> columnX, int cols) {
    final r = look.stationR;
    final rowsAll = rowsOf(plan);
    final vstep = rowStep(look);
    final mid = look.rowY + (rowsAll - 1) * vstep / 2;
    final n = plan.stations.length;
    final ys = List<double?>.filled(n, null);
    final dest = plan.destination;
    if (dest != null) ys[dest] = mid;
    // Sources (nothing comes into them): their own row.
    for (var i = 0; i < n; i++) {
      if (ys[i] != null) continue;
      final st = plan.stations[i];
      if (plan.roads.any((road) => road.to == i)) continue;
      ys[i] = look.rowY + (st.row + (rowsAll - st.rows) / 2) * vstep;
    }
    // Stations on the way, left to right: the row of the leg into them.
    final order = [for (var i = 0; i < n; i++) i]..sort((a, b) =>
        plan.stations[a].column.compareTo(plan.stations[b].column));
    for (final i in order) {
      if (ys[i] != null) continue;
      final feed = plan.roads.where((road) => road.to == i).firstOrNull;
      final y = feed == null ? null : ys[feed.from];
      final st = plan.stations[i];
      ys[i] = y ?? look.rowY + (st.row + (rowsAll - st.rows) / 2) * vstep;
    }
    final stations = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(columnX[_col(plan.stations[i], cols)], ys[i] ?? mid),
    ];
    // How many drawn roads go into each station: two or more merge.
    final into = <int, int>{};
    for (final road in plan.roads) {
      if (_col(plan.stations[road.to], cols) >
          _col(plan.stations[road.from], cols)) {
        into[road.to] = (into[road.to] ?? 0) + 1;
      }
    }
    // The coin keeps clear of a corner, and of a merge point.
    final clear = look.coinR + 4;
    final trunks = <int, _RoadPath>{};
    final paths = <_RoadPath?>[
      for (final road in plan.roads)
        () {
          final a = stations[road.from];
          final b = stations[road.to];
          final c0 = _col(plan.stations[road.from], cols);
          final c1 = _col(plan.stations[road.to], cols);
          if (c1 <= c0) return null;
          final start = Offset(a.dx + r + look.gap, a.dy);
          // Into a station: the line ends at its edge.
          final end = Offset(b.dx - r - look.tipGap, b.dy);
          final lastGap0 = columnX[c1 - 1] + r + look.gap;
          if ((into[road.to] ?? 0) >= 2) {
            // Into the merge point, a little past the last gap's middle,
            // so the shared line into the station reads as one.
            final m = Offset(
                math.max(start.dx + look.corner + 2 * clear,
                    lastGap0 + (end.dx - lastGap0) * 0.55),
                b.dy);
            trunks.putIfAbsent(road.to, () => _RoadPath([m, end]));
            final pts = _elbowPoints(start, m, look.corner);
            final straight = pts.length == 2;
            return _RoadPath(pts,
                coinStop: straight
                    ? (m.dx - start.dx) - 2 * clear - look.corner
                    : (pts[1].dx - start.dx) - clear);
          }
          if ((a.dy - b.dy).abs() < 0.5) return _RoadPath([start, end]);
          // A station of its own on another row: two rounded corners
          // halfway through the last gap.
          final pts = _elbowPoints(
              start, Offset(lastGap0 + (end.dx - lastGap0) * 0.5, b.dy),
              look.corner,
              end: end);
          return _RoadPath(pts, coinStop: (pts[1].dx - start.dx) - clear);
        }(),
    ];
    final destY = dest == null ? mid : stations[dest].dy;
    final dotsY = destY - look.rowY + look.nameTop + look.nameH +
        look.dotsGap + look.dotR;
    return _Geometry(size, stations, columnX, const [], const [], dotsY,
        paths: paths, trunks: trunks, branchRows: rowsAll);
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

  /// The point of road [road]'s line at [f] of its way.
  Offset tipAt(MoneyJourneyPlan plan, JourneyRoad road, double f, _Look look) {
    if (branches) return _branchTip(plan, road, f);
    return Offset(tipX(plan, road, f), look.rowY);
  }

  Offset _branchTip(MoneyJourneyPlan plan, JourneyRoad road, double f) {
    final path = paths[plan.roads.indexOf(road)];
    return path == null ? stations[road.to] : path.at(f);
  }

  /// The x of road [road]'s line at [f] of its way.
  double tipX(MoneyJourneyPlan plan, JourneyRoad road, double f) {
    if (branches) return _branchTip(plan, road, f).dx;
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
    if (branches) {
      final from = restAt(look, road.from);
      final path = paths[plan.roads.indexOf(road)];
      if (path == null) {
        return Offset.lerp(from, restAt(look, road.to), _unit(f))!;
      }
      // Along its own row, never round a corner or onto a merge point:
      // it waits before them.
      final line =
          path.at(math.min(f, path.coinStop)).translate(0, -look.coinLift);
      // Down from above its station onto the line; into the last station
      // it stays on the line and settles once the leg landed.
      final u = _unit(f);
      if (u >= 0.15) return line;
      final blend = Curves.easeInOut.transform(1 - _unit(u / 0.15));
      return Offset.lerp(line, from, blend)!;
    }
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
  double? salY;
  double salPaintedAt = 0;
  bool salWalking = false;

  // The coin's hover, 0..1, and when it was last painted.
  double hover = 0;
  double hoverPaintedAt = 0;

  // Sal's wait: which one ([_waitKeyOf]), since when he has been waiting
  // there (null while he walks to it), and the last news while he did.
  String? waitKey;
  double? waitSince;
  double? perkAt;

  /// The mood he stopped in when a step failed: held still, no loop.
  SalMood? stopMood;

  // Sal has the coin (in his mouth, or at his paws), since when, and
  // where it was when he took it.
  bool carry = false;
  double? carryAt;
  Offset? carryFrom;

  // The hop on confirm and the coin dropped from his mouth into the
  // station ([dropSink]: into the destination, gone after).
  double? hopAt;
  double? dropAt;
  Offset? dropFrom;
  MoneyPlace? dropPlace;
  int? dropTo;
  bool dropSink = false;

  /// His body's offset at the last paint (px, down), for the coin he
  /// carries; and the lines' words and states, for news while he waits.
  double salBob = 0;
  // Whether the 3D clip drew him at the last paint (else the rig did):
  // the coin he holds sits where that body's mouth and paws are.
  bool salSprite = false;
  String linesSig = '';

  // The 3D clip he wears ([_paintSalSprite]): what he is doing (the
  // scene key), the clip, since when, and the one before it (never the
  // same twice in a row); the picks' source.
  String salScene = '';
  String? salClip;
  double salClipAt = 0;
  String? salClipPrev;
  final math.Random salRandom = math.Random();

  // The dissolve on a clip switch (sal_sprite.dart's 120 ms): the clip
  // before, the frame it froze on, and when the switch landed.
  String? salFadeFrom;
  int salFadeFrame = 0;
  double salFadeAt = double.negativeInfinity;

  // The coin in the render ([_salCarries]): whether the coin clips could
  // carry it at the last paint; the pick-up (when it began, where he
  // stands for it, until when it plays); the drop (whether the render
  // sets the coin down, when its clip began, until when it plays); the
  // rendered coin's centre at the last paint and how much of the coin
  // the render showed (0..1; the painted coin takes the rest); and how
  // long the clock must run for a one-shot.
  bool salCarries = false;
  double? pickupAt;
  Offset? pickupPos;
  double pickupUntil = double.negativeInfinity;
  bool dropInRender = false;
  double? dropClipAt;
  double dropUntil = double.negativeInfinity;
  Offset? salCoinAt;
  double salCoinFade = 0;
  double salBusyUntil = double.negativeInfinity;
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
          now < _scene.salBusyUntil ||
          _scene.plan.lines.any((l) => l.status == MoneyStepStatus.running));

  /// Something happened now: the clock runs on [_kRest] from here.
  void _moment(double now) => _busyUntil = math.max(_busyUntil, now + _kRest);

  @override
  void initState() {
    super.initState();
    unawaited(_loadMarks());
    // The sheets decode after the first paint: once they are in, one
    // more frame puts the render on, even where the clock is not
    // running (a finished record, Reduce Motion), else the rig would
    // stay until something else repainted.
    unawaited(_warmSalClips().then((_) {
      if (mounted) setState(() {});
    }));
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
    _stillTimer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  /// Under Reduce Motion the clock does not run: this moves it on to the
  /// next mood's threshold, so the still pose changes there.
  Timer? _stillTimer;

  /// Keeps Sal's wait up to date at [now]: a new wait (a new station, the
  /// coin further on, all the money there) starts over at fetch once he
  /// stands at his spot, and he takes the coin then. True when anything
  /// changed.
  bool _noteWait(double now) {
    final s = _scene;
    final geo = s.geo;
    final key = _waitKeyOf(s, now);
    if (key == null) {
      final had = s.waitSince != null || s.waitKey != null;
      s.waitKey = null;
      s.waitSince = null;
      s.perkAt = null;
      return had;
    }
    var changed = false;
    if (key != s.waitKey) {
      s.waitKey = key;
      s.waitSince = null;
      s.perkAt = null;
      changed = true;
    }
    if (s.waitSince != null || geo == null) return changed;
    // Taking the coin up is not waiting yet.
    if (_picking(s, now)) return changed;
    final aim = _salTarget(s, geo, now);
    final x = s.salX;
    final quiet = s.still ||
        (x != null &&
            (Offset(x, s.salY ?? aim.dy) - aim).distance < 0.5 &&
            (_salTarget(s, geo, now + 120) - aim).distance < 0.3);
    if (!quiet) return changed;
    s.waitSince = now;
    if (!s.carry) {
      final free = _freeCoin(s, geo, now);
      s.carry = true;
      s.dropAt = null;
      s.dropSink = false;
      s.carryAt = s.still ? null : now;
      s.carryFrom = s.still ? null : free?.at;
    }
    return true;
  }

  /// The coin in the render ([_salCarries]): as the coin's leg starts,
  /// Sal, standing at its start, takes the coin up there (body_pickup,
  /// standing still for it) and carries it on from there. Not under
  /// Reduce Motion (he has it once he waits, [_noteWait], in the held
  /// pose), and not without the clips (he fetches the gliding coin).
  void _noteCarry(double now) {
    final s = _scene;
    final geo = s.geo;
    final x = s.salX;
    final y = s.salY;
    if (s.still || s.carry || !s.live || s.outcome != _Outcome.none) return;
    if (geo == null || x == null || y == null || _picking(s, now)) return;
    if (_dropPending(s, now) || !_salCarries()) return;
    final plan = s.plan;
    final spot = _spotOf(s, now);
    if (spot >= plan.chain.length) return;
    final road = plan.roads[plan.chain[spot]];
    if (!_roadRuns(plan, road)) return;
    if ((Offset(x, y) - _salStart(s, geo, road)).distance > 1.5) return;
    s.carry = true;
    s.carryAt = null;
    s.carryFrom = null;
    s.dropAt = null;
    s.dropClipAt = null;
    s.dropInRender = false;
    s.dropSink = false;
    final len = _salOneShot(_kSalPickup);
    if (len <= 0) return;
    s.pickupAt = now;
    s.pickupPos = Offset(x, y);
    s.pickupUntil = now + len;
    s.salBusyUntil = math.max(s.salBusyUntil, s.pickupUntil + 200);
  }

  /// Under Reduce Motion: on to the next mood's still pose when its
  /// time comes.
  void _scheduleStill() {
    _stillTimer?.cancel();
    _stillTimer = null;
    final s = _scene;
    final since = s.waitSince;
    if (!s.still || since == null || !_waiting(s)) return;
    final e = _now - since;
    final next = e < _kSniffAt
        ? _kSniffAt
        : e < _kSettleAt
            ? _kSettleAt
            : null;
    if (next == null) return;
    _stillTimer = Timer(Duration(milliseconds: (next - e).ceil()), () {
      _stillTimer = null;
      if (!mounted || _scene.waitSince != since) return;
      _clock.value = math.max(_clock.value, (since + next) / 1000);
      _scheduleStill();
    });
  }

  /// Runs the clock while something moves (a while after the last moment,
  /// and all along while a step runs); under Reduce Motion (or with
  /// tickers off) plays the pending haptics once this frame is drawn
  /// instead.
  void _kick() {
    if (_scene.still) {
      // Sal's still pose for the wait, once the row is laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_noteWait(_now)) setState(() {});
        _scheduleStill();
      });
    } else {
      _stillTimer?.cancel();
      _stillTimer = null;
    }
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
    if (!_scene.still) {
      _noteCarry(now);
      _noteWait(now);
    }
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
      s.carry = false;
      s.stopMood = null;
      s.dropAt = null;
      s.hopAt = null;
      s.pickupAt = null;
      s.dropClipAt = null;
      s.dropInRender = false;
    }
    // Sal before the change: whether he had the coin, where it was, his
    // mood and his wait.
    final wasWaiting = !first && _waiting(s);
    final keyBefore = first ? null : _waitKeyOf(s, now);
    final moodBefore = first ? SalMood.none : _moodOf(s, now);
    final geoBefore = s.geo;
    final heldBefore = !first && s.carry && geoBefore != null
        ? _coinOf(s, geoBefore, now)
        : null;
    final sig = [for (final l in lines) '${l.text}|${l.status.name}'].join('\n');
    final news = !first && sig != s.linesSig;
    s.linesSig = sig;
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

    // Sal with the coin: a confirm drops it in (with a hop); a stop
    // holds him still in the mood he was in; news while he lies waiting
    // perks his ears.
    final spotNext = _spotOf(s, now + _kDash + 1);
    if (s.carry) {
      int? dropTo;
      var sink = false;
      if (outcome == _Outcome.success) {
        dropTo = plan.destination;
        sink = true;
      } else if (outcome == _Outcome.none &&
          spotNext > spotBefore &&
          spotBefore < plan.chain.length) {
        final reached = plan.roads[plan.chain[spotBefore]].to;
        final carryOn =
            (reached == plan.destination && _destinationWorks(plan)) ||
                (geoBefore?.trunks.containsKey(reached) ?? false);
        if (!carryOn) dropTo = reached;
      }
      if (dropTo != null) {
        s.carry = false;
        s.carryFrom = null;
        s.carryAt = null;
        if (!s.still) {
          s.dropAt = now;
          s.dropFrom = heldBefore?.at;
          s.dropPlace = heldBefore?.place;
          s.dropTo = dropTo;
          s.dropSink = sink;
          // In the render he sets it down where he stops (body_drop),
          // and hops once it is down ([_paintSalSprite]).
          s.dropInRender = s.salCarries;
          s.dropClipAt = null;
          s.hopAt = s.dropInRender ? null : now;
        }
      }
    }
    if (outcome == _Outcome.failure && wasWaiting && moodBefore != SalMood.none) {
      s.stopMood = moodBefore;
    }
    if (news &&
        wasWaiting &&
        !s.still &&
        _waiting(s) &&
        moodBefore == SalMood.settle &&
        _waitKeyOf(s, now) == keyBefore) {
      s.perkAt = now;
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
    final stationR = 5.5.r;
    final trackH = 2.5.r;
    final coinR = 9.r;
    s.look = _Look(
      // A hairline neutral grey that reads on white, on the dark surface
      // and on a slip's side colour alike (the theme's hairline token is
      // too faint for a 2.5 px line in the dark; the dark tertiary ink
      // needs more of itself to show on the dark surface).
      track: c.textTertiary.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.6 : 0.32),
      ink: c.textSecondary,
      stopped: c.textTertiary,
      failed: c.error,
      background: c.background,
      fill: c.textPrimary,
      stationR: stationR,
      trackH: trackH,
      pulseReach: 9.r,
      waypointR: 2.5.r,
      dotR: 2.5.r,
      dotGap: 9.r,
      coinR: coinR,
      // Riding clear of the line.
      coinLift: trackH / 2 + 2.r + coinR,
      gap: 0,
      tipGap: 0,
      corner: 8.r,
      // Stacked sources far enough apart for Sal on the lower leg to
      // stand clear of the line above him (he is about 13/16 of his box
      // tall; the step between rows is 2 * stationR + rowGap).
      rowGap: 53.r,
      salSize: 64.r,
      rigSize: 32.r,
      // Room above the line for Sal (his box top at the line's top edge
      // less 15/16 of his size: the cell's top is empty above his head)
      // and for the coin above a station.
      rowY: 52.r,
      nameTop: 52.r + stationR + 9.r,
      nameH: scaler.scale(11.sp) * 1.2,
      amountTop: trackH / 2 + 4.r,
      amountH: scaler.scale(10.sp) * 1.2 + 2.r,
      dotsGap: 6.r,
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
    } else if (_runningLegsLine(l10n) case final together?) {
      // Legs from several balances running at once say so together.
      status = together;
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
              final size = Size(constraints.maxWidth,
                  _Geometry.heightOf(plan, look, hasDots) + 2.r);
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
                      ..._amounts(context, geo),
                      // Right to left, so the left one of an overlapped
                      // column sits on top.
                      for (final i in [
                        for (var i = 0; i < plan.stations.length; i++) i
                      ]..sort((a, b) {
                          final x = geo.stations[b].dx
                              .compareTo(geo.stations[a].dx);
                          // A stacked column: the lower one on top, so
                          // every station's corner check shows.
                          return x != 0
                              ? x
                              : geo.stations[a].dy
                                  .compareTo(geo.stations[b].dy);
                        }))
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

  /// The status line while two or more legs run at once, in line order
  /// ("Moving \$4.18 from Bitcoin and \$5.00 from Investing"; with three
  /// or more, their total and how many balances), null otherwise. Each
  /// leg's own line stays there for a screen reader.
  String? _runningLegsLine(AppLocalizations l10n) {
    final graph = widget.graph;
    final money = widget.money;
    if (graph == null || money == null) return null;
    final s = _scene;
    if (s.outcome != _Outcome.none) return null;
    final running = <MoneyStep>[];
    for (final road in s.plan.roads) {
      if (road.line < 0) continue;
      final line = s.plan.lines[road.line];
      if (line.status != MoneyStepStatus.running || line.id == null) continue;
      final step = graph.byId(line.id!);
      if (step == null || step.kind != MoneyStepKind.leg) continue;
      running.add(step);
    }
    if (running.length < 2) return null;
    String from(MoneyStep st) =>
        moneyPlaceName(l10n, st.from ?? MoneyPlace.dollars);
    if (running.length == 2) {
      return l10n.moneyStepMovingTwo(money(running[0].usd), from(running[0]),
          money(running[1].usd), from(running[1]));
    }
    final total = running.fold<double>(0, (sum, st) => sum + st.usd);
    return l10n.moneyStepMovingMany(
        money((total * 100).round() / 100), running.length);
  }

  String _nameOf(AppLocalizations l10n, JourneyStation st) =>
      st.label ??
      (st.place == null ? l10n.recipient : moneyPlaceName(l10n, st.place!));

  /// The names under each column: one station's own, or an overlapped
  /// column's together ("Bitcoin · Dollars"), else the first and how
  /// many more ("Bitcoin +2") when that does not fit. Quiet grey until
  /// the money is heading to in the ink, semibold. The stations'
  /// semantics name them, so these are only seen.
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
      // Legs from several balances: under the column's lowest station.
      final lowest = members
          .map((i) => geo.stations[i].dy)
          .reduce((a, b) => math.max(a, b));
      final x = geo.columnX[col];
      // Its room: from halfway to the column before (or the row's start)
      // to halfway to the next (or the row's end), so names never meet.
      // Centred under its icon when it fits there, else moved in from
      // the row's edge (a long name or large text at an end of the row
      // is not cut short).
      final lo = col == 0 ? 0.0 : (geo.columnX[col - 1] + x) / 2 + 3.r;
      final hi = col == cols - 1 ? w : (x + geo.columnX[col + 1]) / 2 - 3.r;
      final room = math.max(0.0, hi - lo);
      // The station the money is heading to: in the ink, semibold; the
      // rest in the quiet caption grey.
      final live = members.contains(_workingStation(s));
      final style = TextStyle(
          color: live ? c.textPrimary : c.textTertiary,
          fontSize: 11.sp,
          fontWeight: live ? FontWeight.w600 : FontWeight.w500,
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
      // A stacked column's names may sit off centre, moved in from the
      // row's edge: each station is on its own row there.
      final centred = geo.branches
          ? room
          : math.min(room, 2 * math.min(x - lo, hi - x));
      if (names.length > 1 && widthOf(label) > centred) {
        label = '${names.first} +${names.length - 1}';
      }
      final width = math.min(widthOf(label).ceilToDouble() + 2, room);
      out.add(Positioned(
        left: (x - width / 2).clamp(lo, math.max(lo, hi - width)),
        // Legs from several balances: under the lowest leg's amount.
        top: geo.branches
            ? lowest + look.stackedNameDy
            : look.nameTop,
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

  /// In a row of parallel legs, under the start of each source's leg:
  /// its amount, small and quiet ("\$4.18"). Only seen: the status line
  /// and the leg's own line say it for a screen reader.
  List<Widget> _amounts(BuildContext context, _Geometry geo) {
    final money = widget.money;
    if (!geo.branches || money == null) return const [];
    final c = context.colors;
    final plan = _scene.plan;
    final look = _scene.look;
    final out = <Widget>[];
    for (var i = 0; i < plan.roads.length; i++) {
      final road = plan.roads[i];
      final path = geo.paths[i];
      if (path == null || road.usd <= 0) continue;
      if (plan.roads.any((r) => r.to == road.from)) continue;
      out.add(Positioned(
        key: ValueKey('money-steps-leg-amount-${plan.stations[road.from].id}'),
        left: path.start.dx,
        top: path.start.dy + look.amountTop,
        child: ExcludeSemantics(
          child: Text(money(road.usd),
              maxLines: 1,
              style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  height: 1.2)),
        ),
      ));
    }
    return out;
  }

  /// A station: a small dot on the line. A hairline ring on the surface
  /// until the money is there, a solid dot in the surface's ink once it
  /// is, with a tiny check in the surface's colour once its part is done
  /// or a small red "!" where the money stopped. The fades are
  /// paint-only.
  Widget _station(
      BuildContext context, int i, _Geometry geo, AppLocalizations l10n) {
    final s = _scene;
    final st = s.plan.stations[i];
    final at = geo.stations[i];
    final look = s.look;
    final r = look.stationR;
    final d = 2 * r;
    final failed = _stationFailedAt(s, i) != null;
    final done = !failed && _stationDoneAt(s, i) != null;
    // A gap in the surface's colour round a dot that overlaps another in
    // its column (one column, several balances).
    final halo = !geo.branches && st.rows > 1 ? 1.r : 0.0;
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
            if (halo > 0)
              Positioned(
                left: -halo,
                top: -halo,
                width: d + 2 * halo,
                height: d + 2 * halo,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: look.background, shape: BoxShape.circle)),
              ),
            // The ring, until the money is there.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: look.background,
                    shape: BoxShape.circle,
                    border: Border.all(color: look.track, width: 1)),
              ),
            ),
            // The dot, once it is.
            Positioned.fill(
              child: _Fade(
                clock: _clock,
                opacity: () => _stationAlpha(s, i, _now),
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: look.fill, shape: BoxShape.circle)),
              ),
            ),
            if (failed || done)
              Positioned.fill(
                child: _Fade(
                  clock: _clock,
                  opacity: () => _badgeAlpha(s, i, _now),
                  child: CustomPaint(
                    key: ValueKey('money-steps-station-'
                        '${failed ? 'failed' : 'done'}-${st.id}'),
                    painter: _StationMarkPainter(
                        failed: failed,
                        ink: look.background,
                        failedFill: look.failed),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A station's mark once its part is done (a tiny check in the
/// surface's colour on its dot) or where the money stopped (a red dot
/// with a small "!").
class _StationMarkPainter extends CustomPainter {
  const _StationMarkPainter(
      {required this.failed, required this.ink, required this.failedFill});
  final bool failed;
  final Color ink;
  final Color failedFill;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, d * 0.14)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = ink;
    if (failed) {
      canvas.drawCircle(c, d / 2, Paint()..color = failedFill);
      canvas.drawLine(Offset(c.dx, c.dy - d * 0.24), Offset(c.dx, c.dy + d * 0.04), line);
      canvas.drawCircle(Offset(c.dx, c.dy + d * 0.22), d * 0.08,
          Paint()..color = ink);
      return;
    }
    canvas.drawPath(
        Path()
          ..moveTo(c.dx - d * 0.2, c.dy + d * 0.02)
          ..lineTo(c.dx - d * 0.05, c.dy + d * 0.17)
          ..lineTo(c.dx + d * 0.22, c.dy - d * 0.14),
        line);
  }

  @override
  bool shouldRepaint(_StationMarkPainter old) =>
      old.failed != failed || old.ink != ink || old.failedFill != failedFill;
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

/// When every road into station [i] had landed (null while one has
/// not), and how long the last one's dash took.
(double, double)? _allLandedAt(_Scene s, int i) {
  double? latest;
  var dash = _kDash;
  for (final r in s.plan.roads.where((r) => r.to == i)) {
    final at = _roadArrivedAt(s, r);
    if (at == null) return null;
    if (latest == null || at > latest) {
      latest = at;
      for (final k in r.segments) {
        dash = s.fx[s.keys[k]]?.dashMs ?? dash;
      }
    }
  }
  return latest == null ? null : (latest, dash);
}

/// How far the shared line from the merge point into station [i] is
/// filled at [now]: nothing until every leg into it landed, then filling
/// over one dash.
double _trunkLit(_Scene s, int i, double now) {
  final landed = _allLandedAt(s, i);
  if (landed == null) return 0;
  final (at, dash) = landed;
  if (s.still || !at.isFinite) return 1;
  return Curves.easeInOutCubic.transform(_unit((now - at) / dash));
}

/// When the money reached station [i]: the first road into it landed,
/// or, into a merge point, its shared line filled; negative infinity
/// when it was there before the view (a source), null while not yet.
double? _stationArrivedAt(_Scene s, int i) {
  final into = s.plan.roads.where((r) => r.to == i);
  if (into.isEmpty) return double.negativeInfinity;
  if (s.geo?.trunks.containsKey(i) ?? false) {
    final landed = _allLandedAt(s, i);
    if (landed == null) return null;
    final (at, dash) = landed;
    return at.isFinite ? at + dash : at;
  }
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

/// How far station [i]'s dot shows at [now]: in as the money gets there.
double _stationAlpha(_Scene s, int i, double now) =>
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

/// Whether the destination has sub-steps of its own to run once the
/// money is there (its pulse shows while they do).
bool _destinationWorks(MoneyJourneyPlan plan) => plan.checkpoints.any((k) =>
    plan.lines[k].status != MoneyStepStatus.fellBack &&
    plan.roads.every((r) => !r.segments.contains(k)));

/// The destination's pulse now, 0..1: in once the money is all there
/// (as the coin sinks in) while its sub-steps run, out as its check or
/// its "!" comes.
double _ringAlpha(_Scene s, double now) {
  final plan = s.plan;
  final dest = plan.destination;
  if (dest == null || !_destinationWorks(plan)) return 0;
  final landed = _allLandedAt(s, dest);
  if (landed == null && plan.roads.any((r) => r.to == dest)) return 0;
  var from = landed == null ? double.negativeInfinity : landed.$1;
  if (from.isFinite) {
    if (s.geo?.trunks.containsKey(dest) ?? false) from += landed!.$2;
    from += _kSwap;
  }
  final end = _stationFailedAt(s, dest) ?? _stationDoneAt(s, dest);
  final fadeIn = _fadeIn(s, from, now, _kStationFade);
  final fadeOut = _fadeIn(s, end, now, _kBadgeFade);
  return fadeIn * (1 - fadeOut);
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

/// The Investing and Predictions stations' marks.
const String _kInvestingMarkAsset = 'lib/assets/hyperliquid-logo.svg';
const String _kPredictionsMarkAsset = 'lib/assets/polymarket-logo.svg';

/// The mark a balance's station and its coin wear, as an SVG asset (null
/// for the outside world, drawn as an arrow on grey).
String? _markAssetOf(MoneyPlace? place) => switch (place) {
      MoneyPlace.bitcoin => kBitcoinMarkAsset,
      MoneyPlace.dollars => kUsdMarkAsset,
      MoneyPlace.investing => _kInvestingMarkAsset,
      MoneyPlace.predictions => _kPredictionsMarkAsset,
      null => null,
    };

/// The balances' marks as pictures, for the coin: loaded once for the
/// app's life. Until one is, its coin is a plain disc in its colour
/// (never a bare "\$").
final Map<String, PictureInfo> _marks = {};
Future<void>? _marksLoading;

Future<void> _loadMarks() => _marksLoading ??= Future.wait([
      for (final asset in const [
        kBitcoinMarkAsset,
        kUsdMarkAsset,
        _kInvestingMarkAsset,
        _kPredictionsMarkAsset,
      ])
        vg
            .loadPicture(SvgAssetLoader(asset), null)
            .then<void>((p) => _marks[asset] = p, onError: (Object _) {}),
    ]).then<void>((_) {
      // Any that failed load again next time a view opens.
      if (_marks.length < 4) _marksLoading = null;
    });

/// Loads the coin's marks now (a test that renders frames waits for
/// them).
@visibleForTesting
Future<void> precacheMoneyJourneyMarks() => _loadMarks();

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

/// Where Sal walks on to once road [road]'s money is there: along the
/// rest of its line (round its corner, along the shared line) to
/// beside the station it goes to, at about 80 px a second; null while
/// it is not there yet. Under Reduce Motion, and for a road that
/// landed before the view, he is beside it at once.
Offset? _salWalk(_Scene s, _Geometry geo, JourneyRoad road, double now,
  double half, double behind) {
  final plan = s.plan;
  final look = s.look;
  final into = plan.roads.indexOf(road);
  final trunk = geo.trunks[road.to];
  final double? at;
  if (trunk != null) {
    at = _allLandedAt(s, road.to)?.$1;
  } else {
    at = _roadLit(s, road, now) >= 1 ? _roadArrivedAt(s, road) : null;
  }
  if (at == null) return null;
  final beside = _besideStation(s, geo, road.to);
  // The way on: from where he waited to beside the station.
  final way = <Offset>[];
  final path = geo.branches ? geo.paths[into] : null;
  if (path != null && path.length > 0) {
    final from = math.max(half / path.length,
        math.min(path.coinStop - behind / path.length, _kHold));
    final d0 = from * path.length;
    way.add(path.at(from));
    for (var i = 1; i < path.points.length; i++) {
      if (path.cum[i] > d0) way.add(path.points[i]);
    }
    if (trunk != null) way.addAll(trunk.points.skip(1));
  } else {
    way.add(Offset(
        math.max(geo.tipX(plan, road, 0) + half,
            math.min(geo.tipX(plan, road, 1) - behind,
                geo.tipX(plan, road, _kHold))),
        look.rowY));
  }
  // Never past beside: the line's end on the station's row is
  // dropped for it.
  while (way.length > 1 &&
      (way.last.dy - beside.dy).abs() < 0.5 &&
      way.last.dx >= beside.dx) {
    way.removeLast();
  }
  way.add(beside);
  final walk = _RoadPath(way);
  if (s.still || !at.isFinite || walk.length <= 0) return beside;
  final dur = (walk.length / 0.08).clamp(500.0, 2200.0);
  return walk.at(Curves.easeInOut.transform(_unit((now - at) / dur)));
}

/// Where Sal waits beside station [i]: on the line, left of its dot
/// (clear of its pulse), with room between him and it for the coin he
/// sets down.
Offset _besideStation(_Scene s, _Geometry geo, int i) {
  final look = s.look;
  final st = geo.stations[i];
  return Offset(
      st.dx -
          look.stationR -
          look.tipGap -
          look.pulseReach -
          look.salHalf -
          (2 * look.coinR * _kHeldScale + 2),
      st.dy);
}

/// Sal's mark: on the line a little behind the coin while it glides,
/// then (once it parked there, the leg still running) right up to it to
/// fetch it; never past ~78% of the leg. At the start of the first line
/// before it leaves; beside the destination when nothing travels; once
/// the money is there, on along the line to beside the station.
Offset _salTarget(_Scene s, _Geometry geo, double now) {
  final plan = s.plan;
  final look = s.look;
  final half = look.salHalf;
  // Taking the coin up: where he stands for it.
  final pick = s.pickupPos;
  if (pick != null && _picking(s, now)) return pick;
  if (plan.chain.isEmpty) {
    return _besideStation(s, geo, plan.destination ?? 0);
  }
  var k = 0;
  for (var i = 0; i < plan.chain.length; i++) {
    if (_roadLit(s, plan.roads[plan.chain[i]], now) > 0) k = i;
  }
  final road = plan.roads[plan.chain[k]];
  final f = _roadLit(s, road, now);
  // Carrying the coin, or the coin parked while its leg runs: at it (he
  // fetches it); else a little behind it.
  final parked = _waiting(s) &&
      f < 1 &&
      (geo.coinOnRoad(plan, road, f, look) -
                  geo.coinOnRoad(
                      plan, road, _roadLit(s, road, now + 120), look))
              .distance <
          0.05;
  final behind = s.carry || parked ? 0.0 : look.coinR + half + 4;
  // Once the money is there (into a merge point: once every leg landed
  // and the shared line fills) he walks on along the line and waits
  // beside the station, left of its pulse, while it works.
  final on = _salWalk(s, geo, road, now, half, behind);
  if (on != null) return on;
  if (geo.branches) {
    // Along the leg's own row: a little behind the coin, never past
    // the hold, and never round a corner or onto a merge point (he
    // waits there, behind where the coin stopped).
    final path = geo.paths[plan.roads.indexOf(road)];
    if (path == null || path.length <= 0) {
      return _besideStation(s, geo, road.to);
    }
    final lo = half / path.length;
    final want = math.min(math.min(f, path.coinStop) - behind / path.length,
        _kHold);
    return path.at(math.max(lo, want));
  }
  final start = geo.tipX(plan, road, 0) + half;
  final x = math.min(
      geo.tipX(plan, road, f) - behind, geo.tipX(plan, road, _kHold));
  return Offset(math.max(start, x), look.rowY);
}


/// Where Sal stands at the start of [road], before the coin leaves.
Offset _salStart(_Scene s, _Geometry geo, JourneyRoad road) {
  final plan = s.plan;
  final half = s.look.salHalf;
  if (geo.branches) {
    final path = geo.paths[plan.roads.indexOf(road)];
    if (path != null && path.length > 0) return path.at(half / path.length);
  }
  return Offset(geo.tipX(plan, road, 0) + half, s.look.rowY);
}

typedef _Coin = ({Offset at, MoneyPlace? place, double alpha, double scale});

/// The coin left to itself (not in Sal's mouth): gliding on its road,
/// resting above the station it reached, sinking in.
_Coin? _freeCoin(_Scene s, _Geometry geo, double now) {
  final plan = s.plan;
  final look = s.look;
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
  final arrived = via == null ? null : _roadArrivedAt(s, via);
  // Into a merge point it waits before the corner (the shared line is
  // the legs' together), and fades out there once its leg landed:
  // never parked at the merge point.
  if (on == null && via != null && geo.trunks.containsKey(via.to)) {
    if (s.still || arrived == null || !arrived.isFinite) return null;
    final t = _unit((now - arrived) / _kSwap);
    if (t >= 1) return null;
    return (
      at: geo.coinOnRoad(plan, via, 1, look),
      place: plan.stations[via.from].place,
      alpha: 1 - t,
      scale: 1.0,
    );
  }
  var at = on ?? geo.restAt(look, station);
  place ??= plan.stations[station].place;
  var alpha = 1.0;
  var scale = 1.0;
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
  // At a destination with sub-steps of its own it sinks in once it
  // turned into its currency, and the pulse takes over (while the
  // journey waits it stays for Sal to fetch); elsewhere it sinks in
  // once everything is done. Then it is gone.
  final works = station == plan.destination &&
      _destinationWorks(plan) &&
      !_waiting(s);
  if (on == null && (works || s.outcome == _Outcome.success)) {
    double start;
    if (works) {
      if (s.still || arrived == null || !arrived.isFinite) return null;
      start = arrived + _kSwap - 150;
    } else {
      start = math.max(s.outcomeAt, arrived ?? double.negativeInfinity);
      for (final k in plan.checkpoints) {
        final d = s.fx[s.keys[k]]?.doneAt;
        if (d != null) start = math.max(start, d);
      }
    }
    final t = _unit((now - start - 150) / _kSink);
    if (t >= 1) return null;
    final e = Curves.easeIn.transform(t);
    final lineY = geo.stations[station].dy;
    at = Offset(at.dx, at.dy + (lineY - at.dy) * e);
    alpha *= 1 - e;
    scale = 1 - 0.4 * e;
  }
  return (at: at, place: place, alpha: alpha, scale: scale);
}


// ─────────────────────────────────────────────────────────────────────
// Sal's waiting moods
// ─────────────────────────────────────────────────────────────────────

/// How Sal waits while a step runs and the money is parked (founder,
/// 27 October 2026), by how long the wait has lasted: [fetch] (0–8 s,
/// sitting with the coin in his mouth like a ball, a wag every 2 s),
/// [sniff] (8–25 s, the coin at his paws, nose down, padding back and
/// forth along the line with small sniff puffs), [settle] (25 s on, with
/// "Taking longer than usual": lying, chin on his paws, a breath every
/// 3 s, ears up and a small "!" when the step reports news). [none]
/// while he walks, hops, or nothing waits.
enum SalMood { none, fetch, sniff, settle }

/// Whether the journey waits on a step, seen live: one runs and nothing
/// has ended. Under Reduce Motion too (still poses); never in a record.
bool _waiting(_Scene s) =>
    s.live &&
    s.outcome == _Outcome.none &&
    s.plan.lines.any((l) => l.status == MoneyStepStatus.running);

/// The station the money waits on (as [_workingStation], Reduce Motion
/// or not).
int? _waitStation(_Scene s) {
  if (!_waiting(s)) return null;
  final plan = s.plan;
  for (final i in plan.chain) {
    if (_roadRuns(plan, plan.roads[i])) return plan.roads[i].to;
  }
  for (final r in plan.roads) {
    if (_roadRuns(plan, r)) return r.to;
  }
  return plan.destination;
}

/// Which wait this is: the station, how far the coin got, and whether
/// all the money is there. News inside one wait (a sub-step, a sub-leg)
/// keeps its mood; a new wait starts at fetch.
String? _waitKeyOf(_Scene s, double now) {
  final st = _waitStation(s);
  if (st == null) return null;
  return '$st|${_spotOf(s, now)}|${_allLandedAt(s, st) != null}';
}

/// The waiting clips the contract promises (the manifest's `waiting`
/// group; sal_sprite.dart), by what Sal does while the money waits
/// (founder, 31 October 2026): fetching he paces, sniffs the trail or
/// digs; sniffing he sniffs the trail or thinks; settled he sits (sitting
/// down first) or points; a success is a jump then the wag; a failure a
/// shake of the head then sad. Never the same clip twice in a row; a clip
/// not decoded (not rendered yet, not registered) is skipped, and with
/// none of a pool there the mood's own clip from the first batch stands
/// in. The mood timing ([_moodOf]) is untouched.
const List<String> _kFetchClips = ['body_pace', 'body_sniff_trail', 'body_dig'];
const List<String> _kSniffClips = ['body_sniff_trail', 'body_think'];
const List<String> _kSettleClips = ['body_sit', 'body_point'];

/// The coin clips ([_salCarries]): he takes the coin up from the floor,
/// carries it in his mouth, sets it down; the coin is in the render.
const String _kSalPickup = 'body_pickup';
const String _kSalCarry = 'body_carry';
const String _kSalDrop = 'body_drop';
const Set<String> _kSalCoinClips = {_kSalPickup, _kSalCarry, _kSalDrop};

/// How fast he walks with the coin (px a ms, for a 64 px Sal).
const double _kSalCarrySpeed = 0.12;

/// Every clip the journey's Sal can wear ([_paintSalSprite]): decoded
/// once when a view mounts ([_warmSalClips]), so no switch waits on a
/// read.
const List<String> _kSalJourneyClips = [
  _kSalPickup,
  _kSalCarry,
  _kSalDrop,
  'body_idle',
  'body_walk',
  'body_sit_down',
  'body_sit',
  'body_wag',
  'body_sad',
  'body_sniff',
  'body_jump',
  'body_shake_no',
  ..._kFetchClips,
  ..._kSniffClips,
  ..._kSettleClips,
];

/// Where the coin sits in a 3D clip's cell, in the rig's 16-unit box
/// (the sheets' cells: x right, y down, his feet at 15): the coin's
/// centre at his mouth, its top edge under the nose, so it reads as a
/// ball held in the mouth with the eyes clear above it; null for a clip
/// that cannot hold it (the head down on the trail or in the ground, or
/// pacing about his spot), where it lies on the line at his paws
/// ([_kSalPawsX]) instead. Measured on the v5 renders (the eyes'
/// centroid; the coin, ~3 units across, centred ~3.8 under it); a
/// re-render that moves the head moves these.
Offset? _salMuzzleOf(String? clip) => switch (clip) {
      'body_sit' => const Offset(7.9, 10.6),
      'body_sit_down' => const Offset(8.5, 9.8),
      'body_point' => const Offset(8.3, 8.8),
      'body_think' => const Offset(8.3, 10.4),
      'body_wag' => const Offset(7.7, 9.9),
      'body_pace' || 'body_dig' || 'body_sniff_trail' => null,
      // body_idle, body_walk, body_sad, body_shake_no, body_jump,
      // body_sniff: standing, the head up.
      _ => const Offset(7.5, 10.2),
    };

/// Where his paws are across the cell (the body's centre, x), for the
/// coin set down on the line.
const double _kSalPawsX = 7.6;

/// The scenes between which a clip waits for its boundary before giving
/// way: the parked moods. Into or out of a walk, a hop or a stop the
/// switch is at once (he has moved, or stopped).
const Set<String> _kSalSoftScenes = {'fetch', 'sniff', 'settle', 'idle'};

Future<void>? _salWarming;

/// Pre-decodes the `waiting` group and the first-batch clips he wears, at
/// the device's density, and reads the coin clips' anchors, once for the
/// app's life.
Future<void> _warmSalClips() => _salWarming ??= () async {
      final density = _salDensity();
      await SalSpriteCache.warmGroup('waiting',
          defaults: _kSalJourneyClips, density: density);
      await SalSpriteCache.warm(_kSalJourneyClips, density);
      await SalCoinAnchors.load();
    }();

/// The sheets' density on this device.
int _salDensity() => SalSpriteCache.densityFor(
    WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio ??
        2.0);

/// Whether the render carries the coin: the carry clip decoded and its
/// anchors read. Until then (or without them) the coin is painted and
/// glides on its own, Sal fetching it.
bool _salCarries() =>
    SalSpriteCache.peek(_kSalCarry, _salDensity()) != null &&
    SalCoinAnchors.peek(_kSalCarry, 0) != null;

/// One one-shot's length in ms; 0 while it is not decoded (skipped).
double _salOneShot(String name) {
  final c = SalSpriteCache.peek(name, _salDensity());
  return c == null ? 0 : _salClipLength(c);
}

/// Whether he is taking the coin up now (standing still for it).
bool _picking(_Scene s, double now) =>
    s.pickupAt != null && !s.still && now < s.pickupUntil;

/// Whether the render still has the coin to set down: on his way to
/// where he stops, or setting it down.
bool _dropPending(_Scene s, double now) =>
    s.dropInRender &&
    !s.still &&
    s.dropAt != null &&
    (s.dropClipAt == null || now < s.dropUntil);

/// While he carries the coin along [road] in the render, its travelled
/// part ends where he is: the money is where he has got it to.
bool _salLeads(_Scene s, int road, double now) {
  if (!s.salCarries || !s.carry || s.still || s.salX == null) return false;
  final chain = s.plan.chain;
  final spot = _spotOf(s, now);
  return spot < chain.length && chain[spot] == road;
}

/// The balance's mark on the coin the render carries, centred on it at
/// [c] (its rim's radius [r] on screen): about 1.2 of its radius tall,
/// inside the rim, squashed as the coin is foreshortened ([roundness]),
/// none lying too flat to read (under half round). The mark the painted
/// coin wears (never a bare "\$"); its colour alone while it loads.
void _paintCoinMark(Canvas canvas, Offset c, double r, double roundness,
    MoneyPlace? place, double alpha) {
  if (alpha <= 0 || roundness < 0.5) return;
  final mr = 0.6 * r;
  final box = Rect.fromCircle(center: Offset.zero, radius: mr);
  canvas
    ..save()
    ..translate(c.dx, c.dy)
    ..scale(1, roundness.clamp(0.0, 1.0));
  if (alpha < 1) {
    canvas.saveLayer(
        box.inflate(1), Paint()..color = Colors.white.withValues(alpha: alpha));
  }
  final asset = _markAssetOf(place);
  final mark = asset == null ? null : _marks[asset];
  if (mark != null && mark.size.width > 0 && mark.size.height > 0) {
    final k = math.max(
        box.width / mark.size.width, box.height / mark.size.height);
    canvas
      ..clipPath(Path()..addOval(box))
      ..translate(-mark.size.width * k / 2, -mark.size.height * k / 2)
      ..scale(k, k)
      ..drawPicture(mark.picture);
  } else {
    canvas.drawCircle(Offset.zero, mr, Paint()..color = _placeColor(place));
    if (asset == null) {
      const glyph = Icons.arrow_outward_rounded;
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(glyph.codePoint),
          style: TextStyle(
            inherit: false,
            fontFamily: glyph.fontFamily,
            package: glyph.fontPackage,
            fontSize: mr * 1.4,
            fontWeight: FontWeight.w800,
            height: 1,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      tp.dispose();
    }
  }
  if (alpha < 1) canvas.restore();
  canvas.restore();
}

/// One clip's length in ms.
double _salClipLength(SalClip c) => c.frames / c.fps * 1000;

/// How close to a boundary (ms) counts as on it: the clock is a double.
const double _kSalBeatSlack = 1.0;

/// The last boundary of a [length] ms loop at or before [elapsed] (within
/// [_kSalBeatSlack]), from its start.
double _salBeatBefore(double elapsed, double length) =>
    ((elapsed + _kSalBeatSlack) / length).floor() * length;

/// The first boundary of a [length] ms loop at or after [elapsed] (within
/// [_kSalBeatSlack]), from its start.
double _salBeatAfter(double elapsed, double length) =>
    ((elapsed - _kSalBeatSlack) / length).ceil() * length;

/// The frame [c] shows [elapsed] ms in.
int _salFrameAt(SalClip c, double elapsed) {
  final raw = (elapsed / 1000 * c.fps).floor();
  return c.loop ? raw % c.frames : raw.clamp(0, c.frames - 1);
}

/// Puts [to] on at [at] (its frame 0 there), the clip before frozen on
/// the frame it showed at [at] for the dissolve (none under Reduce Motion).
void _salSwitch(_Scene s, String to, double at,
    {required String? from, required SalClip? fromClip}) {
  if (from != null && fromClip != null && !s.still) {
    s.salFadeFrom = from;
    s.salFadeFrame = _salFrameAt(fromClip, at - s.salClipAt);
    s.salFadeAt = at;
  } else {
    s.salFadeFrom = null;
  }
  s.salClip = to;
  s.salClipAt = at;
}

/// Draws the 3D Sal for the journey (see the call site); false when the
/// clip is not decoded yet, so the rig draws him instead.
bool _paintSalSprite(Canvas canvas, _Scene s, Offset origin, double u,
    double now,
    {required bool still, required bool walking, required SalMood mood}) {
  final density = _salDensity();
  SalClip? peek(String name) => SalSpriteCache.peek(name, density);
  final carries = s.salCarries;

  // The coin in the render: set down where he stops with it (body_drop),
  // then the hop.
  if (carries &&
      !still &&
      !walking &&
      s.dropInRender &&
      s.dropAt != null &&
      s.dropClipAt == null) {
    s.dropClipAt = now;
    s.dropUntil = now + _salOneShot(_kSalDrop);
    s.hopAt = s.dropUntil;
    s.salBusyUntil = math.max(s.salBusyUntil, s.dropUntil + _kHop + 200);
  }
  final holding = carries && (s.carry || _dropPending(s, now));

  // What he is doing: the scene, the clips it rotates, the one-shot that
  // opens it, and the clip that stands in while none of them is decoded.
  final String scene;
  List<String> pool;
  String? opener;
  final String standIn;
  double? frameTime;
  if (still) {
    // Holding the coin in the render: its held pose.
    final held = carries && s.carry;
    scene = held ? 'still-carry' : 'still';
    pool = const [];
    standIn = held ? _kSalCarry : 'body_idle';
    frameTime = 0;
  } else if (carries && _picking(s, now)) {
    scene = 'pickup';
    pool = const [_kSalPickup];
    standIn = _kSalPickup;
  } else if (carries &&
      s.dropInRender &&
      s.dropClipAt != null &&
      now < s.dropUntil) {
    scene = 'drop';
    pool = const [_kSalDrop];
    standIn = _kSalDrop;
  } else if (holding && walking) {
    scene = 'carry';
    pool = const [_kSalCarry];
    standIn = _kSalCarry;
  } else if (s.outcome == _Outcome.failure) {
    scene = 'failure';
    opener = 'body_shake_no';
    pool = const ['body_sad'];
    standIn = 'body_sad';
  } else if (s.outcome == _Outcome.success || _hopping(s, now)) {
    scene = 'success';
    opener = 'body_jump';
    pool = const ['body_wag'];
    standIn = 'body_wag';
  } else if (walking) {
    scene = 'walk';
    pool = const ['body_walk'];
    standIn = 'body_walk';
  } else if (mood == SalMood.fetch) {
    scene = 'fetch';
    pool = _kFetchClips;
    standIn = 'body_walk';
  } else if (mood == SalMood.sniff) {
    scene = 'sniff';
    pool = _kSniffClips;
    standIn = 'body_sniff';
  } else if (mood == SalMood.settle) {
    scene = 'settle';
    opener = 'body_sit_down';
    pool = _kSettleClips;
    standIn = 'body_sit';
  } else {
    scene = 'idle';
    pool = const ['body_idle'];
    standIn = 'body_idle';
  }

  final name = _salClipRun(s, now,
      scene: scene, pool: pool, opener: opener, standIn: standIn, peek: peek);
  final clip = peek(name);
  if (clip == null) return false;
  final t = frameTime ?? (now - s.salClipAt);
  final frame = frameTime == null
      ? _salFrameAt(clip, t)
      : (t / 1000 * clip.fps).floor().clamp(0, clip.frames - 1);
  final dst = Rect.fromLTWH(origin.dx, origin.dy, 16 * u, 16 * u);
  // The coin a coin clip renders: the balance's mark on it at the
  // frame's anchor, and how much of the coin is the render's.
  final held = s.carry
      ? _carriedPlace(s, now)
      : (place: s.dropPlace, alpha: 1.0);
  final cellScale = 16 * u / SalCoinAnchors.cell;
  s.salCoinAt = null;
  s.salCoinFade = 0;
  void coinOn(String clipName, int clipFrame, double alpha) {
    if (!carries || !_kSalCoinClips.contains(clipName)) return;
    final a = SalCoinAnchors.peek(clipName, clipFrame);
    if (a == null) return;
    final c = origin + a.centre * cellScale;
    s.salCoinAt ??= c;
    s.salCoinFade = math.min(1.0, s.salCoinFade + alpha);
    _paintCoinMark(canvas, c, a.r * cellScale, a.roundness, held.place,
        alpha * held.alpha);
  }

  // The dissolve from the clip before (sal_sprite.dart's rule: an exact
  // lerp in a layer, so matching poses pass unseen); none when still.
  final fading = s.salFadeFrom;
  final fromClip = fading == null ? null : peek(fading);
  final fade = fading == null
      ? 1.0
      : ((now - s.salFadeAt) / kSalCrossfade.inMilliseconds).clamp(0.0, 1.0);
  if (fromClip == null || fade >= 1.0 || frameTime != null) {
    if (fading != null) s.salFadeFrom = null;
    canvas.drawImageRect(
      clip.image,
      clip.cell(frame),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    coinOn(name, frame, 1);
    return true;
  }
  canvas.saveLayer(dst, Paint());
  canvas.drawImageRect(
    fromClip.image,
    fromClip.cell(s.salFadeFrame),
    dst,
    Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(255, 255, 255, 1.0 - fade),
  );
  canvas.drawImageRect(
    clip.image,
    clip.cell(frame),
    dst,
    Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(255, 255, 255, fade)
      ..blendMode = BlendMode.plus,
  );
  canvas.restore();
  coinOn(name, frame, fade);
  coinOn(fading!, s.salFadeFrame, 1 - fade);
  return true;
}

/// The clip Sal wears at [now] in [scene]: a new scene starts with its
/// [opener] (a one-shot) when that is decoded, else a pick from [pool];
/// a clip that has played through (a one-shot its length, a loop one
/// cycle) gives way to another of the pool, never the one just played;
/// [standIn] while none of the pool is decoded. A loop alone keeps
/// looping (its start is never reset). Between parked moods
/// ([_kSalSoftScenes]) a new scene waits for the clip on screen to reach
/// its boundary (a loop back at frame 0, a one-shot through); every
/// switch lands exactly on that boundary, the overshoot being the new
/// clip's first moments, and sets up the dissolve ([_salSwitch]).
String _salClipRun(_Scene s, double now,
    {required String scene,
    required List<String> pool,
    String? opener,
    required String standIn,
    required SalClip? Function(String) peek}) {
  final available = [for (final n in pool) if (peek(n) != null) n];
  String pick() {
    final choices = available.length > 1
        ? [for (final n in available) if (n != s.salClipPrev) n]
        : available;
    if (choices.isEmpty) return standIn;
    return choices[s.salRandom.nextInt(choices.length)];
  }

  final current = s.salClip;
  final clip = current == null ? null : peek(current);
  if (s.salScene != scene || current == null) {
    var at = now;
    if (current != null &&
        clip != null &&
        _kSalSoftScenes.contains(s.salScene) &&
        _kSalSoftScenes.contains(scene)) {
      final length = _salClipLength(clip);
      final elapsed = now - s.salClipAt;
      final boundary = clip.loop
          ? s.salClipAt + _salBeatAfter(elapsed, length)
          : s.salClipAt + length;
      // Not there yet: the mood before stays on, its clip playing on.
      if (now < boundary - _kSalBeatSlack) return current;
      // Within a frame of the boundary the new clip starts there; a
      // one-shot held longer starts now.
      at = now - boundary < 1000 / clip.fps ? boundary : now;
    }
    s.salScene = scene;
    // Never the same twice in a row: the clip on screen is the one to
    // avoid (a pool of one keeps it).
    s.salClipPrev = current;
    final first = opener != null && peek(opener) != null ? opener : pick();
    _salSwitch(s, first, at, from: current, fromClip: clip);
    return first;
  }
  if (clip == null) {
    // Lost (never after a decode; defensively): on to the next.
    final next = pick();
    s.salClipPrev = current;
    _salSwitch(s, next, now, from: null, fromClip: null);
    return next;
  }
  final length = _salClipLength(clip);
  final elapsed = now - s.salClipAt;
  if (elapsed < length - _kSalBeatSlack) return current;
  // Played through: the next of the pool, if there is another, from the
  // boundary this pass ended on.
  final boundary = clip.loop
      ? s.salClipAt + _salBeatBefore(elapsed, length)
      : s.salClipAt + length;
  // Never the same twice in a row: the clip on screen is the one to
  // avoid, so the pick is settled on this beat (a pool of one keeps it).
  s.salClipPrev = current;
  final next = pick();
  if (next == current) {
    // A loop alone goes on from where it is; a one-shot alone replays
    // from its end (or from now, held longer than a frame).
    if (!clip.loop) {
      s.salClipAt = elapsed - length < 1000 / clip.fps ? boundary : now;
    }
    return current;
  }
  _salSwitch(s, next, boundary, from: current, fromClip: clip);
  return next;
}

/// Sal's mood at [now].
SalMood _moodOf(_Scene s, double now) {
  if (s.stopMood case final m?) return m;
  final since = s.waitSince;
  if (since == null || !_waiting(s)) return SalMood.none;
  if (!s.still && (s.salWalking || _hopping(s, now))) return SalMood.none;
  final e = now - since;
  if (e < _kSniffAt) return SalMood.fetch;
  if (e < _kSettleAt) return SalMood.sniff;
  return SalMood.settle;
}

bool _hopping(_Scene s, double now) {
  final at = s.hopAt;
  return at != null && !s.still && now >= at && now < at + _kHop;
}

/// The sprite frame [now] falls on in a beat of [period] that started
/// at [start]: its index in the beat, and which beat.
(int frame, int beat) _spriteFrame(double now, double start, double period) {
  final local = math.max(0.0, now - start);
  final beat = local ~/ period;
  return ((local - beat * period) ~/ _kSprite, beat);
}

/// One frame of Sal's mood: the pose (or lying), how far he paced off
/// his spot (px), the sniff puffs, the ears' "!".
class _SalFrame {
  const _SalFrame(this.pose,
      {this.lying = false,
      this.breath = 0,
      this.ears = 0,
      this.blink = 0.45,
      this.dx = 0,
      this.puffs = 0,
      this.exclaim = false,
      this.exclaimDy = 0});
  final KuteDogPose pose;
  final bool lying;
  final double breath;
  final double ears;
  final double blink;
  final double dx;
  final int puffs;
  final bool exclaim;
  final double exclaimDy;
}

const List<double> _kWag = [0.5, -0.15, 0.5, -0.15, 0.5];
const List<double> _kPace = [0, -2, -4, -6, -6, -6, -6, -6, -4, -2, 0, 0];
const List<double> _kBreathe = [0.6, 1, 0.5];

/// Sal's frame in [mood] at [now]: one still pose per mood under Reduce
/// Motion (or once a step stopped), else the mood's sprite beat.
_SalFrame _salFrameOf(_Scene s, SalMood mood, double now) {
  final still = s.still || s.stopMood != null;
  final since = s.waitSince ?? now;
  switch (mood) {
    case SalMood.none:
      return const _SalFrame(KuteDogPose.neutral);
    case SalMood.fetch:
      // Sitting up, the coin in his mouth; a wag every 2 s.
      if (still) return const _SalFrame(KuteDogPose(headBob: -0.2, tail: 0.15));
      final (f, beat) = _spriteFrame(now, since, _kFetchBeat);
      return _SalFrame(KuteDogPose(
        headBob: -0.2,
        tail: f < _kWag.length ? _kWag[f] : 0.15,
        blink: beat % 3 == 2 && f == 7 ? 1 : 0,
      ));
    case SalMood.sniff:
      // Nose down; pads back along the line and home, sniffing.
      if (still) return const _SalFrame(KuteDogPose(sniff: 1, blink: 0.4));
      final (f, _) = _spriteFrame(now, since + _kSniffAt, _kSniffBeat);
      final pacing = f < _kPace.length;
      final step = pacing && f > 0 && _kPace[f] != _kPace[f - 1];
      return _SalFrame(
        KuteDogPose(
          sniff: 1,
          blink: 0.4,
          headBob: f == 5 || f == 7 ? 0.35 : 0,
          pawLeft: step && f.isOdd ? -0.6 : 0,
          pawRight: step && f.isEven ? -0.6 : 0,
          tail: step ? 0.2 : 0.05,
        ),
        dx: pacing ? _kPace[f] : 0,
        puffs: f >= 4 && f <= 7 ? [1, 2, 3, 3][f - 4] : 0,
      );
    case SalMood.settle:
      // Lying, chin on his paws; a breath every 3 s; ears up and a "!"
      // on news.
      if (still) return const _SalFrame(KuteDogPose.neutral, lying: true);
      final (f, _) = _spriteFrame(now, since + _kSettleAt, _kSettleBeat);
      final perk = s.perkAt;
      final p = perk == null ? -1.0 : now - perk;
      final perked = p >= 0 && p < _kPerk;
      final pf = perked ? p ~/ _kSprite : 0;
      return _SalFrame(
        KuteDogPose.neutral,
        lying: true,
        breath: f < _kBreathe.length ? _kBreathe[f] : 0,
        ears: perked ? -0.55 : 0,
        blink: perked ? 0 : 0.45,
        exclaim: perked && pf < 7,
        exclaimDy: perked && pf < 2 ? -0.8 : 0,
      );
  }
}

/// Where the coin Sal has sits at [now]: in his mouth (fetching,
/// walking, hopping), at his paws on the line (sniffing, lying); on its
/// way into his mouth while he takes it. Null before he was drawn.
({Offset at, double scale})? _heldAt(_Scene s, double now) {
  final x = s.salX;
  final y = s.salY;
  if (x == null || y == null) return null;
  // In the render: the coin the clip draws, where it is this frame.
  final rendered = s.salSprite ? s.salCoinAt : null;
  if (rendered != null) return (at: rendered, scale: _kHeldScale);
  final look = s.look;
  // His feet stand on the track's top edge; the anchors scale with the
  // box that drew him (the 3D clip's, or the smaller rig's).
  final u = (s.salSprite ? look.salSize : look.rigSize) / 16;
  final feet = y - look.trackH / 2;
  final r = look.coinR * _kHeldScale;
  // At the 3D body's muzzle and paws when a clip drew him (the body
  // faces the viewer, so the coin sits on him, not beside him), else at
  // the rig's (the rig faces right: the coin in front of its nose).
  final muzzle = s.salSprite ? _salMuzzleOf(s.salClip) : null;
  final ground = s.salSprite
      ? Offset(x + (_kSalPawsX - 8) * u, feet - r)
      : Offset(x + 8 * u + 1 + r, feet - r);
  final mouth = !s.salSprite
      ? Offset(x, feet - 4.5 * u + s.salBob)
      : muzzle == null
          ? ground
          : Offset(x + (muzzle.dx - 8) * u, feet - (15 - muzzle.dy) * u);
  final mood = _moodOf(s, now);
  var at = switch (mood) {
    SalMood.sniff || SalMood.settle => ground,
    _ => mouth,
  };
  if (mood == SalMood.sniff && !s.still && s.stopMood == null) {
    // Set down over one frame as he starts to sniff.
    final since = s.waitSince ?? now;
    if (now - since - _kSniffAt < _kSprite) {
      at = Offset.lerp(mouth, ground, 0.5)!;
    }
  }
  var scale = _kHeldScale;
  final from = s.carryFrom;
  final t0 = s.carryAt;
  if (from != null && t0 != null && !s.still && now < t0 + _kPickUp) {
    // Taken in three frames, with a little arc.
    final t = (math.max(0.0, now - t0) ~/ _kSprite + 1) / 3;
    at = Offset.lerp(from, at, t)!.translate(0, -5 * math.sin(math.pi * t));
    scale = 1 + (_kHeldScale - 1) * t;
  }
  return (at: at, scale: scale);
}

/// The currency the coin Sal carries is in at [now], and its opacity
/// (dipping as it turns into a station's currency where it arrives).
({MoneyPlace? place, double alpha}) _carriedPlace(_Scene s, double now) {
  final plan = s.plan;
  final chain = plan.chain;
  if (plan.stations.isEmpty) return (place: null, alpha: 1);
  if (chain.isEmpty) {
    return (place: plan.stations[plan.destination ?? 0].place, alpha: 1);
  }
  final spot = _spotOf(s, now);
  if (spot < chain.length) {
    return (place: plan.stations[plan.roads[chain[spot]].from].place, alpha: 1);
  }
  final via = plan.roads[chain.last];
  final from = plan.stations[via.from].place;
  final to = plan.stations[via.to].place;
  double? arrived;
  if (s.geo?.trunks.containsKey(via.to) ?? false) {
    final landed = _allLandedAt(s, via.to);
    if (landed == null) return (place: from, alpha: 1);
    arrived = landed.$1.isFinite ? landed.$1 + landed.$2 : landed.$1;
  } else {
    arrived = _roadArrivedAt(s, via);
  }
  if (arrived == null) return (place: from, alpha: 1);
  if (s.still || !arrived.isFinite) return (place: to, alpha: 1);
  final t = (now - arrived) / _kSwap;
  if (t < 0) return (place: from, alpha: 1);
  if (t >= 1) return (place: to, alpha: 1);
  return (place: t < 0.5 ? from : to, alpha: 1 - 0.6 * math.sin(math.pi * t));
}

/// The coin at [now]: dropped from Sal's mouth into its station (on
/// confirm), in his mouth or at his paws while he has it, else left to
/// itself ([_freeCoin]).
_Coin? _coinOf(_Scene s, _Geometry geo, double now) {
  final dropAt = s.dropAt;
  if (dropAt != null && !s.carry) {
    final t = (now - dropAt) / _kDrop;
    if (t >= 1 && s.dropSink) return null;
    if (t >= 0 && t < 1) {
      final free = s.dropSink ? null : _freeCoin(s, geo, now);
      final to = s.dropTo;
      final _Coin target = free ??
          (
            at: to == null ? s.dropFrom ?? Offset.zero : geo.stations[to],
            place: to == null ? s.dropPlace : s.plan.stations[to].place,
            alpha: 1.0,
            scale: 0.4,
          );
      final e = Curves.easeInOut.transform(t);
      final from = s.dropFrom ?? target.at;
      final at = Offset.lerp(from, target.at, e)!
          .translate(0, -10 * math.sin(math.pi * t));
      final fade =
          s.dropSink ? 1 - Curves.easeIn.transform(_unit((t - 0.55) / 0.45)) : 1;
      return (
        at: at,
        place: t < 0.5 ? s.dropPlace : target.place,
        alpha: target.alpha * fade,
        scale: _kHeldScale + (target.scale - _kHeldScale) * e,
      );
    }
  }
  if (s.carry && s.plan.stations.isNotEmpty) {
    final held = _heldAt(s, now);
    if (held != null) {
      final p = _carriedPlace(s, now);
      return (at: held.at, place: p.place, alpha: p.alpha, scale: held.scale);
    }
  }
  return _freeCoin(s, geo, now);
}

// ─────────────────────────────────────────────────────────────────────
// The painters
// ─────────────────────────────────────────────────────────────────────

/// One track as the map paints it: its path, how far it is filled
/// (0..1) and whether its leg stopped.
class _Track {
  const _Track(this.path, this.f, {required this.stopped});
  final _RoadPath path;
  final double f;
  final bool stopped;
}

/// Behind the stations: the tracks (thin rounded lines in a hairline
/// grey, their travelled part in the surface's ink, each simply ending
/// at the station it goes into; founder, 1 November 2026), the waypoints
/// on them, the pulse on the station the money is heading to and the
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
    final h = look.trackH;
    // A track shorter than its two round caps is not drawn.
    final minLine = 2 * h;
    Paint stroke(Color color, {double? width}) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width ?? h
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final bg = Paint()..color = look.background;
    bool stoppedRoad(JourneyRoad road) =>
        road.segments.any((k) => plan.lines[k].status == MoneyStepStatus.failed);

    // Every track on the row: its path, how far it is filled and whether
    // its leg stopped.
    final tracks = <_Track>[];
    final waypoints = <(Offset, JourneyWaypoint, bool)>[];
    if (geo.branches) {
      // ── Legs from several balances: each its own line ──
      // Every road fills at its own pace from its own station, round its
      // corner into the merge point; the shared line on into the station
      // fills once every one of them landed.
      for (var i = 0; i < geo.paths.length; i++) {
        final path = geo.paths[i];
        if (path == null || path.length < minLine) continue;
        final road = plan.roads[i];
        var f = _roadLit(s, road, now);
        if (f < 1 && _salLeads(s, i, now)) {
          f = math.min(f,
              path.fractionNear(Offset(s.salX!, s.salY ?? path.start.dy)));
        }
        tracks.add(_Track(path, f, stopped: stoppedRoad(road)));
        final n = road.segments.length;
        for (var k = 0; k < road.waypoints.length; k++) {
          final frac = (k + 1) / n;
          waypoints.add((path.at(frac), road.waypoints[k], f >= frac - 1e-6));
        }
      }
      for (final e in geo.trunks.entries) {
        if (e.value.length < minLine) continue;
        tracks.add(_Track(e.value, _trunkLit(s, e.key, now), stopped: false));
      }
    } else {
      // ── One straight track per column gap, and its waypoints ──
      for (var g = 0; g < geo.gaps.length; g++) {
        final (x0, x1) = geo.gaps[g];
        if (x1 - x0 < minLine) continue;
        final r = geo.gapRoad[g];
        final road = r == null ? null : plan.roads[r];
        var local = 0.0;
        var stopped = false;
        if (road != null) {
          final lit = _roadLit(s, road, now);
          final at = geo.gapAt(plan, road, lit);
          if (at != null) {
            local = at.$1 > g ? 1 : (at.$1 < g ? 0 : at.$2);
          }
          if (lit < 1 && _salLeads(s, r!, now)) {
            local =
                math.min(local, ((s.salX! - x0) / (x1 - x0)).clamp(0.0, 1.0));
          }
          stopped = stoppedRoad(road);
        }
        tracks.add(_Track(_RoadPath([Offset(x0, y), Offset(x1, y)]), local,
            stopped: stopped));
        if (road == null) continue;
        final n = road.segments.length;
        for (var k = 0; k < road.waypoints.length; k++) {
          final frac = (k + 1) / n;
          final at = geo.gapAt(plan, road, frac);
          if (at == null || at.$1 != g) continue;
          waypoints.add((
            Offset(x0 + (x1 - x0) * at.$2, y),
            road.waypoints[k],
            local >= at.$2 - 1e-6
          ));
        }
      }
    }

    // The quiet lines first (the shared lines too), so no travelled part
    // is ever under a line where lines meet; then every travelled part,
    // from its line's start to where the money got.
    final grey = stroke(look.track);
    for (final t in tracks) {
      canvas.drawPath(t.path.upTo(1), grey);
    }
    for (final t in tracks) {
      if (t.f <= 0) continue;
      canvas.drawPath(
          t.path.upTo(t.f), stroke(t.stopped ? look.stopped : look.fill));
    }
    for (final (at, w, reached) in waypoints) {
      _waypoint(canvas, at, w, reached, bg);
    }

    // ── The pulse: the station the money is heading to ──
    // The one a leg runs to, or the destination while its own sub-steps
    // run: a 1 px ring in the ink easing out from just past the dot's
    // edge to [_Look.pulseReach] every [_kWorkBreath] (the settle curve,
    // never linear), fading as it goes; one still soft ring under
    // Reduce Motion.
    final dest = plan.destination;
    final ring = _ringAlpha(s, now);
    final live = ring > 0 ? dest : _workingStation(s);
    if (live != null) {
      final c = geo.stations[live];
      final r0 = look.stationR + 2;
      final r1 = look.stationR + look.pulseReach;
      final strength = ring > 0 ? ring : 1.0;
      if (s.still) {
        canvas.drawCircle(c, r0 + 1,
            stroke(look.fill.withValues(alpha: 0.18 * strength), width: 1));
      } else {
        final t = (now % _kWorkBreath) / _kWorkBreath;
        final out = KuteMotion.settle.transform(t);
        final a = 0.3 * (1 - Curves.easeIn.transform(t)) * strength;
        canvas.drawCircle(c, r0 + (r1 - r0) * out,
            stroke(look.fill.withValues(alpha: a), width: 1));
      }
    }

    // ── The destination's checkpoints ──
    if (dest == null) return;
    final dots = _dots(plan);
    if (dots.isEmpty) return;
    final x = geo.stations[dest].dx - (dots.length - 1) * look.dotGap / 2;
    for (var n = 0; n < dots.length; n++) {
      final i = dots[n];
      final c = Offset(x + n * look.dotGap, geo.dotsY);
      final status = plan.lines[i].status;
      if (status == MoneyStepStatus.failed) {
        canvas.drawCircle(c, look.dotR, Paint()..color = look.failed);
      } else if (_doneBy(s, i, now)) {
        canvas.drawCircle(c, look.dotR, Paint()..color = look.fill);
      } else if (status == MoneyStepStatus.running) {
        canvas.drawCircle(
            c, look.dotR - 0.5, stroke(look.fill, width: 1));
        final breath = s.still
            ? 1.0
            : 0.35 +
                0.65 * (0.5 + 0.5 * math.sin(2 * math.pi * now / _kBreath));
        canvas.drawCircle(c, look.dotR * 0.45,
            Paint()..color = look.fill.withValues(alpha: breath));
      } else {
        canvas.drawCircle(
            c, look.dotR - 0.5, stroke(look.track, width: 1));
      }
    }
  }

  /// A sub-leg's waypoint: a small notch in the line (a dot in the
  /// surface's colour), filled in the ink once the travelled part passed
  /// it, red where it stopped.
  void _waypoint(
      Canvas canvas, Offset c, JourneyWaypoint w, bool reached, Paint bg) {
    final look = _scene.look;
    final failed =
        _scene.plan.lines[w.line].status == MoneyStepStatus.failed;
    canvas.drawCircle(c, look.waypointR, bg);
    canvas.drawCircle(
        c,
        look.waypointR * 0.55,
        Paint()
          ..color = failed
              ? look.failed
              : reached
                  ? look.fill
                  : look.track);
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
    return x == null ? null : Offset(x, _scene.salY ?? _scene.look.rowY);
  }

  /// Whether Sal was walking at the last paint.
  bool get walking => _scene.salWalking;

  /// The 3D clip Sal wore at the last paint (the clip the director
  /// chose; see [salSprite] for whether it was decoded and drew him),
  /// for the clip director's tests.
  String? get salClip => _scene.salClip;

  /// Whether a 3D clip drew him at the last paint (else the rig did).
  bool get salSprite => _scene.salSprite;

  /// Whether the clip drew the coin at the last paint (the render carries
  /// it; the painted coin gave way).
  bool get coinInRender => _scene.salCoinFade >= 0.999;

  /// The rendered coin's centre at the last paint, where its mark is
  /// drawn; null when no coin clip drew it.
  Offset? get renderedCoinAt => _scene.salCoinAt;

  /// His box (the 3D clip's), in the screen's units.
  double get salSize => _scene.look.salSize;

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

  /// The mark the coin wears now (an SVG asset; null for the outside
  /// world), the same as its balance's station.
  String? get coinMarkAsset {
    final c = _coin(_now);
    return c == null ? null : _markAssetOf(c.place);
  }

  /// How strongly the destination's pulse shows now, 0..1 (on while its
  /// own sub-steps run, once the money is all there).
  double get destinationRing => _ringAlpha(_scene, _now);

  /// How far the shared line from a merge point into station [id] is
  /// filled now, 0..1; null when no legs merge there.
  double? mergeLitOf(String id) {
    final s = _scene;
    final i = s.plan.stations.indexWhere((st) => st.id == id);
    if (i < 0 || !_geo.trunks.containsKey(i)) return null;
    return _trunkLit(s, i, _now);
  }

  /// Where the legs into station [id] merge, null when none do.
  Offset? mergePointOf(String id) {
    final i = _scene.plan.stations.indexWhere((st) => st.id == id);
    return i < 0 ? null : _geo.trunks[i]?.start;
  }

  /// Sal's waiting mood now.
  SalMood get mood => _moodOf(_scene, _now);

  /// How long Sal has waited at his spot now (null while he does not).
  Duration? get waited {
    final since = _scene.waitSince;
    if (since == null || !_waiting(_scene)) return null;
    return Duration(microseconds: ((_now - since) * 1000).round());
  }

  /// Whether Sal has the coin (in his mouth, or at his paws).
  bool get carrying => _scene.carry;

  /// Whether his ears are up with a "!" over them now (news while he
  /// lies waiting).
  bool get earsPerked {
    final m = mood;
    return m == SalMood.settle && _salFrameOf(_scene, m, _now).exclaim;
  }

  /// Whether he is hopping now (a step confirmed while he had the coin).
  bool get hopping => _hopping(_scene, _now);

  /// Whether a finished record is replaying its journey now.
  bool get replaying {
    final at = _scene.replayAt;
    return at != null && _now < at + _kReplay + 600;
  }

  ({Offset at, MoneyPlace? place, double alpha, double scale})? _coin(
          double now) =>
      _coinOf(_scene, _geo, now);

  @override
  void paint(Canvas canvas, Size size) {
    final s = _scene;
    final look = s.look;
    final now = _now;
    final still = s.still;
    if (s.plan.stations.isEmpty) return;

    // ── Sal ──
    s.salCarries = _salCarries();
    final aim = _salTarget(s, _geo, now);
    final target = aim.dx;
    final was = s.salX;
    var x = target;
    var y = aim.dy;
    if (was != null && !still) {
      final dt = math.max(0.0, now - s.salPaintedAt);
      final k = 1 - math.exp(-dt / _kSalEase);
      x = was + (target - was) * k;
      if ((target - x).abs() < 0.3) x = target;
      final wasY = s.salY ?? aim.dy;
      y = wasY + (aim.dy - wasY) * k;
      if ((aim.dy - y).abs() < 0.3) y = aim.dy;
      if (s.salCarries && (s.carry || _dropPending(s, now))) {
        // With the coin he walks, never dashes.
        final step = Offset(x - was, y - wasY);
        final most = _kSalCarrySpeed * look.salSize / 64 * dt;
        if (step.distance > most) {
          final f = most / step.distance;
          x = was + step.dx * f;
          y = wasY + step.dy * f;
        }
      }
    }
    final walking = !still &&
        was != null &&
        ((x - was).abs() > 0.05 || (y - (s.salY ?? y)).abs() > 0.05);
    s.salX = x;
    s.salY = y;
    s.salPaintedAt = now;
    s.salWalking = walking;
    // The rig's unit (its poses are in its 16-unit box); the 3D clip has
    // its own, larger box below.
    final u = look.rigSize / 16;
    final mood = walking ? SalMood.none : _moodOf(s, now);
    final frame = mood == SalMood.none ? null : _salFrameOf(s, mood, now);
    KuteDogPose pose;
    if (frame != null) {
      pose = frame.pose;
    } else if (_hopping(s, now)) {
      // A step confirmed: a little hop as he drops the coin in.
      final e = now - s.hopAt!;
      final hop = kutePulse(e, 0, 380);
      pose = KuteDogPose(
        lift: 1.8 * hop,
        squash: 1 + 0.08 * hop - 0.12 * kutePulse(e, 360, _kHop),
        earLeft: 0.4 * hop,
        earRight: 0.5 * hop,
        tail: 0.4 * kuteWave(e, 240),
      );
    } else if (still) {
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
    s.salBob = (pose.bodyBob - pose.lift) * u;
    // THE 3D SAL (founder, 31 October 2026, "even on the deposit flow"):
    // the body clips in a 16-unit box, by what he is doing: a failure is
    // sad, a success (and the hop of a step landing) wags, walking and
    // fetching walk, the sniff sniffs, settling sits down then sits, the
    // rest idles. Frame 0 under Reduce Motion. The journey around him
    // (the coin he carries first of all) is painted as ever; only the
    // dog is the render: the clip moves him about his spot and bobs him
    // itself, so the rig's pacing and bob are not added. Until a sheet
    // is decoded (or without one) the rig below draws him, in its own
    // smaller box. Either way his feet (15 of the box's 16 units down)
    // stand on the track's top edge (founder, 1 November 2026).
    final feet = y - look.trackH / 2;
    final su = look.salSize / 16;
    final spriteOrigin = Offset(x - 8 * su, feet - 15 * su);
    s.salSprite = _paintSalSprite(canvas, s, spriteOrigin, su, now,
        still: still, walking: walking, mood: mood);
    if (s.salSprite) {
      s.salBob = 0;
    } else {
      s.salCoinAt = null;
      s.salCoinFade = 0;
      _paintSalRig(canvas, s, frame, pose, u,
          origin: Offset(x - 8 * u + (frame?.dx ?? 0), feet - 15 * u));
    }

    // ── The coin ──
    _paintCoin(canvas, s, now);
  }

  /// The pixel rig's Sal (until the sheets are decoded, or without
  /// them), the sniff puffs and the "!" his ears put up with him.
  void _paintSalRig(Canvas canvas, _Scene s, _SalFrame? frame,
      KuteDogPose pose, double u,
      {required Offset origin}) {
    final look = s.look;
    if (frame != null && frame.lying) {
      paintKuteDogLying(canvas,
          origin: origin,
          unit: u,
          palette: KuteDogPalette.mascot,
          breath: frame.breath,
          ears: frame.ears,
          blink: frame.blink);
      if (frame.exclaim) {
        paintKuteExclaim(canvas,
            origin: origin,
            unit: u,
            at: Offset(14.6, 0.6 + frame.exclaimDy),
            color: look.ink);
      }
    } else {
      paintKuteDog(canvas,
          origin: origin,
          unit: u,
          pose: pose,
          palette: KuteDogPalette.mascot);
    }
    if (frame != null && frame.puffs > 0) {
      // Sniff puffs off his nose, low on the line, rising one by one.
      final nose = origin + Offset(8 * u, 13.6 * u);
      final puff = Paint()..color = look.ink.withValues(alpha: 0.55);
      final d = math.max(1.2, 1.1 * u);
      for (var i = 0; i < frame.puffs; i++) {
        final c = nose + Offset(-4.5 * u - i * 1.6 * u, -0.6 * u - i * 1.3 * u);
        canvas.drawRect(Rect.fromCenter(center: c, width: d, height: d), puff);
      }
    }
  }

  void _paintCoin(Canvas canvas, _Scene s, double now) {
    final look = s.look;
    final still = s.still;
    final c = _coin(now);
    // Parked while a step runs (above a station, or held near the end of
    // its connector), it hovers ±1.5 px; the hover eases in and out so
    // it never jumps.
    final dt = math.max(0.0, now - s.hoverPaintedAt);
    s.hoverPaintedAt = now;
    var parked = false;
    if (c != null && _idle(s) && !s.carry) {
      final before = _coin(now - 80);
      parked = before != null && (before.at - c.at).distance < 0.4;
    }
    s.hover += ((parked ? 1.0 : 0.0) - s.hover) * (1 - math.exp(-dt / 300));
    if (still) s.hover = 0;
    // One coin: where the render draws it, the painted one gives way.
    final a = (c?.alpha ?? 0) * (1 - s.salCoinFade);
    if (c == null || a <= 0) return;
    final hover =
        s.hover * 1.5 * math.sin(2 * math.pi * (now % _kHover) / _kHover);
    final r = look.coinR * c.scale;
    final at = c.at.translate(0, hover);
    final fill = _placeColor(c.place);
    canvas.drawCircle(
        at.translate(0, 1),
        r,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.16 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    // It wears the mark of the balance the money is in, as its station
    // does: the Bitcoin, Dollars, Hyperliquid or Polymarket mark, scaled
    // down into its circle.
    final asset = _markAssetOf(c.place);
    final mark = asset == null ? null : _marks[asset];
    final box = Rect.fromCircle(center: at, radius: r);
    if (mark != null && mark.size.width > 0 && mark.size.height > 0) {
      if (a < 1) {
        canvas.saveLayer(
            box.inflate(1), Paint()..color = Colors.white.withValues(alpha: a));
      } else {
        canvas.save();
      }
      final k = math.max(
          box.width / mark.size.width, box.height / mark.size.height);
      canvas
        ..clipPath(Path()..addOval(box))
        ..translate(at.dx - mark.size.width * k / 2,
            at.dy - mark.size.height * k / 2)
        ..scale(k, k)
        ..drawPicture(mark.picture)
        ..restore();
      return;
    }
    canvas.drawCircle(at, r, Paint()..color = fill.withValues(alpha: a));
    // A mark still loading: its colour alone, never a "\$".
    if (asset != null) return;
    canvas.drawCircle(
        at,
        r - 1.3 * c.scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.white.withValues(alpha: 0.35 * a));
    const glyph = Icons.arrow_outward_rounded;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(glyph.codePoint),
        style: TextStyle(
          inherit: false,
          fontFamily: glyph.fontFamily,
          package: glyph.fontPackage,
          fontSize: r * 1.4,
          fontWeight: FontWeight.w800,
          height: 1,
          color: Colors.white.withValues(alpha: a),
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

/// Paints its child at [opacity], repainting on the clock when it
/// changed since the last paint; never rebuilds or relayouts.
class _Fade extends SingleChildRenderObjectWidget {
  const _Fade({required this.clock, required this.opacity, super.child});
  final Listenable clock;
  final double Function() opacity;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFade(clock, opacity);

  @override
  void updateRenderObject(BuildContext context, _RenderFade renderObject) {
    renderObject
      ..clock = clock
      ..opacity = opacity
      ..markNeedsPaint();
  }
}

class _RenderFade extends RenderProxyBox {
  _RenderFade(this._clock, this.opacity);
  Listenable _clock;
  double Function() opacity;
  double _painted = -1;

  set clock(Listenable v) {
    if (identical(v, _clock)) return;
    if (attached) _clock.removeListener(_tick);
    _clock = v;
    if (attached) _clock.addListener(_tick);
  }

  void _tick() {
    if (opacity() != _painted) markNeedsPaint();
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
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    _painted = _unit(opacity());
    if (child == null || _painted <= 0) {
      layer = null;
      return;
    }
    layer = context.pushOpacity(offset, (_painted * 255).round(), super.paint,
        oldLayer: layer as OpacityLayer?);
  }
}
