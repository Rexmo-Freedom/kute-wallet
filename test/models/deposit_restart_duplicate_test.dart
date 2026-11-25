// After a restart Activity is read back from the cache before the SDK
// answers. A deposit already credited must not come back as its old
// "Receiving" or "Adding to your balance" row beside the received one.
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/mempool_address_service.dart';

Transaction _feed({
  required List<SparkTransaction> spark,
  List<SparkPendingDeposit> pending = const [],
  List<SparkUnclaimedDeposit> unclaimed = const [],
}) =>
    Transaction.empty().copyWith(
      sparkTransactions: spark,
      sparkPendingDeposits: pending,
      sparkUnclaimedDeposits: unclaimed,
    );

SparkTransaction _shell(String txid, {bool pending = false}) =>
    SparkTransaction.fromCache(
      id: 'pay_$txid',
      timestamp: DateTime.utc(2026, 11, 4, 10),
      isConfirmed: !pending,
      amountSats: 50000,
      sparkType: SparkTransactionType.bitcoin,
      direction: TransactionType.received,
      pending: pending,
      onChainTxId: txid,
    );

SparkPendingDeposit _receiving(String txid, int confirmations) =>
    SparkPendingDeposit(
      id: 'spark_pending_$txid',
      timestamp: DateTime.utc(2026, 11, 4, 9),
      confirmations: confirmations,
      mempoolTx: MempoolTransaction(
          txid: txid, confirmed: true, fee: 0, balanceChange: 50000),
    );

SparkUnclaimedDeposit _adding(String txid) => SparkUnclaimedDeposit.fromCache(
      id: '$txid:0',
      timestamp: DateTime.utc(2026, 11, 4, 9),
      txid: txid,
      vout: 0,
      amountSats: 50000,
      isMature: true,
    );

List<String> _ids(Transaction t) => [for (final x in t.allTransactions) x.id];

void main() {
  test('a cached credited deposit hides its cached Receiving row', () {
    final feed = _feed(spark: [_shell('abc')], pending: [_receiving('abc', 1)]);
    expect(_ids(feed), ['pay_abc']);
  });

  test('a mature cached Receiving row hides behind a pending claim shell',
      () {
    // Claim submitted, not settled: one row, the claim's own.
    final feed = _feed(
        spark: [_shell('abc', pending: true)], pending: [_receiving('abc', 4)]);
    expect(_ids(feed), ['pay_abc']);
  });

  test('a cached unclaimed row of a credited deposit is not shown twice', () {
    final feed = _feed(spark: [_shell('abc')], unclaimed: [_adding('abc')]);
    expect(_ids(feed), ['pay_abc']);
  });

  test('another deposit still on its way keeps its row', () {
    final feed = _feed(
        spark: [_shell('abc')],
        pending: [_receiving('xyz', 1)],
        unclaimed: [_adding('def')]);
    expect(_ids(feed).toSet(), {'pay_abc', 'spark_pending_xyz', 'def:0'});
  });
}
