// lib/screens/usd/components/usd_balance_chart.dart
//
// The Dollars tab's Balance tab: the dollar balance over time.
//
// It is the bitcoin Balance tab part for part: the same card, the same
// [BalanceHistoryChart] (the modern line chart with its own headline and
// change line). The ONLY difference is the series: dollars held on the
// spending account instead of the bitcoin balance. Like the bitcoin one it
// has its range row under the plot (1W to ALL, 1M to start, its own
// choice remembered for the session) and draws each bucket's closing
// balance (see balance_history.dart).

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
        // The chart's own header: the balance (the one under a scrubbing
        // finger), and the change over the range or to that moment.
        child: BalanceHistoryChart(
          history: history,
          format: dollars.format,
          rangeKey: 'dollars',
          trackingChart: 'valuation',
        ),
      ),
    );
  }
}
