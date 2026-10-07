import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/secure_screen.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/secure/keychain_local.dart';
import 'package:kute/theme/app_theme.dart';

const hiddenText =
    'Your recovery phrase is hidden while your screen is being recorded.';
const screenshotText = 'You took a screenshot of your recovery phrase. '
    'Delete it from your photos to keep your wallet safe.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var nativeCaptured = false;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    calls.clear();
    nativeCaptured = false;
    messenger.setMockMethodCallHandler(KeychainLocal.channel, (call) async {
      calls.add(call);
      return call.method == 'isCaptured' ? nativeCaptured : null;
    });
  });

  tearDown(() {
    SecureScreenController.debugReset();
    messenger.setMockMethodCallHandler(KeychainLocal.channel, null);
  });

  Future<void> sendFromNative(String method, [Object? arguments]) async {
    await messenger.handlePlatformMessage(
      KeychainLocal.channel.name,
      KeychainLocal.channel.codec
          .encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
  }

  Future<ValueNotifier<Set<String>>> pumpScreens(
    WidgetTester tester,
    Set<String> initial,
  ) async {
    final mounted = ValueNotifier<Set<String>>(initial);
    addTearDown(mounted.dispose);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ValueListenableBuilder<Set<String>>(
            valueListenable: mounted,
            builder: (_, surfaces, __) => Column(
              children: [
                for (final surface in surfaces)
                  SecureScreen(
                    key: ValueKey(surface),
                    surface: surface,
                    child: SecureContent(child: Text('words $surface')),
                  ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return mounted;
  }

  const enable = MethodCall('setSecureScreen', {'enabled': true});
  const disable = MethodCall('setSecureScreen', {'enabled': false});

  Matcher isCall(MethodCall expected) => predicate<MethodCall>(
      (c) =>
          c.method == expected.method &&
          c.arguments.toString() == expected.arguments.toString(),
      '${expected.method}(${expected.arguments})');

  group('Android', () {
    setUp(() => SecureScreenController.debugOverride(
        SecureScreenController(platform: TargetPlatform.android)));

    testWidgets('FLAG_SECURE is ref counted across mounted screens',
        (tester) async {
      final mounted = await pumpScreens(tester, {'seed_words'});
      expect(calls, [isCall(enable)]);

      mounted.value = {'seed_words', 'backup_wallet'};
      await tester.pump();
      expect(calls, [isCall(enable)]);
      expect(SecureScreenController.instance.activeCount, 2);

      mounted.value = {'backup_wallet'};
      await tester.pump();
      expect(calls, [isCall(enable)]);

      mounted.value = {};
      await tester.pump();
      expect(calls, [isCall(enable), isCall(disable)]);
      expect(SecureScreenController.instance.activeCount, 0);

      mounted.value = {'wallets'};
      await tester.pump();
      expect(calls, [isCall(enable), isCall(disable), isCall(enable)]);
    });

    testWidgets('Android never asks about capture and never hides words',
        (tester) async {
      await pumpScreens(tester, {'seed_words'});
      expect(calls.where((c) => c.method == 'isCaptured'), isEmpty);
      expect(find.text('words seed_words'), findsOneWidget);
    });

    testWidgets('a missing native side never throws', (tester) async {
      messenger.setMockMethodCallHandler(KeychainLocal.channel, null);
      final mounted = await pumpScreens(tester, {'seed_words'});
      mounted.value = {};
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('iOS', () {
    setUp(() => SecureScreenController.debugOverride(
        SecureScreenController(platform: TargetPlatform.iOS)));

    testWidgets(
        'monitoring starts with the first screen and stops with the last',
        (tester) async {
      final mounted = await pumpScreens(tester, {'seed_words', 'wallets'});
      expect(calls.map((c) => c.method), ['setSecureScreen', 'isCaptured']);
      expect(calls.first, isCall(enable));

      mounted.value = {};
      await tester.pump();
      expect(calls.last, isCall(disable));
    });

    testWidgets('recording hides the words and they return afterwards',
        (tester) async {
      await pumpScreens(tester, {'seed_words'});
      expect(find.text('words seed_words'), findsOneWidget);

      await sendFromNative('captureChanged', true);
      await tester.pump();
      expect(find.text('words seed_words'), findsNothing);
      expect(find.text(hiddenText), findsOneWidget);

      await sendFromNative('captureChanged', false);
      await tester.pump();
      expect(find.text('words seed_words'), findsOneWidget);
      expect(find.text(hiddenText), findsNothing);
    });

    testWidgets('a screen opened during a recording starts hidden',
        (tester) async {
      nativeCaptured = true;
      await pumpScreens(tester, {'backup_wallet'});
      await tester.pump();
      expect(find.text('words backup_wallet'), findsNothing);
      expect(find.text(hiddenText), findsOneWidget);
    });

    testWidgets('a screenshot shows one warning for the top screen',
        (tester) async {
      await pumpScreens(tester, {'seed_words', 'backup_wallet'});
      await sendFromNative('screenshotTaken');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(screenshotText), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('native events after the last screen closes are ignored',
        (tester) async {
      final mounted = await pumpScreens(tester, {'seed_words'});
      mounted.value = {};
      await tester.pump();
      await sendFromNative('screenshotTaken');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(screenshotText), findsNothing);
    });
  });

  testWidgets('other platforms send nothing', (tester) async {
    SecureScreenController.debugOverride(
        SecureScreenController(platform: TargetPlatform.macOS));
    final mounted = await pumpScreens(tester, {'seed_words'});
    mounted.value = {};
    await tester.pump();
    expect(calls, isEmpty);
  });

  test('every recovery phrase surface is wrapped', () {
    const surfaces = {
      'lib/screens/settings/components/seed_words.dart': 'seed_words',
      'lib/screens/settings/components/backup_wallet.dart': 'backup_wallet',
      'lib/screens/settings/wallets_screen.dart': 'wallets',
      'lib/screens/creation/recover_wallet.dart': 'recover_wallet',
      'lib/screens/recovery/restore_secrets_screen.dart': 'restore_secrets',
    };
    surfaces.forEach((path, surface) {
      final source = File(path).readAsStringSync();
      expect(source, contains("surface: '$surface'"), reason: path);
      expect(source, contains('SecureContent('), reason: path);
    });
  });
}
