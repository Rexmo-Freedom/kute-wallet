// lib/screens/usd/components/usd_earn_chart.dart
//
// The Dollars tab's Earn tab: what holding dollars has paid, over time.
//
// EARN IS NOT A DOOR, IT IS A VIEW OF THE SAME BALANCE. The programme is
// passive — holding dollars pays a daily bitcoin reward on the whole
// balance, with nothing to stake and nothing to deposit into — so there
// is no separate destination to send money to and no screen to push. It
// is a sibling of the Balance tab: the same [AnalyticsCard], the same
// [Chart] engine, the same date-range strip, the same scrub card. The
// ONLY difference is the series: the daily payout ledger, added up, in
// place of the dollar balance.
//
// PAID ONLY. The curve and the total both count payouts the wallet has
// actually received. A pending day lifts neither until it settles, so
// the number under "Paid to you so far" is money in hand.
//
// THE RATE IS NEVER INVENTED. It comes from the service or it is missing:
// a failed read says unavailable, a slow one says loading, and neither
// ever falls back to a constant, a zero or the last number we saw. The
// rate is also confined to this tab — no entry chip, card or row
// anywhere else may print a percentage (App Store constraint).
//
// THE PROJECTION IS NEVER INVENTED EITHER. Past the last paid day the
// curve carries on as a dashed, unfilled tail so the balance can be seen
// heading somewhere. It is built from ONE number, the venue's own
// [UserRewardsSummary.estimatedSatsToday], added once per day: never from
// the rate times the balance, never from an average of past payouts. If
// the summary is missing, still loading, or that estimate is zero, there
// is no tail at all and the chart is exactly what it was. The tail is
// also kept out of the trend colour and the percent badge (see
// [Chart.projectedDays]), and a point out in the future says so on its
// scrub card, so "Paid to you so far" only ever sits over money in hand.
//
// LIVE is dropped from the range strip, same as the Balance tab: payouts
// land once a day, so a per-second mode would redraw an identical line.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/usd_rewards_model.dart';
import 'package:kute/providers/analytics_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_rewards_provider.dart';
import 'package:kute/screens/analytics/components/analytics_card.dart';
import 'package:kute/screens/analytics/components/chart.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart'
    show HomeDateRangeSelector, applyAnalyticsDateRange, kHomeDateRanges;
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The dollar balance a wallet must hold before the rewards programme
/// pays it anything, in dollars.
///
/// Flashnet's own figure (docs.flashnet.xyz/usdb/rewards, read 2026-09-25:
/// "The minimum balance to earn rewards is 10 USDB"). The rewards API
/// reports the rate and the day's estimate but never this floor, so it
/// lives here rather than being inferred from a zero estimate, which a
/// quiet day would look exactly like.
const double kUsdEarnMinimumDollars = 10;

/// [kUsdEarnMinimumDollars] as money. Whole dollars, so it reads as the
/// round rule it is rather than as a computed amount.
String formatUsdEarnMinimum(double amount) =>
    NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 0).format(amount);

/// The earnings chart, sized and framed exactly as the dollar balance
/// one so switching tabs never shifts the card.
class UsdEarnChart extends ConsumerStatefulWidget {
  const UsdEarnChart({super.key});

  @override
  ConsumerState<UsdEarnChart> createState() => _UsdEarnChartState();
}

class _UsdEarnChartState extends ConsumerState<UsdEarnChart> {
  static final List<String> _ranges =
      kHomeDateRanges.where((r) => r != 'LIVE').toList(growable: false);

  String _selectedRange = '7D';

  /// Bumped when the range already shown is tapped again: a zoomed chart
  /// goes back to the whole range.
  int _viewReset = 0;

  /// Ticks the payout countdown. UTC, because the day the programme pays
  /// on is a UTC day: the summary's own volume field is `volumeUtcToday`
  /// and the ledger is keyed by UTC date, so a wallet in Lisbon and one
  /// in São Paulo are paid at the same instant, not at their own
  /// midnights.
  Timer? _countdownTick;
  DateTime _nowUtc = DateTime.now().toUtc();

  ProviderSubscription<AsyncValue<UserRewardsSummary?>>? _summarySub;
  bool _stateTracked = false;

