// Passkey wallet creation keeps the network off its path: the wallet is
// saved right after the OS ceremony, the Spark connect is primed next, and
// the label publish starts in the background. A cancel is reported with
// the sheet it came from; a cancel on the sign-in sheet can go on to a
// fresh passkey.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/screens/creation/passkey_choice.dart';
import 'package:kute/services/tracking_service.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

Wallet _wallet(String label) => Wallet(
    seed: Seed.mnemonic(mnemonic: phrase, passphrase: null), label: label);

/// The SDK's typed verdicts, as the real client throws them.
final _noCredential = PasskeyError.prf(
    PrfProviderError.credentialNotFound('No matching credential'));
final _cancelled =
    PasskeyError.prf(PrfProviderError.userCancelled());

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
    Future<Wallet> Function(String)? signIn,
    Future<Wallet> Function(String, String)? register,
    bool legacy = false,
    void Function(String)? publishLabel,
    Future<void> Function(String)? markPending,
  }) =>
      PasskeyWalletCreation(
        ceremonies: PasskeyCeremonies(
          signIn: signIn ??
              (label) async {
                order.add('sign_in');
                return _wallet(label);
              },
          register: register ??
              (label, name) async {
                order.add('register');
                return _wallet(label);
              },
          hasLegacyCredential: () async => legacy,
          hasKnownCredential: () async => false,
          cacheLabel: (_) async => order.add('cache_label'),
          markPending: markPending ?? (_) async => order.add('mark_pending'),
          publishLabel: publishLabel ?? (_) => order.add('publish_label'),
        ),
        addWallet: (config) async {
          order.add('add_wallet');
          saved.add(config);
        },
        primeSpark: () => order.add('prime_spark'),
      );

  test('the wallet is saved before the label publish completes', () async {
    final publishStarted = Completer<void>();
    final result = await creation(
      publishLabel: (_) {
        order.add('publish_label');
        publishStarted.complete();
        // Never completes: a dead link. Creation must not wait on it.
      },
    ).create(walletId: 'w1', label: 'Spending Wallet · 1', name: 'Spending Wallet');

    expect(publishStarted.isCompleted, isTrue);
    expect(saved.single.id, 'w1');
    expect(saved.single.isPasskey, isTrue);
    expect(saved.single.passkeyLabel, 'Spending Wallet · 1');
    // Not backed up until the label is on the relay.
    expect(saved.single.backedUp, isFalse);
    expect(saved.single.createdEmpty, isTrue);
    expect(saved.single.evmDerivationVersion,
        EvmDerivationVersion.standardBip39);
    expect(order.indexOf('add_wallet'), lessThan(order.indexOf('publish_label')));
    expect(result.path, 'sign_in');
    expect(result.pendingFlagged, isTrue);
    expect(result.analyticsParams.keys,
        containsAll(['path', 'sign_in_ms', 'save_ms', 'total_ms']));
    expect(result.analyticsParams, containsPair('pending_flagged', true));
    expect(result.analyticsParams.containsKey('create_ms'), isFalse);
  });

  test('the Spark connect is primed right after the wallet is saved',
      () async {
    await creation().create(
        walletId: 'w1', label: 'Spending Wallet · 1', name: 'Spending Wallet');
    expect(order, [
      'sign_in',
      'cache_label',
      'mark_pending',
      'add_wallet',
      'prime_spark',
      'publish_label',
    ]);
  });

  test('the pending flag is stored before the wallet record', () async {
    await creation().create(walletId: 'w1', label: 'L · 1', name: 'L');
    expect(order.indexOf('mark_pending'), lessThan(order.indexOf('add_wallet')));
  });

  test('a pending flag that cannot be stored still saves the wallet, unbacked',
      () async {
    final result = await creation(
      markPending: (_) async {
        order.add('mark_pending');
        throw StateError('hive');
      },
    ).create(walletId: 'w1', label: 'L · 1', name: 'L');
    expect(saved.single.backedUp, isFalse);
    expect(result.pendingFlagged, isFalse);
    expect(result.analyticsParams, containsPair('pending_flagged', false));
    expect(order, [
      'sign_in',
      'cache_label',
      'mark_pending',
      'add_wallet',
      'prime_spark',
      'publish_label',
    ]);
    final failed = events
        .where((e) => e.$1 == 'passkey_label_pending_flag_failed')
        .single;
    expect(failed.$2!.values, isNot(contains('L · 1')));
  });

  test('a failure after the save never fails creation', () async {
    // A "failed" creation would be retried as a SECOND wallet under a new
    // label, so once the record is written the result is a success.
    final result = await PasskeyWalletCreation(
      ceremonies: PasskeyCeremonies(
        signIn: (label) async => _wallet(label),
        hasLegacyCredential: () async => false,
        hasKnownCredential: () async => false,
        cacheLabel: (_) async {},
        markPending: (_) async {},
        publishLabel: (_) => throw StateError('publish'),
      ),
      addWallet: (config) async => saved.add(config),
      primeSpark: () => throw StateError('spark'),
    ).create(walletId: 'w1', label: 'L · 1', name: 'L');
    expect(saved.single.id, 'w1');
    expect(result.path, 'sign_in');
    final stages = events
        .where((e) => e.$1 == 'passkey_create_post_save_failed')
        .map((e) => e.$2!['stage'])
        .toList();
    expect(stages, ['prime_spark', 'publish']);
  });

  test('no passkey resolves: one is minted, then the same save path',
      () async {
    final result = await creation(
      signIn: (_) async {
        order.add('sign_in');
        throw _noCredential;
      },
    ).create(walletId: 'w1', label: 'L · 1', name: 'L');
    expect(order, [
      'sign_in',
      'register',
      'cache_label',
      'mark_pending',
      'add_wallet',
      'prime_spark',
      'publish_label',
    ]);
    expect(result.path, 'create');
    expect(result.analyticsParams.keys,
        containsAll(['sign_in_ms', 'create_ms', 'save_ms']));
  });

  test('a cancel on the sign-in sheet names that sheet and saves nothing',
      () async {
    await expectLater(
      creation(signIn: (_) async => throw _cancelled)
          .create(walletId: 'w1', label: 'L · 1', name: 'L'),
      throwsA(isA<PasskeySheetCancelled>()
          .having((e) => e.sheet, 'sheet', PasskeySheet.signIn)),
    );
    expect(saved, isEmpty);
    expect(order, isNot(contains('register')));
  });

  test('a cancel on the create sheet names that sheet', () async {
    await expectLater(
      creation(
        signIn: (_) async => throw _noCredential,
        register: (_, __) async => throw _cancelled,
      ).create(walletId: 'w1', label: 'L · 1', name: 'L'),
      throwsA(isA<PasskeySheetCancelled>()
          .having((e) => e.sheet, 'sheet', PasskeySheet.create)),
    );
    expect(saved, isEmpty);
  });

  test('the legacy USER_CANCELLED platform code is a cancel too', () async {
    await expectLater(
      creation(
              signIn: (_) async =>
                  throw PlatformException(code: 'USER_CANCELLED'))
          .create(walletId: 'w1', label: 'L · 1', name: 'L'),
      throwsA(isA<PasskeySheetCancelled>()),
    );
  });

  test('after a sign-in cancel, creating a new passkey skips the sign-in',
      () async {
    final result = await creation(
      signIn: (_) async => fail('sign-in must not run again'),
    ).create(walletId: 'w1', label: 'L · 1', name: 'L', skipSignIn: true);
    expect(order.first, 'register');
    expect(result.path, 'create_after_cancel');
    expect(saved.single.isPasskey, isTrue);
  });

  test('only CredentialNotFound may mint; other failures surface with a stage',
      () async {
    await expectLater(
      creation(signIn: (_) async => throw StateError('timeout'))
          .create(walletId: 'w1', label: 'L · 1', name: 'L'),
      throwsA(isA<PasskeyStepFailed>()
          .having((e) => e.stage, 'stage', 'sign_in')),
    );
    expect(order, isNot(contains('register')));
    expect(saved, isEmpty);
  });

  test('a device holding a legacy credential never mints', () async {
    await expectLater(
      creation(signIn: (_) async => throw _noCredential, legacy: true)
          .create(walletId: 'w1', label: 'L · 1', name: 'L'),
      throwsA(isA<PasskeyStepFailed>()
          .having((e) => e.stage, 'stage', 'mint_blocked')),
    );
    expect(order, isNot(contains('register')));
    expect(events.map((e) => e.$1), contains('passkey_create_mint_blocked'));
  });
}
