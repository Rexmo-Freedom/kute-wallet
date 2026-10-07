import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/bitcoin_wallet_creation_service.dart';
import 'package:kute/services/onchain/native_bitcoin_primitives.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';

import '../services/support/fake_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

class _Settings extends SettingsModel {
  _Settings()
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: 'https://blockstream.info/api',
          nodeType: 'Blockstream',
          reviewDone: false,
          wallets: const [],
        ));

  @override
  Future<void> addWallet(WalletConfig newWallet) async {
    state = state.copyWith(wallets: [...state.wallets, newWallet]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeKeychain keychain;
  late AuthModel auth;

  setUp(() {
    keychain = FakeKeychain();
    auth = AuthModel(store: keychain.local, syncedStore: keychain.synced);
    messenger.setMockMethodCallHandler(NativeOnchainService.channel,
        (call) async {
      final args = call.arguments as Map;
      return switch (args['action']) {
        'validate' => args['mnemonic'] == phrase,
        'generate' => phrase,
        _ => throw PlatformException(code: 'unexpected'),
      };
    });
  });

  tearDown(() =>
      messenger.setMockMethodCallHandler(NativeOnchainService.channel, null));

  test('setMnemonic writes only the V2 copy, local-only', () async {
    await auth.setMnemonic('w1', phrase);
    expect(keychain.mutations, const [
      FakeMutation('local', 'writeLocalOnly', 'v2:wallet:w1.mnemonic'),
    ]);
  });

  test('setMnemonic refuses an invalid phrase and writes nothing', () async {
    await expectLater(auth.setMnemonic('w1', 'not a phrase'), throwsException);
    expect(keychain.mutations, isEmpty);
  });

  for (final recovered in [false, true]) {
    test(
        'a ${recovered ? 'recovered' : 'new'} Bitcoin wallet stores no V1 copy',
        () async {
      final service = BitcoinWalletCreationService(
        auth: auth,
        settings: _Settings(),
        isSessionUnlocked: () => true,
        primitives: NativeBitcoinPrimitives(
            service: NativeOnchainService(
                transport: (_, __) async => {
                      'external': 'external descriptor',
                      'internal': 'internal descriptor',
                      'accountXpub': 'public xpub',
                    })),
        // No policy is loaded in a unit test; the offline gate is covered
        // in bitcoin_wallet_creation_test.
        ensureAllowed: (_) async {},
      );
      final wallet = await service.create(
          name: 'Bitcoin', recoveryPhrase: recovered ? phrase : null);
      expect(keychain.keys(), {'v2:wallet:${wallet.id}.mnemonic'});
    });
  }

  test('no creation path passes a PIN to setMnemonic', () {
    final calls = RegExp(r'\.setMnemonic\(([^;]*?)\);', dotAll: true);
    var count = 0;
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final match in calls.allMatches(file.readAsStringSync())) {
        count++;
        final args =
            match.group(1)!.split(',').where((a) => a.trim().isNotEmpty);
        expect(args.length, lessThanOrEqualTo(2),
            reason: '${file.path}: setMnemonic(${match.group(1)})');
      }
    }
    expect(count, greaterThanOrEqualTo(4),
        reason: 'add_wallet, passkey_choice, recover_wallet and the '
            'Bitcoin creation service');
  });

  test('only the biometric PIN policy and changePin write biometric_pin', () {
    final writes =
        RegExp(r"write(LocalOnly)?\(\s*key:\s*'biometric_pin'", dotAll: true);
    final writers = [
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        if (writes.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(writers, ['lib/models/auth_model.dart']);
    expect(
        File('lib/services/secure/biometric_pin_policy.dart')
            .readAsStringSync(),
        contains("_key = 'biometric_pin'"));
  });
}
