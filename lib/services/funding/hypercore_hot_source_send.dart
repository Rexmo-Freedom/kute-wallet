import 'package:kute/services/hyperliquid/hypercore_dex_cash.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/services/funding/owned_address_resolver.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/hyperliquid/hypercore_cash.dart';
import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart';
import 'package:kute/services/hyperliquid/hypercore_transfer_proof.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/security/address_guard.dart';

/// Orchestra's hypercore:USDC catalog entry uses a zero address placeholder.
/// Flashnet observes perpetuals USDC deposits: fund with usdSend, never spotSend.
/// No EVM transaction or bridge is involved.
class HypercoreHotSourceSendNative implements HypercoreHotSourceSend {
  HypercoreHotSourceSendNative(this._read);
  final ProviderReader _read;

  /// A `usdSend` costs the sender only its amount: HyperCore takes a new
  /// destination's activation out of what that destination receives. So a
  /// 100% withdrawal sends the whole balance and nothing is held back.
  @override
  Future<BigInt> activationFeeForDestination(String depositAddress) =>
      hypercoreUsdSendSenderFee(depositAddress);

  @override
  bool get isReady => true;

  void _verifyCatalogIdentity() {
    final asset =
        _read(orchestraSupportedRoutesProvider).find('hypercore', 'USDC');
    if (asset == null ||
        asset.decimals != 8 ||
        asset.contractAddress?.toLowerCase() != orchestraHypercoreUsdcId) {
      throw StateError('Native USDC route identity could not be verified.');
    }
  }

  @override
  Future<void> verifyAsset() async {
    _verifyCatalogIdentity();
    await verifyHypercoreUsdcMetadata();
  }

