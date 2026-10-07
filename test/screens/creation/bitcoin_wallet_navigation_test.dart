import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/words_model.dart';
import 'package:kute/providers/words_provider.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/bitcoin_wallet_setup.dart';
import 'package:kute/screens/creation/recover_wallet.dart';
import 'package:kute/screens/creation/set_pin.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/services/secure_storage.dart';
import 'package:kute/theme/app_theme.dart';

class _Words extends MnemonicWords {
  @override
  Future<List<String>> loadWordList() async =>
      ['abandon', 'ability', 'able', 'about'];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final systemBack in [false, true]) {
    testWidgets(
        'cancel Bitcoin recovery preserves current wallet and session (${systemBack ? 'system' : 'toolbar'} back)',
        (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const seedFixture = 'existing local seed fixture';
      FlutterSecureStorage.setMockInitialValues(
          {'v2:wallet:existing.mnemonic': seedFixture});
      final wallet = WalletConfig(id: 'existing', name: 'My spending wallet');
      final settings = Settings(
          wallets: [wallet],
          activeWalletId: wallet.id,
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: true,
          biometricsEnabled: false,
          bitcoinElectrumNode: 'ssl://example.com:50002',
          nodeType: 'electrum',
          reviewDone: true);
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((ref) => SettingsModel(settings)),
        mnemonicWordsProvider.overrideWithValue(_Words()),
      ]);
      addTearDown(container.dispose);
      final session =
          SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026));
      container.read(sessionAuthProvider.notifier).state = session;
      container.read(pinProvider.notifier).state = 'pending-pin';
      container.read(recoveryModeProvider.notifier).state = true;
      final router = GoRouter(initialLocation: '/home', routes: [
        GoRoute(
            path: '/home',
            builder: (context, _) => Scaffold(
                    body: Center(
                  child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const BitcoinWalletSetup())),
                      child: const Text('Add wallet')),
                ))),
        GoRoute(
            path: '/start',
            builder: (_, __) => const Scaffold(body: Text('Get started'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: ScreenUtilInit(
            designSize: const Size(430, 932),
            builder: (_, __) => MaterialApp.router(
                  routerConfig: router,
                  theme: ThemeData(
                      splashFactory: NoSplash.splashFactory,
                      fontFamily: 'Inter',
                      extensions: [AppColorsExtension.light()]),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                )),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add wallet'));
      await tester.pumpAndSettle();
      expect(find.text('Create new wallet'), findsOneWidget);
      expect(find.textContaining('passkey'), findsNothing);
      await tester.tap(find.text('Recover with 12 words'));
      await tester.pumpAndSettle();
      expect(find.byType(RecoverWallet), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Recovery screen layout');
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.tap(find.byKey(const ValueKey('bitcoin-address-type')));
      await tester.pumpAndSettle();
      expect(find.byType(AppBottomSheetListTile), findsNWidgets(4));
      expect(
          tester
              .widgetList<AppBottomSheetListTile>(
                  find.byType(AppBottomSheetListTile))
              .singleWhere((tile) => tile.isSelected)
              .title,
          'Native SegWit');
      await tester.tap(find.text('Taproot'));
      await tester.pumpAndSettle();
      expect(find.text('Taproot (bc1p)'), findsOneWidget);
      expect(find.byType(AppBottomSheetListTile), findsNothing);
      if (systemBack) {
        Navigator.of(tester.element(find.byType(RecoverWallet))).pop();
      } else {
        await tester.tap(find.byType(KuteBackButton).last);
      }
      await tester.pumpAndSettle();
      expect(find.byType(RecoverWallet), findsNothing);
      expect(find.text('Create new wallet'), findsOneWidget);
      expect(find.text('Get started'), findsNothing);
      expect(container.read(sessionAuthProvider), same(session));
      expect(container.read(pinProvider), 'pending-pin');
      expect(container.read(recoveryModeProvider), isTrue);
      expect(container.read(settingsProvider).activeWalletId, wallet.id);
      expect(container.read(settingsProvider).wallets.single, same(wallet));
      expect(await secureStorage.read(key: 'v2:wallet:existing.mnemonic'),
          seedFixture);

      await tester.tap(find.text('Create new wallet'));
      await tester.pumpAndSettle();
      expect(find.byType(BitcoinWalletCreate), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Create screen layout');
      expect(find.text('Back up your 12 words'), findsOneWidget);
      if (systemBack) {
        Navigator.of(tester.element(find.byType(BitcoinWalletCreate))).pop();
      } else {
        await tester.tap(find.byType(KuteBackButton).last);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byType(KuteBackButton).last);
      await tester.pumpAndSettle();
      expect(find.text('Add wallet'), findsOneWidget);
      expect(find.text('Get started'), findsNothing);
      expect(container.read(sessionAuthProvider), same(session));
      expect(container.read(settingsProvider).wallets.single, same(wallet));
      expect(await secureStorage.read(key: 'v2:wallet:existing.mnemonic'),
          seedFixture);
      expect(tester.takeException(), isNull);
    });
  }
}
