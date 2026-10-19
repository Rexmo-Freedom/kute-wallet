// The scanner sheet's camera lifecycle and its link route: the camera
// pauses with the app and resumes with it, a camera that never starts
// offers a retry with a fresh one (the old one released), and the
// `/smart-scanner` link opens the same sheet, not a full-screen page.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/scanner/scanner_camera.dart'
    show ScannerCameraDenied;
import 'package:kute/screens/scanner/scanner_sheet.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_scanner_camera.dart';

final _l10n = AppLocalizationsEn();

/// The camera permission as permission_handler reports it (0 denied,
/// 1 granted).
void _cameraPermission(WidgetTester tester, int status) {
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
      (call) async => call.method == 'checkPermissionStatus' ? status : null);
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
}

/// Five tries at starting the camera, 300 ms apart, then the check.
Future<void> _exhaustStarts(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, FakeScannerCameras cameras,
    {GoRouter? router}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = ThemeData(
      splashFactory: NoSplash.splashFactory,
      fontFamily: 'Inter',
      extensions: [AppColorsExtension.light()]);
  await tester.pumpWidget(ProviderScope(
    overrides: [cameras.override],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => router != null
          ? MaterialApp.router(
              routerConfig: router,
              theme: theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            )
          : MaterialApp(
              theme: theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(children: [
                    TextButton(
                      onPressed: () => showScannerSheet(context),
                      child: const Text('scan'),
                    ),
                    TextButton(
                      onPressed: () =>
                          showScannerSheet(context, multiPart: true),
                      child: const Text('scan multi'),
                    ),
                    TextButton(
                      onPressed: () => showScannerSheet(context,
                          multiPart: true, photos: false),
                      child: const Text('scan recovery'),
                    ),
                  ]),
                ),
              ),
            ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the camera pauses with the app and resumes with it',
      (tester) async {
    final cameras = FakeScannerCameras();
    await _pump(tester, cameras);
    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();
    final camera = cameras.last;
    expect(camera.running, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(camera.running, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(camera.running, isTrue);
    expect(cameras.opened, hasLength(1), reason: 'the same camera resumes');

    // Closed: released, and a later resume does not wake it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(camera.disposed, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(camera.running, isFalse);
  });

  testWidgets(
      'a camera that never starts offers a retry with a fresh one; the old '
      'one is released', (tester) async {
    _cameraPermission(tester, 1);
    final cameras =
        FakeScannerCameras(startErrors: [StateError('camera in use')]);
    await _pump(tester, cameras);
    await tester.tap(find.text('scan'));
    await _exhaustStarts(tester);
    expect(find.text(_l10n.receiveCameraUnavailable), findsOneWidget);
    expect(find.byKey(const ValueKey('scanner-torch')), findsNothing,
        reason: 'no flash without a camera');
    expect(find.byKey(const ValueKey('scanner-gallery')), findsOneWidget,
        reason: 'photos still work');
    final first = cameras.last;

    await tester.tap(find.text(_l10n.tapToRetry));
    await tester.pumpAndSettle();
    expect(cameras.opened, hasLength(2));
    expect(first.disposed, isTrue);
    expect(cameras.last.running, isTrue);
    expect(find.text(_l10n.receiveCameraUnavailable), findsNothing);
    expect(find.byKey(const ValueKey('scanner-torch')), findsOneWidget);
  });

  testWidgets(
      'camera access off: no retry loop, a way to Settings, photos still '
      'there', (tester) async {
    _cameraPermission(tester, 0);
    final cameras =
        FakeScannerCameras(startErrors: [const ScannerCameraDenied()]);
    await _pump(tester, cameras);
    await tester.tap(find.text('scan'));
    await _exhaustStarts(tester);
    expect(cameras.last.starts, 1, reason: 'a denial is never retried');
    expect(find.text(_l10n.scannerCameraAccessOff), findsOneWidget);
    expect(find.text(_l10n.openSettings), findsOneWidget);
    expect(find.byKey(const ValueKey('scanner-torch')), findsNothing);
    expect(find.byKey(const ValueKey('scanner-gallery')), findsOneWidget);
  });

  testWidgets(
      'the recovery-phrase scanner shows flash but no photos; the recipient '
      'and multi-part scanners show both', (tester) async {
    final cameras = FakeScannerCameras();
    await _pump(tester, cameras);
    for (final (button, photos) in [
      ('scan recovery', false),
      ('scan', true),
      ('scan multi', true),
    ]) {
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scanner-torch')), findsOneWidget,
          reason: button);
      expect(find.byKey(const ValueKey('scanner-gallery')),
          photos ? findsOneWidget : findsNothing,
          reason: button);
      expect(find.bySemanticsLabel(_l10n.receiveGallery),
          photos ? findsOneWidget : findsNothing,
          reason: button);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(ScannerSheet), findsNothing);
    }
  });

  testWidgets(
      'the /smart-scanner link opens the same sheet over the current '
      'screen and hands back its value', (tester) async {
    final cameras = FakeScannerCameras();
    String? received;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () async => received = await context.push<String>(
                '/smart-scanner',
                extra: const {'returnRaw': true}),
            child: const Text('link'),
          ),
        ),
      ),
      GoRoute(
        path: '/smart-scanner',
        name: kSmartScannerRouteName,
        pageBuilder: (context, state) {
          final extra = state.extra;
          final returnRaw = extra is Map && extra['returnRaw'] == true;
          return ScannerSheetPage<String>(
            key: state.pageKey,
            name: state.name,
            mode: returnRaw ? ScannerMode.recipient : ScannerMode.route,
          );
        },
      ),
    ]);
    addTearDown(router.dispose);
    await _pump(tester, cameras, router: router);

    await tester.tap(find.text('link'));
    await tester.pumpAndSettle();
    expect(find.byType(ScannerSheet), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.byType(ScannerSheet))),
        isA<ModalBottomSheetRoute<String>>());
    expect(find.text('link', skipOffstage: false), findsOneWidget);

    cameras.last.scan('lnbc1pvjluezpp5qqqsyqcyq5');
    await tester.pumpAndSettle();
    expect(find.byType(ScannerSheet), findsNothing);
    expect(received, 'lnbc1pvjluezpp5qqqsyqcyq5');
    expect(cameras.last.disposed, isTrue);
  });
}
