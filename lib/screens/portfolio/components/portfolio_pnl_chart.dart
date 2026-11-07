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
//   * THE PORTFOLIO SCREEN'S P&L SECTION ([PnlBreakdown]; founder, 5
//     November 2026: "here should be square cards") draws the venues and
//     the all-time stats as the app's squares instead (the Positions and
//     Activity squares: the grouped card's ground, 14 padding): "By venue"
//     as two big squares side by side ([PnlVenueSquare]: the logo
//     top-left, the change top-right in its colour, the name and where the
//     money is quiet, the venue's P&L over the hero's range ONCE at 22 sp,
//     its sparkline across the bottom), and "All time" as compact tiles in
//     one row ([PnlStatTiles]: Realised, Unrealised, Win rate where
//     counted; thirds, halves or one across, never an orphan half). A
//     square tapped picks its venue for the hero above
//     ([portfolioPnlVenueProvider]: the selected outline on it, the other
//     dimmed, the tiles following it); tapped again, both venues;
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
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/models/open_pnl_history.dart' show openPnlRangeShown;
import 'package:kute/providers/open_pnl_history_provider.dart'
    show pnlRangesProvider, pnlWindowProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show
        PortfolioCardList,
        PortfolioRowInset,
        kPortfolioRowGap,
        kPortfolioRowImage,
        kPortfolioSquareIcon,
        portfolioRowChangeStyle,
        portfolioRowFigureStyle,
        portfolioRowSubStyle,
        portfolioRowTitleStyle;
import 'package:kute/screens/portfolio/components/balances_overview.dart'
    show balancesFlatSectionTitle, kBalancesGroupGap, kBalancesTitleGap;
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/portfolio/portfolio_filters.dart'
    show portfolioVenuesProvider;
import 'package:kute/screens/shared/animations/premium_group_container.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart';
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/charts/kute_trend_window.dart';
import 'package:kute/screens/shared/kute_motion.dart'
    show KutePressable, kuteMotion;
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show kActivitySquareHeight;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The plot's height on the P&L section.
const double kPnlChartPlotHeight = 220;

/// The range row's width, centred under the plot.
const double kPnlRangeRowWidth = 280;

/// A venue row's sparkline.
const Size kPnlSparklineSize = Size(48, 20);

/// A venue square's and a stat tile's inner padding (the Positions
/// squares'), the gap over a square's sparkline and its height, and the
/// gap between squares and between tiles (ActivitySquareGrid's), design
/// units.
const double kPnlSquarePad = 14;
const double kPnlSquareSparkGap = 10;
const double kPnlSquareSparkHeight = 28;
const double kPnlSquareGap = 10;

/// A venue square's pick: how long its outline and its neighbour's dim
/// take, and how far the neighbour steps back.
const Duration kPnlPickDuration = Duration(milliseconds: 150);
const double kPnlDimmedOpacity = 0.55;

/// The line's colour: the result over the range, [change] being the P&L
/// at the range's end less its start. Red when it fell, green when it
/// rose, the text colour when it did not move.
Color pnlResultColor(AppColorsExtension c, double change) => change > 0
    ? AppColors.marketUp
    : change < 0
        ? AppColors.marketDown
        : c.textPrimary;

/// The range the P&L charts show, for the rest of the session: the past
/// month to start. One choice for every series (the toggle keeps it), the
/// Portfolio screen's hero chart, its P&L section's venue rows and the
/// "Share P&L" card alike.
final pnlChartRangeProvider =
    StateProvider<BalanceRange>((ref) => BalanceRange.month);

