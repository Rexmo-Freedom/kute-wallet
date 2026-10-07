// lib/services/hardware/eip712_typed_data.dart
//
// Full EIP-712 typed data with one generic encoder (Wallet hardening
// Phase 3, plan B3). Every builder that already produces EIP-712 hashes
// (Hyperliquid, Polymarket, DepositWallet Batch) also produces an
// [Eip712TypedData]; tests pin the generic hash equal to each builder,
// and the external signing path re-checks that equality at runtime
// before any device prompt.
//
// Supported: nested structs, arrays (dynamic and fixed, any depth),
// string, bytes, bool, address, uintN, intN, bytesN. Values are strict:
// a missing or extra field throws instead of encoding a silent zero.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/keccak.dart';

class Eip712Field {
  const Eip712Field(this.name, this.type);

  final String name;
  final String type;

  @override
  bool operator ==(Object other) =>
      other is Eip712Field && other.name == name && other.type == type;

  @override
  int get hashCode => Object.hash(name, type);

  @override
  String toString() => '$type $name';
}

const String kEip712DomainType = 'EIP712Domain';

/// The four-field domain type most builders use.
const List<Eip712Field> kEip712DomainFields = [
  Eip712Field('name', 'string'),
  Eip712Field('version', 'string'),
  Eip712Field('chainId', 'uint256'),
  Eip712Field('verifyingContract', 'address'),
];

class Eip712TypedData {
  Eip712TypedData({
    required Map<String, List<Eip712Field>> types,
    required this.primaryType,
    required Map<String, Object?> domain,
    required Map<String, Object?> message,
  })  : types = Map<String, List<Eip712Field>>.unmodifiable(
            <String, List<Eip712Field>>{
          for (final e in types.entries)
            e.key: List<Eip712Field>.unmodifiable(e.value),
        }),
        domain = Map.unmodifiable(domain),
        message = Map.unmodifiable(message) {
    if (!this.types.containsKey(kEip712DomainType)) {
      throw ArgumentError('Typed data must declare EIP712Domain');
    }
    if (!this.types.containsKey(primaryType)) {
      throw ArgumentError('Primary type is not declared');
    }
    if (primaryType == kEip712DomainType) {
      throw ArgumentError('Primary type cannot be EIP712Domain');
    }
    for (final entry in this.types.entries) {
      final seen = <String>{};
      for (final field in entry.value) {
        if (!seen.add(field.name)) {
          throw ArgumentError('Duplicate field in ${entry.key}');
        }
        final base = baseType(field.type);
        if (!isPrimitiveType(base) && !this.types.containsKey(base)) {
          throw ArgumentError('Unknown type $base');
        }
      }
    }
  }

  /// Declaration order is preserved; the Ledger definition frames follow it.
  final Map<String, List<Eip712Field>> types;
  final String primaryType;
  final Map<String, Object?> domain;
  final Map<String, Object?> message;

  Uint8List get domainSeparator => hashStruct(kEip712DomainType, domain);

  Uint8List get structHash => hashStruct(primaryType, message);

  Uint8List get digest => _keccak(
      Uint8List.fromList([0x19, 0x01, ...domainSeparator, ...structHash]));

  // ───────────────────────────── type encoding ──────────────────────────

  /// Strips every array suffix: `Call[]` -> `Call`, `uint8[2][]` -> `uint8`.
  static String baseType(String type) {
    final i = type.indexOf('[');
    return i < 0 ? type : type.substring(0, i);
  }

  static bool isArrayType(String type) => type.endsWith(']');

  /// Solidity semantics: the outermost dimension is the last bracket.
  static String arrayElementType(String type) {
    final i = type.lastIndexOf('[');
    if (i < 0 || !type.endsWith(']')) {
      throw ArgumentError('Not an array type');
    }
    return type.substring(0, i);
  }

  static int? arrayFixedLength(String type) {
    final i = type.lastIndexOf('[');
    final inner = type.substring(i + 1, type.length - 1);
    return inner.isEmpty ? null : int.parse(inner);
  }

  static bool isPrimitiveType(String base) {
    if (const {'address', 'bool', 'string', 'bytes'}.contains(base)) {
      return true;
    }
    final m = RegExp(r'^(u?int|bytes)(\d+)$').firstMatch(base);
    if (m == null) return false;
    final n = int.parse(m.group(2)!);
    return m.group(1) == 'bytes'
        ? n >= 1 && n <= 32
        : n >= 8 && n <= 256 && n % 8 == 0;
  }

  Set<String> _dependencies(String name, [Set<String>? found]) {
    final out = found ?? <String>{};
    if (out.contains(name) || !types.containsKey(name)) return out;
    out.add(name);
    for (final field in types[name]!) {
      final base = baseType(field.type);
      if (types.containsKey(base)) _dependencies(base, out);
    }
    return out;
  }

