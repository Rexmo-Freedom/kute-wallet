// lib/services/hardware/ledger/eth/eth_eip712_operations.dart
//
// Full EIP-712 signing frames for the Ethereum app (`ethapp.adoc`):
//
//   EIP712_SEND_STRUCT_DEFINITION     E0 1A  (:636-637)
//     P2 0x00 struct name   data: name
//     P2 0xFF struct field  data: TypeDesc | [TypeNameLen TypeName]
//                                 | [TypeSize] | [ArrayLevelCount levels]
//                                 | KeyNameLen KeyName
//   EIP712_SEND_STRUCT_IMPLEMENTATION E0 1C  (:755-756)
//     P1 0x00 complete, 0x01 partial (more chunks follow)
//     P2 0x00 root struct   data: name ("EIP712Domain" or primary type)
//     P2 0x0F array         data: element count (1 byte)
//     P2 0xFF field         data: value length (2 bytes BE) | value,
//                                 chunked in 255-byte frames
//   SIGN_ETH_EIP_712                  E0 0C  (:328-332)
//     P2 0x01 full implementation   data: BIP32 path
//
// Hash-only mode (P2 0x00) is blind signing and has no builder here.
// Field order follows the type declaration; the device rebuilds and
// hashes the typed data itself, so any drift fails signature recovery.

import 'dart:convert';
import 'dart:typed_data';

import 'package:kute/services/hardware/eip712_typed_data.dart';
import 'package:kute/services/hardware/ledger/eth/eth_apdu_common.dart';
import 'package:kute/services/hardware/ledger/ledger_os_operations.dart';

const int _p2StructName = 0x00;
const int _p2StructField = 0xFF;
const int _p2Root = 0x00;
const int _p2Array = 0x0F;
const int _p1Complete = 0x00;
const int _p1Partial = 0x01;

const int _typeCustom = 0;
const int _typeInt = 1;
const int _typeUint = 2;
const int _typeAddress = 3;
const int _typeBool = 4;
const int _typeString = 5;
const int _typeFixedBytes = 6;
const int _typeDynamicBytes = 7;

LedgerApdu eip712StructNameApdu(String name) => LedgerApdu(kEthCla,
    kEthInsEip712StructDefinition, 0x00, _p2StructName, utf8.encode(name));

/// Encodes one struct field definition.
Uint8List eip712FieldDefinition(Eip712TypedData typedData, Eip712Field field) {
  final base = Eip712TypedData.baseType(field.type);
  final levels = RegExp(r'\[(\d*)\]')
      .allMatches(field.type)
      .map((m) => m.group(1)!.isEmpty ? null : int.parse(m.group(1)!))
      .toList();
  if (levels.length > 1) {
    throw UnsupportedError('Multi-dimensional arrays are not sent to Ledger');
  }

  int typeId;
  int? size;
  if (typedData.types.containsKey(base)) {
    typeId = _typeCustom;
  } else if (base == 'address') {
    typeId = _typeAddress;
  } else if (base == 'bool') {
    typeId = _typeBool;
  } else if (base == 'string') {
    typeId = _typeString;
  } else if (base == 'bytes') {
    typeId = _typeDynamicBytes;
  } else {
    final m = RegExp(r'^(uint|int|bytes)(\d+)$').firstMatch(base);
    if (m == null || !Eip712TypedData.isPrimitiveType(base)) {
      throw ArgumentError('Unsupported EIP-712 type $base');
    }
    final n = int.parse(m.group(2)!);
    switch (m.group(1)) {
      case 'uint':
        typeId = _typeUint;
        size = n ~/ 8;
      case 'int':
        typeId = _typeInt;
        size = n ~/ 8;
      default:
        typeId = _typeFixedBytes;
        size = n;
    }
  }

  final key = utf8.encode(field.name);
  final out = BytesBuilder(copy: false)
    ..addByte((levels.isNotEmpty ? 0x80 : 0) |
        (size != null ? 0x40 : 0) |
        typeId);
  if (typeId == _typeCustom) {
    final name = utf8.encode(base);
    out
      ..addByte(name.length)
      ..add(name);
  }
  if (size != null) out.addByte(size);
  if (levels.isNotEmpty) {
    out.addByte(levels.length);
    for (final level in levels) {
      if (level == null) {
        out.addByte(0x00);
      } else {
        out
          ..addByte(0x01)
          ..addByte(level);
      }
    }
  }
  out
    ..addByte(key.length)
    ..add(key);
  return out.toBytes();
}

/// Every struct name and field definition, in declaration order.
List<LedgerApdu> eip712DefinitionApdus(Eip712TypedData typedData) => [
      for (final entry in typedData.types.entries) ...[
        eip712StructNameApdu(entry.key),
        for (final field in entry.value)
          LedgerApdu(kEthCla, kEthInsEip712StructDefinition, 0x00,
              _p2StructField, eip712FieldDefinition(typedData, field)),
      ],
    ];

