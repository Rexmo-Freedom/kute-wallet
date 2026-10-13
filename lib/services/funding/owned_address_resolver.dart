// lib/services/funding/owned_address_resolver.dart
//
// Ownership of a quote's refund and recipient (Phase 5 plan B4). Both are
// resolved from the wallet itself, never from a backend response, for one
// pinned wallet id. Pure core plus a Riverpod adapter.
//
// Rules:
//  - a refund is on the source chain and owned by the source account;
//  - a recipient is owned by the destination account of the same wallet;
//  - the only cross-account pair is the hot Spark wallet with its own
//    venue accounts (Investing, Predictions);
//  - a Ledger route never has a hot recipient or refund.
//
// Hot rows resolve through [OwnedAddressResolver]. Ledger rows resolve
// through [resolveLedgerSettlementOwnership] from explicit, device-verified
// inputs: the Ledger Bitcoin receive address the device displayed for this
// wallet, the verified Ledger EVM identity, and the Polymarket deposit
// wallet the funding service re-derived from that identity.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';

/// Local sources of the spending wallet's own addresses. Each answers for
/// the wallet [spendingWalletId] names at the time of the call, or null.
abstract class OwnedAddressSources {
  String? spendingWalletId();

  Future<String?> sparkSelfAddress();

  /// The Hyperliquid EOA derived from the seed.
  Future<String?> hyperliquidEoa();

  /// The resolved Polymarket deposit wallet.
  Future<String?> polymarketDepositWallet();
}

typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// [OwnedAddressSources] over the app's providers. Pass `ref.read`.
class ProviderOwnedAddressSources implements OwnedAddressSources {
  ProviderOwnedAddressSources(this._read);

  final ProviderReader _read;

  @override
  String? spendingWalletId() => pickSpendingWallet(_read(settingsProvider))?.id;

  @override
  Future<String?> sparkSelfAddress() => _read(sparkSelfAddressProvider.future);

  @override
  Future<String?> hyperliquidEoa() => _read(hyperliquidAddressProvider.future);

  @override
  Future<String?> polymarketDepositWallet() async =>
      (await _read(polymarketTradingProvider.future)).proxyWalletAddress;
}

/// A resolved refund and recipient for one operation.
class SettlementOwnership {
  const SettlementOwnership({required this.refund, required this.recipient});

  final SettlementAddressRef refund;
  final SettlementAddressRef recipient;
}

/// Chains each hot account can hold an address on.
const Map<SettlementAccountKind, Set<String>> _kHotAccountChains = {
  SettlementAccountKind.sparkHot: {'spark'},
  SettlementAccountKind.pmHot: {'polygon'},
  SettlementAccountKind.hlHot: {'hypercore'},
};

/// Chains each Ledger account can hold an address on (B4 Ledger rows).
const Map<SettlementAccountKind, Set<String>> _kLedgerAccountChains = {
  SettlementAccountKind.ledgerBtc: {'bitcoin'},
  SettlementAccountKind.hlLedger: {'hypercore'},
  SettlementAccountKind.pmLedger: {'polygon'},
};

Never _reject(WalletGuardReason reason, String field) =>
    throw WalletGuardException(reason, field: field);

/// Checks the account pair of an operation before anything is resolved.
void checkSettlementAccountPair({
  required RouteKey route,
  required SettlementAccountKind source,
  required SettlementAccountKind destination,
}) {
  if (source == SettlementAccountKind.unknown ||
      destination == SettlementAccountKind.unknown) {
    _reject(WalletGuardReason.ownAddressUnavailable, 'account_kind');
  }
  if (source.isLedger != destination.isLedger) {
    // A Ledger route never has a hot recipient or refund.
    _reject(
      source.isLedger
          ? WalletGuardReason.recipientNotOwn
          : WalletGuardReason.refundNotOwn,
      'cross_account',
    );
  }
  if (source.isLedger) {
    // Ledger rows: only accounts of the same Ledger, each on its own chain.
    final sourceChains = _kLedgerAccountChains[source] ?? const {};
    if (!sourceChains.contains(route.fromChain)) {
      _reject(WalletGuardReason.refundNotOwn, 'source_chain');
    }
    final destinationChains = _kLedgerAccountChains[destination] ?? const {};
    if (!destinationChains.contains(route.toChain)) {
      _reject(WalletGuardReason.recipientNotOwn, 'destination_chain');
    }
    if (source == destination) {
      _reject(WalletGuardReason.recipientNotOwn, 'same_account');
    }
    return;
  }
  final crossAccount = source != destination;
  final sparkWithVenue = (source == SettlementAccountKind.sparkHot) !=
      (destination == SettlementAccountKind.sparkHot);
  if (crossAccount && !sparkWithVenue) {
    _reject(WalletGuardReason.recipientNotOwn, 'cross_account');
  }
  final sourceChains = _kHotAccountChains[source] ?? const {};
  if (!sourceChains.contains(route.fromChain)) {
    _reject(WalletGuardReason.refundNotOwn, 'source_chain');
  }
  final destinationChains = _kHotAccountChains[destination] ?? const {};
  if (!destinationChains.contains(route.toChain)) {
    _reject(WalletGuardReason.recipientNotOwn, 'destination_chain');
  }
}

