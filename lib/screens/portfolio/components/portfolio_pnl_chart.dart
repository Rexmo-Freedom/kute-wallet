// lib/screens/portfolio/components/portfolio_pnl_chart.dart
//
// The profit and loss section of P&L Charts: on the spending account one
// chart for Investing and Predictions together (their series added,
// [PortfolioPerformance.combine]) or one venue's when its row is picked
// (portfolio_statistics.dart); on a Ledger the venue's own. Redone flat
// and confident (founder, 1 November 2026: "to look like good fintech",
// Robinhood and Revolut as they are now), top down:
//
//   * NO CARD around the chart on the Portfolio
//     ([PortfolioPnlChart.flat]): the header, the plot and the ranges on
//     the page background inside the 16 px gutters (the stats strip and
//     the venue rows under them are soft cards, below). A Ledger's
//     Statistics keeps the same content in its card, among its other
//     cards;
//   * the caption "Profit and loss" (13 sp, textSecondary), then the P&L
//     OVER THE RANGE picked as the figure (founder, 1 November 2026: an
//     all-time figure over "Past week" read as a contradiction;
//     [pnlRangeChange]: the line's end less the range's start, ALL the
//     all-time P&L), 34 sp w700 tabular, rolling, signed, in marketUp /
//     marketDown (textPrimary at zero), then the line naming the range
//     ("Past week"), after the percent only where a real base exists
//     ([PortfolioPnlChart.percentBaseUsd]; none today, a P&L series has
//     no base of its own, so never invented);
//   * the plot full-bleed to the gutters, 220 tall: [KuteTrendChart] as
//     it is (the thin line in the RESULT colour of the range,
//     [pnlResultColor]; the dashed hairline at the range's start; the
//     scrub) with the P&L split fill ([KuteTrendChart.zeroSplit]: marketUp
//     at 8% above zero, marketDown at 8% below, a faint zero line when the
//     series crosses it);
//   * the range row (1W 1M 3M 1Y ALL, the small white pill) centred, 16
//     px under the plot, 1M to start and remembered for the session;
//     picking a range morphs the line;
//   * SCRUB: a horizontal drag (or a long press, then slide) puts the P&L
//     under the finger since the range's start in the figure (ALL: the
//     P&L at that point) and its moment in the line under it ("Oct 16
//     14:00"); release puts the range's P&L back;
//   * the STATS STRIP ([PortfolioPnlChart.stats], [PnlStatsFigures]) in
//     ONE soft card (founder, 1 November 2026: the home Activity list's
//     card, PortfolioCardList in position_rows.dart, its rows' 16 / 13
//     padding): one row, three equal columns, 12 sp labels in
//     textSecondary over 15 w600 figures: All time realised, All time
//     unrealised, Win rate. They do NOT follow the range (the providers
//     give the realised P&L and the open P&L as totals), so their labels
//     say all time.
//     A figure no provider gives is not a dash: its column is left out
//     (Win rate needs closed-trade counts, which only Predictions has);
//   * "By venue" (13 sp, textSecondary) and the venue rows
//     ([PortfolioPnlChart.footer], [PnlVenueRow]) in ONE soft card the
//     same way, the Portfolio's one row language (position_rows.dart; the
//     Portfolio section's position rows are drawn the same): the venue's
//     logo (32), its name (15 w500) over where the money is (13), a 48×20
//     sparkline of its P&L over the range, and its P&L now (realised plus
//     open, 15 w600) in its colour with its change over the range (12)
//     under it; the card's inset hairline between rows. A row tapped
//     charts that venue alone (portfolio_statistics.dart);
//   * NO HISTORY (nothing traded or predicted yet, every point zero): no
//     chart. On the Portfolio the sections' one empty state
//     (PortfolioSectionEmpty: the hero Sal, "No P&L yet"); on a Ledger its
//     card's compact Sal with the chart's caption.
//
// [PortfolioPnlSkeleton] is the section's shape while a read is genuinely
// on its way: never a blank frame.
//
// With balances hidden the figures are dots, as on the home header.
//
// Analytics: `portfolio_performance_chart_scrubbed` {venue}, once per
// scrub gesture; venue is the chart's [PortfolioPnlChart.eventVenue] when
// given (the spending account's series: `all`, `hyperliquid` or
// `polymarket`), else `trading`, `predictions`, or `all` for a combined
// chart. Ranges send nothing, as on the Balance charts.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show
        PortfolioCardList,
        PortfolioRowInset,
        kPortfolioRowGap,
        kPortfolioRowImage,
        portfolioRowChangeStyle,
        portfolioRowFigureStyle,
        portfolioRowSubStyle,
        portfolioRowTitleStyle;
