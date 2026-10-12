import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/auth/pin_encryption.dart';
import 'package:kute/services/auth/pin_hash.dart';
import 'package:kute/services/secure/keychain_local.dart';
import 'package:kute/services/secure/legacy_keychain_rescue.dart';
import 'package:kute/services/secure/secret_error_class.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'package:kute/services/tracking_service.dart';

import '../support/fake_legacy_keychain_lookup.dart';
import '../support/fake_secret_store.dart';

const phraseA =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const phraseB = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong';
const pin = '123456';
const v2 = 'v2:wallet:w1.mnemonic';
const v1 = 'mnemonic_w1';

WalletConfig wallet(String id, {String? recoveryCheckAddress}) => WalletConfig(
      id: id,
      name: 'Wallet $id',
      sparkEnabled: true,
      recoveryCheckAddress: recoveryCheckAddress,
    );

/// Delegates to [inner] but fails every plugin `write` with [error], so the
/// local-only retry can be told apart from the first attempt.
class _DuplicateOnWrite implements SecretStore {
  _DuplicateOnWrite(this.inner, this.error);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;
  late FakeLegacyKeychainLookup lookup;
  late List<(String, Map<String, Object>?)> events;
  late String encryptedA;

  setUpAll(() {
    encryptedA = PinEncryptionHelper.encryptData(phraseA, pin);
  });

  setUp(() {
    keychain = FakeKeychain();
    lookup = FakeLegacyKeychainLookup(keychain);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    LegacyKeychainRescue.debugReset();
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    LegacyKeychainRescue.debugReset();
  });

  LegacyKeychainRescue rescue({
    Future<String> Function(String, WalletConfig)? deriveAddress,
    Future<Set<String>> Function(String)? deriveProxyWallets,
    Future<String?> Function(String)? cachedProxyWallet,
  }) =>
      LegacyKeychainRescue(
        lookup: lookup,
        store: keychain.local,
        syncedStore: keychain.synced,
        validate: (m) async => m == phraseA || m == phraseB,
        deriveAddress: deriveAddress ??
            (m, _) async => m == phraseA ? '0xAAAA' : '0xBBBB',
        deriveProxyWallets: deriveProxyWallets,
        cachedProxyWallet: cachedProxyWallet,
        isCupertino: true,
      );

  void seedLegacy(String key, String value) =>
      keychain.seed(key, value, options: legacyAccessibility);

  Iterable<String> ops() => keychain.mutations.map((m) => '${m.op}:${m.key}');
  Iterable<String> eventNames() => events.map((e) => e.$1);
  Map<String, Object>? paramsOf(String event) =>
      events.where((e) => e.$1 == event).map((e) => e.$2).firstOrNull;

