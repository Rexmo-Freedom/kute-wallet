// lib/services/polymarket/live_game/game_momentum.dart
//
// Momentum for a live game, read from the market's own odds and nothing
// else. There is no ball tracking here: every number is how the win chance
// on Polymarket moved.
//
// [buildMomentum] makes one bar per time bucket of the game, signed by
// which side gained win chance in that bucket and sized by how much. The
// window is the game itself, from kickoff ([gameKickoffMs]); buckets are
// one minute for most games; heights are relative to the game's own
// biggest swing ([momentumBarHeight]). [momentumWave] smooths the bars
// into the wave the strip draws.
//
// Pure Dart, cheap (a few hundred samples), and run by the provider, never
// from a build. Unit tested in
// test/services/polymarket/live_game_momentum_test.dart.

import 'dart:math' as math;

import 'package:kute/services/polymarket/live_game/game_score.dart';

/// A price sample: epoch ms and a chance in 0..1.
typedef OddsPoint = ({int tMs, double p});

/// The value of [points] (ascending) at each of `count + 1` instants from
/// [startMs] every [stepMs]: the last sample at or before the instant.
/// Null before the first sample.
List<double?> resampleOdds(
    List<OddsPoint> points, int startMs, int stepMs, int count) {
  final out = List<double?>.filled(count + 1, null);
  var i = 0;
  double? last;
  for (var k = 0; k <= count; k++) {
    final t = startMs + k * stepMs;
    while (i < points.length && points[i].tMs <= t) {
      last = points[i].p;
      i++;
    }
    out[k] = last;
  }
  return out;
}

/// The strip holds at most about this many buckets across the game: one
/// minute each for a game of up to two hours.
const int kMomentumTargetBars = 120;

/// Bars never outnumber this (the longest window at its bucket).
const int kMomentumMaxBars = 120;

/// A bucket that moved less than this (half a point of chance) is flat.
const double kMomentumDeadband = 0.005;

/// The strip's full height is at least this much swing (1.5 points), so a
/// quiet game's noise does not fill the height.
const double kMomentumScaleFloor = 0.015;

/// The strip is shown once this many buckets of the game have a price.
const int kMomentumMinBars = 8;

const List<int> _kBucketMinutes = [1, 2, 3, 4, 5];

/// The bucket for a window: the smallest of 1 to 5 minutes that keeps the
/// window within [kMomentumTargetBars] buckets (one minute up to two
/// hours, two up to four); 5 minutes for anything longer (a bucket is
/// never coarser than that).
int momentumBucketMs(int windowMs) {
  for (final m in _kBucketMinutes) {
    final ms = m * 60000;
    if (windowMs <= ms * kMomentumTargetBars) return ms;
  }
  return _kBucketMinutes.last * 60000;
}

/// How long a game of [sport] usually takes in real time, kickoff to the
/// end with its breaks, for sports with a clock: the strip's axis while
/// the game is in play, so it fills from left to right. Null for sports
/// without one (baseball, tennis, esports, cricket), which use the time
/// played: no length can be promised for them, and a wrong one leaves the
/// graph in a corner of its axis.
int? momentumAxisMs(GameSport sport) => switch (sport) {
      GameSport.soccer => 115 * 60000,
      GameSport.americanFootball => 195 * 60000,
      GameSport.basketball => 150 * 60000,
      GameSport.hockey => 155 * 60000,
      _ => null,
    };

final RegExp _kPeriodStart = RegExp(r'^(Q|P)\s*([1-9])$', caseSensitive: false);
final RegExp _kPeriodEnd = RegExp(
    r'^end(?:\s+of)?\s+(?:(Q|P)\s*)?([1-9])(?:st|nd|rd|th)?(?:\s+(quarter|period))?$',
    caseSensitive: false);
const Set<String> _kHalfTime = {'ht', 'half', 'halftime', 'half time'};