import 'package:kute/screens/portfolio/components/balances_overview.dart'
    show balancesFlatSectionTitle, kBalancesTitleGap;
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart';
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/charts/kute_trend_window.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The plot's height on the P&L section.
const double kPnlChartPlotHeight = 220;

/// The range row's width, centred under the plot.
const double kPnlRangeRowWidth = 280;

/// A venue row's sparkline.
const Size kPnlSparklineSize = Size(48, 20);

/// The line's colour: the result over the range, [change] being the P&L
/// at the range's end less its start. Red when it fell, green when it
/// rose, the text colour when it did not move.
Color pnlResultColor(AppColorsExtension c, double change) => change > 0
    ? AppColors.marketUp
    : change < 0
        ? AppColors.marketDown
        : c.textPrimary;

/// The range the P&L chart shows, for the rest of the session: the past
/// month to start. One choice for every series (the toggle keeps it).
final pnlChartRangeProvider =
    StateProvider<BalanceRange>((ref) => BalanceRange.month);

/// The venue picked in "By venue" on the spending account's P&L Charts
/// (portfolio_statistics.dart): the chart draws it alone and the Portfolio
/// screen's ring above shows it (balances_overview.dart). Null: All.
/// Cleared once nothing watches it (the section left).
final pnlChartVenueProvider =
    StateProvider.autoDispose<PortfolioPerformanceVenue?>((ref) => null);

/// The P&L over [range] of a window's [values] (oldest first): the line's
/// end (or [at], a point under the finger) less the range's start; for
/// ALL the line's own value, the P&L since the account began. Null with
/// no points.
double? pnlRangeChange(List<double> values, BalanceRange range,
    {double? at}) {
  if (values.isEmpty) return null;
  final end = at ?? values.last;
  return range == BalanceRange.all ? end : end - values.first;
}

/// [data]'s P&L over [range] ending [now] ([pnlRangeChange]); null with
/// no points.
double? pnlVenueRangeChange(
    PortfolioPerformance data, BalanceRange range, DateTime now) {
  final series = pnlSeries(data, now);
  return pnlRangeChange(
      kuteTrendWindow(series, series.spanFor(range)).values, range);
}

/// The stats strip's figures for the series drawn. Null is not given by
/// any provider: that column is left out, never a dash or a zero.
@immutable
class PnlStatsFigures {
  const PnlStatsFigures({this.realisedUsd, this.unrealisedUsd, this.winRate});

  /// What closed positions made, net of fees.
  final double? realisedUsd;

  /// What the open positions stand at.
  final double? unrealisedUsd;

  /// The closed positions that made money over every closed one, 0 to 1;
  /// only where the providers count closed trades (Predictions).
  final double? winRate;

  bool get isEmpty =>
      realisedUsd == null && unrealisedUsd == null && winRate == null;
}

class PortfolioPnlChart extends ConsumerStatefulWidget {
  const PortfolioPnlChart({
    super.key,
    required this.venue,
    required this.data,
    this.now,
    this.footer,
    this.stats,
    this.flat = false,
    this.percentBaseUsd,
    this.eventVenue,
    this.venueLines = const [],
  });

  /// The venue charted; null for Investing and Predictions together (the
  /// spending account's P&L Charts), `all` in the events.
  final PortfolioPerformanceVenue? venue;

  /// The P&L series. With no observations (or none off zero) the chart is
  /// its no-history state.
  final PortfolioPerformance data;

