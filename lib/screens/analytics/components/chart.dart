import 'package:kute/helpers/extension.dart';
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

class Chart extends StatefulWidget {
  final List<DateTime> selectedDays;
  final Map<DateTime, num> mainData;
  final Map<DateTime, num> bitcoinBalanceByDayformatted;
  final Map<DateTime, num> dollarBalanceByDay;
  final Map<DateTime, num> priceByDay;
  final String selectedCurrency;
  final bool isShowingMainData;
  final bool isCurrency;
  final String btcFormat;
  final bool isBitcoinAsset;
  final String selectedAsset;

  /// A new value puts a zoomed chart back on the whole range (the range
  /// pill tapped again).
  final Object? viewResetKey;

  /// How many of the trailing days in [selectedDays] are a forecast
  /// rather than something that happened. Zero (the default) is every
  /// existing caller. Those days are drawn as a projected tail by
  /// [KuteLineChart] and are deliberately kept out of the trend colour
  /// and the percent badge, which describe the past only.
  final int projectedDays;

  const Chart({
    super.key,
    required this.selectedDays,
    required this.mainData,
    required this.bitcoinBalanceByDayformatted,
    required this.dollarBalanceByDay,
    required this.priceByDay,
    required this.selectedCurrency,
    required this.isShowingMainData,
    required this.isCurrency,
    required this.btcFormat,
    required this.isBitcoinAsset,
    required this.selectedAsset,
    this.viewResetKey,
    this.projectedDays = 0,
  });

  @override
  State<Chart> createState() => _ChartState();
}

class _ChartState extends State<Chart> {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (widget.selectedDays.isEmpty) {
      return Center(
        child: Text(
          context.l10n.selectADateRange,
          style: TextStyle(color: c.textTertiary, fontSize: 16.sp),
        ),
      );
    }

    final sortedDays = List<DateTime>.from(widget.selectedDays)
      ..sort((a, b) => a.compareTo(b));
    final values = _createValues(widget.mainData, sortedDays);
    // History only. A forecast is not allowed to tint the line or move
    // the badge: both report what actually happened.
    final projected = widget.projectedDays.clamp(0, values.length - 1);
    final int? projectedFrom =
        projected > 0 ? values.length - 1 - projected : null;
    final actualValues =
        projectedFrom == null ? values : values.sublist(0, projectedFrom + 1);
    final trend = _computeTrend(actualValues);

    // Unified chart language: no grid, no axes, just the engine curve
    // (monotone cubic, 0.14 gradient fill, endpoint dot). The change over
    // the window on screen sits above the plot as the venue charts write
    // theirs, and the scrub card (value, change, date) carries the point
    // under the finger.
    final Color lineColor;
    switch (trend) {
      case _Trend.up:
        lineColor = AppColors.marketUp;
        break;
      case _Trend.down:
        lineColor = AppColors.marketDown;
        break;
      case _Trend.neutral:
        lineColor = c.accent;
        break;
    }
    final locale = kuteChartLocale(context);
    final l10n = context.l10n;

