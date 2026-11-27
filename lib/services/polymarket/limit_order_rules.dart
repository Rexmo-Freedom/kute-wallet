// lib/services/polymarket/limit_order_rules.dart
//
// The arithmetic of a resting limit order, exact, before anything is
// approved:
//
//   * the price: on the market's tick (0.1, 0.01, 0.005, 0.0025, 0.001 or
//     0.0001 of a dollar) and inside [tick, 1 - tick]. A price off the
//     tick is refused by the order encoder (order_amounts.dart) after
//     approval, so every seed, step and dial snaps to it at entry, and a
//     price still off it (the tick moved) is an inline error;
//   * the shares a stake buys at a limit, floored to a hundredth in
//     integers: \$1.40 at 28¢ is 5.00 shares, never the 4.99 that
//     1.40 / 0.28 = 4.999999… floored to;
//   * the venue's minimum order size in shares, on buys and sells;
//   * the shares already offered in resting sells, which a new sale of the
//     same token cannot offer again.
//
// Public market facts and the person's own order list only. Nothing here
// signs, places or reads anything.

import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

/// The venue's minimum order size where the market's own figure could not
/// be read: Polymarket's markets quote 5 shares.
const double kPolymarketDefaultMinOrderShares = 5.0;

/// The tick used to snap a price before the market's own is known: a
/// whole cent is on every tick the venue quotes under 0.1.
const double kPolymarketFallbackTick = 0.01;

const int _scale = 1000000;

int _micros(double value) => (value * _scale).round();

double _fromMicros(int micros) =>
    double.parse((micros / _scale).toStringAsFixed(6));

/// The increment [tick] (a venue string such as "0.01") as a number, or
/// null when it is not one the venue quotes.
double? polymarketTickValue(String? tick) => switch (tick) {
      '0.1' => 0.1,
      '0.01' => 0.01,
      '0.005' => 0.005,
      '0.0025' => 0.0025,
      '0.001' => 0.001,
      '0.0001' => 0.0001,
      _ => null,
    };

/// A usable tick: [tick] when it is one the venue quotes, else the
/// fallback whole cent.
double polymarketUsableTick(double? tick) {
  if (tick == null || !tick.isFinite || tick <= 0 || tick >= 1) {
    return kPolymarketFallbackTick;
  }
  final micros = _micros(tick);
  return micros <= 0 ? kPolymarketFallbackTick : _fromMicros(micros);
}

/// Which way a price is moved onto the tick.
enum PolymarketTickSnap {
  /// To the tick at or under it: a buy's seed (never above the market).
  down,

  /// To the tick at or over it: a sell's seed.
  up,

  /// To the nearest tick.
  nearest,
}

/// [price] moved onto [tick]'s grid ([snap]) and kept inside
/// [tick, 1 - tick].
double polymarketSnapToTick(double price, double tick,
    {PolymarketTickSnap snap = PolymarketTickSnap.nearest}) {
  final t = _micros(polymarketUsableTick(tick));
  final maxSteps = _scale ~/ t - 1;
  if (!price.isFinite) return _fromMicros(t);
  final steps = price * _scale / t;
  // The tolerance absorbs binary noise only (53.000000001¢ is 53¢).
  var n = switch (snap) {
    PolymarketTickSnap.down => (steps + 1e-6).floor(),
    PolymarketTickSnap.up => (steps - 1e-6).ceil(),
    PolymarketTickSnap.nearest => steps.round(),
  };
  if (n < 1) n = 1;
  if (n > maxSteps) n = maxSteps;
  return _fromMicros(n * t);
}

/// One tick up ([direction] > 0) or down from [price], inside
/// [tick, 1 - tick]. A price off the tick (the tick moved under it) goes
/// to the tick on that side first: 53.5¢ up is 54¢, down 53¢.
double polymarketStepLimitPrice(double price, double tick, int direction) {
  final usable = polymarketUsableTick(tick);
  if (direction == 0) return polymarketSnapToTick(price, usable);
  if (!polymarketPriceOnTick(price, usable)) {
    return polymarketSnapToTick(price, usable,
        snap: direction > 0 ? PolymarketTickSnap.up : PolymarketTickSnap.down);
  }
  final t = _micros(usable);
  final from = _micros(polymarketSnapToTick(price, usable));
  return polymarketSnapToTick(
      _fromMicros(from + (direction > 0 ? t : -t)), usable);
}

/// Whether [price] lies on [tick]'s grid.
bool polymarketPriceOnTick(double price, double tick) {
  if (!price.isFinite || !tick.isFinite || tick <= 0) return false;
  final steps = price * _scale / _micros(tick);
  return (steps - steps.round()).abs() <= 1e-6;
}

/// Whether [price] lies inside the venue's range for [tick].
bool polymarketPriceInRange(double price, double tick) {
  if (!price.isFinite || !tick.isFinite || tick <= 0) return false;
  final p = _micros(price), t = _micros(tick);
  return p >= t && p <= _scale - t;
}

/// What keeps a limit price from being placed.
enum PolymarketLimitPriceIssue { offTick, outOfRange }

/// Null when [price] can rest on a market whose tick is [tick].
PolymarketLimitPriceIssue? polymarketLimitPriceIssue(
    double price, double tick) {
  if (!polymarketPriceInRange(price, tick)) {
    return PolymarketLimitPriceIssue.outOfRange;
  }
  if (!polymarketPriceOnTick(price, tick)) {
    return PolymarketLimitPriceIssue.offTick;
  }
  return null;
}

