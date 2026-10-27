// Founder, 27 October 2026: "Sometimes the fees have multiple steps — on
// deposit from Investing, and the auto deposits that have several swaps —
// we must show the fee correctly." The slips priced the whole move at the
// Dollars route's share, whatever actually carried it. Every leg's fee is
// added now, parallel legs included.
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/one_balance/funding_fees.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';

VenueCashCandidate _cash(OneBalanceVenue venue, double usd) => (
      venue: venue,
      availableUsd: usd,
      eta: kVenuePullEta[venue]!,
      minimumUsd: 1.0,
    );

void main() {
  // The bet's move as the slip reads it: $10.30 leaves Dollars so that
  // $10.10 lands (the Dollars → Predictions route keeps 20¢).
  const fund = 10.30, arriving = 10.10;

  test('single leg: Dollars carry it all, the plan\'s own move fee', () {
    final fees = estimateOrderFundingFees(
      fundUsd: fund,
      arrivingUsd: arriving,
      dollarsUsd: 50,
      venue: OneBalanceVenue.predictions,
      bitcoinMaxUsd: 100,
      otherVenues: [_cash(OneBalanceVenue.investing, 100)],
    );
    expect(fees.dollarsOnly, isTrue);
    expect(fees.legs.single.sentUsd, fund);
    expect(fees.totalUsd, 0.20);
    // The same figure the plan itself shows.
    final plan = OrderFundingPlan(
        fundUsd: fund, arrivingUsd: arriving, rule: 'r', minUsd: 1);
    expect(fees.totalUsd, plan.feeUsd);
  });

  test('two parallel legs: Bitcoin and Investing, both fees added', () {
    final fees = estimateOrderFundingFees(
      fundUsd: fund,
      arrivingUsd: arriving,
      dollarsUsd: 0,
      venue: OneBalanceVenue.predictions,
      bitcoinMaxUsd: 4.00,
      bitcoinSpread: 0.02,
      otherVenues: [_cash(OneBalanceVenue.investing, 20)],
    );
    expect(fees.legs.map((l) => l.source), [
      FundingLegSource.bitcoin,
      FundingLegSource.investing,
    ]);
    final bitcoin = fees.legs[0], investing = fees.legs[1];
    // $4.00 lands from Bitcoin at a 2% spread: $4.0816 of bitcoin, a
    // $0.0816 fee, to the cent up.
    expect(bitcoin.sentUsd, closeTo(4.00 / 0.98, 1e-9));
    expect(bitcoin.feeUsd, 0.09);
    // The rest, $6.30, from Investing: grossed up by the pull's cost
    // (2% + 30¢) to $6.74, of which $6.3052 lands: $0.4348.
    expect(investing.sentUsd, 6.74);
    expect(investing.feeUsd, 0.44);
    // Both legs, added. The slip used to show the Dollars route's 20¢ for
    // all of it.
    expect(fees.totalUsd, 0.53);
    expect(fees.totalUsd, greaterThan(fund - arriving));
  });

  test('Investing → Predictions (HyperCore, Circle CCTP): the pull\'s cost',
      () {
    final fees = estimateOrderFundingFees(
      fundUsd: fund,
      arrivingUsd: arriving,
      dollarsUsd: 0,
      venue: OneBalanceVenue.predictions,
      otherVenues: [_cash(OneBalanceVenue.investing, 50)],
    );
    final leg = fees.legs.single;
    expect(leg.source, FundingLegSource.investing);
    // $10.30 has to land: (10.30 + 0.30) / 0.98 = $10.82 leaves.
    expect(leg.sentUsd, 10.82);
    // $10.82 − $10.3036 landing = $0.5164, to the cent up.
    expect(leg.feeUsd, 0.52);
    expect(fees.totalUsd, 0.52);
  });

  test('Dollars for part: the route\'s share on the Dollars part only', () {
    final fees = estimateOrderFundingFees(
      fundUsd: fund,
      arrivingUsd: arriving,
      dollarsUsd: 5.00,
      venue: OneBalanceVenue.predictions,
      otherVenues: [_cash(OneBalanceVenue.investing, 50)],
    );
    expect(fees.legs.map((l) => l.source),
        [FundingLegSource.dollars, FundingLegSource.investing]);
    // $5.00 × (20¢ / $10.30) = $0.0971, to the cent up.
    expect(fees.legs[0].feeUsd, 0.10);
    // $5.30 from Investing: (5.30 + 0.30) / 0.98 → $5.72, $5.3056 lands.
    expect(fees.legs[1].sentUsd, 5.72);
    expect(fees.legs[1].feeUsd, 0.42);
    expect(fees.totalUsd, 0.52);
  });

  test('an Investing order from Predictions cash never counts Investing', () {
    final fees = estimateOrderFundingFees(
      fundUsd: 8,
      arrivingUsd: 7.8,
      dollarsUsd: 0,
      venue: OneBalanceVenue.investing,
      otherVenues: [
        _cash(OneBalanceVenue.investing, 100),
        _cash(OneBalanceVenue.predictions, 100),
      ],
    );
    expect(fees.legs.single.source, FundingLegSource.predictions);
    // Predictions → Investing: 2%, no fixed cost. 8 / 0.98 → $8.17.
    expect(fees.legs.single.sentUsd, 8.17);
  });

  test('nothing to move, nothing to price', () {
    expect(
        estimateOrderFundingFees(
                fundUsd: 0,
                arrivingUsd: 0,
                dollarsUsd: 10,
                venue: OneBalanceVenue.predictions)
            .isEmpty,
        isTrue);
  });

  test('the Bitcoin spread from Orchestra\'s own estimate', () {
    // 10,000 sats at $100,000 is $10; $9.80 lands: 2%.
    expect(
        bitcoinSpreadFrom(
            sats: 10000, usdPerBtc: 100000, estimatedOutUsd: 9.80),
        closeTo(0.02, 1e-12));
    expect(bitcoinSpreadFrom(sats: 0, usdPerBtc: 100000, estimatedOutUsd: 9.8),
        isNull);
    expect(
        bitcoinSpreadFrom(sats: 10000, usdPerBtc: 100000, estimatedOutUsd: 11),
        isNull);
  });
}
