// lib/services/polymarket/polymarket_account_resolver.dart
//
// Read-only Polymarket account resolution for a Ledger EOA (Wallet
// hardening Phase 3, plan B8).
//
// It never creates anything: no ClobAuth, no API key, no deployment, no
// approval. It only reads the relayer registry, contract code, the factory
// prediction and Data API positions.
//
// Order, matching the hot `resolveDepositWalletAddress` so both paths see
// the same wallet:
//   1. UUPS deposit wallet registered on the relayer or deployed → use it.
//   2. The factory's current (beacon) wallet deployed or registered → use it.
//   3. Legacy Safe with code or positions → read-only for Ledger (O4).
//   4. Otherwise `none`, but only when every read succeeded. Any failed
//      read that could have changed the answer gives `uncertain`, never
//      `none`.

import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';

/// The reads the resolver and the Ledger account provider need. Every
/// method throws on failure except [relayerWalletDeployed], which returns
/// null when unknown.
abstract class PolymarketAccountReads {
  String deriveDepositWalletAddress(String eoa);
  Future<String> predictDepositWallet(String eoa);
  Future<bool?> relayerWalletDeployed(String address);
  Future<bool> hasCode(String address);
  Future<String> deriveSafeAddress(String eoa);
  Future<List<Position>> positions(String address);
  Future<BigInt> erc20Balance({required String token, required String owner});
}

/// Production reads over the onboarding service's strict variants and the
/// Data API.
class OnboardingPolymarketAccountReads implements PolymarketAccountReads {
  OnboardingPolymarketAccountReads({
    PolymarketOnboardingService? onboarding,
    PolymarketModel? model,
  })  : _onboarding = onboarding ?? PolymarketOnboardingService(),
        _model = model ?? PolymarketModel();

  final PolymarketOnboardingService _onboarding;
  final PolymarketModel _model;

  @override
  String deriveDepositWalletAddress(String eoa) =>
      _onboarding.deriveDepositWalletAddress(eoa);

  @override
  Future<String> predictDepositWallet(String eoa) =>
      _onboarding.predictDepositWalletOrThrow(eoa);

  @override
  Future<bool?> relayerWalletDeployed(String address) =>
      _onboarding.relayerWalletDeployed(address);

  @override
  Future<bool> hasCode(String address) =>
      _onboarding.hasContractCodeOrThrow(address);

  @override
  Future<String> deriveSafeAddress(String eoa) =>
      _onboarding.deriveSafeAddressOrThrow(eoa);

  @override
  Future<List<Position>> positions(String address) =>
      _model.getPositionsOrThrow(address);

  @override
  Future<BigInt> erc20Balance({required String token, required String owner}) =>
      _onboarding.readErc20BalanceOrThrow(token: token, owner: owner);
}

enum PolymarketAccountKind { depositWallet, legacySafe, none, uncertain }

enum DepositWalletVariant { uups, beacon }

class PolymarketLedgerAccount {
  const PolymarketLedgerAccount._({
    required this.kind,
    this.address,
    this.variant,
    this.predictedDepositWallet,
  });

  const PolymarketLedgerAccount.depositWallet(
      String address, DepositWalletVariant variant)
      : this._(
            kind: PolymarketAccountKind.depositWallet,
            address: address,
            variant: variant);

  const PolymarketLedgerAccount.legacySafe(String address)
      : this._(kind: PolymarketAccountKind.legacySafe, address: address);

  const PolymarketLedgerAccount.none({String? predictedDepositWallet})
      : this._(
            kind: PolymarketAccountKind.none,
            predictedDepositWallet: predictedDepositWallet);

  const PolymarketLedgerAccount.uncertain()
      : this._(kind: PolymarketAccountKind.uncertain);

  final PolymarketAccountKind kind;

  /// The account address for [PolymarketAccountKind.depositWallet] and
  /// [PolymarketAccountKind.legacySafe].
  final String? address;
  final DepositWalletVariant? variant;

  /// Where a future deposit wallet would be (display only; never deployed
  /// from here).
  final String? predictedDepositWallet;

  /// POLY_1271 (3) for deposit wallets, POLY_GNOSIS_SAFE (2) for legacy
  /// Safes.
  int? get signatureType => switch (kind) {
        PolymarketAccountKind.depositWallet => 3,
        PolymarketAccountKind.legacySafe => 2,
        _ => null,
      };

  /// Only a deposit wallet can act for a Ledger; a legacy Safe is
  /// read-only (O4).
  bool get canAct => kind == PolymarketAccountKind.depositWallet;
}

class PolymarketAccountResolver {
  PolymarketAccountResolver(this._reads);

  final PolymarketAccountReads _reads;

  Future<PolymarketLedgerAccount> resolve(String eoa) async {
    var uncertain = false;
    Future<T?> attempt<T>(Future<T> Function() read) async {
      try {
        return await read();
      } catch (_) {
        uncertain = true;
        return null;
      }
    }

    final uups = _reads.deriveDepositWalletAddress(eoa);
    if (await _reads.relayerWalletDeployed(uups) == true ||
        await attempt(() => _reads.hasCode(uups)) == true) {
      return PolymarketLedgerAccount.depositWallet(
          uups, DepositWalletVariant.uups);
    }

    final beacon = await attempt(() => _reads.predictDepositWallet(eoa));
    if (beacon != null && beacon.toLowerCase() != uups.toLowerCase()) {
      if (await attempt(() => _reads.hasCode(beacon)) == true ||
          await _reads.relayerWalletDeployed(beacon) == true) {
        return PolymarketLedgerAccount.depositWallet(
            beacon, DepositWalletVariant.beacon);
      }
    }

    final safe = await attempt(() => _reads.deriveSafeAddress(eoa));
    if (safe != null && safe.toLowerCase() != PolymarketConstants.zeroAddress.toLowerCase()) {
      if (await attempt(() => _reads.hasCode(safe)) == true) {
        return PolymarketLedgerAccount.legacySafe(safe);
      }
      final positions = await attempt(() => _reads.positions(safe));
      if (positions != null && positions.isNotEmpty) {
        return PolymarketLedgerAccount.legacySafe(safe);
      }
    }

    if (uncertain) return const PolymarketLedgerAccount.uncertain();
    return PolymarketLedgerAccount.none(predictedDepositWallet: beacon ?? uups);
  }
}
