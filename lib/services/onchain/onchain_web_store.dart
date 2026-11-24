// lib/services/onchain/onchain_web_store.dart
//
// Where a Bitcoin wallet's BDK data lives. On iOS and Android it is a
// SQLite file in the app's documents, owned by native BDK. A browser has
// no files: the web build keeps the wallet's BDK changeset (the same
// state the SQLite file holds) as JSON in a Hive box, which Hive stores
// in IndexedDB there. The database path stays the key, so the native
// rules that read it (temporary-wallet prefixes, one writer per path)
// apply unchanged.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

/// The folder wallet databases are named under: the app's documents on a
/// device; on the web a fixed prefix, since the path is only a key there.
Future<String> onchainDatabaseDirectory() async =>
    kIsWeb ? 'browser' : (await getApplicationDocumentsDirectory()).path;

/// The web build's stored BDK changesets, keyed by database path.
abstract final class OnchainWebStore {
  static const boxName = 'onchain_web_wallets';

  static Future<Box<String>> _box() => Hive.openBox<String>(boxName);

  static Future<String?> read(String dbPath) async => (await _box()).get(dbPath);

  static Future<bool> exists(String dbPath) async =>
      (await _box()).containsKey(dbPath);

  static Future<void> write(String dbPath, String changesetJson) async =>
      (await _box()).put(dbPath, changesetJson);

  static Future<void> delete(String dbPath) async =>
      (await _box()).delete(dbPath);
}
