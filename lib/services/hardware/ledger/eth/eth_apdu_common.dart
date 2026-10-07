// lib/services/hardware/ledger/eth/eth_apdu_common.dart
//
// Shared constants and BIP32 path packing for the Ethereum app APDUs
// (app-ethereum `doc/ethapp.adoc`).

import 'dart:typed_data';

import 'package:kute/services/hardware/ledger/ledger_os_operations.dart';

const int kEthCla = 0xE0;

const int kEthInsGetAddress = 0x02;
const int kEthInsSignTransaction = 0x04;
const int kEthInsGetAppConfiguration = 0x06;
const int kEthInsSignPersonalMessage = 0x08;
const int kEthInsSignEip712 = 0x0C;
const int kEthInsEip712StructDefinition = 0x1A;
const int kEthInsEip712StructImplementation = 0x1C;

/// O5: index 0 only.
const String kLedgerEvmDerivationPath = "m/44'/60'/0'/0/0";

/// Full EIP-712 needs Ethereum app 1.9.19 or later (`ethapp.adoc:318-320`).
/// The real minimum is set by the device matrix (O13).
const LedgerSemver kLedgerEthMinimumAppVersion = LedgerSemver(1, 9, 19);

const int _hardened = 0x80000000;

/// Parses `m/44'/60'/0'/0/0` into BIP32 indices.
List<int> parseBip32Path(String path) {
  final parts = path.trim().split('/');
  if (parts.isEmpty || parts.first != 'm') {
    throw ArgumentError('BIP32 path must start with m');
  }
  final out = <int>[];
  for (final part in parts.skip(1)) {
    final hardened = part.endsWith("'") || part.endsWith('h');
    final digits = hardened ? part.substring(0, part.length - 1) : part;
    final index = int.tryParse(digits);
    if (index == null || index < 0 || index >= _hardened) {
      throw ArgumentError('Invalid BIP32 path component');
    }
    out.add(hardened ? index + _hardened : index);
  }
  if (out.isEmpty || out.length > 10) {
    throw ArgumentError('BIP32 path must have 1 to 10 components');
  }
  return out;
}

/// Count byte followed by each index as 4 bytes big endian.
Uint8List packBip32Path(String path) {
  final indices = parseBip32Path(path);
  final data = ByteData(1 + 4 * indices.length);
  data.setUint8(0, indices.length);
  for (var i = 0; i < indices.length; i++) {
    data.setUint32(1 + 4 * i, indices[i]);
  }
  return data.buffer.asUint8List();
}
