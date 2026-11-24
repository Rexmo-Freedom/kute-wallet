/// Web: WebCrypto and IndexedDB for the seed vault, and the install that
/// puts [VaultStoragePlatform] under flutter_secure_storage. See
/// seed_vault.dart for the design and the threat note.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'package:kute/services/secure/web_vault/seed_vault.dart';
import 'package:kute/services/secure/web_vault/vault_keys.dart';
import 'package:kute/services/secure/web_vault/vault_router.dart';

/// flutter_secure_storage_web's default namespace (WebOptions.publicKey):
/// the raw key lives under it, each value under `<publicKey>.<key>`.
const String _legacyPublicKey = 'FlutterSecureStorage';

const Map<String, String> _legacyOptions = {
  'dbName': 'FlutterEncryptedStorage',
  'publicKey': _legacyPublicKey,
  'wrapKey': '',
  'wrapKeyIv': '',
  'useSessionStorage': 'false',
};

const String _dbName = 'kute_vault';
const List<String> _stores = ['meta', 'entries', 'device', 'plain'];

Future<VaultStoragePlatform?> installWebVault() async {
  final legacyPlatform = FlutterSecureStoragePlatform.instance;
  try {
    if (!_isSecureContext()) {
      throw const VaultUnavailableException('not a secure context');
    }
    final db = IdbVaultDb(await _openDb());
    final vault = SeedVault(crypto: WebVaultCrypto(), db: db);
    await vault.load();
    final legacy = LegacyWebStore(
      platform: legacyPlatform,
      options: _legacyOptions,
      names: _legacyNames,
      rawKeyPresent: () => _localStorage()?.callMethod<JSAny?>(
              'getItem'.toJS, _legacyPublicKey.toJS) !=
          null,
    );
    final router = VaultStoragePlatform(
      vault: vault,
      plain: await db.readPlain(),
      legacy: legacy,
    );
    await router.copyOrdinaryFromLegacy();
    FlutterSecureStoragePlatform.instance = router;
    if (kDebugMode) installWebStorageGuard();
    return router;
  } catch (e) {
    // Fail closed: never fall back to the localStorage layout.
    debugPrint('Web vault unavailable: ${e.runtimeType}');
    FlutterSecureStoragePlatform.instance = _FailClosedPlatform();
    return null;
  }
}

bool _isSecureContext() =>
    (globalContext['isSecureContext'] as JSBoolean?)?.toDart ?? false;

JSObject? _localStorage() {
  try {
    return globalContext['localStorage'] as JSObject?;
  } catch (_) {
    return null;
  }
}

Set<String> _legacyNames() {
  final ls = _localStorage();
  if (ls == null) return const {};
  final out = <String>{};
  final length = (ls['length'] as JSNumber).toDartInt;
  const prefix = '$_legacyPublicKey.';
  for (var i = 0; i < length; i++) {
    final key =
        (ls.callMethod<JSString?>('key'.toJS, i.toJS))?.toDart ?? '';
    if (key.startsWith(prefix)) out.add(key.substring(prefix.length));
  }
  return out;
}

/// Debug builds: any write to localStorage or sessionStorage of a known
/// secret key name or a recovery-phrase-like value throws, whoever makes
/// it.
void installWebStorageGuard() {
  final storage = globalContext['Storage'] as JSObject?;
  final proto = storage?['prototype'] as JSObject?;
  if (proto == null || proto.has('kuteGuarded')) return;
  final original = proto['setItem'] as JSFunction;
  proto['setItem'] = ((JSObject self, JSString key, JSString value) {
    final k = key.toDart;
    if (isKnownSecretKeyName(k) || looksLikeSecretValue(value.toDart)) {
      throw StateError('Secret material must never be written to web '
          'storage (key "$k").');
    }
    original.callMethod<JSAny?>('call'.toJS, self, key, value);
    // ignore: sdk_version_since
  }).toJSCaptureThis;
  proto['kuteGuarded'] = true.toJS;
}

// ── IndexedDB ───────────────────────────────────────────────────────────

Future<JSAny?> _request(JSObject request) {
  final done = Completer<JSAny?>();
  request['onsuccess'] = ((JSObject _) {
    if (!done.isCompleted) done.complete(request['result']);
  }).toJS;
  request['onerror'] = ((JSObject _) {
    if (!done.isCompleted) {
      done.completeError(const VaultUnavailableException('IndexedDB error'));
    }
  }).toJS;
  return done.future;
}

@visibleForTesting
Future<JSObject> debugOpenVaultDb() => _openDb();

Future<JSObject> _openDb() async {
  final idb = globalContext['indexedDB'] as JSObject?;
  if (idb == null) throw const VaultUnavailableException('no IndexedDB');
  final request =
      idb.callMethod<JSObject>('open'.toJS, _dbName.toJS, 1.toJS);
  request['onupgradeneeded'] = ((JSObject _) {
    final db = request['result'] as JSObject;
    final names = db['objectStoreNames'] as JSObject;
    for (final store in _stores) {
      final has =
          names.callMethod<JSBoolean>('contains'.toJS, store.toJS).toDart;
      if (!has) db.callMethod<JSAny?>('createObjectStore'.toJS, store.toJS);
    }
  }).toJS;
  final db = await _request(request).timeout(const Duration(seconds: 10));
  return db as JSObject;
}

