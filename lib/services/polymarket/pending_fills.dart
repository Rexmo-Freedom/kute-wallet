// lib/services/polymarket/pending_fills.dart
//
// A Predictions buy the venue just matched, between the match and the two
// reads that catch up with it. Pure rules, no I/O (the binding lives in
// `PolymarketTradingNotifier`):
//
//   * the POSITION: the Data API lists a new holding seconds to a minute
//     after the match. Until it does, the fill's shares count at the fill
//     price, so the Investments total never drops to "cash only" while
//     the position is on its way (founder, 2026-10-13: "$3.55 in
//     Predictions, placed a bet, and the total went to $6.65");
//   * the CASH: the CLOB matches off chain and settles on Polygon a few
//     seconds later, and the balance read is cached. Until a read shows
//     the spend, the fill's cost is taken off it, so the spent cash stops
//     counting as Available the moment the bet fills, and is never counted
//     next to the position it bought.
//
// A fill leaves once both reads have caught up, or after
// [kPendingFillTtl] whatever they say (a read that never shows it must
// not hold a phantom for good).

import 'package:flutter/foundation.dart' show immutable;

/// Longest a fill is carried for reads that have not caught up.
const Duration kPendingFillTtl = Duration(minutes: 5);

/// Shares within this of the expected size count as indexed (the API
/// rounds sizes).
const double _kSharesTolerance = 0.01;

/// Cash within this of the expected balance counts as settled.
const double _kCashToleranceUsd = 0.01;

@immutable
class PolymarketPendingFill {
  const PolymarketPendingFill({
    required this.key,
    required this.tokenId,
    required this.shares,
    required this.price,
    required this.costUsd,
    required this.expectedShares,
    required this.cashBeforeUsd,
    required this.at,
    this.indexed = false,
    this.cashSettled = false,
  });

  /// The order id (or the token and time when the venue echoed none).
  final String key;

  /// The outcome token bought (`Position.asset`).
  final String tokenId;

  /// Shares the positions read does not show yet.
  final double shares;

  /// The fill price, pUSD per share.
  final double price;

  /// What the fill spent (pUSD), the fill's own figure: what comes off
  /// the cash until a read shows it.
  final double costUsd;

  /// The token's size the positions read shows once this fill is in it.
  final double expectedShares;

  /// The venue's cash before the fill, net of the earlier fills: what a
  /// read shows once those have settled and this one has not. A read at
  /// or under this less [costUsd] shows the spend.
  final double cashBeforeUsd;

  final DateTime at;

  /// The positions read lists the shares.
  final bool indexed;

  /// A cash read shows the spend.
  final bool cashSettled;

  /// What the header adds for it: the shares at the fill price while the
  /// positions read lacks them.
  double get valueUsd {
    if (indexed || !(shares > 0) || !price.isFinite || price <= 0) return 0;
    return shares * price;
  }

  PolymarketPendingFill copyWith({
    double? shares,
    bool? indexed,
    bool? cashSettled,
  }) =>
      PolymarketPendingFill(
        key: key,
        tokenId: tokenId,
        shares: shares ?? this.shares,
        price: price,
        costUsd: costUsd,
        expectedShares: expectedShares,
        cashBeforeUsd: cashBeforeUsd,
        at: at,
        indexed: indexed ?? this.indexed,
        cashSettled: cashSettled ?? this.cashSettled,
      );

  @override
  bool operator ==(Object other) =>
      other is PolymarketPendingFill &&
      other.key == key &&
      other.tokenId == tokenId &&
      other.shares == shares &&
      other.price == price &&
      other.costUsd == costUsd &&
      other.expectedShares == expectedShares &&
      other.cashBeforeUsd == cashBeforeUsd &&
      other.at == at &&
      other.indexed == indexed &&
      other.cashSettled == cashSettled;

  @override
  int get hashCode => Object.hash(key, tokenId, shares, price, costUsd,
      expectedShares, cashBeforeUsd, at, indexed, cashSettled);

