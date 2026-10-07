// lib/providers/viewed_wallet_provider.dart
//
// "What wallet is the user looking at right now?" — separate from
// "what wallet is operationally active?".
//
// `activeWalletId` is the wallet operations target: a Send screen
// will draft against it, the Spark SDK is bound to it, sync targets
// it. Changing it is a heavyweight commit — providers re-evaluate,
// SDK sessions reattach, the tx cache index rotates.
//
// `viewedWalletIdProvider` is the *display* counterpart. The carousel
// updates this synchronously on every swipe. Widgets that just need
// to follow the carousel (header strip, balance card title, the
// wallet picker's selection chip) can `ref.watch(viewedWalletId
// Provider)` and rebuild on every swipe without forcing the heavy
// active-wallet cascade.
//
// The carousel keeps debouncing the `activeWalletId` commit (250 ms
// in `wallet_cards.dart:_switchActiveWallet`) so operational
// behaviour is unaffected by rapid scrolls. Widgets that DO need the
// operational wallet (Send, Sign, etc.) keep reading `activeWalletId`.
//
// Defaults to whatever `settings.activeWalletId` reports, so
// pre-decouple readers see the same value either way.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/settings_model.dart' as settings_model;
import 'package:kute/providers/settings_provider.dart';

final viewedWalletIdProvider = StateProvider<String?>((ref) {
  // Initialise from the active wallet so a cold-start reader doesn't
  // see null until the carousel paints. After that, the carousel is
  // the source of truth for this provider's value — it overrides on
  // every swipe.
  return ref.read(settingsProvider).activeWalletId;
});

/// Convenience: resolves the currently-viewed wallet to its full
/// `WalletConfig`. Returns null if the id is missing or no wallet
/// matches (e.g. just-deleted wallet whose carousel slot hasn't
/// reflowed yet). Display widgets that show wallet name / icon /
/// category can `ref.watch(viewedWalletProvider)` and rebuild on
/// every swipe without dragging the heavy `activeWalletId` cascade
/// behind them.
final viewedWalletProvider = Provider<settings_model.WalletConfig?>((ref) {
  final id = ref.watch(viewedWalletIdProvider);
  if (id == null) return null;
  final wallets = ref.watch(settingsProvider.select((s) => s.wallets));
  for (final w in wallets) {
    if (w.id == id) return w;
  }
  return null;
});
