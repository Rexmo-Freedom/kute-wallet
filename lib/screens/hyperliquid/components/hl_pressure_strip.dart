// lib/screens/hyperliquid/components/hl_pressure_strip.dart
//
// The buy/sell pressure strip directly under the Hyperliquid chart: one
// thin bar, the bought share of the last five minutes' traded notional in
// the up colour and the sold share in the down colour. No labels and no
// numbers. It is always one full bar: until enough trades have printed
// in the window (kHlPressureMinTrades) it is not there at all, rather
// than an empty or half-drawn line.
//
// Source: the public `trades` stream (hyperliquidTradeFlowProvider). It
// is a small widget of its own rather than the Predictions momentum strip
// (momentum_strip.dart), which is a titled, captioned section for a
// two-sided game and far heavier than this needs to be.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/providers/hyperliquid_insights_provider.dart';
import 'package:kute/theme/app_theme.dart';

class HlPressureStrip extends ConsumerWidget {
  /// The market's WIRE coin.
  final String wireCoin;

  const HlPressureStrip({super.key, required this.wireCoin});

  static const double _height = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final share = ref.watch(hyperliquidTradeFlowProvider(wireCoin)
        .select((s) => s.valueOrNull?.pressure?.buyShare));
    if (share == null) return const SizedBox.shrink();
    // Whole per-mille parts: Flexible needs integers of at least one.
    final buy = (share * 1000).round().clamp(1, 999);
    return Padding(
      padding: EdgeInsets.only(top: 8.h),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_height / 2),
        child: SizedBox(
          height: _height,
          width: double.infinity,
          child: Row(
            children: [
              Expanded(
                flex: buy,
                child: ColoredBox(
                    color: AppColors.marketUp.withValues(alpha: 0.6)),
              ),
              Expanded(
                flex: 1000 - buy,
                child: ColoredBox(
                    color: AppColors.marketDown.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
