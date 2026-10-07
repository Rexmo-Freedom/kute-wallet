import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/l10n/l10n.dart' show appL10n;
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/services/funding/ledger_hypercore_funding_service.dart';
import 'package:kute/services/funding/owned_address_resolver.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/hardware/ledger/ledger_hyperliquid_executor.dart';
import 'package:kute/services/hyperliquid/hypercore_cash.dart';
import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hypercore_transfer_proof.dart';
import 'package:kute/services/security/address_guard.dart';

/// Native funding with no signing authority of its own. Every action must pass
/// through the caller's reviewed Ledger approval flow.
class LedgerHypercoreSourceSendNative implements HypercoreReverseSourceSend {
  LedgerHypercoreSourceSendNative(
    this._read, {
    Future<HlAccountSnapshot> Function(String address)? snapshot,
    Future<void> Function()? verifyToken,
    Future<BigInt> Function(String destination)? activationFee,
    Future<String?> Function({
      required String source,
      required String destination,
      required BigInt amountBaseUnits,
      required int nonce,
    })? transferHash,
  })  : _snapshot = snapshot ?? HyperliquidModel().getAccountSnapshot,
        _verifyToken = verifyToken ?? verifyHypercoreUsdcMetadata,
        // Same perpetuals usdSend as the hot account: no sender-side
        // activation charge (see hypercoreUsdSendSenderFee).
        _activationFee = activationFee ?? hypercoreUsdSendSenderFee,
        _transferHash = transferHash ?? readHypercorePerpTransferHash;

  final ProviderReader _read;
  final Future<BigInt> Function(String destination) _activationFee;
  final Future<void> Function() _verifyToken;
  final Future<HlAccountSnapshot> Function(String address) _snapshot;
  final Future<String?> Function({
    required String source,
    required String destination,
    required BigInt amountBaseUnits,
    required int nonce,
  }) _transferHash;

  @override
  bool get isReady => true;

  @override
  Future<BigInt> activationFeeForDestination(String depositAddress) =>
      _activationFee(depositAddress);

  /// At most two actions: an internal move if needed, then the withdrawal.
  @override
  int get deviceConfirmations => 2;

  @override
  Future<String> sendToDeposit({
    required String walletId,
    required String evmAddress,
    required String depositAddress,
    required BigInt amountBaseUnits,
    required BigInt reviewedActivationFeeBaseUnits,
    required String quoteId,
    required LedgerHypercoreApproval approve,
    required Future<void> Function() onBeforeInternalSend,
    required Future<void> Function(int nonce) onBeforeSend,
  }) async {
    var internalPostPending = false;
    var internalPostStarted = false;
    var externalPostStarted = false;
    try {
      final asset =
          _read(orchestraSupportedRoutesProvider).find('hypercore', 'USDC');
      if (asset == null ||
          asset.decimals != 8 ||
          asset.contractAddress?.toLowerCase() != orchestraHypercoreUsdcId) {
        throw StateError('Native USDC route identity could not be verified.');
      }
      if (!isEvmAddress(evmAddress) ||
          !isEvmAddress(depositAddress) ||
          sameEvmAddress(evmAddress, depositAddress)) {
        throw ArgumentError('Invalid native withdrawal destination');
      }
      final wire = hypercorePerpUsdcWire(amountBaseUnits);
      await _verifyToken();
      Future<BigInt> requiredInternalMove() async {
        final fee = await activationFeeForDestination(depositAddress);
        final reserve = hypercoreTransferReserve(
          amountBaseUnits: amountBaseUnits,
          currentFeeBaseUnits: fee,
          reviewedFeeBaseUnits: reviewedActivationFeeBaseUnits,
        );
        final snapshot = await _snapshot(evmAddress);
        return hypercorePerpShortfall(
          requiredBaseUnits: reserve,
          activationFeeBaseUnits: fee,
          spotAvailable: hypercoreAvailableUsdc(0, snapshot.spotBalances),
          perpAvailable: snapshot.withdrawable,
        );
      }

      final internalMove = await requiredInternalMove();
      if (internalMove > BigInt.zero) {
        final transfer = (internalMove.toDouble() / 1e8).toStringAsFixed(6);
        try {
          await approve(
            LedgerHyperliquidIntents.usdClassTransfer(
              walletId: walletId,
              account: evmAddress,
              amount: transfer,
              toPerp: true,
              withdrawalQuoteId: quoteId,
              summary: {
                appL10n().ledgerSummaryAmount: '$transfer USDC',
                appL10n().ledgerSummaryAction:
                    appL10n().ledgerActionMakeFundsAvailable
              },
            ),
            onBeforeSend: (_) async {
              await requiredInternalMove();
              await onBeforeInternalSend();
              internalPostStarted = true;
              internalPostPending = true;
            },
          );
          internalPostPending = false;
        } on HyperliquidRejectedException {
          internalPostPending = false;
          rethrow;
        }
      }
      // Do not offer the external signature until the actual perpetuals balance
      // covers the quote and its current, already-reviewed activation fee.
      if (await requiredInternalMove() > BigInt.zero) {
        throw StateError('Insufficient available perpetuals balance.');
      }
      final nonce = await approve(
          LedgerHyperliquidIntents.usdSend(
            walletId: walletId,
            account: evmAddress,
            destination: depositAddress,
            amountBaseUnits: amountBaseUnits,
            quoteId: quoteId,
            reviewedActivationFeeBaseUnits: reviewedActivationFeeBaseUnits,
            summary: {
              appL10n().ledgerSummaryAmount: '$wire USDC',
              if (reviewedActivationFeeBaseUnits > BigInt.zero)
                appL10n().ledgerSummaryActivationFeeMax:
                    '${(reviewedActivationFeeBaseUnits.toDouble() / 1e8).toStringAsFixed(8)} USDC',
              appL10n().ledgerSummaryTo: depositAddress,
              appL10n().ledgerSummaryAction:
                  appL10n().ledgerActionWithdrawToBitcoin
            },
          ), onBeforeSend: (nonce) async {
        if (await requiredInternalMove() > BigInt.zero) {
          throw StateError('Insufficient available perpetuals balance.');
        }
        await onBeforeSend(nonce);
        externalPostStarted = true;
      });

      // No resubmission: the nonce was persisted before the one native POST.
      // Asked every second within the same six seconds, as the hot sender
      // does: the ledger usually has the hash within one.
      for (var attempt = 0; attempt < 7; attempt++) {
        if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 1));
        try {
          final hash = await _transferHash(
              source: evmAddress,
              destination: depositAddress,
              amountBaseUnits: amountBaseUnits,
              nonce: nonce);
          if (hash != null) return hash;
        } catch (_) {
          // The settlement reconciler continues this exact public proof lookup.
        }
      }
      throw StateError('Native transfer submitted; waiting for confirmation.');
    } catch (error) {
      if (internalPostStarted && !internalPostPending && !externalPostStarted) {
        throw SettlementFundingRefused(error);
      }
      rethrow;
    }
  }
}
