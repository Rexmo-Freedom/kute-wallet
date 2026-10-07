// lib/providers/ledger/ledger_hyperliquid_account_provider.dart
//
// Public Hyperliquid reads for one Ledger wallet (Wallet hardening
// Phase 3, plan B8). Keyed by wallet ID and bound to the device-verified
// EVM address; never to the hot address.
//
// Reads: perps and spot, every HIP-3 dex clearinghouse, open orders and
// fills. Each category fails on its own and is reported in
// `partialFailures`; a failed read is null, never zero. No signing, no credentials, no auto-fire listeners, no sweep.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';

enum LedgerHlReadCategory {
  account,
  hip3Dexes,
  openOrders,
  fills,
}

class LedgerHlAccount {
  const LedgerHlAccount({
    required this.walletId,
    this.address,
    this.account,
    this.dexAccounts = const {},
    this.openOrders,
    this.fills,
    this.partialFailures = const {},
  });

  const LedgerHlAccount.unpaired(this.walletId)
      : address = null,
        account = null,
        dexAccounts = const {},
        openOrders = null,
        fills = null,
        partialFailures = const {};

  final String walletId;

  /// The verified EVM address; null until the Ethereum identity is paired.
  final String? address;

  /// Default perps dex plus spot. Null when that read failed.
  final HlAccountSnapshot? account;

  /// HIP-3 dex name → perps state, for the dexes that read successfully.
  final Map<String, HlAccountSnapshot> dexAccounts;
  final List<HlOpenOrder>? openOrders;
  final List<HlFill>? fills;

  /// Categories that could not load. The UI shows "Some balances could not
  /// load" instead of zero.
  final Set<LedgerHlReadCategory> partialFailures;

  bool get isPaired => address != null;
  bool get hasPartialFailure => partialFailures.isNotEmpty;
}

/// Injectable for tests.
final ledgerHyperliquidModelProvider =
    Provider<HyperliquidModel>((ref) => HyperliquidModel());

const int _dexBatchSize = 8;

final ledgerHlAccountProvider = FutureProvider.autoDispose
    .family<LedgerHlAccount, String>((ref, walletId) async {
  final identity = ref.watch(ledgerIdentityProvider(walletId));
  if (identity == null || !identity.hasVerifiedEvm) {
    return LedgerHlAccount.unpaired(walletId);
  }
  final address = identity.evmAddress!;
  final model = ref.watch(ledgerHyperliquidModelProvider);
  final failures = <LedgerHlReadCategory>{};

  Future<T?> guard<T>(
      LedgerHlReadCategory category, Future<T> Function() read) async {
    try {
      return await read();
    } catch (_) {
      failures.add(category);
      return null;
    }
  }

  final accountF =
      guard(LedgerHlReadCategory.account, () => model.getAccountSnapshot(address));
  final fillsF =
      guard(LedgerHlReadCategory.fills, () => model.getUserFills(address));

  final dexAccounts = <String, HlAccountSnapshot>{};
  final dexes =
      await guard(LedgerHlReadCategory.hip3Dexes, model.getPerpDexsStrict);
  if (dexes != null) {
    for (var start = 0; start < dexes.length; start += _dexBatchSize) {
      await Future.wait(dexes.skip(start).take(_dexBatchSize).map((dex) async {
        final state = await guard(LedgerHlReadCategory.hip3Dexes,
            () => model.getDexClearinghouse(address, dex.name));
        if (state != null) dexAccounts[dex.name] = state;
      }));
    }
  }

  // The venue returns a builder (HIP-3) dex's resting orders only when
  // that dex is named, so read the main dex plus every builder dex this
  // account holds anything on. Without the dex list the builder orders
  // cannot be known: the read is reported as incomplete, never as "no
  // orders".
  final orders = await guard(LedgerHlReadCategory.openOrders, () async {
    if (dexes == null) throw StateError('Builder dexes unavailable');
    return model.getOpenOrders(address, dexes: [
      for (final e in dexAccounts.entries)
        if (e.value.hasActivity) e.key,
    ]);
  });

  final result = LedgerHlAccount(
    walletId: walletId,
    address: address,
    account: await accountF,
    dexAccounts: Map.unmodifiable(dexAccounts),
    openOrders: orders,
    fills: await fillsF,
    partialFailures: Set.unmodifiable(failures),
  );

  try {
    await ref
        .read(ledgerVenueDescriptorStoreProvider)
        .merge(walletId, hlAddress: address);
  } catch (_) {
    // A cache that can always be rebuilt; never fails the read.
  }
  return result;
});
