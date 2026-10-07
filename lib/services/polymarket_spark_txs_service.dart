// Tracks Spark Lightning/Bitcoin transactions that originated from a
// Polymarket flow — bet funding (BTC → Orchestra → USDC.e) on the way
// out, claim deliveries (Orchestra → BTC) on the way in. Used to hide
// these from the home Activity feed since the user-meaningful row
// ("Bought No · $1.49", "Won $4.82", etc.) already conveys what
// happened. Manual BTC↔USDC swaps via the Stables convert flow are
// NOT tagged and stay visible.
//
// Storage:
//   - `polymarket_spark_txs` (key = Spark tx id, value = epoch ms)
//     for outgoing tagged-at-send-time txs (bet funding).
//   - `polymarket_spark_claim_windows` (key = epoch ms, value = JSON
//     `{ts, microUsd}`) for *expected incoming* deliveries from
//     Orchestra after a claim — we don't have the inbound tx id at
//     trigger time, so we register a time-bounded "expected delivery
//     of ~$X" and match against it when Spark indexes the receive.
//   - 30-day retention on outbound tags; 60-min retention on inbound
//     claim windows (Orchestra typically delivers in 1–3 min, plus
//     buffer).
//
// Every accessor null-guards the Hive boxes: transaction-list getters
// call into here from pure model code, and a not-yet-open box (early
// bootstrap, unit tests) must degrade to "nothing tagged" rather than
// throw HiveError out of a balance computation.

import 'dart:convert';

import 'package:hive_ce/hive.dart';

class PolymarketSparkTxsService {
  static const _boxName = 'polymarket_spark_txs';
  static const Duration retention = Duration(days: 30);

  static Box<String>? get _box =>
      Hive.isBoxOpen(_boxName) ? Hive.box<String>(_boxName) : null;

  /// Tag a Spark tx id as part of a Polymarket flow. Subsequent reads
  /// of the home Activity feed will filter it out.
  static void tag(String txId) {
    if (txId.isEmpty) return;
    _box?.put(txId, DateTime.now().millisecondsSinceEpoch.toString());
  }