/// The range the Portfolio screen's P&L engine draws for [venue]'s line
/// (null: both venues; with one venue on, its own line, as the hero
/// draws it): the one picked ([pnlChartRangeProvider]) when the line
/// offers it ([pnlRangesProvider]: the fixed ranges shorter than its
/// history, then ALL), else ALL, the whole line (founder, 7 November
/// 2026: a range reaching back past the history drew a long flat line,
/// "use ALL like it was before"). The hero, its P&L section's venue
/// squares and the "Share P&L" card alike, so the pill lit, the line's
/// words and the card agree. The pick itself is kept: a longer history
/// (another venue picked) shows it again.
final pnlShownRangeProvider = Provider.autoDispose
    .family<BalanceRange, PortfolioPerformanceVenue?>((ref, venue) {
  final venues = ref.watch(portfolioVenuesProvider);
  final line = venue ??
      (venues.trading == venues.predictions
          ? null
          : venues.trading
              ? PortfolioPerformanceVenue.trading
              : PortfolioPerformanceVenue.predictions);
  return openPnlRangeShown(
      ref.watch(pnlChartRangeProvider), ref.watch(pnlRangesProvider(line)));
});

/// The venue picked in "By venue" under the older Portfolio page's P&L
/// chart (portfolio_statistics.dart, OpenInvestmentsScreen): the chart
/// draws it alone. Null: All. Cleared once nothing watches it. The
/// Portfolio screen keeps its own pick ([portfolioPnlVenueProvider]).
final pnlChartVenueProvider =
    StateProvider.autoDispose<PortfolioPerformanceVenue?>((ref) => null);

/// The venue square picked on the Portfolio screen's P&L section
/// (founder, 5 November 2026: "selecting here must change the top
/// graph"): the hero's figure, its P&L line and its chart show that venue
/// alone (components/portfolio_hero.dart), the all-time tiles follow it
/// and "Share P&L" shares its card. Null: both venues. Back to null when
/// the person leaves the P&L section (investments_portfolio.dart) or the
/// screen (nothing watches it then).
final portfolioPnlVenueProvider =
    StateProvider.autoDispose<PortfolioPerformanceVenue?>((ref) => null);

/// A venue as the P&L events name it; null is the account as a whole.
String pnlEventVenue(PortfolioPerformanceVenue? venue) => switch (venue) {
      null => 'all',
      PortfolioPerformanceVenue.trading => 'hyperliquid',
      PortfolioPerformanceVenue.predictions => 'polymarket',
    };

