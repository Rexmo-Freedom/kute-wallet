import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/order_amounts.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';

Map<String, dynamic> fixture({String tick = '0.01'}) => {
      'market': 'market', 'asset_id': 'yes-token', 'tick_size': tick,
      'neg_risk': true, 'min_order_size': '5',
      // REST's worst-first order previously made bestAsk return 0.99.
      'asks': [
        {'price': '0.99', 'size': '100'},
        {'price': '0.42', 'size': '100'},
        {'price': '0.40', 'size': '5'},
      ],
      'bids': [
        {'price': '0.01', 'size': '100'},
        {'price': '0.39', 'size': '100'},
      ],
    };

void main() {
  test('REST ordering and current tick key produce executable best prices', () {
    final book = parsePolymarketOrderBook(fixture());
    expect(book.bestAsk, 0.40);
    expect(book.bestBid, 0.39);
    expect(book.minTickSize, '0.01');
    expect(book.negRisk, isTrue);
  });

  test('a three-dollar buy walks depth rather than using first or best ask',
      () {
    final quote = PolymarketMarketBuyQuote.fromBook(
      parsePolymarketOrderBook(fixture()),
      tokenId: 'yes-token',
      amount: 3,
      slippagePct: 5,
    );
    expect(quote.price, 0.42); // First $2 at 0.40, remaining $1 at 0.42.
    expect(quote.maxPrice, 0.44);
    expect(quote.maxPrice, lessThanOrEqualTo(quote.price * 1.05));
    final shares = (3 / quote.maxPrice * 100).floorToDouble() / 100;
    final wire = PolymarketOrderAmounts.encode(
        tickSize: quote.tickSize,
        price: quote.maxPrice,
        size: shares,
        isBuy: true,
        isMarket: true);
    expect(wire.maker, lessThanOrEqualTo(BigInt.from(3000000)));
    expect(wire.maker * BigInt.from(1000000),
        lessThanOrEqualTo(wire.taker * BigInt.from(440000)));
  });

  test('all-in maximum adds the fee ceiling at the best ask, not the cap', () {
    const terms = PolymarketFeeTerms(
        rate: 0.07, exponent: 1, builderTakerBps: 20, builderMakerBps: 10);
    final quote = PolymarketMarketBuyQuote.fromBook(
      parsePolymarketOrderBook(fixture()),
      tokenId: 'yes-token',
      amount: 3,
      slippagePct: 5,
      fees: terms,
    );
    expect(quote.bestAsk, 0.40);
    expect(quote.feeCeiling, terms.feeCeilingForNotional(3, 0.40));
    expect(quote.feeCeiling, greaterThan(terms.feeCeilingForNotional(3, 0.44)));
    expect(quote.allInMax,
        3 + quote.feeCeiling + PolymarketMarketBuyQuote.roundingHeadroom);
    // Without live terms the documented maxima apply and reserve more.
    final blind = PolymarketMarketBuyQuote.fromBook(
      parsePolymarketOrderBook(fixture()),
      tokenId: 'yes-token',
      amount: 3,
      slippagePct: 5,
    );
    expect(blind.fees.live, isFalse);
    expect(blind.allInMax, greaterThan(quote.allInMax));
  });

  test(
      'widens the selected slippage by at most one tick: the cap is the '
      'slippage rounded down or one tick over the ask, whichever is higher',
      () {
    PolymarketMarketBuyQuote quoteAt(String ask,
        {String tick = '0.01', double slippagePct = 5}) {
      final json = fixture(tick: tick);
      json['asks'] = [
        {'price': ask, 'size': '100000'}
      ];
      return PolymarketMarketBuyQuote.fromBook(parsePolymarketOrderBook(json),
          tokenId: 'yes-token', amount: 3, slippagePct: slippagePct);
    }

    // 4-20c: 5% rounds back down to the ask, so one tick of room instead.
    for (final (ask, cap) in [('0.05', 0.06), ('0.12', 0.13), ('0.18', 0.19)]) {
      final quote = quoteAt(ask);
      expect(quote.maxPrice, cap, reason: 'ask $ask');
      // The extra room is that one tick and no more.
      expect(quote.maxPrice, lessThanOrEqualTo(quote.price + 0.01 + 1e-9));
    }
    // Where 5% already clears a tick it is used, rounded down, as before.
    expect(quoteAt('0.60').maxPrice, 0.63);
    // Slippage 0 keeps the exact ask.
    expect(quoteAt('0.12', slippagePct: 0).maxPrice, 0.12);
    expect(quoteAt('0.60', slippagePct: 0).maxPrice, 0.60);
    // Never past 0.99 for the extra tick, never past 1 - tick at all.
    expect(quoteAt('0.99').maxPrice, 0.99);
    // A fine tick: 1% of 5c is 0.0505, more than one 0.0001 tick.
    expect(quoteAt('0.05', tick: '0.0001', slippagePct: 1).maxPrice, 0.0505);
    // The fillable figure is read at that same cap.
    final json = fixture()
      ..['asks'] = [
        {'price': '0.12', 'size': '10'},
        {'price': '0.13', 'size': '10'},
        {'price': '0.14', 'size': '10'},
      ];
    final thin = PolymarketMarketBuyQuote.fromBook(
        parsePolymarketOrderBook(json),
        tokenId: 'yes-token',
        amount: 1,
        slippagePct: 5);
    expect(thin.maxPrice, 0.13);
    expect(thin.fillableUsd, closeTo(1.2 + 1.3, 1e-9));
  });

  test('the sell floor mirrors the cap: one tick under the bid at least', () {
    for (final (bid, floor) in [(0.05, 0.04), (0.12, 0.11), (0.18, 0.17)]) {
      expect(polymarketSellFloor(bid: bid, slippagePct: 5, tick: 0.01), floor,
          reason: 'bid $bid');
    }
    // 5% of 60c is 57c, past one tick: used as is. 61c * 0.95 rounds up.
    expect(polymarketSellFloor(bid: 0.60, slippagePct: 5, tick: 0.01), 0.57);
    expect(polymarketSellFloor(bid: 0.61, slippagePct: 5, tick: 0.01), 0.58);
    expect(polymarketSellFloor(bid: 0.12, slippagePct: 0, tick: 0.01), 0.12);
    // Floored at one tick above zero.
    expect(polymarketSellFloor(bid: 0.01, slippagePct: 5, tick: 0.01), 0.01);
    expect(polymarketSellFloor(bid: 0.004, slippagePct: 5, tick: 0.001),
        0.003);
  });

  test('supports sub-cent outcomes at their actual tick', () {
    final json = fixture(tick: '0.0001');
    json['asks'] = [
      {'price': '0.0005', 'size': '100000'}
    ];
    final quote = PolymarketMarketBuyQuote.fromBook(
      parsePolymarketOrderBook(json),
      tokenId: 'yes-token',
      amount: 3,
      slippagePct: 5,
    );
    // 5% of 0.05c rounds back to the ask; one 0.01c tick of room.
    expect(quote.maxPrice, 0.0006);
  });

  test('empty liquidity and a different outcome cannot become a quote', () {
    final book = parsePolymarketOrderBook(fixture());
    expect(
        () => PolymarketMarketBuyQuote.fromBook(book,
            tokenId: 'no-token', amount: 3, slippagePct: 5),
        throwsFormatException);
    final empty = fixture()..['asks'] = <dynamic>[];
    expect(
        () => PolymarketMarketBuyQuote.fromBook(parsePolymarketOrderBook(empty),
            tokenId: 'yes-token', amount: 3, slippagePct: 5),
        throwsStateError);
  });

  test('FAK can request a partial fill with insufficient total depth', () {
    final json = fixture()
      ..['asks'] = [
        {'price': '0.4', 'size': '5'}
      ];
    final quote = PolymarketMarketBuyQuote.fromBook(
        parsePolymarketOrderBook(json),
        tokenId: 'yes-token',
        amount: 3,
        slippagePct: 5);
    expect(quote.price, 0.4);
    expect(quote.maxPrice, 0.42);
  });

  test('a Max stake fitted at the best ask passes the placement check', () {
    const terms = PolymarketFeeTerms(
        rate: 0.07, exponent: 1, builderTakerBps: 100, builderMakerBps: 50);
    final book = parsePolymarketOrderBook(fixture());
    const cash = 50.0;
    // What preparation does for a spend-all bet: fit at the executable
    // best ask, keeping the rounding cent free.
    final stake = terms.maxNotionalFor(cash, book.bestAsk!,
        reserve: PolymarketMarketBuyQuote.roundingHeadroom);
    final quote = PolymarketMarketBuyQuote.fromBook(book,
        tokenId: 'yes-token', amount: stake, slippagePct: 5, fees: terms);
    expect(quote.allInMax, lessThanOrEqualTo(cash + 1e-9));
    // Sized at the slippage-raised order price instead (the old Max), the
    // fee ceiling at the lower best ask does not fit.
    final naive = terms.maxNotionalFor(cash, quote.maxPrice);
    final naiveQuote = PolymarketMarketBuyQuote.fromBook(book,
        tokenId: 'yes-token', amount: naive, slippagePct: 5, fees: terms);
    expect(naiveQuote.allInMax, greaterThan(cash));
  });
}
