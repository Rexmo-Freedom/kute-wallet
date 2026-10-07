// lib/services/bitcoin/tx_details_cache.dart
//
// On-disk memo of the `GET /tx/{txid}` payloads the transaction flow graph
// draws from. A confirmed transaction's inputs, outputs and fee are immutable
// (an RBF replacement is a different txid), so once the app has seen them once
// it never has to wait on mempool.space again: reopening a detail sheet paints
// the braid from disk instead of a skeleton.
//
// Only CONFIRMED transactions are stored. An unconfirmed one can still be
// replaced, and the in-memory cache already covers reopening it inside the
// same session.
//
// Every accessor is failure-tolerant: a missing box, a corrupt entry or a
// payload filed under the wrong txid all read as "nothing cached", and the
// caller falls back to the network.

import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:kute/services/mempool_address_service.dart';

class TxDetailsCache {
  TxDetailsCache._();

  static const String boxName = 'mempool_tx_details';

  /// Bump when the stored shape changes incompatibly: entries written by an
  /// older version are then ignored and the next fetch overwrites them.
  static const int _schemaVersion = 1;

  /// Insertion-order bound. Hive keeps `keys` in insertion order, so the
  /// oldest entry is always the first one.
  static const int _maxEntries = 500;

  static Future<Box<String>>? _opening;

  /// The box is opened lazily on first use (it is not registered in the boot
  /// path) and reopened if it was closed underneath us.
  static Future<Box<String>> get _box async {
    try {
      final box = await (_opening ??= Hive.openBox<String>(boxName));
      if (box.isOpen) return box;
      _opening = Hive.openBox<String>(boxName);
      return await _opening!;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  /// The stored payload for [txid], or null when nothing usable is on disk.
  static Future<MempoolTxDetails?> read(String txid) async {
    final id = txid.toLowerCase();
    if (id.isEmpty) return null;
    try {
      final raw = (await _box).get(id);
      if (raw == null) return null;
      final wrapper = jsonDecode(raw) as Map<String, dynamic>;
      if ((wrapper['v'] as num?)?.toInt() != _schemaVersion) return null;
      final tx = wrapper['tx'];
      if (tx is! Map) return null;
      final details = MempoolTxDetails.fromJson(Map<String, dynamic>.from(tx));
      // Same rule as the network path: a payload for another transaction is
      // rejected outright rather than shown.
      if (details.txid.toLowerCase() != id) return null;
      return details;
    } catch (_) {
      return null;
    }
  }

  /// Store [details] when it is confirmed. Never throws.
  static Future<void> write(MempoolTxDetails details) async {
    if (!details.confirmed) return;
    final id = details.txid.toLowerCase();
    if (id.isEmpty) return;
    try {
      final box = await _box;
      await box.put(
        id,
        jsonEncode({'v': _schemaVersion, 'tx': details.toJson()}),
      );
      while (box.length > _maxEntries && box.keys.isNotEmpty) {
        await box.delete(box.keys.first);
      }
    } catch (_) {
      // A full or unavailable disk just means the next open refetches.
    }
  }
}