    return Padding(
      padding: EdgeInsets.only(top: 4.h),
      child: KuteLineChart(
        values: values,
        lineColor: lineColor,
        projectedFrom: projectedFrom,
        viewResetKey: widget.viewResetKey,
        // History only: a forecast is not allowed to move the change,
        // which reports what actually happened.
        summaryBuilder: (first, last) {
          final end = projectedFrom == null
              ? last
              : last.clamp(0, projectedFrom).toInt();
          if (end <= first) return null;
          final percent =
              _computePercentChange(values.sublist(first, end + 1));
          if (percent == null) return null;
          return Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(right: 4.w, bottom: 4.h),
              child: ChartChangeText(percent: percent),
            ),
          );
        },
        onScrubStart: () => TrackingService.analyticsChartScrubbed(
            chart: widget.isCurrency ? 'valuation' : 'balance',
            view: 'line'),
        valueTextBuilder: (index) {
          if (index < 0 || index >= sortedDays.length) return null;
          return _formatValue(
              _resolvedValue(sortedDays[index], values[index]));
        },
        changeFormatter: _formatValue,
        timeTextBuilder: (index) {
          if (index < 0 || index >= sortedDays.length) return null;
          return kuteChartDay(sortedDays[index], locale);
        },
        detailTextBuilder: (index) => [
          // Out in the dashed tail the figure is a forecast.
          if (projectedFrom != null && index > projectedFrom)
            l10n.usdEarnProjectedLabel,
          // A fiat valuation of bitcoin: what was held that day.
          if (widget.isCurrency &&
              widget.isBitcoinAsset &&
              index >= 0 &&
              index < sortedDays.length)
            ...[_heldOn(sortedDays[index])].whereType<String>(),
        ],
      ),
    );
  }

  /// The bitcoin held on [day] (forward-filled from the last day the
  /// balance changed), as the wallet writes it; null when none.
  String? _heldOn(DateTime day) {
    final target = day.dateOnly();
    num held = 0;
    final days = widget.bitcoinBalanceByDayformatted.keys.toList()..sort();
    for (final d in days) {
      if (d.dateOnly().isAfter(target)) break;
      held = widget.bitcoinBalanceByDayformatted[d] ?? held;
    }
    if (held <= 0) return null;
    final int sats = widget.btcFormat == 'sats'
        ? held.round()
        : (held * 100000000).round();
    final unit = widget.btcFormat == 'sats' ? 'sats' : 'BTC';
    return '${sats.toFormattedString(widget.btcFormat)} $unit';
  }

  /// The forward-filled series value at [date] resolved back through the
  /// raw data map (same lookup the old tooltip used), falling back to
  /// the plotted value.
  double _resolvedValue(DateTime date, double plotted) {
    final normalizedData = {
      for (var e in widget.mainData.entries) e.key.dateOnly(): e.value
    };
    return (normalizedData[date.dateOnly()] ?? plotted).toDouble();
  }

  String _formatValue(double actualValue) {
    if (widget.isCurrency) {
      return NumberFormat.simpleCurrency(name: widget.selectedCurrency)
          .format(actualValue);
    }
    if (widget.isBitcoinAsset) {
      final int sats = widget.btcFormat == 'sats'
          ? actualValue.round()
          : (actualValue * 100000000).round();
      final unit = widget.btcFormat == 'sats' ? 'sats' : 'BTC';
      return '${sats.toFormattedString(widget.btcFormat)} $unit';
    }
    return NumberFormat.decimalPattern().format(actualValue);
  }

  _Trend _computeTrend(List<double> values) {
    if (values.length < 2) return _Trend.neutral;
    final first = values.first;
    final last = values.last;
    if (last > first) return _Trend.up;
    if (last < first) return _Trend.down;
    return _Trend.neutral;
  }

  double? _computePercentChange(List<double> values) {
    if (values.length < 2) return null;
    final first = values.first;
    final last = values.last;
    if (first == 0 && last == 0) return null;
    if (first == 0) return 100;
    return ((last - first) / first) * 100;
  }

  List<double> _createValues(
    Map<DateTime, num> data,
    List<DateTime> sortedDays,
  ) {
    final normalizedData = {
      for (var entry in data.entries) entry.key.dateOnly(): entry.value
    };

    // Days prior to the first recorded balance should read as 0, not be
    // back-filled with the first value — otherwise a new wallet shows a flat
    // line at its current balance across the whole range.
    num lastValue = 0;

    final values = <double>[];
    for (int i = 0; i < sortedDays.length; i++) {
      final day = sortedDays[i].dateOnly();
      if (normalizedData.containsKey(day)) {
        lastValue = normalizedData[day]!;
      }
      final v = lastValue.toDouble();
      values.add(v < 0 ? 0 : v);
    }
    return values;
  }
}

/// The change over the window a chart shows, as the venue charts write
/// theirs above the plot: signed, in the up/down colour, no box.
class ChartChangeText extends StatelessWidget {
  final double? percent;

  /// A change already written ("+$12.30 (+1.2%)"), with the way it went
  /// for its colour: the Balance charts write an amount, not a percent.
  final String? label;
  final int direction;

  const ChartChangeText({super.key, required double this.percent})
      : label = null,
        direction = 0;

  const ChartChangeText.written(String this.label,
      {super.key, required this.direction})
      : percent = null;

  @override
  Widget build(BuildContext context) {
    final sign = label != null ? direction : percent!.sign.toInt();
    final color = sign > 0
        ? AppColors.marketUp
        : (sign < 0 ? AppColors.marketDown : context.colors.textSecondary);
    return Text(
      label ?? kuteSignedPercent(percent!),
      maxLines: 1,
      style: TextStyle(
        color: color,
        fontSize: 13.sp,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

enum _Trend { up, down, neutral }
