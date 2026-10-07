import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/order_amounts.dart';

void main() {
  PolymarketOrderAmounts encode({
    String tick = '0.0025',
    double price = 0.5025,
    double size = 1.23,
    bool buy = true,
    bool market = false,
  }) =>
      PolymarketOrderAmounts.encode(
        tickSize: tick,
        price: price,
        size: size,
        isBuy: buy,
        isMarket: market,
      );

  for (final fixture in [
    ('0.1', 0.5, 615000),
    ('0.01', 0.51, 627300),
    ('0.005', 0.505, 621150),
    ('0.0025', 0.5025, 618075),
    ('0.001', 0.849, 1044270),
    ('0.0001', 0.8491, 1044393),
  ]) {
    test('${fixture.$1}: exact six-decimal buy and sell amounts', () {
      final buy = encode(tick: fixture.$1, price: fixture.$2);
      final sell = encode(tick: fixture.$1, price: fixture.$2, buy: false);
      expect(buy.maker, BigInt.from(fixture.$3));
      expect(buy.taker, BigInt.from(1230000));
      expect(sell.maker, buy.taker);
      expect(sell.taker, buy.maker);
    });
  }

  test('off-tick limit price is rejected instead of changed after review', () {
    expect(() => encode(price: 0.503), throwsFormatException);
    expect(() => encode(tick: '0.005', price: 0.501), throwsFormatException);
  });

  test('market prices snap to tick multiples within the approved bound', () {
    final buy = encode(price: 0.5029, market: true);
    final sell = encode(price: 0.5021, buy: false, market: true);
    expect(buy.maker, BigInt.from(610000));
    expect(buy.taker, BigInt.from(1213931));
    expect(sell.maker, BigInt.from(1230000));
    expect(sell.taker, BigInt.from(618075));
    expect(buy.maker * BigInt.from(1000000),
        lessThanOrEqualTo(buy.taker * BigInt.from(502500)));
  });

  test('market buy share precision never worsens the signed price', () {
    final order = encode(tick: '0.005', price: 0.505, market: true);
    expect(order.maker, BigInt.from(620000));
    expect(order.taker, BigInt.from(1227730));
    expect(order.maker * BigInt.from(1000000),
        lessThanOrEqualTo(order.taker * BigInt.from(505000)));
    expect(order.taker, lessThanOrEqualTo(BigInt.from(1230000)));
    expect(order.taker % BigInt.from(10), BigInt.zero);
  });

  test('binary-double noise is accepted without dropping a cent-share', () {
    final order = encode(price: 0.5025000000000001, size: 1.2299999999999998);
    expect(order.maker, BigInt.from(618075));
    expect(order.taker, BigInt.from(1230000));
  });

  test('fractional shares round down and cannot increase the approved size',
      () {
    final order = encode(size: 1.239, buy: false);
    expect(order.maker, BigInt.from(1230000));
  });

  test('unknown, missing and invalid market terms fail closed', () {
    for (final tick in ['null', '', '0.00001', '0.003']) {
      expect(() => encode(tick: tick), throwsFormatException);
    }
    for (final price in [0.0, 1.0, -1.0, double.nan, double.infinity]) {
      expect(() => encode(price: price), throwsFormatException);
    }
    for (final size in [0.0, -1.0, double.nan, double.infinity, 1e15]) {
      expect(() => encode(size: size), throwsFormatException);
    }
    expect(() => encode(size: 0.001), throwsFormatException);
    expect(() => encode(tick: '0.001', price: 0.001, size: 1, market: true),
        throwsFormatException);
    expect(() => encode(tick: '0.01', price: 0.999, market: true, buy: false),
        throwsFormatException);
  });

  test('all market ticks preserve spend, share and worst-price bounds', () {
    for (final (tick, increment, decimals) in [
      ('0.1', 0.1, 3),
      ('0.01', 0.01, 4),
      ('0.005', 0.005, 5),
      ('0.0025', 0.0025, 6),
      ('0.001', 0.001, 5),
      ('0.0001', 0.0001, 6),
    ]) {
      for (final size in [1.23, 5.299, 10.0, 187.67]) {
        final reviewedPrice = 0.50005 + increment / 3;
        final buy =
            encode(tick: tick, price: reviewedPrice, size: size, market: true);
        final sell = encode(
            tick: tick,
            price: reviewedPrice,
            size: size,
            buy: false,
            market: true);
        expect(buy.maker.toDouble() / buy.taker.toDouble(),
            lessThanOrEqualTo(reviewedPrice));
        expect(sell.taker.toDouble() / sell.maker.toDouble(),
            greaterThanOrEqualTo(reviewedPrice));
        expect(buy.maker.toDouble() / 1e6,
            lessThanOrEqualTo(size * reviewedPrice));
        expect(sell.maker.toDouble() / 1e6, lessThanOrEqualTo(size));
        expect(buy.maker % BigInt.from(10000), BigInt.zero);
        expect(buy.taker % BigInt.from(10).pow(6 - decimals), BigInt.zero);
      }
    }
  });
}
