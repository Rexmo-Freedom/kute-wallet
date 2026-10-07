import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';

import 'services/support/fake_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const manifestKey = 'passkey017_recovery_manifest_v1';

/// Fake Breez client: discovery (`label == null`) answers with [published];
/// a labelled sign-in derives that label. Every response names
/// [credential] unless [answerWith] overrides it.
class _Client implements PasskeyClient {
  _Client(this.published);

  final List<String> published;
  final requests = <SignInRequest>[];
  Uint8List credential = Uint8List.fromList([1, 2, 3]);
  Uint8List? answerWith;
  Completer<void>? gate;

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) async {
    requests.add(request);
    if (gate != null) await gate!.future;
    return SignInResponse(
      wallet: Wallet(
        seed: Seed.mnemonic(mnemonic: phrase, passphrase: null),
        label: request.label ?? 'Default',
      ),
      labels: request.label == null ? published : const [],
      credential: PasskeyCredential(credentialId: answerWith ?? credential),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

String seedCacheKey(String label, String credentialHex) =>
    'passkey017_seed_v1__${sha256.convert(utf8.encode('$label|$credentialHex'))}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;
  late Directory hiveDir;

  setUp(() async {
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    PasskeyPrfService.clearMemory();
    hiveDir = await Directory.systemTemp.createTemp('passkey_discovery');
    Hive.init(hiveDir.path);
  });

  tearDown(() async {
    PasskeyService.debugSetClient(null);
    PasskeyPrfService.clearMemory();
    SecretStores.debugReset();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  group('discovery', () {
    test('one unlabelled sign-in lists labels and names the credential',
        () async {
      final client = _Client(['A · 1', 'B · 2']);
      PasskeyService.debugSetClient(client);

      final found = await PasskeyService.discoverWallets();

      expect(found.labels, ['A · 1', 'B · 2']);
      expect(found.credentialId, [1, 2, 3]);
      expect(client.requests, hasLength(1));
      expect(client.requests.single.label, isNull);
      expect(client.requests.single.allowCredentials, isNull);
      // Nothing is persisted until the chosen wallet resolves, and the
      // synced store is neither read for labels nor written.
      expect(keychain.keys(), isEmpty);
      expect(keychain.keys(options: FakeStoreOptions.synced), isEmpty);
      expect(keychain.mutations, isEmpty);
    });

    test('a device with a pin discovers through that credential only',
        () async {
      keychain.seed('passkey017_credential_id', '010203');
      final client = _Client(['A · 1']);
      PasskeyService.debugSetClient(client);

      await PasskeyService.discoverWallets();

      expect(client.requests.single.allowCredentials, [
        Uint8List.fromList([1, 2, 3])
      ]);
    });

    test('a different credential than the stored pin is refused', () async {
      keychain.seed('passkey017_credential_id', 'aabb');
      final client = _Client(['A · 1']);
      PasskeyService.debugSetClient(client);

      await expectLater(PasskeyService.discoverWallets(), throwsStateError);
      expect(keychain.peek('passkey017_credential_id'), 'aabb');
    });

    test('concurrent callers share one ceremony', () async {
      final client = _Client(['A · 1'])..gate = Completer<void>();
      PasskeyService.debugSetClient(client);

      final first = PasskeyService.discoverWallets();
      final second = PasskeyService.discoverWallets();
      await Future<void>.delayed(Duration.zero);
      client.gate!.complete();

      expect(identical(await first, await second), isTrue);
      expect(client.requests, hasLength(1));
    });
  });

  group('restoring a discovered wallet', () {
    test('the confirmation is pinned to the discovered credential', () async {
      final client = _Client(['A · 1', 'B · 2']);
      PasskeyService.debugSetClient(client);
      final found = await PasskeyService.discoverWallets();

      final wallet = await PasskeyService.getWallet(
          label: 'B · 2', legacy: false, credentialId: found.credentialId);

      expect(wallet.label, 'B · 2');
      expect(client.requests, hasLength(2));
      expect(client.requests.last.label, 'B · 2');
      expect(client.requests.last.allowCredentials, [
        Uint8List.fromList([1, 2, 3])
      ]);
      // The pin and the device-local seed are written only now.
      expect(keychain.peek('passkey017_credential_id'), '010203');
      expect(keychain.peek(seedCacheKey('B · 2', '010203')), isNotNull);
      expect(keychain.keys(options: FakeStoreOptions.synced), isEmpty);
    });

    test('another passkey answering the confirmation is refused', () async {
      final client = _Client(['A · 1', 'B · 2']);
      PasskeyService.debugSetClient(client);
      final found = await PasskeyService.discoverWallets();

      client.answerWith = Uint8List.fromList([9, 9]);
      await expectLater(
          PasskeyService.getWallet(
              label: 'B · 2', legacy: false, credentialId: found.credentialId),
          throwsStateError);
      expect(keychain.keys(), isEmpty);
    });

    test('a discovered credential that differs from the pin never prompts',
        () async {
      keychain.seed('passkey017_credential_id', 'aabb');
      final client = _Client(['A · 1']);
      PasskeyService.debugSetClient(client);

      await expectLater(
          PasskeyService.getWallet(
              label: 'A · 1',
              legacy: false,
              credentialId: Uint8List.fromList([1, 2, 3])),
          throwsStateError);
      expect(client.requests, isEmpty);
      expect(keychain.peek('passkey017_credential_id'), 'aabb');
    });

    test('the label discovery already derived needs no second ceremony',
        () async {
      final client = _Client(['Default']);
      PasskeyService.debugSetClient(client);
      final found = await PasskeyService.discoverWallets();

      final wallet = await PasskeyService.getWallet(
          label: 'Default', legacy: false, credentialId: found.credentialId);

      expect(wallet.label, 'Default');
      expect(client.requests, hasLength(1));
      expect(keychain.peek('passkey017_credential_id'), '010203');
      expect(keychain.peek(seedCacheKey('Default', '010203')), isNotNull);
    });
  });

  group('retired recovery manifest', () {
    test('discovery and restore leave the synced store untouched', () async {
      keychain.seedSynced(manifestKey, jsonEncode({'Old · 1': 'breez-0.17'}));
      final client = _Client(const []);
      PasskeyService.debugSetClient(client);

      final found = await PasskeyService.discoverWallets();
      expect(found.labels, isEmpty);
      await PasskeyService.getWallet(
          label: 'New · 2', legacy: false, credentialId: found.credentialId);

      expect(keychain.peekSynced(manifestKey),
          jsonEncode({'Old · 1': 'breez-0.17'}));
      expect(keychain.mutations.where((m) => m.store == 'synced'), isEmpty);
    });

    test('the one-time cleanup deletes only the manifest, once', () async {
      keychain.seedSynced(manifestKey, '{"Default":"0.15.1"}');
      keychain.seedSynced('v2:wallet:w1.mnemonic', phrase);
      keychain.seedSynced('prf_seed_v1__x', 'bb' * 32);

      await PasskeyService.retireRecoveryManifest();

      expect(keychain.peekSynced(manifestKey), isNull);
      expect(keychain.keys(options: FakeStoreOptions.synced),
          {'v2:wallet:w1.mnemonic', 'prf_seed_v1__x'});
      expect(keychain.mutations,
          const [FakeMutation('synced', 'delete', manifestKey)]);

      // An old build on another device writes it again: this install has
      // already retired it and leaves the synced store alone from now on.
      keychain.seedSynced(manifestKey, '{"Default":"0.15.1"}');
      await PasskeyService.retireRecoveryManifest();
      expect(keychain.mutations, hasLength(1));
    });

    test('a failed cleanup is retried on the next start', () async {
      keychain.seedSynced(manifestKey, '{}');
      keychain.failDelete('synced', StateError('locked'), key: manifestKey);

      await PasskeyService.retireRecoveryManifest();
      expect(keychain.peekSynced(manifestKey), '{}');

      keychain.clearFailures();
      await PasskeyService.retireRecoveryManifest();
      expect(keychain.peekSynced(manifestKey), isNull);
    });
  });
}
