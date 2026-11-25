// lib/services/standing_orders/standing_order_store.dart
//
// Where a standing order lives across restarts: its public facts in a
// Hive box, one row per wallet and order; its secret (the signed
// Polymarket order, or the Investing approval the person gave) in the
// device's secure storage, keyed by the order's id. A secret is written
// ONCE per order ([writeSecret] refuses a second: never two signatures
// for one order) and deleted the moment the order is posted, cancelled or
// expired ([deleteSecret]).
//
// Tests pass an in-memory [SecretStore] and `Hive.init` a temp dir.

import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:kute/services/secure/flutter_secret_store.dart'
    show SecretStores;
import 'package:kute/services/secure/secret_store.dart';
import 'package:kute/services/standing_orders/standing_order.dart';

/// A second secret for an order that already has one: nothing is written.
class StandingOrderSecretExists implements Exception {
  const StandingOrderSecretExists(this.id);
  final String id;
  @override
  String toString() => 'StandingOrderSecretExists';
}

class StandingOrderStore {
  StandingOrderStore({SecretStore? secrets, this.boxName = defaultBoxName})
      : _secrets = secrets;

  static const defaultBoxName = 'standing_orders';
  final String boxName;
  final SecretStore? _secrets;

  SecretStore get _secretStore => _secrets ?? SecretStores.local;

  static String rowKey(String walletId, String id) => '$walletId:$id';
  static String secretKey(String id) => 'standing_order:$id';

  Future<Box<String>> _box() => Hive.openBox<String>(boxName);

  /// Every record of [walletId], oldest first. A row this version cannot
  /// read is skipped.
  Future<List<StandingOrder>> load(String walletId) async {
    final box = await _box();
    final out = <StandingOrder>[];
    for (final key in box.keys) {
      if (!key.toString().startsWith('$walletId:')) continue;
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final order = StandingOrder.fromJson(json);
        if (order != null && order.walletId == walletId) out.add(order);
      } catch (_) {
        // Unreadable: skipped, never a stop.
      }
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  Future<void> save(StandingOrder order) async {
    final box = await _box();
    await box.put(rowKey(order.walletId, order.id), jsonEncode(order.toJson()));
    await box.flush();
  }

  Future<void> remove(StandingOrder order) async {
    final box = await _box();
    await box.delete(rowKey(order.walletId, order.id));
    await box.flush();
  }

  /// Writes [id]'s secret once. Throws [StandingOrderSecretExists] when
  /// one is already there: a second signature is never stored while the
  /// first is unaccounted for.
  Future<void> writeSecret(String id, Map<String, Object?> secret) async {
    final key = secretKey(id);
    if (await _secretStore.containsKey(key: key)) {
      throw StandingOrderSecretExists(id);
    }
    await _secretStore.write(key: key, value: jsonEncode(secret));
  }

  /// [id]'s secret, or null when none (posted, cancelled, expired, or a
  /// read that failed: a failed read never permits a second signature,
  /// it reads as absent and the order settles honestly).
  Future<Map<String, Object?>?> readSecret(String id) async {
    final read = await _secretStore.read(key: secretKey(id));
    if (read is! SecretPresent) return null;
    try {
      return (jsonDecode(read.value) as Map).cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasSecret(String id) =>
      _secretStore.containsKey(key: secretKey(id));

  Future<void> deleteSecret(String id) async {
    try {
      await _secretStore.delete(key: secretKey(id));
    } catch (_) {
      // Best effort: a secret that stays is bounded by the order's life.
    }
  }
}
