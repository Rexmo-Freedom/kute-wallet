// A market sell used to be one fill-or-kill order at the slippage floor,
// and a thin book killed it every time: on 2026-11-04 a 43.48-share
// position worth $0.57 (1.3¢ a share) failed half a second after submit,
// and on 2026-11-01 a 1000-share position worth $0.50 failed four times
// before it sold. The sell is now fill-and-kill over a ladder of rungs
// that never cross the approved floor, a dust position's approval reaches
// the venue's lowest price, a partial fill leaves the rest sellable, and a
// book with no bids at all says so. Pure functions: nothing is signed.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart'
    show PolymarketSellPriceMoved;
import 'package:kute/services/polymarket/sell_ladder.dart';
import 'package:kute/services/tracking_service.dart';

const _fakKilled = 'no orders found to match with FAK order. FAK orders are '
    'partially filled or killed if no match is found.';
const _fokKilled =
    "order couldn't be fully filled. FOK orders are fully filled or killed.";

Matcher _prices(List<double> expected) => predicate<List<double>>((rungs) {
      if (rungs.length != expected.length) return false;
      for (var i = 0; i < rungs.length; i++) {
        if ((rungs[i] - expected[i]).abs() > 1e-9) return false;
      }
      return true;
    }, 'rungs $expected');

