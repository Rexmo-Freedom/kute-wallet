// lib/services/hardware/ledger/eth/eth_personal_sign_operation.dart
//
// SIGN_ETH_PERSONAL_MESSAGE (E0 08, `ethapp.adoc:222-223`).
//   first frame  P1 0x00: BIP32 path | message length (4 bytes BE) | chunk
//   later frames P1 0x80: chunk
// The device prompts after the last frame; the response is v | r | s.

import 'dart:typed_data';

import 'package:kute/services/hardware/ledger/eth/eth_apdu_common.dart';
import 'package:kute/services/hardware/ledger/ledger_os_operations.dart';

List<LedgerApdu> ethPersonalSignApdus({
  String path = kLedgerEvmDerivationPath,
  required Uint8List message,
}) {
  final pathBytes = packBip32Path(path);
  final header = ByteData(4)..setUint32(0, message.length);
  final firstRoom = 255 - pathBytes.length - 4;
  final firstEnd = message.length < firstRoom ? message.length : firstRoom;
  final frames = <LedgerApdu>[
    LedgerApdu(kEthCla, kEthInsSignPersonalMessage, 0x00, 0x00, [
      ...pathBytes,
      ...header.buffer.asUint8List(),
      ...message.sublist(0, firstEnd),
    ]),
  ];
  for (var offset = firstEnd; offset < message.length; offset += 255) {
    final end = offset + 255 < message.length ? offset + 255 : message.length;
    frames.add(LedgerApdu(kEthCla, kEthInsSignPersonalMessage, 0x80, 0x00,
        message.sublist(offset, end)));
  }
  return frames;
}
