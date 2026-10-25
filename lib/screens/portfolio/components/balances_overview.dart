// lib/screens/portfolio/components/balances_overview.dart
//
// Investments → Portfolio → Balances (founder request, October 2026:
// "balances is not clear. for example dollars are always available
// regardless", then "ready to use should be sub divided into the 3 i
// think no? position no its all the same"). The breakdown's figures as a
// plain statement, top down:
//
//   * TOTAL: a quiet "Total" over the sum of every balance, in the hero's
//     type a size down;
//   * one thin SEGMENTED BAR under it (8 pt, rounded): each account's
//     cash (Dollars, Investing, Predictions) and ONE segment for what all
//     the positions are worth together, each its share of the total,
//     largest first, in the app's chart ramp by rank (the largest the
//     deepest blue; a sliver under 2% the chart grey:
//     AppColorsExtension.chartColorsByShare), a hairline gap between
//     segments, an empty one drawing none. Nothing but the track while
//     any figure is unknown: a share cannot be drawn without a guess;
//   * READY TO USE: a quiet label with the cash of all three on the right
//     of its line, then one plain ROW per account, no card, hairlines
//     between: its mark and name, its cash on the right (Dollars' balance,
//     each venue's cash). No legend dots: the marks name the accounts. A
//     Rebalance note or the open orders' reserve, when there is one, is a
//     quiet caption under the name;
//   * IN POSITIONS: one row for every position and prediction together,
//     never split by venue: "In positions" with their value on the right
//     and a quiet "N positions" under it (when any); a tap opens the
//     Positions section.
//
// Unknown figures keep the breakdown's rules: a figure never read reads
// a dash, dimmed and sweeping ([StaleShimmer]); a cached one is dimmed
// with the same sweep while it refreshes; never a confident $0.00. The
// account rows are not tappable; the breakdown wraps each in its
// Rebalance band.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_motion.dart'
    show RollingFigure, kuteReduceMotion;
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/theme/app_theme.dart';

/// The three accounts, in row order.
enum BalancesPart { dollars, investing, predictions }

/// The bar's segments: each account's cash, then every position together.
enum BalancesSegment { dollars, investing, predictions, positions }

/// The bar's first draw.
const Duration kBalancesBarDrawDuration = Duration(milliseconds: 700);

/// Under this a figure is nothing ("$0.00"): no segment.
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
    this.reservedUsd = 0,
    this.footer = const [],
  });

  final BalancesPart part;
  final String asset;
  final String name;
  final BalancesFigure cash;

  /// What it holds in positions; null for Dollars, which hold none.
  final BalancesFigure? positions;

  /// How many positions (Investing) or predictions (Predictions) it
  /// holds: the In positions row counts them together.
  final int positionCount;

  /// Cash its open orders reserve: neither ready to use nor a position
  /// (a prediction not yet bought). Part of the account's money at work,
  /// with [positions], and of its total; known whenever [positions] is.
  final double reservedUsd;

  /// Quiet captions under the name: a Rebalance note, what open orders
  /// reserve.
  final List<String> footer;

  /// The key part of its widgets ("dollars", "investing").
  String get id => part.name;

  /// Both figures known.
  bool get known =>
      cash.usd != null && (positions == null || positions!.usd != null);

  double get cashUsd => _clean(cash.usd);
  double get positionsUsd => _clean(positions?.usd);

  /// What open orders reserve, counted only while [positions] is known.
  double get reservedCashUsd => positions?.usd == null ? 0 : _clean(reservedUsd);

  /// Positions and the reserve together: the account's money at work (its
  /// share of the header's Invested).
  double get atWorkUsd => positionsUsd + reservedCashUsd;
  double get totalUsd => cashUsd + atWorkUsd;

  bool get stale => cash.stale || (positions?.stale ?? false);
}

double _clean(double? usd) => usd != null && usd.isFinite && usd > 0 ? usd : 0;

BalancesSegment _segmentOf(BalancesPart part) => switch (part) {
      BalancesPart.dollars => BalancesSegment.dollars,
      BalancesPart.investing => BalancesSegment.investing,
      BalancesPart.predictions => BalancesSegment.predictions,
    };

