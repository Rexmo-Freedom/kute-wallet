// lib/services/balance_milestones.dart
//
// THE BALANCE MILESTONES (founder, 6 November 2026: "Gamify the graph for
// the Bitcoin balance ... to reach certain thresholds"). The Bitcoin home's
// Balance tab climbs a ladder of round figures in the display currency;
// this file is the arithmetic and the once-only record, nothing on screen
// (balance_goals.dart draws it).
//
//   * THE TOTAL is the person's money in Kute that is not in a position:
//     the spending wallet's bitcoin at today's price plus the Dollars
//     cash (the spending account, the cash the venues keep, money moving
//     between them, what the sweeper owes back). Moving bitcoin to
//     Dollars never lowers it. Open Investing and Predictions positions
//     are left out on purpose: nothing on Investing or Predictions is
//     scored or celebrated (allowed-and-banned-claims, kute-points);
//   * THE LADDER is the 1, 2.5, 5 series of each power of ten from a
//     first rung worth about a hundred US dollars in the display currency
//     ($100, $250, $500, $1,000, ...; 50,000 Ft, 100,000 Ft, ...). The
//     first rung is a fixed figure per currency ([kMilestoneFirstRung]),
//     so a moving exchange rate never renumbers the levels; a currency
//     outside the table takes the nice figure nearest a hundred dollars;
//   * THE LEVEL is the rungs passed plus one ("Level 3" has passed two);
//     the goal is the next rung, progress the total over it (0 to the
//     goal, never between rungs);
//   * ONCE: the first time the ladder is read in a currency, every rung
//     already passed is history, recorded without a celebration; after
//     that, a rung passed for the first time is celebrated once (the
//     highest when several go at once). A balance that falls back and
//     climbs again never celebrates the same rung twice. The record lives
//     in [OnceFlagsService]'s box, so a wallet wipe starts it afresh.
//
// Nothing here awards anything: no points, no perks, no money. The ladder
// is a picture of the balance, and the plan's rule that points are never
// earned for balance size stands.

import 'dart:math' as math;

import 'package:kute/services/once_flags_service.dart';

/// The nice numbers the ladder climbs: 1, 2.5 and 5 of each power of ten.
const List<double> _kNiceSteps = [1, 2.5, 5];

/// The [j]-th nice number from one: 1, 2.5, 5, 10, 25, 50, 100, ...
double niceNumberAt(int j) {
  final i = j < 0 ? 0 : j;
  return _kNiceSteps[i % 3] * math.pow(10, i ~/ 3).toDouble();
}

/// The index of the nice number nearest [x] on a log scale; 0 for
/// anything at or under one.
int nearestNiceIndex(double x) {
  if (!x.isFinite || x <= 1) return 0;
  final decade = (math.log(x) / math.ln10).floor();
  var best = 0;
  var bestDistance = double.infinity;
  for (var j = math.max(0, decade * 3 - 3); j <= decade * 3 + 5; j++) {
    final distance = math.log(niceNumberAt(j) / x).abs();
    if (distance < bestDistance) {
      best = j;
      bestDistance = distance;
    }
  }
  return best;
}

/// The largest nice number at or under [x]; 0 under one.
double floorNiceNumber(double x) {
  if (!x.isFinite || x < 1) return 0;
  var j = 0;
  while (niceNumberAt(j + 1) <= x + 1e-9) {
    j++;
  }
  return niceNumberAt(j);
}

/// The ladder's first rung per display currency: a round figure worth
/// about a hundred US dollars, fixed so the levels never move with the
/// rate.
const Map<String, double> kMilestoneFirstRung = {
  'USD': 100,
  'EUR': 100,
  'GBP': 100,
  'CHF': 100,
  'BRL': 500,
  'SEK': 1000,
  'NOK': 1000,
  'DKK': 500,
  'PLN': 500,
  'CZK': 2500,
  'HUF': 50000,
  'RON': 500,
};

/// How many level names there are; every level past the last wears it.
const int kBalanceLevelNames = 12;

/// Where [total] stands on a ladder.
class BalanceMilestoneProgress {
  const BalanceMilestoneProgress({
    required this.reached,
    required this.total,
    required this.next,
    required this.last,
  });

  /// Rungs passed.
  final int reached;

  /// The total read.
  final double total;

  /// The goal: the next rung.
  final double next;

  /// The rung last passed; null below the first.
  final double? last;

  /// "Level 3" has passed two rungs.
  int get level => reached + 1;

  /// Which level name this level wears (0 to [kBalanceLevelNames] - 1).
  int get nameIndex => math.min(reached, kBalanceLevelNames - 1);

  /// The total over the goal, 0 to 1.
  double get fraction {
    if (!(next > 0) || !total.isFinite) return 0;
    return (total / next).clamp(0.0, 1.0);
  }

  /// Whole percent, rounded down and never 100: the goal is not reached
  /// until it is passed, and then the next one is the goal.
  int get percent => (fraction * 100).floor().clamp(0, 99);

  /// What is left to the goal (never negative).
  double get gap => math.max(0, next - total);
}

class BalanceMilestoneLadder {
  BalanceMilestoneLadder._(this.currency, this._first);

