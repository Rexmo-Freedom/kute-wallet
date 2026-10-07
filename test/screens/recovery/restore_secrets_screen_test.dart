import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/recovery/restore_secrets_screen.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/theme/app_theme.dart';

import '../../services/support/fake_secret_store.dart';

const phraseA =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const phraseB = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong';
const addresses = {phraseA: '0xAAAA', phraseB: '0xBBBB'};

Future<String> fakeDerive(String mnemonic) async =>
    addresses[RecoveryCheck.normalize(mnemonic)]!;

class _Settings extends SettingsModel {
  _Settings(super.state);

  @override
  Future<void> setRecoveryCheckAddress(String walletId, String address) async {
    state = state.copyWith(wallets: [
      for (final w in state.wallets)
        w.id == walletId && w.recoveryCheckAddress == null
            ? w.copyWith(recoveryCheckAddress: address)
            : w,
    ]);
  }
}

class _Auth extends AuthModel {
  _Auth(this.keychain)
      : super(store: keychain.local, syncedStore: keychain.synced);
  final FakeKeychain keychain;
  int wipes = 0;

  @override
  Future<void> deleteAuthentication() async {
    wipes++;
    await keychain.local.deleteAllLocalOnly();
  }
}

Settings settingsWith(List<WalletConfig> wallets) => Settings(
      wallets: wallets,
      activeWalletId: wallets.first.id,
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'ssl://example.com:50002',
      nodeType: 'electrum',
      reviewDone: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeKeychain keychain;
  late _Auth auth;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    keychain = FakeKeychain();
    auth = _Auth(keychain);
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    messenger.setMockMethodCallHandler(NativeOnchainService.channel,
        (call) async {
      final args = call.arguments as Map;
      if (args['action'] == 'validate') {
        return addresses.containsKey(args['mnemonic']);
      }
      throw PlatformException(code: 'unexpected');
    });
  });

  tearDown(() {
    SecretStores.debugReset();
    messenger.setMockMethodCallHandler(NativeOnchainService.channel, null);
  });

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    required List<WalletConfig> wallets,
    RestoreSecretsReason reason = RestoreSecretsReason.secretsMissing,
    bool offerLegacyCopies = true,
    PasskeyMnemonicLoader? loadPasskeyMnemonic,
    Future<void> Function()? wipe,
    String? sessionPin,
  }) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => _Settings(settingsWith(wallets))),
      authModelProvider.overrideWith((ref) => auth),
    ]);
    addTearDown(container.dispose);
    if (sessionPin != null) {
      container.read(sessionAuthProvider.notifier).state =
          SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026));
    }
    Widget stub(String name) => Scaffold(body: Text('route:$name'));
    final router = GoRouter(initialLocation: '/restore', routes: [
      GoRoute(
        path: '/restore',
        builder: (_, __) => RestoreSecretsScreen(
          reason: reason,
          deriveAddress: fakeDerive,
          checkBalance: (_) async => 1200,
          loadPasskeyMnemonic: loadPasskeyMnemonic,
          offerLegacyCopies: offerLegacyCopies,
          wipe: wipe,
        ),
      ),
      GoRoute(path: '/set_pin', builder: (_, __) => stub('set_pin')),
      GoRoute(path: '/open_pin', builder: (_, __) => stub('open_pin')),
      GoRoute(path: '/home', builder: (_, __) => stub('home')),
      GoRoute(
        path: '/recover_wallet',
        builder: (_, __) => stub('recover_wallet'),
        routes: [
          GoRoute(path: 'seed', builder: (_, __) => stub('recover_seed')),
        ],
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          routerConfig: router,
          theme: ThemeData(
              fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> enterPhrase(
      WidgetTester tester, String walletId, String phrase) async {
    await tester.tap(find.byKey(ValueKey('restore-phrase-$walletId')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('restore-phrase-field')), phrase);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('restore-phrase-confirm')));
    await tester.pumpAndSettle();
  }

  Future<void> flushToasts(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  final w1 =
      WalletConfig(id: 'w1', name: 'Spending', recoveryCheckAddress: '0xaaaa');
  final w2 = WalletConfig(
      id: 'w2',
      name: 'Savings',
      sparkEnabled: false,
      recoveryCheckAddress: '0xBBBB');

  testWidgets('a matching phrase writes only to the existing wallet id',
      (tester) async {
    keychain.seed('pin_hash', 'hash');
    await pumpScreen(tester, wallets: [w1, w2]);
    expect(find.text('Needs recovery'), findsNWidgets(2));

    await enterPhrase(
        tester,
        'w1',
        '  ABANDON abandon abandon abandon abandon '
            'abandon abandon abandon abandon abandon abandon about ');

    expect(keychain.peek('v2:wallet:w1.mnemonic'), phraseA);
    expect(keychain.peek('v2:wallet:w2.mnemonic'), isNull);
    expect(keychain.mutations, [
      const FakeMutation('local', 'writeLocalOnly', 'v2:wallet:w1.mnemonic')
    ]);
    expect(find.text('Restored'), findsOneWidget);
    await flushToasts(tester);
  });

  group('Paste', () {
    late String? clipboardText;
    late List<String?> clipboardWrites;

    setUp(() {
      clipboardWrites = [];
      messenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'Clipboard.getData') {
          return clipboardText == null ? null : {'text': clipboardText};
        }
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
          clipboardWrites.add(clipboardText);
        }
        return null;
      });
    });
    tearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    testWidgets('fills the field from a messy paste and clears the clipboard',
        (tester) async {
      keychain.seed('pin_hash', 'hash');
      clipboardText = phraseA
          .split(' ')
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value.toUpperCase()}')
          .join(',\n');
      await pumpScreen(tester, wallets: [w1]);
      await tester.tap(find.byKey(const ValueKey('restore-phrase-w1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('restore-phrase-paste')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
          find.byKey(const ValueKey('restore-phrase-field')));
      expect(field.controller!.text, phraseA);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.enableIMEPersonalizedLearning, isFalse);
      expect(clipboardWrites, ['']);

      await tester.tap(find.byKey(const ValueKey('restore-phrase-confirm')));
      await tester.pumpAndSettle();
      expect(keychain.peek('v2:wallet:w1.mnemonic'), phraseA);
      await flushToasts(tester);
    });

    testWidgets('text that is not a phrase stays on the clipboard',
        (tester) async {
      keychain.seed('pin_hash', 'hash');
      clipboardText = 'bc1qsomeaddress the user copied';
      await pumpScreen(tester, wallets: [w1]);
      await tester.tap(find.byKey(const ValueKey('restore-phrase-w1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('restore-phrase-paste')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
          find.byKey(const ValueKey('restore-phrase-field')));
      expect(field.controller!.text, isEmpty);
      expect(clipboardWrites, isEmpty);
      expect(clipboardText, 'bc1qsomeaddress the user copied');
      await flushToasts(tester);
    });
  });

  testWidgets('a phrase for a different wallet is refused and never written',
      (tester) async {
    keychain.seed('pin_hash', 'hash');
    await pumpScreen(tester, wallets: [w1, w2]);

    await enterPhrase(tester, 'w1', phraseB);

    expect(
        find.text(
            'These words belong to a different wallet. Check them and try again.'),
        findsOneWidget);
    expect(keychain.mutations, isEmpty);

    await tester.tap(find.text('Add as a new wallet'));
    await tester.pumpAndSettle();
    expect(find.text('route:open_pin'), findsOneWidget);
    expect(keychain.mutations, isEmpty);
  });

  testWidgets('with a session the mismatch opens the normal recover flow',
      (tester) async {
    keychain.seed('pin_hash', 'hash');
    await pumpScreen(tester, wallets: [w1], sessionPin: '111111');
    await enterPhrase(tester, 'w1', phraseB);
    await tester.tap(find.text('Add as a new wallet'));
    await tester.pumpAndSettle();
    expect(find.text('route:recover_seed'), findsOneWidget);
  });

  testWidgets('without a stored address the balance summary is confirmed first',
      (tester) async {
    keychain.seed('pin_hash', 'hash');
    final container = await pumpScreen(tester,
        wallets: [WalletConfig(id: 'w3', name: 'Old wallet')]);

    await enterPhrase(tester, 'w3', phraseA);
    expect(find.textContaining('1,200 sats'), findsOneWidget);
    expect(keychain.mutations, isEmpty);

    await tester.tap(find.byKey(const ValueKey('restore-choice-confirm')));
    await tester.pumpAndSettle();

    expect(keychain.peek('v2:wallet:w3.mnemonic'), phraseA);
    expect(container.read(settingsProvider).wallets.single.recoveryCheckAddress,
        '0xAAAA');
  });

  testWidgets(
      'a synced copy with the same phrase is used and nothing is written',
      (tester) async {
    keychain
      ..seed('pin_hash', 'hash')
      ..seedSynced('v2:wallet:w1.mnemonic', phraseA);
    await pumpScreen(tester, wallets: [w1], offerLegacyCopies: false);

    await enterPhrase(tester, 'w1', phraseA);

    expect(keychain.mutations, isEmpty);
    expect(keychain.peekSynced('v2:wallet:w1.mnemonic'), phraseA);
    expect(find.text('Restored'), findsOneWidget);
    await flushToasts(tester);
  });

  testWidgets(
      'the legacy copy is offered only with a synced item and writes nothing',
      (tester) async {
    keychain
      ..seed('pin_hash', 'hash')
      ..seedSynced('v2:wallet:w1.mnemonic', phraseA)
      ..seedSynced('v2:wallet:w2.mnemonic', phraseA);
    await pumpScreen(tester, wallets: [w1, w2]);

    expect(find.byKey(const ValueKey('restore-legacy-w1')), findsOneWidget);
    expect(find.byKey(const ValueKey('restore-legacy-w2')), findsNothing,
        reason: 'the residue belongs to a different wallet');

    await tester.tap(find.byKey(const ValueKey('restore-legacy-w1')));
    await tester.pumpAndSettle();

    expect(keychain.mutations, isEmpty);
    expect(keychain.peekSynced('v2:wallet:w1.mnemonic'), phraseA);
    expect(find.text('Restored'), findsOneWidget);
  });

  testWidgets('no legacy copy is offered without a synced item or off iOS',
      (tester) async {
    keychain.seed('pin_hash', 'hash');
    await pumpScreen(tester, wallets: [w1]);
    expect(find.byKey(const ValueKey('restore-legacy-w1')), findsNothing);
  });

  testWidgets('passkey rows run the ceremony through their stored vintage',
      (tester) async {
    keychain.seed('pin_hash', 'hash');
    final calls = <(String?, bool)>[];
    final legacy =
        WalletConfig(id: 'p-legacy', name: 'Legacy passkey', isPasskey: true);
    final modern = WalletConfig(
        id: 'p-017',
        name: 'Passkey',
        isPasskey: true,
        passkeyLabel: 'kute-2',
        passkeyProvider: 'breez-0.17');
    final container = await pumpScreen(
      tester,
      wallets: [legacy, modern],
      loadPasskeyMnemonic: ({String? label, required bool legacy}) async {
        calls.add((label, legacy));
        return legacy ? null : phraseA;
      },
    );

    await tester.tap(find.byKey(const ValueKey('restore-passkey-p-legacy')));
    await tester.pumpAndSettle();
    await flushToasts(tester);
    expect(find.byKey(const ValueKey('restore-phrase-instead-p-legacy')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('restore-passkey-p-017')));
    await tester.pumpAndSettle();

    expect(calls, [(null, true), ('kute-2', false)]);
    final stored = container.read(settingsProvider).wallets;
    expect(stored.map((w) => w.passkeyProvider), [null, 'breez-0.17']);
    expect(stored.last.recoveryCheckAddress, '0xAAAA');
    expect(keychain.mutations, isEmpty);
  });

  testWidgets('Start fresh needs the typed word and wipes local storage only',
      (tester) async {
    keychain
      ..seed('pin_hash', 'hash')
      ..seed('v2:wallet:w1.mnemonic', phraseA)
      ..seedSynced('v2:wallet:w1.mnemonic', phraseA);
    await pumpScreen(tester, wallets: [w1], wipe: auth.deleteAuthentication);

    await tester.tap(find.byKey(const ValueKey('restore-start-fresh')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('restore-start-fresh-field')), 'DELET');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('restore-start-fresh-confirm')));
    await tester.pumpAndSettle();
    expect(auth.wipes, 0);

    await tester.enterText(
        find.byKey(const ValueKey('restore-start-fresh-field')), 'DELETE');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('restore-start-fresh-confirm')));
    await tester.pumpAndSettle();

    expect(auth.wipes, 1);
    expect(keychain.mutations.map((m) => m.op), ['deleteAllLocalOnly']);
    expect(keychain.peekSynced('v2:wallet:w1.mnemonic'), phraseA);
  });

  testWidgets('Start fresh is hidden when reached from a storage failure',
      (tester) async {
    await pumpScreen(tester,
        wallets: [w1], reason: RestoreSecretsReason.storageUnavailable);
    expect(find.byKey(const ValueKey('restore-start-fresh')), findsNothing);
  });

  testWidgets('hardware and watch-only rows ask to reconnect or re-add',
      (tester) async {
    keychain.seed('pin_hash', 'hash');
    await pumpScreen(tester, wallets: [
      w1,
      WalletConfig(id: 'hw', name: 'Jade', isHardware: true),
      WalletConfig(
          id: 'wo', name: 'Watch', isHardware: true, isWatchOnly: true),
    ]);
    // Row hints were reworded in 4e04001b.
    expect(find.text('Connect your device again'), findsOneWidget);
    expect(find.text('Import the wallet again'), findsOneWidget);
  });

  testWidgets('Done without PIN material sets a PIN and returns here',
      (tester) async {
    final container = await pumpScreen(tester, wallets: [w1]);
    await tester.tap(find.byKey(const ValueKey('restore-done')));
    await tester.pumpAndSettle();
    expect(find.text('route:set_pin'), findsOneWidget);
    expect(container.read(restoreSecretsReturnProvider),
        RestoreSecretsReason.secretsMissing);
  });

  group('RecoveryCheck', () {
    const kuteEvmAddress = '0xAac5482758cD28C38090Dcc2f0A08f09C0F814B2';

    test('derives the pinned index 0 address for a fixed mnemonic', () async {
      expect(RecoveryCheck.deriveSync(phraseA), kuteEvmAddress);
      expect(await RecoveryCheck.derive(phraseA), kuteEvmAddress);
    });

    test('standard recovery check uses the persisted wallet format', () async {
      const standard = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';
      final settings = _Settings(settingsWith([
        WalletConfig(id: 'legacy', name: 'Existing'),
        WalletConfig(id: 'standard', name: 'New',
            evmDerivationVersion: EvmDerivationVersion.standardBip39),
      ]));
      await RecoveryCheck.record(settings, 'legacy', phraseA);
      await RecoveryCheck.record(settings, 'standard', phraseA);
      expect(settings.walletById('legacy')!.recoveryCheckAddress, kuteEvmAddress);
      expect(settings.walletById('standard')!.recoveryCheckAddress, standard);
      expect(await RecoveryCheck.derive(phraseA,
          version: EvmDerivationVersion.standardBip39), standard);
      expect(RecoveryCheck.matches(kuteEvmAddress, standard), isFalse);
    });

    test('a re-typed phrase with other case and spacing matches', () {
      final derived = RecoveryCheck.deriveSync(
          '  Abandon ABANDON abandon abandon abandon abandon abandon\n'
          'abandon abandon abandon abandon about ');
      expect(
          RecoveryCheck.matches(kuteEvmAddress.toLowerCase(), derived), isTrue);
      expect(
          RecoveryCheck.matches(
              kuteEvmAddress, RecoveryCheck.deriveSync(phraseB)),
          isFalse);
    });

    test('is stored with the wallet and survives a Hive round trip', () {
      final wallet = WalletConfig(
          id: 'x', name: 'X', recoveryCheckAddress: kuteEvmAddress);
      expect(WalletConfig.fromMap(wallet.toMap()).recoveryCheckAddress,
          kuteEvmAddress);
      expect(
          WalletConfig.fromMap({'id': 'y', 'name': 'Y'}).recoveryCheckAddress,
          isNull);
      expect(wallet.copyWith(name: 'Z').recoveryCheckAddress, kuteEvmAddress);
    });

    test('only stored-seed wallets hold a seed', () {
      expect(RecoveryCheck.holdsStoredSeed(WalletConfig(id: 'a', name: 'a')),
          isTrue);
      for (final w in [
        WalletConfig(id: 'p', name: 'p', isPasskey: true),
        WalletConfig(id: 'h', name: 'h', isHardware: true),
        WalletConfig(id: 'w', name: 'w', isWatchOnly: true),
        WalletConfig(id: 'e', name: 'e', isExternalAddress: true),
      ]) {
        expect(RecoveryCheck.holdsStoredSeed(w), isFalse, reason: w.id);
      }
    });
  });
}
