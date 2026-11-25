// The one book walk every Polymarket buy and sell preview shares
// (polymarketWalkAsks / polymarketWalkBids). Founder, 13 November 2026, on
// 2.2.0 (122): $500 on "Will Flávio Bolsonaro return to Brazil by November
// 30, 2026?" Yes (0.45c mid) read "Payout if you win $111,111.11", the
// stake over the mid. The asks under 1c held $0.70 (92 shares); walked
// whole, the stake buys about 8,000 shares (Polymarket: about $7.8k to
// win, 6.4c average).
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/ledger_pm_trade.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';

/// The Yes ask book from the founder's screenshot (the cheap end exactly,
/// the deeper levels filled in to the same shape).
const founderAsks = <(double, double)>[
  (0.005, 20),
  (0.006, 14),
  (0.007, 20),
  (0.01, 38),
  (0.019, 38),
  (0.02, 50),
  (0.03, 1200),
  (0.05, 2000),
  (0.06, 2000),
  (0.09, 5000),
  (0.79, 1000),
];

Map<String, dynamic> bookJson(List<(double, double)> asks) => {
      'market': 'm',
      'asset_id': 'yes',
      'tick_size': '0.001',
      'neg_risk': false,
      // REST order: worst first.
      'asks': [
        for (final (p, s) in asks.reversed) {'price': '$p', 'size': '$s'},
      ],
      'bids': [
        {'price': '0.004', 'size': '5000'},
      ],
    };

void main() {
  test('\$500 capped at 1c fills only the \$0.70 under it', () {
    final walk =
        polymarketWalkAsks(founderAsks, amountUsd: 500, maxPrice: 0.01);
    expect(walk.fills, isFalse);
    expect(walk.depthUsd, closeTo(0.704, 1e-9));
    expect(walk.spentUsd, closeTo(0.704, 1e-9));
    expect(walk.shares, closeTo(92, 1e-9));
    expect(const PolymarketThinBook(fillableUsd: 0.704).fillableCents, 0.70);
  });

  test('\$500 uncapped buys about 8.1k shares, never 111k', () {
    final walk = polymarketWalkAsks(founderAsks, amountUsd: 500);
    expect(walk.fills, isTrue);
    expect(walk.spentUsd, closeTo(500, 1e-9));
    expect(walk.lastPrice, 0.09);
    expect(walk.shares, closeTo(8064.16, 0.01));
    expect(walk.averagePrice, closeTo(0.062, 0.001));
    // The mid's figure is gone.
    expect(walk.shares, lessThan(500 / 0.0045 / 10));
  });

  test('the placement quote follows the book: its cap fills the stake and '
      'its shares are the walk', () {
    final quote = PolymarketMarketBuyQuote.fromBook(
        parsePolymarketOrderBook(bookJson(founderAsks)),
        tokenId: 'yes',
        amount: 500,
        slippagePct: 5);
    expect(quote.price, 0.09); // the marginal ask the stake reaches
    expect(quote.maxPrice, 0.094); // 9c plus 5%, down to the 0.1c tick
    expect(quote.fills, isTrue);
    expect(quote.shares, closeTo(8064.16, 0.01));
    expect(quote.fillableUsd, closeTo(708.426, 1e-6));
  });

  test('a book whose whole depth is under the stake does not fill', () {
    final thin = founderAsks.take(6).toList(); // $2.43 in all
    final quote = PolymarketMarketBuyQuote.fromBook(
        parsePolymarketOrderBook(bookJson(thin)),
        tokenId: 'yes',
        amount: 500,
        slippagePct: 5);
    expect(quote.fills, isFalse);
    expect(PolymarketThinBook(fillableUsd: quote.fillableUsd).fillableCents,
        2.42);
  });

  test('levels are walked cheapest first whatever their order; invalid '
      'levels are skipped', () {
    final walk = polymarketWalkAsks(
        [(0.5, 10), (0.4, 5), (0, 100), (1.2, 100), (0.45, double.nan)],
        amountUsd: 3);
    expect(walk.lastPrice, 0.5);
    expect(walk.shares, closeTo(5 + 1 / 0.5, 1e-9));
  });

  test('the Ledger depth check is the same walk', () {
    final rules = LedgerPmMarketRules(
        tokenId: '1',
        conditionId: '0x',
        tickSize: '0.001',
        minShares: BigInt.zero,
        negRisk: false,
        asks: founderAsks);
    expect(rules.depthPriceFor(500), 0.09);
    expect(rules.depthPriceFor(100000), isNull);
  });

  test('a sale walks the bids dearest first down to its floor', () {
    const bids = <(double, double)>[(0.30, 10), (0.40, 5), (0.20, 100)];
    final all = polymarketWalkBids(bids, shares: 20);
    expect(all.soldShares, 20);
    expect(all.proceedsUsd, closeTo(5 * 0.40 + 10 * 0.30 + 5 * 0.20, 1e-9));
    final floored = polymarketWalkBids(bids, shares: 20, minPrice: 0.25);
    expect(floored.soldShares, 15);
    expect(floored.proceedsUsd, closeTo(5 * 0.40 + 10 * 0.30, 1e-9));
  });
}
