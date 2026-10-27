// Founder, 27 October 2026: "When I place 5 sometimes it shows 4.99".
// The receipt shows what the venue says the order spent, and a market buy
// signed floor(shares to 0.01) × price floored to the cent: a typed $5.00
// at 37¢ signed 13.51 × 0.37 = $4.9987 → $4.99. A market buy of a typed
// stake must sign (and so spend) the whole stake, at every price.
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/order_amounts.dart';

void main() {
  const cases = [
    (0.37, '0.01'),
    (0.36, '0.01'),
    (0.359, '0.001'),
    (0.6, '0.01'),
    (0.73, '0.01'),
    (0.83, '0.01'),
    (0.97, '0.001'),
    (0.123, '0.001'),
    (0.5, '0.01'),
    (0.0225, '0.0025'),
  ];

  PolymarketOrderAmounts sign(double stake, double price, String tick) {
    final plan = PolymarketOrderPlan.build(
        amount: stake, price: price, tickSize: tick, negRisk: false);
    return PolymarketOrderAmounts.encode(
      tickSize: tick,
      price: price,
      size: plan.shares,
      isBuy: true,
      isMarket: true,
      spendUsd: plan.spendUsd,
    );
  }

  for (final (price, tick) in cases) {
    for (final stake in [5.0, 3.59, 12.34, 1.0]) {
      test('\$$stake typed at ${price * 100}¢ signs \$$stake, never a cent less',
          () {
        final wire = sign(stake, price, tick);
        expect(wire.maker, BigInt.from((stake * 100).round() * 10000));
        // Never a worse price than the reviewed cap.
        expect(wire.maker * BigInt.from(1000000),
            lessThanOrEqualTo(wire.taker * BigInt.from((price * 1e6).round())));
        // The grant binds exactly what is signed.
        final plan = PolymarketOrderPlan.build(
            amount: stake, price: price, tickSize: tick, negRisk: false);
        expect(
            PmGrants.orderAmount(
                isBuy: true,
                size: plan.shares,
                price: price,
                spendUsd: plan.spendUsd),
            wire.maker);
      });
    }
  }

  test('float noise on the stake is not truncated to a cent less', () {
    expect(polymarketMarketBuyBudgetMicros(4.999999999), BigInt.from(5000000));
    expect(polymarketMarketBuyBudgetMicros(0.1 + 0.2), BigInt.from(300000));
    // A stake that really is under a cent short is not rounded up past it.
    expect(polymarketMarketBuyBudgetMicros(4.996), BigInt.from(4990000));
  });

  test('without the stake the old floored budget is unchanged (limits, sells)',
      () {
    final wire = PolymarketOrderAmounts.encode(
        tickSize: '0.01',
        price: 0.37,
        size: 13.51,
        isBuy: true,
        isMarket: true);
    expect(wire.maker, BigInt.from(4990000));
  });
}