/// The shares [amountUsd] buys at the limit [price], floored to a
/// hundredth of a share in integers. Their cost (shares × price, exact in
/// micro-dollars) never exceeds the stake.
double polymarketLimitBuyShares(double amountUsd, double price) {
  if (!amountUsd.isFinite || amountUsd <= 0) return 0;
  if (!price.isFinite || price <= 0 || price >= 1) return 0;
  final amount = BigInt.from(_micros(amountUsd));
  final p = BigInt.from(_micros(price));
  if (p <= BigInt.zero) return 0;
  final hundredths = amount * BigInt.from(100) ~/ p;
  return hundredths.toInt() / 100;
}

/// The hundredths of a share [shares] stands for, read without float
/// noise (5.0000000001 and 4.9999999999 are both 500).
int polymarketShareHundredths(double shares) {
  if (!shares.isFinite || shares <= 0) return 0;
  return (shares * 100 + 1e-6).floor();
}

/// The smallest stake, in whole cents, whose shares at [price] reach
/// [minShares] ([polymarketLimitBuyShares] of it is at least that).
double polymarketLimitBuyMinimumUsd(double minShares, double price) {
  if (!price.isFinite || price <= 0 || price >= 1) return 0;
  if (!minShares.isFinite || minShares <= 0) return 0;
  final need = BigInt.from((minShares * 100 - 1e-6).ceil());
  final p = BigInt.from(_micros(price));
  final scale = BigInt.from(_scale);
  final cents = (need * p + scale - BigInt.one) ~/ scale;
  return cents.toInt() / 100;
}

/// Whether [shares] is at least the venue's [minShares].
bool polymarketMeetsMinimumShares(double shares, double minShares) =>
    polymarketShareHundredths(shares) >=
    (minShares * 100 - 1e-6).ceil();

/// The shares of [tokenId] offered in [orders]' resting sells (what is
/// left unfilled of each): the venue holds them for those orders, so a
/// new sale cannot offer them again.
double polymarketSharesInRestingSells(List<Order> orders, String? tokenId) {
  if (tokenId == null || tokenId.isEmpty) return 0;
  var hundredths = 0;
  for (final o in orders) {
    if (o.assetId != tokenId || o.side.toUpperCase() != 'SELL') continue;
    final left = (double.tryParse(o.originalSize) ?? 0) -
        (double.tryParse(o.sizeMatched) ?? 0);
    if (left > 0) hundredths += (left * 100 - 1e-6).ceil();
  }
  return hundredths / 100;
}

/// The shares of a [held] position free to sell: less what [locked] in
/// resting sells, never under zero, to the hundredth.
double polymarketFreeShares(double held, double locked) {
  final free = polymarketShareHundredths(held) -
      (locked <= 0 ? 0 : (locked * 100 - 1e-6).ceil());
  return free <= 0 ? 0 : free / 100;
}

/// "53¢", "3.4¢", "0.25¢": a limit price in cents to its tick's precision.
String polymarketLimitCentsLabel(double price) {
  var s = (price * 100).toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  return '$s¢';
}

/// Why a resting limit was stopped before its approval: the market's own
/// terms, read just before, do not take it as it stands. Nothing was
/// signed; the ticket says which and the person adjusts it.
enum PolymarketLimitRefusal { offTick, outOfRange, belowMinimum, tickUnknown }

class PolymarketLimitRefused implements Exception {
  const PolymarketLimitRefused(this.reason, {this.tick, this.minShares});

  final PolymarketLimitRefusal reason;

  /// The market's increment as read, for "in steps of 0.1¢".
  final double? tick;

  /// The venue's minimum in shares, for the minimum's line.
  final double? minShares;

  @override
  String toString() => 'Limit refused before approval: ${reason.name}';
}

/// The check a resting limit BUY of [amountUsd] at [price] passes before
/// its approval, on the market's [tickSize] (the venue's string) and
/// [minShares]: throws [PolymarketLimitRefused] when it would be refused.
void polymarketCheckLimitBuy({
  required double amountUsd,
  required double price,
  required String? tickSize,
  required double? minShares,
}) {
  final tick = polymarketTickValue(tickSize);
  if (tick == null) {
    throw const PolymarketLimitRefused(PolymarketLimitRefusal.tickUnknown);
  }
  switch (polymarketLimitPriceIssue(price, tick)) {
    case PolymarketLimitPriceIssue.offTick:
      throw PolymarketLimitRefused(PolymarketLimitRefusal.offTick, tick: tick);
    case PolymarketLimitPriceIssue.outOfRange:
      throw PolymarketLimitRefused(PolymarketLimitRefusal.outOfRange,
          tick: tick);
    case null:
      break;
  }
  final min = minShares != null && minShares > 0
      ? minShares
      : kPolymarketDefaultMinOrderShares;
  if (!polymarketMeetsMinimumShares(
      polymarketLimitBuyShares(amountUsd, price), min)) {
    throw PolymarketLimitRefused(PolymarketLimitRefusal.belowMinimum,
        tick: tick, minShares: min);
  }
}

/// Whether a typed dollar figure [amountUsd] stays within [shares] at
/// [price], allowing the cent the figure was rounded up to (Max writes
/// 4.67 shares at 53¢ as \$2.48, which divides back to 4.679).
bool polymarketAmountWithinShares(
        double amountUsd, double shares, double price) =>
    amountUsd <= (shares * price * 100 - 1e-6).ceilToDouble() / 100 + 1e-9;
