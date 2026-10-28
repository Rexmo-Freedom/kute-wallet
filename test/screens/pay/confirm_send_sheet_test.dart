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
import 'package:kute/screens/scanner/scanner_sheet.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_scanner_camera.dart';
import '../../helpers/runtime_policy_fixture.dart';

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

/// The scanner sheet's stand-in cameras for the current test.
FakeScannerCameras _cameras = FakeScannerCameras();

Future<(ProviderContainer, GoRouter)> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1125, 2436);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  _cameras = FakeScannerCameras();
  final container = ProviderContainer(overrides: [
    _cameras.override,
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

/// The step on screen, by the header its page announces (the steps have
/// no visible heading).
Finder _step(String title) => find.byWidgetPredicate((w) =>
    w is Semantics &&
    w.properties.header == true &&
    w.properties.label == title);

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
    expect(_step(_l10n.sendTo), findsOneWidget);
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
    expect(_step(_l10n.amount), findsOneWidget);
    expect(_step(_l10n.sendTo), findsNothing);
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
    expect(_step(_l10n.amount), findsOneWidget);
    expect(events.where((e) => e.$1 == 'send_step').map((e) => e.$2?['step']),
        contains('amount'));

    await _dragDown(tester);
    expect(find.byType(ConfirmSend), findsOneWidget);
    expect(tester.getTopLeft(_sheet).dy, moreOrLessEquals(8));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmSend), findsOneWidget);
    expect(_step(_l10n.sendTo), findsOneWidget);

    // On Send to it closes.
    await _dragDown(tester);
    expect(find.byType(ConfirmSend), findsNothing);
  });

  testWidgets(
      'the scanner opens as a sheet over the send sheet; closing it '
      'leaves Send as it was', (tester) async {
    _clipboard(tester, null);
    final (_, router) = await _pump(tester);
    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();
    final location =
        router.routerDelegate.currentConfiguration.last.matchedLocation;

    await tester.tap(find.byTooltip(_l10n.scan));
    await tester.pumpAndSettle();
    expect(find.byType(ScannerSheet), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.byType(ScannerSheet))),
        isA<ModalBottomSheetRoute<dynamic>>());
    expect(router.routerDelegate.currentConfiguration.last.matchedLocation,
        location,
        reason: 'no route pushed for the scanner');
    expect(find.byType(ConfirmSend, skipOffstage: false), findsOneWidget,
        reason: 'Send waits under the scanner');
    expect(_cameras.last.running, isTrue);

    await tester.tap(find.byKey(const ValueKey('scanner-close')));
    await tester.pumpAndSettle();
    expect(find.byType(ScannerSheet), findsNothing);
    expect(find.byType(ConfirmSend), findsOneWidget);
    expect(_step(_l10n.sendTo), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(tester.getSize(_sheet).height,
        moreOrLessEquals(812 * kSendSheetMediumFraction));
    expect(_cameras.last.disposed, isTrue);
  });

  testWidgets('the scanner opens over the sheet and fills its recipient',
      (tester) async {
    _clipboard(tester, null);
    await _pump(tester);
    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(_l10n.scan));
    await tester.pumpAndSettle();
    expect(find.byType(ScannerSheet), findsOneWidget);
    _cameras.last.scan('bitcoin:$_btc?amount=0.001');
    await tester.pumpAndSettle();

    expect(find.byType(ScannerSheet), findsNothing);
    expect(_cameras.last.disposed, isTrue);
    expect(find.byType(ConfirmSend), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        _btc);
    expect(tester.getSize(_sheet).height, moreOrLessEquals(_full));
  });

  testWidgets(
      'swaps blocked for a region: every plain bitcoin rail still goes '
      '(on-chain, Lightning invoice, Lightning address, LNURL, Spark), and '
      'no region copy shows', (tester) async {
    const regions = {'label': 'the European Union, the UK and Switzerland'};
    final policy = runtimePolicyFixture(blocked: {
      'orchestra.swap',
      'orchestra.swap.stablecoins',
      'orchestra.swap.altcoins',
      'crypto.deposit',
    }, reasons: {
      'orchestra.swap': 'country_blocked',
      'orchestra.swap.stablecoins': 'country_blocked',
      'orchestra.swap.altcoins': 'country_blocked',
      'crypto.deposit': 'country_blocked',
    }, decorations: {
      'orchestra.swap': {'regions': regions},
    });
    AffiliateService.debugSessionToken = 'session';
    RuntimeCapabilitiesService.debugInstance = policy;
    addTearDown(() => AffiliateService.debugSessionToken = null);
    expect(await policy.refresh(), isTrue);
    _clipboard(tester, null);
    await _pump(tester);
    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();
    final cta = find.ancestor(
        of: find.text(_l10n.continueLabel), matching: find.byType(AppButton));
    for (final recipient in [
      'lnbc1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdpl2pkx2ctnv5sxxmmwwd5kgetjypeh2ursdae8g6twvus8g6rfwvs8qun0dfjkxaq',
      'satoshi@paykute.com',
      'lnurl1dp68gurn8ghj7ctsdyhxwetewdjhytnxw4hxgtmvde6hymp0wpshj0mswfhk5etrw3ykg0f3xqcs2mcx97',
      'sp1qqw5hn4hlkuu2lesxpqh6w6rm0krsjr0xn6yrefvnmsq8mzqxw40qzuy7nt',
      _btc,
    ]) {
      await tester.enterText(find.byType(TextField), recipient);
      await tester.pumpAndSettle();
      expect(tester.widget<AppButton>(cta).onPressed, isNotNull,
          reason: recipient);
      expect(find.textContaining('Not available'), findsNothing,
          reason: recipient);
    }
    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(_step(_l10n.amount), findsOneWidget);
    expect(find.byType(CapabilityUnavailableSheet), findsNothing);
    // The policy's expiry timer goes with it.
    RuntimeCapabilitiesService.debugInstance = null;
    policy.dispose();
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
    expect(_step(_l10n.amount), findsOneWidget);
  });
}