class IdbVaultDb implements VaultDb {
  IdbVaultDb(this._db);
  final JSObject _db;

  Future<T> _tx<T>(List<String> stores, String mode,
      Future<T> Function(JSObject Function(String) store) body) async {
    final tx = _db.callMethod<JSObject>(
        'transaction'.toJS, stores.map((s) => s.toJS).toList().toJS, mode.toJS);
    final complete = Completer<void>();
    tx['oncomplete'] = ((JSObject _) {
      if (!complete.isCompleted) complete.complete();
    }).toJS;
    void fail(JSObject _) {
      if (!complete.isCompleted) {
        complete.completeError(
            const VaultUnavailableException('IndexedDB transaction failed'));
      }
    }

    tx['onerror'] = fail.toJS;
    tx['onabort'] = fail.toJS;
    final result = await body(
        (name) => tx.callMethod<JSObject>('objectStore'.toJS, name.toJS));
    await complete.future;
    return result;
  }

  Future<JSAny?> _get(String store, String key) => _tx([store], 'readonly',
      (os) => _request(os(store).callMethod<JSObject>('get'.toJS, key.toJS)));

  Future<void> _put(String store, String key, JSAny value) =>
      _tx([store], 'readwrite', (os) async {
        await _request(
            os(store).callMethod<JSObject>('put'.toJS, value, key.toJS));
      });

  Future<void> _delete(String store, String key) =>
      _tx([store], 'readwrite', (os) async {
        await _request(os(store).callMethod<JSObject>('delete'.toJS, key.toJS));
      });

  Future<Map<String, String>> _all(String store) =>
      _tx([store], 'readonly', (os) async {
        // Both requests go out before any await: a transaction stays
        // active only while it has requests in flight.
        final keysReq = _request(os(store).callMethod<JSObject>('getAllKeys'.toJS));
        final valuesReq = _request(os(store).callMethod<JSObject>('getAll'.toJS));
        final k = (await keysReq as JSArray).toDart;
        final v = (await valuesReq as JSArray).toDart;
        return {
          for (var i = 0; i < k.length && i < v.length; i++)
            (k[i] as JSString).toDart: (v[i] as JSString).toDart,
        };
      });

  @override
  Future<Map<String, Object?>?> readMeta() async {
    final raw = await _get('meta', 'vault');
    if (raw == null) return null;
    return (jsonDecode((raw as JSString).toDart) as Map).cast<String, Object?>();
  }

  @override
  Future<void> writeMeta(Map<String, Object?> meta) =>
      _put('meta', 'vault', jsonEncode(meta).toJS);

  @override
  Future<void> deleteMeta() => _delete('meta', 'vault');

  @override
  Future<Object?> readDeviceKey() async => await _get('device', 'key');

  @override
  Future<Object?> readDeviceSecret() async => await _get('device', 'secret');

  /// The PBKDF2 base CryptoKey object itself (structured clone).
  @override
  Future<void> writeDeviceSecret(Object secret) =>
      _put('device', 'secret', secret as JSAny);

  /// Stored as the CryptoKey object itself (structured clone); its bytes
  /// never pass through script.
  @override
  Future<void> writeDeviceKey(Object key) => _put('device', 'key', key as JSAny);

  @override
  Future<Map<String, Map<String, Object?>>> readEntries() async => {
        for (final e in (await _all('entries')).entries)
          e.key: (jsonDecode(e.value) as Map).cast<String, Object?>(),
      };

  @override
  Future<void> writeEntry(String name, Map<String, Object?> entry) =>
      _put('entries', name, jsonEncode(entry).toJS);

  @override
  Future<void> deleteEntry(String name) => _delete('entries', name);

  @override
  Future<Map<String, String>> readPlain() => _all('plain');

  @override
  Future<void> writePlain(String name, String value) =>
      _put('plain', name, value.toJS);

  @override
  Future<void> deletePlain(String name) => _delete('plain', name);

  @override
  Future<void> clear() => _tx(_stores, 'readwrite', (os) async {
        await Future.wait([
          for (final store in _stores)
            _request(os(store).callMethod<JSObject>('clear'.toJS)),
        ]);
      });
}

// ── WebCrypto ───────────────────────────────────────────────────────────

JSObject _obj(Map<String, JSAny?> fields) {
  final o = JSObject();
  fields.forEach((k, v) => o[k] = v);
  return o;
}

JSArray<JSString> _usages(List<String> u) => u.map((e) => e.toJS).toList().toJS;

class WebVaultCrypto implements VaultCrypto {
  JSObject get _crypto => globalContext['crypto'] as JSObject;
  JSObject get _subtle => _crypto['subtle'] as JSObject;

  Future<JSAny?> _call(String method, List<JSAny?> args) =>
      _subtle.callMethodVarArgs<JSPromise<JSAny?>>(method.toJS, args).toDart;

  JSObject get _aes => _obj({'name': 'AES-GCM'.toJS, 'length': 256.toJS});

