import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:kute/models/transactions_model.dart';

enum SparkDepositUpdateKind { upsert, claimed, snapshot }

/// SDK new/unclaimed/claimed events are batches, not full deposit snapshots.
/// Only listUnclaimedDeposits may authoritatively replace the whole list.
class SparkDepositUpdate {
  const SparkDepositUpdate(this.kind, this.deposits);

  final SparkDepositUpdateKind kind;
  final List<spark.DepositInfo> deposits;

  bool get hasSettledClaims =>
      kind == SparkDepositUpdateKind.claimed &&
      deposits.any(
          (d) => d.instantClaimStatus is! spark.InstantClaimStatus_Submitted);
}

String sparkOutpointKey(String txid, int vout) => '${txid.toLowerCase()}:$vout';

/// Outpoints already credited as Spark deposit payments. Cache-hydrated
/// payment shells carry no deposit details, so only live rows count.
Set<String> sparkDepositPaymentOutpoints(Iterable<SparkTransaction> payments) {
  final outpoints = <String>{};
  for (final payment in payments) {
    final details = payment.details;
    final deposit = details?.details;
    if (details != null &&
        details.status != spark.PaymentStatus.failed &&
        deposit is spark.PaymentDetails_Deposit) {
      outpoints.add(sparkOutpointKey(deposit.txId, deposit.vout));
    }
  }
  return outpoints;
}

/// [settledOutpoints] (see [sparkDepositPaymentOutpoints]) and lowercase
/// [mempoolTxids] stop late events from resurrecting credited deposits or
/// duplicating deposits a mempool `n/3` row already shows.
List<SparkUnclaimedDeposit> applySparkDepositUpdate(
  List<SparkUnclaimedDeposit> current,
  SparkDepositUpdate update, {
  required DateTime now,
  Set<String> settledOutpoints = const {},
  Set<String> mempoolTxids = const {},
}) {
  final previous = {
    for (final row in current) sparkOutpointKey(row.txid, row.vout): row,
  };
  final next = update.kind == SparkDepositUpdateKind.snapshot
      ? <String, SparkUnclaimedDeposit>{}
      : Map<String, SparkUnclaimedDeposit>.of(previous);
  for (final deposit in update.deposits) {
    final id = sparkOutpointKey(deposit.txid, deposit.vout);
    // Instant claims settle asynchronously even though the SDK uses its
    // ClaimedDeposits event. Keep them discoverable until a later snapshot.
    if (update.kind == SparkDepositUpdateKind.claimed &&
        deposit.instantClaimStatus is! spark.InstantClaimStatus_Submitted) {
      next.remove(id);
    } else if (settledOutpoints.contains(id) ||
        mempoolTxids.contains(deposit.txid.toLowerCase())) {
      next.remove(id);
    } else {
      next[id] = SparkUnclaimedDeposit(
        id: '${deposit.txid}:${deposit.vout}',
        timestamp: previous[id]?.timestamp ?? now,
        depositInfo: deposit,
      );
    }
  }
  return next.values.toList();
}

/// True when [next] holds the same live deposits as [current], in order.
/// Cache-hydrated rows never match, so their live payload is still written.
bool sameSparkDepositRows(
    List<SparkUnclaimedDeposit> current, List<SparkUnclaimedDeposit> next) {
  if (current.length != next.length) return false;
  for (var i = 0; i < current.length; i++) {
    final info = current[i].depositInfo;
    if (info == null ||
        current[i].id != next[i].id ||
        info != next[i].depositInfo) {
      return false;
    }
  }
  return true;
}
