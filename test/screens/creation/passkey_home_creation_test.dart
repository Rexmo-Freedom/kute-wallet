// New passkey wallets go to Kute's own RP. Creation falls back to Breez's
// RP (the flow exactly as it was) ONLY when the platform refuses Kute's RP
// before any credential exists; never after one was created, never for any
// other failure, and never on the web.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/screens/creation/passkey_choice.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/tracking_service.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

Wallet _wallet(String label) => Wallet(
    seed: Seed.mnemonic(mnemonic: phrase, passphrase: null), label: label);

final _noCredential = PasskeyError.prf(
    PrfProviderError.credentialNotFound('No matching credential'));
final _cancelled = PasskeyError.prf(PrfProviderError.userCancelled());

/// iOS: ASAuthorizationError.failed passed through the SDK plugin.
final _iosNotAssociated = PasskeyError.prf(PrfProviderError.generic(
    'PasskeyPrfException(unknown): Application with identifier '
    'T.com.kutewallet.app is not associated with domain kutewallet.com'));

/// Android: Credential Manager's Digital Asset Links refusal.
final _androidNotAssociated = PasskeyError.prf(
    PrfProviderError.authenticationFailed(
        'TYPE_SECURITY_ERROR: The incoming request cannot be validated'));

void main() {
  late List<String> order;
  late List<WalletConfig> saved;
  late List<(String, Map<String, Object>?)> events;

  setUp(() {
    order = [];
    saved = [];
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() => TrackingService.debugTrackObserver = null);

  PasskeyWalletCreation creation({
    bool refused = false,
    Future<Wallet> Function(String)? kuteSignIn,
    Future<Wallet> Function(String, String)? kuteRegister,
    bool breezFallback = true,
    bool withKute = true,
  }) =>
      PasskeyWalletCreation(
        ceremonies: PasskeyCeremonies(
          signIn: (label) async {
            order.add('breez:sign_in');
            throw _noCredential;
          },
          register: (label, name) async {
            order.add('breez:register');
            return _wallet(label);
          },
          hasLegacyCredential: () async => false,
          hasKnownCredential: () async => false,
          cacheLabel: (_) async => order.add('breez:cache_label'),
          markPending: (_) async => order.add('breez:mark_pending'),
          publishLabel: (_) => order.add('breez:publish_label'),
          kute: withKute
              ? PasskeyHomeCeremonies(
                  platformRefusesRp: () async {
                    order.add('kute:domain_check');
                    return refused;
                  },
                  signIn: kuteSignIn ??
                      (label) async {
                        order.add('kute:sign_in');
                        throw _noCredential;
                      },
                  register: kuteRegister ??
                      (label, name) async {
                        order.add('kute:register');
                        return _wallet(label);
                      },
                  hasKnownCredential: () async => false,
                  markPending: (_) async => order.add('kute:mark_pending'),
                  publishLabel: (_) => order.add('kute:publish_label'),
                  breezFallback: breezFallback,
                )
              : null,
        ),
        addWallet: (config) async {
          order.add('add_wallet');
          saved.add(config);
        },
        primeSpark: () => order.add('prime_spark'),
      );

  Future<PasskeyCreationResult> run(PasskeyWalletCreation c,
          {bool skipSignIn = false}) =>
      c.create(
          walletId: 'w1',
          label: 'Daily · 1',
          name: 'Daily',
          skipSignIn: skipSignIn);

  test('a new wallet is created on Kute\'s RP and stamped kute-1', () async {
    final result = await run(creation());
    expect(order, [
      'kute:domain_check',
      'kute:sign_in',
      'kute:register',
      'kute:mark_pending',
      'add_wallet',
      'prime_spark',
      'kute:publish_label',
    ]);
    expect(saved.single.passkeyProvider, 'kute-1');
    expect(saved.single.passkeyLabel, 'Daily · 1');
    expect(saved.single.backedUp, isFalse);
    expect(result.home, PasskeyHome.kute);
    expect(result.path, 'create');
    expect(result.analyticsParams, containsPair('passkey_home', 'kute'));
  });

  test('an existing Kute passkey derives the new label, minting nothing',
      () async {
    final result = await run(creation(kuteSignIn: (label) async {
      order.add('kute:sign_in');
      return _wallet(label);
    }));
    expect(order.where((s) => s.contains('register')), isEmpty);
    expect(result.path, 'sign_in');
    expect(saved.single.passkeyProvider, 'kute-1');
  });

  test('the iOS domain verdict falls back to Breez before any ceremony',
      () async {
    final result = await run(creation(refused: true));
    expect(order, [
      'kute:domain_check',
      'breez:sign_in',
      'breez:register',
      'breez:cache_label',
      'breez:mark_pending',
      'add_wallet',
      'prime_spark',
      'breez:publish_label',
    ]);
    expect(saved.single.passkeyProvider, 'breez-0.17');
    expect(result.home, PasskeyHome.breez);
    expect(result.analyticsParams, containsPair('passkey_home', 'breez'));
  });

  for (final (name, error) in [
    ('iOS', _iosNotAssociated),
    ('Android', _androidNotAssociated),
  ]) {
    test('$name: a refused Kute sign-in falls back to Breez', () async {
      await run(creation(kuteSignIn: (label) async {
        order.add('kute:sign_in');
        throw error;
      }));
      expect(order.contains('kute:register'), isFalse);
      expect(order, containsAllInOrder(['breez:sign_in', 'breez:register']));
      expect(saved.single.passkeyProvider, 'breez-0.17');
    });

    test('$name: a refused Kute mint falls back to Breez', () async {
      await run(creation(kuteRegister: (label, _) async {
        order.add('kute:register');
        throw error;
      }));
      expect(
          order,
          containsAllInOrder(
              ['kute:register', 'breez:sign_in', 'breez:register']));
      expect(saved.single.passkeyProvider, 'breez-0.17');
    });
  }

  test('a typed configuration error on the Kute mint falls back', () async {
    await run(creation(kuteRegister: (label, _) async {
      order.add('kute:register');
      throw PasskeyError.prf(PrfProviderError.configuration('no entitlement'));
    }));
    expect(saved.single.passkeyProvider, 'breez-0.17');
  });

  test('a credential that exists on Kute\'s RP never falls back', () async {
    // created-but-not-derived carries the very same text: still no fallback.
    await expectLater(run(creation(kuteRegister: (label, _) async {
      order.add('kute:register');
      throw PasskeyError.createdButNotDerived(
          credentialId: Uint8List.fromList([1]),
          source: PrfProviderError.generic(
              'is not associated with domain kutewallet.com'));
    })), throwsA(isA<PasskeyStepFailed>()));
    expect(order.where((s) => s.startsWith('breez:')), isEmpty);
    expect(saved, isEmpty);
  });

  test('a Kute mint without the PRF key asks the user, no fallback', () async {
    await expectLater(run(creation(kuteRegister: (label, _) async {
      throw PasskeyError.createdButNotDerived(
          credentialId: Uint8List.fromList([1]),
          source: const PrfProviderError.prfNotSupported());
    })), throwsA(isA<PasskeyPrfUnsupported>()));
    expect(order.where((s) => s.startsWith('breez:')), isEmpty);
  });

  for (final (name, error) in [
    ('a cancel', _cancelled),
    ('a timeout', PasskeyError.prf(PrfProviderError.userTimedOut())),
    (
      'an auth failure',
      PasskeyError.prf(PrfProviderError.authenticationFailed('locked'))
    ),
    ('a network error', PasskeyError.prf(PrfProviderError.generic('offline'))),
  ]) {
    test('$name on the Kute sign-in never falls back', () async {
      await expectLater(
          run(creation(kuteSignIn: (label) async => throw error)),
          throwsA(
              anyOf(isA<PasskeySheetCancelled>(), isA<PasskeyStepFailed>())));
      expect(order.where((s) => s.startsWith('breez:')), isEmpty);
      expect(order.contains('kute:register'), isFalse);
      expect(saved, isEmpty);
    });

    test('$name on the Kute mint never falls back', () async {
      await expectLater(
          run(creation(kuteRegister: (label, _) async => throw error)),
          throwsA(
              anyOf(isA<PasskeySheetCancelled>(), isA<PasskeyStepFailed>())));
      expect(order.where((s) => s.startsWith('breez:')), isEmpty);
      expect(saved, isEmpty);
    });
  }

  test('a dismissed Kute sheet says which home it was', () async {
    try {
      await run(creation(kuteSignIn: (label) async => throw _cancelled));
      fail('expected a cancel');
    } on PasskeySheetCancelled catch (e) {
      expect(e.home, PasskeyHome.kute);
      expect(e.sheet, PasskeySheet.signIn);
    }
  });

  test('create-after-cancel goes straight to the Kute mint', () async {
    final result = await run(creation(), skipSignIn: true);
    expect(order.take(2), ['kute:domain_check', 'kute:register']);
    expect(result.path, 'create_after_cancel');
    expect(saved.single.passkeyProvider, 'kute-1');
  });

  test('the web never falls back to Breez', () async {
    await expectLater(run(creation(refused: true, breezFallback: false)),
        throwsA(isA<PasskeyStepFailed>()));
    await expectLater(
        run(creation(
            breezFallback: false,
            kuteRegister: (label, _) async => throw _iosNotAssociated)),
        throwsA(isA<PasskeyStepFailed>()));
    expect(order.where((s) => s.startsWith('breez:')), isEmpty);
    expect(saved, isEmpty);
  });

  test('without Kute ceremonies the Breez flow runs exactly as before',
      () async {
    final result = await run(creation(withKute: false));
    expect(order, [
      'breez:sign_in',
      'breez:register',
      'breez:cache_label',
      'breez:mark_pending',
      'add_wallet',
      'prime_spark',
      'breez:publish_label',
    ]);
    expect(saved.single.passkeyProvider, 'breez-0.17');
    expect(result.home, PasskeyHome.breez);
  });

  test('the production default tries Kute\'s RP and falls back on phones', () {
    const defaults = PasskeyHomeCeremonies();
    expect(defaults.breezFallback, !kIsWeb);
  });
}
