// lib/services/orchestra/onetime_refund_address_store.dart
//
// The last return address the person typed for a one-time receive, per
// wallet and source network, so the next receive on that network starts
// with it filled in. On the device only: never in analytics, never sent
// anywhere except as a quote's refund address to Kute's backend. Wiped
// with the wallet.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_ce/hive.dart';

abstract final class OneTimeRefundAddressStore {
  static const boxName = 'onetime_refund_addresses_v1';

  /// Test seam: an in-memory store in place of the Hive box.
  @visibleForTesting
  static Map<String, String>? debugMemory;

  static String _key(String walletId, String chain) =>
      '$walletId|${chain.trim().toLowerCase()}';

  static Future<Box<String>> _box() async => Hive.isBoxOpen(boxName)
      ? Hive.box<String>(boxName)
      : await Hive.openBox<String>(boxName);

  /// The last return address for [walletId] on [chain], or null.
  static Future<String?> read(String walletId, String chain) async {
    final memory = debugMemory;
    if (memory != null) return memory[_key(walletId, chain)];
    try {
      return (await _box()).get(_key(walletId, chain));
    } catch (_) {
      return null;
    }
  }

  /// Remembers [address] for [walletId] on [chain]. Best effort.
  static Future<void> save(
      String walletId, String chain, String address) async {
    final memory = debugMemory;
    if (memory != null) {
      memory[_key(walletId, chain)] = address;
      return;
    }
    try {
      await (await _box()).put(_key(walletId, chain), address);
    } catch (_) {
      // Only a convenience: the next receive asks again.
    }
  }

  /// Forgets every return address of [walletId].
  static Future<void> deleteForWallet(String walletId) async {
    final memory = debugMemory;
    if (memory != null) {
      memory.removeWhere((k, _) => k.startsWith('$walletId|'));
      return;
    }
    try {
      final box = await _box();
      await box.deleteAll([
        for (final k in box.keys)
          if ('$k'.startsWith('$walletId|')) k
      ]);
    } catch (_) {}
  }

  /// Forgets every return address on the device.
  static Future<void> clear() async {
    debugMemory?.clear();
    if (debugMemory != null) return;
    try {
      if (Hive.isBoxOpen(boxName)) await Hive.box<String>(boxName).close();
      await Hive.deleteBoxFromDisk(boxName);
    } catch (_) {}
  }
}