  /// The ladder in [currency]; [usdToDisplay] (display units per US
  /// dollar) only for a currency outside [kMilestoneFirstRung].
  factory BalanceMilestoneLadder.forCurrency(String currency,
      {double? usdToDisplay}) {
    final code = currency.toUpperCase();
    final fixed = kMilestoneFirstRung[code];
    final rate =
        usdToDisplay != null && usdToDisplay.isFinite && usdToDisplay > 0
            ? usdToDisplay
            : 1.0;
    return BalanceMilestoneLadder._(
        code, nearestNiceIndex(fixed ?? 100 * rate));
  }

  /// The display currency's code.
  final String currency;

  /// The first rung's place in the nice numbers.
  final int _first;

  /// The [i]-th rung from the first (0).
  double rung(int i) => niceNumberAt(_first + i);

  /// How many rungs [total] has passed (a hair of float slack, so $250
  /// read as 249.9999999 is $250).
  int reached(double total) {
    if (!total.isFinite) return 0;
    var n = 0;
    while (n < 64 && total + 1e-6 >= rung(n)) {
      n++;
    }
    return n;
  }

  BalanceMilestoneProgress progress(double total) {
    final n = reached(total);
    return BalanceMilestoneProgress(
      reached: n,
      total: total.isFinite && total > 0 ? total : 0,
      next: rung(n),
      last: n > 0 ? rung(n - 1) : null,
    );
  }
}

/// What the Move to Dollars door opens with, in US dollars: a round tenth
/// of [goal] (the 1, 2.5, 5 figure at or under it), never more than the
/// bitcoin is worth ([bitcoinUsd], whole dollars); null when that is under
/// a dollar (nothing worth moving) or the rate is unknown.
double? balanceGoalSuggestedUsd({
  required double goal,
  required double usdToDisplay,
  required double bitcoinUsd,
}) {
  if (!(usdToDisplay > 0) || !usdToDisplay.isFinite) return null;
  if (!bitcoinUsd.isFinite || bitcoinUsd < 1) return null;
  final tenth = floorNiceNumber(goal / 10 / usdToDisplay);
  final suggestion = math.min(math.max(tenth, 1.0), bitcoinUsd.floorToDouble());
  return suggestion >= 1 ? suggestion : null;
}

/// Whether a goal line at [goal] is close enough above the line on screen
/// ([values], in the chart's own unit) to be drawn on the line's scale:
/// within the span the line already covers (a flat line: a quarter of its
/// height), so the line keeps at least half the plot. A goal the line has
/// already touched on screen is always in reach.
bool balanceGoalInReach(List<double> values, double goal) {
  if (values.isEmpty || !goal.isFinite) return false;
  var lo = values.first, hi = values.first;
  for (final v in values) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  if (goal <= hi) return true;
  final room = math.max(hi - lo, hi.abs() * 0.25);
  return room > 0 && goal - hi <= room;
}

/// The once-only flags the record keeps (OnceFlagsService in the app, a
/// map in tests).
abstract class BalanceMilestoneFlags {
  bool isClaimed(String key);

  /// True the first time only.
  bool claim(String key);
}

/// The app's flags: [OnceFlagsService]'s box, cleared by a wallet wipe.
class OnceBalanceMilestoneFlags implements BalanceMilestoneFlags {
  const OnceBalanceMilestoneFlags();

  @override
  bool isClaimed(String key) => OnceFlagsService.isClaimed(key);

  @override
  bool claim(String key) => OnceFlagsService.claimOnce(key);
}

/// The once-only record of the rungs celebrated, per display currency.
class BalanceMilestoneRecord {
  const BalanceMilestoneRecord(this.flags);

  final BalanceMilestoneFlags flags;

  static String baselineKey(String currency) =>
      'balance_milestones_seen_${currency.toUpperCase()}';

  static String rungKey(String currency, double rung) =>
      'balance_milestone_${currency.toUpperCase()}_${rung.round()}';

  /// Whether [reached] holds a rung not recorded yet (so a caller can
  /// wait for the figure to settle before [claim]).
  bool hasNews(BalanceMilestoneLadder ladder, int reached) {
    if (!flags.isClaimed(baselineKey(ladder.currency))) return true;
    for (var i = reached - 1; i >= 0; i--) {
      if (!flags.isClaimed(rungKey(ladder.currency, ladder.rung(i)))) {
        return true;
      }
    }
    return false;
  }

  /// Records every rung under [reached] and returns the one to celebrate
  /// now (the highest recorded for the first time), or null: nothing new,
  /// or this is the first reading in this currency (history, no party).
  double? claim(BalanceMilestoneLadder ladder, int reached) {
    final currency = ladder.currency;
    final firstReading = !flags.isClaimed(baselineKey(currency));
    double? celebrate;
    for (var i = 0; i < reached; i++) {
      final rung = ladder.rung(i);
      if (flags.claim(rungKey(currency, rung)) && !firstReading) {
        celebrate = rung;
      }
    }
    if (firstReading) {
      flags.claim(baselineKey(currency));
      return null;
    }
    return celebrate;
  }
}
