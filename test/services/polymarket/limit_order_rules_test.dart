import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/limit_order_rules.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/order_amounts.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

/// Every price on [tick]'s grid inside the venue's range.
List<double> _grid(String tick) {
  final t = polymarketTickValue(tick)!;
  final steps = (1 / t).round();
  return [
    for (var i = 1; i < steps; i++) double.parse((i * t).toStringAsFixed(6)),
  ];
}

const _ticks = ['0.1', '0.01', '0.005', '0.0025', '0.001', '0.0001'];

Order _order(String token, String side, double size, double matched) => Order(
      id: 'o-$token-$side-$size',
      market: 'm',
      assetId: token,
      owner: 'x',
      side: side,
      price: '0.5',
      originalSize: '$size',
      sizeMatched: '$matched',
      outcome: 'Yes',
    );

void main() {
  group('P2: the shares a limit stake buys', () {
    test('the old float division signed 4.99 shares at the minimum', () {
      // The audit's cases: 1.40 / 0.28 = 4.999999… floored to 4.99.
      for (final cents in [28, 33, 56, 66]) {
        final price = cents / 100;
        final minimum = (5 * price * 100).ceilToDouble() / 100;
        final old = ((minimum / price) * 100).floorToDouble() / 100;
        expect(old, lessThan(5), reason: '$cents¢');
        expect(polymarketLimitBuyShares(minimum, price), 5.0,
            reason: '$cents¢');
      }
    });

    for (final tick in _ticks) {
      test('the minimum stake reaches 5 shares at every price on $tick',
          () {
        final prices = tick == '0.0001'
            // Every cent plus every 37th step between (9,999 points
            // otherwise; the arithmetic does not depend on the step).
            ? [
                for (var c = 1; c <= 99; c++) c / 100,
                for (var i = 1; i < 10000; i += 37) i / 10000,
              ]
            : _grid(tick);
        for (final price in prices) {
          final minimum =
              polymarketLimitBuyMinimumUsd(kPolymarketDefaultMinOrderShares,
                  price);
          final shares = polymarketLimitBuyShares(minimum, price);
          expect(
              polymarketMeetsMinimumShares(
                  shares, kPolymarketDefaultMinOrderShares),
              isTrue,
              reason: '$price: \$$minimum buys $shares');
          // A cent less is under the minimum: it is the smallest stake.
          if (minimum >= 0.02) {
            expect(
                polymarketMeetsMinimumShares(
                    polymarketLimitBuyShares(minimum - 0.01, price),
                    kPolymarketDefaultMinOrderShares),
                isFalse,
                reason: '$price: \$${minimum - 0.01}');
          }
          // The signed order: never more than the stake, never fewer
          // shares than the venue's minimum.
          final amounts = PolymarketOrderAmounts.encode(
              tickSize: tick,
              price: price,
              size: shares,
              isBuy: true,
              isMarket: false);
          expect(amounts.taker, greaterThanOrEqualTo(BigInt.from(5000000)),
              reason: '$price');
          expect(amounts.maker,
              lessThanOrEqualTo(BigInt.from((minimum * 1e6).round())),
              reason: '$price');
        }
      });
    }

    test('the whole cents 1 to 99 at each tick, with stakes around them',
        () {
      for (final tick in _ticks) {
        for (var c = 1; c <= 99; c++) {
          final price = c / 100;
          // A 10¢ market quotes only every tenth cent.
          if (!polymarketPriceOnTick(price, polymarketTickValue(tick)!)) {
            continue;
          }
          for (final stake in [1.0, 1.4, 2.5, 3.3, 10.0, 12.34, 99.99]) {
            final shares = polymarketLimitBuyShares(stake, price);
            final amounts = PolymarketOrderAmounts.encode(
                tickSize: tick,
                price: price,
                size: shares,
                isBuy: true,
                isMarket: false);
            expect(amounts.maker,
                lessThanOrEqualTo(BigInt.from((stake * 1e6).round())));
            // Floored to the hundredth, never one under it.
            final exact = stake / price;
            expect(shares, lessThanOrEqualTo(exact + 1e-9));
            expect(shares, greaterThan(exact - 0.0100001));
          }
        }
      }
    });

    test('the standing order plan sizes a limit the same exact way', () {
      expect(PolymarketOrderPlan.sharesFor(1.40, 0.28), 5.0);
      expect(PolymarketOrderPlan.sharesFor(1.65, 0.33), 5.0);
      expect(PolymarketOrderPlan.sharesFor(2.80, 0.56), 5.0);
      expect(PolymarketOrderPlan.sharesFor(3.30, 0.66), 5.0);
    });
  });

  group('P1: limit prices on the tick', () {
    test('a mid off the tick seeds on it, down for a buy, up for a sell',
        () {
      expect(polymarketSnapToTick(0.535, 0.01, snap: PolymarketTickSnap.down),
          0.53);
      expect(polymarketSnapToTick(0.535, 0.01, snap: PolymarketTickSnap.up),
          0.54);
      expect(polymarketSnapToTick(0.53, 0.01, snap: PolymarketTickSnap.down),
          0.53);
      expect(
          polymarketSnapToTick(0.0345, 0.001, snap: PolymarketTickSnap.down),
          0.034);
      expect(polymarketSnapToTick(0.47, 0.1), 0.5);
    });

    test('the steps stay on the tick and inside its range', () {
      for (final tick in _ticks.map(polymarketTickValue)) {
        var price = polymarketSnapToTick(0.5355, tick!);
        for (var i = 0; i < 40; i++) {
          price = polymarketStepLimitPrice(price, tick, 1);
          expect(polymarketLimitPriceIssue(price, tick), isNull,
              reason: '$tick $price');
        }
        for (var i = 0; i < 80; i++) {
          price = polymarketStepLimitPrice(price, tick, -1);
          expect(polymarketLimitPriceIssue(price, tick), isNull,
              reason: '$tick $price');
        }
      }
      // From 53.5¢ one cent up is 54¢ (on the tick), never 54.5¢.
      expect(polymarketStepLimitPrice(0.535, 0.01, 1), 0.54);
      expect(polymarketStepLimitPrice(0.535, 0.01, -1), 0.53);
      expect(polymarketStepLimitPrice(0.53, 0.01, 1), 0.54);
      expect(polymarketStepLimitPrice(0.53, 0.01, -1), 0.52);
      // The ends: one tick, and one tick under a dollar.
      expect(polymarketStepLimitPrice(0.01, 0.01, -1), 0.01);
      expect(polymarketStepLimitPrice(0.99, 0.01, 1), 0.99);
      // P9: a 0.1¢ market reaches under 1¢ and over 99¢.
      expect(polymarketStepLimitPrice(0.01, 0.001, -1), 0.009);
      expect(polymarketStepLimitPrice(0.99, 0.001, 1), 0.991);
      expect(polymarketStepLimitPrice(0.001, 0.001, -1), 0.001);
    });

    test('an off-tick or out-of-range price is named before approval', () {
      expect(polymarketLimitPriceIssue(0.535, 0.01),
          PolymarketLimitPriceIssue.offTick);
      expect(polymarketLimitPriceIssue(0.53, 0.01), isNull);
      expect(polymarketLimitPriceIssue(0.535, 0.005), isNull);
      expect(polymarketLimitPriceIssue(0.55, 0.1),
          PolymarketLimitPriceIssue.offTick);
      expect(polymarketLimitPriceIssue(0.995, 0.01),
          PolymarketLimitPriceIssue.outOfRange);
      expect(polymarketLimitPriceIssue(0.0, 0.01),
          PolymarketLimitPriceIssue.outOfRange);
      expect(polymarketLimitPriceIssue(0.995, 0.001), isNull);
      // Every price the rules accept, the encoder signs.
      for (final tick in _ticks) {
        final t = polymarketTickValue(tick)!;
        for (final price in tick == '0.0001'
            ? [0.0001, 0.0137, 0.5, 0.9999]
            : _grid(tick)) {
          expect(polymarketLimitPriceIssue(price, t), isNull);
          expect(
              () => PolymarketOrderAmounts.encode(
                  tickSize: tick,
                  price: price,
                  size: 10,
                  isBuy: true,
                  isMarket: false),
              returnsNormally,
              reason: '$tick $price');
        }
      }
    });

    test('an unknown tick snaps to whole cents', () {
      expect(polymarketUsableTick(null), 0.01);
      expect(polymarketUsableTick(0.001), 0.001);
      expect(polymarketTickValue('0.02'), isNull);
    });

    test('the price reads to its tick', () {
      expect(polymarketLimitCentsLabel(0.53), '53¢');
      expect(polymarketLimitCentsLabel(0.034), '3.4¢');
      expect(polymarketLimitCentsLabel(0.0025), '0.25¢');
    });
  });

  group('P3 / P4: what a sale may offer', () {
    test('the minimum is in shares', () {
      expect(polymarketMeetsMinimumShares(4.99, 5), isFalse);
      expect(polymarketMeetsMinimumShares(5, 5), isTrue);
      expect(polymarketMeetsMinimumShares(4.9999999999, 5), isTrue);
    });

    test('shares in resting sells of the token are not free', () {
      final orders = [
        _order('t', 'SELL', 4, 1),
        _order('t', 'SELL', 2.5, 0),
        _order('t', 'BUY', 9, 0),
        _order('other', 'SELL', 7, 0),
      ];
      expect(polymarketSharesInRestingSells(orders, 't'), 5.5);
      expect(polymarketSharesInRestingSells(orders, 'none'), 0);
      expect(polymarketFreeShares(10, 5.5), 4.5);
      expect(polymarketFreeShares(5, 5.5), 0);
      expect(polymarketFreeShares(10.37, 0), 10.37);
    });
  });
}
