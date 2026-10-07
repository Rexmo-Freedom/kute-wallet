// USB transport choice in the Ledger device picker (Wallet hardening
// Phase 3, P3.2 / O16): USB only on Android with the flag on.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/constants/feature_flags.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/providers/ledger/ledger_transports_provider.dart';
import 'package:kute/screens/shared/ledger_device_picker.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class _RecordingLedgerService extends LedgerService {
  _RecordingLedgerService() : super(disconnectBle: (_) async {});

  final scans = <LedgerConnectionType>[];

  @override
  Future<void> startScan(LedgerConnectionType type) async => scans.add(type);

  @override
  Future<void> stopScan() async {}
}

const _usbKey = ValueKey('ledger_transport_usb');
const _bluetoothKey = ValueKey('ledger_transport_bluetooth');

Future<_RecordingLedgerService> _openPicker(
  WidgetTester tester, {
  required TargetPlatform platform,
  required bool usbFlag,
}) async {
  // Phone-sized surface (390 x 844 logical). The default 800 x 600 test
  // surface is shorter than any supported phone and overflows the picker's
  // existing empty state even with the flag off.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final service = _RecordingLedgerService();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ledgerServiceProvider.overrideWith((ref) => service),
      ledgerTransportPlatformProvider.overrideWithValue(platform),
      ledgerUsbTransportFlagProvider.overrideWithValue(usbFlag),
    ],
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showLedgerDevicePicker(context, ref),
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open picker'));
  await tester.pumpAndSettle();
  return service;
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
  });

  test('the release USB flag controls the default Android transports', () {
    final container = ProviderContainer(overrides: [
      ledgerTransportPlatformProvider.overrideWithValue(TargetPlatform.android),
    ]);
    addTearDown(container.dispose);
    expect(container.read(ledgerTransportsProvider), [
      LedgerConnectionType.bluetooth,
      if (kLedgerUsbTransportEnabled) LedgerConnectionType.usb,
    ]);
  });

  test('USB is offered only on Android with the flag on', () {
    for (final platform in TargetPlatform.values) {
      for (final usb in [false, true]) {
        final expected = [
          LedgerConnectionType.bluetooth,
          if (usb && platform == TargetPlatform.android)
            LedgerConnectionType.usb,
        ];
        expect(
            availableLedgerTransports(platform: platform, usbEnabled: usb),
            expected,
            reason: '$platform usb=$usb');
      }
    }
  });

  testWidgets('Android with the flag on offers USB and rescans on choice',
      (tester) async {
    final service = await _openPicker(tester,
        platform: TargetPlatform.android, usbFlag: true);
    expect(service.scans, [LedgerConnectionType.bluetooth]);
    expect(find.byKey(_bluetoothKey), findsOneWidget);
    expect(find.byKey(_usbKey), findsOneWidget);

    await tester.tap(find.byKey(_usbKey));
    await tester.pumpAndSettle();
    expect(service.scans,
        [LedgerConnectionType.bluetooth, LedgerConnectionType.usb]);
    expect(
        find.text(
            'Make sure your Ledger is unlocked and connected with a USB cable.'),
        findsOneWidget);

    // Choosing the transport already selected does not rescan.
    await tester.tap(find.byKey(_usbKey));
    await tester.pumpAndSettle();
    expect(service.scans.length, 2);
  });

  testWidgets('Android with the flag off stays Bluetooth only',
      (tester) async {
    final service = await _openPicker(tester,
        platform: TargetPlatform.android, usbFlag: false);
    expect(service.scans, [LedgerConnectionType.bluetooth]);
    expect(find.byKey(_usbKey), findsNothing);
    expect(find.byKey(_bluetoothKey), findsNothing);
  });

  testWidgets('iOS never offers USB, even with the flag on', (tester) async {
    final service =
        await _openPicker(tester, platform: TargetPlatform.iOS, usbFlag: true);
    expect(service.scans, [LedgerConnectionType.bluetooth]);
    expect(find.byKey(_usbKey), findsNothing);
  });
}
