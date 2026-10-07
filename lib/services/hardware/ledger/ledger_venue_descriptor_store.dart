// lib/services/hardware/ledger/ledger_venue_descriptor_store.dart
//
// Public venue descriptors for a Ledger account, keyed by wallet ID
// (Wallet hardening Phase 3, plan B7).
//
// Every field is a cache that can always be rebuilt from the verified EVM
// address and public chain or venue reads. Nothing here is secret: no
// keys, no signatures, no API credentials (the Polymarket CLOB HMAC
// credentials live in secure storage under `pm_api_credentials_<walletId>`).
// Addresses are validated on write so a malformed value can never be
// persisted and later mistaken for an identity.

import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:kute/services/hardware/ledger/ledger_submitted_action_store.dart';
import 'package:kute/services/hardware/ledger/ledger_verified_address_store.dart';

/// How the Ledger's Polymarket account resolved (plan B8).
enum LedgerPmAccountKind {
  /// V2 deposit wallet (POLY_1271, sigType 3). The only kind a Ledger can
  /// act on.
  depositWallet,

  /// Legacy Gnosis Safe with code or positions. Read-only for Ledger (O4).
  legacySafe,

  /// Nothing deployed and no positions.
  none,
}

class LedgerVenueDescriptor {
  const LedgerVenueDescriptor({
    this.schema = currentSchema,
    this.hlAddress,
    this.pmAccountKind,
    this.pmAddress,
    this.pmSignatureType,
    required this.resolvedAtMs,
  });

  static const int currentSchema = 1;

  final int schema;
  final String? hlAddress;
  final LedgerPmAccountKind? pmAccountKind;
  final String? pmAddress;
  final int? pmSignatureType;
  final int resolvedAtMs;

  LedgerVenueDescriptor copyWith({
    String? hlAddress,
    LedgerPmAccountKind? pmAccountKind,
    String? pmAddress,
    int? pmSignatureType,
    required int resolvedAtMs,
  }) =>
      LedgerVenueDescriptor(
        schema: currentSchema,
        hlAddress: hlAddress ?? this.hlAddress,
        pmAccountKind: pmAccountKind ?? this.pmAccountKind,
        pmAddress: pmAddress ?? this.pmAddress,
        pmSignatureType: pmSignatureType ?? this.pmSignatureType,
        resolvedAtMs: resolvedAtMs,
      );

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'hlAddress': hlAddress,
        'pmAccountKind': pmAccountKind?.name,
        'pmAddress': pmAddress,
        'pmSignatureType': pmSignatureType,
        'resolvedAtMs': resolvedAtMs,
      };

  /// Null for anything malformed or from an unknown schema; callers
  /// rebuild instead of trusting it.
  static LedgerVenueDescriptor? tryFromJson(Object? raw) {
    if (raw is! Map || raw['schema'] != currentSchema) return null;
    final at = raw['resolvedAtMs'];
    if (at is! int) return null;
    final hl = raw['hlAddress'];
    final pm = raw['pmAddress'];
    if (hl != null && !_isAddress(hl)) return null;
    if (pm != null && !_isAddress(pm)) return null;
    final kindName = raw['pmAccountKind'];
    final kind = LedgerPmAccountKind.values
        .where((k) => k.name == kindName)
        .firstOrNull;
    if (kindName != null && kind == null) return null;
    final sigType = raw['pmSignatureType'];
    if (sigType != null && sigType is! int) return null;
    return LedgerVenueDescriptor(
      hlAddress: hl as String?,
      pmAccountKind: kind,
      pmAddress: pm as String?,
      pmSignatureType: sigType as int?,
      resolvedAtMs: at,
    );
  }

  void validate() {
    if (hlAddress != null && !_isAddress(hlAddress)) {
      throw ArgumentError('hlAddress must be a 0x address');
    }
    if (pmAddress != null && !_isAddress(pmAddress)) {
      throw ArgumentError('pmAddress must be a 0x address');
    }
    if (pmSignatureType != null &&
        (pmSignatureType! < 0 || pmSignatureType! > 3)) {
      throw ArgumentError('pmSignatureType out of range');
    }
  }
}

bool _isAddress(Object? value) =>
    value is String && RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value);

class LedgerVenueDescriptorStore {
  LedgerVenueDescriptorStore({
    Future<Box<String>> Function()? openBox,
    DateTime Function()? clock,
  })  : _openBox = openBox ?? (() => Hive.openBox<String>(boxName)),
        _clock = clock ?? DateTime.now;

  static const String boxName = 'ledger_venue_descriptors';

  final Future<Box<String>> Function() _openBox;
  final DateTime Function() _clock;

  Future<LedgerVenueDescriptor?> read(String walletId) async {
    final box = await _openBox();
    final raw = box.get(walletId);
    if (raw == null) return null;
    try {
      return LedgerVenueDescriptor.tryFromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String walletId, LedgerVenueDescriptor descriptor) async {
    descriptor.validate();
    final box = await _openBox();
    await box.put(walletId, jsonEncode(descriptor.toJson()));
  }

  /// Merges fresh public reads into the cached descriptor.
  Future<LedgerVenueDescriptor> merge(
    String walletId, {
    String? hlAddress,
    LedgerPmAccountKind? pmAccountKind,
    String? pmAddress,
    int? pmSignatureType,
  }) async {
    final now = _clock().millisecondsSinceEpoch;
    final current = await read(walletId);
    final next = current == null
        ? LedgerVenueDescriptor(
            hlAddress: hlAddress,
            pmAccountKind: pmAccountKind,
            pmAddress: pmAddress,
            pmSignatureType: pmSignatureType,
            resolvedAtMs: now,
          )
        : current.copyWith(
            hlAddress: hlAddress,
            pmAccountKind: pmAccountKind,
            pmAddress: pmAddress,
            pmSignatureType: pmSignatureType,
            resolvedAtMs: now,
          );
    await write(walletId, next);
    return next;
  }

  Future<void> clearWallet(String walletId) async {
    final box = await _openBox();
    await box.delete(walletId);
  }
}

/// Removes every Ledger-scoped local record for [walletId]: venue
/// descriptors and submitted-action records. Called from
/// `SettingsModel.removeWallet`, next to the `pm_api_credentials_<walletId>`
/// delete. Best effort per store, like the other per-wallet cleanups.
Future<void> wipeLedgerWalletLocalData(
  String walletId, {
  LedgerVenueDescriptorStore? descriptors,
  LedgerSubmittedActionStore? submittedActions,
  LedgerVerifiedAddressStore? verifiedAddresses,
}) async {
  try {
    await (descriptors ?? LedgerVenueDescriptorStore()).clearWallet(walletId);
  } catch (_) {}
  try {
    await (submittedActions ?? LedgerSubmittedActionStore())
        .clearWallet(walletId);
  } catch (_) {}
  try {
    await (verifiedAddresses ?? LedgerVerifiedAddressStore())
        .clearWallet(walletId);
  } catch (_) {}
}