  /// True if [txId] is a tagged Polymarket-flow tx (within retention).
  /// Side-effect: GCs stale entries on access.
  static bool isTagged(String txId) {
    if (txId.isEmpty) return false;
    final box = _box;
    if (box == null) return false;
    final raw = box.get(txId);
    if (raw == null) return false;
    final ts = int.tryParse(raw);
    if (ts == null) {
      box.delete(txId);
      return false;
    }
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age > retention.inMilliseconds) {
      box.delete(txId);
      return false;
    }
    return true;
  }

  /// Snapshot of all tagged tx ids (post-GC). Used by transaction list
  /// builders that want to do bulk filtering.
  static Set<String> snapshot() {
    final box = _box;
    if (box == null) return const {};
    final result = <String>{};
    final stale = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final ts = int.tryParse(raw);
      if (ts == null || now - ts > retention.inMilliseconds) {
        stale.add(key as String);
        continue;
      }
      result.add(key as String);
    }
    for (final k in stale) {
      box.delete(k);
    }
    return result;
  }

  // ─── Orchestra exchange order tagging ───────────────────────────────
  //
  // Distinguishes bet-flow Orchestra exchanges (plumbing, hide from home)
  // from user-initiated Convert exchanges (show on home — they ARE the
  // user-meaningful row). Both use `provider: 'Orchestra'` on the
  // SwapOrder model, so we tag the bet-flow orderIds via a
  // separate Hive box and the home filter only hides tagged ones.
  static const _orderBoxName = 'polymarket_orchestra_orders';
  static const Duration orderRetention = Duration(days: 30);

  static Box<String>? get _ordersBox =>
      Hive.isBoxOpen(_orderBoxName) ? Hive.box<String>(_orderBoxName) : null;

  /// Tag an Orchestra orderId as belonging to the bet/claim flow.
  /// The home Activity feed will hide its SwapOrderTransaction row.
  static void tagOrchestraOrder(String orderId) {
    if (orderId.isEmpty) return;
    _ordersBox?.put(
        orderId, DateTime.now().millisecondsSinceEpoch.toString());
  }

  /// True if [orderId] was tagged by the bet flow (within retention).
  static bool isOrchestraOrderTagged(String orderId) {
    if (orderId.isEmpty) return false;
    final box = _ordersBox;
    if (box == null) return false;
    final raw = box.get(orderId);
    if (raw == null) return false;
    final ts = int.tryParse(raw);
    if (ts == null) {
      box.delete(orderId);
      return false;
    }
    if (DateTime.now().millisecondsSinceEpoch - ts >
        orderRetention.inMilliseconds) {
      box.delete(orderId);
      return false;
    }
    return true;
  }

  /// Snapshot of all tagged Orchestra orderIds (post-GC). Used by the
  /// home Activity filter so a single Hive walk covers all rows.
  static Set<String> orchestraOrderSnapshot() {
    final box = _ordersBox;
    if (box == null) return const {};
    final result = <String>{};
    final stale = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final ts = int.tryParse(raw);
      if (ts == null || now - ts > orderRetention.inMilliseconds) {
        stale.add(key as String);
        continue;
      }
      result.add(key as String);
    }
    for (final k in stale) {
      box.delete(k);
    }
    return result;
  }

  // ─── Expected inbound deliveries (claim → Spark BTC) ────────────────

  static const _claimWindowsBoxName = 'polymarket_spark_claim_windows';
  static const Duration claimWindow = Duration(minutes: 60);

  static Box<String>? get _claimsBox => Hive.isBoxOpen(_claimWindowsBoxName)
      ? Hive.box<String>(_claimWindowsBoxName)
      : null;

  /// Register an expected inbound BTC delivery from Orchestra after a
  /// claim. [microUsd] is the USDC.e amount that was sent through
  /// Orchestra (we don't know the BTC amount at trigger time — we'll
  /// match by approximate USD equivalent when the Spark receive lands).
  static void recordExpectedClaimDelivery({required BigInt microUsd}) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    _claimsBox?.put(
      ts.toString(),
      jsonEncode({'ts': ts, 'microUsd': microUsd.toString()}),
    );
  }

  /// Total USDC.e (in micro-USD) of open expected-claim-delivery
  /// windows — i.e. routes currently in flight from Orchestra back
  /// to Spark BTC. UI uses this to drive the "Routing to Bitcoin"
  /// banner: when non-zero, the user has winnings mid-flight and we
  /// surface the indicator across Home + Predictions. Stale windows
  /// (older than [claimWindow]) are excluded but not GC'd here —
  /// `consumeMatchingClaim` handles GC on receive-side.
  static BigInt pendingDeliveryTotalMicro() {
    final box = _claimsBox;
    if (box == null) return BigInt.zero;
    final now = DateTime.now().millisecondsSinceEpoch;
    BigInt total = BigInt.zero;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        final wrap = jsonDecode(raw) as Map<String, dynamic>;
        final ts = wrap['ts'] as int? ?? 0;
        if (now - ts > claimWindow.inMilliseconds) continue;
        final amt = BigInt.tryParse(
                (wrap['microUsd'] as String?) ?? '0') ??
            BigInt.zero;
        total += amt;
      } catch (_) {}
    }
    return total;
  }

  /// True if [satsAmount] received at [arrivedAtMs] looks like an Orchestra
  /// claim delivery. Match heuristic: the Spark receive arrived within
  /// [claimWindow] of a recorded expected delivery, and there's at least
  /// one un-matched claim in the window. We don't compare amounts strictly
  /// because BTC↔USD price changes between claim trigger and delivery.
  /// First matching window is consumed (deleted) so a single inbound
  /// receive doesn't keep matching unrelated claims.
  static bool consumeMatchingClaim({
    required int receivedAtMs,
  }) {
    final box = _claimsBox;
    if (box == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    String? matchKey;
    final stale = <String>[];
    int? bestDelta;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        final wrap = jsonDecode(raw) as Map<String, dynamic>;
        final ts = wrap['ts'] as int? ?? 0;
        if (now - ts > claimWindow.inMilliseconds) {
          stale.add(key as String);
          continue;
        }
        final delta = (receivedAtMs - ts).abs();
        if (delta > claimWindow.inMilliseconds) continue;
        if (bestDelta == null || delta < bestDelta) {
          bestDelta = delta;
          matchKey = key as String;
        }
      } catch (_) {
        stale.add(key as String);
      }
    }
    for (final k in stale) {
      box.delete(k);
    }
    if (matchKey == null) return false;
    box.delete(matchKey);
    return true;
  }

  // ─── Confirmed Orchestra delivery legs (hide raw Spark receive) ─────
  //
  // Unlike the time-only claim-window heuristic above (whose home-feed
  // hide is disabled — see transactions_model.homeTransactionsSorted),
  // these ids are tagged only after a STRONG match: the receive landed
  // inside a pending Orchestra→Spark exchange's delivery window AND its
  // sats are within tolerance of that exchange's quoted out. The
  // exchange row is settled with the real amount in the same reconcile
  // pass, so hiding the raw receive never leaves the feed story-less.

  static const _deliveryBoxName = 'orchestra_delivery_spark_txs';

  static Box<String>? get _deliveryBox => Hive.isBoxOpen(_deliveryBoxName)
      ? Hive.box<String>(_deliveryBoxName)
      : null;

  /// Tag a Spark receive as the delivery leg of a settled Orchestra
  /// exchange. The home Activity feed hides it.
  static void tagOrchestraDelivery(String txId) {
    if (txId.isEmpty) return;
    _deliveryBox?.put(
        txId, DateTime.now().millisecondsSinceEpoch.toString());
  }

  /// Snapshot of tagged delivery-leg tx ids (post-GC, same 30-day
  /// retention as the outbound tags).
  static Set<String> orchestraDeliverySnapshot() {
    final box = _deliveryBox;
    if (box == null) return const {};
    final result = <String>{};
    final stale = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final ts = int.tryParse(raw);
      if (ts == null || now - ts > retention.inMilliseconds) {
        stale.add(key as String);
        continue;
      }
      result.add(key as String);
    }
    for (final k in stale) {
      box.delete(k);
    }
    return result;
  }
}
