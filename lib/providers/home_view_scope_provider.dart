import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Drives whether home surfaces (Analytics, Activity, Predictions
/// rail) display an aggregated / asset-filtered / per-wallet view.
/// Set by the home carousel on every page change so dependent
/// surfaces can branch off a single source of truth.
///
/// Recognised values:
///   - `null` — follow the active wallet (default, pre-carousel
///     behaviour)
///   - `'all'` — sum across every wallet on device (carousel page 0)
///   - `'spending-btc'` — spending wallet, Bitcoin slice only
///     (carousel page 1)
///   - `'spending-usdc'` — spending wallet, USDC slice only
///     (carousel page 2)
final homeViewScopeProvider = StateProvider<String?>((ref) => null);

/// Convenience predicate so widgets can read the scope without
/// remembering the magic string.
final isAllAccountsScopeProvider = Provider<bool>(
    (ref) => ref.watch(homeViewScopeProvider) == 'all');

/// True when the carousel is on the Bitcoin sub-page — analytics
/// surfaces should hide USDC + stables and chart pure BTC.
final isBtcOnlyScopeProvider = Provider<bool>(
    (ref) => ref.watch(homeViewScopeProvider) == 'spending-btc');

/// True when the carousel is on the USDC sub-page — analytics
/// surfaces should hide BTC and chart only the USDC balance.
final isUsdcOnlyScopeProvider = Provider<bool>(
    (ref) => ref.watch(homeViewScopeProvider) == 'spending-usdc');