bool _sameAddress(String chain, String a, String b) {
  if (chain == 'spark') return sameSparkAddress(a, b);
  if (kEvmAddressChains.contains(chain)) return sameEvmAddress(a, b);
  return a.trim().isNotEmpty && a.trim() == b.trim();
}

/// Checks the refund and recipient a quote request carries against the
/// resolved [ownership]. Throws [WalletGuardException] on a mismatch.
void verifySettlementOwnership({
  required RouteKey route,
  required SettlementOwnership ownership,
  required String refundAddress,
  required String recipientAddress,
}) {
  if (!_sameAddress(route.fromChain, refundAddress, ownership.refund.address)) {
    _reject(WalletGuardReason.refundNotOwn, 'refund');
  }
  if (!_sameAddress(
      route.toChain, recipientAddress, ownership.recipient.address)) {
    _reject(WalletGuardReason.recipientNotOwn, 'recipient');
  }
}

class OwnedAddressResolver {
  OwnedAddressResolver(this._sources, {this.mainnet = true});

  final OwnedAddressSources _sources;

  /// Spark on this app always runs on mainnet (lib/models/breez/init.dart).
  final bool mainnet;

  /// Resolves the refund and recipient for an operation on [walletId].
  /// Throws [WalletGuardException] when the pair is not allowed, an
  /// address cannot be resolved, or the spending wallet changed while
  /// resolving.
  Future<SettlementOwnership> resolve({
    required String walletId,
    required RouteKey route,
    required SettlementAccountKind source,
    required SettlementAccountKind destination,
  }) async {
    checkSettlementAccountPair(
        route: route, source: source, destination: destination);
    final refund = await _resolveHot(
      walletId: walletId,
      account: source,
      chain: route.fromChain,
      field: 'refund',
    );
    final recipient = await _resolveHot(
      walletId: walletId,
      account: destination,
      chain: route.toChain,
      field: 'recipient',
    );
    return SettlementOwnership(refund: refund, recipient: recipient);
  }

  /// Resolves the refund for a send to an address the user entered on
  /// [walletId]. Only the refund is owned; the recipient is recorded as
  /// [OwnedAddressKind.external] after a format check on the destination
  /// chain.
  Future<SettlementOwnership> resolveExternalSend({
    required String walletId,
    required RouteKey route,
    required SettlementAccountKind source,
    required String recipientAddress,
  }) async {
    if (source.isLedger) {
      // A Ledger route never pays an address the user typed.
      _reject(WalletGuardReason.recipientNotOwn, 'ledger_external');
    }
    final sourceChains = _kHotAccountChains[source] ?? const {};
    if (!sourceChains.contains(route.fromChain)) {
      _reject(WalletGuardReason.refundNotOwn, 'source_chain');
    }
    final refund = await _resolveHot(
      walletId: walletId,
      account: source,
      chain: route.fromChain,
      field: 'refund',
    );
    final recipient = recipientAddress.trim();
    if (recipient.isEmpty ||
        formatMatchesChain(route.toChain, recipient, mainnet: mainnet) !=
            AddressFormatMatch.ok) {
      _reject(WalletGuardReason.recipientAddressChain, 'recipient');
    }
    return SettlementOwnership(
      refund: refund,
      recipient: SettlementAddressRef(
          address: recipient, kind: OwnedAddressKind.external),
    );
  }

