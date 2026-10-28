// The passkey label publish is off the creation path: it is flagged
// pending first, runs in the background with a per-attempt timeout, and a
// label that did not land stays pending until a later ceremony (which
// primes the label-store identity) retries it.

import 'dart:async';
import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/tracking_service.dart';

import 'support/fake_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

/// Fake label store: every `store` call either waits on [gate], fails
/// [failures] times, or succeeds.
class _Labels implements PasskeyLabels {
  final stored = <String>[];
  int failures = 0;
  Completer<void>? gate;

  /// Labels whose every publish fails.
  final failFor = <String>{};

  @override
  Future<void> store({required String label}) async {
    if (gate != null) await gate!.future;
    if (failFor.contains(label)) throw Exception('relay down');
    if (failures > 0) {
      failures--;
      throw Exception('relay down');
    }
    stored.add(label);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Client implements PasskeyClient {
  _Client(this.labelsFake);

  final _Labels labelsFake;
  Uint8List credential = Uint8List.fromList([1, 2, 3]);

  @override
  PasskeyLabels labels() => labelsFake;

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) async {
    return SignInResponse(
      wallet: Wallet(
        seed: Seed.mnemonic(mnemonic: phrase, passphrase: null),
        label: request.label ?? 'Default',
      ),
      labels: const [],
      credential: PasskeyCredential(credentialId: credential),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;
  late Directory hiveDir;
  late _Labels labels;
  late _Client client;
  late List<(String, Map<String, Object>?)> events;

  setUp(() async {
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    PasskeyPrfService.clearMemory();
    hiveDir = await Directory.systemTemp.createTemp('passkey_label');
    Hive.init(hiveDir.path);
    labels = _Labels();
    client = _Client(labels);
    PasskeyService.debugSetClient(client);
    PasskeyService.debugResetPendingLabels();
    PasskeyService.labelPublishBackoff = Duration.zero;
    PasskeyService.labelPublishAttemptTimeout = const Duration(seconds: 20);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() async {
    TrackingService.debugTrackObserver = null;
    PasskeyService.debugSetClient(null);
    PasskeyService.debugResetPendingLabels();
    PasskeyPrfService.clearMemory();
    SecretStores.debugReset();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test('the label is flagged pending before the publish lands', () async {
    labels.gate = Completer<void>();
    final publish =
        PasskeyService.publishLabelInBackground('A · 1', trigger: 'create');
    // Let the flag write land (real Hive I/O); the store call is still
    // parked on the gate.
    await _until(() async => PasskeyService.hasPendingLabel('A · 1'));
    expect(PasskeyService.pendingLabels.value, {'A · 1'});
    expect(labels.stored, isEmpty);

    labels.gate!.complete();
    expect(await publish, isTrue);
    expect(labels.stored, ['A · 1']);
    expect(await PasskeyService.hasPendingLabel('A · 1'), isFalse);
    expect(PasskeyService.pendingLabels.value, isEmpty);
    final published =
        events.where((e) => e.$1 == 'passkey_label_published').toList();
    expect(published, hasLength(1));
    expect(published.single.$2, containsPair('result', 'landed'));
    expect(published.single.$2, containsPair('attempts', 1));
    expect(published.single.$2, containsPair('trigger', 'create'));
    // Never the label itself.
    expect(published.single.$2!.values, isNot(contains('A · 1')));
  });

  test('a publish that keeps failing leaves the label pending', () async {
    labels.failures = 99;
    expect(
        await PasskeyService.publishLabelInBackground('A · 1',
            trigger: 'create'),
        isFalse);
    expect(await PasskeyService.hasPendingLabel('A · 1'), isTrue);
    final published =
        events.where((e) => e.$1 == 'passkey_label_published').single;
    expect(published.$2, containsPair('result', 'failed'));
    expect(published.$2, containsPair('attempts', 3));
    // The flag survives a restart of the in-memory view.
    PasskeyService.debugResetPendingLabels();
    await PasskeyService.loadPendingLabels();
    expect(PasskeyService.pendingLabels.value, {'A · 1'});
  });

  test('each attempt is capped by the per-attempt timeout', () async {
    PasskeyService.labelPublishAttemptTimeout =
        const Duration(milliseconds: 20);
    // The first attempt never answers; the retry does.
    final hang = Completer<void>();
    labels.gate = hang;
    final publish = PasskeyService.storeLabel('A · 1');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    labels.gate = null;
    expect(await publish, isTrue);
    expect(labels.stored, ['A · 1']);
  });

  test('a later ceremony retries the pending label, same credential only',
      () async {
    labels.failures = 99;
    await PasskeyService.publishLabelInBackground('A · 1', trigger: 'create');
    expect(await PasskeyService.hasPendingLabel('A · 1'), isTrue);
    // A label created under another credential must not be published by
    // this one's identity.
    await PasskeyService.markLabelPending('B · 2', credentialHex: 'ffff');
    labels.failures = 0;

    // No ceremony in this process yet: nothing may publish (it would cost
    // a biometric prompt to derive the identity).
    await PasskeyService.retryPendingLabels();
    await pumpEventQueue();
    expect(labels.stored, isEmpty);

    // A sign-in ceremony primes the identity for credential 010203.
    await PasskeyService.getWallet(label: 'A · 1', legacy: false);
    await _until(() async => labels.stored.isNotEmpty);
    await _until(() async => !await PasskeyService.hasPendingLabel('A · 1'));
    // The retry event is tracked just after the pending entry clears; under
    // a loaded test run it can trail by a few turns of the event loop.
    await _until(() async => events.any((e) =>
        e.$1 == 'passkey_label_published' && e.$2?['trigger'] == 'retry'));
    expect(labels.stored, ['A · 1']);
    expect(await PasskeyService.hasPendingLabel('A · 1'), isFalse);
    expect(await PasskeyService.hasPendingLabel('B · 2'), isTrue);
    final retried = events
        .where((e) =>
            e.$1 == 'passkey_label_published' && e.$2?['trigger'] == 'retry')
        .toList();
    expect(retried, hasLength(1));
    expect(retried.single.$2, containsPair('result', 'landed'));
  });

  test('concurrent marks and clears never lose a pending label', () async {
    await PasskeyService.markLabelPending('A · 1', credentialHex: '010203');
    // A retry's clear(A) racing a create's mark(C): each read-modify-writes
    // the whole map, so unserialised the later write drops the other label.
    await Future.wait([
      PasskeyService.clearLabelPending('A · 1'),
      PasskeyService.markLabelPending('C · 3', credentialHex: '010203'),
    ]);
    expect(await PasskeyService.hasPendingLabel('A · 1'), isFalse);
    expect(await PasskeyService.hasPendingLabel('C · 3'), isTrue);

    // Many at once, interleaved.
    await Future.wait([
      for (var i = 0; i < 20; i++)
        PasskeyService.markLabelPending('M · $i', credentialHex: '010203'),
      PasskeyService.clearLabelPending('C · 3'),
      for (var i = 0; i < 20; i += 2)
        PasskeyService.clearLabelPending('M · $i'),
    ]);
    final expected = {for (var i = 1; i < 20; i += 2) 'M · $i'};
    for (var i = 0; i < 20; i++) {
      expect(await PasskeyService.hasPendingLabel('M · $i'),
          expected.contains('M · $i'),
          reason: 'M · $i');
    }
    expect(await PasskeyService.hasPendingLabel('C · 3'), isFalse);
    PasskeyService.debugResetPendingLabels();
    await PasskeyService.loadPendingLabels();
    expect(PasskeyService.pendingLabels.value, expected);
  });

  test('a retry clearing one label never drops a label created meanwhile',
      () async {
    // C's publish keeps failing, so C must stay pending for a later retry.
    labels.failFor.add('C · 3');
    await PasskeyService.markLabelPending('A · 1', credentialHex: '010203');
    // The sign-in ceremony primes the identity and fires the retry of A in
    // the background; the create flow publishes C right after.
    await PasskeyService.getWallet(label: 'C · 3', legacy: false);
    final created =
        PasskeyService.publishLabelInBackground('C · 3', trigger: 'create');
    await _until(() async => labels.stored.contains('A · 1'));
    expect(await created, isFalse);
    await _until(() async => !await PasskeyService.hasPendingLabel('A · 1'));
    expect(await PasskeyService.hasPendingLabel('C · 3'), isTrue);
    PasskeyService.debugResetPendingLabels();
    await PasskeyService.loadPendingLabels();
    expect(PasskeyService.pendingLabels.value, {'C · 3'});
  });

  test('the create flow asks for immediately available credentials only',
      () async {
    final requests = <SignInRequest>[];
    final recording = _RecordingClient(labels, requests);
    PasskeyService.debugSetClient(recording);
    await PasskeyService.getWallet(
        label: 'A · 1', legacy: false, preferImmediatelyAvailable: true);
    expect(requests.single.preferImmediatelyAvailableCredentials, isTrue);
    // Other call sites keep the SDK default.
    PasskeyService.clearSession();
    await PasskeyService.getWallet(label: 'B · 2', legacy: false);
    expect(requests.last.preferImmediatelyAvailableCredentials, isNull);
  });
}

/// Poll [condition] (real storage I/O completes on its own schedule) for
/// up to two seconds.
Future<void> _until(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition never held');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _RecordingClient extends _Client {
  _RecordingClient(super.labelsFake, this.requests);

  final List<SignInRequest> requests;

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) {
    requests.add(request);
    return super.signIn(request: request);
  }
}
