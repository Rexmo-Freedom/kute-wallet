import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';

/// Native Hyperliquid trailing-stop parameters. The public exchange app uses
/// this L1 action (not a synthetic trigger maintained by the phone).
/// Wire contract checked against https://app.hyperliquid.xyz/ on 2026-09-27;
/// the exchange-endpoint documentation does not yet describe this action.
class HlTrailingStop {
  const HlTrailingStop(
      {required this.retracement, this.percent = true, this.activationPrice});
  final double retracement;
  final bool percent;
  final double? activationPrice;

  void validate(
      {required HlMarket market,
      required bool isBuy,
      required double referencePrice}) {
    if (market.isSpot || !referencePrice.isFinite || referencePrice <= 0) {
      throw ArgumentError('Trailing stops require a perpetual market price.');
    }
    if (!retracement.isFinite ||
        retracement <= 0 ||
        (percent &&
            (retracement >= 100 ||
                double.parse(retracement.toStringAsFixed(4)) != retracement))) {
      throw ArgumentError('Enter a positive trailing distance below 100%.');
    }
    final activation = activationPrice;
    if (activation != null &&
        (!activation.isFinite ||
            activation <= 0 ||
            (isBuy
                ? activation >= referencePrice
                : activation <= referencePrice))) {
      throw ArgumentError(isBuy
          ? 'Activation price must be below the current market price.'
          : 'Activation price must be above the current market price.');
    }
  }

  Map<String, Object?> get intentFields => {
        'trailingRetracement': retracement,
        'trailingPercent': percent,
        'trailingActivation': activationPrice,
      };

  /// Insertion order is part of Hyperliquid's MsgPack signature. Percent
  /// distances use four decimals AND the percent suffix in the venue app.
  Map<String, dynamic> action(
          {required HlMarket market,
          required bool isBuy,
          required String size,
          required bool reduceOnly}) =>
      {
        'type': 'trailingStop',
        'asset': market.assetId,
        'isBuy': isBuy,
        'sz': size,
        'reduceOnly': reduceOnly,
        'retracement': percent
            ? {'pct': '${retracement.toStringAsFixed(4)}%'}
            : {'px': floatToWire(retracement)},
        'activationPx':
            activationPrice == null ? null : floatToWire(activationPrice!),
      };
}
