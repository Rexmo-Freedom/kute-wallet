import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/auth/pin_encryption.dart';
import 'package:kute/services/auth/pin_hash.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/secure/biometric_pin_policy.dart';

import '../services/support/fake_secret_store.dart';
import '../services/support/legacy_reader_r0.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeKeychain keychain;
  late AuthModel auth;
  late BiometricPinPolicy policy;
  late LegacyReaderR0 oldBuild;
  final wallets = [WalletConfig(id: 'w1', name: 'Spending')];

  setUp(() {
    keychain = FakeKeychain();
    auth = AuthModel(store: keychain.local, syncedStore: keychain.synced);
    policy =
        BiometricPinPolicy(store: keychain.local, syncedStore: keychain.synced);
    oldBuild = LegacyReaderR0(
      storage: keychain.local,
      synced: keychain.synced,
      validateMnemonic: (m) async => m == phrase,
      retryDelay: Duration.zero,
    );
    messenger.setMockMethodCallHandler(NativeOnchainService.channel,
        (call) async => (call.arguments as Map)['mnemonic'] == phrase);
  });

  tearDown(() =>
      messenger.setMockMethodCallHandler(NativeOnchainService.channel, null));

  test('the previous build reads a wallet created by 1a', () async {
    await auth.setPinAsync('123456');
    await auth.setMnemonic('w1', phrase);
    expect(keychain.peek('mnemonic_w1'), isNull);

    expect(await oldBuild.getMnemonic('w1', '123456'), phrase);
    expect(await oldBuild.getMnemonic('w1', ''), phrase);
    expect(
        PinHashHelper.verifyPin('123456', keychain.peek('pin_hash')!), isTrue);
  });

  test('a biometric_pin removed by 1a sends the previous build to the keypad',
      () async {
    keychain
      ..seed('pin_hash', PinHashHelper.hashPin('123456'))
      ..seed('biometric_pin', '123456')
      ..seed('v2:wallet:w1.mnemonic', phrase);
    await policy.applyAfterUnlock(await policy.evaluate(wallets));
    expect(keychain.peek('biometric_pin'), isNull);

    expect(await oldBuild.biometricUnlockPin(), isNull,
        reason: 'stored_pin_null: the keypad takes over');
    expect(await oldBuild.getMnemonic('w1', '123456'), phrase);
  });

  test('a V1-only wallet keeps working in the previous build', () async {
    keychain
      ..seed('pin_hash', PinHashHelper.hashPin('123456'))
      ..seed('biometric_pin', '123456')
      ..seed('mnemonic_w1', PinEncryptionHelper.encryptData(phrase, '123456'));
    final dependency = await policy.evaluate(wallets);
    expect(dependency.exists, isTrue);
    await policy.applyAfterUnlock(dependency);

    final storedPin = await oldBuild.biometricUnlockPin();
    expect(storedPin, '123456');
    expect(await oldBuild.getMnemonic('w1', storedPin!), phrase);
  });
}