  group('native lookup wrapper', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      messenger.setMockMethodCallHandler(KeychainLocal.channel, (call) async {
        calls.add(call);
        final args = call.arguments as Map;
        switch (call.method) {
          case 'readLegacyItem':
            if (args['account'] == 'pin_hash') return 'salt:hash';
            if (args['account'] == 'boom') {
              throw PlatformException(
                  code: 'Unexpected security result code', details: -25308);
            }
            return null;
          case 'listLegacyAccounts':
            return <String>['v2:wallet:a.mnemonic', 'v2:wallet:b.mnemonic'];
        }
        throw PlatformException(code: 'unexpected');
      });
    });

    tearDown(() =>
        messenger.setMockMethodCallHandler(KeychainLocal.channel, null));

    test('reads and lists through the security channel on iOS', () async {
      const native = NativeLegacyKeychainLookup(platform: TargetPlatform.iOS);
      expect((await native.read('pin_hash')).valueOrThrow(), 'salt:hash');
      expect(await native.read('missing'), isA<SecretAbsent>());
      expect(await native.listAccounts(prefix: 'v2:wallet:'),
          ['v2:wallet:a.mnemonic', 'v2:wallet:b.mnemonic']);
      expect(calls.map((c) => c.method),
          ['readLegacyItem', 'readLegacyItem', 'listLegacyAccounts']);
      final args = calls.first.arguments as Map;
      expect(args['service'], 'flutter_secure_storage_service');
      expect(args['synchronizable'], false);
      // No accessibility is ever part of the query.
      expect(args.keys, isNot(contains('accessibility')));
    });

    test('a failed read is reported as failed, never as absent', () async {
      const native = NativeLegacyKeychainLookup(platform: TargetPlatform.iOS);
      final read = await native.read('boom');
      expect(read, isA<SecretFailed>());
      expect((read as SecretFailed).errorClass,
          SecretErrorClass.interactionNotAllowed);
    });

    test('is a no-op on Android', () async {
      const native =
          NativeLegacyKeychainLookup(platform: TargetPlatform.android);
      expect(await native.read('pin_hash'), isA<SecretAbsent>());
      expect(await native.listAccounts(prefix: 'v2:'), isEmpty);
      expect(calls, isEmpty);
    });
  });

  group('scan', () {
    test('lists only items the current store cannot read', () async {
      seedLegacy(v2, phraseA);
      seedLegacy('mnemonic_w2', encryptedA);
      keychain.seed('v2:wallet:w3.mnemonic', phraseB); // readable today
      seedLegacy('pin_hash', PinHashHelper.hashPin(pin));
      seedLegacy('biometric_pin', pin);

      final scan = await rescue()
          .scan([wallet('w1'), wallet('w2'), wallet('w3')], source: 'startup');

      expect(scan.copies.map((c) => c.walletId), ['w1', 'w2']);
      expect(scan.copies.first.plain, isTrue);
      expect(scan.copies.first.encrypted, isFalse);
      expect(scan.copies.last.encrypted, isTrue);
      expect(scan.copies.last.needsPin, isTrue);
      expect(scan.pinHash, isTrue);
      expect(scan.biometricPin, isTrue);
      expect(keychain.mutations, isEmpty);
      expect(paramsOf('seed_rescue_lookup_completed'), {
        'source': 'startup',
        'outcome': 'found',
        'plain_count': 1,
        'encrypted_count': 1,
        'icloud_count': 0,
      });
    });

    test('unlisted wallet ids and iCloud copies appear only for the sheet',
        () async {
      seedLegacy('v2:wallet:gone.mnemonic', phraseA);
      keychain.seedSynced('v2:wallet:cloud.mnemonic', phraseB);
      seedLegacy('mnemonic_old.next', 'pending-blob');

      final startup = await rescue().scan(const [], source: 'startup');
      expect(startup.found, isFalse);

      final sheet = await rescue()
          .scan(const [], source: 'sheet', includeUnlisted: true);
      expect(sheet.copies.map((c) => c.walletId), ['gone', 'cloud']);
      expect(sheet.copies.first.wallet, isNull);
      expect(sheet.copies.last.icloud, isTrue);
      expect(sheet.copies.last.preferredEra, LegacyCopyEra.icloud);
    });

    test('skips passkey and cold wallets and is empty off iOS', () async {
      seedLegacy(v2, phraseA);
      final passkey = WalletConfig(
          id: 'w1', name: 'P', sparkEnabled: true, isPasskey: true);
      expect((await rescue().scan([passkey], source: 'startup')).found,
          isFalse);
      expect(lookup.reads, isNot(contains(v2)));
      final readsBefore = lookup.reads.length;
      final android = LegacyKeychainRescue(
          lookup: lookup, store: keychain.local, isCupertino: false);
      expect((await android.scan([wallet('w1')], source: 'startup')).found,
          isFalse);
      expect(lookup.reads, hasLength(readsBefore));
    });
  });

  group('V1 decryption', () {
    test('the known PIN opens the Era A blob, a wrong one does not',
        () async {
      seedLegacy(v1, encryptedA);
      final copy = LegacyWalletCopy(walletId: 'w1', encrypted: true);
      expect(await rescue().readEncrypted(copy, pin), phraseA);
      await expectLater(
          rescue().readEncrypted(copy, '000000'),
          throwsA(isA<LegacyRescueException>().having(
              (e) => e.reason, 'reason', LegacyRescueFailure.wrongPin)));
    });

    test('the old pin_hash verifies the PIN', () async {
      seedLegacy('pin_hash', PinHashHelper.hashPin(pin));
      expect(await rescue().legacyPinMatches(pin), isTrue);
      expect(await rescue().legacyPinMatches('000000'), isFalse);
    });

    test('silent PIN candidates: typed first, then stored biometric copies',
        () async {
      keychain.seed('biometric_pin', '111111');
      expect(await rescue().silentPinCandidates(typedPin: pin),
          [pin, '111111']);
      // The same slot under the legacy accessibility: only the lookup
      // sees it.
      seedLegacy('biometric_pin', '222222');
      expect(await rescue().silentPinCandidates(), ['222222']);
      expect(await rescue().silentPinCandidates(typedPin: '222222'),
          ['222222']);
    });
  });

  group('validation', () {
    test('rejects a phrase outside the word list', () async {
      await expectLater(
          rescue().validate('not a phrase', wallet('w1')),
          throwsA(isA<LegacyRescueException>().having((e) => e.reason,
              'reason', LegacyRescueFailure.invalidPhrase)));
    });

    test('compares with the stored recovery check address', () async {
      expect(
          await rescue()
              .validate(phraseA, wallet('w1', recoveryCheckAddress: '0xaaaa')),
          LegacyCopyCheck.address);
      await expectLater(
          rescue()
              .validate(phraseB, wallet('w1', recoveryCheckAddress: '0xAAAA')),
          throwsA(isA<LegacyRescueException>().having(
              (e) => e.reason, 'reason', LegacyRescueFailure.mismatch)));
    });

    test('falls back to the cached Polymarket deposit wallet', () async {
      final r = rescue(
        cachedProxyWallet: (_) async => '0xDEP0',
        deriveProxyWallets: (m) async => {m == phraseA ? '0xdep0' : '0x1'},
      );
      expect(await r.validate(phraseA, wallet('w1')), LegacyCopyCheck.proxy);
      // A proxy this check cannot derive (a Safe) is not a mismatch.
      expect(await r.validate(phraseB, wallet('w1')), LegacyCopyCheck.none);
    });

    test('passes on BIP39 alone when the phone holds no public data',
        () async {
      expect(await rescue().validate(phraseA, wallet('w1')),
          LegacyCopyCheck.none);
      expect(await rescue().validate(phraseA, null), LegacyCopyCheck.none);
    });
  });

  group('startup decision', () {
    test('plain copy and old pin_hash: re-saved, PIN screen', () async {
      seedLegacy(v2, phraseA);
      seedLegacy('pin_hash', PinHashHelper.hashPin(pin));
      seedLegacy('biometric_pin', pin);

      final outcome = await rescue().rescueAtStartup([wallet('w1')]);

      expect(outcome, StartupRescueOutcome.pinScreen);
      expect((await keychain.local.read(key: v2)).valueOrThrow(), phraseA);
      expect(await keychain.local.read(key: 'pin_hash'), isA<SecretPresent>());
      expect(await keychain.local.read(key: 'biometric_pin'),
          isA<SecretPresent>());
      // In-place local-only updates only: nothing deleted, nothing synced.
      expect(ops(), [
        'writeLocalOnly:$v2',
        'writeLocalOnly:pin_hash',
        'writeLocalOnly:biometric_pin',
      ]);
      expect(paramsOf('seed_rescue_restored'),
          {'source': 'startup', 'era': 'b', 'check': 'none'});
      expect(LegacyKeychainRescue.hasPendingAfterPin, isFalse);
    });

    test('a plain copy that mismatches the wallet is left alone', () async {
      seedLegacy(v2, phraseB);
      seedLegacy('pin_hash', PinHashHelper.hashPin(pin));
      final outcome = await rescue()
          .rescueAtStartup([wallet('w1', recoveryCheckAddress: '0xAAAA')]);
      // PIN material is still re-saved: the restore screen then shows the
      // wallet as needing recovery instead of asking for a new PIN.
      expect(outcome, StartupRescueOutcome.pinScreen);
      expect(await keychain.local.read(key: v2), isA<SecretAbsent>());
      expect(paramsOf('seed_rescue_failed'),
          {'source': 'startup', 'era': 'b', 'reason': 'mismatch'});
    });

    test('encrypted copy and old pin_hash: PIN screen, finished on PIN entry',
        () async {
      seedLegacy(v1, encryptedA);
      seedLegacy('pin_hash', PinHashHelper.hashPin(pin));

      final outcome = await rescue().rescueAtStartup([wallet('w1')]);
      expect(outcome, StartupRescueOutcome.pinScreen);
      expect(await keychain.local.read(key: v2), isA<SecretAbsent>());
      expect(LegacyKeychainRescue.hasPendingAfterPin, isTrue);

      final auth = AuthModel(store: keychain.local, syncedStore: keychain.synced);
      expect(await auth.checkPin('000000'), PinCheck.mismatch);
      expect(LegacyKeychainRescue.hasPendingAfterPin, isTrue);
      expect(await auth.checkPin(pin), PinCheck.match);

      expect((await keychain.local.read(key: v2)).valueOrThrow(), phraseA);
      expect((await keychain.local.read(key: v1)).valueOrThrow(), encryptedA);
      expect(ops(), [
        'writeLocalOnly:pin_hash',
        'writeLocalOnly:$v2',
        'writeLocalOnly:$v1',
      ]);
      expect(paramsOf('seed_rescue_restored'),
          {'source': 'startup', 'era': 'a', 'check': 'none'});
      expect(LegacyKeychainRescue.hasPendingAfterPin, isFalse);
    });

    test('a wallet without old pin material: nothing, restore screen',
        () async {
      seedLegacy(v1, encryptedA);
      expect(await rescue().rescueAtStartup([wallet('w1')]),
          StartupRescueOutcome.nothing);
      expect(keychain.mutations, isEmpty);
      expect(LegacyKeychainRescue.hasPendingAfterPin, isFalse);
    });

    test('nothing found: nothing written, lookup reported as none',
        () async {
      expect(await rescue().rescueAtStartup([wallet('w1')]),
          StartupRescueOutcome.nothing);
      expect(keychain.mutations, isEmpty);
      expect(paramsOf('seed_rescue_lookup_completed')!['outcome'], 'none');
      expect(eventNames(), isNot(contains('seed_rescue_restored')));
    });

    test('a failing lookup is reported and changes nothing', () async {
      lookup.failure = PlatformException(code: 'x', details: -25308);
      expect(await rescue().rescueAtStartup([wallet('w1')]),
          StartupRescueOutcome.nothing);
      expect(keychain.mutations, isEmpty);
    });
  });

  group('pin_hash write', () {
    test('retries once as a local-only update on errSecDuplicateItem',
        () async {
      final store = _DuplicateOnWrite(
          keychain.local,
          PlatformException(
              code: 'Unexpected security result code',
              message: 'The specified item already exists in the keychain.',
              details: -25299));
      final auth = AuthModel(store: store, syncedStore: keychain.synced);
      await auth.setPinAsync(pin);
      expect(store.writes, ['write:pin_hash', 'writeLocalOnly:pin_hash']);
      expect(await auth.checkPin(pin), PinCheck.match);
    });

    test('any other write failure is rethrown unchanged', () async {
      final error = PlatformException(code: 'x', details: -25308);
      final store = _DuplicateOnWrite(keychain.local, error);
      final auth = AuthModel(store: store, syncedStore: keychain.synced);
      await expectLater(auth.setPin(pin), throwsA(same(error)));
      expect(store.writes, ['write:pin_hash']);
    });

    test('-25299 classifies as duplicateItem, not definitive', () {
      final cls = classifySecretError(
          PlatformException(code: 'x', details: -25299),
          platform: TargetPlatform.iOS);
      expect(cls, SecretErrorClass.duplicateItem);
      expect(cls.isDefinitive, isFalse);
    });
  });
}
