import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/asset_icon_provider.dart' show kUsdMarkAsset;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, kOrchestraUsdChain, isOrchestraUsdRoute;

/// The asset delivered by a Lightning-funded Cash App order.
/// Keep this independent of the payment source: every destination is
/// funded with Lightning BTC, but only Bitcoin orders credit the BTC wallet.
///
/// Adding a delivery leg is adding a row here: the chain, the asset and
/// the label are all the order needs, so the next rail is a leg rather
/// than another special case.
enum CashAppDestination {
  spending('spark', 'BTC', 'Bitcoin'),
  bitcoinWallet('bitcoin', 'BTC', 'Bitcoin'),

  /// The spending account's dollar balance. Verified live against the
  /// Orchestra catalogue: lightning:BTC reaches spark:USDB (its `to`
  /// rule is an except list that does not name the dollar token), so
  /// the onramp lands in dollars rather than buying bitcoin first.
  /// The label is the only user-visible string here, and it says
  /// dollars, never the token's own name.
  dollars(kOrchestraUsdChain, kOrchestraUsdAssetCode, 'Dollars'),
  predictions('polygon', 'USDC.e', 'Predictions'),
  investing('hypercore', 'USDC', 'Investing');

  const CashAppDestination(this.chain, this.asset, this.label);

  final String chain;
  final String asset;
  final String label;

  bool get isVenue => this == predictions || this == investing;

  /// The leg settles in a dollar-denominated asset, so what arrives is
  /// counted in dollars and never subtracted from the Lightning sats
  /// that paid for it. True for the venues and for the dollar balance.
  bool get deliversDollars => asset.toUpperCase() != 'BTC';

  String get icon => switch (this) {
        predictions => 'lib/assets/polymarket-logo.svg',
        investing => 'lib/assets/hyperliquid-logo.svg',
        dollars => kUsdMarkAsset,
        _ => 'lib/assets/Bitcoin_lightning_logo.png',
      };
}

/// Total quoted conversion cost, measured in a common unit on both legs.
/// A dollar leg's base units must never be subtracted from Lightning sats,
/// so anything that settles in dollars is costed in dollars.
({double? usd, double? sats}) cashAppQuotedCost({
  required CashAppDestination destination,
  required String amountIn,
  required String estimatedOut,
  required double fiatUsd,
}) {
  final rawOutput = double.tryParse(estimatedOut);
  if (rawOutput == null || !rawOutput.isFinite || rawOutput < 0) {
    return (usd: null, sats: null);
  }
  if (destination.deliversDollars) {
    final received = orchestraAmountToDouble(estimatedOut, destination.asset,
        chain: destination.chain);
    if (!fiatUsd.isFinite || fiatUsd <= 0 || received > fiatUsd) {
      return (usd: null, sats: null);
    }
    return (usd: fiatUsd - received, sats: null);
  }
  final paid = double.tryParse(amountIn);
  if (paid == null || !paid.isFinite || paid <= 0 || rawOutput > paid) {
    return (usd: null, sats: null);
  }
  return (usd: null, sats: paid - rawOutput);
}

/// Read the actual delivery leg so history and retries keep their destination
/// after a restart or after Orchestra replaces a quote ID with an order ID.
CashAppDestination? cashAppDestination(SwapOrder order) {
  if (!order.isCashAppPurchase) return null;
  final asset = order.coinTo.trim().toUpperCase();
  final network = order.networkTo.trim().toUpperCase();
  if (asset == 'BTC' && network == 'SPARK') {
    return CashAppDestination.spending;
  }
  if (asset == 'BTC' && network == 'BITCOIN') {
    return CashAppDestination.bitcoinWallet;
  }
  if (isOrchestraUsdRoute(network, asset)) {
    return CashAppDestination.dollars;
  }
  if ((asset == 'USDC.E' || asset == 'USDC') && network == 'POLYGON') {
    return CashAppDestination.predictions;
  }
  if (asset == 'USDC' && network == 'HYPERCORE') {
    return CashAppDestination.investing;
  }
  return null;
}

/// An automatic wrap may only touch the account that received this completed
/// deposit. It must not wrap another wallet's collateral or race a withdrawal.
bool cashAppNeedsPredictionsWrap(
  SwapOrder order, {
  required String? activeWalletId,
  required String? predictionsAddress,
  required Iterable<SwapOrder> orders,
}) {
  if (!order.isComplete ||
      cashAppDestination(order) != CashAppDestination.predictions ||
      order.coinTo.toUpperCase() != 'USDC.E' ||
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

SwapOrder cashAppDepositOrder({
  required OrchestraOnrampResponse order,
  required CashAppDestination destination,
  required String recipient,
  required double fiatUsd,
  required String? walletId,
  required DateTime createdAt,
}) {
  final id = order.orderId.isNotEmpty ? order.orderId : order.quoteId;
  if (id.trim().isEmpty || recipient.trim().isEmpty) {
    throw StateError('Deposit requires an order ID and recipient');
  }
  return SwapOrder(
    id: id,
    coinFrom: 'BTC',
    networkFrom: 'LIGHTNING',
    coinTo: destination.asset,
    networkTo: destination.chain.toUpperCase(),
    routeVersion:
        destination.isVenue ? 'cashapp-${destination.chain}-v1' : null,
    depositAddress: order.depositAddress,
    depositAmount:
        orchestraAmountToDouble(order.amountIn, 'BTC', chain: 'lightning')
            .toStringAsFixed(8),
    withdrawalAmount: orchestraAmountToDouble(
            order.estimatedOut, destination.asset,
            chain: destination.chain)
        .toStringAsFixed(8),
    status: 'pending',
    timestamp: createdAt.millisecondsSinceEpoch,
    withdrawalAddress: recipient,
    depositMin: '0',
    depositMax: '0',
    rate: '0',
    refundAddress: '',
    provider: 'Orchestra',
    purchaseSource: 'cashapp',
    purchaseFiatUsd: fiatUsd.toStringAsFixed(2),
    expiresAt: DateTime.tryParse(order.expiresAt)?.millisecondsSinceEpoch,
    walletId: walletId,
  );
}