  /// The moment the line ends on; now unless a test pins it.
  final DateTime? now;

  /// The venue rows under "By venue" ([PnlVenueRow]s), which pick the
  /// series drawn.
  final Widget? footer;

  /// The stats strip under the ranges; null or empty draws none.
  final PnlStatsFigures? stats;

  /// On the page itself, no card (the Portfolio); a Ledger's Statistics
  /// keeps its card.
  final bool flat;

  /// What the change line's percent is taken of; null (or not above zero)
  /// writes no percent. No provider gives one today.
  final double? percentBaseUsd;

  /// The `venue` the scrub event sends; [venue]'s name (or `all`) when
  /// null.
  final String? eventVenue;

  /// One extra line per venue, in the venue's colour, over the same range.
  final List<(Color, PortfolioPerformance)> venueLines;

  @override
  ConsumerState<PortfolioPnlChart> createState() => _PortfolioPnlChartState();
}

class _PortfolioPnlChartState extends ConsumerState<PortfolioPnlChart> {
  /// The point under the finger; null at rest.
  KuteTrendPoint? _scrub;

  String get _venueName => widget.eventVenue ?? widget.venue?.name ?? 'all';

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final c = context.colors;
    final l10n = context.l10n;
    final range = ref.watch(pnlChartRangeProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    String money(double value) =>
        !visible ? '••••••' : formatPolyAmount(ref, value.abs());
    String signed(double value) =>
        !visible ? '••••••' : '${kuteChangeSign(value)}${money(value)}';

    final now = widget.now ?? DateTime.now();
    final series = pnlSeries(data, now);
    final hasHistory = series.values.any((v) => v != 0);
    final flat = widget.flat;

    if (!hasHistory) {
      return _frame(
        context,
        flat
            // The sections' one empty state, where the empty P&L section
            // puts it (the page's 8 above it, then 14).
            ? Padding(
                padding: EdgeInsets.only(top: 14.h),
                child: PortfolioSectionEmpty(
                    key: const ValueKey('statistics-pnl-no-history'),
                    title: l10n.pnlNoHistoryTitle,
                    tagline: PortfolioSectionTagline.pnl),
              )
            : Padding(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: NoActivityState(
                  key: const ValueKey('statistics-pnl-no-history'),
                  title: l10n.pnlNoHistoryTitle,
                  subtitle: l10n.pnlChartNoHistory,
                  cycles: 3,
                  compact: true,
                ),
              ),
      );
    }

    final span = series.spanFor(range);
    final shown = kuteTrendWindow(series, span);
    final values = shown.values;
    final times = shown.times;
    final scrub = _scrub;
    final scrubbing = scrub != null && scrub.index < values.length;

    final locale = kuteChartLocale(context);
    // On daily (or coarser) buckets a point at midnight closes the day
    // before; finer buckets say when in the day.
    final daily = series.strideFor(span) * series.cellMinutes >= 1440;
    String timeOf(DateTime t) {
      final d = daily && t.hour == 0 && t.minute == 0
          ? t.subtract(const Duration(minutes: 1))
          : t;
      return daily ? kuteChartDay(d, locale) : kuteChartDayTime(t, locale);
    }

    // The result over the range: the line's colour.
    final lineColor = values.isEmpty
        ? c.textPrimary
        : pnlResultColor(c, values.last - values.first);

    // The figure: the P&L over the range picked, or since the range's
    // start to the point under the finger (ALL: the P&L at that point).
    final headline = pnlRangeChange(values, range,
            at: scrubbing ? scrub.value : null) ??
        series.values.last;
    final headlineColor =
        !visible ? c.textPrimary : pnlResultColor(c, headline);

    final quiet = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // The figure leads, scaled down rather than cut on a narrow phone or
    // under large text.
    final figure = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: RollingNumberText(
        key: const ValueKey('statistics-pnl-headline'),
        text: signed(headline),
        duration: Duration(milliseconds: scrubbing ? 120 : 350),
        dimColor: c.textTertiary,
        style: AppTextStyles.balance(context).copyWith(
          color: headlineColor,
          fontSize: 34.sp,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    // The line under the figure: the range the figure is over ("Past
    // week"), or the moment under the finger, after the figure's percent
    // of a real base (none today).
    Widget changeLine() {
      if (values.length < 2) return const SizedBox.shrink();
      final tail = scrubbing
          ? timeOf(scrub.time ?? times.last)
          : kuteTrendPeriodLabel(l10n, range);
      final color = headline > 0
          ? AppColors.marketUp
          : headline < 0
              ? AppColors.marketDown
              : c.textSecondary;
      final base = widget.percentBaseUsd;
      final percent = visible && base != null && base > 0 && headline != 0
          ? kuteSignedPercent(headline / base * 100)
          : null;
      return Padding(
        padding: EdgeInsets.only(top: 6.h),
        child: Text.rich(
          TextSpan(children: [
            if (percent != null) ...[
              TextSpan(
                text: percent,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: ' · '),
            ],
            TextSpan(text: tail),
          ]),
          key: const ValueKey('statistics-pnl-header'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: quiet,
        ),
      );
    }

    final header = Column(
      key: const ValueKey('statistics-pnl-head'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.portfolioProfitLoss,
            key: const ValueKey('statistics-pnl-caption'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // The Portfolio sections' one title style ("Investing · 2").
            style: balancesFlatSectionTitle(context)),
        SizedBox(height: 4.h),
        figure,
        changeLine(),
      ],
    );

    final chart = KuteTrendChart(
      key: const ValueKey('statistics-pnl-chart'),
      values: values,
      times: times,
      lineColor: lineColor,
      zeroSplit: true,
      lines: [
        for (final (color, perf) in widget.venueLines)
          KuteTrendLine(
            values: kuteTrendWindow(pnlSeries(perf, now), span).values,
            color: color,
          ),
      ],
      height: kPnlChartPlotHeight.h,
      onScrub: (p) => setState(() => _scrub = p),
      // Once per scrub gesture.
      onScrubStart: () => TrackingService.track(
          'portfolio_performance_chart_scrubbed',
          params: {'venue': _venueName}),
    );

    final ranges = Center(
      child: SizedBox(
        width: kPnlRangeRowWidth.w,
        child: KuteChartRangeRow(
          key: const ValueKey('trend-chart-ranges'),
          labels: [for (final r in BalanceRange.values) r.label],
          selectedIndex: range.index,
          onSelected: (i) => ref.read(pnlChartRangeProvider.notifier).state =
              BalanceRange.values[i],
        ),
      ),
    );

    final stats = widget.stats;
    final footer = widget.footer;
    return _frame(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flat: the caption where the Portfolio section's title sits.
          SizedBox(height: flat ? 14.h : 16.h),
          header,
          SizedBox(height: 16.h),
          chart,
          SizedBox(height: kKuteTrendRangeGap.h),
          ranges,
          if (stats != null && !stats.isEmpty) ...[
            SizedBox(height: 24.h),
            // On the Portfolio, ONE soft card (see the file header).
            if (flat)
              PortfolioCardList(
                key: const ValueKey('statistics-pnl-stats-card'),
                rows: [
                  Builder(
                    builder: (context) => Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: PortfolioRowInset.of(context),
                          vertical: PortfolioRowInset.verticalOf(context)),
                      child: PnlStatsStrip(stats: stats),
                    ),
                  ),
                ],
              )
            else
              PnlStatsStrip(stats: stats),
          ],
          if (footer != null) ...[
            SizedBox(height: 28.h),
            Text(l10n.pnlByVenue,
                key: const ValueKey('statistics-pnl-by-venue'),
                style: balancesFlatSectionTitle(context)),
            SizedBox(height: kBalancesTitleGap.h),
            footer,
          ],
          SizedBox(height: flat ? 8.h : 16.h),
        ],
      ),
    );
  }

  /// The page itself (flat) or a Ledger's card, with its insets.
  Widget _frame(BuildContext context, Widget child) {
    if (widget.flat) {
      return KeyedSubtree(
          key: const ValueKey('statistics-pnl-section'), child: child);
    }
    return Container(
      key: const ValueKey('statistics-pnl-card'),
      clipBehavior: Clip.antiAlias,
      decoration: AppDecorations.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: child,
    );
  }
}