/// The name a period change takes under the strip's axis, for [period] as
/// the feed wrote it: the period that STARTS at that tick, never "End …".
/// Null for a change that gets no name.
///
///   * Quarters (American football, basketball): "Q2", "Q3", "Q4", "HT"
///     at the half, "OT". The feed's "End Q1" is where Q2 starts, so it
///     reads "Q2"; "End Q2" is the half ("HT"); "End Q4" names nothing.
///     (The first quarter is the axis's own start.)
///   * Hockey: "P2", "P3", "OT" the same way.
///   * Football: "HT" at the break; the halves are the axis's 0' and 90'.
///   * Anything else: the feed's own word.
String? momentumPeriodLabel(GameSport sport, String period) {
  final raw = period.trim();
  if (raw.isEmpty) return null;
  final lower = raw.toLowerCase();
  switch (sport) {
    case GameSport.soccer:
      if (lower == 'ht') return 'HT';
      if (lower == '1h' || lower == '2h') return null;
      return raw;
    case GameSport.americanFootball:
    case GameSport.basketball:
    case GameSport.hockey:
      final letter = sport == GameSport.hockey ? 'P' : 'Q';
      final last = sport == GameSport.hockey ? 3 : 4;
      if (_kHalfTime.contains(lower)) {
        return sport == GameSport.hockey ? null : 'HT';
      }
      if (lower.startsWith('ot')) return 'OT';
      final start = _kPeriodStart.firstMatch(raw);
      if (start != null) {
        final n = int.parse(start.group(2)!);
        // The first period starts the axis.
        return n <= 1 || n > last ? null : '$letter$n';
      }
      final end = _kPeriodEnd.firstMatch(raw);
      if (end != null) {
        final n = int.parse(end.group(2)!);
        if (n >= last) return null;
        if (sport != GameSport.hockey && n == 2) return 'HT';
        return '$letter${n + 1}';
      }
      return raw;
    default:
      return raw;
  }
}

/// [labels] with each name kept once, on its last tick: the feed marks
/// both the end of a quarter and the start of the next, and the next
/// one's name belongs where it starts.
List<String?> momentumLabelsOnce(List<String?> labels) {
  final seen = <String>{};
  final out = List<String?>.filled(labels.length, null);
  for (var i = labels.length - 1; i >= 0; i--) {
    final l = labels[i];
    if (l != null && l.isNotEmpty && seen.add(l)) out[i] = l;
  }
  return out;
}

/// What the strip's axis reads at its start for [sport]: a football
/// match's minute, the first quarter or period of a game counted in them.
String? momentumAxisStartLabel(GameSport sport) => switch (sport) {
      GameSport.soccer => "0'",
      GameSport.americanFootball || GameSport.basketball => 'Q1',
      GameSport.hockey => 'P1',
      _ => null,
    };

/// Which names fit under the strip's axis, given where each would sit
/// ([spans], left to right, in pixels): a name is kept only when it stays
/// [gap] clear of every name already kept. The two ends of the axis are
/// placed first, then the [latest] period (where the game is now), then
/// the rest from the left. Returns the kept indexes in order.
List<int> momentumAxisLabelsKept(
  List<({double left, double right})> spans, {
  double gap = 8,
  int? latest,
}) {
  if (spans.isEmpty) return const [];
  final kept = <int>[];
  bool clear(int i) => kept.every((k) =>
      spans[i].left >= spans[k].right + gap ||
      spans[i].right + gap <= spans[k].left);
  void offer(int i) {
    if (i < 0 || i >= spans.length || kept.contains(i)) return;
    if (clear(i)) kept.add(i);
  }

  offer(0);
  offer(spans.length - 1);
  if (latest != null) offer(latest);
  for (var i = 1; i < spans.length - 1; i++) {
    offer(i);
  }
  return kept..sort();
}

/// The height of a bar, 0..1 of the half strip: the swing against the
/// game's biggest ([scale]) on a square-root curve, so a middling swing
/// still shows beside a goal-sized one. The biggest is full height.
double momentumBarHeight(double swing, double scale) {
  if (scale <= 0 || !swing.isFinite) return 0;
  return math.sqrt(math.min(1.0, swing.abs() / scale));
}

/// The strip as a wave: one value per bar in -1..1, positive where side A
/// was gaining and negative where side B was. Each bar's eased height
/// ([momentumBarHeight]) is averaged with its neighbours (1-2-1), so the
/// strip reads as waves rather than single-minute noise, and the result is
/// stretched so the game's biggest wave is full height. A flat or empty
/// bar counts as zero. All zeros when nothing moved.
List<double> momentumWave(MomentumStrip strip) {
  final bars = strip.bars;
  final raw = [
    for (final b in bars)
      b.flat ? 0.0 : b.swing.sign * momentumBarHeight(b.swing, strip.scale)
  ];
  final out = List<double>.filled(raw.length, 0);
  var peak = 0.0;
  for (var i = 0; i < raw.length; i++) {
    var sum = 2 * raw[i], weight = 2.0;
    if (i > 0) {
      sum += raw[i - 1];
      weight += 1;
    }
    if (i + 1 < raw.length) {
      sum += raw[i + 1];
      weight += 1;
    }
    out[i] = sum / weight;
    if (out[i].abs() > peak) peak = out[i].abs();
  }
  if (peak <= 0) return out;
  for (var i = 0; i < out.length; i++) {
    out[i] = out[i] / peak;
  }
  return out;
}

