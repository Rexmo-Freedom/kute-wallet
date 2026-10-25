// lib/screens/portfolio/components/balances_overview.dart
//
// Investments → Portfolio → Balances (founder request, October 2026:
// "balances is not clear. for example dollars are always available
// regardless"). The breakdown's figures as a plain statement, top down:
//
//   * TOTAL: a quiet "Total" over the sum of every balance, in the hero's
//     type a size down;
//   * one thin SEGMENTED BAR under it (8 pt, rounded), split by each
//     balance's share of the total, largest first, in the app's chart
//     ramp by rank (the largest the deepest blue; a sliver under 2% the
//     chart grey: AppColorsExtension.chartColorsByShare), a hairline gap
//     between segments, an empty balance drawing none; each row below
//     carries its segment's colour as a small dot before its name.
//     Nothing but the track while any balance is unknown: a share cannot
//     be drawn without a guess;
//   * two figures side by side: READY TO USE (the cash of all three:
//     Dollars and the venues' cash) and IN POSITIONS (what the open
//     positions and predictions are worth);
//   * one plain ROW per balance, no card, hairlines between: its mark,
//     name and one secondary line, its total on the right. Dollars always
//     reads "Available"; a venue reads "$X available", then "· $Y in N
//     positions" (Investing) or "· $Y in N predictions" (Predictions;
//     the app never says "bets") when it holds any ("· $Y in open
//     orders" when only orders hold its money). A Rebalance note or the
//     open orders' reserve, when there is one, is a quiet caption under
//     it.
//
// Unknown figures keep the breakdown's rules: a balance never read
// reads a dash and its secondary line is a shimmering bone, a cached one
// is dimmed with the skeleton's sweep ([StaleShimmer]) while it
// refreshes, never a confident $0.00. The rows are not tappable (the
// ring's rows only picked a slice); the breakdown wraps each in its
// Rebalance band.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_motion.dart'
    show RollingFigure, kuteReduceMotion;
import 'package:kute/screens/shared/kute_skeleton.dart' show SkeletonBar;
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/theme/app_theme.dart';

/// The three balances, in bar and row order.
enum BalancesPart { dollars, investing, predictions }

/// The bar's first draw.
const Duration kBalancesBarDrawDuration = Duration(milliseconds: 700);

/// Under this a figure is nothing ("$0.00"): no positions part.
const double kBalancesCentUsd = 0.005;

/// A figure as the breakdown resolved it: its text (masked when balances
/// are hidden, a dash when never read), whether it is still refreshing,
/// and its value (null when unknown).
@immutable
class BalancesFigure {
  const BalancesFigure(this.text, {this.stale = false, this.usd});

  final String text;
  final bool stale;
  final double? usd;
}

/// One balance as its row shows it.
@immutable
class BalancesEntry {
  const BalancesEntry({
    required this.part,
    required this.asset,
    required this.name,
    required this.cash,
    this.positions,
    this.positionCount = 0,
    this.footer = const [],
  });

  final BalancesPart part;
  final String asset;
  final String name;
  final BalancesFigure cash;

  /// What it holds in positions; null for Dollars, which hold none.
  final BalancesFigure? positions;

  /// How many positions (Investing) or predictions (Predictions) it
  /// holds.
  final int positionCount;

  /// Quiet captions under the secondary line: a Rebalance note, what open
  /// orders reserve.
  final List<String> footer;

  /// The key part of its widgets ("dollars", "investing").
  String get id => part.name;

  /// Both figures known.
  bool get known =>
      cash.usd != null && (positions == null || positions!.usd != null);

  double get cashUsd => _clean(cash.usd);
  double get positionsUsd => _clean(positions?.usd);
  double get totalUsd => cashUsd + positionsUsd;

  bool get stale => cash.stale || (positions?.stale ?? false);
}

double _clean(double? usd) => usd != null && usd.isFinite && usd > 0 ? usd : 0;

/// The bar's segments: each non-empty balance with its share of the
/// total (0..1, adding up to 1), largest first (ties in row order). None
/// while any balance is unknown, or when there is nothing. Pure for the
/// tests.
List<(BalancesPart, double)> balancesBarSegments(List<BalancesEntry> entries) {
  if (entries.any((e) => !e.known)) return const [];
  final total = entries.fold<double>(0, (sum, e) => sum + e.totalUsd);
  if (total < kBalancesCentUsd) return const [];
  return [
    for (final e in entries)
      if (e.totalUsd >= kBalancesCentUsd) (e.part, e.totalUsd / total),
  ]..sort((a, b) {
      final bySize = b.$2.compareTo(a.$2);
      return bySize != 0 ? bySize : a.$1.index.compareTo(b.$1.index);
    });
}