/// The stats strip (see the file header): one row of equal thirds, a
/// 12 sp label in textSecondary over a 15 w600 figure; a figure that is
/// not given leaves its column out.
class PnlStatsStrip extends ConsumerWidget {
  const PnlStatsStrip({super.key, required this.stats});

  final PnlStatsFigures stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    String signed(double v) => visible
        ? '${kuteChangeSign(v)}${formatPolyAmount(ref, v.abs())}'
        : '••••••';
    Color colorOf(double v) => visible ? pnlResultColor(c, v) : c.textPrimary;
    final columns = <(String, String, String, Color)>[
      // All time: the providers give these as totals, not over a range.
      if (stats.realisedUsd case final v?)
        ('realised', l10n.pnlStatRealisedAllTime, signed(v), colorOf(v)),
      if (stats.unrealisedUsd case final v?)
        ('unrealised', l10n.pnlStatUnrealisedAllTime, signed(v), colorOf(v)),
      if (stats.winRate case final v?)
        (
          'win-rate',
          l10n.pnlStatWinRate,
          '${(v * 100).round()}%',
          c.textPrimary
        ),
    ];
    return Row(
      key: const ValueKey('statistics-pnl-stats'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (id, label, figure, color) in columns)
          Expanded(
            key: ValueKey('statistics-pnl-stat-$id'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500)),
                SizedBox(height: 4.h),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(figure,
                      maxLines: 1,
                      style: TextStyle(
                          color: color,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ],
            ),
          ),
        // Fewer than three: the columns keep their thirds.
        for (var i = columns.length; i < 3; i++) const Spacer(),
      ],
    );
  }
}

