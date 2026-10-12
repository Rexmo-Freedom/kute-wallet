// lib/screens/usd/components/usd_earn_chart.dart
//
// The Dollars tab's Earn view: what holding dollars has paid, over time,
// and what it pays next.
//
// EARN IS NOT A DOOR, IT IS A VIEW OF THE SAME BALANCE. The programme is
// passive — holding dollars pays a daily bitcoin reward on the whole
// balance, with nothing to stake and nothing to deposit into — so there
// is no separate destination to send money to and no screen to push. It
// sits under the Balance tab as the Earn pill (usd_balance_tabs.dart):
// the same [AnalyticsCard], the same [Chart] engine, the same date-range
// strip, the same scrub card. The ONLY difference is the series: the
// daily payout ledger, added up, in place of the dollar balance.
//
// THE HEADLINE IS THE NEXT PAYMENT (owner decision: "instead of the
// 'paid to you so far', just the next payment amount there"). The
// figure is the venue's own [UserRewardsSummary.estimatedSatsToday] —
// the same single number the dashed tail is built from — with the
// countdown to the payout as its quiet second line and the rate on the
// right. Said once, in the header: there is no second "next payment"
// block.
//
// PAID ONLY. The curve counts payouts the wallet has actually received.
// A pending day does not lift it until it settles, and a point out in
// the dashed tail says so on its scrub card.
//
// THE PAYOUT CLOCK IS FLASHNET'S. "Payouts are scheduled daily at 01:00
// UTC" (docs.flashnet.xyz/usdb/rewards, read 2026-10-12), so the
// countdown runs to the next 01:00 UTC, not to midnight: a UTC day is
// cut at 00:00 and paid an hour later, and between the two the next
// payment is minutes away, not a day.
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
// scrub card.
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

  @override
  void initState() {
    super.initState();
    _countdownTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _nowUtc = DateTime.now().toUtc());
    });
    // Opening the pill IS opening Earn — it replaced the pushed screen
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
    // The chart reads whatever unit the wallet is set to, because
    // [Chart] formats its own bubbles from that setting.
    final byDay = _cumulativeByDay(history?.payouts, inSats: inSats);

    // The forecast, or nothing at all. A projection with no projected
    // days is returned whenever the venue's daily estimate is missing, still loading or
    // zero, and then every value below is the untouched history.
    final projection = UsdEarnProjection.from(
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

    // The headline: what the programme pays next, in whatever unit the
    // wallet reads in. Straight from the venue's own estimate — the one
    // number the dashed tail is also built from — never the rate times
    // the balance. While the summary is on its way the slot says so,
    // and a dead service says unavailable, in the rate's own words;
    // neither is ever a zero dressed up as a payment. Under the floor
    // the venue's estimate is nothing, and the note below says why.
    final String nextPaymentText;
    if (summary != null) {
      nextPaymentText =
          '${summary.estimatedSatsToday.toFormattedString(btcFormat)} '
          '${inSats ? 'sats' : 'BTC'}';
    } else if (summaryAsync.hasError) {
      nextPaymentText = l10n.usdEarnRateUnavailable;
    } else {
      nextPaymentText = l10n.usdEarnRatePending;
    }

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
                    headlineLabel: l10n.usdEarnNextPayment,
                    headlineText: nextPaymentText,
                    countdownLabel: l10n.usdEarnNextPaymentIn,
                    countdownText: usdEarnCountdownLabel(
                        usdEarnNextPayoutUtc(_nowUtc).difference(_nowUtc)),
                    rateLabel: l10n.usdEarnRate,
                    rateText: rateText,
                    c: c,
                  ),
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

/// The next 01:00 UTC after [nowUtc]: when Flashnet pays the day that
/// was cut at the preceding midnight ("Payouts are scheduled daily at
/// 01:00 UTC", docs.flashnet.xyz/usdb/rewards). At exactly 01:00 the
/// payment is being made, so the clock already points a day ahead.
DateTime usdEarnNextPayoutUtc(DateTime nowUtc) {
  final utc = nowUtc.toUtc();
  final todayPayout = DateTime.utc(utc.year, utc.month, utc.day, 1);
  return utc.isBefore(todayPayout)
      ? todayPayout
      : DateTime.utc(utc.year, utc.month, utc.day + 1, 1);
}

/// `6h 12m 03s`, counting down. Hours are never padded, so the line
/// does not jitter between widths at the start of a day.
String usdEarnCountdownLabel(Duration left) {
  final clamped = left.isNegative ? Duration.zero : left;
  final minutes = clamped.inMinutes % 60;
  final seconds = clamped.inSeconds % 60;
  return '${clamped.inHours}h '
      '${minutes.toString().padLeft(2, '0')}m '
      '${seconds.toString().padLeft(2, '0')}s';
}

/// The days handed to [Chart] and the series behind them, with however
/// many trailing days of that series are a forecast rather than a fact.
class UsdEarnProjection {
  const UsdEarnProjection({
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
  static UsdEarnProjection from({
    required List<DateTime> days,
    required Map<DateTime, num> byDay,
    required int estimateSats,
    required bool inSats,
  }) {
    final none = UsdEarnProjection(days: days, byDay: byDay, projectedDays: 0);
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
    return UsdEarnProjection(
      days: outDays,
      byDay: outByDay,
      projectedDays: horizon,
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

/// The headline above the earnings chart: the next payment with the
/// countdown under it, and the rate — the one place in the app allowed
/// to print it — parked on the right. Same typography and same rolling
/// cadence as the dollar balance header; the countdown is the hero's
/// own "quiet second line", in the projection note's type, so the row
/// still fits a narrow phone with the rate's long label beside it.
class _EarnHeader extends StatelessWidget {
  const _EarnHeader({
    required this.headlineLabel,
    required this.headlineText,
    required this.countdownLabel,
    required this.countdownText,
    required this.rateLabel,
    required this.rateText,
    required this.c,
  });

  final String headlineLabel;
  final String headlineText;
  final String countdownLabel;
  final String countdownText;
  final String rateLabel;
  final String rateText;
  final AppColorsExtension c;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: c.textTertiary,
      fontSize: 12.sp,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = TextStyle(
      color: c.textPrimary,
      fontSize: 18.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.0,
    );

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
                  headlineLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
                SizedBox(height: 2.h),
                // Scaled down rather than clipped when the rate's label
                // leaves it short of room, as the hero amount is.
                Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: RollingNumberText(
                      text: headlineText,
                      duration: const Duration(milliseconds: 350),
                      dimColor: c.textTertiary,
                      style: valueStyle,
                    ),
                  ),
                ),
                SizedBox(height: 4.h),
                // "Pays in 6h 12m 03s": the wait as a fact on screen
                // rather than something to work out. Tabular figures so
                // the line does not shimmy as the seconds tick.
                Text(
                  '$countdownLabel $countdownText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
                style: labelStyle,
              ),
              SizedBox(height: 2.h),
              Text(
                rateText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: valueStyle,
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
