// lib/models/hl_price_line.dart
//
// A price line: a level the person set on an Investing market's chart. It
// lives on this device only. While the app is open and that market's price
// is live somewhere in the app, a crossing marks the line as reached. It is
// not a notification and nothing checks it while the app is closed.
//
// Direction comes from the price when the line was set: a line above the
// price waits for a rise to it, a line below waits for a fall. One-shot:
// once reached it stays reached until the person removes it.

import 'package:kute/models/hyperliquid_market.dart';

/// Where a line sits against the price when it was set.
enum HlPriceLineDirection { above, below }

/// Lines one person may keep, across every market.
const int kHlPriceLineLimit = 20;

/// How far from the price a line may be, as a factor either way.
const double kHlPriceLineMaxFactor = 10;

/// Closer to the price than this fraction is "at the price": no line.
const double kHlPriceLineMinGap = 0.0001;

/// Why a level was not accepted.
enum HlPriceLineRefusal { limit, atPrice, tooFar }

/// The refusal for [level] against the price [reference] with [count] lines
/// kept already, or null when it is fine.
HlPriceLineRefusal? hlPriceLineRefusal({
  required double level,
  required double? reference,
  required int count,
}) {
  if (count >= kHlPriceLineLimit) return HlPriceLineRefusal.limit;
  final now = reference;
  if (now == null || !now.isFinite || now <= 0) {
    return HlPriceLineRefusal.atPrice;
  }
  if (!level.isFinite || level <= 0) return HlPriceLineRefusal.tooFar;
  if (level > now * kHlPriceLineMaxFactor ||
      level < now / kHlPriceLineMaxFactor) {
    return HlPriceLineRefusal.tooFar;
  }
  if ((level - now).abs() < now * kHlPriceLineMinGap) {
    return HlPriceLineRefusal.atPrice;
  }
  return null;
}

class HlPriceLine {
  const HlPriceLine({
    required this.id,
    required this.marketKey,
    required this.coin,
    required this.wireCoin,
    required this.kind,
    required this.level,
    required this.direction,
    required this.createdAtMs,
    this.reachedAtMs,
  });

  final String id;

  /// The market's identity (hlChartDrawingMarketKey).
  final String marketKey;

  /// The display coin the live prices are keyed by.
  final String coin;

  /// The market the display coin must be priced from: spot, native perps
  /// and builder venues can share a display coin.
  final String wireCoin;

  final HlMarketKind kind;
  final double level;
  final HlPriceLineDirection direction;
  final int createdAtMs;

  /// When the price got there; null while waiting.
  final int? reachedAtMs;

  bool get isReached => reachedAtMs != null;

  /// Whether [price] is at or past the line, seen from where it was set.
  bool reachedBy(double price) =>
      direction == HlPriceLineDirection.above ? price >= level : price <= level;

  HlPriceLine reachedAt(int ms) => HlPriceLine(
        id: id,
        marketKey: marketKey,
        coin: coin,
        wireCoin: wireCoin,
        kind: kind,
        level: level,
        direction: direction,
        createdAtMs: createdAtMs,
        reachedAtMs: ms,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'market': marketKey,
        'coin': coin,
        'wire': wireCoin,
        'kind': kind.name,
        'level': level,
        'dir': direction.name,
        'at': createdAtMs,
        if (reachedAtMs != null) 'hit': reachedAtMs,
      };

  /// Null for a corrupt record.
  static HlPriceLine? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final market = json['market'];
    final coin = json['coin'];
    final wire = json['wire'];
    final level = json['level'];
    final at = json['at'];
    final hit = json['hit'];
    if (id is! String ||
        market is! String ||
        coin is! String ||
        wire is! String ||
        level is! num ||
        at is! num) {
      return null;
    }
    final price = level.toDouble();
    if (!price.isFinite || price <= 0) return null;
    return HlPriceLine(
      id: id,
      marketKey: market,
      coin: coin,
      wireCoin: wire,
      kind: json['kind'] == HlMarketKind.spot.name
          ? HlMarketKind.spot
          : HlMarketKind.perp,
      level: price,
      direction: json['dir'] == HlPriceLineDirection.below.name
          ? HlPriceLineDirection.below
          : HlPriceLineDirection.above,
      createdAtMs: at.toInt(),
      reachedAtMs: hit is num ? hit.toInt() : null,
    );
  }
}