/// One venue's row under "By venue", in the Portfolio's one row language
/// (position_rows.dart: the logo 32, the name 15 w500, [subtitle] 13 under
/// it, the figure 15 w600 at the end with its change 12 under it, the
/// [PortfolioRowInset] padding, the soft card's inset where a
/// [PortfolioCardList] draws it): the venue's P&L now
/// (realised plus open) in its colour, its change over the range picked
/// under it, and the sparkline of [data] over that range before them.
/// [quiet] (the venue's "No … yet") stands as the line under the name and
/// leaves the figure out. [dimmed] while the other venue is charted;
/// [onTap] picks it (null: nothing to pick).
class PnlVenueRow extends ConsumerWidget {
  const PnlVenueRow({
    super.key,
    required this.logoAsset,
    required this.name,
    required this.subtitle,
    required this.data,
    required this.pnlUsd,
    this.quiet,
    this.dimmed = false,
    this.selected = false,
    this.onTap,
    this.now,
  });

  final String logoAsset;
  final String name;

  /// The line under the name (where the money is: "Polymarket").
  final String subtitle;
  final PortfolioPerformance data;

  /// The venue's P&L now; null: not known (a dash).
  final double? pnlUsd;

  /// The venue's "No … yet": the line under the name, no figure.
  final String? quiet;
  final bool dimmed;
  final bool selected;
  final VoidCallback? onTap;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final range = ref.watch(pnlChartRangeProvider);
    final pnl = pnlUsd;
    final quietText = quiet;
    String money(double v) =>
        visible ? formatPolyAmount(ref, v.abs()) : '••••••';

