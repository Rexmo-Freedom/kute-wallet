// lib/providers/bitcoin_config_provider.dart
//
// Backwards-compatibility shim. The wallet-keyed family providers
// live in `wallet_scoped_bitcoin_config_provider.dart` — these
// `activeWallet`-bound providers forward to the family.
//
// Resolution order:
//   1. `bdkScopeWalletIdProvider` — when set, the user is inside a
//      hardware/watch-only detail surface (Send / Receive / Move
//      pushed from there). All BDK operations must scope to that
//      wallet's descriptor, not the spending wallet's.
//   2. `settings.activeWalletId` — otherwise the carousel's active
//      wallet (which the home keeps pinned to spending).
//
// Pre-shim bug: `_handleHardwareSigning` built a PSBT via these
// providers, but they only read `activeWalletId` → the PSBT was
// built against the SPENDING wallet's UTXOs while the user thought
// they were spending from their hardware wallet. The wallet-detail
// screen only sets `bdkScopeWalletIdProvider`, not `activeWalletId`
// (Home must stay parked on spending), so the shim has to honour
// the scope to route the send correctly.

import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/bitcoin_config_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scope_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';

/// Effective walletId for the legacy single-wallet providers. Reads
/// `bdkScopeWalletIdProvider` first (set by wallet-detail entries +
/// any flow pushed from there), then falls back to
/// `settings.activeWalletId` (the carousel's hot wallet).
String? _effectiveBdkWalletId(Ref ref) {
  final scopeId = ref.watch(bdkScopeWalletIdProvider);
  if (scopeId != null) return scopeId;
  return ref.watch(settingsProvider.select((s) => s.activeWalletId));
}

final bitcoinConfigProvider = FutureProvider<BitcoinConfig>((ref) async {
  final walletId = _effectiveBdkWalletId(ref);
  if (walletId == null) {
    throw Exception('No active wallet selected');
  }
  return ref.watch(bitcoinConfigForWalletProvider(walletId).future);
});

final restoreWalletProvider = FutureProvider<NativeWalletSession>((ref) async {
  final walletId = _effectiveBdkWalletId(ref);
  if (walletId == null) {
    throw Exception('No active wallet selected');
  }
  return ref.watch(restoreWalletForWalletProvider(walletId).future);
});
