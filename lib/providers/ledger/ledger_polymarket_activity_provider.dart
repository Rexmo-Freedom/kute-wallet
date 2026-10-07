import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';

final ledgerPolymarketActivityModelProvider =
    Provider<PolymarketModel>((ref) => PolymarketModel());

/// Public history for the deposit wallet or legacy Safe resolved for this exact
/// Ledger. Never reads the spending account or creates trading credentials.
final ledgerPmActivityProvider = FutureProvider.autoDispose
    .family<List<Activity>, String>((ref, walletId) async {
  final identity = ref.watch(ledgerIdentityProvider(walletId));
  if (identity == null || !identity.hasVerifiedEvm) return const [];
  if (identity.walletId != walletId) {
    throw StateError('Ledger identity does not match the requested wallet');
  }
  final account = await ref.watch(ledgerPmAccountProvider(walletId).future);
  if (account.walletId != walletId ||
      account.eoa?.toLowerCase() != identity.evmAddress!.toLowerCase()) {
    throw StateError('Ledger account does not match the verified identity');
  }
  if (!account.isPaired ||
      account.account?.kind == PolymarketAccountKind.none) {
    return const [];
  }
  final address = account.account?.address;
  if (address == null ||
      account.account?.kind == PolymarketAccountKind.uncertain) {
    throw StateError('Ledger Predictions account is not available');
  }
  return ref
      .watch(ledgerPolymarketActivityModelProvider)
      .getUserActivityOrThrow(address);
});
