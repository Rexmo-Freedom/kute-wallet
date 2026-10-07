import 'dart:math' as math;
import 'package:kute/models/orchestra_model.dart';

/// Display amounts from the provider's total fee. Never reconstruct the total
/// from feeBps: minimum, affiliate, rounding and route costs are missing there.
/// https://docs.flashnet.xyz/orchestra/fees
class OrchestraFeeAmount {
  const OrchestraFeeAmount({this.usd, this.sats});
  final double? usd, sats;
  bool get isAvailable => usd != null || sats != null;
}

OrchestraFeeAmount orchestraFeeAmount(OrchestraEstimate quote) {
  final usd = _nonnegative(quote.totalFeeAmountUsd);
  final raw = _rawInteger(quote.totalFeeAmount);
  if (usd == 0 && raw != null && raw > BigInt.zero) {
    return const OrchestraFeeAmount();
  }
  final details = quote.feeAssetDetails;
  final matchingAsset = details != null &&
      quote.feeAsset?.toUpperCase() == details.asset.toUpperCase();
  double? sats;
  double? stableUsd;
  if (raw != null && matchingAsset) {
    final units = raw.toDouble() / math.pow(10, details.decimals);
    if (units.isFinite) {
      if (details.asset.toUpperCase() == 'BTC') {
        final value = units * 1e8;
        if (value.isFinite) sats = value;
      } else if (const {'USDC', 'USDC.E', 'USDT', 'USDB', 'USD'}
          .contains(details.asset.toUpperCase())) {
        stableUsd = units;
      }
    }
  }
  // A provider's explicit USD valuation also supports fees in other assets.
  // When both fields describe a stablecoin they must agree; an inconsistent
  // near-zero USD field must not hide a positive, correctly scaled raw fee.
  if (usd != null &&
      stableUsd != null &&
      (usd - stableUsd).abs() > math.max(0.000001, stableUsd.abs() * .02)) {
    return const OrchestraFeeAmount();
  }
  return OrchestraFeeAmount(usd: usd ?? stableUsd, sats: sats);
}

/// Destination amount is already net of the route's quoted conversion pricing.
/// It must never have the fee subtracted a second time.
OrchestraFeeAmount orchestraReceiveAmount(OrchestraEstimate quote,
    {required String destinationChain, required String destinationAsset}) {
  final details = quote.destination;
  final raw = _rawInteger(quote.estimatedOut);
  if (raw == null ||
      details == null ||
      details.chain.toLowerCase() != destinationChain.toLowerCase() ||
      details.asset.toUpperCase() != destinationAsset.toUpperCase()) {
    return const OrchestraFeeAmount();
  }
  final units = raw.toDouble() / math.pow(10, details.decimals);
  if (!units.isFinite) return const OrchestraFeeAmount();
  if (details.asset.toUpperCase() == 'BTC') {
    final sats = units * 1e8;
    return sats.isFinite
        ? OrchestraFeeAmount(sats: sats)
        : const OrchestraFeeAmount();
  }
  return const {'USDC', 'USDC.E', 'USDT', 'USDB', 'USD'}
          .contains(details.asset.toUpperCase())
      ? OrchestraFeeAmount(usd: units)
      : const OrchestraFeeAmount();
}

/// Kute's rate on this estimate as a fraction, or null when the backend
/// reported none or an impossible value. Unknown is never zero.
double? orchestraKuteFeeRate(OrchestraEstimate quote) {
  final bps = quote.kuteAppFeeBps;
  if (bps == null || bps < 0 || bps >= 10000) return null;
  return bps / 10000;
}

/// Whether the estimate's output still carries the Kute fee. A missing header
/// reads as excluded, the way the backend reports its policy.
bool _excludesKuteFee(OrchestraEstimate quote) =>
    quote.estimateIncludesAppFee != true;