  Future<SettlementAddressRef> _resolveHot({
    required String walletId,
    required SettlementAccountKind account,
    required String chain,
    required String field,
  }) async {
    if (walletId.isEmpty || _sources.spendingWalletId() != walletId) {
      _reject(WalletGuardReason.ownAddressUnavailable, 'wallet_changed');
    }
    final String? address;
    final OwnedAddressKind kind;
    try {
      switch (account) {
        case SettlementAccountKind.sparkHot:
          kind = OwnedAddressKind.sparkSelf;
          address = await _sources.sparkSelfAddress();
        case SettlementAccountKind.hlHot:
          kind = OwnedAddressKind.hyperliquidEoa;
          address = await _sources.hyperliquidEoa();
        case SettlementAccountKind.pmHot:
          kind = OwnedAddressKind.polymarketDepositWallet;
          address = await _sources.polymarketDepositWallet();
        default:
          _reject(WalletGuardReason.ownAddressUnavailable, field);
      }
    } on WalletGuardException {
      rethrow;
    } catch (_) {
      _reject(WalletGuardReason.ownAddressUnavailable, field);
    }
    // The active wallet may have switched while the source was read; the
    // address then belongs to another wallet.
    if (_sources.spendingWalletId() != walletId) {
      _reject(WalletGuardReason.ownAddressUnavailable, 'wallet_changed');
    }
    final value = address?.trim() ?? '';
    if (value.isEmpty ||
        formatMatchesChain(chain, value, mainnet: mainnet) !=
            AddressFormatMatch.ok) {
      _reject(WalletGuardReason.ownAddressUnavailable, field);
    }
    return SettlementAddressRef(address: value, kind: kind);
  }
}

// ─────────────────────────────── Ledger rows ───────────────────────────────

/// A Ledger Bitcoin receive address that the device displayed and the user
/// confirmed for [walletId].
typedef LedgerBtcAddressProof = ({
  String walletId,
  String address,
  int index,
  DateTime verifiedAt,
});

/// The Ledger rows of the B4 table, resolved from explicit inputs for one
/// Ledger wallet. Never reads the active or spending wallet.
///
///  - `bitcoin:BTC` (ledgerBtc): [verifiedBtc] for this wallet, a mainnet
///    bitcoin address and never Spark, with its index and verification
///    time recorded.
///  - `hypercore:USDC` (hlLedger): [verifiedEvmAddress], the paired EVM
///    address with a completed device verification.
///  - `polygon:USDC.e` (pmLedger): [depositWallet], which the caller
///    re-derived from the verified EVM address; the verified identity is
///    still required.
///
/// Throws [WalletGuardException] when the pair is not allowed or a row is
/// missing or malformed.
SettlementOwnership resolveLedgerSettlementOwnership({
  required String walletId,
  required RouteKey route,
  required SettlementAccountKind source,
  required SettlementAccountKind destination,
  String? verifiedEvmAddress,
  LedgerBtcAddressProof? verifiedBtc,
  String? depositWallet,
  bool mainnet = true,
}) {
  if (!source.isLedger || !destination.isLedger) {
    _reject(WalletGuardReason.recipientNotOwn, 'cross_account');
  }
  checkSettlementAccountPair(
      route: route, source: source, destination: destination);
  if (walletId.isEmpty) {
    _reject(WalletGuardReason.ownAddressUnavailable, 'wallet');
  }

  SettlementAddressRef row(
      SettlementAccountKind account, String chain, String field) {
    switch (account) {
      case SettlementAccountKind.ledgerBtc:
        final proof = verifiedBtc;
        if (proof == null || proof.walletId != walletId) {
          _reject(WalletGuardReason.ownAddressUnavailable, field);
        }
        final address = proof.address.trim();
        if (formatMatchesChain(chain, address, mainnet: mainnet) !=
                AddressFormatMatch.ok ||
            isSparkAddress(address, mainnet: true) ||
            isSparkAddress(address, mainnet: false)) {
          _reject(WalletGuardReason.ownAddressUnavailable, field);
        }
        return SettlementAddressRef(
          address: address,
          kind: OwnedAddressKind.ledgerBitcoinReceive,
          index: proof.index,
          deviceVerifiedAt: proof.verifiedAt,
        );
      case SettlementAccountKind.hlLedger:
        final evm = verifiedEvmAddress?.trim() ?? '';
        if (evm.isEmpty ||
            formatMatchesChain(chain, evm, mainnet: mainnet) !=
                AddressFormatMatch.ok) {
          _reject(WalletGuardReason.ownAddressUnavailable, field);
        }
        return SettlementAddressRef(
            address: evm, kind: OwnedAddressKind.ledgerEvm);
      case SettlementAccountKind.pmLedger:
        final evm = verifiedEvmAddress?.trim() ?? '';
        final wallet = depositWallet?.trim() ?? '';
        if (evm.isEmpty ||
            wallet.isEmpty ||
            formatMatchesChain(chain, wallet, mainnet: mainnet) !=
                AddressFormatMatch.ok) {
          _reject(WalletGuardReason.ownAddressUnavailable, field);
        }
        return SettlementAddressRef(
            address: wallet, kind: OwnedAddressKind.polymarketDepositWallet);
      default:
        _reject(WalletGuardReason.ownAddressUnavailable, field);
    }
  }

  return SettlementOwnership(
    refund: row(source, route.fromChain, 'refund'),
    recipient: row(destination, route.toChain, 'recipient'),
  );
}