/// Each segment's colour, by part: the chart ramp by rank of size.
Map<BalancesPart, Color> balancesBarColors(
    AppColorsExtension c, List<(BalancesPart, double)> segments) {
  final colors = c.chartColorsByShare([for (final s in segments) s.$2]);
  return {
    for (var i = 0; i < segments.length; i++) segments[i].$1: colors[i],
  };
}

/// The summary's three figures in dollars: the total, the cash ready to
/// use and what is in positions; each null while a part of it is unknown.
/// Pure for the tests.
({double? total, double? ready, double? inPositions}) balancesSummary(
    List<BalancesEntry> entries) {
  final ready = entries.every((e) => e.cash.usd != null)
      ? entries.fold<double>(0, (s, e) => s + e.cashUsd)
      : null;
  final held = [
    for (final e in entries)
      if (e.positions case final p?) p,
  ];
  final inPositions = held.every((p) => p.usd != null)
      ? held.fold<double>(0, (s, p) => s + _clean(p.usd))
      : null;
  return (
    total: ready != null && inPositions != null ? ready + inPositions : null,
    ready: ready,
    inPositions: inPositions,
  );
}

/// A row's secondary line, or null while its figures are not known (a
/// bone in its place). Dollars: "Available", always. A venue: "$X
/// available", then "· $Y in N positions" / "· $Y in N predictions"
/// when it holds any, "· $Y in open orders" when only orders hold its
/// money.
/// Pure for the tests.
String? balancesRowLine(AppLocalizations l10n, BalancesEntry e) {
  final positions = e.positions;
  if (positions == null) return l10n.available;
  if (e.cash.usd == null || positions.usd == null) return null;
  final available = l10n.hlYieldAvailableLine(e.cash.text);
  if (_clean(positions.usd) < kBalancesCentUsd) return available;
  final n = e.positionCount;
  final held = n <= 0
      ? l10n.investingInOpenOrders(positions.text)
      : e.part == BalancesPart.predictions
          ? l10n.portfolioBalanceInPredictions(positions.text, n)
          : l10n.portfolioBalanceInPositions(positions.text, n);
  return '$available · $held';
}

/// The total, the bar, the two figures and the rows (see the file
/// header). [money] writes an amount (masked when balances are hidden);
/// [wrap] lets the breakdown wrap each row (its Rebalance band, the
/// Dollars arrival).
class BalancesOverview extends StatelessWidget {
  const BalancesOverview({
    super.key,
    required this.entries,
    required this.money,
    this.wrap,
  });

  final List<BalancesEntry> entries;
  final String Function(double usd) money;
  final Widget Function(BalancesPart part, Widget row)? wrap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final sum = balancesSummary(entries);
    final segments = balancesBarSegments(entries);
    final colors = balancesBarColors(c, segments);
    final stale = entries.any((e) => e.stale);
    BalancesFigure figure(double? usd, bool anyStale) => usd == null
        ? const BalancesFigure('—')
        : BalancesFigure(money(usd), stale: anyStale, usd: usd);
    final total = figure(sum.total, stale);
    final ready = figure(sum.ready, entries.any((e) => e.cash.stale));
    final inPositions = figure(
        sum.inPositions, entries.any((e) => e.positions?.stale ?? false));
    final label = TextStyle(
      color: c.textSecondary,
      fontSize: 14.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.25,
    );

    return Column(
      key: const ValueKey('portfolio-balance-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 8.h),
        Text(l10n.total, style: label),
        SizedBox(height: 4.h),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FittedBox(
            key: const ValueKey('portfolio-balance-total'),
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: _Live(
              figure: total,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 34.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.0,
                height: 1.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        SizedBox(height: 16.h),
        ExcludeSemantics(
            child: _SegmentBar(segments: segments, colors: colors)),
        SizedBox(height: 18.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SummaryFigure(
                key: const ValueKey('portfolio-balance-ready'),
                label: l10n.portfolioBalanceReadyToUse,
                figure: ready,
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: _SummaryFigure(
                key: const ValueKey('portfolio-balance-in-positions'),
                label: l10n.portfolioBalanceInPositionsLabel,
                figure: inPositions,
              ),
            ),
          ],
        ),
        SizedBox(height: 16.h),
        for (final (i, e) in entries.indexed) ...[
          if (i > 0)
            Divider(
              color: context.isDark ? c.border : c.borderSubtle,
              height: 1,
              thickness: 0.5,
              indent: _kRowMark.w + _kRowGap.w,
            ),
          _wrap(
              e.part,
              _AccountRow(
                key: ValueKey('portfolio-balance-${e.id}'),
                entry: e,
                dot: colors[e.part],
                total: e.known
                    ? BalancesFigure(money(e.totalUsd),
                        stale: e.stale, usd: e.totalUsd)
                    : const BalancesFigure('—'),
                line: balancesRowLine(l10n, e),
              )),
        ],
      ],
    );
  }