  /// `Primary(fields)` followed by referenced types sorted by name.
  String encodeType(String name) {
    final deps = _dependencies(name)..remove(name);
    final ordered = [name, ...deps.toList()..sort()];
    return ordered
        .map((t) =>
            '$t(${types[t]!.map((f) => '${f.type} ${f.name}').join(',')})')
        .join();
  }

  Uint8List typeHash(String name) => _keccak(utf8.encode(encodeType(name)));

  Uint8List hashStruct(String name, Map<String, Object?> data) {
    final fields = types[name];
    if (fields == null) throw ArgumentError('Unknown struct $name');
    final names = fields.map((f) => f.name).toSet();
    for (final key in data.keys) {
      if (!names.contains(key)) {
        throw ArgumentError('Unexpected field $key in $name');
      }
    }
    final out = BytesBuilder(copy: false)..add(typeHash(name));
    for (final field in fields) {
      if (!data.containsKey(field.name) || data[field.name] == null) {
        throw ArgumentError('Missing field ${field.name} in $name');
      }
      out.add(encodeValue(field.type, data[field.name]));
    }
    return _keccak(out.toBytes());
  }

  /// The 32-byte `encodeData` word for one value.
  Uint8List encodeValue(String type, Object? value) {
    if (value == null) throw ArgumentError('Null value for $type');
    if (isArrayType(type)) {
      if (value is! List) throw ArgumentError('Expected a list for $type');
      final fixed = arrayFixedLength(type);
      if (fixed != null && value.length != fixed) {
        throw ArgumentError('Expected $fixed items for $type');
      }
      final element = arrayElementType(type);
      final out = BytesBuilder(copy: false);
      for (final item in value) {
        out.add(encodeValue(element, item));
      }
      return _keccak(out.toBytes());
    }
    if (types.containsKey(type)) {
      if (value is! Map) throw ArgumentError('Expected a map for $type');
      return hashStruct(type, Map<String, Object?>.from(value));
    }
    switch (type) {
      case 'string':
        if (value is! String) throw ArgumentError('Expected a string');
        return _keccak(utf8.encode(value));
      case 'bytes':
        return _keccak(eip712Bytes(value));
      case 'bool':
        if (value is! bool) throw ArgumentError('Expected a bool');
        return _word(value ? BigInt.one : BigInt.zero);
      case 'address':
        final bytes = eip712AddressBytes(value);
        return Uint8List(32)..setRange(12, 32, bytes);
    }
    final sized = RegExp(r'^(u?int|bytes)(\d+)$').firstMatch(type);
    if (sized == null) throw ArgumentError('Unsupported type $type');
    final n = int.parse(sized.group(2)!);
    if (sized.group(1) == 'bytes') {
      final bytes = eip712Bytes(value);
      if (bytes.length != n) {
        throw ArgumentError('Expected $n bytes for $type');
      }
      return Uint8List(32)..setRange(0, n, bytes);
    }
    final big = eip712Integer(value);
    if (sized.group(1) == 'uint') {
      if (big.isNegative || big.bitLength > n) {
        throw ArgumentError('Value out of range for $type');
      }
      return _word(big);
    }
    final limit = BigInt.one << (n - 1);
    if (big >= limit || big < -limit) {
      throw ArgumentError('Value out of range for $type');
    }
    return _word(big.isNegative ? (BigInt.one << 256) + big : big);
  }
}

// ───────────────────────────── value coercion ───────────────────────────

/// int, BigInt, decimal string, or 0x hex string.
BigInt eip712Integer(Object value) {
  if (value is BigInt) return value;
  if (value is int) return BigInt.from(value);
  if (value is String) {
    final s = value.trim();
    final parsed = s.startsWith('0x') || s.startsWith('0X')
        ? BigInt.tryParse(s.substring(2), radix: 16)
        : BigInt.tryParse(s);
    if (parsed != null) return parsed;
  }
  throw ArgumentError('Expected an integer');
}

/// `Uint8List`, `List<int>`, or 0x hex string.
Uint8List eip712Bytes(Object value) {
  if (value is Uint8List) return value;
  if (value is List<int>) return Uint8List.fromList(value);
  if (value is String) {
    final clean = value.startsWith('0x') ? value.substring(2) : value;
    if (clean.length.isEven && RegExp(r'^[0-9a-fA-F]*$').hasMatch(clean)) {
      return Uint8List.fromList([
        for (var i = 0; i < clean.length; i += 2)
          int.parse(clean.substring(i, i + 2), radix: 16),
      ]);
    }
  }
  throw ArgumentError('Expected bytes');
}

Uint8List eip712AddressBytes(Object value) {
  final bytes = eip712Bytes(value);
  if (bytes.length != 20) throw ArgumentError('Address must be 20 bytes');
  return bytes;
}

Uint8List _word(BigInt value) {
  final out = Uint8List(32);
  var v = value;
  for (var i = 31; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  return out;
}

Uint8List _keccak(List<int> data) =>
    KeccakDigest(256).process(Uint8List.fromList(data));
