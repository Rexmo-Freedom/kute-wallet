// lib/services/hardware/ledger/eth/eth_app_config_operation.dart
//
// GET_APP_CONFIGURATION (E0 06, `ethapp.adoc:178-179`).
// Response: flags(1) | major(1) | minor(1) | patch(1).

import 'dart:typed_data';

import 'package:kute/services/hardware/ledger/eth/eth_apdu_common.dart';
import 'package:kute/services/hardware/ledger/ledger_os_operations.dart';

LedgerApdu ethAppConfigApdu() =>
    LedgerApdu(kEthCla, kEthInsGetAppConfiguration, 0x00, 0x00);

class EthAppConfig {
  const EthAppConfig({required this.flags, required this.version});

  final int flags;
  final LedgerSemver version;

  bool supports(LedgerSemver minimum) => !(version < minimum);
}

EthAppConfig parseEthAppConfig(Uint8List payload) {
  if (payload.length < 4) {
    throw const FormatException('Truncated app configuration');
  }
  return EthAppConfig(
    flags: payload[0],
    version: LedgerSemver(payload[1], payload[2], payload[3]),
  );
}
