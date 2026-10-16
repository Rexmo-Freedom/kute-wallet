// `setReviewDone` runs unawaited five seconds after the home transaction
// list mounts. On a phone whose 1.x build stored `reviewDone` under the
// legacy Keychain accessibility the plugin write collides with it
// (`errSecDuplicateItem`); that was the PlatformException reaching the zone
// handler after unlock. The flag is a convenience: the write is retried in
// place and never throws.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/secret_store.dart';

import '../services/support/fake_secret_store.dart';

/// Delegates to [inner] but fails every plugin `write` with [error].
class _FailingWrite implements SecretStore {
  _FailingWrite(this.inner, this.error);
  final SecretStore inner;
  final Object error;
  final writes = <String>[];

  @override
  Future<SecretRead> read({required String key}) => inner.read(key: key);
  @override
  Future<void> write({required String key, required String value}) async {
    writes.add('write:$key');
    throw error;
  }

  @override
  Future<void> writeLocalOnly({required String key, required String value}) {
    writes.add('writeLocalOnly:$key');
    return inner.writeLocalOnly(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) => inner.delete(key: key);
  @override
  Future<void> deleteLocalOnly({required String key}) =>
      inner.deleteLocalOnly(key: key);
  @override
  Future<void> deleteAllLocalOnly() => inner.deleteAllLocalOnly();
  @override
  Future<bool> containsKey({required String key}) =>
      inner.containsKey(key: key);
}

Settings _settings() => Settings(
      wallets: [WalletConfig(id: 'w1', name: 'Spending')],
      activeWalletId: 'w1',
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'ssl://example.com:50002',
      nodeType: 'electrum',
      reviewDone: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;

  setUp(() => keychain = FakeKeychain());
  tearDown(SecretStores.debugReset);

  test('a duplicate-item write is retried in place', () async {
    final store = _FailingWrite(
        keychain.local,
        PlatformException(
            code: 'Unexpected security result code', details: -25299));
    SecretStores.debugOverride(local: store, synced: keychain.synced);
    final model = SettingsModel(_settings());
    await model.setReviewDone(true);
    expect(model.state.reviewDone, isTrue);
    expect(store.writes, ['write:reviewDone', 'writeLocalOnly:reviewDone']);
    expect(keychain.peek('reviewDone'), 'true');
  });

  test('any other write failure is dropped, the flag still flips', () async {
    final store = _FailingWrite(
        keychain.local, PlatformException(code: 'x', details: -25308));
    SecretStores.debugOverride(local: store, synced: keychain.synced);
    final model = SettingsModel(_settings());
    await model.setReviewDone(true);
    expect(model.state.reviewDone, isTrue);
    expect(store.writes, ['write:reviewDone']);
    expect(keychain.mutations, isEmpty);
  });
}
