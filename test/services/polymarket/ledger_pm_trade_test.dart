import 'package:flutter_test/flutter_test.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/screens/ledger/polymarket/ledger_pm_support.dart';
import 'package:kute/services/polymarket/ledger_pm_trade.dart';

void main() {
  test('asks are sorted cheapest first and malformed levels dropped', () {
    final asks = LedgerPmMarketSource.parseAsks([
      {'price': '0.99', 'size': '100'},
      {'price': '0.42', 'size': '100'},
      {'price': '0.40', 'size': '5'},
      {'price': 'nan', 'size': '1'},
      {'price': '1.0', 'size': '1'},
      {'price': '0.5', 'size': '0'},
      'garbage',
    ]);
    expect(asks.map((a) => a.$1), [0.40, 0.42, 0.99]);
    expect(LedgerPmMarketSource.parseAsks(null), isEmpty);
  });

  test('depth price walks the book for the stake and refuses a thin book',
      () {
    final rules = LedgerPmMarketRules(
        tokenId: '1',
        conditionId: '0x' + 'a' * 64,
        tickSize: '0.01',
        minShares: BigInt.from(5),
        negRisk: false,
        asks: LedgerPmMarketSource.parseAsks([
          {'price': '0.99', 'size': '100'},
          {'price': '0.42', 'size': '100'},
          {'price': '0.40', 'size': '5'},
        ]));
    // First 2 dollars at 0.40, the next dollar at 0.42.
    expect(rules.depthPriceFor(3), 0.42);
    expect(rules.depthPriceFor(1), 0.40);
    // 2 + 42 + 99 dollars of depth; a larger stake cannot fill.
    expect(rules.depthPriceFor(200), isNull);
    expect(rules.depthPriceFor(0), isNull);
    expect(LedgerPmMarketRules(
            tokenId: '1',
            conditionId: 'c',
            tickSize: '0.01',
            minShares: BigInt.zero,
            negRisk: false)
        .depthPriceFor(3), isNull);
  });

  test('a Ledger market buy is capped by the one-tick rule', () {
    final rules = LedgerPmMarketRules(
        tokenId: '1',
        conditionId: '0x' + 'a' * 64,
        tickSize: '0.01',
        minShares: BigInt.from(5),
        negRisk: false);
    double capFor(double reviewed, double slippagePct) {
      final a = rules.amounts(
          budgetUsd: 3,
          reviewedPrice: reviewed,
          isLimit: false,
          slippagePct: slippagePct);
      // The worst price the device is shown: maker / taker, rounded up.
      return ((a.maker * BigInt.from(1000000) + a.taker - BigInt.one) ~/
                  a.taker)
              .toInt() /
          1000000;
    }

    for (final (ask, cap) in [(0.05, 0.06), (0.12, 0.13), (0.18, 0.19)]) {
      expect(capFor(ask, 5), lessThanOrEqualTo(cap + 1e-9), reason: '$ask');
      expect(capFor(ask, 5), greaterThan(cap - 0.001), reason: '$ask');
    }
    expect(capFor(0.60, 5), closeTo(0.63, 0.001));
    expect(capFor(0.12, 0), closeTo(0.12, 0.001));
  });

  test('a neg-risk allowance is the smaller of the exchange and v1 adapter',
      () {
    LedgerPmBuyingPower power(Map<String, String> allowances) =>
        LedgerPmBuyingPower.fromClob(
            depositWallet: '0x${'55' * 20}',
            collateral: {'balance': '10000000', 'allowances': allowances},
            orders: const []);
    final exchange = PolymarketConstants.exchangeAddress;
    final negRisk = PolymarketConstants.negRiskExchangeAddress;
    final adapter = PolymarketConstants.legacyNegRiskAdapterAddress;

    final both = power({exchange: '7', negRisk: '9', adapter: '4'});
    expect(both.allowance(false), BigInt.from(7));
    expect(both.allowance(true), BigInt.from(4));
    expect(power({negRisk: '3', adapter: '8'}).allowance(true), BigInt.from(3));
    // The CLOB refuses a neg-risk order with no adapter allowance.
    expect(power({negRisk: '9'}).allowance(true), BigInt.zero);
  });

  test('a Ledger sell keeps one tick under the bid at least', () {
    LedgerPmSellQuote? sell(double bid, double slippage) =>
        buildLedgerPmSellQuote(
            shares: 10, bestBid: bid, tickSize: '0.01', slippage: slippage);
    expect(sell(0.05, 0.05)!.price, 0.04);
    expect(sell(0.12, 0.05)!.price, 0.11);
    expect(sell(0.18, 0.05)!.price, 0.17);
    expect(sell(0.60, 0.05)!.price, 0.57);
    expect(sell(0.12, 0)!.price, 0.12);
    expect(sell(0.01, 0.05)!.price, 0.01);
  });
}
