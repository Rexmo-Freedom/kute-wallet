import 'package:kute/helpers/orchestra_router.dart'
    show orchestraAmountToDecimalString;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/orchestra_routes.dart'
    show orchestraExchangeStatus;

/// Activity for money that reached a reusable (standing) deposit address.
///
/// A deposit that became an Orchestra order (`ord_…`) gets that order's
/// Activity row, written by background sync's standing sweep, and that
/// row's details carry the refund. Until it has one, the deposit has a
/// row of its own (`sdep_…`) in the Activity list of the asset it was
/// meant to land as, from the moment the provider lists it: arriving
/// while it is bridged or converted, held (with the refund in its
/// details), returned, or failed. Generating an address never writes a
/// row. On the Investing-withdrawal instruction only a deposit that did
/// not work gets one ([stuckStandingDepositRow]): the CCTP watcher's own
/// row shows the move while it runs.

/// Route version on the Activity rows of an Investing → Dollars move that
/// went out of HyperCore by Circle CCTP: converted by a one-time Orchestra
/// quote since 19 October 2026 (`HypercoreCctpWithdrawal`), by the
/// Investing-withdrawal standing instruction before that.
const String kHypercoreCctpRouteVersion = 'hypercore_cctp_to_spark_usd_v1';

/// The same for an Investing → Bitcoin move by CCTP (spark:BTC).
const String kHypercoreCctpBtcRouteVersion = 'hypercore_cctp_to_spark_btc_v1';

/// The same for an Investing → Predictions move by CCTP (polygon:USDC.e).
const String kHypercoreCctpPredictionsRouteVersion =
    'hypercore_cctp_to_polygon_usdce_v1';

/// The route version of a CCTP move into [destination].
String hypercoreCctpRouteVersion(InvestingWithdrawalDestination destination) =>
    switch (destination) {
      InvestingWithdrawalDestination.dollars => kHypercoreCctpRouteVersion,
      InvestingWithdrawalDestination.bitcoin => kHypercoreCctpBtcRouteVersion,
      InvestingWithdrawalDestination.predictions =>
        kHypercoreCctpPredictionsRouteVersion,
    };

/// The route version of rows on [record], an Investing-withdrawal
/// instruction.
String hypercoreCctpRouteVersionFor(StandingDepositRecord record) =>
    hypercoreCctpRouteVersion(InvestingWithdrawalDestination.values
            .where((d) => d.chain == record.chain && d.asset == record.asset)
            .firstOrNull ??
        InvestingWithdrawalDestination.dollars);

/// The row status for a standing deposit that never became an order, or
/// null when it is not stuck (still converting, or converted).
///
/// `held` waits to be returned and its details offer the refund;
/// `refund_requested` has been asked back; `refunded` is back with the
/// payer; `failed` needs support.
String? stuckStandingDepositStatus(Map<String, dynamic> deposit) {
  if (deposit['refundTxId'] != null) return 'refunded';
  // A linked order's status takes precedence in the listing; otherwise
  // the batch states held, refund_requested and refunded do, over the
  // transfer status (https://docs.flashnet.xyz/orchestra/deposit-addresses).
  final status = deposit['status'];
  final batch = deposit['batchState'];
  if (status == 'refunded' || batch == 'refunded') {
    return 'refunded';
  }
  if (!standingDepositHasOrder(deposit) &&
      (batch == 'held' || batch == 'refund_requested')) {
    return batch as String;
  }
  return switch (status) {
    'held' => 'held',
    'refund_requested' => 'refund_requested',
    'failed' => 'failed',
    _ => null,
  };
}

/// Row statuses a Receive deposit's own row may carry beside the stuck
/// ones: the progress words the shared Activity rows know, and the
/// outcomes of an order the row stands in for.
const Set<String> _depositRowStatuses = {
  'exchanging',
  'confirmation',
  'sending',
  'success',
  'refunded',
  'overdue',
};

