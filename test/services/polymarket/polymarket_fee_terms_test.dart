import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';

void main() {
  sellProceedsTests();
  const crypto = PolymarketFeeTerms(
      rate: 0.07, exponent: 1, builderTakerBps: 20, builderMakerBps: 10);

  test('platform fee follows the documented curve and builder fee notional',
      () {
    // 10 shares at 0.50: 10 x 0.07 x 0.25 = 0.175; builder 20 bps of 5.
    expect(crypto.platformFee(10, 0.5), closeTo(0.175, 1e-9));
    expect(crypto.builderFee(10, 0.5), closeTo(0.01, 1e-9));
    expect(crypto.builderFee(10, 0.5, taker: false), closeTo(0.005, 1e-9));
    expect(crypto.platformFee(10, 1.2), 0);
  });

  test('fee ceiling for a stake is taken at the cheapest fill and rounds up',
      () {
    // 3 dollars at 0.05 buys 60 shares: 60 x 0.07 x 0.0475 = 0.1995 + 0.006.
    expect(crypto.feeCeilingForNotional(3, 0.05), closeTo(0.21, 1e-9));
    // The same 3 dollars at 0.95 buys ~3.16 shares and costs far less.
    expect(crypto.feeCeilingForNotional(3, 0.95), lessThanOrEqualTo(0.02));
    expect(crypto.allInCost(3, 0.05), closeTo(3.21, 1e-9));
  });

  test('the old 3% haircut did not cover low-priced crypto outcomes', () {
    // 100 dollars at 0.10: fee/notional = 0.07 x 0.9 + 0.002 = 6.5%.
    expect(crypto.feeCeilingForNotional(100, 0.10), greaterThan(3));
    // And it over-reserved on a fee-free market.
    const free = PolymarketFeeTerms(
        rate: 0, exponent: 1, builderTakerBps: 0, builderMakerBps: 0);
    expect(free.feeCeilingForNotional(100, 0.10), 0);
    expect(free.maxNotionalFor(100, 0.10), 100);
  });

  test('max stake for a budget fits the budget all-in and is maximal', () {
    for (final price in [0.03, 0.25, 0.5, 0.77, 0.99]) {
      for (final budget in [1.0, 3.0, 12.37, 250.0]) {
        final stake = crypto.maxNotionalFor(budget, price);
        expect(stake, greaterThan(0));
        expect(crypto.allInCost(stake, price), lessThanOrEqualTo(budget + 1e-9),
            reason: 'budget $budget at $price');
        expect(crypto.allInCost(stake + 0.01, price), greaterThan(budget),
            reason: 'a cent more must not fit at $price');
      }
    }
    expect(crypto.maxNotionalFor(0, 0.5), 0);
    expect(crypto.maxNotionalFor(10, 1), 0);
  });

  test('a reserve (the market buy rounding cent) is kept free on top', () {
    for (final price in [0.03, 0.25, 0.5, 0.77]) {
      for (final budget in [1.5, 12.37, 250.0]) {
        final stake = crypto.maxNotionalFor(budget, price, reserve: 0.01);
        expect(crypto.allInCost(stake, price) + 0.01,
            lessThanOrEqualTo(budget + 1e-9),
            reason: 'budget $budget at $price');
        expect(crypto.allInCost(stake + 0.01, price) + 0.01,
            greaterThan(budget),
            reason: 'a cent more must not fit at $price');
      }
    }
  });

  test('documented maxima reserve at least as much as any live curve', () {
    expect(PolymarketFeeTerms.worstCase.live, isFalse);
    expect(PolymarketFeeTerms.worstCase.feeCeilingForNotional(50, 0.3),
        greaterThanOrEqualTo(crypto.feeCeilingForNotional(50, 0.3)));
    expect(PolymarketFeeTerms.worstCase.maxNotionalFor(50, 0.3),
        lessThanOrEqualTo(crypto.maxNotionalFor(50, 0.3)));
  });
}

void sellProceedsTests() {
  // The sell ticket's "To Predictions" is the sale less the fees the venue
  // takes from the proceeds: the same platform curve and builder rate the
  // fee estimate above it shows.
  const sports = PolymarketFeeTerms(
      rate: 0.05, exponent: 1, builderTakerBps: 20, builderMakerBps: 0);
  const free = PolymarketFeeTerms(
      rate: 0, exponent: 1, builderTakerBps: 20, builderMakerBps: 0);
  test('sell proceeds are the sale less the fee the estimate shows', () {
    // 10 shares at 0.60: $6.00 less 10 x 0.05 x 0.24 + $6 x 0.002 = $0.132.
    expect(sports.sellProceeds(10, 0.6), closeTo(5.868, 1e-9));
    for (final terms in [sports, free]) {
      for (final (shares, price) in [
        (1.0, 0.03),
        (10.0, 0.6),
        (5000.0, 0.97)
      ]) {
        final gross = shares * price;
        expect(
            terms.sellProceeds(shares, price) + terms.totalFee(shares, price),
            closeTo(gross, 1e-9));
      }
    }
    // A fee-free market's sale loses only the builder fee.
    expect(free.sellProceeds(10, 0.6), closeTo(6 - 0.012, 1e-9));
    expect(sports.sellProceeds(0, 0.6), 0);
    expect(sports.sellProceeds(10, 0), 0);
  });
}
