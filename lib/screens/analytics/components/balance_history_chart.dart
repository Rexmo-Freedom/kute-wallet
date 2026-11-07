// lib/screens/analytics/components/balance_history_chart.dart
//
// The Balance chart of a Bitcoin wallet (spending, hardware, watch-only,
// Ledger) and of the Dollars account, drawn through the modern line chart
// ([KuteTrendChart], founder, 31 October 2026: "make the graph modern"):
//
//   * a header the chart owns, calm (founder, 7 November 2026: "This part
//     on top in Balance is too dense still, too much information"): ONE
//     figure, the balance (now, or under a scrubbing finger), and ONE
//     quiet line under it: the other unit ([BalanceHistoryChart.secondary]:
//     the fiat worth of a bitcoin balance), then, at rest, what the line
//     did over the range as "▲ 12.4%" in the change's colour, only when
//     that says something ([balanceChartChange]: never flat, never when
//     the change is the whole balance, a first deposit inside the range or
//     an account emptied); the range row under the plot names the period.
//     While a finger scrubs, the moment under it ("Oct 16 14:00") instead
//     of the change;
//   * the plot: the closing balance of each bucket the range calls for (a
//     quarter hour to a week), so money passing through within a bucket
//     never spikes it; ONE line in the result colour of the range (up,
//     down, the text colour when flat), its fill, a dashed hairline at
//     the range's first value; no axes, no grid, no labels;
//   * a range row 16 px under the plot (1W 1M 3M 1Y ALL, the small white
//     pill), 1M to start and remembered per chart for the session;
//     picking a range morphs the line;
//   * NO HISTORY (the account never held money): Activity's empty state
//     in its place (founder, 31 October 2026: "no balance should also
//     show Sal"), Sal centred with "No balance history yet" and "It
//     starts with your first transaction.": no headline, no chart, no
//     range row;
//   * with balances hidden the figures are dots, as on the home header;
//   * a GOAL ([BalanceHistoryChart.goal], the Bitcoin home's next
//     milestone, balance_goals.dart): drawn as the plot's dashed goal line
//     only while it is in reach of the line on screen
//     ([balanceGoalInReach]: the line keeps at least half the plot) and
//     the figures are shown. Nothing else of the milestones is drawn
//     here: they stand under the card.
//
// Analytics: `analytics_chart_scrubbed` {chart, view: line}, once per
// scrub gesture. Ranges send nothing.

import 'package:flutter/material.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/charts/kute_trend_window.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/balance_milestones.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The range each Balance chart shows, per chart ([BalanceHistoryChart.
/// rangeKey]), for the rest of the session: the past month to start.
final balanceChartRangeProvider =
    StateProvider.family<BalanceRange, String>((ref, key) => BalanceRange.month);

class BalanceHistoryChart extends ConsumerStatefulWidget {
  /// The balance as the moments it changed, in the unit it is drawn in
  /// (sats for bitcoin, dollars).
  final BalanceHistory history;

  /// Writes an amount without a sign ("₿17,520", "$12.30"): the headline,
  /// the scrubbed balance and the size of the change.
  final String Function(double value) format;

  /// Writes the second line under the headline for a balance (its fiat
  /// worth); null draws none.
  final String? Function(double value)? secondary;

  /// Which session range this chart remembers ('bitcoin', 'dollars').
  final String rangeKey;

  /// `analytics_chart_scrubbed`'s chart name, as the old chart sent it.
  final String trackingChart;

  /// The moment the line ends on; now unless a test pins it.
  final DateTime? now;

  /// A goal in the chart's own unit, drawn as the dashed goal line while
  /// it is in reach of the line on screen; null draws none.
  final KuteTrendGoal? goal;

  const BalanceHistoryChart({
    super.key,
    required this.history,
    required this.format,
    required this.trackingChart,
    this.secondary,
    this.rangeKey = 'bitcoin',
    this.now,
    this.goal,
  });

  @override
  ConsumerState<BalanceHistoryChart> createState() =>
      _BalanceHistoryChartState();
}

class _BalanceHistoryChartState extends ConsumerState<BalanceHistoryChart> {
  /// The point under the finger; null at rest.
  KuteTrendPoint? _scrub;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final range = ref.watch(balanceChartRangeProvider(widget.rangeKey));
    // With balances hidden the figures are dots, as on the home header,
    // and the change carries no percent.
    final visible =
        ref.watch(settingsProvider.select((s) => s.balanceVisible));
    String amount(double v) => visible ? widget.format(v) : '••••••';
    final history = widget.history;
    final hasHistory = history.changes.isNotEmpty || history.opening > 0;
    // Nothing ever on this balance (founder, 31 October 2026: "no balance
    // should also show Sal"): the same empty state as Activity, Sal
    // centred with the title and its line, no headline and no empty plot.
    // A balance with no points but an opening keeps the headline and the
    // chart's own caption.
    if (!hasHistory) {
      return NoActivityState(
        key: const ValueKey('balance-chart-no-history'),
        title: l10n.balanceNoHistoryTitle,
        subtitle: l10n.balanceNoHistorySub,
        cycles: 3,
        compact: true,
      );
    }
    final series = balanceSeries(history, widget.now ?? DateTime.now());
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

