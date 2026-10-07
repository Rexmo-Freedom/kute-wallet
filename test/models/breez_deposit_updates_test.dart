import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/deposit_update.dart';
import 'package:kute/models/transactions_model.dart';

void main() {
  final firstSeen = DateTime.utc(2026, 9, 14);
  final later = DateTime.utc(2026, 9, 15);
  spark.DepositInfo deposit(String txid, int vout,
          {bool mature = false,
          spark.InstantClaimStatus? instant,
          spark.DepositClaimError? claimError}) =>
      spark.DepositInfo(
        txid: txid,
        vout: vout,
        amountSats: BigInt.from(10000),
        isMature: mature,
        instantClaimStatus: instant,
        claimError: claimError,
      );
  SparkUnclaimedDeposit row(spark.DepositInfo d) => SparkUnclaimedDeposit(
        id: '${d.txid}:${d.vout}',
        timestamp: firstSeen,
        depositInfo: d,
      );

  test('new and failed-claim deltas preserve other deposits and first seen',
      () {
    final a = deposit('a', 0);
    final b = deposit('b', 1);
    final rows = applySparkDepositUpdate(
        [row(a)], SparkDepositUpdate(SparkDepositUpdateKind.upsert, [b]),
        now: later);
    expect(rows.map((r) => r.id), ['a:0', 'b:1']);
    final updated = applySparkDepositUpdate(
        rows,
        SparkDepositUpdate(
            SparkDepositUpdateKind.upsert, [deposit('a', 0, mature: true)]),
        now: later);
    expect(updated.map((r) => r.id), ['a:0', 'b:1']);
    expect(updated.first.isMature, isTrue);
    expect(updated.first.timestamp, firstSeen);
    expect(updated.last.timestamp, later);
  });

  test('claimed batch removes only its exact outpoint and is idempotent', () {
    final a = deposit('same-tx', 0, mature: true);
    final b = deposit('same-tx', 1);
    final update = SparkDepositUpdate(SparkDepositUpdateKind.claimed, [a]);
    final remaining =
        applySparkDepositUpdate([row(a), row(b)], update, now: later);
    expect(remaining.map((r) => r.id), ['same-tx:1']);
    expect(remaining.single.timestamp, firstSeen);
    expect(update.hasSettledClaims, isTrue);
    expect(applySparkDepositUpdate(remaining, update, now: later).single.id,
        'same-tx:1');
  });

  test('authoritative snapshot reconciles removed rows, preserving timestamps',
      () {
    final remaining = applySparkDepositUpdate(
      [row(deposit('a', 0)), row(deposit('b', 1))],
      SparkDepositUpdate(
          SparkDepositUpdateKind.snapshot, [deposit('b', 1, mature: true)]),
      now: later,
    );
    expect(remaining.single.id, 'b:1');
    expect(remaining.single.timestamp, firstSeen);
    expect(
        applySparkDepositUpdate(remaining,
            const SparkDepositUpdate(SparkDepositUpdateKind.snapshot, []),
            now: later),
        isEmpty);
  });

  test('empty delta does not erase pending rows or imply a successful claim',
      () {
    const update = SparkDepositUpdate(SparkDepositUpdateKind.claimed, []);
    expect(applySparkDepositUpdate([row(deposit('a', 0))], update, now: later),
        hasLength(1));
    expect(update.hasSettledClaims, isFalse);
  });

  test('instant submitted claim remains pending until reconciliation', () {
    final submitted = deposit('a', 0,
        instant: const spark.InstantClaimStatus.submitted(claimId: 'claim'));
    final update =
        SparkDepositUpdate(SparkDepositUpdateKind.claimed, [submitted]);
    final remaining =
        applySparkDepositUpdate([row(deposit('a', 0))], update, now: later);
    expect(remaining.single.depositInfo!.instantClaimStatus,
        submitted.instantClaimStatus);
    expect(remaining.single.timestamp, firstSeen);
    expect(update.hasSettledClaims, isFalse);
  });

  test('cache-hydrated rows retain timestamps when their live payload returns',
      () {
    final cached = SparkUnclaimedDeposit.fromCache(
        id: 'A:0',
        timestamp: firstSeen,
        txid: 'A',
        vout: 0,
        amountSats: 10000,
        isMature: false);
    final result = applySparkDepositUpdate(
        [cached],
        SparkDepositUpdate(
            SparkDepositUpdateKind.upsert, [deposit('a', 0, mature: true)]),
        now: later);
    expect(result, hasLength(1));
    expect(result.single.timestamp, firstSeen);
    expect(result.single.depositInfo, isNotNull);
  });

  SparkTransaction payment(String txid, int vout,
          {spark.PaymentStatus status = spark.PaymentStatus.completed}) =>
      SparkTransaction(
        id: 'claim-$txid-$vout',
        timestamp: later,
        isConfirmed: status == spark.PaymentStatus.completed,
        details: spark.Payment(
          id: 'claim-$txid-$vout',
          paymentType: spark.PaymentType.receive,
          status: status,
          amount: BigInt.from(9000),
          fees: BigInt.zero,
          timestamp: BigInt.one,
          method: spark.PaymentMethod.deposit,
          details: spark.PaymentDetails.deposit(txId: txid, vout: vout),
        ),
      );

  test('credited deposits are not resurrected by late events or snapshots',
      () {
    final settled = sparkDepositPaymentOutpoints([
      payment('ABC', 0),
      payment('def', 1, status: spark.PaymentStatus.failed),
      SparkTransaction.fromCache(
          id: 'shell',
          timestamp: later,
          isConfirmed: true,
          amountSats: 9000,
          sparkType: SparkTransactionType.bitcoin,
          direction: TransactionType.received,
          pending: false),
    ]);
    expect(settled, {'abc:0'});
    final resurrected = applySparkDepositUpdate(
        [row(deposit('abc', 0, mature: true)), row(deposit('b', 1))],
        SparkDepositUpdate(
            SparkDepositUpdateKind.upsert, [deposit('abc', 0, mature: true)]),
        now: later,
        settledOutpoints: settled);
    expect(resurrected.map((r) => r.id), ['b:1']);
    final snapshot = applySparkDepositUpdate(
        const [],
        SparkDepositUpdate(SparkDepositUpdateKind.snapshot,
            [deposit('abc', 0), deposit('def', 1, mature: true)]),
        now: later,
        settledOutpoints: settled);
    expect(snapshot.map((r) => r.id), ['def:1']);
  });

  test('deposits shown by a mempool row stay hidden whatever their maturity',
      () {
    final deposits = [
      deposit('AA', 0),
      deposit('bb', 0, mature: true),
      deposit('cc', 0),
    ];
    for (final kind in [
      SparkDepositUpdateKind.upsert,
      SparkDepositUpdateKind.snapshot
    ]) {
      final rows = applySparkDepositUpdate(
          [row(deposit('AA', 0))], SparkDepositUpdate(kind, deposits),
          now: later, mempoolTxids: {'aa', 'bb'});
      expect(rows.map((r) => r.id), ['cc:0']);
    }
  });

  test('repeated snapshots are recognised as unchanged', () {
    SparkDepositUpdate snapshot(List<spark.DepositInfo> deposits) =>
        SparkDepositUpdate(SparkDepositUpdateKind.snapshot, deposits);
    final rows = applySparkDepositUpdate(
        const [], snapshot([deposit('a', 0, mature: true)]),
        now: firstSeen);
    expect(
        sameSparkDepositRows(
            rows,
            applySparkDepositUpdate(
                rows, snapshot([deposit('a', 0, mature: true)]),
                now: later)),
        isTrue);
    final failed = deposit('a', 0,
        mature: true,
        claimError: const spark.DepositClaimError.generic(message: 'fee'));
    expect(
        sameSparkDepositRows(
            rows, applySparkDepositUpdate(rows, snapshot([failed]), now: later)),
        isFalse);
    expect(
        sameSparkDepositRows(
            rows, applySparkDepositUpdate(rows, snapshot(const []), now: later)),
        isFalse);
    final cached = SparkUnclaimedDeposit.fromCache(
        id: 'a:0',
        timestamp: firstSeen,
        txid: 'a',
        vout: 0,
        amountSats: 10000,
        isMature: true);
    expect(
        sameSparkDepositRows(
            [cached],
            applySparkDepositUpdate(
                [cached], snapshot([deposit('a', 0, mature: true)]),
                now: later)),
        isFalse);
  });
}
