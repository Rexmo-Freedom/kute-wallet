// lib/services/orchestra/own_bitcoin_deliveries.dart
//
// Which Spark receives are the wallet's own Orchestra deliveries to
// Bitcoin, so Activity lists each such move once: the move's row (a
// withdrawal from Investments, a purchase from Dollars, a multi-source
// move whose legs these rows are) and never a "Received ₿" row beside it.
//
// A receive is a delivery when:
//
//  1. the delivery reconciler linked it to the row it settled
//     (`PolymarketSparkTxsService.orchestraDeliveryLinks`): that row is on
//     the list, by id, by the order its quote became, or by its settlement
//     operation. Deterministic, and it survives a restart.
//  2. otherwise, a row delivering bitcoin to the wallet's own Spark balance
//     claims it by amount and time, one receive per row and one row per
//     receive, the closest amount first, then the closest time. The wallet's
//     own withdrawals (Investing, Predictions, Dollars to Bitcoin) and
//     anything settling to its own address may land up to
//     [kOwnDeliveryArrivalWindow] after the row started: a Circle CCTP leg
//     out of Investing or an order Orchestra held for screening routinely
//     lands well past the hour the old rule allowed, and its receive then
//     stood beside the move for good.
//
// A row whose bitcoin amount is not known yet (a CCTP leg before its
// order reports one) claims nothing by amount: only the reconciler's link
// can tie a receive to it. A receive nothing claims keeps its own row.
// Pure, so the lists and the tests read the same answer.

import 'dart:math' as math;

import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/orchestra/own_spark_arrivals.dart'
    show OwnSparkArrivals;
import 'package:kute/services/orchestra/venue_arrivals.dart'
    show OrchestraOrderIds;
import 'package:kute/services/polymarket_spark_txs_service.dart'
    show OrchestraDeliveryLink;
import 'package:kute/services/security/address_guard.dart'
    show sparkIdentityPubkeyHex;

/// How long after one of the wallet's own deliveries to Bitcoin started
/// its bitcoin may still land and be folded into it: the same day the
/// dollar side gives a venue withdrawal (`kVenueWithdrawalArrivalWindow`).
const Duration kOwnDeliveryArrivalWindow = Duration(hours: 24);

/// A row stamped a little after its money moved (written when the flow
/// returned) may see its receive land just before it.
const Duration kOwnDeliveryEarlyMargin = Duration(minutes: 10);

/// Whether [address] is one of [own] (lowercased), either spelling of a
/// Spark address included (`sp1…` and `spark1…` encode the same key, and
/// the SDK's spelling is not always the one a provider echoes back).
bool settlesToOwnAddress(String address, Set<String> own) {
  final a = address.trim().toLowerCase();
  if (a.isEmpty || own.isEmpty) return false;
  if (own.contains(a)) return true;
  final key = sparkIdentityPubkeyHex(a);
  if (key == null) return false;
  for (final o in own) {
    if (sparkIdentityPubkeyHex(o) == key) return true;
  }
  return false;
}

/// An Orchestra BTC figure in sats: Flashnet's sats (a whole number of at
/// least one) or a BTC decimal (the status poll's).
int orchestraBtcFieldToSats(String btcField) {
  final raw = double.tryParse(btcField) ?? 0;
  if (!raw.isFinite || raw <= 0) return 0;
  return (raw >= 1 && raw == raw.roundToDouble())
      ? raw.round()
      : (raw * 100000000).round();
}

/// The kinds that are the wallet's own money coming home to its own Spark
/// balance by construction: the flow resolved the recipient to the
/// wallet's address before anything moved.
const Set<SwapActivityKind> _ownWithdrawalKinds = {
  SwapActivityKind.dollarWithdrawal,
  SwapActivityKind.investingWithdrawal,
  SwapActivityKind.predictionsWithdrawal,
};

