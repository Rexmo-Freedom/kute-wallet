/// Web: deletes the SDK's IndexedDB databases for one storage directory
/// (see breez_web_storage.dart).
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'breez_web_storage.dart' show isBreezDatabaseFor;

/// The names the SDK opens for a storage directory, for a browser without
/// `indexedDB.databases()`.
List<String> _knownNames(String storageDir) =>
    [storageDir, '$storageDir-tree'];

Future<List<String>?> _listDatabases(JSObject idb) async {
  if (!idb.has('databases')) return null;
  try {
    final list = await idb
        .callMethod<JSPromise<JSArray<JSObject>>>('databases'.toJS)
        .toDart
        .timeout(const Duration(seconds: 5));
    return [
      for (final db in list.toDart)
        if (db['name'] case final JSString name) name.toDart,
    ];
  } catch (_) {
    return null;
  }
}

/// Deletes one database. A delete that is blocked (a connection still
/// open) completes once that connection closes; it is given a few
/// seconds, then left to finish on its own.
Future<bool> _delete(JSObject idb, String name) {
  final done = Completer<bool>();
  try {
    final request =
        idb.callMethod<JSObject>('deleteDatabase'.toJS, name.toJS);
    request['onsuccess'] = ((JSObject _) {
      if (!done.isCompleted) done.complete(true);
    }).toJS;
    request['onerror'] = ((JSObject _) {
      if (!done.isCompleted) done.complete(false);
    }).toJS;
  } catch (_) {
    return Future.value(false);
  }
  return done.future
      .timeout(const Duration(seconds: 10), onTimeout: () => false);
}

Future<int> deleteBreezWebStorage(String storageDir) async {
  if (storageDir.isEmpty) return 0;
  final idb = globalContext['indexedDB'] as JSObject?;
  if (idb == null) return 0;
  final listed = await _listDatabases(idb);
  final names = listed == null
      ? _knownNames(storageDir)
      : [
          for (final name in listed)
            if (isBreezDatabaseFor(name, storageDir)) name,
        ];
  var deleted = 0;
  for (final name in names) {
    if (await _delete(idb, name)) deleted++;
  }
  return deleted;
}
