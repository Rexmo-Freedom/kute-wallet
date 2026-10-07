import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Captures the route the user came from before entering the
/// add-wallet flow. Entry points (the home wallets menu, Sal, search)
/// set this to '/home' before pushing `addWallet`.
///
/// VESTIGIAL — currently write-only: no completion handler reads it;
/// the wallet-creation screens (`/import-xpub`,
/// `/import-external-address`, etc.) hardcode `context.go('/home')`.
/// It existed for the removed Wealth tab's "return to /portfolio"
/// case. Kept (and still written) only so a future non-home entry
/// point can wire up a consumer; delete it if none appears.
final addWalletReturnRouteProvider = StateProvider<String?>((_) => null);