/// The bar's segments: each account's non-empty cash and, when any, what
/// every position is worth together, each with its share of the total
/// (0..1, adding up to 1), largest first (ties in [BalancesSegment]
/// order). None while any figure is unknown, or when there is nothing.
/// Pure for the tests.
List<(BalancesSegment, double)> balancesBarSegments(
    List<BalancesEntry> entries) {
  if (entries.any((e) => !e.known)) return const [];
  final positions = entries.fold<double>(0, (sum, e) => sum + e.atWorkUsd);
  final parts = <(BalancesSegment, double)>[
    for (final e in entries) (_segmentOf(e.part), e.cashUsd),
    (BalancesSegment.positions, positions),
  ];
  final total = parts.fold<double>(0, (sum, p) => sum + p.$2);
  if (total < kBalancesCentUsd) return const [];
  return [
    for (final (segment, usd) in parts)
      if (usd >= kBalancesCentUsd) (segment, usd / total),
  ]..sort((a, b) {
      final bySize = b.$2.compareTo(a.$2);
      return bySize != 0 ? bySize : a.$1.index.compareTo(b.$1.index);
    });
}

/// Each segment's colour: the chart ramp by rank of size.
Map<BalancesSegment, Color> balancesBarColors(
    AppColorsExtension c, List<(BalancesSegment, double)> segments) {
  final colors = c.chartColorsByShare([for (final s in segments) s.$2]);
  return {
    for (var i = 0; i < segments.length; i++) segments[i].$1: colors[i],
  };
}

/// The summary's figures in dollars: the total, the cash ready to use and
/// what is in positions; each null while a part of it is unknown. Pure for
/// the tests.
({double? total, double? ready, double? inPositions}) balancesSummary(
    List<BalancesEntry> entries) {
  final ready = entries.every((e) => e.cash.usd != null)
      ? entries.fold<double>(0, (s, e) => s + e.cashUsd)
      : null;
  final held = [
    for (final e in entries)
      if (e.positions != null) e,
  ];
  // Positions and what open orders reserve: the header's Invested.
  final inPositions = held.every((e) => e.positions!.usd != null)
      ? held.fold<double>(0, (s, e) => s + e.atWorkUsd)
      : null;
  return (
    total: ready != null && inPositions != null ? ready + inPositions : null,
    ready: ready,
    inPositions: inPositions,
  );
}

/// How many positions and predictions the accounts hold together.
int balancesPositionCount(List<BalancesEntry> entries) => entries.fold<int>(
    0, (n, e) => n + (e.positionCount > 0 ? e.positionCount : 0));

/// The total, the bar, Ready to use over a row per account, then In
/// positions (see the file header). [money] writes an amount (masked when
/// balances are hidden); [wrap] lets the breakdown wrap each account row
/// (its Rebalance band, the Dollars arrival); [onPositions] is a tap on
/// In positions (null: not tappable).
class BalancesOverview extends StatelessWidget {
  const BalancesOverview({
    super.key,
    required this.entries,
    required this.money,
    this.wrap,
    this.onPositions,
  });

  final List<BalancesEntry> entries;
  final String Function(double usd) money;
  final Widget Function(BalancesPart part, Widget row)? wrap;
  final VoidCallback? onPositions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final sum = balancesSummary(entries);
    final segments = balancesBarSegments(entries);
    final colors = balancesBarColors(c, segments);
    final stale = entries.any((e) => e.stale);
    // Unknown: a dash, dimmed and sweeping, never a confident $0.00.
    BalancesFigure figure(double? usd, bool anyStale) => usd == null
        ? const BalancesFigure('—', stale: true)
        : BalancesFigure(money(usd), stale: anyStale, usd: usd);
    final total = figure(sum.total, stale);
    final ready = figure(sum.ready, entries.any((e) => e.cash.stale));
    final inPositions = figure(
        sum.inPositions, entries.any((e) => e.positions?.stale ?? false));
    final count = balancesPositionCount(entries);
    final label = TextStyle(
      color: c.textSecondary,
      fontSize: 14.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.25,
    );
    final hairline = Divider(
      color: context.isDark ? c.border : c.borderSubtle,
      height: 1,
      thickness: 0.5,
      indent: _kRowMark.w + _kRowGap.w,
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
        SizedBox(height: 24.h),
        _SectionLine(
          key: const ValueKey('portfolio-balance-ready'),
          label: l10n.portfolioBalanceReadyToUse,
          figure: ready,
        ),
        SizedBox(height: 2.h),
        for (final (i, e) in entries.indexed) ...[
          if (i > 0) hairline,
          _wrap(
              e.part,
              _AccountRow(
                key: ValueKey('portfolio-balance-${e.id}'),
                entry: e,
                cash: e.cash.usd == null
                    ? const BalancesFigure('—', stale: true)
                    : e.cash,
              )),
        ],
        Divider(
          color: context.isDark ? c.border : c.borderSubtle,
          height: 1,
          thickness: 0.5,
        ),
        _PositionsRow(
          key: const ValueKey('portfolio-balance-positions'),
          label: l10n.portfolioBalanceInPositionsLabel,
          figure: inPositions,
          line: count > 0 ? l10n.portfolioPositionsCount(count) : null,
          onTap: onPositions,
        ),
      ],
    );
  }

  Widget _wrap(BalancesPart part, Widget row) => wrap?.call(part, row) ?? row;
}