  Widget _wrap(BalancesPart part, Widget row) => wrap?.call(part, row) ?? row;
}

/// A row's mark and the gap after it.
const double _kRowMark = 36;
const double _kRowGap = 12;

/// A live figure: a new value rolls the digits that changed; while it
/// refreshes it is dimmed with the skeleton's sweep.
class _Live extends StatelessWidget {
  const _Live({required this.figure, required this.style});

  final BalancesFigure figure;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => StaleShimmer(
        stale: figure.stale,
        child: RollingFigure(
            text: figure.text,
            style: figure.stale
                ? style.copyWith(color: context.colors.textSecondary)
                : style),
      );
}

/// One of the two figures under the bar: a quiet label over the amount.
class _SummaryFigure extends StatelessWidget {
  const _SummaryFigure({super.key, required this.label, required this.figure});

  final String label;
  final BalancesFigure figure;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: '$label ${figure.text}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
                height: 1.25,
              )),
          SizedBox(height: 2.h),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: _Live(
              figure: figure,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                height: 1.25,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The thin bar: one segment per non-empty balance in its colour, a
/// hairline gap between, over the quiet track; grown in once on first
/// show (at once under Reduce Motion).
class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.segments, required this.colors});

  final List<(BalancesPart, double)> segments;
  final Map<BalancesPart, Color> colors;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final height = 8.h;
    final track = context.isDark ? c.surfaceLight : c.surfaceElevated;
    return ClipRRect(
      key: const ValueKey('portfolio-balance-bar'),
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: track,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: kuteReduceMotion(context)
                ? Duration.zero
                : kBalancesBarDrawDuration,
            curve: Curves.easeOutCubic,
            // Laid out whole, revealed from the start edge: the gaps never
            // squeeze a row narrower than they are.
            builder: (context, t, child) => ClipRect(
              clipper: _RevealClipper(t, Directionality.of(context)),
              child: child,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, (part, share)) in segments.indexed) ...[
                  if (i > 0) SizedBox(width: 2.w),
                  Expanded(
                    // Thousandths, never zero: a sliver stays visible.
                    flex: math.max(1, (share * 1000).round()),
                    child: ColoredBox(
                      key: ValueKey('portfolio-balance-bar-${part.name}'),
                      color: colors[part] ?? c.chartOther,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The share [t] of the bar shown, from the start edge.
class _RevealClipper extends CustomClipper<Rect> {
  _RevealClipper(this.t, this.direction);

  final double t;
  final TextDirection direction;

  @override
  Rect getClip(Size size) {
    final w = size.width * t.clamp(0.0, 1.0);
    return direction == TextDirection.rtl
        ? Rect.fromLTWH(size.width - w, 0, w, size.height)
        : Rect.fromLTWH(0, 0, w, size.height);
  }

  @override
  bool shouldReclip(_RevealClipper old) =>
      old.t != t || old.direction != direction;
}

/// One balance: mark, name and its secondary line, its total on the
/// right; any caption under them.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    super.key,
    required this.entry,
    required this.total,
    required this.line,
    this.dot,
  });

  final BalancesEntry entry;

  /// Its segment's colour on the bar, the legend before its name; null
  /// when it draws no segment.
  final Color? dot;
  final BalancesFigure total;

  /// The secondary line; null draws a bone (the figures not read yet).
  final String? line;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    final secondary = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final caption = secondary.copyWith(color: c.textTertiary);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 14.h),
      child: Row(
        children: [
          SvgPicture.asset(e.asset, width: _kRowMark.w, height: _kRowMark.w),
          SizedBox(width: _kRowGap.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (dot case final color?) ...[
                      Container(
                        key: ValueKey('portfolio-balance-${e.id}-dot'),
                        width: 8.w,
                        height: 8.w,
                        decoration:
                            BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      SizedBox(width: 6.w),
                    ],
                    Flexible(
                      child: Text(e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.settingsTitle(context)
                              .copyWith(letterSpacing: -0.2, height: 1.25)),
                    ),
                  ],
                ),
                SizedBox(height: 2.h),
                if (line case final text?)
                  StaleShimmer(
                    stale: e.stale,
                    child: Text(text,
                        key: ValueKey('portfolio-balance-${e.id}-line'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: secondary),
                  )
                else
                  Padding(
                    key: ValueKey('portfolio-balance-${e.id}-line-loading'),
                    padding: EdgeInsets.symmetric(vertical: 3.h),
                    child: SkeletonBar(120.w, 12.h),
                  ),
                for (final note in e.footer) ...[
                  SizedBox(height: 2.h),
                  Text(note, style: caption),
                ],
              ],
            ),
          ),
          SizedBox(width: 12.w),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 150.w),
            child: FittedBox(
              key: ValueKey('portfolio-balance-${e.id}-total'),
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: _Live(
                figure: total,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.25,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
