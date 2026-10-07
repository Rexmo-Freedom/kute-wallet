// lib/screens/usd/components/usd_balance_chart.dart
//
// The Dollars tab's Balance tab: the dollar balance over time.
//
// It is the bitcoin Balance tab part for part: the same card, the same
// [BalanceHistoryChart], the same scrub card. The ONLY difference is the
// series: dollars held on the spending account instead of the bitcoin
// balance. Like the bitcoin one it has no range row: the whole history,
// from just before the first transfer to now, fitted to the width and
// drawn in steps (a cash balance only moves when a transfer settles).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/analytics/components/analytics_card.dart';
import 'package:kute/screens/analytics/components/balance_history_chart.dart';

/// The dollar balance chart, sized and framed exactly as the bitcoin
/// one so switching tabs never shifts the card.
class UsdBalanceChart extends ConsumerWidget {
  const UsdBalanceChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(usdBalanceStepsProvider);
    // The account holds dollars, so the figures are dollars whatever
    // display currency is set; the hero above the strip reads the same.
    final dollars = NumberFormat.simpleCurrency(name: 'USD');

    return AnalyticsCard(
      // The 400 dp every non-Fees analytics card shares.
      height: 400.h,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
        // No headline above the plot (owner decision): the balance now
        // is the hero card at the top of the screen, and a touched
        // moment is written on the chart's own scrub card.
        child: BalanceHistoryChart(
          history: history,
          format: dollars.format,
          scaleLabel: dollarScaleLabel,
          trackingChart: 'valuation',
        ),
      ),
    );
  }
}

/// A level of the dollar Balance chart's scale: "$0", "$5", "$1.5K",
/// or with cents ("$0.50") when the levels are under a dollar apart.
String dollarScaleLabel(double level, double step) => step >= 1
    ? '\$${NumberFormat.compact(locale: 'en_US').format(level)}'
    : '\$${level.toStringAsFixed(2)}';
