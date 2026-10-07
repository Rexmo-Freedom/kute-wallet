import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/settings/components/seed_words.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/theme/app_theme.dart';

class _Settings extends StateNotifier<Settings> implements SettingsModel {
  _Settings()
      : super(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'default',
            reviewDone: true,
            activeWalletId: 'a',
            wallets: [
              WalletConfig(id: 'a', name: 'Wallet A'),
              WalletConfig(
                  id: 'b',
                  name: 'Wallet B',
                  evmDerivationVersion: EvmDerivationVersion.standardBip39),
            ]));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends AuthModel {
  final reads = <String, Completer<SeedRead>>{};
  @override
  Future<SeedRead> readMnemonic(
    String walletId, {
    required SeedAccess access,
    SeedSession session = SeedSession.locked,
  }) =>
      (reads[walletId] ??= Completer<SeedRead>()).future;
}

Future<void> _reveal(WidgetTester tester) async {
  final context = tester.element(find.byType(SeedWords));
  final reveal = find.widgetWithText(
      AppButton, context.l10n.revealYourRecoveryPhrase);
  expect(reveal, findsOneWidget);
  await tester.ensureVisible(reveal);
  await tester.tap(reveal);
  await tester.pump();
}

void main() {
  final registry = AuthGrantRegistry.instance;
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    registry.revokeAll(includeAutofire: true);
  });
  tearDown(() => registry.revokeAll(includeAutofire: true));

  Future<({ProviderContainer container, _Auth auth})> mount(
      WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _Auth();
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => _Settings()),
      authModelProvider.overrideWith((ref) => auth),
    ]);
    addTearDown(container.dispose);
    container.read(sessionAuthProvider.notifier).state =
        SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime.now());
    for (final wallet in ['a', 'b']) {
      registry.issueSeedReveal(seedRevealIntent(wallet),
          method: AuthGrantMethod.pin);
    }
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
                theme: ThemeData(
                    fontFamily: 'Inter',
                    extensions: [AppColorsExtension.light()]),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const SeedWords(),
              )),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(auth.reads.containsKey('a'), isTrue);
    return (container: container, auth: auth);
  }

  testWidgets('a late wallet A seed never replaces the reviewed wallet B seed',
      (tester) async {
    final harness = await mount(tester);
    await tester.tap(find.text('Wallet A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Wallet B'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(harness.auth.reads.containsKey('b'), isTrue);
    harness.auth.reads['b']!
        .complete(const SeedOk('bravo fixture', SeedSource.v2Local));
    await tester.pump();
    // Words stay masked until the user reveals them (62f18037).
    expect(find.text('bravo'), findsNothing);
    await _reveal(tester);
    expect(find.text('bravo'), findsOneWidget);
    // The EVM derivation label left this screen (3f1e568d); the reviewed
    // wallet is identified by its name and its words.
    expect(find.text('Wallet B'), findsOneWidget);
    harness.auth.reads['a']!
        .complete(const SeedOk('alpha fixture', SeedSource.v2Local));
    await tester.pump();
    expect(find.text('Wallet B'), findsOneWidget);
    expect(find.text('bravo'), findsOneWidget);
    expect(find.text('alpha'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  for (final reason in ['revoked', 'locked']) {
    testWidgets('$reason while reading prevents disclosure', (tester) async {
      final harness = await mount(tester);
      if (reason == 'revoked') {
        registry.revokeAll(includeAutofire: true);
      } else {
        harness.container.read(appLockedProvider.notifier).state = true;
      }
      harness.auth.reads['a']!
          .complete(const SeedOk('alpha fixture', SeedSource.v2Local));
      await tester.pump();
      expect(find.text('alpha'), findsNothing);
      expect(find.byIcon(Icons.copy_rounded), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('revoked reveal grant cannot copy an already displayed seed',
      (tester) async {
    final clipboardWrites = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardWrites.add(call);
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final harness = await mount(tester);
    harness.auth.reads['a']!
        .complete(const SeedOk('alpha fixture', SeedSource.v2Local));
    await tester.pump();
    // Copy only appears once the words are revealed (62f18037).
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
    await _reveal(tester);
    expect(find.text('alpha'), findsOneWidget);
    registry.revokeAll(includeAutofire: true);
    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pump();
    expect(clipboardWrites, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
