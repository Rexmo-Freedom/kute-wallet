// lib/services/hyperevm/hyperevm_runtime.dart
//
// App wiring for the HyperEVM legs of the Investing moves: opening the
// spending wallet's Hyperliquid key for one operation, the app-wide
// sweeper, the USDC parked on HyperEVM (shown as pending Investing
// balance), and the checks that start a sweep after a restart.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/hyperevm/hyperevm_bridge.dart';
import 'package:kute/services/hyperevm/hyperevm_vault.dart';
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/services/orchestra_routes.dart'
    show claimOrderTerminalAnalytics;
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/tracking_service.dart';

/// Opens the spending wallet [walletId]'s Hyperliquid key for [address].
/// Throws when the session is locked or the wallet or account changed;
/// the signer re-checks both before every signature leaves the app.
Future<HyperEvmSigner> openHyperEvmSigner(
    ProviderReader read, String walletId, String address) async {
  final wallet = pickSpendingWallet(read(settingsProvider));
  if (wallet == null || wallet.id != walletId) {
    throw StateError('The spending wallet changed.');
  }
  final session = read(seedSessionProvider);
  final authSession = read(sessionAuthProvider);
  if (!session.unlocked || authSession == null) {
    throw const SeedLockedException();
  }
  final mnemonic = await resolveBip39MnemonicFor(wallet,
      access: SeedAccess.automatic, session: session);
  if (mnemonic == null ||
      pickSpendingWallet(read(settingsProvider))?.id != wallet.id) {
    throw StateError('The spending wallet changed.');
  }
  final account = await HyperliquidOnboardingService.provisionHyperliquidAccount(
      mnemonic: mnemonic,
      walletId: wallet.id,
      evmDerivationVersion: wallet.evmDerivationVersion);
  if (!sameEvmAddress(account.address, address)) {
    throw StateError('The Hyperliquid account changed.');
  }
  void ensureAuthorized() {
    if (!read(seedSessionProvider).unlocked ||
        !identical(read(sessionAuthProvider), authSession) ||
        pickSpendingWallet(read(settingsProvider))?.id != wallet.id) {
      throw const SeedLockedException();
    }
  }

  return HyperEvmSignerNative(
    credentials: account.credentials,
    address: account.address,
    ensureAuthorized: ensureAuthorized,
  );
}

/// Fires once per sweep that credited HyperCore (a deposit that landed,
/// a refund that came back). The one-balance rail's `credited` stream.
final StreamController<void> hyperEvmCreditedController =
    StreamController<void>.broadcast();

/// USDC (in dollars) last read on the account's HyperEVM address: a
/// deposit Orchestra delivered and the sweep has not moved yet, or a
/// refund. Investing counts it as pending, so it never looks gone.
final hyperEvmParkedUsdProvider = StateProvider<double>((_) => 0);

/// Whether a withdrawal may still spend the USDC on [address]: one this
/// process is running, or one whose provider transfer was signed and is
/// not settled. Those keep the sweeper away.
Future<bool> hyperEvmReservedByWithdrawal(
    SettlementStore store, String address) async {
  for (final op in await store.pendingForReconcile()) {
    if (op.route.fromChain != 'hyperevm') continue;
    if (op.refund == null || !sameEvmAddress(op.refund!.address, address)) {
      continue;
    }
    if (store.isLeased(op.operationId)) return true;
    final signed = op.funding?.evmTxHash?.isNotEmpty ?? false;
    if (signed &&
        (op.stage == SettlementStage.broadcasting ||
            op.stage == SettlementStage.fundingUnknown)) {
      return true;
    }
  }
  return false;
}

