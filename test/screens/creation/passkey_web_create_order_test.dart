// Creating a passkey wallet on the web: the quiet sign-in that lets an
// existing Kute passkey derive a new label cannot be quiet in a browser
// without immediate mediation; it showed "You don't have any passkeys
// saved for this website" before the create sheet. On the web the create
// now runs first unless the browser can sign in silently or this browser
// already knows a Kute credential (then the pinned sign-in, so one passkey
// keeps serving several wallets). The phones keep their order.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/creation/passkey_choice.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

Wallet _wallet(String label) => Wallet(
    seed: Seed.mnemonic(mnemonic: phrase, passphrase: null), label: label);

void main() {
  late List<String> order;

  PasskeyWalletCreation creation(
          {required bool web, required bool known, required bool immediate}) =>
      PasskeyWalletCreation(
        ceremonies: PasskeyCeremonies(
          signIn: (label) async => throw UnimplementedError(),
          register: (label, name) async => throw UnimplementedError(),
          hasLegacyCredential: () async => false,
          hasKnownCredential: () async => false,
          cacheLabel: (_) async {},
          markPending: (_) async {},
          publishLabel: (_) {},
          kute: PasskeyHomeCeremonies(
            platformRefusesRp: () async => false,
            signIn: (label) async {
              order.add('sign_in');
              return _wallet(label);
            },
            register: (label, name) async {
              order.add('register');
              return _wallet(label);
            },
            hasKnownCredential: () async => known,
            markPending: (_) async {},
            publishLabel: (_) {},
            breezFallback: !web,
            web: web,
            immediateMediation: () async => immediate,
          ),
        ),
        addWallet: (_) async {},
        primeSpark: () {},
      );

  Future<PasskeyCreationResult> run(PasskeyWalletCreation c) => c.create(
      walletId: 'w1', label: 'Daily · 1', name: 'Daily', skipSignIn: false);

  setUp(() => order = []);

  test('web, no silent sign-in, nothing known: create, no sign-in sheet',
      () async {
    final r = await run(creation(web: true, known: false, immediate: false));
    expect(order, ['register']);
    expect(r.path, 'create');
  });

  test('web, a Kute credential known here: the pinned sign-in', () async {
    final r = await run(creation(web: true, known: true, immediate: false));
    expect(order, ['sign_in']);
    expect(r.path, 'sign_in');
  });

  test('web with immediate mediation: the quiet sign-in first', () async {
    await run(creation(web: true, known: false, immediate: true));
    expect(order.first, 'sign_in');
  });

  test('phones: the sign-in first, as before', () async {
    await run(creation(web: false, known: false, immediate: false));
    expect(order.first, 'sign_in');
  });
}
