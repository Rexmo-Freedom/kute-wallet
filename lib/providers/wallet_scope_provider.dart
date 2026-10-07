import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';

/// Wallet that operational flows (Send, Move, Receive, transaction
/// list, balance card, analytics) should target when set. Null = use
/// the active (spending) wallet as before.
///
/// Architecture:
///   * activeWalletId is *always* the Breez/spending wallet. Home
///     never changes its target.
///   * When the user drills into a hardware/watch-only wallet via
///     the portfolio detail screen, that screen registers its id
///     here via [setBdkScope]. The screen and any flows pushed from
///     it (Send, Move, Receive) observe this provider and route
///     against the scoped wallet instead.
///   * The BDK sync service watches this provider — when non-null,
///     it runs a parallel scan loop for that wallet so its balance
///     and transactions populate the per-wallet cache without
///     touching the Breez/Spark sync of the spending wallet.
///   * Popping back from the detail screen clears the scope, the
///     BDK loop stops, and the spending wallet is the only target
///     again.
final bdkScopeWalletIdProvider = StateProvider<String?>((ref) => null);

/// Resolve the wallet that operational flows should act on.
///
/// Returns the BDK-scoped wallet when set (the user is inside a
/// hardware/watch-only detail surface), otherwise the active
/// (spending) wallet. Returns null only when no spending wallet
/// exists either — a very-early-boot edge.
WalletConfig? scopedOperationalWallet(Ref ref) {
  final scopeId = ref.watch(bdkScopeWalletIdProvider);
  final settings = ref.watch(settingsProvider);
  if (scopeId != null) {
    for (final w in settings.wallets) {
      if (w.id == scopeId) return w;
    }
  }
  return settings.activeWallet;
}
