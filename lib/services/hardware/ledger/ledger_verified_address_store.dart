// lib/services/hardware/ledger/ledger_verified_address_store.dart
//
// Last Bitcoin receive address a Ledger confirmed on its own screen, per
// wallet (Wallet hardening Phase 4a, P4.8, owner decision O10).
//
// The Cash App purchase into a Ledger asks for an on-device check whenever
// the delivery address differs from the last one the device confirmed.
// Only public data is stored: the address, its derivation index and when it
// was confirmed. A malformed record reads as "never verified", so the check
// runs again instead of trusting it.

import 'dart:convert';

import 'package:hive_ce/hive.dart';

class LedgerVerifiedAddress {
  const LedgerVerifiedAddress({
    required this.address,
    required this.index,
    required this.verifiedAtMs,
  });

  static const int currentSchema = 1;

  final String address;
  final int index;
  final int verifiedAtMs;

  /// True when [address] at [index] is exactly what the device confirmed.
  bool matches(String address, int index) =>
      this.address == address && this.index == index;

  Map<String, dynamic> toJson() => {
        'schema': currentSchema,
        'address': address,
        'index': index,
        'verifiedAtMs': verifiedAtMs,
      };

  static LedgerVerifiedAddress? tryFromJson(Object? raw) {
    if (raw is! Map || raw['schema'] != currentSchema) return null;
    final address = raw['address'];
    final index = raw['index'];
    final at = raw['verifiedAtMs'];
    if (address is! String || address.trim().isEmpty) return null;
    if (index is! int || index < 0) return null;
    if (at is! int) return null;
    return LedgerVerifiedAddress(
        address: address, index: index, verifiedAtMs: at);
  }
}

class LedgerVerifiedAddressStore {
  LedgerVerifiedAddressStore({
    Future<Box<String>> Function()? openBox,
    DateTime Function()? clock,
  })  : _openBox = openBox ?? (() => Hive.openBox<String>(boxName)),
        _clock = clock ?? DateTime.now;

  static const String boxName = 'ledger_verified_receive_addresses';

  final Future<Box<String>> Function() _openBox;
  final DateTime Function() _clock;

  Future<LedgerVerifiedAddress?> read(String walletId) async {
    try {
      final box = await _openBox();
      final raw = box.get(walletId);
      if (raw == null) return null;
      return LedgerVerifiedAddress.tryFromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Remembers [address] at [index] as confirmed on the device.
  Future<LedgerVerifiedAddress> write(
    String walletId, {
    required String address,
    required int index,
  }) async {
    if (address.trim().isEmpty) {
      throw ArgumentError('address must not be empty');
    }
    if (index < 0) throw ArgumentError('index must not be negative');
    final record = LedgerVerifiedAddress(
      address: address,
      index: index,
      verifiedAtMs: _clock().millisecondsSinceEpoch,
    );
    final box = await _openBox();
    await box.put(walletId, jsonEncode(record.toJson()));
    return record;
  }

  Future<void> clearWallet(String walletId) async {
    final box = await _openBox();
    await box.delete(walletId);
  }
}
