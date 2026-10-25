// lib/screens/portfolio/components/balances_overview.dart
//
// Investments → Portfolio → Balances. What the money is DOING first, where
// it sits only as detail (founder, October 2026, after a competitor review:
// Robinhood's "Buying power", Revolut's "Total wealth"; the account-by-
// account layout before it read "it means nothing, I don't know which is
// which"). Top down:
//
//   * a moderate RING on the left (the engine's KuteDonutChart) with
//     "Total" and the total in its hole, and a three-line LEGEND to its
//     right: a dot, the label and its share of the total, for
//       Buying power — every spare dollar: Dollars + Hyperliquid cash +
//                      Polymarket cash,
//       Predictions  — what the open Polymarket positions are worth (and
//                      the cash open BUY orders reserve: money at work
//                      there, named under the row),
//       Investing    — what the open Hyperliquid positions are worth.
//     Each category wears a FIXED colour of the muted chart palette
//     (Buying power indigo, Investing teal, Predictions amber:
//     AppColorsExtension.chartCategorical), never a rank colour, so the
//     legend, the slices and the rows' dots always agree. A category at
//     0% stays in the legend, dimmed, with no slice; thin gaps between
//     slices (the ring's own);
//   * one hairline ROW per category, its dot first:
//       Buying power — "Ready for any trade or prediction", the spare cash
//                      on the right; under it quiet indented sub-rows,
//                      where it sits, largest first: Hyperliquid,
//                      Polymarket, Dollars (all three, $0.00 when known);
//       Predictions  — "N open", the value and a chevron: a tap opens the
//                      Positions section (it has no venue filter);
//       Investing    — "N open" or "No open positions" (or what open
//                      orders hold, when that is all there is), the value
//                      and a chevron, the same tap.
//     A Rebalance note sits under its venue's sub-row; an open order's
//     reserve under Predictions. Every amount ends on one column.
//
// Unknown figures keep the breakdown's rules: a figure never read reads a
// dash, dimmed and sweeping ([StaleShimmer]); a cached one is dimmed with
// the same sweep while it refreshes; never a confident $0.00. While any
// part of the total is unknown the ring shows its track only and the
// legend no shares: a share cannot be drawn without a guess.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/theme/app_theme.dart';

/// The three accounts the figures come from.
enum BalancesPart { dollars, investing, predictions }

/// What the money is doing, in legend and row order.
enum BalancesCategory { buyingPower, predictions, investing }

/// Under this a figure is nothing ("$0.00"): no slice.
const double kBalancesCentUsd = 0.005;

/// The ring's size: moderate, beside its legend (the Breakdown card's
/// ring is 184 on a row of its own).
const double kBalancesRingDiameter = 140;
const double kBalancesRingThickness = 12;

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

/// One account as the breakdown read it.
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

  /// Where the money sits, as the Buying power sub-row names it
  /// ("Hyperliquid", "Polymarket", "Dollars").
  final String name;
  final BalancesFigure cash;

  /// What it holds in positions; null for Dollars, which hold none.
  final BalancesFigure? positions;

  /// How many positions (Investing) or predictions (Predictions) it holds.
  final int positionCount;

  /// Cash its open orders reserve: neither spare cash nor a position
  /// (a prediction not yet bought). Part of the account's money at work,
  /// with [positions], and of its total; known whenever [positions] is.
  final double reservedUsd;

  /// Quiet captions under its sub-row: a Rebalance note.
  final List<String> footer;

  /// The key part of its widgets ("dollars", "investing").
  String get id => part.name;

  /// Both figures known.
  bool get known =>
      cash.usd != null && (positions == null || positions!.usd != null);

  double get cashUsd => _clean(cash.usd);
  double get positionsUsd => _clean(positions?.usd);

  /// What open orders reserve, counted only while [positions] is known.
  double get reservedCashUsd =>
      positions?.usd == null ? 0 : _clean(reservedUsd);

  /// Positions and the reserve together: the account's money at work (its
  /// share of the header's Invested).
  double get atWorkUsd => positionsUsd + reservedCashUsd;
  double get totalUsd => cashUsd + atWorkUsd;

  bool get stale => cash.stale || (positions?.stale ?? false);
}

double _clean(double? usd) => usd != null && usd.isFinite && usd > 0 ? usd : 0;

/// One category's figure: its value (null while a part of it is unknown)
/// and whether any part is refreshing.
typedef BalancesCategoryFigure = ({double? usd, bool stale});

