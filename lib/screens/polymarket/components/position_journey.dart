// lib/screens/polymarket/components/position_journey.dart
//
// Two quiet pieces of the open-position screen, around the speedometer
// (position_speedometer.dart):
//
//   * the result, under the dial: "▲ $9.40 · +247%", the figure in the
//     app's up / down colour after a painted caret, as the Portfolio rows
//     write theirs (flat reads "$0.00 · 0.0%" quietly, no caret), and a
//     quiet "since you bought at 19¢" under it;
//   * the chart, at the bottom, brokerage style: the held side's chance
//     since the first buy of this holding (the market sheet's own price
//     history of the held token, so a No reads as 1 − Yes), one 2 px line
//     in the colour of the result (up, down, or neutral when flat), a faint
//     dashed line at the average price labelled "Your avg 19¢", the live
//     end dot; no fill, no axes; the start date and "Now" under it. Hidden
//     without history.
//
// Nothing here is logged.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketMarketHistoryProvider;
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketActivityProvider;
import 'package:kute/screens/polymarket/components/market_chart.dart'
    show formatPolyBoughtCents;
import 'package:kute/theme/app_theme.dart';

// ─── Result line ─────────────────────────────────────────────────────

/// "+81%", "+4.5%", "0.0%", "-12%": whole percents from 10% up, one
/// decimal under it.
String polyResultPercent(double percent) {
  final a = percent.abs();
  final digits = a >= 9.95 ? a.toStringAsFixed(0) : a.toStringAsFixed(1);
  if (digits == '0.0' || digits == '0') return '0.0%';
  return '${percent < 0 ? '-' : '+'}$digits%';
}

/// Whether a profit or loss of [pnl] dollars reads as flat.
bool polyResultIsFlat(double pnl) => pnl.abs() < 0.005;

/// "▲ $9.40 · +247%" under the dial, "since you bought at 19¢" under
/// it.
class PolyPositionResultLine extends StatelessWidget {
  const PolyPositionResultLine({
    super.key,
    required this.pnl,
    required this.pnlPercent,
    required this.amountText,
    this.boughtText,
  });

  /// The profit or loss in dollars (value now less what was paid).
  final double pnl;
  final double pnlPercent;

  /// [pnl]'s size, formatted ("$9.40"), no sign.
  final String amountText;

  /// The average price paid ("19¢"); no second line without it.
  final String? boughtText;

  static const lineKey = ValueKey('poly-position-result');
  static const figureKey = ValueKey('poly-position-result-figure');
  static const caretKey = ValueKey('poly-position-result-caret');
  static const sinceKey = ValueKey('poly-position-result-since');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final flat = polyResultIsFlat(pnl);
    final up = pnl > 0;
    final color = flat
        ? c.textSecondary
        : (up ? AppColors.marketUp : AppColors.marketDown);
    final change =
        '$amountText · ${flat ? '0.0%' : polyResultPercent(pnlPercent)}';
    final figure = TextStyle(
      color: color,
      fontSize: 15.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
      height: 1.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final quiet = TextStyle(
      color: c.textTertiary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.3,
    );
    final bought = boughtText;
    return Column(
      key: lineKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!flat) ...[
                CustomPaint(
                  key: caretKey,
                  size: Size(8.w, 6.h),
                  painter: PolyCaretPainter(up: up, color: color),
                ),
                SizedBox(width: 5.w),
              ],
              Text(change, key: figureKey, style: figure, maxLines: 1),
            ],
          ),
        ),
        if (bought != null)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              context.l10n.polyPosSinceBoughtAt(bought),
              key: sinceKey,
              style: quiet,
              maxLines: 1,
            ),
          ),
      ],
    );
  }
}

/// The small solid triangle before a P&L figure, as the Portfolio rows
/// paint it: up or down.
class PolyCaretPainter extends CustomPainter {
  const PolyCaretPainter({required this.up, required this.color});

  final bool up;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = up
        ? (Path()
          ..moveTo(0, size.height)
          ..lineTo(size.width / 2, 0)
          ..lineTo(size.width, size.height))
        : (Path()
          ..moveTo(0, 0)
          ..lineTo(size.width / 2, size.height)
          ..lineTo(size.width, 0));
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(PolyCaretPainter old) =>
      old.up != up || old.color != color;
}

// ─── Journey data ────────────────────────────────────────────────────

/// The held side's chance since the holding's first buy: [since], then
/// the history after it, oldest first.
typedef PolyPositionJourney = ({
  DateTime since,
  List<PolymarketPricePoint> points,
});