  @override
  Uint8List randomBytes(int length) => (_crypto.callMethod<JSUint8Array>(
          'getRandomValues'.toJS, Uint8List(length).toJS))
      .toDart;

  @override
  Future<Object> newDeviceKey() async => (await _call('generateKey', [
        _aes,
        false.toJS,
        _usages(['encrypt', 'decrypt']),
      ]))!;

  @override
  Future<Object> pinKey(String pin, Uint8List salt, int iterations) async {
    final base = await _call('importKey', [
      'raw'.toJS,
      Uint8List.fromList(utf8.encode(pin)).toJS,
      'PBKDF2'.toJS,
      false.toJS,
      _usages(['deriveKey']),
    ]);
    return (await _call('deriveKey', [
      _obj({
        'name': 'PBKDF2'.toJS,
        'salt': salt.toJS,
        'iterations': iterations.toJS,
        'hash': 'SHA-256'.toJS,
      }),
      base,
      _aes,
      false.toJS,
      _usages(['encrypt', 'decrypt']),
    ]))!;
  }

  @override
  Future<Object> newDeviceSecret() async {
    final bytes = randomBytes(32);
    try {
      // PBKDF2 keys can never be extractable.
      return (await _call('importKey', [
        'raw'.toJS,
        bytes.toJS,
        'PBKDF2'.toJS,
        false.toJS,
        _usages(['deriveKey']),
      ]))!;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<Object> devicePinKey(Object deviceSecret, String pin,
      Uint8List vaultSalt, int iterations) async {
    final pinBytes = utf8.encode(pin);
    final input = Uint8List(vaultSalt.length + pinBytes.length)
      ..setAll(0, vaultSalt)
      ..setAll(vaultSalt.length, pinBytes);
    final digest = await _call('digest', ['SHA-256'.toJS, input.toJS]);
    input.fillRange(0, input.length, 0);
    return (await _call('deriveKey', [
      _obj({
        'name': 'PBKDF2'.toJS,
        'salt': digest,
        'iterations': iterations.toJS,
        'hash': 'SHA-256'.toJS,
      }),
      deviceSecret as JSAny,
      _aes,
      false.toJS,
      _usages(['encrypt', 'decrypt']),
    ]))!;
  }

  @override
  Future<Object> hkdfKey(Uint8List ikm, Uint8List salt, Uint8List info) async {
    final base = await _call('importKey', [
      'raw'.toJS,
      ikm.toJS,
      'HKDF'.toJS,
      false.toJS,
      _usages(['deriveKey']),
    ]);
    return (await _call('deriveKey', [
      _obj({
        'name': 'HKDF'.toJS,
        'hash': 'SHA-256'.toJS,
        'salt': salt.toJS,
        'info': info.toJS,
      }),
      base,
      _aes,
      false.toJS,
      _usages(['encrypt', 'decrypt']),
    ]))!;
  }

  @override
  Future<Object> rawKey(Uint8List raw) async => (await _call('importKey', [
        'raw'.toJS,
        raw.toJS,
        _obj({'name': 'AES-GCM'.toJS}),
        false.toJS,
        _usages(['encrypt', 'decrypt']),
      ]))!;

  JSObject _gcm(Uint8List iv, Uint8List aad) => _obj({
        'name': 'AES-GCM'.toJS,
        'iv': iv.toJS,
        'additionalData': aad.toJS,
        'tagLength': 128.toJS,
      });

  @override
  Future<Uint8List> seal(
      Object key, Uint8List iv, Uint8List plain, Uint8List aad) async {
    final out =
        await _call('encrypt', [_gcm(iv, aad), key as JSAny, plain.toJS]);
    return (out as JSArrayBuffer).toDart.asUint8List();
  }

  @override
  Future<Uint8List> open(
      Object key, Uint8List iv, Uint8List sealed, Uint8List aad) async {
    try {
      final out =
          await _call('decrypt', [_gcm(iv, aad), key as JSAny, sealed.toJS]);
      return (out as JSArrayBuffer).toDart.asUint8List();
    } catch (e) {
      // OperationError is WebCrypto's tag failure.
      String? name;
      try {
        name = ((e as JSObject)['name'] as JSString?)?.toDart;
      } catch (_) {}
      if (name == 'OperationError') throw const VaultTagError();
      rethrow;
    }
  }
}

/// Installed when the vault cannot start: every call fails, so nothing is
/// ever written to the old localStorage layout.
class _FailClosedPlatform extends FlutterSecureStoragePlatform {
  Never _fail() => throw const VaultUnavailableException('web vault');

  @override
  Future<bool> containsKey(
          {required String key, required Map<String, String> options}) async =>
      _fail();

  @override
  Future<void> delete(
          {required String key, required Map<String, String> options}) async =>
      _fail();

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      _fail();

  @override
  Future<String?> read(
          {required String key, required Map<String, String> options}) async =>
      _fail();

  @override
  Future<Map<String, String>> readAll(
          {required Map<String, String> options}) async =>
      _fail();

  @override
  Future<void> write(
          {required String key,
          required String value,
          required Map<String, String> options}) async =>
      _fail();
}