/// The categories the accounts make, in legend order: Buying power (every
/// account's cash), then Predictions and Investing (what each venue has at
/// work), each only when its venue is on the account. Pure for the tests.
Map<BalancesCategory, BalancesCategoryFigure> balancesCategories(
    List<BalancesEntry> entries) {
  BalancesEntry? of(BalancesPart part) {
    for (final e in entries) {
      if (e.part == part) return e;
    }
    return null;
  }

  BalancesCategoryFigure atWork(BalancesEntry e) => (
        usd: e.positions?.usd == null ? null : e.atWorkUsd,
        stale: e.positions?.stale ?? false,
      );
  final predictions = of(BalancesPart.predictions);
  final investing = of(BalancesPart.investing);
  return {
    BalancesCategory.buyingPower: (
      usd: entries.every((e) => e.cash.usd != null)
          ? entries.fold<double>(0, (s, e) => s + e.cashUsd)
          : null,
      stale: entries.any((e) => e.cash.stale),
    ),
    if (predictions != null) BalancesCategory.predictions: atWork(predictions),
    if (investing != null) BalancesCategory.investing: atWork(investing),
  };
}

/// The total of [categories], null while any is unknown.
double? balancesTotal(
        Map<BalancesCategory, BalancesCategoryFigure> categories) =>
    categories.values.every((c) => c.usd != null)
        ? categories.values.fold<double>(0, (s, c) => s + _clean(c.usd))
        : null;

/// Each category's share of the total (0..1, adding up to 1), in legend
/// order, zero for an empty one; empty while any figure is unknown or when
/// there is nothing at all. Pure for the tests.
Map<BalancesCategory, double> balancesShares(
    Map<BalancesCategory, BalancesCategoryFigure> categories) {
  final total = balancesTotal(categories);
  if (total == null || total < kBalancesCentUsd) return const {};
  return {
    for (final e in categories.entries)
      e.key: _clean(e.value.usd) < kBalancesCentUsd
          ? 0.0
          : _clean(e.value.usd) / total,
  };
}

/// A share as the legend writes it: whole percents, "<1%" for a sliver
/// that is not nothing, ">99%" for all but a sliver, "0%" for nothing.
/// Pure for the tests.
String balancesPercent(double share) {
  if (!share.isFinite || share <= 0) return '0%';
  final pct = share * 100;
  if (pct < 1) return '<1%';
  if (pct > 99 && pct < 100) return '>99%';
  return '${pct.round()}%';
}

/// Each category's fixed colour: the muted chart palette's indigo, amber
/// and teal, the same in the legend, the ring and the rows.
Color balancesCategoryColor(AppColorsExtension c, BalancesCategory category) =>
    switch (category) {
      BalancesCategory.buyingPower => c.chartCategorical[0],
      BalancesCategory.investing => c.chartCategorical[1],
      BalancesCategory.predictions => c.chartCategorical[2],
    };

/// The accounts under Buying power, largest cash first (an unknown one
/// last; ties in account order). Pure for the tests.
List<BalancesEntry> balancesBuyingPowerPlaces(List<BalancesEntry> entries) =>
    [...entries]..sort((a, b) {
        final au = a.cash.usd, bu = b.cash.usd;
        if (au == null || bu == null) {
          if (au == null && bu == null) return a.part.index - b.part.index;
          return au == null ? 1 : -1;
        }
        final bySize = _clean(bu).compareTo(_clean(au));
        return bySize != 0 ? bySize : a.part.index - b.part.index;
      });

