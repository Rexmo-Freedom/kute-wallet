// lib/services/polymarket/live_game/game_pressure.dart
//
// The "pressure" signal of a live game: one side's win chance drifting up
// steadily for several minutes with NO score change. It is read from the
// odds and nothing else (no ball position, no shots), and the copy that
// shows it says so.
//
// Thresholds, tuned on one-minute odds of live games (2026-10-04: five
// soccer internationals, two NFL games). In-play soccer odds wobble about
// half a point to a point a minute; a steady 3-point climb over 4+ quiet
// minutes happened 0 to 2 times per side per match, a 2-point one too
// often to mean anything on its own.
//
// Pure Dart; unit tested in
// test/services/polymarket/live_game_pressure_test.dart.

/// Shortest and longest stretch (whole minutes) the drift is measured over.
const int kPressureMinMinutes = 4;
const int kPressureMaxMinutes = 8;

/// Minutes after a score or period change before the odds are read again:
/// the market needs that long to settle on the new score.
const int kPressureSettleMinutes = 2;

/// The climb in win chance that turns the label on.
const double kPressureEnter = 0.03;

/// The same with the totals market agreeing (the Over rising too).
const double kPressureEnterConfirmed = 0.02;

/// The label stays until the climb falls under this (hysteresis: half of
/// the entry, so it does not flicker around the threshold).
const double kPressureExit = 0.015;

/// How steady the climb must be: net move over total movement (1 = every
/// minute went the same way). Under this it is chop, not a drift.
const double kPressureMinEfficiency = 0.6;

/// One minute may carry at most this share of the climb. More is a jump:
/// something happened (a card, a goal the score feed has not shown yet),
/// which is not pressure.
const double kPressureMaxStepShare = 0.6;

/// The Over price must rise at least this much over the same stretch to
/// count as agreeing.
const double kPressureOverRise = 0.01;

enum PressureSide { a, b }

class PressureSignal {
  final PressureSide side;

  /// How much that side's win chance rose (0.04 = 4 points).
  final double drift;

  /// Over how many minutes.
  final int minutes;

  /// The totals market moved with it (the Over price rose).
  final bool confirmedByTotals;

  const PressureSignal({
    required this.side,
    required this.drift,
    required this.minutes,
    this.confirmedByTotals = false,
  });

  @override
  String toString() =>
      'Pressure(${side.name} +${(drift * 100).toStringAsFixed(1)} in '
      '${minutes}m${confirmedByTotals ? ' +totals' : ''})';
}

/// Whether one side's win chance has been climbing steadily with no score
/// change. All series are one-minute samples, oldest first, ending now and
/// aligned with each other ([resampleOdds]).
///
/// * [a], [b]: each side's win chance; without [b] it is `1 - a` (a
///   two-way market).
/// * [over]: the main total's Over price, when the event has one.
/// * [quietMinutes]: whole minutes since the last score or period change
///   (null: none seen). The first [kPressureSettleMinutes] of them are
///   skipped.
/// * [leader]: 1 when A is ahead on the scoreboard, -1 when B is, 0 level,
///   null unknown.
/// * [previous]: the signal of the last evaluation, for the hysteresis.
///
/// The side that is AHEAD gains win chance every minute just because time
/// runs out, which is not pressure. So a side counts on its own only when
/// it is not ahead (score unknown: when its chance is at most 50%); the
/// side ahead needs the totals market to agree, since a clock running down
/// makes the Over fall, not rise.
PressureSignal? detectPressure({
  required List<double?> a,
  List<double?>? b,
  List<double?>? over,
  int? quietMinutes,
  int? leader,
  PressureSignal? previous,
  bool inPlay = true,
}) {
  if (!inPlay || a.length <= kPressureMinMinutes) return null;
  var maxL = kPressureMaxMinutes;
  if (quietMinutes != null) {
    final usable = quietMinutes - kPressureSettleMinutes;
    if (usable < maxL) maxL = usable;
  }
  if (maxL < kPressureMinMinutes) return null;

  PressureSignal? best;
  for (final side in PressureSide.values) {
    final series = side == PressureSide.a
        ? a
        : (b ?? [for (final v in a) v == null ? null : 1 - v]);
    if (series.length != a.length) continue;
    final now = series.last;
    if (now == null) continue;
    final ahead = leader == null
        ? now > 0.5
        : (side == PressureSide.a ? leader > 0 : leader < 0);
    final holding = previous != null && previous.side == side;
    final n = series.length - 1;
    for (var l = kPressureMinMinutes; l <= maxL && l <= n; l++) {
      final start = series[n - l];
      if (start == null) break;
      final drift = now - start;
      if (drift <= 0) continue;
      var path = 0.0, maxStep = 0.0, gap = false;
      for (var k = n - l; k < n; k++) {
        final x = series[k], y = series[k + 1];
        if (x == null || y == null) {
          gap = true;
          break;
        }
        final step = y - x;
        path += step.abs();
        if (step > maxStep) maxStep = step;
      }
      if (gap || path <= 0) continue;
      var confirmed = false;
      if (over != null && over.length == a.length) {
        final o0 = over[n - l], o1 = over[n];
        confirmed = o0 != null && o1 != null && o1 - o0 >= kPressureOverRise;
      }
      if (ahead && !confirmed) continue;
      final bool ok;
      if (holding) {
        ok = drift >= kPressureExit;
      } else {
        ok = drift >= (confirmed ? kPressureEnterConfirmed : kPressureEnter) &&
            drift / path >= kPressureMinEfficiency &&
            maxStep <= kPressureMaxStepShare * drift;
      }
      if (ok && (best == null || drift > best.drift)) {
        best = PressureSignal(
          side: side,
          drift: drift,
          minutes: l,
          confirmedByTotals: confirmed,
        );
      }
    }
  }
  return best;
}