void main() {
  group('the floor the person approves', () {
    test('a normal position: the floor at their slippage', () {
      expect(polymarketSellApprovalFloor(bid: 0.50, slippagePct: 5, tick: 0.01),
          closeTo(0.48, 1e-9));
    });

    test('a position under 2¢: the venue\'s lowest price, 0.1¢', () {
      expect(
          polymarketSellApprovalFloor(bid: 0.013, slippagePct: 5, tick: 0.001),
          kPolymarketSellPriceFloor);
      expect(
          polymarketSellApprovalFloor(bid: 0.0005, slippagePct: 5, tick: 0.001),
          kPolymarketSellPriceFloor);
    });

    test('exactly 2¢ is not dust: the slippage floor', () {
      expect(
          polymarketSellApprovalFloor(bid: 0.02, slippagePct: 5, tick: 0.001),
          closeTo(0.019, 1e-9));
    });
  });

  group('the rungs', () {
    test('a normal book that did not move: one fill-and-kill rung at the '
        'approved floor, the whole sweep the approval allows', () {
      expect(
          polymarketSellLadder(
              approvedFloor: 0.48, freshBid: 0.50, slippagePct: 5, tick: 0.01),
          _prices([0.48]));
    });

    test('a bid that rose: the floor at the new bid first, then wider, '
        'down to the approved floor and never under it', () {
      final rungs = polymarketSellLadder(
          approvedFloor: 0.48, freshBid: 0.60, slippagePct: 5, tick: 0.01);
      expect(rungs, _prices([0.57, 0.54, 0.48]));
      expect(rungs.every((r) => r >= 0.48 - 1e-9), isTrue);
      expect(rungs.last, closeTo(0.48, 1e-9));
    });

    test('a sub-2¢ position: from the floor at the bid down to 0.1¢', () {
      final rungs = polymarketSellLadder(
          approvedFloor: kPolymarketSellPriceFloor,
          freshBid: 0.013,
          slippagePct: 5,
          tick: 0.001);
      expect(rungs, _prices([0.012, 0.011, 0.008, 0.003, 0.001]));
      expect(rungs.length, greaterThan(1));
      expect(rungs.last, kPolymarketSellPriceFloor);
    });

    test('rungs descend and none is under the approved floor, whatever the '
        'book', () {
      for (final (floor, bid, slip, tick) in [
        (0.48, 0.50, 5.0, 0.01),
        (0.48, 0.75, 5.0, 0.01),
        (0.001, 0.013, 5.0, 0.001),
        (0.001, 0.004, 5.0, 0.001),
        (0.30, 0.31, 0.0, 0.01),
        (0.955, 0.98, 2.0, 0.001),
      ]) {
        final rungs = polymarketSellLadder(
            approvedFloor: floor, freshBid: bid, slippagePct: slip, tick: tick);
        expect(rungs, isNotEmpty);
        for (var i = 1; i < rungs.length; i++) {
          expect(rungs[i], lessThan(rungs[i - 1]));
        }
        expect(rungs.every((r) => r >= floor - 1e-9), isTrue,
            reason: 'floor $floor bid $bid: $rungs');
        expect(rungs.every((r) => r >= kPolymarketSellPriceFloor), isTrue);
        expect(rungs.last, closeTo(floor, 1e-9));
      }
    });

    test('a bid that fell under the approved floor: nothing is sent, the '
        'retry names the floor at the new bid', () {
      expect(
          () => polymarketSellLadder(
              approvedFloor: 0.48, freshBid: 0.40, slippagePct: 5, tick: 0.01),
          throwsA(isA<PolymarketSellPriceMoved>()
              .having((e) => e.price, 'price', 0.40)
              .having((e) => e.limit, 'limit', 0.48)
              .having((e) => e.retryPrice, 'retry', closeTo(0.38, 1e-9))));
    });

    test('a bid that could not be read: the approved floor alone', () {
      expect(
          polymarketSellLadder(
              approvedFloor: 0.48, freshBid: null, slippagePct: 5, tick: 0.01),
          _prices([0.48]));
    });
  });

  group('every rung killed', () {
    test('a book with no bids at all: the honest no-buyers failure, '
        'counted as no liquidity', () {
      final outcome = polymarketSellLadderOutcome(
          lastError: Exception(_fakKilled),
          bookRead: true,
          bestBid: null,
          approvedFloor: 0.012,
          slippagePct: 5,
          tick: 0.001);
      expect(outcome, isA<PolymarketSellNoBids>());
      expect(TrackingService.errorCategory(outcome), 'no_route');
      expect(polymarketSellKilledForWantOfBids(outcome), isTrue);
    });

    test('a bid now under the approved floor: the retry copy with the new '
        'floor', () {
      final outcome = polymarketSellLadderOutcome(
          lastError: Exception(_fakKilled),
          bookRead: true,
          bestBid: 0.40,
          approvedFloor: 0.48,
          slippagePct: 5,
          tick: 0.01);
      expect(
          outcome,
          isA<PolymarketSellPriceMoved>()
              .having((e) => e.limit, 'limit', 0.48)
              .having((e) => e.retryPrice, 'retry', closeTo(0.38, 1e-9)));
    });

    test('a bid that fell into dust: the retry reaches 0.1¢', () {
      final outcome = polymarketSellLadderOutcome(
          lastError: Exception(_fakKilled),
          bookRead: true,
          bestBid: 0.015,
          approvedFloor: 0.031,
          slippagePct: 5,
          tick: 0.001);
      expect(
          outcome,
          isA<PolymarketSellPriceMoved>()
              .having((e) => e.retryPrice, 'retry', kPolymarketSellPriceFloor));
    });

    test('bids still at or above the floor: the kill itself, no liquidity',
        () {
      final kill = Exception(_fakKilled);
      final outcome = polymarketSellLadderOutcome(
          lastError: kill,
          bookRead: true,
          bestBid: 0.50,
          approvedFloor: 0.48,
          slippagePct: 5,
          tick: 0.01);
      expect(outcome, same(kill));
      expect(TrackingService.errorCategory(outcome), 'no_route');
    });

    test('a book that could not be read again: the kill itself, or the '
        'ladder\'s own no-bids reason', () {
      final kill = Exception(_fokKilled);
      expect(
          polymarketSellLadderOutcome(
              lastError: kill,
              bookRead: false,
              bestBid: null,
              approvedFloor: 0.48,
              slippagePct: 5,
              tick: 0.01),
          same(kill));
      final none = polymarketSellLadderOutcome(
          lastError: null,
          bookRead: false,
          bestBid: null,
          approvedFloor: 0.48,
          slippagePct: 5,
          tick: 0.01);
      expect(TrackingService.errorCategory(none), 'no_route');
      expect(polymarketSellKilledForWantOfBids(none), isTrue);
    });

    test('a kill for want of bids is told from a refusal of the order', () {
      expect(polymarketSellKilledForWantOfBids(Exception(_fakKilled)), isTrue);
      expect(polymarketSellKilledForWantOfBids(Exception(_fokKilled)), isTrue);
      expect(
          polymarketSellKilledForWantOfBids(
              Exception('not enough balance / allowance')),
          isFalse);
      expect(polymarketSellKilledForWantOfBids(Exception('invalid signature')),
          isFalse);
    });
  });

  group('a partial fill', () {
    test('does not empty the position, so the token is not marked sold', () {
      expect(polymarketSaleEmptiesPosition(sold: 20, held: 43.48), isFalse);
      expect(polymarketSaleEmptiesPosition(sold: 999, held: 1000), isFalse);
    });

    test('the whole position sold, to float noise, is marked', () {
      expect(polymarketSaleEmptiesPosition(sold: 43.48, held: 43.48), isTrue);
      expect(
          polymarketSaleEmptiesPosition(sold: 43.4799999, held: 43.48), isTrue);
      expect(polymarketSaleEmptiesPosition(sold: 1000, held: 1000), isTrue);
    });
  });
}