/// The Kute fee on this estimate, in the destination's unit. The provider
/// charges the Kute rate on what remains after its own fee and takes it out of
/// that amount (https://docs.flashnet.xyz/orchestra/fees). The quoted output
/// is the closest known base for that remainder: an estimate that leaves the
/// Kute fee out is the gross base, and one that already deducted it is the
/// base times one minus the rate. Null when the rate or the output is
/// unknown, never zero.
OrchestraFeeAmount orchestraKuteFeeAmount(OrchestraEstimate quote,
    {required String destinationChain, required String destinationAsset}) {
  final rate = orchestraKuteFeeRate(quote);
  if (rate == null) return const OrchestraFeeAmount();
  final out = orchestraReceiveAmount(quote,
      destinationChain: destinationChain, destinationAsset: destinationAsset);
  return _scaled(out, _excludesKuteFee(quote) ? rate : rate / (1 - rate));
}

/// [estimatedOut], the estimate's output already read in the destination
/// coin's own units (any coin, not only bitcoin and dollars), less the Kute
/// fee when the estimate leaves it out. The `/estimate` the backend serves
/// strips the app fee and says so (`X-Kute-Estimate-Includes-App-Fee:
/// false`), while the quote that is paid takes it, so a "You receive" built
/// on the raw figure reads high by exactly the Kute rate. Null when the rate
/// is unknown and the estimate excludes it: there is no honest net figure.
double? orchestraOutNetOfKuteFee(OrchestraEstimate quote, double estimatedOut) {
  if (!estimatedOut.isFinite || estimatedOut < 0) return null;
  if (!_excludesKuteFee(quote)) return estimatedOut;
  final rate = orchestraKuteFeeRate(quote);
  if (rate == null) return null;
  return estimatedOut * (1 - rate);
}

/// What arrives after every fee, in the destination's unit: the provider's
/// output as quoted when the Kute fee is already inside it, otherwise that
/// output less the Kute fee. Unavailable while the Kute rate is unknown, so a
/// gross figure is never shown as the net one.
OrchestraFeeAmount orchestraNetReceiveAmount(OrchestraEstimate quote,
    {required String destinationChain, required String destinationAsset}) {
  final out = orchestraReceiveAmount(quote,
      destinationChain: destinationChain, destinationAsset: destinationAsset);
  if (!_excludesKuteFee(quote)) return out;
  final rate = orchestraKuteFeeRate(quote);
  if (rate == null) return const OrchestraFeeAmount();
  return _scaled(out, 1 - rate);
}

/// The whole cost of the conversion in the destination's own unit: the
/// value that went in, less what actually arrives. The provider's
/// `totalFeeAmount` covers only its own rate; the route's fixed costs
/// (destination gas, bridging) are already inside `estimatedOut` and
/// appear nowhere in that figure, so a fee row built from it could read
/// two cents on a transfer that lost a dollar twenty (owner report:
/// "the fees and the you receive have a mismatch").
///
/// [inputValueInDestinationUnits] is the amount sent valued at the app's
/// own price, in the same unit [orchestraNetReceiveAmount] answers in:
/// dollars for a stablecoin destination, sats for bitcoin. Unavailable
/// without that value, and unavailable when it comes out negative, which
/// means the reference price and the quote disagree rather than that the
/// route is free.
OrchestraFeeAmount orchestraTotalCostAmount(
  OrchestraEstimate quote, {
  required String destinationChain,
  required String destinationAsset,
  required double? inputValueInDestinationUnits,
}) {
  final input = inputValueInDestinationUnits;
  if (input == null || !input.isFinite || input <= 0) {
    return const OrchestraFeeAmount();
  }
  final net = orchestraNetReceiveAmount(quote,
      destinationChain: destinationChain, destinationAsset: destinationAsset);
  final usd = net.usd, sats = net.sats;
  if (usd != null) {
    final cost = input - usd;
    return cost.isFinite && cost >= 0
        ? OrchestraFeeAmount(usd: cost)
        : const OrchestraFeeAmount();
  }
  if (sats != null) {
    final cost = input - sats;
    return cost.isFinite && cost >= 0
        ? OrchestraFeeAmount(sats: cost)
        : const OrchestraFeeAmount();
  }
  return const OrchestraFeeAmount();
}

