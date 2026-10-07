import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/secure_screen.dart';
import 'package:kute/helpers/seed_clipboard.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/settings/wallets_screen.dart';
import 'package:kute/services/secure/keychain_local.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:qr_flutter/qr_flutter.dart';

const phrase = 'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final l10n = AppLocalizationsEn();
  final securityCalls = <MethodCall>[];
  final clipboardCalls = <MethodCall>[];
  final events = <(String, Map<String, Object>?)>[];

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
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
    TrackingService.debugTrackObserver = null;
    SecureScreenController.debugReset();
    messenger.setMockMethodCallHandler(KeychainLocal.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpSheet(WidgetTester tester, String? value,
      {Future<void> Function(String)? onCopy}) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: RecoveryPhraseSheet(
              phrase: value,
              onCopy: onCopy ?? (_) async {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('the phrase is plain text with no selection',
      (tester) async {
    await pumpSheet(tester, phrase);

    expect(find.text(phrase), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(SelectionArea), findsNothing);
    expect(find.text(l10n.done), findsOneWidget);

    await tester.longPress(find.text(phrase));
    await tester.pump();
    expect(clipboardCalls, isEmpty);
  });

  testWidgets('the QR code appears only after an explicit tap', (tester) async {
    await pumpSheet(tester, phrase);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text(l10n.walletsShowQr), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('wallets-show-qr')));
    await tester.pump();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byKey(const ValueKey('wallets-show-qr')), findsNothing);
    expect(clipboardCalls, isEmpty);
  });

  testWidgets('the sheet is a secure screen', (tester) async {
    await pumpSheet(tester, phrase);
    expect(find.byType(SecureScreen), findsOneWidget);
    expect(securityCalls.single.method, 'setSecureScreen');
    expect(securityCalls.single.arguments, {'enabled': true});
  });

  testWidgets('Copy puts the phrase on the clipboard as a sensitive copy',
      (tester) async {
    final clipboard = SeedClipboard();
    await pumpSheet(tester, phrase, onCopy: clipboard.copy);
    expect(find.byKey(const ValueKey('wallets-copy-phrase')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('wallets-copy-phrase')));
    await tester.pump();
    await tester.pump();

    final copy = securityCalls.where((c) => c.method == 'copySensitive');
    expect(copy.single.arguments,
        {'text': phrase, 'expirySeconds': 60});
    expect(clipboardCalls.where((c) => c.method == 'Clipboard.setData'),
        isEmpty);
    expect(clipboard.hasPendingCopy, isTrue);
    expect(find.text(l10n.recoveryPhraseCopied), findsOneWidget);
    expect(events.map((e) => e.$1), contains('seed_phrase_copied'));
    for (final (_, params) in events) {
      for (final value in params?.values ?? const <Object>[]) {
        expect(value.toString(), isNot(contains('abandon')));
      }
    }

    clipboard.dispose();
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('without a phrase there is no QR option', (tester) async {
    await pumpSheet(tester, null);
    expect(find.text(l10n.walletsNoRecoveryPhraseStored), findsOneWidget);
    expect(find.byKey(const ValueKey('wallets-copy-phrase')), findsNothing);
    expect(find.byKey(const ValueKey('wallets-show-qr')), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
  });
}
