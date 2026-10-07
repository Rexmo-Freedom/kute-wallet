import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/secure_screen.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/settings/wallets_screen.dart';
import 'package:kute/services/secure/keychain_local.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:qr_flutter/qr_flutter.dart';

// Public BIP39 test vector key (abandon x11 about). Never fund it.
const testKey =
    '0x1ab42cc412b618bdea3a599e3c9bae199ebf030895b039e9db1e30dafb12b727';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final l10n = AppLocalizationsEn();
  final events = <(String, Map<String, Object>?)>[];

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    SecureScreenController.debugOverride(
        SecureScreenController(platform: TargetPlatform.android));
    messenger.setMockMethodCallHandler(
        KeychainLocal.channel, (call) async => null);
    messenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    SecureScreenController.debugReset();
    messenger.setMockMethodCallHandler(KeychainLocal.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    required Future<String?> Function(BuildContext) reveal,
    Future<void> Function(String)? onCopy,
  }) async {
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
            child: PrivateKeySheet(
              reveal: reveal,
              onCopy: onCopy ?? (_) async {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('the key is hidden until the gate passes, warning first',
      (tester) async {
    var gateRuns = 0;
    await pumpSheet(tester, reveal: (_) async {
      gateRuns++;
      return testKey;
    });

    expect(find.byType(SecureScreen), findsOneWidget);
    expect(find.text(l10n.walletsPrivateKeyWarning), findsOneWidget);
    expect(find.text(testKey), findsNothing);
    expect(find.text(l10n.copy), findsNothing);
    expect(gateRuns, 0);

    await tester.tap(find.byKey(const ValueKey('wallets-show-private-key')));
    await tester.pump();

    expect(gateRuns, 1);
    expect(find.byKey(const ValueKey('wallets-private-key')), findsOneWidget);
    expect(find.text(testKey), findsOneWidget);
    expect(find.text(l10n.copy), findsOneWidget);
  });

  testWidgets('declining the gate keeps the key hidden', (tester) async {
    await pumpSheet(tester, reveal: (_) async => null);
    await tester.tap(find.byKey(const ValueKey('wallets-show-private-key')));
    await tester.pump();

    expect(find.byKey(const ValueKey('wallets-private-key')), findsNothing);
    expect(find.text(l10n.walletsPrivateKeyUnavailable), findsNothing);
    expect(
        find.byKey(const ValueKey('wallets-show-private-key')), findsOneWidget);
  });

  testWidgets('a failed read shows a note, never a key', (tester) async {
    await pumpSheet(tester, reveal: (_) async => throw StateError('mismatch'));
    await tester.tap(find.byKey(const ValueKey('wallets-show-private-key')));
    await tester.pump();

    expect(find.byKey(const ValueKey('wallets-private-key')), findsNothing);
    expect(find.text(l10n.walletsPrivateKeyUnavailable), findsOneWidget);
  });

  testWidgets(
      'copy goes through the auto-clearing clipboard, tracked '
      'without the key', (tester) async {
    final copied = <String>[];
    await pumpSheet(tester,
        reveal: (_) async => testKey, onCopy: (k) async => copied.add(k));
    await tester.tap(find.byKey(const ValueKey('wallets-show-private-key')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wallets-copy-private-key')));
    await tester.pump();

    expect(copied, [testKey]);
    expect(events.map((e) => e.$1), contains('settings_private_key_copied'));
    for (final (_, params) in events) {
      for (final value in params?.values ?? const <Object>[]) {
        expect(value.toString(), isNot(contains(testKey.substring(2))));
      }
    }
    // Let the snackbar timers finish.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets(
      'the QR appears only after the reveal and a tap, encodes '
      'exactly the key, inside SecureContent', (tester) async {
    await pumpSheet(tester, reveal: (_) async => testKey);

    // Before the reveal: no QR and no way to ask for one.
    expect(find.byType(QrImageView), findsNothing);
    expect(find.byKey(const ValueKey('wallets-show-private-key-qr')),
        findsNothing);

    await tester.tap(find.byKey(const ValueKey('wallets-show-private-key')));
    await tester.pump();

    // Revealed key, QR still hidden until asked for.
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text(l10n.walletsShowQr), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('wallets-show-private-key-qr')));
    await tester.pump();

    final qr = find.byType(QrImageView);
    expect(qr, findsOneWidget);
    // buildQrCode feeds the same string to the QR and its Hero tag;
    // QrImageView keeps its data private, so read it from the tag.
    final hero =
        tester.widget<Hero>(find.ancestor(of: qr, matching: find.byType(Hero)));
    expect(hero.tag, 'qrCode_$testKey');
    expect(RegExp(r'^0x[0-9a-f]{64}$').hasMatch(testKey), isTrue);
    expect(find.ancestor(of: qr, matching: find.byType(SecureContent)),
        findsOneWidget);
    expect(find.byKey(const ValueKey('wallets-show-private-key-qr')),
        findsNothing);
    // No event carries the key.
    for (final (_, params) in events) {
      for (final value in params?.values ?? const <Object>[]) {
        expect(value.toString(), isNot(contains(testKey.substring(2))));
      }
    }
  });

  testWidgets('a declined or failed reveal never offers a QR', (tester) async {
    await pumpSheet(tester, reveal: (_) async => null);
    await tester.tap(find.byKey(const ValueKey('wallets-show-private-key')));
    await tester.pump();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.byKey(const ValueKey('wallets-show-private-key-qr')),
        findsNothing);

    await pumpSheet(tester, reveal: (_) async => throw StateError('x'));
    await tester.tap(find.byKey(const ValueKey('wallets-show-private-key')));
    await tester.pump();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.byKey(const ValueKey('wallets-show-private-key-qr')),
        findsNothing);
  });

  testWidgets('closing the sheet drops the QR with the key', (tester) async {
    await pumpSheet(tester, reveal: (_) async => testKey);
    await tester.tap(find.byKey(const ValueKey('wallets-show-private-key')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wallets-show-private-key-qr')));
    await tester.pump();
    expect(find.byType(QrImageView), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text(testKey), findsNothing);

    // A fresh sheet starts hidden again.
    await pumpSheet(tester, reveal: (_) async => testKey);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text(testKey), findsNothing);
  });
}
