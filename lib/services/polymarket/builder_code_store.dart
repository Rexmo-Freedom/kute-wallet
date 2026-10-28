// lib/services/polymarket/builder_code_store.dart
//
// The device copy of the Polymarket builder code (see
// PolymarketBuilderCodeResolver). One Hive box, one key, opened on first
// use so it needs no slot in main()'s boot batch. Best-effort both ways:
// a box that cannot be opened reads as "no copy" and writes are dropped.

import 'dart:async';

import 'package:hive_ce/hive.dart';
import 'package:kute/services/polymarket/builder_code_resolver.dart';

class PolymarketBuilderCodeStore {
  PolymarketBuilderCodeStore._();

  static const _boxName = 'polymarket_builder_code';
  static const _key = 'code';
  static const _revisionKey = 'revision';

  static Future<Box<String>>? _opening;

  static Future<Box<String>> _box() {
    if (Hive.isBoxOpen(_boxName)) return Future.value(Hive.box<String>(_boxName));
    return _opening ??= Hive.openBox<String>(_boxName).whenComplete(() {
      _opening = null;
    });
  }

  /// The last copy written, or null.
  static Future<PersistedBuilderCode?> read() async {
    try {
      final box = await _box();
      final code = box.get(_key);
      if (code == null) return null;
      return PersistedBuilderCode(code, int.tryParse(box.get(_revisionKey) ?? ''));
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(PersistedBuilderCode copy) async {
    try {
      final box = await _box();
      await box.putAll({
        _key: copy.code,
        if (copy.revision != null) _revisionKey: '${copy.revision}',
      });
      if (copy.revision == null) await box.delete(_revisionKey);
    } catch (_) {
      // Disk full or Hive not initialised: the in-memory copy still serves.
    }
  }
}
