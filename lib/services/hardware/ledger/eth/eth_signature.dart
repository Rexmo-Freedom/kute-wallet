// lib/services/hardware/ledger/eth/eth_signature.dart
//
// Signature responses from SIGN_ETH_PERSONAL_MESSAGE and SIGN_ETH_EIP_712:
// v(1) | r(32) | s(32). Personal and EIP-712 signatures carry v 27 or 28;
// 0 or 1 is normalized for safety. Any other v fails closed.

import 'dart:typed_data';

import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthSignature;

EthSignature parseEthSignatureResponse(Uint8List payload) {
  if (payload.length != 65) {
    throw const FormatException('Signature response must be 65 bytes');
  }
  var v = payload[0];
  if (v == 0 || v == 1) v += 27;
  if (v != 27 && v != 28) {
    throw const FormatException('Unexpected signature recovery id');
  }
  BigInt read(int start) {
    var out = BigInt.zero;
    for (var i = start; i < start + 32; i++) {
      out = (out << 8) | BigInt.from(payload[i]);
    }
    return out;
  }

  return EthSignature(read(1), read(33), v);
}