    Widget? end;
    if (quietText == null) {
      final series = pnlSeries(data, now ?? DateTime.now());
      final values = kuteTrendWindow(series, series.spanFor(range)).values;
      final delta = values.length < 2 ? null : values.last - values.first;
      final figure = pnl == null
          ? '—'
          : visible
              ? '${kuteChangeSign(pnl)}${money(pnl)}'
              : '••••••';
      final changeColor = delta == null || !visible
          ? c.textSecondary
          : delta == 0
              ? c.textSecondary
              : pnlResultColor(c, delta);
      end = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (values.length >= 2) ...[
            PnlSparkline(
                values: values,
                color: pnlResultColor(c, values.last - values.first)),
            SizedBox(width: 12.w),
          ],
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(figure,
                      key: const ValueKey('pnl-venue-figure'),
                      maxLines: 1,
                      style: portfolioRowFigureStyle(context,
                          color: pnl == null || !visible
                              ? c.textPrimary
                              : pnlResultColor(c, pnl))),
                  if (delta != null) ...[
                    SizedBox(height: 2.h),
                    Text(
                        !visible
                            ? '••••••'
                            : delta == 0
                                ? context.l10n.chartNoChange
                                : '${kuteTrendArrow(delta)}${money(delta)}',
                        key: const ValueKey('pnl-venue-change'),
                        maxLines: 1,
                        style: portfolioRowChangeStyle(changeColor)),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    final row = Padding(
      padding: EdgeInsets.symmetric(
          horizontal: PortfolioRowInset.of(context),
          vertical: PortfolioRowInset.verticalOf(context)),
      child: Row(
        children: [
          SizedBox.square(
            dimension: kPortfolioRowImage.w,
            child: SvgPicture.asset(logoAsset,
                width: kPortfolioRowImage.w,
                height: kPortfolioRowImage.w,
                fit: BoxFit.contain),
          ),
          SizedBox(width: kPortfolioRowGap.w),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: portfolioRowTitleStyle(context)),
                SizedBox(height: 2.h),
                Text(quietText ?? subtitle,
                    key: const ValueKey('pnl-venue-subtitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: portfolioRowSubStyle(context)),
              ],
            ),
          ),
          if (end != null) ...[
            SizedBox(width: 8.w),
            // The figure at the row's end, whatever its width.
            Expanded(
                flex: 3,
                child: Align(alignment: Alignment.centerRight, child: end)),
          ],
        ],
      ),
    );
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final body = AnimatedOpacity(
      opacity: dimmed ? 0.45 : 1,
      duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
      child: row,
    );
    final tap = onTap;
    if (tap == null) return body;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
          behavior: HitTestBehavior.opaque, onTap: tap, child: body),
    );
  }
}

/// A venue's P&L over the range, [kPnlSparklineSize]: the monotone line
/// alone, 1.5 px in its result colour, no fill, no reference.
class PnlSparkline extends StatelessWidget {
  const PnlSparkline({super.key, required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        key: const ValueKey('pnl-sparkline'),
        size: Size(kPnlSparklineSize.width.w, kPnlSparklineSize.height.h),
        painter: _SparklinePainter(values, color),
      );
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n < 2) return;
    var lo = values.first, hi = values.first;
    for (final v in values) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    const inset = 1.5;
    final h = size.height - inset * 2;
    final pts = [
      for (var i = 0; i < n; i++)
        Offset(i / (n - 1) * size.width,
            inset + h - (values[i] - lo) / (hi - lo) * h)
    ];
    canvas.drawPath(kuteMonotonePath(pts), kuteStrokePaint(color, width: 1.5));
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      !identical(old.values, values) || old.color != color;
}

/// The P&L section's shape while a read is genuinely on its way (never a
/// blank frame): the caption, the figure and the change line as bars, the
/// plot's block at the plot's own height and the range row under it, so
/// nothing moves when the chart lands.
class PortfolioPnlSkeleton extends StatelessWidget {
  const PortfolioPnlSkeleton({super.key});

  @override
  Widget build(BuildContext context) => KuteSkeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 16.h),
            SkeletonBar(96.w, 13.sp),
            SizedBox(height: 8.h),
            SkeletonBar(150.w, 34.sp, radius: 8.r),
            SizedBox(height: 8.h),
            SkeletonBar(140.w, 13.sp),
            SizedBox(height: 16.h),
            SkeletonBar(double.infinity, kPnlChartPlotHeight.h, radius: 12.r),
            SizedBox(height: kKuteTrendRangeGap.h),
            Center(
                child: SkeletonBar(kPnlRangeRowWidth.w, 28.h, radius: 14.h)),
          ],
        ),
      );
}
