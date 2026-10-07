import 'dart:convert';
import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/services/auth/pin_encryption.dart';
import 'package:kute/services/auth/pin_hash.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:pointycastle/export.dart' as pc;

import '../support/fake_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const otherPhrase = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong';
const rpId = 'keys.breez.technology';

String prfKey(String salt) =>
    'prf_seed_v1__${sha256.convert(utf8.encode('$rpId|$salt'))}';
String get legacyCredentialIdKey =>
    'prf_credential_id_v1__${sha256.convert(utf8.encode(rpId))}';
String seedCacheKey(String label, String credentialHex) =>
    'passkey017_seed_v1__${sha256.convert(utf8.encode('$label|$credentialHex'))}';
String cachedWallet(String label, String mnemonic) => jsonEncode({
      'label': label,
      'seed': jsonEncode({'t': 'm', 'm': mnemonic, 'p': null}),
    });

/// PinEncryptionHelper's legacy V1 layout: base64(iv):base64(AES-CBC with
/// key sha256(pin)).
String legacyEncrypt(String plain, String pin) {
  final key = Uint8List.fromList(sha256.convert(utf8.encode(pin)).bytes);
  final iv = Uint8List.fromList(List.generate(16, (i) => i));
  final cipher = pc.PaddedBlockCipherImpl(
    pc.PKCS7Padding(),
    pc.CBCBlockCipher(pc.AESEngine()),
  )..init(
      true,
      pc.PaddedBlockCipherParameters<pc.CipherParameters, pc.CipherParameters>(
        pc.ParametersWithIV(pc.KeyParameter(key), iv),
        null,
      ),
    );
  final out = cipher.process(Uint8List.fromList(utf8.encode(plain)));
  return '${base64Encode(iv)}:${base64Encode(out)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const prfChannel = MethodChannel('com.kutewallet.app/passkey_prf');
  late FakeKeychain keychain;
  late Directory hiveDir;
  late List<MethodCall> prfCalls;

  setUp(() async {
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    PasskeyPrfService.clearMemory();
    PasskeyService.clearSession();
    hiveDir = await Directory.systemTemp.createTemp('no_cloud_purge');
    Hive.init(hiveDir.path);
    prfCalls = [];
    messenger.setMockMethodCallHandler(NativeOnchainService.channel,
        (call) async {
      final args = call.arguments as Map;
      if (args['action'] == 'validate') return args['mnemonic'] == phrase;
      throw PlatformException(code: 'unexpected');
    });
    messenger.setMockMethodCallHandler(prfChannel, (call) async {
      prfCalls.add(call);
      return {
        'prf': Uint8List.fromList(List.filled(32, 7)),
        'credentialId': Uint8List.fromList([1, 2, 3]),
      };
    });
  });

  tearDown(() async {
    SecretStores.debugReset();
    PasskeyPrfService.clearMemory();
    PasskeyService.clearSession();
    messenger.setMockMethodCallHandler(NativeOnchainService.channel, null);
    messenger.setMockMethodCallHandler(prfChannel, null);
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  group('removals and wipes keep synced twins', () {
    test('wallet removal deletes only local copies', () async {
      const keys = [
        'mnemonic_w1',
        'v2:wallet:w1.mnemonic',
        'xpub_w1',
        'external_address_w1',
      ];
      for (final key in keys) {
        keychain.seed(key, 'local');
        keychain.seedSynced(key, 'synced');
      }
      await AuthModel().deleteWalletMnemonic('w1');
      for (final key in keys) {
        expect(keychain.peek(key), isNull, reason: key);
        expect(keychain.peekSynced(key), 'synced', reason: key);
      }
    });

    test('Forgot PIN and the sixth wrong PIN wipe local items only', () async {
      keychain.seed('pin_hash', 'hash');
      keychain.seed('biometric_pin', '1234');
      keychain.seed('v2:wallet:w1.mnemonic', phrase);
      keychain.seed(prfKey('Default'), 'aa' * 32);
      keychain.seedSynced('v2:wallet:w1.mnemonic', phrase);
      keychain.seedSynced(prfKey('Default'), 'bb' * 32);
      keychain.seedSynced(legacyCredentialIdKey, '0102');
      keychain.seedSynced(
          'passkey017_recovery_manifest_v1', '{"Default":"0.15.1"}');

      await AuthModel().deleteAuthentication();

      expect(keychain.keys(), isEmpty);
      expect(keychain.keys(options: FakeStoreOptions.synced), {
        'v2:wallet:w1.mnemonic',
        prfKey('Default'),
        legacyCredentialIdKey,
        'passkey017_recovery_manifest_v1',
      });
      expect(keychain.mutations,
          const [FakeMutation('local', 'deleteAllLocalOnly', '*')]);
    });

    test('both wipe surfaces go through deleteAuthentication', () {
      for (final path in [
        'lib/screens/login/open_pin.dart',
        'lib/screens/shared/lock_overlay.dart',
      ]) {
        expect(
            File(path).readAsStringSync(), contains('deleteAuthentication()'),
            reason: path);
      }
    });

    test('discardDerive deletes only the local PRF seed', () async {
      keychain.seed(prfKey('L'), 'aa' * 32);
      keychain.seedSynced(prfKey('L'), 'bb' * 32);
      await PasskeyPrfService.discardDerive('L', dropPin: false);
      expect(keychain.peek(prfKey('L')), isNull);
      expect(keychain.peekSynced(prfKey('L')), 'bb' * 32);
    });

    test('clearCache deletes only the local PRF seed', () async {
      keychain.seed(prfKey('L'), 'aa' * 32);
      keychain.seedSynced(prfKey('L'), 'bb' * 32);
      await PasskeyPrfService.derivePrfSeed('L');
      await PasskeyPrfService.clearCache();
      expect(prfCalls, isEmpty);
      expect(keychain.peek(prfKey('L')), isNull);
      expect(keychain.peekSynced(prfKey('L')), 'bb' * 32);
    });
  });

  group('seed writes keep synced twins', () {
    test('setMnemonic on an id that only has synced copies', () async {
      keychain.seedSynced('v2:wallet:w1.mnemonic', phrase);
      keychain.seedSynced('mnemonic_w1', 'synced-v1');
      await AuthModel().setMnemonic('w1', phrase);
      expect(keychain.peek('v2:wallet:w1.mnemonic'), phrase);
      expect(keychain.peekSynced('v2:wallet:w1.mnemonic'), phrase);
      expect(keychain.peekSynced('mnemonic_w1'), 'synced-v1');
      expect(keychain.mutations.map((m) => m.op).toSet(), {'writeLocalOnly'});
    });

    test('a failed synced seed read never derives a replacement wallet', () async {
      keychain.seedSynced(prfKey('L'), 'bb' * 32);
      keychain.failRead('synced', PlatformException(code: 'x', details: -25308),
          key: prfKey('L'));
      await expectLater(PasskeyPrfService.derivePrfSeed('L'),
          throwsA(isA<PlatformException>()));
      expect(prfCalls, isEmpty);
      expect(keychain.peek(prfKey('L')), isNull);
      expect(keychain.peekSynced(prfKey('L')), 'bb' * 32);
    });

    test('changePin re-encrypts V1 without touching synced twins', () async {
      final box = await Hive.openBox('settings');
      await box.put('wallets', [
        {'id': 'w1', 'name': 'Wallet'},
      ]);
      keychain.seed('pin_hash', PinHashHelper.hashPin('1234'));
      keychain.seed(
          'mnemonic_w1', PinEncryptionHelper.encryptData(phrase, '1234'));
      keychain.seedSynced('mnemonic_w1', 'synced-v1');
      keychain.seedSynced('v2:wallet:w1.mnemonic', phrase);

      await AuthModel().changePin('1234', '5678');

      expect(
          PinEncryptionHelper.decryptData(
              keychain.peek('mnemonic_w1')!, '5678'),
          phrase);
      expect(keychain.peekSynced('mnemonic_w1'), 'synced-v1');
      expect(keychain.peekSynced('v2:wallet:w1.mnemonic'), phrase);
      expect(
          keychain.mutations
              .where((m) => m.key == 'mnemonic_w1')
              .map((m) => m.op),
          ['writeLocalOnly']);
    });
  });

  group('reads write nothing', () {
    test('a synced mnemonic hit is not copied locally', () async {
      keychain.seedSynced('v2:wallet:w1.mnemonic', phrase);
      expect(
          await AuthModel().getMnemonic('w1', access: SeedAccess.interactive),
          phrase);
      expect(keychain.peek('v2:wallet:w1.mnemonic'), isNull);
      expect(keychain.mutations, isEmpty);
    });

    test('a synced PRF hit is not copied locally', () async {
      keychain.seedSynced(prfKey('L'), 'bb' * 32);
      expect(await PasskeyPrfService.derivePrfSeed('L'), List.filled(32, 0xbb));
      expect(prfCalls, isEmpty);
      expect(keychain.peek(prfKey('L')), isNull);
      expect(keychain.mutations, isEmpty);
    });

    test('a legacy-format V1 copy decrypts and is not rewritten', () async {
      final legacy = legacyEncrypt(phrase, '1234');
      expect(PinEncryptionHelper.isLegacyFormat(legacy), isTrue);
      keychain.seed('mnemonic_w1', legacy);
      expect(
          await AuthModel().getMnemonic('w1',
              access: SeedAccess.interactive,
              session: const SeedSession(typedPin: '1234')),
          phrase);
      expect(keychain.peek('mnemonic_w1'), legacy);
      expect(keychain.mutations, isEmpty);
    });
  });

  test('a wipe forgets PRF seeds and passkey wallets held in memory', () async {
    const credentialHex = '0a0b';
    Future<String> walletMnemonic() async {
      final wallet = await PasskeyService.getWallet(label: 'W', legacy: false);
      return (wallet.seed as Seed_Mnemonic).mnemonic;
    }

    keychain.seed(prfKey('L'), 'aa' * 32);
    keychain.seed('passkey017_credential_id', credentialHex);
    keychain.seed(seedCacheKey('W', credentialHex), cachedWallet('W', phrase));
    expect(await PasskeyPrfService.derivePrfSeed('L'), List.filled(32, 0xaa));
    expect(await walletMnemonic(), phrase);

    await AuthModel().deleteAuthentication();

    keychain.seed(prfKey('L'), 'cc' * 32);
    keychain.seed('passkey017_credential_id', credentialHex);
    keychain.seed(
        seedCacheKey('W', credentialHex), cachedWallet('W', otherPhrase));
    expect(await PasskeyPrfService.derivePrfSeed('L'), List.filled(32, 0xcc));
    expect(await walletMnemonic(), otherPhrase);
    expect(prfCalls, isEmpty);
  });

  group('source scan', () {
    Iterable<(String, String)> libSources() sync* {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final file in files) {
        final code = file
            .readAsStringSync()
            .split('\n')
            .map((line) => line.replaceFirst(RegExp(r'//.*$'), ''))
            .join('\n');
        yield (file.path, code);
      }
    }

    test(
        'the synced store is mutated only to retire the manifest and the '
        'credential id',
        () {
      final mutation = RegExp(
        r'synced\w*\s*\.\s*(write|writeLocalOnly|delete|deleteLocalOnly|deleteAll|deleteAllLocalOnly)\s*\(',
        caseSensitive: false,
      );
      final hits = <String>[];
      for (final (path, code) in libSources()) {
        for (final match in mutation.allMatches(code)) {
          final start = code.lastIndexOf('static ', match.start);
          final owner =
              start < 0 ? '' : code.substring(start, code.indexOf('(', start));
          final call =
              code.substring(match.start, code.indexOf(')', match.end) + 1);
          hits.add('${path.replaceAll('\\', '/')} | $owner | '
              '${call.replaceAll(RegExp(r'\s+'), ' ')}');
        }
      }
      expect(
          hits,
          unorderedEquals([
            'lib/services/passkey_prf_service.dart | '
                'static Future<void> _deleteCredentialId | '
                'synced.delete(key: key)',
            'lib/services/passkey_service.dart | '
                'static Future<void> retireRecoveryManifest | '
                'synced.delete(key: _retiredManifestKey)',
          ]));
    });

    test('no plugin delete-all on secure storage outside KeychainLocal', () {
      final deleteAll = RegExp(r'[sS]torage\w*\s*\.\s*deleteAll\s*\(\s*\)');
      final hits = [
        for (final (path, code) in libSources())
          if (!path.endsWith('keychain_local.dart') && deleteAll.hasMatch(code))
            path,
      ];
      expect(hits, isEmpty);
    });
  });
}
