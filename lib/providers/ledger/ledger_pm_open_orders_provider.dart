import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/ledger/ledger_pm_buying_power_provider.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

final ledgerPmOpenOrdersProvider = FutureProvider.autoDispose
    .family<List<Order>?, String>((ref, walletId) async {
  final timer = Timer(const Duration(seconds: 8), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final identity = ref.watch(ledgerIdentityProvider(walletId));
  if (identity?.hasVerifiedEvm != true) return null;
  final factory = ref.watch(ledgerPmExecutorFactoryProvider);
  final account =
      await PolymarketAccountResolver(ref.watch(ledgerPolymarketReadsProvider))
          .resolve(identity!.evmAddress!);
  if (account.kind == PolymarketAccountKind.none) return const <Order>[];
  if (!account.canAct) return null;
  final rows = await factory(
          walletId: walletId,
          pairedAddress: identity.evmAddress!,
          signer: ledgerReadOnlySigner(identity.evmAddress!),
          account: account)
      .readOpenOrders();
  return rows?.map(Order.fromJson).toList();
});

/// Cancel only an order returned by this exact Ledger account's CLOB session.
Future<void> cancelLedgerPmOrder(
    WidgetRef ref, String walletId, String id) async {
  final identity = ref.read(ledgerIdentityProvider(walletId));
  if (identity?.hasVerifiedEvm != true) {
    throw StateError('Connect your Ledger account.');
  }
  final account =
      await PolymarketAccountResolver(ref.read(ledgerPolymarketReadsProvider))
          .resolve(identity!.evmAddress!);
  if (!account.canAct ||
      ref.read(ledgerIdentityProvider(walletId)) != identity) {
    throw StateError('Wallet changed. Review again.');
  }
  final executor = ref.read(ledgerPmExecutorFactoryProvider)(
      walletId: walletId,
      pairedAddress: identity.evmAddress!,
      signer: ledgerReadOnlySigner(identity.evmAddress!),
      account: account);
  final orders = await executor.readOpenOrders();
  if (ref.read(ledgerIdentityProvider(walletId)) != identity ||
      orders == null) {
    throw StateError('Account unavailable. Retry.');
  }
  if (orders.any((order) => order['id'] == id)) await executor.cancelOrder(id);
  ref.invalidate(ledgerPmOpenOrdersProvider(walletId));
  ref.invalidate(ledgerPmBuyingPowerProvider(walletId));
  ref.invalidate(ledgerPmAccountProvider(walletId));
}
