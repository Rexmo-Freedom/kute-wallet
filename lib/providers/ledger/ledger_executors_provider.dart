import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
// lib/providers/ledger/ledger_executors_provider.dart
//
// Injectable factories for the Ledger execution services (Wallet
// hardening Phase 4a, P4.5 to P4.7). Sheets never construct executors or
// signers directly, so widget tests can swap every device and network
// seam. Nothing here holds a key: the only signing authority an executor
// receives is the Ledger external signer handed over by the approval
// controller after the user reviewed the action.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/hardware/ledger/ledger_device_session.dart';
import 'package:kute/services/hardware/ledger/ledger_evm_signer.dart';
import 'package:kute/services/hardware/ledger/ledger_hyperliquid_executor.dart';
import 'package:kute/services/hardware/ledger/ledger_polymarket_executor.dart';
import 'package:kute/services/hardware/ledger/ledger_submitted_action_store.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';

final ledgerSubmittedActionStoreProvider =
    Provider<LedgerSubmittedActionStore>((ref) => LedgerSubmittedActionStore());

typedef LedgerEvmSignerFactory = LedgerEvmSigner Function(
    LedgerDeviceSession session, String pairedAddress);

final ledgerEvmSignerFactoryProvider = Provider<LedgerEvmSignerFactory>(
  (ref) => (session, pairedAddress) =>
      LedgerEvmSigner(session: session, pairedAddress: pairedAddress),
);

typedef LedgerHlExecutorFactory = LedgerHyperliquidExecutor Function({
  required String walletId,
  required String pairedAddress,
  required EvmExternalSigner signer,
});

final ledgerHlExecutorFactoryProvider = Provider<LedgerHlExecutorFactory>(
  (ref) => ({
    required String walletId,
    required String pairedAddress,
    required EvmExternalSigner signer,
  }) =>
      LedgerHyperliquidExecutor(
        walletId: walletId,
        pairedAddress: pairedAddress,
        signer: signer,
        store: ref.read(ledgerSubmittedActionStoreProvider),
        checkCapability: (intent) async {
          if (intent.kind == LedgerActionKind.hlUpdateLeverage) {
            // The region's leverage cap, as the spending wallet checks it
            // before asking the venue to set the leverage.
            RuntimeCapabilitiesService.instance
                .ensureLeverageAllowed(intent.params['leverage'] as int? ?? 1);
          }
          if (intent.kind == LedgerActionKind.hlTrailingStop ||
              (intent.kind == LedgerActionKind.hlOrder &&
                  intent.params['tif'] != 'Ioc') ||
              (intent.kind == LedgerActionKind.hlUpdateLeverage &&
                  (intent.params['leverage'] as int? ?? 1) > 1)) {
            await RuntimeCapabilitiesService.instance
                .ensureAllowed('trading.advanced');
          }
          if (intent.kind == LedgerActionKind.hlApproveBuilderFee) {
            // Approving the published fee also enables a separately allowed
            // exit; a new-trade block must not strand an existing position.
            await RuntimeCapabilitiesService.instance
                .ensureAnyAllowed(['hyperliquid.trade', 'hyperliquid.close']);
          } else {
            await RuntimeCapabilitiesService.instance.ensureAllowed(intent
                        .kind ==
                    LedgerActionKind.hlCancel
                ? 'hyperliquid.cancel'
                : LedgerHyperliquidExecutor.isReducingOrder(intent)
                    ? 'hyperliquid.close'
                    : LedgerHyperliquidExecutor.isExistingFundsIntent(intent)
                        ? 'hyperliquid.withdraw'
                        : 'hyperliquid.trade');
          }
          if (intent.kind == LedgerActionKind.hlOrder ||
              intent.kind == LedgerActionKind.hlApproveBuilderFee) {
            // The builder comes only from the backend. What the intent
            // names (an approval's builder, an order's `b`/`f`, or no
            // builder at all) must be exactly what the backend publishes
            // now, so an approval and the orders it covers never name
            // different addresses; a rotation in between re-reviews.
            final builder = await HyperliquidFundingService.getBuilder();
            final approval =
                intent.kind == LedgerActionKind.hlApproveBuilderFee;
            final address =
                intent.params[approval ? 'builder' : 'builderAddress'];
            final fee =
                intent.params[approval ? 'maxFeeRate' : 'builderFeeTenthsBp'];
            if (address?.toString().toLowerCase() !=
                    builder?.builderAddress.toLowerCase() ||
                fee !=
                    (approval
                        ? builder?.maxFeeRate
                        : builder?.defaultFeeTenthsBp)) {
              throw StateError(
                  'Trading fee settings changed. Review the action again.');
            }
          }
        },
        // The fresh callback above evaluates each intent independently. Do not
        // reuse a trade-only display gate for cancellation or withdrawal.
        geoAllowed: () => true,
      ),
);

typedef LedgerPmExecutorFactory = LedgerPolymarketExecutor Function({
  required String walletId,
  required String pairedAddress,
  required EvmExternalSigner signer,
  required PolymarketLedgerAccount account,
  bool Function(String address)? belongsToLedger,
});

final ledgerPmExecutorFactoryProvider = Provider<LedgerPmExecutorFactory>(
  (ref) => ({
    required String walletId,
    required String pairedAddress,
    required EvmExternalSigner signer,
    required PolymarketLedgerAccount account,
    bool Function(String address)? belongsToLedger,
  }) =>
      LedgerPolymarketExecutor(
        walletId: walletId,
        pairedAddress: pairedAddress,
        signer: signer,
        account: account,
        store: ref.read(ledgerSubmittedActionStoreProvider),
        clob: HttpLedgerPolymarketClob(),
        relayer: OnboardingLedgerPolymarketRelayer(),
        belongsToLedger: belongsToLedger,
        checkCapability: RuntimeCapabilitiesService.instance.ensureAllowed,
      ),
);

/// An external signer that refuses every request. Reconciliation builds
/// executors with it so a read path can never reach a device prompt.
EvmExternalSigner ledgerReadOnlySigner(String pairedAddress) =>
    EvmExternalSigner(
      address: pairedAddress,
      sign: (_) => throw StateError('Reconciliation never signs'),
    );
