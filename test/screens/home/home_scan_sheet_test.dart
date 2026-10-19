// Home's scan button (beside "Purchase Bitcoin") opens the scanner as a
// bottom sheet over Home, not a full-screen route. Closing it (X or a
// swipe) comes back to Home and releases the camera; a payment code
// closes it and opens Send with what was read, as the full-screen scanner
// did.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/send_tx_model.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/scanner/scanner_sheet.dart';
import 'package:kute/screens/shared/bitcoin_wallet_actions.dart';
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_scanner_camera.dart';

final _l10n = AppLocalizationsEn();

class _Policy extends ChangeNotifier implements RuntimeCapabilitiesService {
  @override
  CapabilityDecision decision(String id) =>
      const CapabilityDecision(allowed: true);

  @override
  bool allows(String id) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _savings = WalletConfig(
  id: 'cold',
  name: 'Cold',
  sparkEnabled: false,
  isHardware: true,
);

const _btc = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';

/// Stands in for the send sheet the scan hands over to.
class _SendStub extends ConsumerWidget {
  const _SendStub();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = ref.watch(sendTxProvider);
    return Scaffold(body: Text('send to ${tx.address} as ${tx.type.name}'));
  }
}

Future<(FakeScannerCameras, GoRouter)> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cameras = FakeScannerCameras();
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => Scaffold(
        body: BitcoinWalletPrimaryActions(wallet: _savings, source: 'home'),
      ),
    ),
    GoRoute(
      path: '/home/pay/confirm_send',
      builder: (_, __) => const _SendStub(),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      cameras.override,
      runtimeCapabilitiesProvider.overrideWith((ref) => _Policy()),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [WalletConfig(id: 'spending', name: 'Spending'), _savings],
          ))),
    ],
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
  return (cameras, router);
}

Future<void> _openScanner(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'scan opens the scanner as a bottom sheet over Home, with its title, '
      'flash and photo controls; no full-screen route', (tester) async {
    final (cameras, router) = await _pump(tester);
    await _openScanner(tester);

    expect(find.byType(ScannerSheet), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.byType(ScannerSheet)));
    expect(route, isA<ModalBottomSheetRoute<dynamic>>());
    expect(route!.settings.name, kSmartScannerRouteName);
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');
    expect(find.byType(BitcoinWalletPrimaryActions, skipOffstage: false),
        findsOneWidget,
        reason: 'Home waits under the sheet');
    expect(find.text(_l10n.scanQrCode), findsOneWidget);
    expect(find.byKey(const ValueKey('scanner-torch')), findsOneWidget);
    expect(find.byKey(const ValueKey('scanner-gallery')), findsOneWidget);
    expect(find.bySemanticsLabel(_l10n.flash), findsOneWidget);
    expect(find.bySemanticsLabel(_l10n.receiveGallery), findsOneWidget);
    expect(find.text(_l10n.paste), findsNothing,
        reason: 'no Paste inside the scanner');
    // The close X sits left of the title.
    expect(
        tester
            .getCenter(find.descendant(
                of: find.byType(ScannerSheet),
                matching: find.byType(KuteCloseButton)))
            .dx,
        lessThan(tester.getTopLeft(find.text(_l10n.scanQrCode)).dx));

    expect(cameras.opened, hasLength(1));
    expect(cameras.last.multiPart, isFalse);
    expect(cameras.last.running, isTrue);
    // The camera is the card: as wide as the sheet, down to its bottom.
    final sheet = tester.getRect(find.byType(ScannerSheet));
    final preview =
        tester.getRect(find.byKey(const ValueKey('fake-camera-preview')));
    expect(preview.width, sheet.width);
    expect(preview.left, sheet.left);
    expect(preview.bottom, sheet.bottom);

    // The flash control toggles the torch and shows its state.
    expect(find.byIcon(Icons.flash_off_rounded), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scanner-torch')));
    await tester.pump();
    expect(cameras.last.torchToggles, 1);
    expect(find.byIcon(Icons.flash_on_rounded), findsOneWidget);
  });

  testWidgets('the X closes it back to Home and releases the camera',
      (tester) async {
    final (cameras, router) = await _pump(tester);
    await _openScanner(tester);

    await tester.tap(find.descendant(
        of: find.byType(ScannerSheet), matching: find.byType(KuteCloseButton)));
    await tester.pump();
    // Stopped the moment it starts closing, released once gone.
    expect(cameras.last.running, isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(ScannerSheet), findsNothing);
    expect(find.byType(BitcoinWalletPrimaryActions), findsOneWidget);
    expect(cameras.last.disposed, isTrue);
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');
  });

  testWidgets('a swipe down closes it and releases the camera', (tester) async {
    final (cameras, _) = await _pump(tester);
    await _openScanner(tester);

    await tester.dragFrom(
        tester.getTopLeft(find.byType(ScannerSheet)) + const Offset(200, 10),
        const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(find.byType(ScannerSheet), findsNothing);
    expect(cameras.last.running, isFalse);
    expect(cameras.last.disposed, isTrue);
  });

  testWidgets(
      'a bitcoin address closes the sheet and opens Send with it, as the '
      'full-screen scanner did', (tester) async {
    final (cameras, router) = await _pump(tester);
    await _openScanner(tester);

    cameras.last.scan(_btc);
    await tester.pumpAndSettle();

    expect(find.byType(ScannerSheet), findsNothing);
    expect(find.text('send to $_btc as ${PaymentType.Bitcoin.name}'),
        findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/home/pay/confirm_send');
    expect(cameras.last.disposed, isTrue);
  });
}
