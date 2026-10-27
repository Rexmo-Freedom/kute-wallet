/// The whole cents a market buy of [spendUsd] signs, in micro-pUSD: the
/// stake to the cent, never more. Float noise (4.9999999 for a typed
/// \$5.00) is absorbed, never truncated to a cent less.
BigInt polymarketMarketBuyBudgetMicros(double spendUsd) {
  if (!spendUsd.isFinite || spendUsd <= 0) return BigInt.zero;
  return BigInt.from((spendUsd * 100 + 1e-6).floor()) * BigInt.from(10000);
}

/// Integer amount encoding for the CLOB's documented price increments.
/// https://docs.polymarket.com/trading/place-orders
class PolymarketOrderAmounts {
  const PolymarketOrderAmounts._(this.maker, this.taker);

  final BigInt maker;
  final BigInt taker;

  /// Market prices are bounds: round buys down and sells up to a tick.
  /// A resting limit must already be tick-aligned, otherwise it needs a
  /// new review. Rounding can never increase spend/shares or worsen price.
  ///
  /// [spendUsd]: a market buy's stake. The order spends exactly that, to
  /// the cent ([polymarketMarketBuyBudgetMicros]), the way Polymarket's own
  /// clients sign a market buy (maker = the dollar amount). Without it the
  /// budget was [size] (shares floored to a hundredth) × price floored to
  /// the cent, so a typed \$5.00 at 37¢ signed 13.51 × 0.37 = \$4.9987 →
  /// \$4.99, and the receipt said \$4.99 (founder, 27 October 2026).
  static PolymarketOrderAmounts encode({
    required String tickSize,
    required double price,
    required double size,
    required bool isBuy,
    required bool isMarket,
    double? spendUsd,
  }) {
    final (tickMicros, amountDecimals) = switch (tickSize) {
      '0.1' => (100000, 3),
      '0.01' => (10000, 4),
      '0.005' => (5000, 5),
      '0.0025' => (2500, 6),
      '0.001' => (1000, 5),
      '0.0001' => (100, 6),
      _ => throw const FormatException('Unsupported market price increment'),
    };
    if (!price.isFinite ||
        price <= 0 ||
        price >= 1 ||
        !size.isFinite ||
        size <= 0 ||
        size > 9000000000) {
      throw const FormatException('Invalid order price or size');
    }

    final ticks = price * 1000000 / tickMicros;
    final nearest = ticks.round();
    // This tolerance absorbs binary-double representation only; it is
    // much smaller than the smallest supported tick (0.0001).
    final aligned = (ticks - nearest).abs() <= 1e-9;
    if (!isMarket && !aligned) {
      throw const FormatException(
          'Limit price does not match the current market increment; review the order again');
    }
    final steps = aligned ? nearest : (isBuy ? ticks.floor() : ticks.ceil());
    final priceMicros = BigInt.from(steps * tickMicros);
    final scale = BigInt.from(1000000);
    if (priceMicros < BigInt.from(tickMicros) ||
        priceMicros > scale - BigInt.from(tickMicros)) {
      throw const FormatException('Price is outside the market limits');
    }

    // Shares support two decimal places. Restore an exact cent-share
    // only when floating-point multiplication introduced representation
    // noise; otherwise floor so an exit never exceeds the approved size.
    final centShares = size * 100;
    final nearestShares = centShares.round();
    final shareUnits = (centShares - nearestShares).abs() <= 1e-8
        ? nearestShares
        : centShares.floor();
    final shareMicros = BigInt.from(shareUnits) * BigInt.from(10000);
    final quoteMicros = shareMicros * priceMicros ~/ scale;
    if (shareMicros <= BigInt.zero || quoteMicros <= BigInt.zero) {
      throw const FormatException('Order rounds to zero');
    }

    if (isBuy && isMarket) {
      // Market buys spend whole cents. Round the resulting share amount
      // UP at the permitted precision, so maker/taker cannot cross the
      // reviewed maximum price. Since shareMicros is a multiple of that
      // precision and the budget is floored, taker never exceeds it.
      final cent = BigInt.from(10000);
      final stake = spendUsd == null
          ? null
          : polymarketMarketBuyBudgetMicros(spendUsd);
      final budget = stake ?? quoteMicros ~/ cent * cent;
      final quantum = BigInt.from(10).pow(6 - amountDecimals);
      final divisor = priceMicros * quantum;
      final shares =
          (budget * scale + divisor - BigInt.one) ~/ divisor * quantum;
      // A stake-sized buy may ask a share fraction past the floored
      // [size] (that is the point); never more than one quantum past
      // what the stake buys at the price.
      final shareCap = stake == null
          ? shareMicros
          : budget * scale ~/ priceMicros + quantum;
      if (budget <= BigInt.zero ||
          shares <= BigInt.zero ||
          shares > shareCap) {
        throw const FormatException('Order is below the supported precision');
      }
      return PolymarketOrderAmounts._(budget, shares);
    }

    // With two share decimals and the documented price precision, this
    // product is exactly representable in the token's six decimal units.
    return isBuy
        ? PolymarketOrderAmounts._(quoteMicros, shareMicros)
        : PolymarketOrderAmounts._(shareMicros, quoteMicros);
  }
}
