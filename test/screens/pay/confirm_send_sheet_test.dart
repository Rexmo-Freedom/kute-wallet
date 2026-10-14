// The bitcoin send opens as the send sheet through its own route
// (`pay_send`), the way the dock, the scanner hand-off and payment links
// reach it: Send to first at medium height; a recipient (typed, pasted
// or brought by the link) makes it full.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/pay/components/confirm_send.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

final _l10n = AppLocalizationsEn();

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: true,
      activeWalletId: 'spending',
      wallets: [WalletConfig(id: 'spending', name: 'Spending')],
    );

const _btc = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';

/// The sheet's full height on a 375 x 812 view with no status bar.
const double _full = 812 - 8;

/// The platform clipboard, holding [text] (null: empty).
void _clipboard(WidgetTester tester, String? text) {
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    switch (call.method) {
      case 'Clipboard.getData':
        return text == null ? null : {'text': text};
      case 'Clipboard.hasStrings':
        return {'value': text != null};
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
}

/// A long drag down from the sheet's handle.
Future<void> _dragDown(WidgetTester tester) async {
  await tester.dragFrom(
      tester.getTopLeft(_sheet) + const Offset(180, 8), const Offset(0, 600));
  await tester.pumpAndSettle();
}

/// [scanResult] is what the stand-in scanner hands back.
Future<(ProviderContainer, GoRouter)> _pump(WidgetTester tester,
    {String? scanResult}) async {
  tester.view.physicalSize = const Size(1125, 2436);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => SettingsModel(_settings())),
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (context, _) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => context.pushNamed('pay_send'),
            child: const Text('Open send'),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/send',
      name: 'pay_send',
      pageBuilder: (context, state) => SendSheetPage<void>(
        key: state.pageKey,
        name: state.name,
        child: const ConfirmSend(),
      ),
    ),
    GoRoute(
      path: '/scan',
      name: 'smartScanner',
      builder: (context, state) {
        expect((state.extra as Map)['returnRaw'], isTrue);
        return Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.pop(scanResult),
              child: const Text('Scanned'),
            ),
          ),
        );
      },
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
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (container, router);
}

Finder get _sheet => find.byKey(const ValueKey('send-sheet'));

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('confirm_send_sheet');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('the bitcoin send opens on Send to, at medium height',
      (tester) async {
    _clipboard(tester, null);
    await _pump(tester);
    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmSend), findsOneWidget);
    expect(find.text(_l10n.sendWhereShouldItLand), findsOneWidget);
    expect(tester.getSize(_sheet).height,
        moreOrLessEquals(812 * kSendSheetMediumFraction));
  });

  testWidgets('a payment link with its recipient opens it full, on Amount',
      (tester) async {
    final (container, router) = await _pump(tester);
    // The scanner (or the link handler) writes the recipient and pushes
    // the route at once; hold the draft as it does.
    container.listen(sendTxProvider, (_, __) {});
    container
        .read(sendTxProvider.notifier)
        .updateAddress('bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq');
    router.pushNamed('pay_send');
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmSend), findsOneWidget);
    expect(find.text(_l10n.amount), findsOneWidget);
    expect(find.text(_l10n.sendWhereShouldItLand), findsNothing);
    expect(tester.getSize(_sheet).height, moreOrLessEquals(812 - 8));
  });

  testWidgets(
      'a recipient expands it and moves on to Amount; past Send to a drag '
      'does not close it, system back steps back, and the funnel says it '
      'is a sheet', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    _clipboard(tester, _btc);
    await _pump(tester);
    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();
    expect(events.where((e) => e.$1 == 'send_flow_started').single.$2,
        containsPair('presentation', 'sheet'));

    await tester.tap(find.byTooltip(_l10n.paste));
    await tester.pumpAndSettle();
    expect(tester.getSize(_sheet).height, moreOrLessEquals(_full));
    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.amount), findsOneWidget);
    expect(
        events.where((e) => e.$1 == 'send_step').map((e) => e.$2?['step']),
        contains('amount'));

    await _dragDown(tester);
    expect(find.byType(ConfirmSend), findsOneWidget);
    expect(tester.getTopLeft(_sheet).dy, moreOrLessEquals(8));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmSend), findsOneWidget);
    expect(find.text(_l10n.sendWhereShouldItLand), findsOneWidget);

    // On Send to it closes.
    await _dragDown(tester);
    expect(find.byType(ConfirmSend), findsNothing);
  });

  testWidgets('the scanner opens over the sheet and fills its recipient',
      (tester) async {
    _clipboard(tester, null);
    await _pump(tester, scanResult: 'bitcoin:$_btc?amount=0.001');
    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(_l10n.scan));
    await tester.pumpAndSettle();
    expect(find.text('Scanned'), findsOneWidget);
    await tester.tap(find.text('Scanned'));
    await tester.pumpAndSettle();

    expect(find.byType(ConfirmSend), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        _btc);
    expect(tester.getSize(_sheet).height, moreOrLessEquals(_full));
  });

  testWidgets(
      'the keyboard: Continue and the field sit above it, nothing '
      'overflows at 375 pt with text x1.3', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    _clipboard(tester, null);
    await _pump(tester);
    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), _btc);
    const keyboard = 336.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(_sheet).height, moreOrLessEquals(_full));
    const keyboardTop = 812 - keyboard;
    expect(tester.getRect(find.byType(TextField)).bottom,
        lessThanOrEqualTo(keyboardTop));
    final cta = find.ancestor(
        of: find.text(_l10n.continueLabel), matching: find.byType(AppButton));
    expect(tester.getRect(cta).bottom, lessThanOrEqualTo(keyboardTop));
    expect(tester.widget<AppButton>(cta).onPressed, isNotNull);

    await tester.tap(cta);
    await tester.pumpAndSettle();
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(_l10n.amount), findsOneWidget);
  });
}
