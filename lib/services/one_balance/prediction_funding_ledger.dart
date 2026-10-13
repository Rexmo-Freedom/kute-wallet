// lib/services/one_balance/prediction_funding_ledger.dart
//
// One record per move of Dollars into Predictions for a bet:
//
//   sent → landed → reserved (its order is being placed) → released
//
// No sweep or pull ever takes cash a record still holds: a move still on
// its way (sent, not landed) is in flight; a landed move whose order is
// being placed is reserved. A placed, failed or abandoned order releases
// its record at once, so the cash is never held by a bet that is over:
// it stays on Predictions as available cash (a retry or the next bet uses
// it first), and goes home to Dollars only after a day without activity
// (`VenueActivity`, `kVenueIdleSweepAfter`). Every step is activity.
//
// Memory only, like the order-funding journey: a restart starts empty,
// and the sweeper's own rules (pending rows, recent settlement records)
// still hold any move that is truly on a rail.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_activity.dart';

/// Where a funding move is.
enum PredictionFundingStage { sent, landed, reserved, released }

/// One move of Dollars into Predictions for a bet.
class PredictionFundingRecord {
  PredictionFundingRecord._(this.key, this.sentUsd, this.sentAt);

  /// The move's one-way reference (`TrackingService.orderRef` of its
  /// quote), never a raw id.
  final String key;

  /// What left Dollars.
  final double sentUsd;
  final DateTime sentAt;

  PredictionFundingStage stage = PredictionFundingStage.sent;
  DateTime? landedAt;
  DateTime? releasedAt;

  /// placed | failed | abandoned | timeout.
  String? releaseReason;
}

class PredictionFundingLedger {
  PredictionFundingLedger._();

  static PredictionFundingLedger instance = PredictionFundingLedger._();

  /// Test seam: the clock records are stamped with.
  static DateTime Function() clock = DateTime.now;

  @visibleForTesting
  static void reset() => instance = PredictionFundingLedger._();

  /// A sent move not seen landing within this is no longer held as in
  /// flight here (the queued bet's own funds timeout is 12 minutes; the
  /// sweeper's pending-row rule covers a move still on a rail).
  static const Duration inFlightMax = Duration(minutes: 15);

  final Map<String, PredictionFundingRecord> _records = {};

  PredictionFundingRecord? record(String key) => _records[key];

  /// Dollars left for Predictions under [key].
  void sent(String key, {required double usd}) {
    _prune();
    _records[key] = PredictionFundingRecord._(key, usd, clock());
    VenueActivity.note(OneBalanceVenue.predictions);
  }

  /// The move under [key] is credited and spendable on Predictions.
  void landed(String? key) {
    final r = key == null ? null : _records[key];
    if (r == null || r.stage != PredictionFundingStage.sent) return;
    r.stage = PredictionFundingStage.landed;
    r.landedAt = clock();
  }

  /// The order this move paid for is being placed.
  void reserve(String? key) {
    final r = key == null ? null : _records[key];
    if (r == null || r.stage == PredictionFundingStage.released) return;
    r.landedAt ??= clock();
    r.stage = PredictionFundingStage.reserved;
  }

  /// The move's bet is over ([reason]: placed | failed | abandoned |
  /// timeout). Its cash is the venue's available cash from now.
  /// Idempotent.
  void release(String? key, {required String reason}) {
    final r = key == null ? null : _records[key];
    if (r == null || r.stage == PredictionFundingStage.released) return;
    r.stage = PredictionFundingStage.released;
    r.releasedAt = clock();
    r.releaseReason = reason;
    VenueActivity.note(OneBalanceVenue.predictions);
  }

  /// A record whose order is being placed right now.
  bool get hasReserved =>
      _records.values.any((r) => r.stage == PredictionFundingStage.reserved);

  /// A move that left Dollars and has not been seen landing yet.
  bool get hasInFlight {
    final now = clock();
    return _records.values.any((r) =>
        r.stage == PredictionFundingStage.sent &&
        now.difference(r.sentAt) < inFlightMax);
  }

  /// Keeps memory bounded: released records older than an hour go.
  void _prune() {
    final now = clock();
    _records.removeWhere((_, r) =>
        r.stage == PredictionFundingStage.released &&
        r.releasedAt != null &&
        now.difference(r.releasedAt!) > const Duration(hours: 1));
  }
}