/// A row's mark and the gap after it.
const double _kRowMark = 36;
const double _kRowGap = 12;

/// An amount on the right of a row.
TextStyle _amountStyle(BuildContext context) => TextStyle(
      color: context.colors.textPrimary,
      fontSize: 16.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.25,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// A live figure: a new value rolls the digits that changed; while it
/// refreshes (or is not known yet) it is dimmed with the skeleton's sweep.
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

/// An amount at the end of a row, scaled down rather than cut.
class _EndFigure extends StatelessWidget {
  const _EndFigure({super.key, required this.figure, required this.style});

  final BalancesFigure figure;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 160.w),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerEnd,
          child: _Live(figure: figure, style: style),
        ),
      );
}

/// Ready to use's line: the quiet label, its sum at the end.
class _SectionLine extends StatelessWidget {
  const _SectionLine({super.key, required this.label, required this.figure});

  final String label;
  final BalancesFigure figure;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(
      color: c.textSecondary,
      fontSize: 14.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.25,
    );
    return Semantics(
      container: true,
      header: true,
      label: '$label ${figure.text}',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
          SizedBox(width: 12.w),
          _EndFigure(
            key: const ValueKey('portfolio-balance-ready-amount'),
            figure: figure,
            style: style.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

/// The thin bar: one segment per non-empty figure in its colour, a
/// hairline gap between, over the quiet track; grown in once on first
/// show (at once under Reduce Motion).
class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.segments, required this.colors});

  final List<(BalancesSegment, double)> segments;
  final Map<BalancesSegment, Color> colors;

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
                for (final (i, (segment, share)) in segments.indexed) ...[
                  if (i > 0) SizedBox(width: 2.w),
                  Expanded(
                    // Thousandths, never zero: a sliver stays visible.
                    flex: math.max(1, (share * 1000).round()),
                    child: ColoredBox(
                      key: ValueKey('portfolio-balance-bar-${segment.name}'),
                      color: colors[segment] ?? c.chartOther,
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

/// One account: its mark and name, its cash on the right; any caption
/// under the name.
class _AccountRow extends StatelessWidget {
  const _AccountRow({super.key, required this.entry, required this.cash});

  final BalancesEntry entry;
  final BalancesFigure cash;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    final caption = TextStyle(
      color: c.textTertiary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
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
                Text(e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.settingsTitle(context)
                        .copyWith(letterSpacing: -0.2, height: 1.25)),
                for (final note in e.footer) ...[
                  SizedBox(height: 2.h),
                  Text(note, style: caption),
                ],
              ],
            ),
          ),
          SizedBox(width: 12.w),
          _EndFigure(
            key: ValueKey('portfolio-balance-${e.id}-amount'),
            figure: cash,
            style: _amountStyle(context),
          ),
        ],
      ),
    );
  }
}

/// Every position and prediction together: "In positions" and a quiet
/// count under it, their value on the right; a tap opens the Positions
/// section ([onTap], null: not tappable).
class _PositionsRow extends StatelessWidget {
  const _PositionsRow({
    super.key,
    required this.label,
    required this.figure,
    required this.line,
    this.onTap,
  });

  final String label;
  final BalancesFigure figure;

  /// "N positions"; null when none is held.
  final String? line;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: 14.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.settingsTitle(context)
                        .copyWith(letterSpacing: -0.2, height: 1.25)),
                if (line case final text?) ...[
                  SizedBox(height: 2.h),
                  Text(text,
                      key: const ValueKey('portfolio-balance-positions-line'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                        height: 1.3,
                      )),
                ],
              ],
            ),
          ),
          SizedBox(width: 12.w),
          _EndFigure(
            key: const ValueKey('portfolio-balance-positions-amount'),
            figure: figure,
            style: _amountStyle(context),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: onTap != null,
      label: [label, figure.text, if (line != null) line!].join(', '),
      excludeSemantics: true,
      child: onTap == null
          ? row
          : Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: row),
            ),
    );
  }
}
