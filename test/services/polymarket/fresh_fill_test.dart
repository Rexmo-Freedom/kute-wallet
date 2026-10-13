// A queued bet is priced from the book read after its money landed: the
// executable ask plus the tolerance, on the market's increment, never past
// the approval and never outside the venue's valid range.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/fresh_fill.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/order_refusal.dart';
import 'package:kute/services/polymarket/polymarket_slippage_defaults.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderBook;

const _token = '42';

OrderBook _book(List<(String, String)> asks, {String tick = '0.01'}) =>
    parsePolymarketOrderBook({
      'market': 'm',
      'asset_id': _token,
      'tick_size': tick,
      'neg_risk': false,
      'min_order_size': '5',
      'asks': [
        for (final (p, s) in asks) {'price': p, 'size': s}
      ],
      'bids': const [],
    });

void main() {
  group('polymarketWorstPriceOnTick', () {
    test('rounds a buy\'s worst price down to the increment', () {
      expect(polymarketWorstPriceOnTick(0.525, 0.01), 0.52);
      expect(polymarketWorstPriceOnTick(0.5299, 0.01), 0.52);
      expect(polymarketWorstPriceOnTick(0.52, 0.01), 0.52);
      expect(polymarketWorstPriceOnTick(0.9876, 0.001), 0.987);
    });

    test('clamps to one tick .. one minus a tick (1¢–99¢ on a 1¢ market)',
        () {
      expect(polymarketWorstPriceOnTick(1.2, 0.01), 0.99);
      expect(polymarketWorstPriceOnTick(0.999, 0.01), 0.99);
      expect(polymarketWorstPriceOnTick(0.001, 0.01), 0.01);
      expect(polymarketWorstPriceOnTick(0, 0.01), 0.01);
      expect(polymarketWorstPriceOnTick(0.9999, 0.001), 0.999);
    });
  });

  group('polymarketFillPrice', () {
    test('priced from the fresh ask plus tolerance, under the approval', () {
      // Ask 48¢ at 5%: 50.4¢ → 50¢. The approval allows 52.5¢.
      final fill = polymarketFillPrice(_book([('0.48', '100')]),
          tokenId: _token,
          amount: 10,
          slippagePct: 5,
          approvedMaxPrice: 0.525);
      expect(fill.orderPrice, 0.50);
      expect(fill.bestAsk, 0.48);
      expect(fill.quotedPrice, 0.48);
    });

    test('never above the approved maximum, on its increment', () {
      // Ask 51¢ at 5%: 53.55¢ → 53¢; the approval's 52.5¢ → 52¢.
      final fill = polymarketFillPrice(_book([('0.51', '100')]),
          tokenId: _token,
          amount: 10,
          slippagePct: 5,
          approvedMaxPrice: 0.525);
      expect(fill.orderPrice, 0.52);
    });

    test('at least one tick of room over the ask', () {
      // 12¢ at 5% rounds back to 12¢: one tick more, 13¢.
      final fill = polymarketFillPrice(_book([('0.12', '1000')]),
          tokenId: _token,
          amount: 10,
          slippagePct: 5,
          approvedMaxPrice: 0.20);
      expect(fill.orderPrice, 0.13);
    });

    test('a 0.001 market keeps its increment and its 99.9¢ ceiling', () {
      final fill = polymarketFillPrice(
          _book([('0.985', '1000')], tick: '0.001'),
          tokenId: _token,
          amount: 10,
          slippagePct: 10,
          approvedMaxPrice: 0.999);
      expect(fill.orderPrice, 0.999);
    });

    test('the ask already past the approval: nothing to sign, the new max '
        'named for the retry', () {
      expect(
          () => polymarketFillPrice(_book([('0.70', '100')]),
              tokenId: _token,
              amount: 10,
              slippagePct: 5,
              approvedMaxPrice: 0.525),
          throwsA(isA<PolymarketThinBook>()
              .having((e) => e.price, 'price', 0.70)
              .having((e) => e.limit, 'limit', 0.525)
              .having((e) => e.retryPrice, 'retry', 0.73)));
    });

    test('an empty book is a thin book', () {
      expect(
          () => polymarketFillPrice(_book(const []),
              tokenId: _token,
              amount: 10,
              slippagePct: 5,
              approvedMaxPrice: 0.5),
          throwsA(isA<PolymarketThinBook>()
              .having((e) => e.fillableUsd, 'fillable', 0)));
    });
  });

  test('price refusals are the ones a re-priced order may follow', () {
    expect(
        isPolymarketPriceRefusal('no orders found to match with FAK order. '
            'FAK orders are partially filled or killed if no match is found.'),
        isTrue);
    expect(
        isPolymarketPriceRefusal("order couldn't be fully filled. FOK orders "
            'are fully filled or killed.'),
        isTrue);
    expect(isPolymarketPriceRefusal('invalid price (1.2), min: 0.01 - max: 0.99'),
        isTrue);
    expect(isPolymarketPriceRefusal('not enough balance / allowance'), isFalse);
    expect(isPolymarketPriceRefusal('invalid signature'), isFalse);
  });

  test('a game in play starts at the short round\'s tolerance', () {
    expect(polymarketDefaultSlippagePct(question: 'Lakers vs Celtics'), 5);
    expect(
        polymarketDefaultSlippagePct(
            question: 'Lakers vs Celtics', live: true),
        kPolymarketFastRoundSlippagePct);
  });
}
