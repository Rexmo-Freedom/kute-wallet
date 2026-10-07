import 'dart:math' as math;
import 'package:kute/screens/shared/fee_copy.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/historical_price_provider.dart';
import 'package:kute/theme/app_theme.dart';

/// Average-cost Bitcoin counterfactual for precisely the shares exited in
/// this event. Earlier sells reduce the pool proportionally. The outcome is
/// frozen at the exit date, never recomputed using today's BTC price.
final polymarketBitcoinComparisonProvider = FutureProvider.autoDispose
    .family<double?, PolymarketTransaction>((ref, target) async {
  final a = target.activity;
  final side = (a.side ?? '').toUpperCase();
  final open = side == 'BUY';
  if (!open && side != 'SELL' && target.activityType.name != 'redeem') {
    return null;
  }
  final positions = open
      ? ref.watch(polymarketTradingProvider).valueOrNull?.openPositions
      : null;
  final btcNow =
      open ? ref.watch(selectedCurrencyProvider('USD')).toDouble() : 0.0;
  final history = ref
      .watch(transactionNotifierProvider)
      .polymarketTransactions
      .where((t) =>
          t.activity.conditionId == a.conditionId &&
          (a.asset?.isNotEmpty == true
              ? t.activity.asset == a.asset
              : t.activity.outcomeIndex == a.outcomeIndex) &&
          (open || !t.timestamp.isAfter(target.timestamp)))
      .toList()
    ..sort((x, y) => x.timestamp.compareTo(y.timestamp));
  await prewarmBtcPriceHistory();
  double units = 0, bitcoin = 0;
  for (final t in history) {
    final trade = t.activity;
    final tradeSide = (trade.side ?? '').toUpperCase();
    if (tradeSide == 'BUY' && trade.size > 0 && trade.usdcSize > 0) {
      final rate = await ref
          .watch(historicalBtcPriceProvider(t.timestamp.toUtc()).future);
      if (rate == null || rate <= 0) {
        return null;
      }
      units += trade.size;
      bitcoin += trade.usdcSize / rate;
    } else if (tradeSide == 'SELL' || t.activityType.name == 'redeem') {
      if (units <= 0 || bitcoin <= 0) {
        return null;
      }
      final quantity = trade.size > 0
          ? trade.size
          : (t.activityType.name == 'redeem' ? units : 0.0);
      if (quantity <= 0 || quantity > units + 1e-6) {
        return null;
      }
      final fraction = (quantity / units).clamp(0.0, 1.0);
      if (!open && t.id == target.id) {
        final rate = await ref
            .watch(historicalBtcPriceProvider(target.timestamp.toUtc()).future);
        if (rate == null || rate <= 0) {
          return null;
        }
        final heldValue = bitcoin * fraction * rate;
        return heldValue > 0 ? (target.usdcAmount / heldValue - 1) * 100 : null;
      }
      bitcoin *= 1 - fraction;
      units -= quantity;
    }
  }
  if (open && units > 0 && bitcoin > 0 && btcNow > 0 && positions != null) {
    for (final position in positions) {
      if (position.asset != a.asset) {
        continue;
      }
      // Transfers or incomplete history must not masquerade as returns.
      // The tolerance is real though: the venue reports a rounded size
      // and the trade sizes it is compared against are rounded too, so
      // an exact match asked for a precision neither number carries and
      // an ordinary position read as unavailable. Half a percent, floor
      // one hundredth of a share, still catches a position that holds
      // shares this history never bought.
      final drift = (position.size - units).abs();
      final tolerance = math.max(0.01, units * 0.005);
      if (drift > tolerance || !position.curPrice.isFinite) {
        return null;
      }
      return (position.size * position.curPrice / (bitcoin * btcNow) - 1) * 100;
    }
  }
  return null;
});

class BitcoinPerformanceComparison extends StatelessWidget {
  const BitcoinPerformanceComparison(
      {super.key,
      this.percent,
      this.loading = false,
      this.label = 'vs holding Bitcoin',
      this.unavailable = 'Entry history unavailable',
      this.note = 'Estimated · daily Bitcoin prices · before fees'});
  final double? percent;
  final bool loading;
  final String label, unavailable, note;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = percent;
    final valid = p != null && p.isFinite;
    final value = !valid
        ? (loading ? 'Calculating…' : unavailable)
        : '${p >= 0 ? '+' : '−'}${p.abs().toStringAsFixed(1)}%';
    return Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // The value sits at the row's right edge, like every other
            // detail row.
            Expanded(
                child: Text(feeCopy(context, label),
                    style: TextStyle(color: c.textSecondary, fontSize: 13.sp))),
            SizedBox(width: 12.w),
            Text(feeCopy(context, value),
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: valid
                        ? (p >= 0 ? AppColors.marketUp : AppColors.marketDown)
                        : c.textTertiary)),
          ]),
          if (valid)
            Padding(
                padding: EdgeInsets.only(top: 4.h),
                child: Text(
                    '${feeCopy(context, p >= 0 ? 'Ahead of holding Bitcoin.' : 'Behind holding Bitcoin.')} ${feeCopy(context, note)}',
                    style: TextStyle(
                        color: c.textTertiary, fontSize: 11.sp, height: 1.35))),
        ]));
  }
}

class PolymarketBitcoinComparison extends ConsumerWidget {
  const PolymarketBitcoinComparison({super.key, required this.transaction});
  final PolymarketTransaction transaction;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closed = transaction.activity.side?.toUpperCase() == 'SELL' ||
        transaction.activityType.name == 'redeem';
    final result = ref.watch(polymarketBitcoinComparisonProvider(transaction));
    // Shown only once there is an answer: a comparison whose price history
    // never arrives must not sit on "Calculating…" forever, and one that
    // cannot be made has nothing to say on a detail sheet.
    final percent = result.valueOrNull;
    if (percent == null || !percent.isFinite) return const SizedBox.shrink();
    return BitcoinPerformanceComparison(
        percent: result.valueOrNull,
        loading: result.isLoading,
        label: closed ? 'vs holding Bitcoin' : 'Position vs holding Bitcoin',
        note: closed
            ? 'Estimated · daily Bitcoin prices · before fees'
            : 'Current position · daily entry Bitcoin prices · before fees');
  }
}
