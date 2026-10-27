// lib/screens/portfolio/components/balances_overview.dart
//
// Investments → Portfolio → Balances, the Portfolio's first section. What
// the money is DOING first, where it sits only as detail (founder,
// October 2026, after a competitor review: Robinhood's "Buying power",
// Revolut's "Total wealth"), and since 27 October 2026 the positions
// themselves under their venue (the Positions pill is gone). Top down:
//
//   * BUYING POWER on the left — a small "● Buying power" label, the
//     spare cash as the big figure (Dollars + Hyperliquid cash +
//     Polymarket cash), and "Ready for any trade or prediction" with a
//     small chevron that opens, in place, where that cash sits, largest
//     first: Hyperliquid, Polymarket, Dollars (all three, $0.00 when
//     known). A Rebalance note under a place opens the split by itself.
//     On the right a small RING (the engine's KuteDonutChart, 90) with
//     "Total" and the total in its hole; its slices wear each category's
//     FIXED colour of the muted chart palette (Buying power indigo,
//     Investing teal, Predictions amber: AppColorsExtension.chartCategorical),
//     the same as the dots, so there is no legend and no percentages;
//   * the breakdown's [action] (one full-width Move money, its steps);
//   * a hairline, then INVESTED with what Predictions and Investing have at
//     work on the right (bold);
//   * one block per venue: "● Predictions  N" with its value and its P&L
//     (in the result colour) on the right, the venue's positions under it,
//     slightly indented, as the Option-B position rows
//     (components/position_rows.dart: picture, short title, "event ·
//     side", chance bar with its entry tick, value and %), a tap opening
//     each one's sheet; then "● Investing  N" the same way. A venue with
//     nothing open reads "No open positions" in its header row and lists
//     nothing; what open orders hold there is named under its header.
//
// Unknown figures keep the breakdown's rules: a figure never read reads a
// dash, dimmed and sweeping ([StaleShimmer]); a cached one is dimmed with
// the same sweep while it refreshes; never a confident $0.00. While any
// part of the total is unknown the ring shows its track only.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show kPortfolioRowGap, kPortfolioRowImage;
import 'package:kute/screens/shared/kute_motion.dart'
    show RollingFigure, kuteReduceMotion;
import 'package:kute/screens/shared/kute_skeleton.dart' show SkeletonRowList;
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/theme/app_theme.dart';

/// The three accounts the figures come from.
enum BalancesPart { dollars, investing, predictions }

/// What the money is doing, in legend and row order.
enum BalancesCategory { buyingPower, predictions, investing }

/// Under this a figure is nothing ("$0.00"): no slice.
const double kBalancesCentUsd = 0.005;

/// The ring's size: small, at the end of the Buying power row (the
/// Breakdown card's ring is 184 on a row of its own).
const double kBalancesRingDiameter = 96;
const double kBalancesRingThickness = 7;

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

  /// Quiet captions under its sub-row (where Buying power sits): a
  /// Rebalance note. Any note opens the split.
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

/// What Balances lists under a venue's header: its position [rows], in
/// order (the breakdown's caller builds them, open_investments_screen.dart),
/// the venue's P&L beside its value ([pnl]), and shimmer rows while the
/// venue is still read with nothing listed ([loading]).
@immutable
class BalancesVenueList {
  const BalancesVenueList(
      {this.rows = const [], this.pnl, this.loading = false});

  final List<Widget> rows;
  final Widget? pnl;
  final bool loading;

  static const BalancesVenueList empty = BalancesVenueList();
}

/// Buying power and the ring, Move money ([action]), Invested and each
/// venue with its positions (see the file header). [money] writes an
/// amount (masked when balances are hidden); [wrap] lets the breakdown
/// wrap each account's place row (its Rebalance band, the Dollars
/// arrival); [venues] are the rows under Predictions and Investing.
class BalancesOverview extends StatefulWidget {
  const BalancesOverview({
    super.key,
    required this.entries,
    required this.money,
    this.wrap,
    this.action,
    this.venues = const {},
  });

