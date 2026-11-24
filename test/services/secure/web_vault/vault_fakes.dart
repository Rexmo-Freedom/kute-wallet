// Dart VM stand-ins for WebCrypto, IndexedDB and the old
// flutter_secure_storage_web localStorage layout. The crypto is real
// (pointycastle AES-GCM, PBKDF2-SHA-256, HKDF-SHA-256), so a wrong key
// fails the tag exactly as WebCrypto does.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:pointycastle/export.dart' as pc;

import 'package:kute/services/secure/web_vault/seed_vault.dart';
import 'package:kute/services/secure/web_vault/vault_router.dart';

/// An opaque key handle: tests cannot read its bytes through the vault.
class FakeKey {
  FakeKey._(this._bytes, this.kind);
  final Uint8List _bytes;
  final String kind;
}

class FakeVaultCrypto implements VaultCrypto {
  FakeVaultCrypto({int seed = 7}) : _random = Random(seed);
  final Random _random;
  int pinDerivations = 0;
  final List<int> iterationsSeen = [];

  @override
  Uint8List randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

  @override
  Future<Object> newDeviceKey() async => FakeKey._(randomBytes(32), 'device');

  @override
  Future<Object> pinKey(String pin, Uint8List salt, int iterations) async {
    pinDerivations++;
    iterationsSeen.add(iterations);
    final d = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(salt, iterations, 32));
    return FakeKey._(d.process(Uint8List.fromList(utf8.encode(pin))), 'pin');
  }

  @override
  Future<Object> newDeviceSecret() async =>
      FakeKey._(randomBytes(32), 'pbkdf2-base');

  @override
  Future<Object> devicePinKey(Object deviceSecret, String pin,
      Uint8List vaultSalt, int iterations) async {
    pinDerivations++;
    iterationsSeen.add(iterations);
    final salt = pc.SHA256Digest()
        .process(Uint8List.fromList([...vaultSalt, ...utf8.encode(pin)]));
    final d = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(salt, iterations, 32));
    return FakeKey._(d.process((deviceSecret as FakeKey)._bytes), 'pin2');
  }

  @override
  Future<Object> hkdfKey(Uint8List ikm, Uint8List salt, Uint8List info) async {
    final d = pc.HKDFKeyDerivator(pc.SHA256Digest())
      ..init(pc.HkdfParameters(ikm, 32, salt, info));
    final out = Uint8List(32);
    d.deriveKey(null, 0, out, 0);
    return FakeKey._(out, 'hkdf');
  }

  @override
  Future<Object> rawKey(Uint8List raw) async =>
      FakeKey._(Uint8List.fromList(raw), 'raw');

  pc.GCMBlockCipher _gcm(bool encrypt, Object key, Uint8List iv, Uint8List aad) =>
      pc.GCMBlockCipher(pc.AESEngine())
        ..init(encrypt,
            pc.AEADParameters(pc.KeyParameter((key as FakeKey)._bytes), 128, iv, aad));

  @override
  Future<Uint8List> seal(
          Object key, Uint8List iv, Uint8List plain, Uint8List aad) async =>
      _gcm(true, key, iv, aad).process(plain);

  @override
  Future<Uint8List> open(
      Object key, Uint8List iv, Uint8List sealed, Uint8List aad) async {
    try {
      return _gcm(false, key, iv, aad).process(sealed);
    } on pc.InvalidCipherTextException {
      throw const VaultTagError();
    } on ArgumentError {
      throw const VaultTagError();
    }
  }
}

class MemoryVaultDb implements VaultDb {
  Map<String, Object?>? meta;
  Object? deviceKey;
  Object? deviceSecret;
  final Map<String, Map<String, Object?>> entries = {};
  final Map<String, String> plain = {};

  /// Makes the next entry write throw (a storage failure mid-migration).
  int failEntryWritesAfter = -1;