/// The row status of any deposit on a Receive address
/// ([standingDepositRow]). The provider's statuses are an open set: a
/// deposit with no order that is neither stuck nor known is on its way
/// (detected, bridging, materializing…), so it reads as arriving, never
/// as "waiting for payment", which would expire it on screen. A linked
/// order's own status reads as that order's row will.
String standingDepositRowStatus(Map<String, dynamic> deposit) {
  final linked = standingDepositHasOrder(deposit);
  final stuck = stuckStandingDepositStatus(deposit);
  if (stuck != null && !(linked && stuck == 'failed')) return stuck;
  final mapped = orchestraExchangeStatus('${deposit['status'] ?? ''}');
  if (_depositRowStatuses.contains(mapped)) return mapped;
  if (mapped == 'expired') return linked ? 'expired' : 'failed';
  return 'exchanging';
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
      (seen(deposit['observedAt']) ??
              seen(deposit['createdAt']) ??
              seen(deposit['detectedAt']) ??
              seen(deposit['updatedAt']) ??
              now ??
              DateTime.now())
          .millisecondsSinceEpoch;
  // Money on the Investing-withdrawal instruction left Investing: its row
  // reads as the Investing withdrawal it is, whoever writes it first (the
  // standing sweep or the CCTP watcher), so the two never disagree.
  final investing =
      StandingDepositStore.isInvestingWithdrawalLabel(record.label);
  return SwapOrder(
    id: id,
    activityDirection: investing ? null : 'receive',
    coinFrom: investing ? 'USDC' : asset,
    networkFrom: investing ? 'HYPERCORE' : chain,
    coinTo: record.asset,
    networkTo: record.chain.toUpperCase(),
    depositAddress: record.addressFor(chain) ?? '',
    depositAmount: orchestraAmountToDecimalString('${deposit['amount']}', asset,
        chain: chain),
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
    purchaseSource: investing ? null : 'crypto_receive',
    routeVersion: investing ? hypercoreCctpRouteVersionFor(record) : null,
  );
}

/// The row Activity shows for [deposit] on [record] until the order it
/// became has a row of its own, or null when there is nothing to show.
///
/// On a Receive address every listed deposit has one, from the moment
/// the provider observes it ([standingDepositRowStatus]). On the
/// Investing-withdrawal instruction it is [stuckStandingDepositRow].
/// [existing] is the row already stored for it, whose first-seen time
/// is kept.
SwapOrder? standingDepositRow({
  required Map<String, dynamic> deposit,
  required StandingDepositRecord record,
  required String walletId,
  required String recipient,
  SwapOrder? existing,
  DateTime? now,
}) {
  final stuck = stuckStandingDepositRow(
      deposit: deposit,
      record: record,
      walletId: walletId,
      recipient: recipient,
      existing: existing,
      now: now);
  if (stuck != null ||
      StandingDepositStore.isInvestingWithdrawalLabel(record.label)) {
    return stuck;
  }
  final id = stuckStandingDepositRowId(deposit);
  final chain = deposit['chain'];
  final asset = deposit['asset'];
  if (id == null || chain is! String || asset is! String) return null;
  return _depositRow(
      deposit: deposit,
      record: record,
      walletId: walletId,
      recipient: recipient,
      id: id,
      chain: chain,
      asset: asset,
      status: standingDepositRowStatus(deposit),
      existing: existing,
      now: now);
}

SwapOrder _depositRow({
  required Map<String, dynamic> deposit,
  required StandingDepositRecord record,
  required String walletId,
  required String recipient,
  required String id,
  required String chain,
  required String asset,
  required String status,
  SwapOrder? existing,
  DateTime? now,
}) {
  DateTime? seen(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
  final timestamp = existing?.timestamp ??
      (seen(deposit['observedAt']) ??
              seen(deposit['createdAt']) ??
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
    networkTo: record.chain.toUpperCase(),
    depositAddress: record.addressFor(chain) ?? '',
    depositAmount: orchestraAmountToDecimalString('${deposit['amount']}', asset,
        chain: chain),
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

/// The Activity row of the order [orderId] a deposit on [record]'s
/// [chain]/[asset] address became. A receive into [record]'s asset, or,
/// on the Investing-withdrawal instruction, the Investing → Dollars
/// withdrawal it is. Shared by the standing sweep and the CCTP watcher so
/// whichever writes it first writes the same row.
SwapOrder standingOrderRow({
  required StandingDepositRecord record,
  required String orderId,
  required String chain,
  required String asset,
  required String depositAddress,
  required String amountIn,
  required String amountOut,
  required String status,
  required int timestamp,
  required String recipient,
  required String walletId,
  String? operationId,
}) {
  final investing =
      StandingDepositStore.isInvestingWithdrawalLabel(record.label);
  return SwapOrder(
    id: orderId,
    activityDirection: investing ? null : 'receive',
    coinFrom: investing ? 'USDC' : asset,
    networkFrom: investing ? 'HYPERCORE' : chain,
    coinTo: record.asset,
    networkTo: record.chain.toUpperCase(),
    depositAddress: depositAddress,
    depositAmount:
        orchestraAmountToDecimalString(amountIn, asset, chain: chain),
    withdrawalAmount: orchestraAmountToDecimalString(amountOut, record.asset,
        chain: record.chain),
    status: status,
    timestamp: timestamp,
    withdrawalAddress: recipient,
    depositMin: '0',
    depositMax: '0',
    rate: '0',
    refundAddress: '',
    provider: 'Orchestra',
    walletId: walletId,
    purchaseSource: investing ? null : 'crypto_receive',
    operationId: operationId,
    routeVersion: investing ? hypercoreCctpRouteVersionFor(record) : null,
  );
}
