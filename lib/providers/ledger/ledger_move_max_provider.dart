import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/bitcoin_model.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/bitcoin_provider.dart'
    show getCustomFeeRateProvider;
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/services/bitcoin/ledger_btc_send_service.dart'
    show bitcoinScriptPubKeyHex;
import 'package:kute/services/onchain/native_onchain_service.dart'
    show OnchainException;

/// A conservative principal cap for a Ledger venue deposit. The final quote
/// and transaction review still determine the actual network fee.
class LedgerMoveMax {
  const LedgerMoveMax({
    required this.maxSats,
    required this.estimatedFeeSats,
    required this.feeRateSatVb,
  });

  final int maxSats;

  /// Drain fee plus a reserve for the eventual recipient and change outputs.
  final int estimatedFeeSats;

  /// The selected rate, rounded up exactly as the native BDK builder does.
  final double feeRateSatVb;
}

/// Builds an unsigned drain using only the named Ledger's BDK session. No
/// signing, broadcasting, active-wallet lookup, or address-index advance.
/// Callers must treat loading/errors as an unknown cap, never use an old value
/// while a refreshed estimate is pending, and retain the final send review.
final ledgerMoveMaxProvider =
    FutureProvider.autoDispose.family<LedgerMoveMax, String>((ref, walletId) async {
  final identity = ref.watch(ledgerIdentityProvider(walletId));
  final wallet = ref.watch(settingsProvider.select((settings) =>
      settings.wallets.where((wallet) => wallet.id == walletId).firstOrNull));
  if (wallet == null ||
      !wallet.isLedger ||
      !wallet.usesBdk ||
      identity?.hasVerifiedEvm != true ||
      !RegExp(r'^[0-9a-fA-F]{8}$')
          .hasMatch(wallet.masterFingerprint?.trim() ?? '')) {
    throw StateError('Ledger wallet identity unavailable');
  }

  ref.watch(walletBalanceCacheProvider.select((cache) => cache[walletId]));
  ref.watch(walletTransactionCacheProvider.select((cache) => cache[walletId]));
  var disposed = false;
  ref.onDispose(() => disposed = true);

  void requireCurrentIdentity() {
    if (disposed) throw StateError('Ledger maximum estimate superseded');
    final current = ref
        .read(settingsProvider)
        .wallets
        .where((wallet) => wallet.id == walletId)
        .firstOrNull;
    if (current == null ||
        !current.isLedger ||
        current.scriptType != wallet.scriptType ||
        ref.read(ledgerIdentityProvider(walletId)) != identity) {
      throw StateError('Ledger wallet identity changed');
    }
  }

  final dependencies = await Future.wait<Object>([
    ref.watch(bitcoinModelForWalletProvider(walletId).future),
    ref.watch(getCustomFeeRateProvider.future),
  ]);
  requireCurrentIdentity();
  final model = dependencies[0] as BitcoinModel;
  final selectedRate = dependencies[1] as double;
  if (model.config.walletId != walletId ||
      model.config.network != Network.bitcoin ||
      !selectedRate.isFinite ||
      selectedRate <= 0) {
    throw StateError('Ledger balance or fee estimate unavailable');
  }

  // Opening Move also schedules a scan. Native admission is exclusive, so a
  // read-only estimate waits for it rather than repeatedly failing as busy.
  // Only admission failures retry; a timed-out native request may still run.
  Future<T> whenIdle<T>(Future<T> Function() operation) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      await model.config.session.service.whenIdle(walletId).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw const OnchainException('timeout'),
          );
      requireCurrentIdentity();
      if (model.config.needsFullScan) {
        throw StateError('Ledger balance has not been scanned');
      }
      try {
        return await operation();
      } on OnchainException catch (error) {
        if (error.code != 'busy' || attempt == 2) rethrow;
      }
    }
    throw const OnchainException('busy');
  }

  final rate = selectedRate.ceilToDouble();
  final address = await whenIdle(() => model.getCurrentAddress(0));
  requireCurrentIdentity();
  final script = bitcoinScriptPubKeyHex(address, mainnet: true);
  if (script == null) throw StateError('Ledger receive address unavailable');

  final drain = await whenIdle(() => model.drainWalletBitcoinTransaction(
      TransactionBuilder(0, address, rate)));
  requireCurrentIdentity();
  final transaction = drain.extractTx();
  final outputs = transaction.output();
  if (drain.signed == true ||
      !transaction.hasInputOutputDetails ||
      transaction.input().isEmpty ||
      outputs.length != 1 ||
      outputs.single.scriptPubkey.toLowerCase() != script) {
    throw StateError('Ledger maximum estimate could not be verified');
  }

  final spendable = outputs.single.value.toSat();
  final drainFee = drain.fee();
  const maximumMoneySats = 2100000000000000;
  if (spendable <= 0 ||
      drainFee <= 0 ||
      spendable + drainFee > maximumMoneySats) {
    throw StateError('Ledger maximum estimate is invalid');
  }

  // The drain has already paid for all eligible inputs and one own output.
  // An exact-amount deposit can replace that output and add change. Supported
  // address formats have at most 42 script bytes (a 40-byte witness program),
  // so 8 value + 1 length + 42 script bytes bounds each output at 51 vbytes.
  // Reserve both whole outputs without crediting the existing drain output.
  const outputReserveVbytes = 2 * 51;
  if (rate > maximumMoneySats / outputReserveVbytes) {
    throw StateError('Ledger fee estimate is invalid');
  }
  final reserve = (rate * outputReserveVbytes).ceil();
  return LedgerMoveMax(
    maxSats: spendable > reserve ? spendable - reserve : 0,
    estimatedFeeSats: drainFee + reserve,
    feeRateSatVb: rate,
  );
});
