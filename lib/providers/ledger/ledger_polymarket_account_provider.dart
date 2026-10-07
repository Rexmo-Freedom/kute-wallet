// lib/providers/ledger/ledger_polymarket_account_provider.dart
//
// Public Polymarket reads for one Ledger wallet (Wallet hardening
// Phase 3, plan B8). Keyed by wallet ID and bound to the device-verified
// EVM address.
//
// Read only: account resolution, Data API positions, on-chain cash
// (pUSD and USDC.e) and CTF operator approvals. It never creates CLOB
// credentials, never deploys and never approves; there is no code path
// for any of that here. Each read
// category fails on its own and is reported in `partialFailures`; a
// failed read is null, never zero.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/services/hardware/ledger/ledger_venue_descriptor_store.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Position;

enum LedgerPmReadCategory { account, positions, cash }

class LedgerPmAccount {
  const LedgerPmAccount({
    required this.walletId,
    this.eoa,
    this.account,
    this.positions,
    this.pusdBalance,
    this.usdceBalance,
    this.partialFailures = const {},
  });

  const LedgerPmAccount.unpaired(this.walletId)
      : eoa = null,
        account = null,
        positions = null,
        pusdBalance = null,
        usdceBalance = null,
        partialFailures = const {};

  final String walletId;
  final String? eoa;
  final PolymarketLedgerAccount? account;
  final List<Position>? positions;

  /// Base units (6 decimals). Null when not read or the read failed.
  final BigInt? pusdBalance;
  final BigInt? usdceBalance;
  final Set<LedgerPmReadCategory> partialFailures;

  bool get isPaired => eoa != null;
  bool get hasPartialFailure => partialFailures.isNotEmpty;

  /// A legacy Safe is shown but never acted on (O4).
  bool get isReadOnly => account?.kind == PolymarketAccountKind.legacySafe;
}

/// Injectable for tests.
final ledgerPolymarketReadsProvider = Provider<PolymarketAccountReads>(
    (ref) => OnboardingPolymarketAccountReads());

/// `CTF.isApprovedForAll(owner, operator)` on-chain. Throws when the read
/// fails or returns no boolean, so an unknown approval is never missing.
typedef LedgerPmShareOperatorRead = Future<bool> Function(
    {required String owner, required String operator});

/// Injectable for tests. Read only, like every read here.
final ledgerPmShareOperatorReadProvider =
    Provider<LedgerPmShareOperatorRead>((ref) {
  final onboarding = PolymarketOnboardingService();
  return ({required owner, required operator}) async =>
      await onboarding.readApprovalOrThrow(
          token: PolymarketConstants.ctfAddress,
          owner: owner,
          spender: operator,
          operatorApproval: true) ==
      BigInt.one;
});

final ledgerPmAccountProvider = FutureProvider.autoDispose
    .family<LedgerPmAccount, String>((ref, walletId) async {
  final identity = ref.watch(ledgerIdentityProvider(walletId));
  if (identity == null || !identity.hasVerifiedEvm) {
    return LedgerPmAccount.unpaired(walletId);
  }
  final eoa = identity.evmAddress!;
  final reads = ref.watch(ledgerPolymarketReadsProvider);
  final failures = <LedgerPmReadCategory>{};

  PolymarketLedgerAccount? account;
  try {
    account = await PolymarketAccountResolver(reads).resolve(eoa);
    if (account.kind == PolymarketAccountKind.uncertain) {
      failures.add(LedgerPmReadCategory.account);
    }
  } catch (_) {
    failures.add(LedgerPmReadCategory.account);
  }

  List<Position>? positions;
  BigInt? pusd;
  BigInt? usdce;
  final address = account?.address;
  if (address != null) {
    final positionsF = reads.positions(address).then<List<Position>?>((p) => p,
        onError: (Object _) {
      failures.add(LedgerPmReadCategory.positions);
      return null;
    });
    try {
      final balances = await Future.wait([
        reads.erc20Balance(token: PolymarketConstants.pusdAddress, owner: address),
        reads.erc20Balance(
            token: PolymarketConstants.usdcEAddress, owner: address),
      ]);
      pusd = balances[0];
      usdce = balances[1];
    } catch (_) {
      failures.add(LedgerPmReadCategory.cash);
    }
    positions = await positionsF;
  }

  final kind = account?.kind;
  if (kind != null && kind != PolymarketAccountKind.uncertain) {
    try {
      await ref.read(ledgerVenueDescriptorStoreProvider).merge(
            walletId,
            pmAccountKind: switch (kind) {
              PolymarketAccountKind.depositWallet =>
                LedgerPmAccountKind.depositWallet,
              PolymarketAccountKind.legacySafe => LedgerPmAccountKind.legacySafe,
              _ => LedgerPmAccountKind.none,
            },
            pmAddress: address,
            pmSignatureType: account!.signatureType,
          );
    } catch (_) {
      // A cache that can always be rebuilt; never fails the read.
    }
  }

  return LedgerPmAccount(
    walletId: walletId,
    eoa: eoa,
    account: account,
    positions: positions,
    pusdBalance: pusd,
    usdceBalance: usdce,
    partialFailures: Set.unmodifiable(failures),
  );
});
