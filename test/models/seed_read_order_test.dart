import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/services/auth/pin_encryption.dart';
import 'package:kute/services/auth/pin_hash.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';

import '../services/support/fake_secret_store.dart';
import '../services/support/recording_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const v2Key = 'v2:wallet:w1.mnemonic';
const unlocked = SeedSession(unlocked: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final storageError = PlatformException(code: 'x', details: -25308);
  late FakeKeychain keychain;
  late List<String> reads;
  late AuthModel auth;

  setUp(() {
    keychain = FakeKeychain();
    reads = [];
    auth = AuthModel(
      store: RecordingSecretStore(keychain.local, name: 'local', log: reads),
      syncedStore:
          RecordingSecretStore(keychain.synced, name: 'synced', log: reads),
    );
    AuthModel.readRetryDelay = Duration.zero;
    messenger.setMockMethodCallHandler(NativeOnchainService.channel,
        (call) async {
      final args = call.arguments as Map;
      if (args['action'] == 'validate') return args['mnemonic'] == phrase;
      throw PlatformException(code: 'unexpected');
    });
  });

  tearDown(() {
    AuthModel.readRetryDelay = const Duration(milliseconds: 500);
    messenger.setMockMethodCallHandler(NativeOnchainService.channel, null);
  });

  Iterable<String> ops() => keychain.mutations.map((m) => '${m.op}:${m.key}');

  group('session gate', () {
    test('automatic access while locked reads nothing', () async {
      keychain.seed(v2Key, phrase);
      for (final session in const [
        SeedSession.locked,
        SeedSession(typedPin: '123456'),
      ]) {
        expect(
            await auth.readMnemonic('w1',
                access: SeedAccess.automatic, session: session),
            isA<SeedLocked>());
      }
      expect(reads, isEmpty);
    });

    test('interactive access reads without an unlocked session', () async {
      keychain.seed(v2Key, phrase);
      final read =
          await auth.readMnemonic('w1', access: SeedAccess.interactive);
      expect(read, isA<SeedOk>());
      expect((read as SeedOk).value, phrase);
    });

    test('requireMnemonic and getMnemonic report the outcome', () async {
      await expectLater(auth.requireMnemonic('w1', session: SeedSession.locked),
          throwsA(isA<SeedLockedException>()));
      await expectLater(
          auth.requireMnemonic('w1', session: unlocked),
          throwsA(isA<SeedUnavailableException>().having(
              (e) => e.reason, 'reason', SeedUnavailableReason.absent)));
      keychain.seed(v2Key, phrase);
      expect(await auth.requireMnemonic('w1', session: unlocked), phrase);
      expect(
          await auth.getMnemonic('w1', access: SeedAccess.automatic), isNull);
    });
  });

  group('1a read order', () {
    test('V2 local is read first and wins', () async {
      keychain
        ..seed(v2Key, phrase)
        ..seedSynced(v2Key, 'synced words')
        ..seed('mnemonic_w1', 'cipher');
      final read = await auth.readMnemonic('w1',
          access: SeedAccess.automatic, session: unlocked);
      expect((read as SeedOk).source, SeedSource.v2Local);
      expect(reads, ['local:$v2Key']);
    });

    test('V2 synced is next and is never copied locally', () async {
      keychain
        ..seedSynced(v2Key, phrase)
        ..seed('mnemonic_w1', 'cipher');
      final read = await auth.readMnemonic('w1',
          access: SeedAccess.automatic, session: unlocked);
      expect((read as SeedOk).source, SeedSource.v2Synced);
      expect(read.value, phrase);
      expect(reads, ['local:$v2Key', 'synced:$v2Key']);
      expect(keychain.peek(v2Key), isNull);
      expect(keychain.mutations, isEmpty);
    });

    test('V1 decrypts with the typed PIN and writes nothing', () async {
      keychain.seed(
          'mnemonic_w1', PinEncryptionHelper.encryptData(phrase, '123456'));
      final read = await auth.readMnemonic('w1',
          access: SeedAccess.automatic,
          session: const SeedSession(unlocked: true, typedPin: '123456'));
      expect((read as SeedOk).source, SeedSource.v1);
      expect(read.value, phrase);
      expect(reads, ['local:$v2Key', 'synced:$v2Key', 'local:mnemonic_w1']);
      expect(keychain.mutations, isEmpty);
    });

    test('V1 without a PIN source is locked', () async {
      keychain.seed(
          'mnemonic_w1', PinEncryptionHelper.encryptData(phrase, '123456'));
      expect(
          await auth.readMnemonic('w1',
              access: SeedAccess.automatic, session: unlocked),
          isA<SeedLocked>());
      expect(reads.where((r) => r == 'local:mnemonic'), isEmpty,
          reason: 'the root is read only when V1 is absent');
      expect(keychain.mutations, isEmpty);
    });

    test('V1 decrypts with a kept biometric_pin that verifies', () async {
      keychain
        ..seed('pin_hash', PinHashHelper.hashPin('123456'))
        ..seed('biometric_pin', '123456')
        ..seed(
            'mnemonic_w1', PinEncryptionHelper.encryptData(phrase, '123456'));
      final read = await auth.readMnemonic('w1',
          access: SeedAccess.automatic, session: unlocked);
      expect((read as SeedOk).value, phrase);
      expect(keychain.mutations, isEmpty);
    });

    test('a stale biometric_pin is never used', () async {
      keychain
        ..seed('pin_hash', PinHashHelper.hashPin('654321'))
        ..seed('biometric_pin', '123456')
        ..seed(
            'mnemonic_w1', PinEncryptionHelper.encryptData(phrase, '123456'));
      expect(
          await auth.readMnemonic('w1',
              access: SeedAccess.automatic, session: unlocked),
          isA<SeedLocked>());
    });

    test('a legacy plaintext pin verifies without being upgraded', () async {
      keychain
        ..seed('pin', '123456')
        ..seed('biometric_pin', '123456')
        ..seed(
            'mnemonic_w1', PinEncryptionHelper.encryptData(phrase, '123456'));
      final read = await auth.readMnemonic('w1',
          access: SeedAccess.automatic, session: unlocked);
      expect((read as SeedOk).value, phrase);
      expect(keychain.peek('pin_hash'), isNull);
      expect(keychain.mutations, isEmpty);
    });

    test('a V1 copy that does not decrypt with the verified PIN is unreadable',
        () async {
      keychain.seed(
          'mnemonic_w1', PinEncryptionHelper.encryptData(phrase, '000000'));
      final read = await auth.readMnemonic('w1',
          access: SeedAccess.interactive,
          session: const SeedSession(typedPin: '123456'));
      expect(read, isA<SeedUnavailable>());
      expect(
          (read as SeedUnavailable).reason, SeedUnavailableReason.unreadable);
    });

    test('an encrypted root decrypts with the PIN source and writes nothing',
        () async {
      keychain.seed(
          'mnemonic', PinEncryptionHelper.encryptData(phrase, '123456'));
      final read = await auth.readMnemonic('w1',
          access: SeedAccess.automatic,
          session: const SeedSession(unlocked: true, typedPin: '123456'));
      expect((read as SeedOk).source, SeedSource.root);
      expect(read.value, phrase);
      expect(reads, [
        'local:$v2Key',
        'synced:$v2Key',
        'local:mnemonic_w1',
        'local:mnemonic',
      ]);
      expect(keychain.mutations, isEmpty);
    });

    test('nothing stored is absent after a single pass', () async {
      final read = await auth.readMnemonic('w1',
          access: SeedAccess.automatic, session: unlocked);
      expect((read as SeedUnavailable).reason, SeedUnavailableReason.absent);
      expect(reads, [
        'local:$v2Key',
        'synced:$v2Key',
        'local:mnemonic_w1',
        'local:mnemonic',
      ]);
    });
  });

  group('root promotion', () {
    test('without a PIN source it writes V2 only and keeps the root', () async {
      keychain.seed('mnemonic', phrase);
      final read = await auth.readMnemonic('w1',
          access: SeedAccess.automatic, session: unlocked);
      expect((read as SeedOk).source, SeedSource.root);
      expect(ops(), ['writeLocalOnly:$v2Key']);
      expect(keychain.peek(v2Key), phrase);
      expect(keychain.peek('mnemonic_w1'), isNull);
      expect(keychain.peek('mnemonic'), phrase);
    });

    test('with a PIN source it also writes V1 and never deletes the root',
        () async {
      keychain.seed('mnemonic', phrase);
      await auth.readMnemonic('w1',
          access: SeedAccess.automatic,
          session: const SeedSession(unlocked: true, typedPin: '123456'));
      expect(ops(), ['writeLocalOnly:mnemonic_w1', 'writeLocalOnly:$v2Key']);
      expect(
          PinEncryptionHelper.decryptData(
              keychain.peek('mnemonic_w1')!, '123456'),
          phrase);
      expect(keychain.peek('mnemonic'), phrase);
      expect(
          keychain.mutations.where((m) => m.op.startsWith('delete')), isEmpty);
    });

    test('an earlier failed read skips the copy but still returns the root',
        () async {
      keychain
        ..seed('mnemonic', phrase)
        ..failRead('local', storageError, key: v2Key);
      final read = await auth.readMnemonic('w1',
          access: SeedAccess.automatic, session: unlocked);
      expect((read as SeedOk).value, phrase);
      expect(keychain.mutations, isEmpty);
    });
  });

  group('failed reads', () {
    test('retry three times, then report storage', () async {
      keychain.failRead('local', storageError, key: v2Key);
      final read = await auth.readMnemonic('w1',
          access: SeedAccess.automatic, session: unlocked);
      expect((read as SeedUnavailable).reason, SeedUnavailableReason.storage);
      expect(reads.where((r) => r == 'local:$v2Key'), hasLength(3));
    });

    test('a failed V1 read is retried, never treated as absent', () async {
      keychain
        ..seed('mnemonic', phrase)
        ..failRead('local', storageError, key: 'mnemonic_w1');
      final read = await auth.readMnemonic('w1',
          access: SeedAccess.automatic, session: unlocked);
      expect((read as SeedUnavailable).reason, SeedUnavailableReason.storage);
      expect(reads.where((r) => r == 'local:mnemonic_w1'), hasLength(3));
      expect(reads.where((r) => r == 'local:mnemonic'), isEmpty);
      expect(keychain.mutations, isEmpty);
    });

    test('a failed local read still returns the synced copy', () async {
      keychain
        ..seedSynced(v2Key, phrase)
        ..failRead('local', storageError, key: v2Key);
      final read = await auth.readMnemonic('w1',
          access: SeedAccess.automatic, session: unlocked);
      expect((read as SeedOk).source, SeedSource.v2Synced);
    });
  });
}
