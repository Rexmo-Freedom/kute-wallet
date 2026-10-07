import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/services/polymarket/ledger_pm_trade.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';

export 'package:kute/services/polymarket/ledger_pm_trade.dart'
    show LedgerPmBuyingPower;

/// Authenticated collateral minus open BUY reservations for this Ledger only.
/// Null means credentials need an explicit device authentication; failed reads
/// remain errors. Neither state is a verified zero balance.
final ledgerPmBuyingPowerProvider = FutureProvider.autoDispose
    .family<LedgerPmBuyingPower?, String>((ref, walletId) async {
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final identity = ref.watch(ledgerIdentityProvider(walletId));
  if (identity?.hasVerifiedEvm != true) return null;
  final factory = ref.watch(ledgerPmExecutorFactoryProvider);
  final reads = ref.watch(ledgerPolymarketReadsProvider);
  final account =
      await PolymarketAccountResolver(reads).resolve(identity!.evmAddress!);
  if (!account.canAct) return null;
  return factory(
          walletId: walletId,
          pairedAddress: identity.evmAddress!,
          signer: ledgerReadOnlySigner(identity.evmAddress!),
          account: account)
      .readBuyingPower();
});

/// Includes an unresolved allowance batch. Reopening a ticket or restarting
/// cannot hide a submission whose outcome has not been authoritatively read.
final ledgerPmPendingBetProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, walletId) async {
  final store = ref.watch(ledgerSubmittedActionStoreProvider);
  return await store.blockingPolymarketOrder(walletId) != null ||
      await store.blockingPolymarketBatch(walletId) != null;
});
