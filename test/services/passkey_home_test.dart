// Two passkey homes: the marker → RP mapping (fail closed), the Breez home's
// unchanged SDK arguments and storage keys, and the isolation of every
// per-RP cache and stored key between the Breez and the Kute home.

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

import 'support/fake_secret_store.dart';

/// A home's client: every request is logged with the home's name, and the
/// derived seed is the home's own byte, so a seed served across homes
/// shows.
class _Client implements PasskeyClient {
  _Client.logged(this.name, this.byte, this.credential, this.log);

  final String name;
  final int byte;
  final Uint8List credential;
  final List<String> log;
  final signIns = <SignInRequest>[];
  final registers = <RegisterRequest>[];
  List<String> published = const [];

  Wallet _wallet(String? label) => Wallet(
      seed: Seed.entropy(Uint8List.fromList(List.filled(16, byte))),
      label: label ?? 'Default');

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) async {
    log.add('$name:signIn:${request.label}');
    signIns.add(request);
    return SignInResponse(
      wallet: _wallet(request.label),
      labels: published,
      credential: PasskeyCredential(credentialId: credential),
    );
  }

  @override
  Future<RegisterResponse> register({required RegisterRequest request}) async {
    log.add('$name:register:${request.label}');
    registers.add(request);
    return RegisterResponse(
      wallet: _wallet(request.label),
      credential: PasskeyCredential(credentialId: credential),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('marker → home mapping', () {
    test('the three known markers route to their home', () {
      expect(PasskeyHomes.routeFor(null), PasskeyRoute.legacy);
      expect(PasskeyHomes.routeFor('breez-0.17'), PasskeyRoute.breez);
      expect(PasskeyHomes.routeFor('kute-1'), PasskeyRoute.kute);
      expect(PasskeyHomes.homeForMarker('breez-0.17'), PasskeyHome.breez);
      expect(PasskeyHomes.homeForMarker('kute-1'), PasskeyHome.kute);
      expect(PasskeyHomes.rpIdFor(PasskeyHome.breez), 'keys.breez.technology');
      expect(PasskeyHomes.rpIdFor(PasskeyHome.kute), 'kutewallet.com');
      expect(PasskeyHomes.markerFor(PasskeyHome.breez), 'breez-0.17');
      expect(PasskeyHomes.markerFor(PasskeyHome.kute), 'kute-1');
      // The persisted literals never change.
      expect(PasskeyService.vintageBreez017, 'breez-0.17');
      expect(PasskeyService.vintageKute1, 'kute-1');
    });

    test('an unknown marker fails closed, never a default RP', () {
      for (final marker in ['', 'breez-0.18', 'kute-2', 'KUTE-1', 'kute']) {
        expect(() => PasskeyHomes.routeFor(marker),
            throwsA(isA<UnknownPasskeyProvider>()));
        expect(() => PasskeyHomes.homeForMarker(marker),
            throwsA(isA<UnknownPasskeyProvider>()));
        expect(() => PasskeyService.forMarker(marker),
            throwsA(isA<UnknownPasskeyProvider>()));
      }
    });

    test('a legacy (null) marker has no SDK home', () {
      expect(() => PasskeyHomes.homeForMarker(null), throwsArgumentError);
      expect(() => PasskeyService.forMarker(null), throwsArgumentError);
    });

    test('the web offers Kute passkeys only on kutewallet.com and below', () {
      expect(PasskeyHomes.hostIsKute('kutewallet.com'), isTrue);
      expect(PasskeyHomes.hostIsKute('app.kutewallet.com'), isTrue);
      expect(PasskeyHomes.hostIsKute('APP.KuteWallet.com'), isTrue);
      expect(PasskeyHomes.hostIsKute('localhost'), isFalse);
      expect(PasskeyHomes.hostIsKute('127.0.0.1'), isFalse);
      expect(PasskeyHomes.hostIsKute('evilkutewallet.com'), isFalse);
      expect(PasskeyHomes.hostIsKute('kutewallet.com.evil.com'), isFalse);
      expect(PasskeyHomes.hostIsKute('keys.breez.technology'), isFalse);
      // Never on native.
      expect(PasskeyHomes.webPageOnKuteHome, isFalse);
    });

    test('restore asks Breez then Kute on phones, Kute alone on the web', () {
      expect(PasskeyHomes.restoreOrder(web: false),
          [PasskeyHome.breez, PasskeyHome.kute]);
      expect(PasskeyHomes.restoreOrder(web: true), [PasskeyHome.kute]);
    });
  });

  group('the Breez home sends what it always sent', () {
    late List<MethodCall> calls;
    const channel = MethodChannel('breez_sdk_spark_passkey');

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'createPasskey') {
          return {
            'credentialId': base64Encode([1, 2, 3])
          };
        }
        return {
          'seeds': [base64Encode(List.filled(32, 0))],
          'credentialId': base64Encode([1, 2, 3]),
        };
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    PasskeyProvider providerFor(PasskeyConfig? config) => PasskeyProvider(
        config?.providerOptions ?? const PasskeyProviderOptions());

    test('Breez client configs are the ones built before Kute had a home', () {
      // The cached client: the SDK's zero-config constructor (no config).
      expect(PasskeyService.breez.clientConfig(), isNull);
      expect(PasskeyService.breez.clientConfig(userDisplayName: '  '), isNull);
      // The register client with the user's name: names only, no RP.
      expect(
          PasskeyService.breez.clientConfig(userDisplayName: ' Daily '),
          const PasskeyConfig(
            providerOptions: PasskeyProviderOptions(
                userName: 'Daily', userDisplayName: 'Daily'),
          ));
    });

    test('Breez ceremonies reach the platform on keys.breez.technology',
        () async {
      await providerFor(PasskeyService.breez.clientConfig()).deriveSeeds(
          const DeriveSeedsRequest(salts: ['L'], allowCredentials: []));
      await providerFor(
              PasskeyService.breez.clientConfig(userDisplayName: 'Daily'))
          .createPasskey(const [], const ['L']);
      final derive = calls[0].arguments as Map;
      expect(derive['rpId'], 'keys.breez.technology');
      expect(derive['rpName'], 'Breez');
      expect(derive['userName'], 'Breez');
      expect(
          derive.containsKey('preferImmediatelyAvailableCredentials'), isFalse);
      final create = calls[1].arguments as Map;
      expect(create['rpId'], 'keys.breez.technology');
      expect(create['rpName'], 'Breez');
      expect(create['userName'], 'Daily');
      expect(create['userDisplayName'], 'Daily');
    });

    test('Kute ceremonies reach the platform on kutewallet.com as "Kute"',
        () async {
      await providerFor(PasskeyService.kute.clientConfig()).deriveSeeds(
          const DeriveSeedsRequest(
              salts: ['L'],
              allowCredentials: [],
              preferImmediatelyAvailableCredentials: true));
      await providerFor(
              PasskeyService.kute.clientConfig(userDisplayName: 'Daily'))
          .createPasskey(const [], const ['L']);
      final derive = calls[0].arguments as Map;
      expect(derive['rpId'], 'kutewallet.com');
      expect(derive['rpName'], 'Kute');
      expect(derive['preferImmediatelyAvailableCredentials'], isTrue);
      final create = calls[1].arguments as Map;
      expect(create['rpId'], 'kutewallet.com');
      expect(create['rpName'], 'Kute');
      expect(create['userName'], 'Daily');
    });

    test('Breez storage keys are the historical ones; Kute has its own', () {
      final cred = Uint8List.fromList([1, 2, 3]);
      expect(PasskeyService.breez.credentialIdKey, 'passkey017_credential_id');
      expect(PasskeyService.breez.pendingLabelsKey, 'passkey_pending_labels');
      expect(PasskeyService.breez.seedCacheKey('L · 1', cred),
          'passkey017_seed_v1__${sha256.convert(utf8.encode('L · 1|010203'))}');
      expect(
          PasskeyService.kute.credentialIdKey, 'passkey_kute1_credential_id');
      expect(PasskeyService.kute.pendingLabelsKey,
          'passkey_kute1_pending_labels'); // gitleaks:allow
      expect(PasskeyService.kute.seedCacheKey('L · 1', cred),
          startsWith('passkey_kute1_seed_v1__'));
      expect(PasskeyService.kute.seedCacheKey('L · 1', cred),
          isNot(PasskeyService.breez.seedCacheKey('L · 1', cred)));
    });
  });

  group('per-home isolation', () {
    late FakeKeychain keychain;
    late Directory hiveDir;
    late List<String> log;
    late _Client breez;
    late _Client kute;
    final breezCred = Uint8List.fromList([1, 2, 3]);
    final kuteCred = Uint8List.fromList([9, 8, 7]);

    setUp(() async {
      keychain = FakeKeychain();
      SecretStores.debugOverride(
          local: keychain.local, synced: keychain.synced);
      PasskeyPrfService.clearMemory();
      hiveDir = await Directory.systemTemp.createTemp('passkey_home');
      Hive.init(hiveDir.path);
      await Hive.openBox('settings');
      log = [];
      breez = _Client.logged('breez', 1, breezCred, log);
      kute = _Client.logged('kute', 2, kuteCred, log);
      PasskeyService.debugSetClient(breez);
      PasskeyService.debugSetHomeClient(PasskeyHome.kute, kute);
      PasskeyService.debugResetPendingLabels();
    });

    tearDown(() async {
      PasskeyService.debugSetClient(null);
      PasskeyService.debugSetHomeClient(PasskeyHome.kute, null);
      PasskeyService.debugResetPendingLabels();
      PasskeyPrfService.clearMemory();
      SecretStores.debugReset();
      await Hive.close();
      await hiveDir.delete(recursive: true);
    });

    Seed seedOf(int byte) =>
        Seed.entropy(Uint8List.fromList(List.filled(16, byte)));

    test('seedFor routes each marker to its own home only', () async {
      final b = await PasskeyService.seedFor(
          passkeyLabel: 'B · 1', provider: 'breez-0.17');
      final k = await PasskeyService.seedFor(
          passkeyLabel: 'K · 2', provider: 'kute-1');
      expect(b, seedOf(1));
      expect(k, seedOf(2));
      expect(log, ['breez:signIn:B · 1', 'kute:signIn:K · 2']);
    });

    test('an unknown marker derives nothing on any home', () async {
      await expectLater(
          PasskeyService.seedFor(passkeyLabel: 'X · 1', provider: 'breez-9'),
          throwsA(isA<UnknownPasskeyProvider>()));
      expect(
          await PasskeyService.getMnemonicFor(
              label: 'X · 1', provider: 'breez-9'),
          isNull);
      expect(() => PasskeyService.forgetWalletFor('X · 1', provider: 'x'),
          throwsA(isA<UnknownPasskeyProvider>()));
      expect(log, isEmpty);
      expect(keychain.keys(), isEmpty);
    });

    test('a Kute wallet never falls back to the cached label', () async {
      await Hive.box('settings').put('passkey_cached_label', 'B · 1');
      await expectLater(
          PasskeyService.seedFor(passkeyLabel: null, provider: 'kute-1'),
          throwsStateError);
      expect(log, isEmpty);
    });

    test('the same label on both homes derives on each home separately',
        () async {
      final b =
          await PasskeyService.getWallet(label: 'Same · 1', legacy: false);
      final k = await PasskeyService.kute.getWallet(label: 'Same · 1');
      expect(b.seed, seedOf(1));
      expect(k.seed, seedOf(2));
      // The Breez session cache never answered the Kute call.
      expect(log, ['breez:signIn:Same · 1', 'kute:signIn:Same · 1']);
    });

    test('pins and seed caches land under each home\'s own keys', () async {
      await PasskeyService.getWallet(label: 'B · 1', legacy: false);
      await PasskeyService.kute.getWallet(label: 'K · 2');
      expect(keychain.peek('passkey017_credential_id'), _hex(breezCred));
      expect(keychain.peek('passkey_kute1_credential_id'), _hex(kuteCred));
      expect(
          keychain.peek(PasskeyService.breez.seedCacheKey('B · 1', breezCred)),
          isNotNull);
      expect(keychain.peek(PasskeyService.kute.seedCacheKey('K · 2', kuteCred)),
          isNotNull);
      // Nothing of one home under the other's keys.
      expect(
          keychain.peek(PasskeyService.breez.seedCacheKey('K · 2', kuteCred)),
          isNull);
      expect(
          keychain.peek(PasskeyService.breez.seedCacheKey('K · 2', breezCred)),
          isNull);
      expect(
          keychain.peek(PasskeyService.kute.seedCacheKey('B · 1', breezCred)),
          isNull);
      expect(keychain.keys().where((k) => k.contains('kute1')).length, 2);
    });

    test('a Breez cached seed is never served to a Kute wallet', () async {
      // A warm device: the Breez home has a pin and a cached seed for L.
      keychain.seed('passkey017_credential_id', _hex(breezCred));
      keychain.seed(
          PasskeyService.breez.seedCacheKey('L · 1', breezCred),
          jsonEncode({
            'label': 'L · 1',
            'seed': jsonEncode({'t': 'e', 'h': '01' * 16}),
          }));
      final b = await PasskeyService.getWallet(label: 'L · 1', legacy: false);
      expect(b.seed, seedOf(1));
      expect(log, isEmpty, reason: 'the Breez seed came from its cache');
      final k = await PasskeyService.kute.getWallet(label: 'L · 1');
      expect(k.seed, seedOf(2));
      expect(log, ['kute:signIn:L · 1']);
      // Kute's sign-in was not pinned to the Breez credential.
      expect(kute.signIns.single.allowCredentials, isNull);
    });

    test('a Kute pin never pins a Breez sign-in, and the reverse', () async {
      keychain.seed('passkey_kute1_credential_id', _hex(kuteCred));
      await PasskeyService.getWallet(label: 'B · 1', legacy: false);
      expect(breez.signIns.single.allowCredentials, isNull);
      keychain.seed('passkey017_credential_id', _hex(breezCred));
      await PasskeyService.kute.getWallet(label: 'K · 9');
      expect(kute.signIns.single.allowCredentials, [kuteCred]);
    });

    test('Kute creation excludes only Kute credentials', () async {
      keychain.seed('passkey017_credential_id', _hex(breezCred));
      keychain.seed('passkey_kute1_credential_id', _hex(kuteCred));
      await PasskeyService.kute.createWallet(label: 'K · 3');
      expect(kute.registers.single.excludeCredentials, [kuteCred]);
      expect(breez.registers, isEmpty);
      // The Breez pin is untouched by a Kute mint.
      expect(keychain.peek('passkey017_credential_id'), _hex(breezCred));
    });

    test('known credentials are per home', () async {
      expect(await PasskeyService.kute.hasKnownCredential(), isFalse);
      keychain.seed('passkey017_credential_id', _hex(breezCred));
      expect(await PasskeyService.hasKnownCredential(), isTrue);
      expect(await PasskeyService.kute.hasKnownCredential(), isFalse);
      keychain.seed('passkey_kute1_credential_id', _hex(kuteCred));
      expect(await PasskeyService.kute.hasKnownCredential(), isTrue);
    });

    test('pending labels are kept per home', () async {
      await PasskeyService.kute.markLabelPending('K · 2');
      expect(await PasskeyService.kute.hasPendingLabel('K · 2'), isTrue);
      expect(await PasskeyService.hasPendingLabel('K · 2'), isFalse);
      expect(Hive.box('settings').get('passkey_pending_labels'), isNull);
      expect(Hive.box('settings').get('passkey_kute1_pending_labels'),
          {'K · 2': ''});
      await PasskeyService.markLabelPending('B · 1');
      expect(PasskeyService.pendingLabelsNow, {'B · 1'});
      expect(PasskeyService.kute.pendingLabelsNow, {'K · 2'});
      expect(PasskeyService.allPendingLabelsNow, {'B · 1', 'K · 2'});
      await PasskeyService.kute.clearLabelPending('B · 1');
      expect(await PasskeyService.hasPendingLabel('B · 1'), isTrue);
    });

    test('forgetting a Kute wallet leaves every Breez entry', () async {
      await PasskeyService.getWallet(label: 'L · 1', legacy: false);
      await PasskeyService.kute.getWallet(label: 'L · 1');
      await Hive.box('settings').put('passkey_cached_label', 'L · 1');
      final breezKey = PasskeyService.breez.seedCacheKey('L · 1', breezCred);
      final kuteKey = PasskeyService.kute.seedCacheKey('L · 1', kuteCred);
      expect(keychain.peek(breezKey), isNotNull);
      expect(keychain.peek(kuteKey), isNotNull);

      await PasskeyService.forgetWalletFor('L · 1', provider: 'kute-1');
      expect(keychain.peek(kuteKey), isNull);
      expect(keychain.peek(breezKey), isNotNull);
      expect(Hive.box('settings').get('passkey_cached_label'), 'L · 1');
      // Kute's session copy is gone (a ceremony again), Breez's is not.
      log.clear();
      await PasskeyService.getWallet(label: 'L · 1', legacy: false);
      await PasskeyService.kute.getWallet(label: 'L · 1');
      expect(log, ['kute:signIn:L · 1']);

      await PasskeyService.forgetWalletFor('L · 1', provider: 'breez-0.17');
      expect(keychain.peek(breezKey), isNull);
      expect(keychain.peek(kuteKey), isNotNull);
    });

    test('discovery is per home and tags the home it ran on', () async {
      breez.published = ['B · 1'];
      kute.published = ['K · 2'];
      final b = await PasskeyService.discoverWallets();
      final k = await PasskeyService.kute
          .discoverWallets(preferImmediatelyAvailable: true);
      expect(b.labels, ['B · 1']);
      expect(b.home, PasskeyHome.breez);
      expect(b.credentialId, breezCred);
      expect(k.labels, ['K · 2']);
      expect(k.home, PasskeyHome.kute);
      expect(k.credentialId, kuteCred);
      // Breez's discovery request is unchanged; Kute's asks quietly.
      expect(
          breez.signIns.single.preferImmediatelyAvailableCredentials, isNull);
      expect(kute.signIns.single.preferImmediatelyAvailableCredentials, isTrue);
      // Nothing is pinned by a discovery.
      expect(keychain.keys(), isEmpty);
    });

    test('clearSession forgets both homes', () async {
      await PasskeyService.getWallet(label: 'B · 1', legacy: false);
      await PasskeyService.kute.getWallet(label: 'K · 2');
      PasskeyService.clearSession();
      SecretStores.debugReset();
      keychain = FakeKeychain();
      SecretStores.debugOverride(
          local: keychain.local, synced: keychain.synced);
      log.clear();
      await PasskeyService.getWallet(label: 'B · 1', legacy: false);
      await PasskeyService.kute.getWallet(label: 'K · 2');
      expect(log, ['breez:signIn:B · 1', 'kute:signIn:K · 2']);
    });
  });

  group('platform refusal of an RP', () {
    PasskeyError prf(PrfProviderError e) => PasskeyError.prf(e);

    test('only a failed ceremony that names the association qualifies', () {
      expect(
          PasskeyService.isRpNotAssociatedError(prf(
              const PrfProviderError.generic(
                  'PasskeyPrfException(unknown): The operation couldn’t be '
                  'completed. Application with identifier T.com.kutewallet.app '
                  'is not associated with domain kutewallet.com'))),
          isTrue);
      expect(
          PasskeyService.isRpNotAssociatedError(prf(
              const PrfProviderError.authenticationFailed(
                  'TYPE_SECURITY_ERROR: The incoming request cannot be '
                  'validated'))),
          isTrue);
      expect(
          PasskeyService.isRpNotAssociatedError(prf(
              const PrfProviderError.generic(
                  'PasskeyPrfException(unknown): Domain verification failed. '
                  'Passkeys require a physical device'))),
          isTrue);
      expect(
          PasskeyService.isRpNotAssociatedError(
              prf(const PrfProviderError.configuration('entitlement missing'))),
          isTrue);
    });

    test('nothing after a credential exists, and no other failure', () {
      expect(
          PasskeyService.isRpNotAssociatedError(
              PasskeyError.createdButNotDerived(
                  credentialId: Uint8List.fromList([1]),
                  source: const PrfProviderError.generic(
                      'is not associated with domain kutewallet.com'))),
          isFalse);
      for (final e in [
        const PrfProviderError.userCancelled(),
        const PrfProviderError.userTimedOut(),
        const PrfProviderError.credentialNotFound('none'),
        const PrfProviderError.prfNotSupported(),
        const PrfProviderError.authenticationFailed('biometry locked'),
        const PrfProviderError.generic('network'),
        const PrfProviderError.credentialAlreadyExists('dup'),
      ]) {
        expect(PasskeyService.isRpNotAssociatedError(prf(e)), isFalse,
            reason: '$e');
      }
      expect(
          PasskeyService.isRpNotAssociatedError(
              StateError('is not associated with domain')),
          isFalse);
      expect(
          PasskeyService.isRpNotAssociatedError(
              const PasskeyError.generic('is not associated with domain')),
          isFalse);
    });

    test('the domain probe reads only a "not associated" verdict', () async {
      PasskeyService.debugDomainAssociation = (_) async =>
          const DomainAssociationNotAssociated(source: 's', reason: 'r');
      expect(await PasskeyService.kute.platformReportsNotAssociated(), isTrue);
      PasskeyService.debugDomainAssociation =
          (_) async => const DomainAssociationSkipped(reason: 'offline');
      expect(await PasskeyService.kute.platformReportsNotAssociated(), isFalse);
      PasskeyService.debugDomainAssociation =
          (_) async => const DomainAssociationAssociated();
      expect(await PasskeyService.kute.platformReportsNotAssociated(), isFalse);
      PasskeyService.debugDomainAssociation =
          (_) async => throw StateError('x');
      expect(await PasskeyService.kute.platformReportsNotAssociated(), isFalse);
      PasskeyService.debugDomainAssociation = null;
      // No plugin in tests: no verdict, not a refusal.
      expect(await PasskeyService.kute.platformReportsNotAssociated(), isFalse);
    });
  });
}