  final List<BalancesEntry> entries;
  final String Function(double usd) money;
  final Widget Function(BalancesPart part, Widget row)? wrap;
  final Widget? action;
  final Map<BalancesCategory, BalancesVenueList> venues;

  @override
  State<BalancesOverview> createState() => _BalancesOverviewState();
}

class _BalancesOverviewState extends State<BalancesOverview> {
  /// Where Buying power sits, opened with its chevron.
  bool _split = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final entries = widget.entries;
    final money = widget.money;
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

    // Invested: what both venues have at work, the hero's old second line.
    final atWork = [
      for (final e in categories.entries)
        if (e.key != BalancesCategory.buyingPower) e.value,
    ];
    final invested = figure((
      usd: atWork.every((f) => f.usd != null)
          ? atWork.fold<double>(0, (s, f) => s + _clean(f.usd))
          : null,
      stale: atWork.any((f) => f.stale),
    ));

    Widget venue(BalancesCategory category, BalancesEntry e) {
      final list = widget.venues[category] ?? BalancesVenueList.empty;
      final open = e.positionCount > 0 || list.rows.isNotEmpty;
      final f = figure(categories[category]!);
      // Nothing open: what open orders hold when that is all there is,
      // else "No open positions" in the header's place for a figure.
      final reserve = e.reservedCashUsd >= kBalancesCentUsd
          ? l10n.investingInOpenOrders(money(e.reservedCashUsd))
          : !open && e.positions?.usd != null && e.atWorkUsd >= kBalancesCentUsd
              ? l10n.investingInOpenOrders(money(e.atWorkUsd))
              : null;
      final empty = !open && !list.loading && reserve == null && !f.stale;
      return Column(
        key: ValueKey('portfolio-balance-venue-${category.name}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _VenueHeader(
            key: ValueKey('portfolio-balance-category-${category.name}'),
            category: category,
            color: balancesCategoryColor(c, category),
            title: label(category),
            count: e.positionCount > 0 ? e.positionCount : null,
            figure: f,
            pnl: open ? list.pnl : null,
            empty: empty ? l10n.portfolioNoOpenPositions : null,
            caption: reserve,
          ),
          if (list.rows.isNotEmpty || list.loading)
            Padding(
              key: ValueKey('portfolio-balance-${category.name}-positions'),
              padding: EdgeInsetsDirectional.only(start: (_kDot + _kDotGap).w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ..._rowsWithHairlines(context, list.rows),
                  if (list.loading)
                    SkeletonRowList(
                        count: 2,
                        padding: EdgeInsets.symmetric(vertical: 8.h),
                        rowPadding: EdgeInsets.symmetric(vertical: 10.h)),
                ],
              ),
            ),
        ],
      );
    }

    final places = balancesBuyingPowerPlaces(entries);
    // A Rebalance note is never folded away.
    final split = _split || places.any((e) => e.footer.isNotEmpty);
    final predictions = entryOf(BalancesPart.predictions);
    final investing = entryOf(BalancesPart.investing);
    final buyingPower = figure(categories[BalancesCategory.buyingPower]!);

    return Column(
      key: const ValueKey('portfolio-balance-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 8.h),
        Row(
          children: [
            Expanded(
              child: _BuyingPower(
                color: balancesCategoryColor(c, BalancesCategory.buyingPower),
                label: l10n.portfolioBuyingPower,
                hint: l10n.portfolioBuyingPowerHint,
                figure: buyingPower,
                open: split,
                onToggle: places.any((e) => e.footer.isNotEmpty)
                    ? null
                    : () => setState(() => _split = !_split),
              ),
            ),
            SizedBox(width: 16.w),
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
          ],
        ),
        // Where the cash sits, opened in place.
        AnimatedSize(
          duration: kuteReduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: split
              ? Padding(
                  key: const ValueKey('portfolio-balance-split'),
                  padding: EdgeInsets.only(top: 8.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (widget.action case final action?) ...[
          SizedBox(height: 16.h),
          action,
        ],
        SizedBox(height: 16.h),
        if (predictions != null || investing != null) ...[
          hairline,
          _InvestedRow(title: l10n.betInvested, figure: invested),
          if (predictions != null)
            venue(BalancesCategory.predictions, predictions),
          if (predictions != null && investing != null) ...[
            SizedBox(height: 4.h),
            hairline,
          ],
          if (investing != null) venue(BalancesCategory.investing, investing),
        ],
      ],
    );
  }

  Widget _wrap(BalancesPart part, Widget row) =>
      widget.wrap?.call(part, row) ?? row;
}

/// [rows] with the position list's hairlines between them.
List<Widget> _rowsWithHairlines(BuildContext context, List<Widget> rows) {
  final c = context.colors;
  return [
    for (var i = 0; i < rows.length; i++) ...[
      if (i > 0)
        Divider(
          color: context.isDark ? c.border : c.borderSubtle,
          height: 1,
          thickness: 0.5,
          indent: (kPortfolioRowImage + kPortfolioRowGap).w,
        ),
      rows[i],
    ],
  ];
}

/// The dot before a category's name.
const double _kDot = 8;

/// A venue's text starts after its dot and this gap; its rows and the
/// places under Buying power line up with it.
const double _kDotGap = 12;

/// The big figure: Buying power, the money that can be used now.
const double _kBigFigure = 34;

/// A live figure: a new value rolls the digits that changed; while it
/// refreshes (or is not known yet) it is dimmed with the skeleton's sweep.
class _Live extends StatelessWidget {
  const _Live({super.key, required this.figure, required this.style});

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
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerEnd,
        child: _Live(figure: figure, style: style),
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: _kDot.w,
        height: _kDot.w,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// A P&L beside a venue's value: "+$1.10" or "−$0.40" in the result
/// colour; nothing when it is under a cent. [money] writes the amount.
class BalancesPnlText extends StatelessWidget {
  const BalancesPnlText({super.key, required this.usd, required this.money});

  final double usd;
  final String Function(double usd) money;

  @override
  Widget build(BuildContext context) {
    if (!usd.isFinite || usd.abs() < kBalancesCentUsd) {
      return const SizedBox.shrink();
    }
    final up = usd > 0;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: 6.w),
      child: RollingFigure(
        key: const ValueKey('portfolio-balance-venue-pnl'),
        text: '${up ? '+' : '−'}${money(usd.abs())}',
        style: TextStyle(
          color: up ? AppColors.marketUp : AppColors.marketDown,
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          height: 1.25,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// The ring: one slice per non-empty category in its colour, "Total" and
/// the total in the hole. Only the track while a figure is unknown. Not a
/// control.
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
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  )),
              SizedBox(height: 1.h),
              // The hole is narrow: a long total scales down, never spills.
              FittedBox(
                key: const ValueKey('portfolio-balance-total'),
                fit: BoxFit.scaleDown,
                child: _Live(
                  figure: total,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
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

/// Buying power: the small dotted label, the big figure, and the hint with
/// its chevron, which opens where the cash sits ([onToggle]; null: held
/// open by a note).
class _BuyingPower extends StatelessWidget {
  const _BuyingPower({
    required this.color,
    required this.label,
    required this.hint,
    required this.figure,
    required this.open,
    required this.onToggle,
  });

  final Color color;
  final String label;
  final String hint;
  final BalancesFigure figure;
  final bool open;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final quiet = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.3,
    );
    return Column(
      key: const ValueKey('portfolio-balance-category-buyingPower'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _Dot(color: color),
            SizedBox(width: 8.w),
            Flexible(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: quiet),
            ),
          ],
        ),
        SizedBox(height: 6.h),
        Semantics(
          label: label,
          child: FittedBox(
            key:
                const ValueKey('portfolio-balance-category-buyingPower-amount'),
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: _Live(
              figure: figure,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: _kBigFigure.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.0,
                height: 1.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        SizedBox(height: 6.h),
        Semantics(
          button: onToggle != null,
          expanded: open,
          child: GestureDetector(
            key: const ValueKey('portfolio-balance-split-toggle'),
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(hint,
                      key: const ValueKey(
                          'portfolio-balance-category-buyingPower-line'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: quiet),
                ),
                if (onToggle != null) ...[
                  SizedBox(width: 2.w),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: kuteReduceMotion(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18.w, color: c.textTertiary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Invested: what both venues have at work, a bold row.
class _InvestedRow extends StatelessWidget {
  const _InvestedRow({required this.title, required this.figure});

  final String title;
  final BalancesFigure figure;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(
      color: c.textPrimary,
      fontSize: 17.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.25,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      container: true,
      label: '$title, ${figure.text}',
      excludeSemantics: true,
      child: Padding(
        key: const ValueKey('portfolio-balance-invested'),
        padding: EdgeInsets.only(top: 16.h, bottom: 4.h),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
            SizedBox(width: 12.w),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 210.w),
              child: _EndFigure(
                  key: const ValueKey('portfolio-balance-invested-amount'),
                  figure: figure,
                  style: style),
            ),
          ],
        ),
      ),
    );
  }
}

/// A venue's header: its dot, name and count, its value and P&L at the
/// end ("No open positions" in their place when nothing is held), what
/// open orders hold under it ([caption]).
class _VenueHeader extends StatelessWidget {
  const _VenueHeader({
    super.key,
    required this.category,
    required this.color,
    required this.title,
    required this.count,
    required this.figure,
    required this.pnl,
    required this.empty,
    required this.caption,
  });

  final BalancesCategory category;
  final Color color;
  final String title;
  final int? count;
  final BalancesFigure figure;
  final Widget? pnl;
  final String? empty;
  final String? caption;

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
    final titleStyle = AppTextStyles.settingsTitle(context)
        .copyWith(letterSpacing: -0.2, height: 1.25);
    final name = category.name;
    return Semantics(
      container: true,
      label: [
        title,
        if (count != null) '$count',
        empty ?? figure.text,
        if (caption != null) caption!,
      ].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.only(top: 14.h, bottom: 4.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _Dot(color: color),
                SizedBox(width: _kDotGap.w),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle),
                      ),
                      if (count case final n?) ...[
                        SizedBox(width: 8.w),
                        Text('$n',
                            key: ValueKey(
                                'portfolio-balance-category-$name-count'),
                            style: titleStyle.copyWith(
                                color: c.textTertiary,
                                fontWeight: FontWeight.w500,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 12.w),
                if (empty case final text?)
                  Text(text,
                      key: ValueKey('portfolio-balance-category-$name-line'),
                      maxLines: 1,
                      style: quiet)
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 210.w),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          _Live(
                            key: ValueKey(
                                'portfolio-balance-category-$name-amount'),
                            figure: figure,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              height: 1.25,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                          if (pnl case final p?) p,
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (caption case final text?) ...[
              SizedBox(height: 2.h),
              Padding(
                padding:
                    EdgeInsetsDirectional.only(start: (_kDot + _kDotGap).w),
                child: Text(text,
                    key: ValueKey('portfolio-balance-category-$name-caption'),
                    style: quiet.copyWith(color: c.textTertiary)),
              ),
            ],
          ],
        ),
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
            start: (_kDot + _kDotGap).w, top: 4.h, bottom: 4.h),
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
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 150.w),
                  child: _EndFigure(
                    key: ValueKey('portfolio-balance-${entry.id}-amount'),
                    figure: cash,
                    style: style,
                  ),
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