  @override
  String toString() => 'PolymarketPendingFill($tokenId, $shares sh, '
      '\$$costUsd, indexed: $indexed, cashSettled: $cashSettled)';
}

/// A new fill of [shares] of [tokenId] for [costUsd], given the token's
/// size the positions read shows now ([listedShares]), the fills already
/// pending, and the venue's cash as the state holds it ([stateCashUsd],
/// already net of the pending fills' unsettled costs). Null when the fill
/// says nothing usable.
PolymarketPendingFill? newPendingFill({
  required String key,
  required String tokenId,
  required double shares,
  required double costUsd,
  required double listedShares,
  required double stateCashUsd,
  required List<PolymarketPendingFill> pending,
  required DateTime now,
}) {
  if (tokenId.isEmpty ||
      !shares.isFinite ||
      shares <= 0 ||
      !costUsd.isFinite ||
      costUsd <= 0) {
    return null;
  }
  var expected = listedShares.isFinite && listedShares > 0 ? listedShares : 0.0;
  for (final f in pending) {
    if (f.tokenId == tokenId && !f.indexed) expected += f.shares;
  }
  final cash = stateCashUsd.isFinite && stateCashUsd > 0 ? stateCashUsd : 0.0;
  return PolymarketPendingFill(
    key: key,
    tokenId: tokenId,
    shares: shares,
    price: costUsd / shares,
    costUsd: costUsd,
    expectedShares: expected + shares,
    cashBeforeUsd: cash,
    at: now,
  );
}

/// The fills against a fresh positions read: a fill is indexed once the
/// token's listed size reaches what it expects; one the read shows only
/// part of keeps the rest. Fills both reads have caught up with, and
/// fills older than [kPendingFillTtl], leave.
List<PolymarketPendingFill> reconcilePendingFills(
  List<PolymarketPendingFill> fills,
  Map<String, double> listedShares,
  DateTime now,
) {
  final out = <PolymarketPendingFill>[];
  for (final f in fills) {
    if (now.difference(f.at) > kPendingFillTtl) continue;
    var next = f;
    if (!f.indexed) {
      final listed = listedShares[f.tokenId] ?? 0;
      final missing = f.expectedShares - listed;
      if (missing <= _kSharesTolerance) {
        next = f.copyWith(indexed: true);
      } else if (missing < f.shares) {
        next = f.copyWith(shares: missing);
      }
    }
    if (next.indexed && next.cashSettled) continue;
    out.add(next);
  }
  return out;
}

/// A raw cash read net of the fills it does not show yet: a fill whose
/// spend the read shows is settled from then on; the others' costs come
/// off. Returns the net cash and the fills with their flags.
(double, List<PolymarketPendingFill>) netCashOfPendingFills(
  double rawCashUsd,
  List<PolymarketPendingFill> fills,
) {
  final raw = rawCashUsd.isFinite && rawCashUsd > 0 ? rawCashUsd : 0.0;
  var net = raw;
  final out = <PolymarketPendingFill>[];
  // The fills in the order they happened: each one's spend shows once the
  // read is at or under its own "before" figure less what it cost.
  final ordered = [...fills]..sort((a, b) => a.at.compareTo(b.at));
  for (final f in ordered) {
    if (f.cashSettled) {
      out.add(f);
      continue;
    }
    if (raw <= f.cashBeforeUsd - f.costUsd + _kCashToleranceUsd) {
      out.add(f.copyWith(cashSettled: true));
      continue;
    }
    net -= f.costUsd;
    out.add(f);
  }
  return (net > 0 ? net : 0.0, out);
}

/// What the header adds for [fills]: the shares no positions read lists.
double pendingFillsValueUsd(Iterable<PolymarketPendingFill> fills) {
  var sum = 0.0;
  for (final f in fills) {
    sum += f.valueUsd;
  }
  return sum;
}