/// The ring and its legend over one row per category (see the file
/// header). [money] writes an amount (masked when balances are hidden);
/// [wrap] lets the breakdown wrap each account's sub-row (its Rebalance
/// band, the Dollars arrival); [onPositions] is a tap on Predictions or
/// Investing (null: not tappable).
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
    final categories = balancesCategories(entries);
    final shares = balancesShares(categories);
    final total = balancesTotal(categories);
    // Unknown: a dash, dimmed and sweeping, never a confident $0.00.
    BalancesFigure figure(BalancesCategoryFigure f) => f.usd == null
        ? const BalancesFigure('—', stale: true)
        : BalancesFigure(money(f.usd!), stale: f.stale, usd: f.usd);
    final totalFigure = total == null
        ? const BalancesFigure('—', stale: true)
        : BalancesFigure(money(total),
            stale: categories.values.any((f) => f.stale), usd: total);
    String label(BalancesCategory category) => switch (category) {
          BalancesCategory.buyingPower => l10n.portfolioBuyingPower,
          BalancesCategory.predictions => l10n.predictions,
          BalancesCategory.investing => l10n.trading,
        };
    BalancesEntry? entryOf(BalancesPart part) {
      for (final e in entries) {
        if (e.part == part) return e;
      }
      return null;
    }

    final hairline = Divider(
      color: context.isDark ? c.border : c.borderSubtle,
      height: 1,
      thickness: 0.5,
    );

    // A venue's secondary line: how many are open; what open orders hold
    // when that is all there is; or nothing open.
    String openLine(BalancesEntry e) {
      if (e.positionCount > 0) return l10n.portfolioOpenCount(e.positionCount);
      if (e.positions?.usd != null && e.atWorkUsd >= kBalancesCentUsd) {
        return l10n.investingInOpenOrders(money(e.atWorkUsd));
      }
      return l10n.portfolioNoOpenPositions;
    }

    Widget venueRow(BalancesCategory category, BalancesEntry e) {
      final reserve = e.positionCount > 0 &&
              e.reservedCashUsd >= kBalancesCentUsd
          ? l10n.investingInOpenOrders(money(e.reservedCashUsd))
          : null;
      return _CategoryRow(
        key: ValueKey('portfolio-balance-category-${category.name}'),
        category: category,
        color: balancesCategoryColor(c, category),
        title: label(category),
        line: openLine(e),
        caption: reserve,
        figure: figure(categories[category]!),
        onTap: onPositions,
      );
    }

    final places = balancesBuyingPowerPlaces(entries);
    final predictions = entryOf(BalancesPart.predictions);
    final investing = entryOf(BalancesPart.investing);

    return Column(
      key: const ValueKey('portfolio-balance-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 8.h),
        Row(
          children: [
            _Ring(
              categories: categories.keys.toList(),
              shares: shares,
              total: totalFigure,
              label: l10n.total,
              semantics: [
                '${l10n.total} ${totalFigure.text}',
                if (shares.isNotEmpty)
                  for (final k in categories.keys)
                    '${label(k)} ${balancesPercent(shares[k] ?? 0)}',
              ].join(', '),
            ),
            SizedBox(width: 20.w),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, k) in categories.keys.indexed) ...[
                      if (i > 0) SizedBox(height: 12.h),
                      _LegendLine(
                        key: ValueKey('portfolio-balance-legend-${k.name}'),
                        color: balancesCategoryColor(c, k),
                        label: label(k),
                        // No share while the total is unknown.
                        share: shares.isEmpty
                            ? null
                            : balancesPercent(shares[k] ?? 0),
                        dimmed: shares.isNotEmpty && (shares[k] ?? 0) <= 0,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 20.h),
        hairline,
        _CategoryRow(
          key: const ValueKey('portfolio-balance-category-buyingPower'),
          category: BalancesCategory.buyingPower,
          color: balancesCategoryColor(c, BalancesCategory.buyingPower),
          title: l10n.portfolioBuyingPower,
          line: l10n.portfolioBuyingPowerHint,
          figure: figure(categories[BalancesCategory.buyingPower]!),
        ),
        for (final e in places)
          _wrap(
              e.part,
              _PlaceRow(
                key: ValueKey('portfolio-balance-${e.id}'),
                entry: e,
                cash: e.cash.usd == null
                    ? const BalancesFigure('—', stale: true)
                    : e.cash,
              )),
        SizedBox(height: 10.h),
        if (predictions != null) ...[
          hairline,
          venueRow(BalancesCategory.predictions, predictions),
        ],
        if (investing != null) ...[
          hairline,
          venueRow(BalancesCategory.investing, investing),
        ],
        hairline,
      ],
    );
  }

  Widget _wrap(BalancesPart part, Widget row) => wrap?.call(part, row) ?? row;
}

/// The legend's and the rows' dot.
const double _kDot = 8;

/// A row's text starts after its dot and this gap; the sub-rows line up
/// with it.
const double _kDotGap = 12;

/// The chevron's room at a row's end: rows without one keep it empty, so
/// every amount ends on one column.
const double _kChevron = 20;
const double _kChevronGap = 4;

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
        constraints: BoxConstraints(maxWidth: 150.w),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerEnd,
          child: _Live(figure: figure, style: style),
        ),
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.dimmed = false});

  final Color color;
  final bool dimmed;

  @override
  Widget build(BuildContext context) => Container(
        width: _kDot.w,
        height: _kDot.w,
        decoration: BoxDecoration(
          color: dimmed ? context.colors.textDisabled : color,
          shape: BoxShape.circle,
        ),
      );
}