  /// The next 00:00 UTC after [nowUtc], which is when the day's payout
  /// is cut.
  static DateTime _nextPayoutUtc(DateTime nowUtc) =>
      DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day + 1);

  /// `6h 12m 03s`, counting down. Hours are never padded, so the line
  /// does not jitter between widths at the start of a day.
  static String _countdownLabel(Duration left) {
    final clamped = left.isNegative ? Duration.zero : left;
    final minutes = clamped.inMinutes % 60;
    final seconds = clamped.inSeconds % 60;
    return '${clamped.inHours}h '
        '${minutes.toString().padLeft(2, '0')}m '
        '${seconds.toString().padLeft(2, '0')}s';
  }

  @override
  void initState() {
    super.initState();
    _countdownTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _nowUtc = DateTime.now().toUtc());
    });
    // Opening the tab IS opening Earn — it replaced the pushed screen
    // that used to fire `usd_earn_opened`.
    TrackingService.track('usd_earn_opened', params: {'surface': 'usd_tab'});
    // What the tab could say, once per open, when the summary first
    // answers: booleans only, never the balance, the rate or a payout.
    _summarySub = ref.listenManual<AsyncValue<UserRewardsSummary?>>(
      userRewardsSummaryProvider,
      (_, next) {
        if (_stateTracked || next.isLoading) return;
        _stateTracked = true;
        final summary = next.valueOrNull;
        final payouts =
            ref.read(payoutHistoryProvider(earnPayoutPage)).valueOrNull;
        TrackingService.track('usd_earn_state_shown', params: {
          'rate_state': next.hasError || summary?.rewardsPercent == null
              ? 'unavailable'
              : 'shown',
          'below_minimum': summary != null &&
              summary.usdbBalanceDisplay < kUsdEarnMinimumDollars,
          'has_estimate': (summary?.estimatedSatsToday ?? 0) > 0,
          if (payouts != null) 'has_payouts': payouts.payouts.isNotEmpty,
        });
      },
      fireImmediately: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      applyAnalyticsDateRange(ref, _selectedRange);
    });
  }

  @override
  void dispose() {
    _countdownTick?.cancel();
    _summarySub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final selectedDays = ref.watch(selectedDaysDateArrayProvider);
    final summaryAsync = ref.watch(userRewardsSummaryProvider);
    final payoutsAsync = ref.watch(payoutHistoryProvider(earnPayoutPage));
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    final inSats = btcFormat == 'sats';

    final summary = summaryAsync.valueOrNull;
    // The rate, straight from the service. Null on a failure AND on a
    // still-loading read; the two are told apart below.
    final percent = summary?.rewardsPercent;
    final String? rate =
        percent == null ? null : '${percent.toStringAsFixed(1)}%';
    // A summary that states no rate reads as unavailable, never as a
    // rate the app made up.
    final rateUnavailable = summaryAsync.hasError ||
        (!summaryAsync.isLoading && (summary == null || percent == null));
    final rateText = rate ??
        (rateUnavailable
            ? l10n.usdEarnRateUnavailable
            : l10n.usdEarnRatePending);

    // Flashnet pays rewards on a dollar balance of at least
    // [kUsdEarnMinimumDollars]; under that the programme pays nothing at
    // all, whatever the rate says. Only a READ balance can be under it:
    // while the summary is loading there is nothing to claim either way.
    final belowMinimum =
        summary != null && summary.usdbBalanceDisplay < kUsdEarnMinimumDollars;

    final history = payoutsAsync.valueOrNull;
    final paidSats = history?.totalPayoutSats ?? 0;
    // The chart reads whatever unit the wallet is set to, because
    // [Chart] formats its own bubbles from that setting.
    final byDay = _cumulativeByDay(history?.payouts, inSats: inSats);

    // The forecast, or nothing at all. [_Projection.none] is returned
    // whenever the venue's daily estimate is missing, still loading or
    // zero, and then every value below is the untouched history.
    final projection = _Projection.from(
      days: selectedDays,
      byDay: byDay,
      estimateSats: summary?.estimatedSatsToday ?? 0,
      inSats: inSats,
    );

    final Widget body;
    // The note belongs to the curve, so it only appears when the curve
    // does: a skeleton or a notice in that slot has no dashed tail to
    // explain.
    var chartDrawn = false;
    if (history == null && payoutsAsync.isLoading) {
      body = const _ChartSkeleton();
    } else if (payoutsAsync.hasError) {
      body = _Notice(text: l10n.usdEarnActivityUnavailable);
    } else if (byDay.isEmpty) {
      body = _Notice(text: l10n.usdEarnActivityEmpty);
    } else {
      chartDrawn = true;
      body = Chart(
        selectedDays: projection.days,
        mainData: projection.byDay,
        // The bitcoin-only slots the shared chart carries for its
        // tooltip: an earnings series has no balance and no price
        // behind it.
        bitcoinBalanceByDayformatted: const {},
        dollarBalanceByDay: const {},
        priceByDay: const {},
        selectedCurrency: 'USD',
        isShowingMainData: true,
        // Payouts are bitcoin, so the bubbles read in sats or BTC,
        // whichever the wallet is set to.
        isCurrency: false,
        btcFormat: btcFormat,
        isBitcoinAsset: true,
        selectedAsset: 'BTC',
        viewResetKey: (_selectedRange, _viewReset),
        projectedDays: projection.projectedDays,
      );
    }

    // Money in hand; a scrubbed day, paid or projected, is written on the
    // chart's scrub card.
    final headlineSats = paidSats;

    // The day's payout, in whatever unit the wallet reads in. Straight
    // from the venue's own estimate: never the rate times the balance.
    final nextPaymentSats = summary?.estimatedSatsToday ?? 0;
    final nextPaymentText =
        '${nextPaymentSats.toFormattedString(btcFormat)} ${inSats ? 'sats' : 'BTC'}';

    return AnalyticsCard(
      // The 400 dp every non-Fees analytics card shares.
      height: 400.h,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
              child: Column(
                children: [
                  _EarnHeader(
                    paidLabel: l10n.usdEarnPaidToDate,
                    paidText: '${headlineSats.toFormattedString(btcFormat)} '
                        '${inSats ? 'sats' : 'BTC'}',
                    rateLabel: l10n.usdEarnRate,
                    rateText: rateText,
                    c: c,
                  ),
                  // What is coming and when, which is the question a
                  // person actually has after putting money in. Held
                  // back only while the summary is still loading and
                  // while the balance is under the floor, where the
                  // answer is nothing and the note below says why.
                  if (summary != null && !belowMinimum) ...[
                    SizedBox(height: 10.h),
                    _NextPayment(
                      label: l10n.usdEarnNextPayment,
                      amountText: nextPaymentText,
                      countdownLabel: l10n.usdEarnNextPaymentIn,
                      countdownText: _countdownLabel(
                          _nextPayoutUtc(_nowUtc).difference(_nowUtc)),
                      c: c,
                    ),
                  ],
                  Expanded(child: body),
                  if (chartDrawn && projection.isOn) ...[
                    SizedBox(height: 6.h),
                    _ProjectionNote(text: l10n.usdEarnProjectionNote),
                  ],
                  // The gate, said only where it bites. A balance already
                  // over the floor does not need telling about it, and a
                  // balance under it is earning nothing and deserves to
                  // know why. Read live off the summary so a deposit
                  // clears the line by itself.
                  if (belowMinimum) ...[
                    SizedBox(height: 6.h),
                    _ProjectionNote(
                        text: l10n.usdEarnBelowMinimum(
                            formatUsdEarnMinimum(kUsdEarnMinimumDollars))),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
            child: HomeDateRangeSelector(
              selectedRange: _selectedRange,
              ranges: _ranges,
              onSelected: (range) {
                if (range != _selectedRange) {
                  TrackingService.track('usd_chart_range_changed', params: {
                    'chart': 'earn',
                    'from': _selectedRange,
                    'to': range,
                  });
                }
                setState(() {
                  if (range == _selectedRange) _viewReset++;
                  _selectedRange = range;
                });
                applyAnalyticsDateRange(ref, range);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The ledger turned into a running total, one entry per day the
  /// programme paid. Days in between carry forward inside [Chart], which
  /// is exactly right for a cumulative series: a day with no payment
  /// leaves the line where it was.
  static Map<DateTime, num> _cumulativeByDay(
    List<RewardPayout>? payouts, {
    required bool inSats,
  }) {
    if (payouts == null || payouts.isEmpty) return const {};
    final paid = payouts
        .where((p) => p.isPaid && p.dayDate != null)
        .toList(growable: false)
      ..sort((a, b) => a.dayDate!.compareTo(b.dayDate!));
    final byDay = <DateTime, num>{};
    var running = 0;
    for (final payout in paid) {
      final day = payout.dayDate!;
      running += payout.payoutSats;
      byDay[DateTime(day.year, day.month, day.day)] =
          inSats ? running : running / 1e8;
    }
    return byDay;
  }
}

/// The days handed to [Chart] and the series behind them, with however
/// many trailing days of that series are a forecast rather than a fact.
class _Projection {
  const _Projection({
    required this.days,
    required this.byDay,
    required this.projectedDays,
  });

  final List<DateTime> days;
  final Map<DateTime, num> byDay;
  final int projectedDays;

  bool get isOn => projectedDays > 0;

  /// Carry the cumulative curve forward from the last day on screen,
  /// adding the venue's own daily estimate once per day.
  ///
  /// Returns the history untouched, with no projected days at all, when
  /// there is nothing to project from: no estimate yet (a missing or
  /// still-loading summary reads as 0), an estimate of zero, or an empty
  /// ledger. Nothing here is ever derived from the rate or the balance.
  ///
  /// The horizon is a third of the visible window, so the forecast keeps
  /// the same share of the chart on every range pill, floored at 3 days
  /// (a week-long window would otherwise get a tail too short to read)
  /// and capped at 90 (a straight-line extrapolation of one day's rate
  /// stops being worth drawing past a quarter, and ALL can span years).
  static _Projection from({
    required List<DateTime> days,
    required Map<DateTime, num> byDay,
    required int estimateSats,
    required bool inSats,
  }) {
    final none = _Projection(days: days, byDay: byDay, projectedDays: 0);
    if (estimateSats <= 0 || days.isEmpty || byDay.isEmpty) return none;

    final horizon = (days.length / 3).round().clamp(3, 90);
    final normalized = {
      for (final e in byDay.entries)
        DateTime(e.key.year, e.key.month, e.key.day): e.value
    };

    // Where the drawn line actually sits on the last real day. [Chart]
    // starts its forward fill at zero and only picks up days inside the
    // window, so the anchor is worked out the same way: a tail that
    // started anywhere else would leave a step in the curve.
    num running = 0;
    for (final day in days) {
      final key = DateTime(day.year, day.month, day.day);
      final value = normalized[key];
      if (value != null) running = value;
    }

    final step = inSats ? estimateSats.toDouble() : estimateSats / 1e8;
    final anchor = days.last;
    final outDays = List<DateTime>.from(days);
    final outByDay = Map<DateTime, num>.from(byDay);
    for (var i = 1; i <= horizon; i++) {
      // Built by calendar day, not by adding 24 hours, so a clock change
      // cannot land two projected points on the same date.
      final day = DateTime(anchor.year, anchor.month, anchor.day + i);
      outDays.add(day);
      outByDay[day] = running + step * i;
    }
    return _Projection(
      days: outDays,
      byDay: outByDay,
      projectedDays: horizon,
    );
  }
}

/// What the programme pays next and how long until it does.
///
/// The amount is the venue's own estimate for the day. The time is the
/// next 00:00 UTC, which is when the day is cut, and it counts down so
/// the wait is a fact on screen rather than something to work out.
/// Passive text, so nothing to track.
class _NextPayment extends StatelessWidget {
  const _NextPayment({
    required this.label,
    required this.amountText,
    required this.countdownLabel,
    required this.countdownText,
    required this.c,
  });

  final String label;
  final String amountText;
  final String countdownLabel;
  final String countdownText;
  final AppColorsExtension c;

  @override
  Widget build(BuildContext context) {
    Widget column(String heading, String value, {bool alignEnd = false}) =>
        Column(
          crossAxisAlignment:
              alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              heading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                height: 1.0,
              ),
            ),
          ],
        );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: column(label, amountText)),
          SizedBox(width: 12.w),
          column(countdownLabel, countdownText, alignEnd: true),
        ],
      ),
    );
  }
}