    // The headline: the balance now, or under the finger.
    final headline = scrubbing
        ? scrub.value
        : (values.isNotEmpty ? values.last : history.current);
    final secondaryText = widget.secondary?.call(headline);

    final quiet = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // ONE quiet line under the figure (founder, 7 November 2026: "This
    // part on top in Balance is too dense still"): the other unit, then,
    // at rest, what the line did over the range when that says something
    // ("▲ 12.4%", the range row under the plot names the period); while a
    // finger scrubs, the moment under it. Hidden: the other unit's dots.
    String? tail;
    Color? tailColor;
    if (visible && scrubbing) {
      tail = timeOf(scrub.time ?? times.last);
    } else if (visible) {
      final move = balanceChartChange(values);
      if (move != null) {
        tail =
            '${kuteTrendArrow(move)}${kuteSignedPercent(move).replaceFirst(RegExp(r'^[+\u2212-]'), '')}';
        tailColor = move > 0 ? AppColors.marketUp : AppColors.marketDown;
      }
    }
    final line = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (secondaryText != null)
          RollingNumberText(
            key: const ValueKey('balance-chart-secondary'),
            text: visible ? secondaryText : '••••••',
            duration: Duration(milliseconds: scrubbing ? 120 : 350),
            style: quiet,
          ),
        if (tail != null)
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                if (secondaryText != null) const TextSpan(text: ' · '),
                TextSpan(
                  text: tail,
                  style: tailColor == null
                      ? null
                      : TextStyle(
                          color: tailColor, fontWeight: FontWeight.w600),
                ),
              ]),
              key: const ValueKey('balance-chart-header'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: quiet,
            ),
          ),
        // Nothing to say: the line keeps its height, so the plot never
        // moves under a finger.
        if (secondaryText == null && tail == null) Text('\u00A0', style: quiet),
      ],
    );

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RollingNumberText(
          key: const ValueKey('balance-chart-headline'),
          text: amount(headline),
          duration: Duration(milliseconds: scrubbing ? 120 : 350),
          dimColor: c.textTertiary,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 22.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            height: 1.0,
          ),
        ),
        if (hasHistory) ...[SizedBox(height: 6.h), line],
        if (!hasHistory)
          Padding(
            padding: EdgeInsets.only(top: 4.h),
            child: Text(
              l10n.balanceChartNoHistory,
              key: const ValueKey('balance-chart-empty'),
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );

    // The goal line only while it is close enough to keep the line's
    // shape, and never over hidden figures.
    final goal = widget.goal;
    // Kept while a finger scrubs: the scale never moves under it.
    final shownGoal =
        goal != null && visible && balanceGoalInReach(values, goal.value)
            ? goal
            : null;

    final chart = KuteTrendChart(
      key: const ValueKey('balance-chart'),
      values: hasHistory ? values : const [],
      times: hasHistory ? times : null,
      goal: shownGoal,
      height: kKuteTrendPlotHeight.h,
      onScrub: (p) => setState(() => _scrub = p),
      onScrubStart: () => TrackingService.analyticsChartScrubbed(
          chart: widget.trackingChart, view: 'line'),
      rangeLabels: [for (final r in BalanceRange.values) r.label],
      selectedRange: range.index,
      onRangeSelected: (i) {
        ref.read(balanceChartRangeProvider(widget.rangeKey).notifier).state =
            BalanceRange.values[i];
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        if (hasHistory) ...[SizedBox(height: 12.h), chart],
      ],
    );
  }
}

/// What the line did over [values] as a percent of where it started, or
/// null when that says nothing: fewer than two points, a flat line (under
/// a tenth of a percent), or a range whose smaller end is under a tenth of
/// the larger, a first deposit inside the range or an account emptied,
/// where the change is the whole balance (founder, 7 November 2026).
double? balanceChartChange(List<double> values) {
  if (values.length < 2) return null;
  final base = values.first, to = values.last;
  if (!(base > 0) || !(to > 0) || !base.isFinite || !to.isFinite) return null;
  final lo = base < to ? base : to, hi = base < to ? to : base;
  if (lo < hi * 0.1) return null;
  final percent = (to - base) / base * 100;
  return kutePercentDirection(percent) == 0 ? null : percent;
}