/// Device value encoding: integers as minimal big-endian bytes (two's
/// complement within the type size when negative), bool as one byte,
/// address as 20 bytes, string as UTF-8, bytes as raw bytes.
Uint8List eip712FieldValue(String type, Object value) {
  switch (type) {
    case 'string':
      if (value is! String) throw ArgumentError('Expected a string');
      return Uint8List.fromList(utf8.encode(value));
    case 'bool':
      if (value is! bool) throw ArgumentError('Expected a bool');
      return Uint8List.fromList([value ? 1 : 0]);
    case 'address':
      return eip712AddressBytes(value);
    case 'bytes':
      return eip712Bytes(value);
  }
  final m = RegExp(r'^(uint|int|bytes)(\d+)$').firstMatch(type);
  if (m == null) throw ArgumentError('Unsupported EIP-712 type $type');
  final n = int.parse(m.group(2)!);
  if (m.group(1) == 'bytes') {
    final bytes = eip712Bytes(value);
    if (bytes.length != n) throw ArgumentError('Expected $n bytes');
    return bytes;
  }
  var big = eip712Integer(value);
  if (big.isNegative) {
    if (m.group(1) == 'uint') throw ArgumentError('Negative uint');
    big = (BigInt.one << n) + big;
  }
  return _minimalBigEndian(big);
}

Uint8List _minimalBigEndian(BigInt value) {
  if (value == BigInt.zero) return Uint8List.fromList([0]);
  final out = <int>[];
  var v = value;
  while (v > BigInt.zero) {
    out.insert(0, (v & BigInt.from(0xff)).toInt());
    v = v >> 8;
  }
  return Uint8List.fromList(out);
}

List<LedgerApdu> _fieldValueApdus(Uint8List value) {
  if (value.length > 0xFFFF) {
    throw ArgumentError('EIP-712 field value too large');
  }
  final data = Uint8List.fromList(
      [(value.length >> 8) & 0xff, value.length & 0xff, ...value]);
  final frames = <LedgerApdu>[];
  for (var offset = 0; offset < data.length; offset += 255) {
    final end = offset + 255 < data.length ? offset + 255 : data.length;
    frames.add(LedgerApdu(
      kEthCla,
      kEthInsEip712StructImplementation,
      end < data.length ? _p1Partial : _p1Complete,
      _p2StructField,
      data.sublist(offset, end),
    ));
  }
  return frames;
}

void _walkField(Eip712TypedData typedData, String type, Object? value,
    List<LedgerApdu> out) {
  if (value == null) throw ArgumentError('Null value for $type');
  if (Eip712TypedData.isArrayType(type)) {
    if (value is! List) throw ArgumentError('Expected a list for $type');
    if (value.length > 255) {
      throw ArgumentError('Arrays over 255 items are not sent to Ledger');
    }
    out.add(LedgerApdu(kEthCla, kEthInsEip712StructImplementation,
        _p1Complete, _p2Array, [value.length]));
    final element = Eip712TypedData.arrayElementType(type);
    for (final item in value) {
      _walkField(typedData, element, item, out);
    }
    return;
  }
  if (typedData.types.containsKey(type)) {
    if (value is! Map) throw ArgumentError('Expected a map for $type');
    _walkStruct(typedData, type, Map<String, Object?>.from(value), out);
    return;
  }
  out.addAll(_fieldValueApdus(eip712FieldValue(type, value)));
}

void _walkStruct(Eip712TypedData typedData, String name,
    Map<String, Object?> data, List<LedgerApdu> out) {
  for (final field in typedData.types[name]!) {
    if (!data.containsKey(field.name)) {
      throw ArgumentError('Missing field ${field.name} in $name');
    }
    _walkField(typedData, field.type, data[field.name], out);
  }
}

/// Domain then message implementation frames.
List<LedgerApdu> eip712ImplementationApdus(Eip712TypedData typedData) {
  final out = <LedgerApdu>[];
  for (final (root, data) in [
    (kEip712DomainType, typedData.domain),
    (typedData.primaryType, typedData.message),
  ]) {
    out.add(LedgerApdu(kEthCla, kEthInsEip712StructImplementation,
        _p1Complete, _p2Root, utf8.encode(root)));
    _walkStruct(typedData, root, data, out);
  }
  return out;
}

/// Definitions then implementations; everything before the sign frame.
List<LedgerApdu> eip712PayloadApdus(Eip712TypedData typedData) =>
    [...eip712DefinitionApdus(typedData), ...eip712ImplementationApdus(typedData)];

/// SIGN_ETH_EIP_712 in full-implementation mode (P2 0x01). The device
/// prompts on this frame.
LedgerApdu eip712SignFullApdu({String path = kLedgerEvmDerivationPath}) =>
    LedgerApdu(kEthCla, kEthInsSignEip712, 0x00, 0x01, packBip32Path(path));