/// A game's kickoff (epoch ms), or null when nothing trustworthy says:
/// the live feed's own start time, then Gamma's game start, then the first
/// time anyone saw the game in play, each only when it is not after
/// [untilMs] (now, or the end of a finished game). Gamma's event start
/// date is when the market opened, so [marketStartMs] counts only when it
/// is within [maxWindowMs] of [untilMs].
int? gameKickoffMs({
  int? feedStartMs,
  int? gammaStartMs,
  int? firstSeenMs,
  int? marketStartMs,
  required int untilMs,
  int maxWindowMs = 6 * 3600000,
}) {
  for (final t in [feedStartMs, gammaStartMs, firstSeenMs]) {
    if (t != null && t > 0 && t < untilMs) return t;
  }
  final m = marketStartMs;
  if (m != null && m > 0 && m < untilMs && untilMs - m <= maxWindowMs) {
    return m;
  }
  return null;
}

class MomentumBar {
  final int startMs;
  final int endMs;

  /// Change of side A's edge over the bucket, in chance (0.03 = 3 points):
  /// positive when A gained, negative when B gained. With both sides'
  /// prices it is half of (A's change minus B's change), so a draw price
  /// moving alone does not count for either side.
  final double swing;

  /// No price at all in or before this bucket.
  final bool empty;

  const MomentumBar({
    required this.startMs,
    required this.endMs,
    required this.swing,
    this.empty = false,
  });

  bool get flat => empty || swing.abs() < kMomentumDeadband;
}

class MomentumStrip {
  final List<MomentumBar> bars;
  final int startMs;
  final int endMs;

  /// Where the strip's time axis ends: [endMs], or later while a game
  /// with a clock is in play (the part not yet played stays empty).
  final int axisEndMs;
  final int bucketMs;

  /// The swing a full-height bar stands for.
  final double scale;

  const MomentumStrip({
    required this.bars,
    required this.startMs,
    required this.endMs,
    int? axisEndMs,
    required this.bucketMs,
    required this.scale,
  }) : axisEndMs = axisEndMs ?? endMs;

  static const empty =
      MomentumStrip(bars: [], startMs: 0, endMs: 0, bucketMs: 60000, scale: 1);

  bool get isEmpty => bars.every((b) => b.empty);

  /// Enough of the game has a price to draw: [kMomentumMinBars] buckets,
  /// and at least one of them moved.
  bool get readable =>
      bars.where((b) => !b.empty).length >= kMomentumMinBars &&
      bars.any((b) => !b.flat);
}

/// Momentum bars for the game window [startMs]..[endMs] from side A's win
/// chance [a] and, when the market has one, side B's [b] (ascending). The
/// last bar may be a part bucket that ends now. [axisMs] is the usual
/// length of the game while it is in play ([momentumAxisMs]): the bucket is
/// then sized for the whole game, and the axis runs to its expected end.
MomentumStrip buildMomentum({
  required List<OddsPoint> a,
  List<OddsPoint>? b,
  required int startMs,
  required int endMs,
  int? axisMs,
}) {
  if (endMs <= startMs || a.isEmpty) return MomentumStrip.empty;
  final window = math.max(endMs - startMs, axisMs ?? 0);
  final bucket = momentumBucketMs(window);
  final count = ((endMs - startMs) / bucket).ceil();
  final bars = <MomentumBar>[];
  var maxAbs = 0.0;
  var ia = 0, ib = 0;
  double? lastA, lastB;
  double? edge() {
    if (lastA == null) return null;
    if (b == null) return lastA;
    if (lastB == null) return null;
    return (lastA! - lastB!) / 2;
  }

  void advance(int t) {
    while (ia < a.length && a[ia].tMs <= t) {
      lastA = a[ia].p;
      ia++;
    }
    if (b != null) {
      while (ib < b.length && b[ib].tMs <= t) {
        lastB = b[ib].p;
        ib++;
      }
    }
  }

  advance(startMs);
  var open = edge();
  for (var k = 0; k < count; k++) {
    final from = startMs + k * bucket;
    final to = from + bucket > endMs ? endMs : from + bucket;
    if (open == null) {
      // The series starts inside this bucket: measure from its first
      // price there.
      final firstA = ia < a.length && a[ia].tMs <= to ? a[ia] : null;
      if (firstA != null) {
        advance(firstA.tMs);
        open = edge();
      }
    }
    advance(to);
    final close = edge();
    if (open == null || close == null) {
      bars.add(MomentumBar(startMs: from, endMs: to, swing: 0, empty: true));
    } else {
      final swing = close - open;
      if (swing.abs() > maxAbs) maxAbs = swing.abs();
      bars.add(MomentumBar(startMs: from, endMs: to, swing: swing));
    }
    open = close ?? open;
  }
  return MomentumStrip(
    bars: bars,
    startMs: startMs,
    endMs: endMs,
    axisEndMs: startMs + window,
    bucketMs: bucket,
    scale: maxAbs > kMomentumScaleFloor ? maxAbs : kMomentumScaleFloor,
  );
}
