import 'package:kute/models/swap_order_model.dart';

/// An Orchestra order delivering dollars to Polygon: a deposit into
/// Predictions, whatever paid for it (Bitcoin, Dollars, or a Lightning
/// funded Cash App purchase). It arrives as USDC.e, which an order cannot
/// use until it is converted to pUSD.
bool isPredictionsDepositOrder(SwapOrder order) {
  final asset = order.coinTo.trim().toUpperCase();
  return order.isOrchestra &&
      order.networkTo.trim().toUpperCase() == 'POLYGON' &&
      (asset == 'USDC' || asset == 'USDC.E');
}

/// Whether the background sync converts what [order] delivered as soon as
/// it completes. Only a completed deposit into the active account's own
/// Predictions wallet ([predictionsAddress]) qualifies, and not while a
/// withdrawal out of that wallet is still on its way: a conversion must
/// never touch another wallet's money or race a withdrawal.
bool predictionsDepositNeedsWrap(
  SwapOrder order, {
  required String? activeWalletId,
  required String? predictionsAddress,
  required Iterable<SwapOrder> orders,
}) {
  if (!order.isComplete ||
      !isPredictionsDepositOrder(order) ||
      order.walletId == null ||
      order.walletId != activeWalletId ||
      predictionsAddress == null ||
      predictionsAddress.isEmpty ||
      order.withdrawalAddress.toLowerCase() !=
          predictionsAddress.toLowerCase()) {
    return false;
  }
  return !orders.any((candidate) =>
      candidate.walletId == order.walletId &&
      candidate.shouldPollOrchestra &&
      candidate.networkFrom.toUpperCase() == 'POLYGON' &&
      const {'USDC', 'USDC.E', 'PUSD'}
          .contains(candidate.coinFrom.toUpperCase()));
}
