// lib/services/dollars_yield.dart
//
// Recognises the daily reward people who hold Dollars are paid (founder,
// 25 November 2026: "label it as usdb yield deposit"; the row reads
// "Dollars yield"). The reward lands as bitcoin, a plain Spark transfer
// into the spending wallet, so in the SDK's list it is one more received
// payment. The rewards service's payout ledger (`RewardPayout`) is the
// only thing that says which one it was.
//
// How a payment is recognised, strongest first:
//   1. The ledger row's `txId` is the payment's own id (the Spark transfer
//      id the SDK lists it under), and the amounts agree.
//   2. Only for a PAID row whose `txId` matched nothing: the payment is a
//      completed, received, plain Spark transfer (no invoice, no HTLC) of
//      exactly the row's sats, settled on the row's paid day (UTC; the
//      accrual day or the next one when the row has no paid time). A row
//      takes a payment only when it is that row's ONLY candidate and the
//      payment is no other row's candidate: two payments of the same amount
//      that day, or one payment two rows could claim, label nothing.
// Pending rows never label. The ledger is the spending wallet's own (it is
// keyed by that wallet's Spark identity) and is matched against that
// wallet's payments only. When in doubt the row stays "Received".
//
// Labelling only: no amount, balance or gate reads from here.

import 'dart:convert';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:hive_ce/hive.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/models/usd_rewards_model.dart';

/// The payment ids of [payments] that are Dollars yield payouts in
/// [payouts], the ledger of the wallet those payments belong to.
Set<String> matchDollarsYieldPayments(
  List<RewardPayout> payouts,
  Iterable<SparkTransaction> payments,
) {
  final paid =
      payouts.where((p) => p.isPaid && p.payoutSats > 0).toList(growable: false);
  if (paid.isEmpty) return const <String>{};
  final received = payments
      .where((t) =>
          t.type == TransactionType.received &&
          !t.isPending &&
          t.amountSats > 0)
      .toList(growable: false);
  if (received.isEmpty) return const <String>{};

  final matched = <String>{};
  final open = <RewardPayout>[];

  // 1. The ledger names the transfer.
  final byId = <String, SparkTransaction>{};
  for (final t in received) {
    byId[_normalizeId(t.id)] = t;
  }
  for (final p in paid) {
    final key = p.txId == null ? '' : _normalizeId(p.txId!);
    final hit = key.isEmpty ? null : byId[key];
    if (hit != null) {
      if (hit.amountSats == p.payoutSats) matched.add(hit.id);
      continue; // Named a payment: never fall back for this row.
    }
    open.add(p);
  }

  // 2. Exact sats on the paid day, unambiguous both ways.
  final rowCandidates = <RewardPayout, List<SparkTransaction>>{};
  final claims = <String, int>{};
  for (final p in open) {
    final days = _settlementDays(p);
    if (days.isEmpty) continue;
    final list = received
        .where((t) =>
            !matched.contains(t.id) &&
            _isPlainSparkTransfer(t) &&
            t.amountSats == p.payoutSats &&
            days.contains(_utcDay(t.timestamp)))
        .toList(growable: false);
    rowCandidates[p] = list;
    for (final t in list) {
      claims[t.id] = (claims[t.id] ?? 0) + 1;
    }
  }
  for (final list in rowCandidates.values) {
    if (list.length != 1) continue;
    final t = list.single;
    if (claims[t.id] == 1) matched.add(t.id);
  }
  return matched;
}

/// A transfer id as both sides may spell it: the SDK can suffix a payment
/// id with `:n`, and a UUID may come with or without dashes or in either
/// case.
String _normalizeId(String id) {
  final base = id.contains(':') ? id.split(':').first : id;
  return base.trim().toLowerCase().replaceAll('-', '');
}

/// A received payment on the Spark rail that pays no invoice and no HTLC:
/// the shape of a payout. A cached shell (no SDK payload) is judged by its
/// rail alone.
bool _isPlainSparkTransfer(SparkTransaction t) {
  if (t.sparkType != SparkTransactionType.spark) return false;
  final live = t.details;
  if (live == null) return true;
  if (live.status != breez.PaymentStatus.completed) return false;
  final d = live.details;
  if (d == null) return true;
  if (d is! breez.PaymentDetails_Spark) return false;
  return d.invoiceDetails == null && d.htlcDetails == null;
}

String _utcDay(DateTime at) {
  final u = at.toUtc();
  return '${u.year.toString().padLeft(4, '0')}-'
      '${u.month.toString().padLeft(2, '0')}-'
      '${u.day.toString().padLeft(2, '0')}';
}

/// The UTC days a paid row's transfer may carry: the day of its paid time,
/// or, without one, the accrual day and the next (payouts land at 01:00
/// UTC the day after they accrue).
Set<String> _settlementDays(RewardPayout p) {
  final paidAt = p.paidAt == null ? null : DateTime.tryParse(p.paidAt!);
  if (paidAt != null) return {_utcDay(paidAt)};
  final day = p.dayDate;
  if (day == null) return const <String>{};
  final start = DateTime.utc(day.year, day.month, day.day);
  return {_utcDay(start), _utcDay(start.add(const Duration(days: 1)))};
}

/// The paid ledger rows kept on disk per wallet, so the activity labels its
/// yield at launch, before (or without) the rewards service answering.
/// Only what the matcher reads is kept.
class DollarsYieldLedgerStore {
  static const String boxName = 'dollars_yield_ledger';

  static Future<Box<String>?> _box() async {
    try {
      return Hive.isBoxOpen(boxName)
          ? Hive.box<String>(boxName)
          : await Hive.openBox<String>(boxName);
    } catch (_) {
      return null;
    }
  }

  /// Every wallet's rows, read synchronously from the box opened at boot
  /// (hive_boot.dart); empty when it is not open.
  static Map<String, List<RewardPayout>> readAll() {
    final Box<String> box;
    try {
      if (!Hive.isBoxOpen(boxName)) return const {};
      box = Hive.box<String>(boxName);
    } catch (_) {
      return const {};
    }
    final out = <String, List<RewardPayout>>{};
    for (final key in box.keys) {
      try {
        final raw = box.get(key);
        if (raw == null) continue;
        out['$key'] = decode(raw);
      } catch (_) {
        // A damaged entry labels nothing.
      }
    }
    return out;
  }

  static Future<void> write(String walletId, List<RewardPayout> rows) async {
    final box = await _box();
    if (box == null) return;
    try {
      await box.put(walletId, encode(rows));
    } catch (_) {}
  }

  static String encode(List<RewardPayout> rows) => jsonEncode([
        for (final p in rows)
          {
            'day': p.day,
            'payoutSats': p.payoutSats,
            'status': p.status,
            if (p.txId != null) 'txId': p.txId,
            if (p.paidAt != null) 'paidAt': p.paidAt,
          }
      ]);

  static List<RewardPayout> decode(String raw) {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map) RewardPayout.fromJson(e.cast<String, dynamic>())
    ];
  }
}
