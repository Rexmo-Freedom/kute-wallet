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
import 'package:kute/helpers/secure_screen.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/settings/components/backup_wallet.dart';
import 'package:kute/services/secure/keychain_local.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

// Public synthetic vector. Never fund it.
const phrase = 'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

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
            wallets: [WalletConfig(id: 'a', name: 'Wallet A')]));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends AuthModel {
  @override
  Future<SeedRead> readMnemonic(
    String walletId, {
    required SeedAccess access,
    SeedSession session = SeedSession.locked,
  }) async =>
      const SeedOk(phrase, SeedSource.v2Local);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final registry = AuthGrantRegistry.instance;
  final l10n = AppLocalizationsEn();
  final securityCalls = <MethodCall>[];
  final clipboardCalls = <MethodCall>[];
  final events = <(String, Map<String, Object>?)>[];

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // A cached asset future from an earlier test never resolves here.
    rootBundle.clear();
    registry.revokeAll(includeAutofire: true);
    securityCalls.clear();
    clipboardCalls.clear();
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    SecureScreenController.debugOverride(
        SecureScreenController(platform: TargetPlatform.android));
    messenger.setMockMethodCallHandler(KeychainLocal.channel, (call) async {
      securityCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method.startsWith('Clipboard.')) clipboardCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    registry.revokeAll(includeAutofire: true);
    TrackingService.debugTrackObserver = null;
    SecureScreenController.debugReset();
    messenger.setMockMethodCallHandler(KeychainLocal.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => _Settings()),
      authModelProvider.overrideWith((ref) => _Auth()),
    ]);
    addTearDown(container.dispose);
    container.read(sessionAuthProvider.notifier).state =
        SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime.now());
    registry.issueSeedReveal(seedRevealIntent('a'),
        method: AuthGrantMethod.pin);
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
                home: const BackupWallet(walletId: 'a'),
              )),
    ));
    // The word list loads from assets on a real async gap.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (find.text('about').evaluate().isNotEmpty) break;
    }
    expect(find.text('about'), findsOneWidget);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  testWidgets('Copy copies the whole phrase through SeedClipboard',
      (tester) async {
    await mount(tester);
    final copy = find.byKey(const ValueKey('backup-copy-phrase'));
    expect(copy, findsOneWidget);
    // The button sits with the words, inside the capture-hidden content.
    expect(find.ancestor(of: copy, matching: find.byType(SecureContent)),
        findsOneWidget);

    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pump();
    await tester.pump();

    final sensitive = securityCalls.where((c) => c.method == 'copySensitive');
    expect(sensitive.single.arguments, {'text': phrase, 'expirySeconds': 60});
    expect(clipboardCalls.where((c) => c.method == 'Clipboard.setData'),
        isEmpty);
    expect(find.text(l10n.recoveryPhraseCopied), findsOneWidget);
    final copied = events.where((e) => e.$1 == 'seed_phrase_copied');
    expect(copied.single.$2, {'surface': 'backup_wallet'});

    await unmount(tester);
  });

  testWidgets('the reveal step keeps one instruction and no extra captions',
      (tester) async {
    await mount(tester);
    expect(find.text(l10n.writeTheseDown), findsOneWidget);
    expect(find.text(l10n.wordsInOrderWarning(12)), findsOneWidget);
    // The reinstall caption under the card was noise next to the words.
    expect(
        find.text('Deleting or reinstalling the app could lose access to '
            'your funds.'),
        findsNothing);
    // Each word shows once, in its tile, and nowhere else.
    expect(find.text('about'), findsOneWidget);
    expect(find.textContaining(phrase), findsNothing);
    await unmount(tester);
  });
}