/// [a] plus [b] in every unit both carry. Amounts in different units are
/// bridged with [usdPerBtc], the app's own display price; without it the sum
/// is unavailable rather than silently partial.
OrchestraFeeAmount orchestraFeeSum(OrchestraFeeAmount a, OrchestraFeeAmount b,
        {double? usdPerBtc}) =>
    _combine(a, b, usdPerBtc, (x, y) => x + y);

/// [total] less [part], bridged like [orchestraFeeSum]. Unavailable when the
/// part exceeds the total, which means the two do not describe the same fee.
OrchestraFeeAmount orchestraFeeDifference(
    OrchestraFeeAmount total, OrchestraFeeAmount part,
    {double? usdPerBtc}) {
  final result = _combine(total, part, usdPerBtc, (x, y) => x - y);
  if ((result.usd ?? 0) < 0 || (result.sats ?? 0) < 0) {
    return const OrchestraFeeAmount();
  }
  return result;
}

/// Fee shares of the amount sent under a final quote, as the provider applies
/// them: its own rate on the input, then the Kute rate on what remains. The
/// Kute share is null when the quote carried no app fee list.
({double provider, double? kute}) orchestraQuoteFeeShares(
    OrchestraQuote quote) {
  final provider = math.min(1.0, math.max(0, quote.feeBps) / 10000);
  final appBps = quote.appFeeBps;
  final kute =
      appBps == null || appBps < 0 ? null : (1 - provider) * appBps / 10000;
  return (provider: provider, kute: kute);
}

/// The provider and Kute fees under a final quote in the unit [amountIn] is
/// given in (sats for a bitcoin source), as [orchestraQuoteFeeShares] applies
/// them. [total] is what a review's "Fees" headline states: both parts, never
/// the provider's rate alone while the Kute fee hides as a percentage.
({double provider, double? kute, double total}) orchestraQuoteFeeAmounts(
    OrchestraQuote quote, num amountIn) {
  final shares = orchestraQuoteFeeShares(quote);
  final amount = amountIn.toDouble();
  final provider = amount * shares.provider;
  final kute = shares.kute == null ? null : amount * shares.kute!;
  return (provider: provider, kute: kute, total: provider + (kute ?? 0));
}

OrchestraFeeAmount _scaled(OrchestraFeeAmount amount, double factor) {
  if (!factor.isFinite || factor < 0) return const OrchestraFeeAmount();
  double? scale(double? value) {
    if (value == null) return null;
    final result = value * factor;
    return result.isFinite ? result : null;
  }

  return OrchestraFeeAmount(usd: scale(amount.usd), sats: scale(amount.sats));
}

OrchestraFeeAmount _combine(OrchestraFeeAmount a, OrchestraFeeAmount b,
    double? usdPerBtc, double Function(double, double) op) {
  if (!a.isAvailable || !b.isAvailable) return const OrchestraFeeAmount();
  final rate =
      usdPerBtc != null && usdPerBtc.isFinite && usdPerBtc > 0 ? usdPerBtc : null;
  double? usdOf(OrchestraFeeAmount x) =>
      x.usd ?? (x.sats != null && rate != null ? x.sats! / 1e8 * rate : null);
  double? satsOf(OrchestraFeeAmount x) =>
      x.sats ?? (x.usd != null && rate != null ? x.usd! / rate * 1e8 : null);
  double? apply(double? x, double? y) {
    if (x == null || y == null) return null;
    final result = op(x, y);
    return result.isFinite ? result : null;
  }

  return OrchestraFeeAmount(
      usd: apply(usdOf(a), usdOf(b)), sats: apply(satsOf(a), satsOf(b)));
}

BigInt? _rawInteger(String? value) {
  if (value == null || !RegExp(r'^\d+$').hasMatch(value)) return null;
  return BigInt.tryParse(value);
}

double? _nonnegative(String? value) {
  final number = double.tryParse(value ?? '');
  return number != null && number.isFinite && number >= 0 ? number : null;
}