/// The Portfolio screen's venue pick ([portfolioPnlVenueProvider]) set to
/// [next] (null: both venues again), from a venue square or the hero's
/// "All" chip: a selection click and `portfolio_statistics_venue_toggled`
/// {venue: all | hyperliquid | polymarket}, the event the older page's
/// venue rows send. Nothing when [next] is already the pick.
void portfolioPickPnlVenue(WidgetRef ref, PortfolioPerformanceVenue? next) {
  final notifier = ref.read(portfolioPnlVenueProvider.notifier);
  if (notifier.state == next) return;
  HapticFeedback.selectionClick();
  TrackingService.track('portfolio_statistics_venue_toggled',
      params: {'venue': pnlEventVenue(next)});
  notifier.state = next;
}

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
  /// The point under the finger; null at rest. A notifier, not state: a
  /// scrub frame rebuilds the figure and the line under it alone (the
  /// plot draws its own crosshair), never the section.
  final _scrub = ValueNotifier<KuteTrendPoint?>(null);

  @override
  void dispose() {
    _scrub.dispose();
    super.dispose();
  }

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

    final quiet = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // The figure leads, scaled down rather than cut on a narrow phone or
    // under large text. It is the P&L over the range picked, or since the
    // range's start to the point under the finger (ALL: the P&L at that
    // point).
    Widget figure(bool scrubbing, double headline) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: RollingNumberText(
        key: const ValueKey('statistics-pnl-headline'),
        text: signed(headline),
        duration: Duration(milliseconds: scrubbing ? 120 : 350),
        dimColor: c.textTertiary,
        style: AppTextStyles.balance(context).copyWith(
          color: !visible ? c.textPrimary : pnlResultColor(c, headline),
          fontSize: 34.sp,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    // The line under the figure: the range the figure is over ("Past
    // week"), or the moment under the finger, after the figure's percent
    // of a real base (none today).
    Widget changeLine(KuteTrendPoint? scrub, double headline) {
      if (values.length < 2) return const SizedBox.shrink();
      final tail = scrub != null
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
        ValueListenableBuilder<KuteTrendPoint?>(
          valueListenable: _scrub,
          builder: (context, point, _) {
            final scrub =
                point != null && point.index < values.length ? point : null;
            final headline =
                pnlRangeChange(values, range, at: scrub?.value) ??
                    series.values.last;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                figure(scrub != null, headline),
                changeLine(scrub, headline),
              ],
            );
          },
        ),
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
      onScrub: (p) => _scrub.value = p,
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

/// One figure of the stats: its key ([id], `statistics-pnl-stat-<id>`),
/// its label, the figure as written and its colour.
typedef PnlStat = ({String id, String label, String figure, Color color});

/// The stats [stats] gives, in order (Realised, Unrealised, Win rate), a
/// figure no provider gives left out. [allTime]: the labels say all time
/// themselves ("All time realised"); false under an "All time" title of
/// their own ([PnlBreakdown]). Masked with balances hidden.
List<PnlStat> pnlStats(BuildContext context, WidgetRef ref,
    PnlStatsFigures stats,
    {required bool allTime}) {
  final c = context.colors;
  final l10n = context.l10n;
  final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
  String signed(double v) => visible
      ? '${kuteChangeSign(v)}${formatPolyAmount(ref, v.abs())}'
      : '••••••';
  Color colorOf(double v) => visible ? pnlResultColor(c, v) : c.textPrimary;
  return [
    // All time: the providers give these as totals, not over a range.
    if (stats.realisedUsd case final v?)
      (
        id: 'realised',
        label: allTime ? l10n.pnlStatRealisedAllTime : l10n.pnlStatRealised,
        figure: signed(v),
        color: colorOf(v)
      ),
    if (stats.unrealisedUsd case final v?)
      (
        id: 'unrealised',
        label:
            allTime ? l10n.pnlStatUnrealisedAllTime : l10n.pnlStatUnrealised,
        figure: signed(v),
        color: colorOf(v)
      ),
    if (stats.winRate case final v?)
      (
        id: 'win-rate',
        label: l10n.pnlStatWinRate,
        figure: '${(v * 100).round()}%',
        color: c.textPrimary
      ),
  ];
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
    final columns = pnlStats(context, ref, stats, allTime: true);
    return Row(
      key: const ValueKey('statistics-pnl-stats'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in columns)
          Expanded(
            key: ValueKey('statistics-pnl-stat-${s.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.label,
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
                  child: Text(s.figure,
                      maxLines: 1,
                      style: TextStyle(
                          color: s.color,
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

/// The Portfolio screen's P&L section (founder, 4 November 2026: the one
/// chart is the hero's, components/portfolio_hero.dart; 5 November 2026:
/// "here should be square cards"): "By venue" over the venue squares
/// ([venues]: [PnlVenueSquare]s side by side, each venue's P&L over the
/// hero's range with its sparkline), then "All time" over the stats as
/// compact square tiles in one row ([PnlStatTiles]: Realised, Unrealised,
/// Win rate where a provider counts closed trades; a figure no provider
/// gives leaves its tile out). The section's first title sits
/// [kPortfolioSectionEmptyTop] under the strip, where the other sections
/// start.
class PnlBreakdown extends StatelessWidget {
  const PnlBreakdown({super.key, required this.venues, required this.stats});

  final Widget venues;
  final PnlStatsFigures stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: const ValueKey('statistics-pnl-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The section's list starts 4 under the strip.
        SizedBox(height: (kPortfolioSectionEmptyTop - 4).h),
        Text(l10n.pnlByVenue,
            key: const ValueKey('statistics-pnl-by-venue'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: balancesFlatSectionTitle(context)),
        SizedBox(height: kBalancesTitleGap.h),
        venues,
        if (!stats.isEmpty) ...[
          SizedBox(height: kBalancesGroupGap.h),
          Text(l10n.portfolioAllTime,
              key: const ValueKey('statistics-pnl-all-time'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: balancesFlatSectionTitle(context)),
          SizedBox(height: kBalancesTitleGap.h),
          PnlStatTiles(
              key: const ValueKey('statistics-pnl-stats-card'), stats: stats),
        ],
      ],
    );
  }
}

/// A venue square's height: its content at the viewer's text size (the
/// logo row, the name and the line under it, the P&L, the sparkline), at
/// least [kActivitySquareHeight]. The same for every venue, so squares
/// side by side line up whatever each shows.
double pnlVenueSquareHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  final content = kPnlSquarePad.w * 2 +
      kPortfolioSquareIcon.w +
      10.w +
      scaler.scale(13.sp) * 1.25 +
      2.h +
      scaler.scale(12.sp) * 1.3 +
      4.h +
      scaler.scale(22.sp) * 1.2 +
      kPnlSquareSparkGap.h +
      kPnlSquareSparkHeight.h +
      // A pixel of slack for rounding.
      2;
  final least = kActivitySquareHeight.w;
  return content > least ? content : least;
}

/// One venue under "By venue" on the Portfolio screen as a big square (the
/// Positions squares' shape, position_rows.dart: the grouped card's
/// ground, [kPnlSquarePad] padding, [pnlVenueSquareHeight] tall):
///
///   * the venue's logo ([kPortfolioSquareIcon]) top-left;
///   * top-right the change in its colour: "▲ 12.3%" of [percentBaseUsd]
///     where a real base is given (none today: a P&L series has no base of
///     its own, so none is invented), else the arrow and the range the
///     figure is over ("▲ Past month"), never the amount a second time;
///   * the venue's name quiet (13) over where the money is (12, tertiary);
///   * the venue's P&L over the hero's range as the hero shows it
///     ([pnlShownRangeProvider], [pnlRangeChange]: the line's end less the
///     range's start, ALL the P&L now) ONCE, 22 sp w700 tabular, signed,
///     in its colour;
///   * its sparkline across the bottom ([PnlSparkline.wide]).
///
/// [quiet] (the venue's "No … yet") stands as the line under the name and
/// leaves the figure, the change and the sparkline out. With balances
/// hidden the figure is dots and nothing says which way it went. [onTap]
/// (null: nothing to pick) taps the whole square on the press spring.
///
/// PICKED (the Portfolio screen's P&L, founder 5 November 2026: the hero
/// shows the venue picked): [selected] draws the app's selected outline
/// over the square (1.5 in the call-to-action colour, as a picked
/// Portfolio Builder card; easing in over 150 ms), [dimmed] (the other
/// venue picked) takes it to 55 % opacity. Screen readers hear a button,
/// selected or not.
class PnlVenueSquare extends ConsumerWidget {
  const PnlVenueSquare({
    super.key,
    required this.logoAsset,
    required this.name,
    required this.subtitle,
    required this.data,
    this.quiet,
    this.percentBaseUsd,
    this.onTap,
    this.selected = false,
    this.dimmed = false,
    this.now,
    this.venue,
  });

  /// The venue the square is (the Portfolio screen's P&L): its figure and
  /// sparkline from the whole P&L engine over the hero's range as the hero
  /// shows it ([pnlShownRangeProvider]), the hero's own line when the
  /// square is picked ([pnlWindowProvider], its last point the venue's
  /// P&L now); null, or while the engine is read: the venue's published
  /// line ([pnlSeries]).
  final PortfolioPerformanceVenue? venue;

  /// The venue the hero shows alone: the selected outline.
  final bool selected;

  /// The other venue is picked: the square steps back.
  final bool dimmed;

  final String logoAsset;
  final String name;

  /// Where the money is ("Polymarket").
  final String subtitle;
  final PortfolioPerformance data;

  /// The venue's "No … yet": the line under the name, no figure.
  final String? quiet;

  /// What the change's percent is taken of; null (or not above zero)
  /// writes the range instead. No provider gives one today.
  final double? percentBaseUsd;
  final VoidCallback? onTap;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    // On the Portfolio screen the hero's range as the hero shows it (its
    // pill lit); else the range picked.
    final range = venue != null
        ? ref.watch(
            pnlShownRangeProvider(ref.watch(portfolioPnlVenueProvider)))
        : ref.watch(pnlChartRangeProvider);
    final quietText = quiet;
    final List<double> values;
    final engine = quietText == null && venue != null
        ? ref.watch(pnlWindowProvider((range: range, venue: venue)))
        : null;
    if (engine != null && engine.values.isNotEmpty) {
      // The engine's line, its last point the venue's P&L now.
      values = [...engine.values];
      values[values.length - 1] = data.totalPnlUsd ??
          (data.points.isEmpty ? 0.0 : data.points.last.pnlUsd);
    } else if (quietText == null) {
      final series = pnlSeries(data, now ?? DateTime.now());
      values = kuteTrendWindow(series, series.spanFor(range)).values;
    } else {
      values = const [];
    }
    final pnl = quietText == null ? pnlRangeChange(values, range) : null;
    final tone = pnl == null || !visible
        ? c.textSecondary
        : pnl == 0
            ? c.textSecondary
            : pnlResultColor(c, pnl);

    // The corner: the percent of a real base, else the range.
    String? corner;
    if (quietText == null && pnl != null) {
      final base = percentBaseUsd;
      final arrow = visible ? kuteTrendArrow(pnl) : '';
      corner = visible && base != null && base > 0
          ? '$arrow${kuteSignedPercent(pnl / base * 100).replaceFirst(RegExp(r'^[+−]'), '')}'
          : '$arrow${kuteTrendPeriodLabel(l10n, range)}';
    }

    final quietStyle = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.25,
    );
    final decoration = PremiumGroupContainer.decorationOf(context);
    final radius = decoration.borderRadius as BorderRadius?;
    final icon = kPortfolioSquareIcon.w;
    final spark = kPnlSquareSparkHeight.h;
    final outline = context.ctaFill;
    final square = KutePressable(
      enabled: onTap != null,
      // The selected outline eases in and out with the pick (a picked
      // Portfolio Builder card's), drawn over the square so nothing in it
      // moves; at once under Reduce Motion.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: selected ? 1 : 0),
        duration: kuteMotion(context, kPnlPickDuration),
        curve: Curves.easeOut,
        builder: (context, picked, child) => Container(
          key: const ValueKey('pnl-venue-square'),
          height: pnlVenueSquareHeight(context),
          decoration: decoration,
          foregroundDecoration: picked <= 0
              ? null
              : BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                      color: outline.withValues(alpha: outline.a * picked),
                      width: 1.5),
                ),
          child: child,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: EdgeInsets.all(kPnlSquarePad.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox.square(
                        dimension: icon,
                        child: SvgPicture.asset(logoAsset,
                            width: icon, height: icon, fit: BoxFit.contain),
                      ),
                      SizedBox(width: 8.w),
                      if (corner != null)
                        Expanded(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topRight,
                              child: Text(corner,
                                  key: const ValueKey('pnl-venue-change'),
                                  maxLines: 1,
                                  style: quietStyle.copyWith(
                                    color: tone,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  )),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(name,
                      key: const ValueKey('pnl-venue-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: quietStyle),
                  SizedBox(height: 2.h),
                  Text(quietText ?? subtitle,
                      key: const ValueKey('pnl-venue-subtitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: quietStyle.copyWith(
                          color: c.textTertiary, fontSize: 12.sp, height: 1.3)),
                  if (quietText == null) ...[
                    SizedBox(height: 4.h),
                    // A figure too wide for the square shrinks rather than
                    // overflow it.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        pnl == null
                            ? '—'
                            : visible
                                ? '${kuteChangeSign(pnl)}${formatPolyAmount(ref, pnl.abs())}'
                                : '••••••',
                        key: const ValueKey('pnl-venue-figure'),
                        maxLines: 1,
                        style: TextStyle(
                          color: pnl == null || !visible
                              ? c.textPrimary
                              : pnlResultColor(c, pnl),
                          fontSize: 22.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          height: 1.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ] else
                    // The figure's room, so a quiet square's words sit
                    // level with its neighbour's.
                    SizedBox(
                        height: 4.h +
                            MediaQuery.textScalerOf(context).scale(22.sp) *
                                1.2),
                  SizedBox(height: kPnlSquareSparkGap.h),
                  if (values.length >= 2)
                    PnlSparkline.wide(
                        values: values,
                        height: spark,
                        color: visible
                            ? pnlResultColor(c, values.last - values.first)
                            : c.textTertiary)
                  else
                    SizedBox(height: spark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final body = AnimatedOpacity(
      opacity: dimmed ? kPnlDimmedOpacity : 1,
      duration: kuteMotion(context, kPnlPickDuration),
      curve: Curves.easeOut,
      child: square,
    );
    if (onTap == null) return body;
    return Semantics(button: true, selected: selected, child: body);
  }
}

/// A stat tile's height: its label's line over the figure, at the
/// viewer's text size.
double pnlStatTileHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return kPnlSquarePad.w * 2 +
      scaler.scale(12.sp) * 1.3 +
      8.h +
      scaler.scale(20.sp) * 1.2 +
      // A pixel of slack for rounding.
      2;
}

/// The all-time stats under "All time" on the Portfolio screen as compact
/// square tiles in ONE row ([pnlStats]: Realised, Unrealised, Win rate
/// where counted), equal widths [kPnlSquareGap] apart: thirds for three,
/// halves for two, one across for one, so never an orphan half tile. Each
/// tile is the squares' ground ([PremiumGroupContainer], [kPnlSquarePad]):
/// its label (12, textSecondary) at the top, its figure (20 w700 tabular,
/// in its colour) at the bottom, each scaled down rather than cut.
class PnlStatTiles extends ConsumerWidget {
  const PnlStatTiles({super.key, required this.stats});

  final PnlStatsFigures stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final tiles = pnlStats(context, ref, stats, allTime: false);
    if (tiles.isEmpty) return const SizedBox.shrink();
    final height = pnlStatTileHeight(context);
    final decoration = PremiumGroupContainer.decorationOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) SizedBox(width: kPnlSquareGap.w),
          Expanded(
            child: Container(
              key: ValueKey('statistics-pnl-stat-${tiles[i].id}'),
              height: height,
              padding: EdgeInsets.all(kPnlSquarePad.w),
              decoration: decoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(tiles[i].label,
                        maxLines: 1,
                        style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1,
                            height: 1.3)),
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(tiles[i].figure,
                        maxLines: 1,
                        style: TextStyle(
                            color: tiles[i].color,
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            height: 1.2,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ),
                ],
              ),
            ),
          ),
        ],
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

/// A venue's P&L over the range, [kPnlSparklineSize] (a venue row's) or
/// across the width it is given ([PnlSparkline.wide], a venue square's):
/// the monotone line alone, 1.5 px in its result colour, no fill, no
/// reference.
class PnlSparkline extends StatelessWidget {
  const PnlSparkline({super.key, required this.values, required this.color})
      : height = null;

  /// The whole width it is given, [height] (logical pixels) tall.
  const PnlSparkline.wide(
      {super.key,
      required this.values,
      required this.color,
      required double this.height});

  final List<double> values;
  final Color color;

  /// [PnlSparkline.wide]'s height; null: [kPnlSparklineSize].
  final double? height;

  @override
  Widget build(BuildContext context) {
    final tall = height;
    final painter = _SparklinePainter(values, color);
    if (tall == null) {
      return CustomPaint(
        key: const ValueKey('pnl-sparkline'),
        size: Size(kPnlSparklineSize.width.w, kPnlSparklineSize.height.h),
        painter: painter,
      );
    }
    return SizedBox(
      width: double.infinity,
      height: tall,
      child: CustomPaint(key: const ValueKey('pnl-sparkline'), painter: painter),
    );
  }
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