/// When the shares of [tokenId] held now were first bought: the first
/// buy after the last time the holding went to zero. Null without a buy.
DateTime? polyFirstBuyOfHolding(List<Activity> activities, String tokenId) {
  if (tokenId.isEmpty) return null;
  final trades = activities.where((a) => a.asset == tokenId && a.size > 0)
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  var shares = 0.0;
  DateTime? first;
  for (final t in trades) {
    final side = (t.side ?? '').toUpperCase();
    if (side == 'BUY') {
      if (shares <= 1e-6) first = t.timestampDate;
      shares += t.size;
    } else if (side == 'SELL') {
      shares = math.max(0, shares - t.size);
      if (shares <= 1e-6) first = null;
    }
  }
  return first;
}

/// The shortest range of the market sheet's history that reaches back
/// [age].
String polyJourneyInterval(Duration age) {
  if (age <= const Duration(minutes: 55)) return '1h';
  if (age <= const Duration(hours: 5, minutes: 50)) return '6h';
  if (age <= const Duration(hours: 23, minutes: 30)) return '1d';
  if (age <= const Duration(days: 6, hours: 20)) return '1w';
  if (age <= const Duration(days: 29)) return '1m';
  return 'max';
}

/// The journey of the holding of [tokenId]: its first buy from the trade
/// history ([fallbackSince], the position's own date, without one) and
/// the held token's history since, from the market sheet's cache. Null
/// when the start is unknown or there is no history after it.
final polyPositionJourneyProvider = FutureProvider.autoDispose
    .family<PolyPositionJourney?, ({String tokenId, DateTime? fallbackSince})>(
        (ref, key) async {
  if (key.tokenId.isEmpty) return null;
  DateTime? since;
  try {
    final activities = await ref.watch(polymarketActivityProvider.future);
    since = polyFirstBuyOfHolding(activities, key.tokenId);
  } catch (_) {}
  since ??= key.fallbackSince;
  if (since == null) return null;
  final now = DateTime.now();
  if (!since.isBefore(now)) return null;
  final interval = polyJourneyInterval(now.difference(since));
  final history = await ref.watch(polymarketMarketHistoryProvider(
      (tokenId: key.tokenId, interval: interval)).future);
  final start = since;
  final after = history.where((p) => p.timestamp.isAfter(start)).toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (after.isEmpty) return null;
  return (since: start, points: after);
});

// ─── Journey line ────────────────────────────────────────────────────

/// The chart at the bottom: the held side's chance since the first buy.
class PolyPositionJourneyLine extends StatelessWidget {
  const PolyPositionJourneyLine({
    super.key,
    required this.journey,
    required this.live,
    required this.color,
    this.entry,
    this.now,
  });

  final PolyPositionJourney journey;

  /// The held side's live chance: the end of the line.
  final double live;

  /// The line's colour: the result's (up, down, or neutral when flat).
  final Color color;

  /// The price paid per share: the dashed line.
  final double? entry;

  /// The right end; the clock when null.
  final DateTime? now;

  static const chartKey = ValueKey('poly-position-journey');
  static const paintKey = ValueKey('poly-position-journey-paint');
  static const avgKey = ValueKey('poly-position-journey-avg');