/// The receives among [receives] that are deliveries of [exchanges] (the
/// surface's conversion rows), each mapped to the row it belongs to.
///
/// [betFlowOrderIds] are orders the bet and claim flows tagged (ownership
/// without an own settle address); [links] the reconciler's links.
Map<String, String> ownBitcoinDeliveryReceives(
  List<SwapOrderTransaction> exchanges,
  Iterable<SparkTransaction> receives, {
  required Set<String> ownAddresses,
  required SwapActivityKind Function(SwapOrder order) classify,
  Set<String> betFlowOrderIds = const {},
  Map<String, OrchestraDeliveryLink> links = const {},
}) {
  final claimed = <String, String>{};
  final inbound = [
    for (final rx in receives)
      if (rx.type == TransactionType.received) rx,
  ];
  if (inbound.isEmpty || exchanges.isEmpty) return claimed;
  final used = <String>{};

  // 1. The reconciler's links: the row it settled, wherever its id went.
  if (links.isNotEmpty) {
    for (final rx in inbound) {
      final link = links[rx.id];
      if (link == null) continue;
      final order = link.orderId;
      final resolved = order == null ? null : OrchestraOrderIds.resolve(order);
      for (final ex in exchanges) {
        if (used.contains(ex.id)) continue;
        if (ex.details.coinTo.toUpperCase() != 'BTC') continue;
        final op = ex.details.operationId;
        if (ex.id == order ||
            ex.id == resolved ||
            (link.operationId != null && op == link.operationId)) {
          claimed[rx.id] = ex.id;
          used.add(ex.id);
          break;
        }
      }
    }
  }

  // 2. Amount and time, one to one.
  final pairs = <({String rx, String ex, int diff, int delta})>[];
  for (final ex in exchanges) {
    if (used.contains(ex.id)) continue;
    final d = ex.details;
    if (d.coinTo.toUpperCase() != 'BTC') continue;
    // Only a delivery to the Spark balance is a Spark receive: bitcoin
    // settled on-chain (a Ledger, another wallet) never is.
    final to = d.networkTo.toUpperCase();
    if (to != 'SPARK' && to != 'LIGHTNING') continue;
    if (OwnSparkArrivals.failedStatuses.contains(d.status)) continue;
    final fieldSats = orchestraBtcFieldToSats(d.withdrawalAmount);
    if (fieldSats <= 0) continue;
    final kind = classify(d);
    final toSelf = settlesToOwnAddress(d.withdrawalAddress, ownAddresses);
    // A Spark address the wallet knows is not its own: someone else's
    // money, whatever the flow says.
    final foreign = !toSelf &&
        ownAddresses.isNotEmpty &&
        sparkIdentityPubkeyHex(d.withdrawalAddress.trim()) != null;
    final ownWithdrawal =
        d.isOrchestra && _ownWithdrawalKinds.contains(kind) && !foreign;
    final tagged = betFlowOrderIds.contains(ex.id);
    // Amount and time alone can coincide: the row must be the wallet's.
    if (!ownWithdrawal && !toSelf && !tagged) continue;
    // A withdrawal's stored figure is the quote's estimate until the poll
    // writes the delivered one: a wider match than an exact settled
    // amount is held to.
    final tolSats = math.max(
        1, (fieldSats * (ownWithdrawal ? 0.10 : 0.02)).round());
    final window = ownWithdrawal || toSelf
        ? kOwnDeliveryArrivalWindow
        : const Duration(minutes: 30);
    for (final rx in inbound) {
      if (claimed.containsKey(rx.id)) continue;
      final diff = (rx.amountSats.abs() - fieldSats).abs();
      if (diff > tolSats) continue;
      final delta = rx.timestamp.difference(ex.timestamp);
      if (delta < -kOwnDeliveryEarlyMargin || delta > window) continue;
      pairs.add((
        rx: rx.id,
        ex: ex.id,
        diff: diff,
        delta: delta.inMilliseconds.abs(),
      ));
    }
  }
  pairs.sort((a, b) {
    final byDiff = a.diff.compareTo(b.diff);
    return byDiff != 0 ? byDiff : a.delta.compareTo(b.delta);
  });
  for (final p in pairs) {
    if (claimed.containsKey(p.rx) || used.contains(p.ex)) continue;
    claimed[p.rx] = p.ex;
    used.add(p.ex);
  }
  return claimed;
}
