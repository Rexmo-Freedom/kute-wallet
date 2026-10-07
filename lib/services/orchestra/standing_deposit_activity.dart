import 'package:kute/helpers/orchestra_router.dart'
    show orchestraAmountToDecimalString;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';

/// Activity for money that reached a reusable (standing) deposit address.
///
/// A deposit that became an Orchestra order (`ord_…`) already has its own
/// Activity row, written by background sync's standing sweep, and that
/// row's details carry the refund. This file covers the other case: a
/// deposit the provider holds without ever creating an order (below the
/// minimum, the wrong asset, and the like). It gets a row in the Activity
/// list of the asset it was meant to land as, and only then: generating
/// an address never writes a row, and neither does a deposit that is
/// still on its way to becoming an order.

/// The row status for a standing deposit that never became an order, or
/// null when it is not stuck (still converting, or converted).
///
/// `held` waits to be returned and its details offer the refund;
/// `refund_requested` has been asked back; `refunded` is back with the
/// payer; `failed` needs support.
String? stuckStandingDepositStatus(Map<String, dynamic> deposit) {
  if (deposit['refundTxId'] != null) return 'refunded';
  return switch (deposit['status']) {
    'held' => 'held',
    'refund_requested' => 'refund_requested',
    'failed' => 'failed',
    _ => null,
  };
}

/// Whether [deposit] became an order whose own row represents it.
bool standingDepositHasOrder(Map<String, dynamic> deposit) {
  final order = deposit['orderId'];
  return order is String && order.startsWith('ord_');
}

/// The Activity id of [deposit]'s stuck row, or null without a deposit id.
String? stuckStandingDepositRowId(Map<String, dynamic> deposit) {
  final id = deposit['id'];
  return id is String && id.isNotEmpty
      ? '$kStuckStandingDepositRowPrefix$id'
      : null;
}

/// The row Activity should show for [deposit] on [record], or null when
/// the deposit is not stuck. [existing] is the row already stored for
/// it, whose first-seen time is kept.
///
/// The row is shaped like the order rows the sweep writes for the same
/// address (a receive from [deposit]'s chain into [record]'s asset on
/// Spark), so it lands in the same Activity list.
SwapOrder? stuckStandingDepositRow({
  required Map<String, dynamic> deposit,
  required StandingDepositRecord record,
  required String walletId,
  required String recipient,
  SwapOrder? existing,
  DateTime? now,
}) {
  if (standingDepositHasOrder(deposit)) return null;
  var status = stuckStandingDepositStatus(deposit);
  // A refund this wallet asked for reads as asked before the provider's
  // listing catches up.
  final journal = record.refunds[deposit['id']];
  if (status == 'held' &&
      journal != null &&
      (journal is! Map || journal['state'] != 'refused')) {
    status = 'refund_requested';
  }
  final id = stuckStandingDepositRowId(deposit);
  final chain = deposit['chain'];
  final asset = deposit['asset'];
  if (status == null || id == null || chain is! String || asset is! String) {
    return null;
  }
  DateTime? seen(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
  final timestamp = existing?.timestamp ??
      (seen(deposit['createdAt']) ??
              seen(deposit['detectedAt']) ??
              seen(deposit['updatedAt']) ??
              now ??
              DateTime.now())
          .millisecondsSinceEpoch;
  return SwapOrder(
    id: id,
    activityDirection: 'receive',
    coinFrom: asset,
    networkFrom: chain,
    coinTo: record.asset,
    networkTo: 'SPARK',
    depositAddress: record.addressFor(chain) ?? '',
    depositAmount:
        orchestraAmountToDecimalString('${deposit['amount']}', asset, chain: chain),
    withdrawalAmount: '0',
    status: status,
    timestamp: timestamp,
    withdrawalAddress: recipient,
    depositMin: '0',
    depositMax: '0',
    rate: '0',
    refundAddress: '',
    provider: 'Orchestra',
    walletId: walletId,
    purchaseSource: 'crypto_receive',
  );
}