  /// The chart's points: the buy at the price paid (or the first point's
  /// price), the history after it, and the live chance now.
  static List<({double t, double p})> series(
      PolyPositionJourney journey, double live, double? entry, DateTime now) {
    final t0 = journey.since.millisecondsSinceEpoch.toDouble();
    final t1 = math.max(now.millisecondsSinceEpoch.toDouble(), t0 + 1);
    double x(DateTime t) =>
        ((t.millisecondsSinceEpoch - t0) / (t1 - t0)).clamp(0.0, 1.0);
    final first = entry ?? journey.points.first.price;
    return [
      (t: 0.0, p: first.clamp(0.0, 1.0).toDouble()),
      for (final pt in journey.points)
        if (pt.timestamp.isBefore(now))
          (t: x(pt.timestamp), p: pt.price.clamp(0.0, 1.0).toDouble()),
      (t: 1.0, p: live.clamp(0.0, 1.0).toDouble()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final at = now ?? DateTime.now();
    final pts = series(journey, live, entry, at);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final since = journey.since.toLocal();
    final sameDay = at.difference(journey.since) < const Duration(hours: 20);
    String startLabel;
    try {
      startLabel = sameDay
          ? DateFormat.Hm(locale).format(since)
          : DateFormat.MMMd(locale).format(since);
    } catch (_) {
      startLabel = sameDay
          ? DateFormat.Hm().format(since)
          : DateFormat.MMMd().format(since);
    }
    final e = entry;
    final avgLabel = e == null ? null : l10n.polyPosYourAvg(formatPolyBoughtCents(e));
    final axisStyle = TextStyle(
      color: c.textTertiary,
      fontSize: 11.sp,
      fontWeight: FontWeight.w500,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final avgStyle = TextStyle(
      color: c.textSecondary,
      fontSize: 11.sp,
      fontWeight: FontWeight.w600,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final chartH = 110.h;
    final range = polyJourneyRange(pts.map((p) => p.p), entry);
    // "Your avg 19¢" at the dashed line's left: under it where there is
    // room, else over it; on the screen's background, clear of the line
    // (which starts at that price).
    final avgY = e == null
        ? 0.0
        : (1 - (e - range.lo) / (range.hi - range.lo)) * chartH;
    final avgBelow = avgY + 20 <= chartH;

    return Semantics(
      container: true,
      label: [
        if (avgLabel != null) avgLabel,
        '$startLabel – ${l10n.polyPosNow}',
      ].join(', '),
      child: ExcludeSemantics(
        child: Column(
          key: chartKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: chartH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      key: paintKey,
                      painter: PolyJourneyPainter(
                        points: pts,
                        entry: entry,
                        lo: range.lo,
                        hi: range.hi,
                        color: color,
                        guide: c.textTertiary,
                        ring: c.background,
                      ),
                    ),
                  ),
                  if (avgLabel != null)
                    Positioned(
                      key: avgKey,
                      left: 0,
                      top: avgBelow ? avgY + 3 : avgY - 19,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.background,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 2, vertical: 1),
                          child: Text(avgLabel, style: avgStyle, maxLines: 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: 6.h),
            Row(
              children: [
                Text(startLabel, style: axisStyle),
                const Spacer(),
                Text(l10n.polyPosNow, style: axisStyle),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The chart's vertical range: every point and the price paid, with a
/// little air, at least ten points of chance tall, inside 0..1.
({double lo, double hi}) polyJourneyRange(Iterable<double> ps, double? entry) {
  var lo = 1.0;
  var hi = 0.0;
  for (final p in [...ps, if (entry != null) entry]) {
    lo = math.min(lo, p);
    hi = math.max(hi, p);
  }
  if (hi < lo) return (lo: 0, hi: 1);
  final span = math.max(0.10, hi - lo);
  final mid = (lo + hi) / 2;
  var l = mid - span * 0.62;
  var h = mid + span * 0.62;
  if (l < 0) {
    h -= l;
    l = 0;
  }
  if (h > 1) {
    l -= h - 1;
    h = 1;
  }
  return (lo: math.max(0, l), hi: math.min(1, h));
}

/// The chart's line colour: the result's, up or down, neutral when flat.
Color polyJourneyColor(double pnl, Color neutral) => polyResultIsFlat(pnl)
    ? neutral
    : (pnl > 0 ? AppColors.marketUp : AppColors.marketDown);

/// Paints the chart: the faint dashed line at the price paid, the 2 px
/// line in one colour, the live end dot. No fill, no axes.
class PolyJourneyPainter extends CustomPainter {
  PolyJourneyPainter({
    required this.points,
    required this.entry,
    required this.lo,
    required this.hi,
    required this.color,
    required this.guide,
    required this.ring,
  });

  final List<({double t, double p})> points;
  final double? entry;
  final double lo;
  final double hi;

  /// The line's and the end dot's colour.
  final Color color;

  /// The dashed line's colour.
  final Color guide;

  /// Around the end dot: the screen's background.
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    const padX = 5.0;
    final w = size.width - padX * 2;
    double y(double p) => (1 - (p - lo) / (hi - lo)) * size.height;
    Offset at(({double t, double p}) q) => Offset(padX + q.t * w, y(q.p));

    final e = entry;
    if (e != null) {
      final ey = y(e);
      final dash = Paint()
        ..color = guide.withValues(alpha: 0.55)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.butt;
      for (var x = 0.0; x < size.width; x += 7) {
        canvas.drawLine(
            Offset(x, ey), Offset(math.min(x + 4, size.width), ey), dash);
      }
    }

    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (final q in points.skip(1)) {
      final o = at(q);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..color = color);

    final end = at(points.last);
    canvas.drawCircle(end, 5, Paint()..color = ring..isAntiAlias = true);
    canvas.drawCircle(end, 3.5, Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(PolyJourneyPainter old) =>
      old.points != points ||
      old.entry != entry ||
      old.lo != lo ||
      old.hi != hi ||
      old.color != color ||
      old.guide != guide ||
      old.ring != ring;
}
