import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, kOrchestraUsdChain;

/// The Orchestra estimate the Move sheet samples for its bitcoin price.
///
/// The sample has to travel the SAME direction as the move. A withdrawal
/// out of Investing or Predictions samples the venue's exit leg, which the
/// backend gates on `hyperliquid.withdraw` / `polymarket.withdraw` alone.
/// It used to sample the deposit leg on every move, so a country blocked
/// from funding a venue (the UK) saw "Price unavailable" on every
/// withdrawal although withdrawals are allowed everywhere.
class MoveRateSample {
  const MoveRateSample({
    required this.sourceChain,
    required this.sourceAsset,
    required this.destinationChain,
    required this.destinationAsset,
    required this.amount,
    required this.reverse,
  });

  final String sourceChain, sourceAsset, destinationChain, destinationAsset;

  /// Raw Orchestra base units of [sourceAsset].
  final String amount;

  /// Dollars in, bitcoin out (a venue withdrawal).
  final bool reverse;

  static const sampleSats = 100000;
  static const sampleUsd = 100.0;

  /// Dollars per bitcoin from the estimate's raw [estimatedOut], or null
  /// when the figure is not a usable price.
  double? usdPerBtc(String estimatedOut) {
    final out = orchestraAmountToDouble(estimatedOut, destinationAsset,
        chain: destinationChain);
    final rate = reverse
        ? (out > 0 ? sampleUsd / out : double.nan)
        : out / (sampleSats / 1e8);
    return rate.isFinite && rate > 0 ? rate : null;
  }
}

/// Picks the sample for a move. [venueSource] is a withdrawal out of a
/// venue: Investing when [fromHyperliquid], otherwise Predictions.
MoveRateSample moveRateSample({
  required bool ledger,
  required bool venueSource,
  required bool fromHyperliquid,
  required bool investing,
  required bool buyingDollars,
}) {
  if (venueSource) {
    final chain = fromHyperliquid ? 'hypercore' : 'polygon';
    final asset = fromHyperliquid ? 'USDC' : 'USDC.e';
    return MoveRateSample(
      sourceChain: chain,
      sourceAsset: asset,
      // Only the price is read, so the person's own Spark bitcoin is the
      // destination for every withdrawal, Ledger included.
      destinationChain: 'spark',
      destinationAsset: 'BTC',
      amount: doubleToOrchestraAmount(MoveRateSample.sampleUsd, asset,
          chain: chain),
      reverse: true,
    );
  }
  return MoveRateSample(
    sourceChain: ledger ? 'bitcoin' : 'spark',
    sourceAsset: 'BTC',
    destinationChain: buyingDollars
        ? kOrchestraUsdChain
        : investing
            ? 'hypercore'
            : 'polygon',
    destinationAsset: buyingDollars
        ? kOrchestraUsdAssetCode
        : investing
            ? 'USDC'
            : 'USDC.e',
    amount: MoveRateSample.sampleSats.toString(),
    reverse: false,
  );
}
