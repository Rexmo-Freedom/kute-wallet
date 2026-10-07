// lib/providers/shell_wallet_provider.dart
//
// Which wallet the persistent shell is showing in its FIRST tab.
//
// Switching wallets is no longer a pushed screen with its own app bar and
// back button (user decision September 2026): the chosen wallet becomes the
// first tab of the existing top strip, exactly like Home. Null means the
// spending account, i.e. the ordinary Home tab.
//
// Lives under providers/ (not screens/) so the router, the nav strip and
// the accounts sheet can all read it without importing each other.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';

/// Id of the wallet mounted in the shell's first tab, or null for Home.
final shellWalletIdProvider = StateProvider<String?>((_) => null);

/// The wallet behind [shellWalletIdProvider]. Null when the shell is on
/// Home, and also when the id no longer resolves (the wallet was removed),
/// so a deleted wallet self-heals back to Home instead of stranding a tab.
final shellWalletProvider = Provider<WalletConfig?>((ref) {
  final id = ref.watch(shellWalletIdProvider);
  if (id == null) return null;
  final wallets = ref.watch(settingsProvider.select((s) => s.wallets));
  for (final wallet in wallets) {
    if (wallet.id == id) return wallet;
  }
  return null;
});

/// The wallet whose Dollars, Investing and Predictions the shell's strip
/// and pager offer: the wallet mounted in the first tab, or, with the
/// shell on Home, the wallet Home is actually showing when that is a
/// Ledger. Null means the spending account.
///
/// The shell wallet alone is not enough. It is null whenever nobody picked
/// a wallet in the wallets menu, yet Home renders the ACTIVE wallet, and
/// that can be a Ledger: the first wallet added becomes active, and a
/// Ledger-only install has no spending account to snap back to on boot.
/// Reading null as "spending" there drew the spending account's Dollars,
/// Investing and Predictions above a Ledger. The Ledger now owns the
/// strip, so its venues follow `ledger.hyperliquid` / `ledger.polymarket`
/// like everywhere else.
final shellVenueOwnerProvider = Provider<WalletConfig?>((ref) {
  final shell = ref.watch(shellWalletProvider);
  if (shell != null) return shell;
  final (active, wallets) =
      ref.watch(settingsProvider.select((s) => (s.activeWallet, s.wallets)));
  if (active != null) return active.isLedger ? active : null;
  // No active wallet: Home is empty. Without a spending account to own the
  // strip, a Ledger does.
  if (wallets.any((w) => w.isSparkWallet)) return null;
  for (final wallet in wallets) {
    if (wallet.isLedger) return wallet;
  }
  return null;
});
