// lib/services/polymarket/combos/combo_math.dart
//
// Pure combo arithmetic: quote multiplier and fees, settlement payout and
// the ESTIMATED value of an open combo. Nothing here touches the network.
//
// Settlement (docs.polymarket.com/trading/positions/combinatorial): a combo
// YES share pays the product of its legs' payouts. A winning leg pays 1, a
// losing leg 0 (so any loss zeroes the combo) and a voided leg 0.5 (halving
// it). There is no combo price feed, so an open combo is valued at the
// product of its legs' live prices. That is an estimate and every surface
// labels it as one; a SELL RFQ is the only exact exit price.

import 'package:kute/models/polymarket_model.dart' show PolymarketPricePoint;

final BigInt _e6 = BigInt.from(1000000);

double e6ToDouble(BigInt v) => v.toDouble() / 1e6;

/// USD → 6-decimal base units, rounded down (a budget never rounds up past
/// what the user typed). The tiny nudge keeps 0.29 * 1e6 = 289999.99… at
/// 290000.
BigInt usdToE6Floor(double usd) {
  if (!usd.isFinite || usd <= 0) return BigInt.zero;
  return BigInt.from((usd * 1e6 + 1e-6).floor());
}

/// Payout ÷ cost. For a BUY quote: `net_receive_e6` (shares, $1 each if
/// every leg wins; equal to `taker_amount_e6`) over `total_required_e6`
/// (the stake, fees included). Zero when there is no cost.
double comboMultiplier({required BigInt payoutE6, required BigInt costE6}) {
  if (costE6 <= BigInt.zero || payoutE6 <= BigInt.zero) return 0;
  return payoutE6.toDouble() / costE6.toDouble();
}

/// BUY fee: the stake above the order's own collateral.
BigInt comboBuyFeeE6(
    {required BigInt totalRequiredE6, required BigInt makerAmountE6}) {
  final fee = totalRequiredE6 - makerAmountE6;
  return fee.isNegative ? BigInt.zero : fee;
}

/// SELL fee: the order's gross collateral above the net proceeds.
BigInt comboSellFeeE6(
    {required BigInt takerAmountE6, required BigInt netReceiveE6}) {
  final fee = takerAmountE6 - netReceiveE6;
  return fee.isNegative ? BigInt.zero : fee;
}

/// Payout of [sharesE6] combo shares at settlement factor [factor]
/// (rounded down to the base unit, as the chain pays).
BigInt comboPayoutE6({required BigInt sharesE6, required double factor}) {
  if (factor <= 0 || sharesE6 <= BigInt.zero) return BigInt.zero;
  // factor is a product of 1 / 0.5 terms: 1 / 2^n exactly.
  var halvings = 0;
  var f = factor;
  while (f < 1 - 1e-12 && halvings < 64) {
    f *= 2;
    halvings++;
  }
  if ((f - 1).abs() < 1e-9) return sharesE6 >> halvings;
  return BigInt.from((sharesE6.toDouble() * factor).floor());
}

/// A leg's mark: its live outcome price while open, its payout once
/// resolved (1 won, 0 lost, 0.5 void).
class ComboLegMark {
  const ComboLegMark({required this.resolved, required this.price});
  final bool resolved;
  final double price;

  /// A resolved leg's payout, snapped to the three values the protocol
  /// pays so a 0.9999 mark never reads as a fractional payout.
  double get payout {
    if (price >= 0.99) return 1;
    if (price <= 0.01) return 0;
    return 0.5;
  }
}

/// The settled payout per share: null while any leg is still open, except
/// that a single lost leg settles the combo at 0 straight away.
double? comboSettlementFactor(List<ComboLegMark> legs) {
  if (legs.isEmpty) return null;
  var factor = 1.0;
  var open = false;
  for (final leg in legs) {
    if (!leg.resolved) {
      open = true;
      continue;
    }
    final p = leg.payout;
    if (p == 0) return 0;
    factor *= p;
  }
  return open ? null : factor;
}

/// Payout per share if every open leg wins: resolved legs at their payout,
/// open legs at 1.
double comboBestCaseFactor(List<ComboLegMark> legs) {
  var factor = 1.0;
  for (final leg in legs) {
    if (!leg.resolved) continue;
    factor *= leg.payout;
  }
  return legs.isEmpty ? 0 : factor;
}

/// ESTIMATED value: shares × product of the legs' marks (open legs at their
/// live price, resolved legs at their payout).
double comboEstimatedValue(
    {required double shares, required List<ComboLegMark> legs}) {
  if (legs.isEmpty || shares <= 0) return 0;
  var factor = 1.0;
  for (final leg in legs) {
    final p = leg.resolved ? leg.payout : leg.price.clamp(0.0, 1.0);
    factor *= p;
  }
  return shares * factor;
}

/// ESTIMATED combo price series: the product of the legs' price histories.
/// Each leg is carried forward from its last point; the series starts once
/// every leg has a point, and has one point per distinct timestamp.
List<PolymarketPricePoint> comboEstimateSeries(
    List<List<PolymarketPricePoint>> legSeries) {
  if (legSeries.isEmpty || legSeries.any((s) => s.isEmpty)) return const [];
  final sorted = [
    for (final s in legSeries)
      ([...s]..sort((a, b) => a.timestamp.compareTo(b.timestamp))),
  ];
  final stamps = <int>{
    for (final s in sorted)
      for (final p in s) p.timestamp.millisecondsSinceEpoch,
  }.toList()
    ..sort();
  final cursor = List<int>.filled(sorted.length, -1);
  final out = <PolymarketPricePoint>[];
  for (final t in stamps) {
    var ready = true;
    var product = 1.0;
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      while (cursor[i] + 1 < s.length &&
          s[cursor[i] + 1].timestamp.millisecondsSinceEpoch <= t) {
        cursor[i]++;
      }
      if (cursor[i] < 0) {
        ready = false;
        break;
      }
      product *= s[cursor[i]].price.clamp(0.0, 1.0);
    }
    if (!ready) continue;
    out.add(PolymarketPricePoint(
      timestamp: DateTime.fromMillisecondsSinceEpoch(t),
      price: product,
    ));
  }
  return out;
}

/// The quote's implied price per share in base units, for sanity checks:
/// maker ÷ taker for a BUY, taker ÷ maker for a SELL (×1e6).
BigInt comboOrderPriceE6({
  required bool isBuy,
  required BigInt makerAmountE6,
  required BigInt takerAmountE6,
}) {
  final num = isBuy ? makerAmountE6 : takerAmountE6;
  final den = isBuy ? takerAmountE6 : makerAmountE6;
  if (den <= BigInt.zero) return BigInt.zero;
  return num * _e6 ~/ den;
}
