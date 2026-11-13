// lib/services/polymarket/sell_ladder.dart
//
// The rungs of a market sell, and what a sale that sold nothing says.
//
// A market sell used to be one fill-or-kill order at the slippage floor:
// the whole size at no less than the bid minus the slippage, or nothing.
// A thin book killed it every time. On 2026-11-04 a 43.48-share position
// worth $0.57 (1.3¢ a share) failed half a second after submit, and on
// 2026-11-01 a 1000-share position worth $0.50 failed four times before
// it sold: there were buyers, just not for every share at once within the
// floor, and the person could not exit.
//
// Now a market sell is fill-and-kill: it sells what the book has at or
// above its price and the rest stays with the person, sellable again at
// once. The rungs run from the floor at the bid read when the order is
// signed down to the floor the person approved, never under it; a wider
// rung than the approval would allow is not sent. For a position already
// trading under 2¢ the approval itself names the venue's lowest price,
// 0.1¢, so the ladder can reach whatever bid is left.

import 'dart:math' as math;

import 'package:kute/services/polymarket/market_buy_quote.dart';

/// The lowest price the venue takes a sell at (0.1¢).
const double kPolymarketSellPriceFloor = 0.001;

/// Under this bid a position is dust: the approval reaches the venue's
/// lowest price so the shares can leave at whatever bid is left.
const double kPolymarketDustSellBid = 0.02;

/// How many times the slippage doubles for the wider rungs, at most.
const int _kWiderRungs = 6;

double _clamp(double price) =>
    price.clamp(kPolymarketSellPriceFloor, 0.99).toDouble();

/// The worst price a market sell of a position bidding at [bid] asks the
/// person to approve: the floor at their slippage (polymarketSellFloor),
/// or [kPolymarketSellPriceFloor] for a dust position.
double polymarketSellApprovalFloor({
  required double bid,
  required double slippagePct,
  required double tick,
}) {
  if (!bid.isFinite || bid <= 0 || bid < kPolymarketDustSellBid) {
    return kPolymarketSellPriceFloor;
  }
  return _clamp(
      polymarketSellFloor(bid: bid, slippagePct: slippagePct, tick: tick));
}

/// The prices a market sell is sent at, highest first, every one at or
/// above [approvedFloor]: the floor at [freshBid] for the person's
/// slippage (polymarketSellSendPrice, which throws
/// [PolymarketSellPriceMoved] when the bid has fallen under the approved
/// floor), then the floors for the slippage doubled, while they stay
/// above the approved floor, then the approved floor itself. A bid that
/// was not read gives the approved floor alone.
List<double> polymarketSellLadder({
  required double approvedFloor,
  required double? freshBid,
  required double slippagePct,
  required double tick,
}) {
  final floor = _clamp(approvedFloor);
  final first = _clamp(polymarketSellSendPrice(
    approvedFloor: floor,
    freshBid: freshBid,
    slippagePct: slippagePct,
    tick: tick,
  ));
  final rungs = <double>[first];
  final bid = freshBid;
  if (bid != null && bid.isFinite && bid > 0 && bid < 1) {
    var slip = slippagePct > 0 ? slippagePct : 1.0;
    for (var i = 0; i < _kWiderRungs; i++) {
      slip *= 2;
      if (slip >= 100) break;
      final rung = _clamp(
          polymarketSellFloor(bid: bid, slippagePct: slip, tick: tick));
      if (rung < floor - 1e-9) break;
      if (rung < rungs.last - 1e-9) rungs.add(rung);
    }
  }
  if (floor < rungs.last - 1e-9) rungs.add(floor);
  return rungs;
}

/// Every rung was killed and the book, read again, has no bids at all.
/// Nothing was sold; no price would have.
class PolymarketSellNoBids implements Exception {
  const PolymarketSellNoBids();

  @override
  String toString() => 'No bids matched at this price: the book has no bids.';
}

/// What a market sell whose every rung was killed ends with, from the
/// book read after the last kill: [PolymarketSellNoBids] when the book
/// has no bid at all; [PolymarketSellPriceMoved] (with the floor a new
/// approval would name) when its best bid is under [approvedFloor], so a
/// wider rung would have crossed the approval; otherwise the last kill
/// itself ([lastError]), the book being thinner than it read. An unread
/// book ([bookRead] false) ends with the last kill too.
Object polymarketSellLadderOutcome({
  required Object? lastError,
  required bool bookRead,
  required double? bestBid,
  required double approvedFloor,
  required double slippagePct,
  required double tick,
}) {
  final fallback = lastError ??
      Exception('No bids matched at this price. The book may be thin. '
          'Try selling a smaller amount or wait for liquidity.');
  if (!bookRead) return fallback;
  if (bestBid == null || !bestBid.isFinite || bestBid <= 0) {
    return const PolymarketSellNoBids();
  }
  if (bestBid < approvedFloor - 1e-9) {
    return PolymarketSellPriceMoved(
      price: bestBid,
      limit: approvedFloor,
      retryPrice: polymarketSellApprovalFloor(
          bid: bestBid, slippagePct: slippagePct, tick: tick),
    );
  }
  return fallback;
}

/// Whether [error] is the order book killing a market sell for want of
/// bids (a fill-or-kill or fill-and-kill kill, or the ladder's own
/// "no bids matched"), as opposed to a refusal of the order itself.
bool polymarketSellKilledForWantOfBids(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('fok') ||
      text.contains('fak') ||
      text.contains('fully filled') ||
      text.contains('partially filled') ||
      text.contains('no orders found to match') ||
      text.contains('no bids matched');
}

/// Whether selling [sold] shares empties a position of [held] shares. Only
/// then is the token marked sold (the guard against a second order on a
/// stale tile); a partial sale leaves the rest sellable at once.
bool polymarketSaleEmptiesPosition({required double sold, required double held}) =>
    held <= 0 || sold >= held - math.max(1e-6, held * 1e-9);