/// The line under the curve that says the dashed part has not happened.
/// Passive text, so nothing to track.
class _ProjectionNote extends StatelessWidget {
  const _ProjectionNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: double.infinity,
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.start,
        style: TextStyle(
          color: c.textTertiary,
          fontSize: 11.sp,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// The headline above the earnings chart. Same typography and same
/// rolling cadence as the dollar balance header, with the rate parked on
/// the right: it is the one place in the app allowed to print it.
class _EarnHeader extends StatelessWidget {
  const _EarnHeader({
    required this.paidLabel,
    required this.paidText,
    required this.rateLabel,
    required this.rateText,
    required this.c,
  });

  final String paidLabel;
  final String paidText;
  final String rateLabel;
  final String rateText;
  final AppColorsExtension c;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paidLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2.h),
                Align(
                  alignment: Alignment.centerLeft,
                  child: RollingNumberText(
                    text: paidText,
                    duration: const Duration(milliseconds: 350),
                    dimColor: c.textTertiary,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rateLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                rateText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Placeholder while the ledger is on its way. Sized like the curve it
/// replaces so the card does not resize when the data lands.
class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    return Center(child: SkeletonBar(280.w, 160.h, radius: 14.r));
  }
}

/// A failed or empty read says so rather than drawing a flat line at
/// zero, which would read as "the programme has never paid you".
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