  @override
  Future<String> sendToDeposit({
    required String depositAddress,
    required BigInt amountBaseUnits,
    required BigInt reviewedActivationFeeBaseUnits,
    required void Function() ensurePayable,
    required String quoteId,
    required String sourceAddress,
    required String walletId,
    required Future<void> Function(int nonce) onBeforeSend,
  }) async {
    var internalPostPending = false;
    var externalPostStarted = false;
    try {
      _verifyCatalogIdentity();
      if (!isEvmAddress(depositAddress) ||
          sameEvmAddress(sourceAddress, depositAddress)) {
        throw ArgumentError('Invalid native deposit destination');
      }
      final amountWire = hypercorePerpUsdcWire(amountBaseUnits);
      final wallet = pickSpendingWallet(_read(settingsProvider));
      if (wallet == null || wallet.id != walletId) {
        throw StateError('The spending wallet changed.');
      }
      final session = _read(seedSessionProvider);
      final authSession = _read(sessionAuthProvider);
      if (!session.unlocked || authSession == null) {
        throw const SeedLockedException();
      }
      final mnemonic = await resolveBip39MnemonicFor(wallet,
          access: SeedAccess.automatic, session: session);
      if (mnemonic == null ||
          pickSpendingWallet(_read(settingsProvider))?.id != wallet.id) {
        throw StateError('The spending wallet changed.');
      }
      final account =
          await HyperliquidOnboardingService.provisionHyperliquidAccount(
              mnemonic: mnemonic,
              walletId: wallet.id,
              evmDerivationVersion: wallet.evmDerivationVersion);
      if (!sameEvmAddress(account.address, sourceAddress)) {
        throw StateError('The native source account changed.');
      }
      void ensureWallet() {
        if (!_read(seedSessionProvider).unlocked ||
            !identical(_read(sessionAuthProvider), authSession) ||
            pickSpendingWallet(_read(settingsProvider))?.id != wallet.id) {
          throw const SeedLockedException();
        }
      }

      Future<BigInt> requiredReserve() async {
        final currentFee = await activationFeeForDestination(depositAddress);
        ensureWallet();
        return hypercoreTransferReserve(
          amountBaseUnits: amountBaseUnits,
          currentFeeBaseUnits: currentFee,
          reviewedFeeBaseUnits: reviewedActivationFeeBaseUnits,
        );
      }

      final model = HyperliquidModel();
      Future<BigInt> requiredInternalMove() async {
        final reserve = await requiredReserve();
        final snapshot = await model.getAccountSnapshot(account.address);
        ensureWallet();
        return hypercorePerpShortfall(
          requiredBaseUnits: reserve,
          activationFeeBaseUnits: reserve - amountBaseUnits,
          spotAvailable: hypercoreAvailableUsdc(0, snapshot.spotBalances),
          perpAvailable: snapshot.withdrawable,
        );
      }

      // Any sender-side charge is additional to the quote (none for a
      // usdSend today). Check the full reserve before any internal move.
      // Validate aggregate withdrawable cash, then collect only the portion
      // needed in the default perpetuals account. Never include locked margin.
      final reserve = await requiredReserve();
      final portfolio = await model.getPortfolioSnapshot(account.address);
      ensureWallet();
      final spotMove = hypercorePerpShortfall(
          requiredBaseUnits: reserve,
          activationFeeBaseUnits: reserve - amountBaseUnits,
          spotAvailable: hypercoreAvailableUsdc(0, portfolio.spotBalances),
          perpAvailable: portfolio.withdrawable);
      final requiredDefault = reserve - spotMove;
      final exchange = HyperliquidExchangeService(
        credentials: account.credentials,
        walletAddress: account.address,
        allowNonceRetry: false,
        onBeforePost: (post) async {
          ensureWallet();
          if (post.action['type'] == 'usdSend') {
            final remainingMove = await requiredInternalMove();
            if (remainingMove > BigInt.zero) {
              throw HypercoreBalanceShortfall(
                  'Insufficient available perpetuals balance.');
            }
            await onBeforeSend(post.nonce);
            ensureWallet();
          }
        },
      );
      void beforeDispatch() {
        ensureWallet();
        ensurePayable();
      }

      var internalMove = BigInt.zero;
      try {
        await collectOwnDexCash(
            model: model,
            exchange: exchange,
            requiredDefaultUsd: requiredDefault.toDouble() / 1e8,
            beforeSend: () {
              beforeDispatch();
              internalPostPending = true;
            });
        internalPostPending = false;
        internalMove = await requiredInternalMove();
        if (internalMove > BigInt.zero) {
          await exchange.usdClassTransfer(
            amount: internalMove.toDouble() / 1e8,
            toPerp: true,
            beforeSend: () {
              beforeDispatch();
              internalPostPending = true;
            },
          );
          internalPostPending = false;
        }
      } on HyperliquidRejectedException {
        internalPostPending = false;
        rethrow;
      }
      // Check again before the external signature after an internal
      // transfer. With none, the read just above is this same check with
      // nothing in between, so it is not asked twice. The pre-POST hook
      // repeats it after signing either way, before anything is recorded
      // or sent.
      if (internalMove > BigInt.zero &&
          await requiredInternalMove() > BigInt.zero) {
        throw HypercoreBalanceShortfall(
            'Insufficient available perpetuals balance.');
      }
      final nonce = await exchange.usdSend(
          destination: depositAddress,
          amount: amountWire,
          beforeSend: () {
            beforeDispatch();
            externalPostStarted = true;
          });
      // The exchange acknowledges acceptance without returning a tx hash.
      // Find its canonical ledger hash; never sign or send again while waiting.
      // Asked every second rather than every two, within the same six
      // seconds: the ledger usually has it within one, and the sheet was
      // held for the rest of the two-second step.
      for (var attempt = 0; attempt < 7; attempt++) {
        if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 1));
        try {
          final hash = await readHypercorePerpTransferHash(
              source: account.address,
              destination: depositAddress,
              amountBaseUnits: amountBaseUnits,
              nonce: nonce);
          if (hash != null) return hash;
        } catch (_) {
          // The persisted nonce lets the public reconciler continue after this
          // foreground lookup or a process exit, without another signing step.
        }
      }
      throw StateError('Native transfer submitted; waiting for confirmation.');
    } catch (error) {
      // A confirmed internal move stays in the same account. It does not
      // fund this quote. An uncertain internal POST remains blocked so a
      // stale balance cannot cause a second class transfer on retry.
      if (!externalPostStarted && !internalPostPending) {
        throw SettlementFundingRefused(error);
      }
      rethrow;
    }
  }
}
