// lib/services/hyperliquid/hyperliquid_msgpack.dart
//
// Minimal msgpack encoder for Hyperliquid /exchange action hashing.
//
// Hyperliquid's L1-action signature commits to `keccak256(msgpack(action) ++
// nonce ++ …)`, where the reference serialization is Python's
// `msgpack.packb(action)` (hyperliquid-python-sdk, signing.py). We hand-roll
// the encoder instead of depending on a msgpack package because actions only
// ever contain nil / bool / int / str / array / map — every numeric price or
// size crosses the wire as a string — and a ~120-line encoder we byte-test
// against Python vectors is a smaller risk surface than an unaudited dep.
//
// Two properties MUST hold for signatures to verify:
//   1. Integers use the smallest possible encoding (Python packb default).
//   2. Map keys serialize in INSERTION order — Dart map literals are
//      LinkedHashMaps, so action builders (hyperliquid_signing.dart) just
//      have to list fields in the exact order the Python SDK does.
//
// Doubles are rejected outright: an un-stringified price/size reaching the
// encoder is always a caller bug that would produce an unverifiable action.

import 'dart:convert';
import 'dart:typed_data';

Uint8List packMsgpack(Object? value) {
  final out = BytesBuilder(copy: false);
  _pack(value, out);
  return out.toBytes();
}

void _pack(Object? value, BytesBuilder out) {
  if (value == null) {
    out.addByte(0xc0);
  } else if (value is bool) {
    out.addByte(value ? 0xc3 : 0xc2);
  } else if (value is int) {
    _packInt(value, out);
  } else if (value is String) {
    _packString(value, out);
  } else if (value is List) {
    _packArrayHeader(value.length, out);
    for (final item in value) {
      _pack(item, out);
    }
  } else if (value is Map) {
    _packMapHeader(value.length, out);
    value.forEach((k, v) {
      if (k is! String) {
        throw ArgumentError('msgpack: map keys must be String, got $k');
      }
      _packString(k, out);
      _pack(v, out);
    });
  } else if (value is double) {
    throw ArgumentError(
        'msgpack: doubles are not allowed in Hyperliquid actions — '
        'prices/sizes must be wire strings (floatToWire)');
  } else {
    throw ArgumentError('msgpack: unsupported type ${value.runtimeType}');
  }
}

void _packInt(int value, BytesBuilder out) {
  if (value >= 0) {
    if (value <= 0x7f) {
      out.addByte(value); // positive fixint
    } else if (value <= 0xff) {
      out.addByte(0xcc); // uint8
      out.addByte(value);
    } else if (value <= 0xffff) {
      out.addByte(0xcd); // uint16
      out.add(_beBytes(value, 2));
    } else if (value <= 0xffffffff) {
      out.addByte(0xce); // uint32
      out.add(_beBytes(value, 4));
    } else {
      out.addByte(0xcf); // uint64
      out.add(_beBytes(value, 8));
    }
  } else {
    if (value >= -32) {
      out.addByte(0xe0 | (value + 32)); // negative fixint
    } else if (value >= -128) {
      out.addByte(0xd0); // int8
      out.addByte(value & 0xff);
    } else if (value >= -32768) {
      out.addByte(0xd1); // int16
      out.add(_beBytes(value, 2));
    } else if (value >= -2147483648) {
      out.addByte(0xd2); // int32
      out.add(_beBytes(value, 4));
    } else {
      out.addByte(0xd3); // int64
      out.add(_beBytes(value, 8));
    }
  }
}

void _packString(String value, BytesBuilder out) {
  final bytes = utf8.encode(value);
  final len = bytes.length;
  if (len <= 31) {
    out.addByte(0xa0 | len); // fixstr
  } else if (len <= 0xff) {
    out.addByte(0xd9); // str8
    out.addByte(len);
  } else if (len <= 0xffff) {
    out.addByte(0xda); // str16
    out.add(_beBytes(len, 2));
  } else {
    out.addByte(0xdb); // str32
    out.add(_beBytes(len, 4));
  }
  out.add(bytes);
}

void _packArrayHeader(int len, BytesBuilder out) {
  if (len <= 15) {
    out.addByte(0x90 | len); // fixarray
  } else if (len <= 0xffff) {
    out.addByte(0xdc); // array16
    out.add(_beBytes(len, 2));
  } else {
    out.addByte(0xdd); // array32
    out.add(_beBytes(len, 4));
  }
}

void _packMapHeader(int len, BytesBuilder out) {
  if (len <= 15) {
    out.addByte(0x80 | len); // fixmap
  } else if (len <= 0xffff) {
    out.addByte(0xde); // map16
    out.add(_beBytes(len, 2));
  } else {
    out.addByte(0xdf); // map32
    out.add(_beBytes(len, 4));
  }
}

/// Big-endian two's-complement truncation of [value] to [width] bytes.
Uint8List _beBytes(int value, int width) {
  final bytes = Uint8List(width);
  var v = value;
  for (var i = width - 1; i >= 0; i--) {
    bytes[i] = v & 0xff;
    v >>= 8;
  }
  return bytes;
}
