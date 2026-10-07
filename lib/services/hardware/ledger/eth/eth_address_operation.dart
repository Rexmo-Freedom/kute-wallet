// lib/services/hardware/ledger/eth/eth_address_operation.dart
//
// GET_ETH_PUBLIC_ADDRESS (E0 02, `ethapp.adoc:64-65`).
//   P1 0x00 return address, 0x01 display address and confirm first
//   P2 0x00 no chain code
//   data: BIP32 path
// Response: pubKeyLen | uncompressed pubkey | addressLen | address as
// ASCII hex (no 0x).

import 'dart:convert';
import 'dart:typed_data';

import 'package:kute/services/hardware/ledger/eth/eth_apdu_common.dart';
import 'package:kute/services/hardware/ledger/ledger_os_operations.dart';

LedgerApdu ethGetAddressApdu({
  String path = kLedgerEvmDerivationPath,
  required bool display,
}) =>
    LedgerApdu(kEthCla, kEthInsGetAddress, display ? 0x01 : 0x00, 0x00,
        packBip32Path(path));

class EthAddressResponse {
  const EthAddressResponse({required this.publicKey, required this.address});

  /// 65-byte uncompressed public key.
  final Uint8List publicKey;

  /// 0x-prefixed address exactly as the device reported it.
  final String address;
}

EthAddressResponse parseEthAddressResponse(Uint8List payload) {
  if (payload.isEmpty) {
    throw const FormatException('Empty address response');
  }
  final pubLen = payload[0];
  if (1 + pubLen >= payload.length) {
    throw const FormatException('Truncated public key');
  }
  final publicKey = Uint8List.fromList(payload.sublist(1, 1 + pubLen));
  final addrLen = payload[1 + pubLen];
  final start = 2 + pubLen;
  if (addrLen != 40 || start + addrLen > payload.length) {
    throw const FormatException('Unexpected address length');
  }
  final hex = ascii.decode(payload.sublist(start, start + addrLen));
  if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(hex)) {
    throw const FormatException('Address is not hex');
  }
  return EthAddressResponse(publicKey: publicKey, address: '0x$hex');
}
