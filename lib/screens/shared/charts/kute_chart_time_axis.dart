// lib/screens/shared/charts/kute_chart_time_axis.dart
//
// The time axis under a zoomable chart (the Predictions chart, the
// Bitcoin and Dollars balance charts): when the window on screen starts,
// at the plot's left edge, and when it ends, at its right edge. The end
// reads "Now" while the window reaches the live edge. Both follow every
// pan and pinch, so the dates say how far a zoom went.
//
// The format follows the window's span: under a day the time of day
// ("14:05"), under a year the day ("Sep 12", "12 de set."), longer the
// month ("Sep 2025"), in the app's language (kute_chart_format.dart). The
// labels are the charts' own scale labels (tertiary, 10.5, semibold,
// tabular figures); no gridlines, no frame. Time runs left to right on
// every chart, so the row keeps that order in a right-to-left language.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:kute/screens/shared/charts/kute_chart_core.dart';
import 'package:kute/theme/app_theme.dart';

/// The height of the time axis row; a chart takes it from its plot, so
/// the chart as a whole keeps its height.
const double kKuteTimeAxisHeight = 16.0;

/// [t] as the time axis writes it for a window [span] long: the time of
/// day under a day, the day under a year, the month past that.
String kuteAxisTime(DateTime t, Duration span, String? locale) {
  if (span < const Duration(days: 1)) return DateFormat.Hm(locale).format(t);
  if (span < const Duration(days: 365)) {
    return DateFormat.MMMd(locale).format(t);
  }
  return DateFormat.yMMM(locale).format(t);
}

/// The two labels for a window from [start] to [end]: [end] reads
/// [nowLabel] when the window reaches the live edge ([live]).
({String start, String end}) kuteTimeAxisTexts({
  required DateTime start,
  required DateTime end,
  required bool live,
  required String nowLabel,
  String? locale,
}) {
  final span = end.difference(start).abs();
  return (
    start: kuteAxisTime(start, span, locale),
    end: live ? nowLabel : kuteAxisTime(end, span, locale),
  );
}

/// The time axis row: [start] at the left edge, [end] at the right.
class KuteTimeAxis extends StatelessWidget {
  final String start;
  final String end;

  const KuteTimeAxis({super.key, required this.start, required this.end});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: kuteChartFontFamily,
      color: context.colors.textTertiary,
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.2,
    );
    return SizedBox(
      height: kKuteTimeAxisHeight,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(start,
                  key: const ValueKey('kute-time-axis-start'),
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  textScaler: TextScaler.noScaling),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(end,
                  key: const ValueKey('kute-time-axis-end'),
                  style: style,
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.clip,
                  textScaler: TextScaler.noScaling),
            ),
          ],
        ),
      ),
    );
  }
}