/// Investing deposits that went through HyperEVM and whose USDC reached
/// HyperCore: their completion fires here, once, when the sweep credits
/// HyperCore (the reconciler leaves the success to this).
Future<void> reportHyperEvmDepositsCredited(SettlementStore store) async {
  for (final op in await store.all()) {
    if (op.route.toChain != 'hyperevm' ||
        op.flow != SettlementFlow.sparkToInvestingDirect ||
        op.stage != SettlementStage.settled) {
      continue;
    }
    if (!claimOrderTerminalAnalytics('settlement_op:${op.operationId}',
        success: true)) {
      continue;
    }
    final usd = op.quote == null
        ? null
        : (BigInt.tryParse(op.quote!.estimatedOut) ?? BigInt.zero)
                .toDouble() /
            1e6;
    TrackingService.hyperliquidDepositCompleted(
      amountUsd: usd,
      route: 'hyperevm',
      walletKind: 'hot',
      sourceAsset: op.route.fromAsset.toUpperCase() == 'BTC' ? 'btc' : 'usd',
      orderId: op.orderId,
      quoteId: op.quote?.quoteId,
    );
  }
}

final hyperEvmSweeperProvider = Provider<HyperEvmSweeper>((ref) {
  final reader = HyperEvmReaderNative();
  const journal = HiveHyperEvmTxJournal();
  return HyperEvmSweeper(
    reader: reader,
    journal: journal,
    keeper: HyperEvmFloatKeeper(reader: reader, journal: journal),
    openSigner: (address) async {
      try {
        final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
        if (walletId == null) return null;
        return await openHyperEvmSigner(ref.read, walletId, address);
      } catch (_) {
        return null;
      }
    },
    reservedByWithdrawal: (address) async =>
        hyperEvmReservedByWithdrawal(await SettlementStore.shared(), address),
    onParked: (_, micros) {
      try {
        ref.read(hyperEvmParkedUsdProvider.notifier).state =
            micros.toDouble() / 1e6;
      } catch (_) {}
    },
    onSwept: (_, micros) {
      TrackingService.hyperliquidDepositStep(
          step: 'core_credited', amountUsd: micros.toDouble() / 1e6);
      hyperEvmCreditedController.add(null);
      unawaited(() async {
        try {
          await reportHyperEvmDepositsCredited(await SettlementStore.shared());
        } catch (_) {}
      }());
    },
  );
});

/// After a start, a foreground or an unlock: sweeps when a recent
/// Investing move through HyperEVM may have left USDC on the address (a
/// deposit delivered or still on its way, a withdrawal that stopped or was
/// refunded), or USDC was seen parked there. Otherwise nothing is read:
/// no polling while nothing is in flight.
Future<void> maybeSweepHyperEvm(Ref ref) async {
  try {
    final store = await SettlementStore.shared();
    final now = DateTime.now();
    var arriving = false;
    var check = ref.read(hyperEvmParkedUsdProvider) > 0;
    for (final op in await store.all()) {
      if (op.flow == SettlementFlow.hyperevmGasFloat) continue;
      final recent = now.difference(op.updatedAt) < const Duration(hours: 24);
      if (op.route.toChain == 'hyperevm') {
        // A deposit Orchestra is still delivering, or delivered lately.
        if (!op.stage.isTerminal && op.stage.mayHaveMovedFunds) {
          arriving = true;
        } else if (op.stage == SettlementStage.settled && recent) {
          check = true;
        }
      } else if (op.route.fromChain == 'hyperevm' && recent) {
        // A withdrawal that stopped, failed or was refunded leaves its
        // USDC on the HyperEVM address.
        const leftOnEvm = {
          SettlementStage.notFunded,
          SettlementStage.failed,
          SettlementStage.refunding,
          SettlementStage.refunded,
          SettlementStage.lateDeposit,
        };
        if (leftOnEvm.contains(op.stage)) check = true;
      }
    }
    if (!arriving && !check) return;
    final address = await ref.read(hyperliquidAddressProvider.future);
    if (address == null) return;
    final sweeper = ref.read(hyperEvmSweeperProvider);
    if (arriving) {
      unawaited(sweeper.watch(address, total: const Duration(minutes: 10)));
    } else {
      unawaited(sweeper.sweepOnce(address).then((_) {}, onError: (_) {}));
    }
  } catch (_) {}
}
