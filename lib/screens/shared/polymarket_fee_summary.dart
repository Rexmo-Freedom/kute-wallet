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
      this.showNote = true,
      this.moveFeeUsd,
      this.moveFeeLabel = 'Move fee',
      this.moveFeePending = false,
      this.moveLegs = const []});
  final String? tokenId;
  final double shares, price;
  final bool bitcoinFirst, limit, hasFunds;

  /// The plain slip shows the figure alone; the note about how the final
  /// fee is decided belongs to Advanced (owner decision).
  final bool showNote;

  /// One balance: what moving the bet's shortfall from Dollars costs.
  /// Added to the total and listed as one [moveFeeLabel] detail row, so
  /// the slip shows the whole cost of the bet in the one fee row. Null
  /// while no money has to move.
  final double? moveFeeUsd;
  final String moveFeeLabel;

  /// The move is needed but its cost is still being read: the total
  /// reads "Calculating…" until it is.
  final bool moveFeePending;

  /// A move funded from more than Dollars (Bitcoin, the other venue's
  /// cash, every leg at once): each leg's fee as its own line in the
  /// breakdown, in place of the one [moveFeeLabel] line. [moveFeeUsd] is
  /// then their sum.
  final List<MoneyFeeLeg> moveLegs;
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
    final moveFee = moveFeeUsd;
    final moving = moveFeePending || moveFee != null;
    // The move's own cost, known or still being read, as the row's one
    // detail: kept even while the venue curve is loading or unavailable.
    // A move from more than Dollars lists every leg's fee, one line each.
    final moveDetails = !moving
        ? const <Widget>[]
        : moveLegs.isNotEmpty && moveFee != null
            ? [
                for (final leg in moveLegs)
                  MoneyFeeSummary(
                      label: leg.label,
                      usd: leg.usd,
                      bitcoinFirst: bitcoinFirst),
              ]
            : [
                MoneyFeeSummary(
                    label: moveFeeLabel,
                    usd: moveFee,
                    state: moveFee == null ? 'Calculating…' : null,
                    bitcoinFirst: bitcoinFirst),
              ];
    return fees.when(
      loading: () => MoneyFeeSummary(
          bitcoinFirst: bitcoinFirst,
          state: 'Calculating…',
          details: moveDetails),
      error: (_, __) => MoneyFeeSummary(
          bitcoinFirst: bitcoinFirst,
          state: 'Estimate unavailable',
          onRetry: () => ref.invalidate(polymarketFeeTermsProvider(tokenId!)),
          details: moveDetails),
      data: (f) {
        final platform = f.platformFee(shares, price);
        // A resting limit may still cross and fill as a taker.
        final builder = f.builderFee(shares, price, taker: true);
        final total = platform + builder + (moveFee ?? 0);
        return MoneyFeeSummary(
              usd: moveFeePending ? null : total,
              state: moveFeePending ? 'Calculating…' : null,
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
                ...moveDetails,
              ]);
      },
    );
  }
}
