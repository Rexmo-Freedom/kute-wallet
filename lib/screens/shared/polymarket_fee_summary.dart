import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/screens/shared/money_fee_summary.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';

/// Fee curve from the CLOB V2 market, not the legacy fee-rate endpoint,
/// read through the same [polymarketFeeTermsProvider] the placement engine
/// sizes with, so the estimate here and the reserve there cannot disagree.
class PolymarketFeeSummary extends ConsumerWidget {
  const PolymarketFeeSummary(
      {super.key,
      required this.tokenId,
      required this.shares,
      required this.price,
      required this.bitcoinFirst,
      this.limit = false,
      this.hasFunds = true,
      this.showNote = true});
  final String? tokenId;
  final double shares, price;
  final bool bitcoinFirst, limit, hasFunds;

  /// The plain slip shows the figure alone; the note about how the final
  /// fee is decided belongs to Advanced (owner decision).
  final bool showNote;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hasFunds) {
      return MoneyFeeSummary(
          bitcoinFirst: bitcoinFirst, state: 'Add funds to continue');
    }
    if (shares <= 0 || !shares.isFinite) {
      return MoneyFeeSummary(
          bitcoinFirst: bitcoinFirst, state: 'Enter an amount');
    }
    if (tokenId == null ||
        tokenId!.isEmpty ||
        !price.isFinite ||
        price <= 0 ||
        price >= 1) {
      return MoneyFeeSummary(
          bitcoinFirst: bitcoinFirst, state: 'Price unavailable');
    }
    final fees = ref.watch(polymarketFeeTermsProvider(tokenId!));
    return fees.when(
      loading: () =>
          MoneyFeeSummary(bitcoinFirst: bitcoinFirst, state: 'Calculating…'),
      error: (_, __) => MoneyFeeSummary(
          bitcoinFirst: bitcoinFirst,
          state: 'Estimate unavailable',
          onRetry: () => ref.invalidate(polymarketFeeTermsProvider(tokenId!))),
      data: (f) {
        final platform = f.platformFee(shares, price);
        // A resting limit may still cross and fill as a taker.
        final builder = f.builderFee(shares, price, taker: true);
        final total = platform + builder;
        return MoneyFeeSummary(
              usd: total,
              bitcoinFirst: bitcoinFirst,
              note: !showNote
                  ? null
                  : limit
                      ? 'If filled as a taker. Maker fees may be lower.'
                      : 'Final fee depends on the fill price.',
              details: [
                MoneyFeeSummary(
                    label: 'Polymarket fee',
                    usd: platform,
                    bitcoinFirst: bitcoinFirst),
                MoneyFeeSummary(
                    label: 'Kute fee',
                    usd: builder,
                    bitcoinFirst: bitcoinFirst),
              ]);
      },
    );
  }
}