/// The ring: one slice per non-empty category in its colour, "Total" and
/// the total in the hole. Only the track while a figure is unknown. Not a
/// control: the rows below carry the detail and the taps.
class _Ring extends StatelessWidget {
  const _Ring({
    required this.categories,
    required this.shares,
    required this.total,
    required this.label,
    required this.semantics,
  });

  final List<BalancesCategory> categories;
  final Map<BalancesCategory, double> shares;
  final BalancesFigure total;
  final String label;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: IgnorePointer(
        child: KuteDonutChart(
          key: const ValueKey('portfolio-balance-ring'),
          diameter: kBalancesRingDiameter.w,
          thickness: kBalancesRingThickness.w,
          trackColor: context.isDark ? c.surfaceLight : c.surfaceElevated,
          onSelected: (_) {},
          segments: [
            for (final k in categories)
              if ((shares[k] ?? 0) > 0)
                KuteDonutSegment(
                  id: k,
                  value: shares[k]!,
                  color: balancesCategoryColor(c, k),
                  semanticsLabel: '',
                ),
          ],
          center: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  maxLines: 1,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  )),
              SizedBox(height: 2.h),
              // The hole is narrow: a long total scales down, never spills.
              FittedBox(
                key: const ValueKey('portfolio-balance-total'),
                fit: BoxFit.scaleDown,
                child: _Live(
                  figure: total,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    height: 1.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One legend line: the dot, the label, the share at the end; dimmed at
/// 0%.
class _LegendLine extends StatelessWidget {
  const _LegendLine({
    super.key,
    required this.color,
    required this.label,
    required this.share,
    required this.dimmed,
  });

  final Color color;
  final String label;

  /// Null while the total is unknown.
  final String? share;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(
      color: dimmed ? c.textTertiary : c.textPrimary,
      fontSize: 14.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.25,
    );
    return Row(
      children: [
        _Dot(color: color, dimmed: dimmed),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
        SizedBox(width: 8.w),
        Text(share ?? '—',
            key: const ValueKey('portfolio-balance-legend-share'),
            style: style.copyWith(
                color:
                    dimmed || share == null ? c.textTertiary : c.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
  }
}

/// A category row: its dot, its title over a quiet line (and a caption),
/// its figure on the right; a chevron and a tap when [onTap] is given.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    super.key,
    required this.category,
    required this.color,
    required this.title,
    required this.line,
    required this.figure,
    this.caption,
    this.onTap,
  });

  final BalancesCategory category;
  final Color color;
  final String title;
  final String line;
  final String? caption;
  final BalancesFigure figure;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final quiet = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: 14.h),
      child: Row(
        children: [
          _Dot(color: color),
          SizedBox(width: _kDotGap.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.settingsTitle(context)
                        .copyWith(letterSpacing: -0.2, height: 1.25)),
                SizedBox(height: 2.h),
                Text(line,
                    key: ValueKey('portfolio-balance-category-${category.name}-line'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: quiet),
                if (caption case final text?) ...[
                  SizedBox(height: 2.h),
                  Text(text,
                      key: ValueKey(
                          'portfolio-balance-category-${category.name}-caption'),
                      style: quiet.copyWith(color: c.textTertiary)),
                ],
              ],
            ),
          ),
          SizedBox(width: 12.w),
          _EndFigure(
            key: ValueKey('portfolio-balance-category-${category.name}-amount'),
            figure: figure,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              height: 1.25,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(width: _kChevronGap.w),
          if (onTap != null)
            Icon(Icons.chevron_right_rounded,
                size: _kChevron.w, color: c.textTertiary)
          else
            SizedBox(width: _kChevron.w),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: onTap != null,
      label: [title, figure.text, line, if (caption != null) caption!]
          .join(', '),
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

/// Where spare cash sits: a quiet indented line under Buying power, the
/// account's name and its cash, any Rebalance note under it.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({super.key, required this.entry, required this.cash});

  final BalancesEntry entry;
  final BalancesFigure cash;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(
      color: c.textSecondary,
      fontSize: 14.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      container: true,
      label: [entry.name, cash.text, ...entry.footer].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
            start: (_kDot + _kDotGap).w,
            end: (_kChevron + _kChevronGap).w,
            top: 4.h,
            bottom: 4.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style),
                ),
                SizedBox(width: 12.w),
                _EndFigure(
                  key: ValueKey('portfolio-balance-${entry.id}-amount'),
                  figure: cash,
                  style: style,
                ),
              ],
            ),
            for (final note in entry.footer) ...[
              SizedBox(height: 2.h),
              Text(note,
                  style:
                      style.copyWith(color: c.textTertiary, fontSize: 13.sp)),
            ],
          ],
        ),
      ),
    );
  }
}