  @override
  Future<Map<String, Object?>?> readMeta() async =>
      meta == null ? null : jsonDecode(jsonEncode(meta)) as Map<String, Object?>;
  @override
  Future<void> writeMeta(Map<String, Object?> m) async =>
      meta = jsonDecode(jsonEncode(m)) as Map<String, Object?>;
  @override
  Future<void> deleteMeta() async => meta = null;
  @override
  Future<Object?> readDeviceKey() async => deviceKey;
  @override
  Future<void> writeDeviceKey(Object key) async => deviceKey = key;
  @override
  Future<Object?> readDeviceSecret() async => deviceSecret;
  @override
  Future<void> writeDeviceSecret(Object secret) async => deviceSecret = secret;
  @override
  Future<Map<String, Map<String, Object?>>> readEntries() async =>
      {for (final e in entries.entries) e.key: Map.of(e.value)};
  @override
  Future<void> writeEntry(String name, Map<String, Object?> entry) async {
    if (failEntryWritesAfter == 0) throw StateError('disk full');
    if (failEntryWritesAfter > 0) failEntryWritesAfter--;
    entries[name] = Map.of(entry);
  }

  @override
  Future<void> deleteEntry(String name) async => entries.remove(name);
  @override
  Future<Map<String, String>> readPlain() async => Map.of(plain);
  @override
  Future<void> writePlain(String name, String value) async =>
      plain[name] = value;
  @override
  Future<void> deletePlain(String name) async => plain.remove(name);
  @override
  Future<void> clear() async {
    meta = null;
    deviceKey = null;
    deviceSecret = null;
    entries.clear();
    plain.clear();
  }
}

/// The old flutter_secure_storage_web layout: a fake localStorage holding
/// the raw key under `FlutterSecureStorage` and each value under
/// `FlutterSecureStorage.<key>` (values kept as given; the real plugin
/// AES-GCM-encrypts them with that raw key, which is the problem).
class FakeLegacyWeb extends FlutterSecureStoragePlatform {
  final Map<String, String> localStorage = {};
  static const prefix = 'FlutterSecureStorage';

  void seed(Map<String, String> values) {
    localStorage[prefix] = base64Encode(List.filled(32, 9));
    values.forEach((k, v) => localStorage['$prefix.$k'] = 'enc:$v');
  }

  LegacyWebStore store() => LegacyWebStore(
        platform: this,
        options: const {'publicKey': prefix},
        names: () => {
          for (final k in localStorage.keys)
            if (k.startsWith('$prefix.')) k.substring(prefix.length + 1),
        },
        rawKeyPresent: () => localStorage.containsKey(prefix),
      );

  @override
  Future<String?> read(
      {required String key, required Map<String, String> options}) async {
    final v = localStorage['$prefix.$key'];
    return v?.substring(4);
  }

  @override
  Future<void> write(
      {required String key,
      required String value,
      required Map<String, String> options}) async {
    localStorage['$prefix.$key'] = 'enc:$value';
  }

  @override
  Future<bool> containsKey(
          {required String key, required Map<String, String> options}) async =>
      localStorage.containsKey('$prefix.$key');

  @override
  Future<void> delete(
          {required String key, required Map<String, String> options}) async =>
      localStorage.remove('$prefix.$key');

  @override
  Future<Map<String, String>> readAll(
          {required Map<String, String> options}) async =>
      {
        for (final e in localStorage.entries)
          if (e.key.startsWith('$prefix.'))
            e.key.substring(prefix.length + 1): e.value.substring(4),
      };

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      localStorage.removeWhere((k, _) => k == prefix || k.startsWith('$prefix.'));
}

/// A vault with test-speed PBKDF2 (the format stores the count; the
/// default N is asserted separately).
Future<SeedVault> newVault(MemoryVaultDb db,
    {FakeVaultCrypto? crypto, int iterations = 1000}) async {
  final vault = SeedVault(
      crypto: crypto ?? FakeVaultCrypto(), db: db, iterations: iterations);
  await vault.load();
  return vault;
}
