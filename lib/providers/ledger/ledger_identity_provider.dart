// lib/providers/ledger/ledger_identity_provider.dart
//
// The public identity of one Ledger wallet, keyed by wallet ID (Wallet
// hardening Phase 3, plan B8). Never follows the active or spending
// wallet; a Ledger surface always names the wallet it shows.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/hardware/ledger/ledger_venue_descriptor_store.dart';

class LedgerIdentity {
  const LedgerIdentity({
    required this.walletId,
    this.masterFingerprint,
    this.evmAddress,
    this.evmDerivationPath,
    this.evmVerifiedAtMs,
  });

  factory LedgerIdentity.fromWallet(WalletConfig wallet) => LedgerIdentity(
        walletId: wallet.id,
        masterFingerprint: wallet.masterFingerprint,
        evmAddress: wallet.evmAddress,
        evmDerivationPath: wallet.evmDerivationPath,
        evmVerifiedAtMs: wallet.evmVerifiedAtMs,
      );

  final String walletId;
  final String? masterFingerprint;
  final String? evmAddress;
  final String? evmDerivationPath;
  final int? evmVerifiedAtMs;

  bool get hasVerifiedEvm => evmAddress != null && evmVerifiedAtMs != null;

  @override
  bool operator ==(Object other) =>
      other is LedgerIdentity &&
      other.walletId == walletId &&
      other.masterFingerprint == masterFingerprint &&
      other.evmAddress == evmAddress &&
      other.evmDerivationPath == evmDerivationPath &&
      other.evmVerifiedAtMs == evmVerifiedAtMs;

  @override
  int get hashCode => Object.hash(walletId, masterFingerprint, evmAddress,
      evmDerivationPath, evmVerifiedAtMs);
}

/// Null when [walletId] is missing or is not a Ledger.
final ledgerIdentityProvider =
    Provider.autoDispose.family<LedgerIdentity?, String>((ref, walletId) {
  return ref.watch(settingsProvider.select((settings) {
    for (final wallet in settings.wallets) {
      if (wallet.id == walletId) {
        return wallet.isLedger ? LedgerIdentity.fromWallet(wallet) : null;
      }
    }
    return null;
  }));
});

/// Public venue descriptor cache (injectable for tests).
final ledgerVenueDescriptorStoreProvider =
    Provider<LedgerVenueDescriptorStore>((ref) => LedgerVenueDescriptorStore());
