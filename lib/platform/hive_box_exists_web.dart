/// Web: whether a Hive box's IndexedDB database exists, closing every
/// connection it opens (see hive_box_exists.dart).
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

Future<bool> boxExists(String name) async {
  final idb = globalContext['indexedDB'] as JSObject?;
  if (idb == null) return false;
  // Hive names a box's database by the box name in lower case.
  final database = name.toLowerCase();
  if (idb.has('databases')) {
    try {
      final list = await idb
          .callMethod<JSPromise<JSArray<JSObject>>>('databases'.toJS)
          .toDart
          .timeout(const Duration(seconds: 5));
      return list.toDart.any(
          (db) => (db['name'] as JSString?)?.toDart == database);
    } catch (_) {
      // Opened below instead.
    }
  }
  final done = Completer<bool>();
  try {
    final request =
        idb.callMethod<JSObject>('open'.toJS, database.toJS);
    var created = false;
    request['onupgradeneeded'] = ((JSObject _) {
      // No such database: this open would create it. Abort, so nothing
      // is left behind.
      created = true;
      try {
        (request['transaction'] as JSObject?)
            ?.callMethod<JSAny?>('abort'.toJS);
      } catch (_) {}
    }).toJS;
    request['onsuccess'] = ((JSObject _) {
      try {
        (request['result'] as JSObject?)?.callMethod<JSAny?>('close'.toJS);
      } catch (_) {}
      if (!done.isCompleted) done.complete(!created);
    }).toJS;
    request['onerror'] = ((JSObject _) {
      if (!done.isCompleted) done.complete(false);
    }).toJS;
  } catch (_) {
    return false;
  }
  return done.future.timeout(const Duration(seconds: 5), onTimeout: () => false);
}
