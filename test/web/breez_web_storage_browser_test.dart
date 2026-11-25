// The SDK-database cleanup of a removed wallet, in a real browser:
//   flutter test --platform chrome test/web/breez_web_storage_browser_test.dart
@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/platform/breez_web_storage.dart';

JSObject get _idb => globalContext['indexedDB'] as JSObject;

/// Creates (and closes) an empty database named [name].
Future<void> _create(String name) {
  final done = Completer<void>();
  final request = _idb.callMethod<JSObject>('open'.toJS, name.toJS, 1.toJS);
  request['onsuccess'] = ((JSObject _) {
    (request['result'] as JSObject).callMethod<JSAny?>('close'.toJS);
    done.complete();
  }).toJS;
  request['onerror'] = ((JSObject _) => done.completeError('open')).toJS;
  return done.future;
}

Future<Set<String>> _names() async {
  final list = await _idb
      .callMethod<JSPromise<JSArray<JSObject>>>('databases'.toJS)
      .toDart;
  return {
    for (final db in list.toDart) (db['name'] as JSString).toDart,
  };
}

void main() {
  // The layout the SDK's wasm build uses: `<storageDir>/<network>/<hash>`
  // and the same with `-tree`.
  const removed = [
    'breez_w1/mainnet/0a1b2c3d',
    'breez_w1/mainnet/0a1b2c3d-tree',
  ];
  const kept = [
    'breez_w10/mainnet/0a1b2c3d',
    'breez_w10/mainnet/0a1b2c3d-tree',
    'breez_w2/mainnet/99887766',
    'breez_prefs',
    'kute_vault_test_other',
  ];

  setUp(() async {
    for (final name in [...removed, ...kept]) {
      await _create(name);
    }
  });

  tearDown(() async {
    for (final name in kept) {
      _idb.callMethod<JSAny?>('deleteDatabase'.toJS, name.toJS);
    }
  });

  test('deletes only the removed wallet\'s SDK databases', () async {
    expect(await deleteBreezWebStorage('breez_w1'), removed.length);
    final names = await _names();
    for (final name in removed) {
      expect(names, isNot(contains(name)));
    }
    for (final name in kept) {
      expect(names, contains(name));
    }
  });
}
