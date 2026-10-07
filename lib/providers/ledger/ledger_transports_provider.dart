// lib/providers/ledger/ledger_transports_provider.dart
//
// Which Ledger transports the device picker offers. Injectable in place of
// `Platform.isAndroid` (ledger_service.dart) so widget tests can cover
// both platforms and both flag states.
//
// Bluetooth is always offered first (today's behaviour). USB is added only
// on Android with `kLedgerUsbTransportEnabled` on (O16).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/constants/feature_flags.dart';
import 'package:kute/services/ledger_service.dart';

final ledgerUsbTransportFlagProvider =
    Provider<bool>((ref) => kLedgerUsbTransportEnabled);

final ledgerTransportPlatformProvider =
    Provider<TargetPlatform>((ref) => defaultTargetPlatform);

List<LedgerConnectionType> availableLedgerTransports({
  required TargetPlatform platform,
  required bool usbEnabled,
}) =>
    [
      LedgerConnectionType.bluetooth,
      if (usbEnabled && platform == TargetPlatform.android)
        LedgerConnectionType.usb,
    ];

final ledgerTransportsProvider = Provider<List<LedgerConnectionType>>(
  (ref) => availableLedgerTransports(
    platform: ref.watch(ledgerTransportPlatformProvider),
    usbEnabled: ref.watch(ledgerUsbTransportFlagProvider),
  ),
);
