import 'dart:typed_data';
import 'dart:io';

/// Pure Dart implementation of the BBQr protocol (Better Bitcoin QR).
/// Spec: https://github.com/coinkite/BBQr/blob/master/BBQr.md
///
/// BBQr encodes binary data across one or more QR codes using the
/// alphanumeric character set (0-9 A-Z $ % * + - . / :).

// ── Constants ──────────────────────────────────────────────────────────

const _base36Chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// Alphanumeric capacity per QR version at ECC level L.
const _qrAlnumCapacity = <int>[
  //  v1     v2     v3     v4     v5     v6     v7     v8     v9    v10
      25,    47,    77,   114,   154,   195,   224,   279,   335,   395,
  // v11    v12    v13    v14    v15    v16    v17    v18    v19    v20
     468,   535,   619,   667,   758,   854,   938,  1046,  1153,  1249,
  // v21    v22    v23    v24    v25    v26    v27    v28    v29    v30
    1352,  1460,  1588,  1704,  1853,  1990,  2132,  2223,  2369,  2520,
  // v31    v32    v33    v34    v35    v36    v37    v38    v39    v40
    2677,  2840,  3009,  3183,  3351,  3537,  3729,  3927,  4087,  4296,
];

// ── File Types ─────────────────────────────────────────────────────────

enum BbqrFileType {
  psbt('P'),
  transaction('T'),
  json('J'),
  cbor('C'),
  unicode('U'),
  binary('B');

  final String code;
  const BbqrFileType(this.code);

  static BbqrFileType? fromCode(String c) {
    for (final t in values) {
      if (t.code == c) return t;
    }
    return null;
  }
}

// ── Encoding Types ─────────────────────────────────────────────────────

enum BbqrEncoding {
  hex('H'),
  zlib('Z');

  final String code;
  const BbqrEncoding(this.code);

  static BbqrEncoding? fromCode(String c) {
    for (final e in values) {
      if (e.code == c) return e;
    }
    return null;
  }
}

// ── Encoder ────────────────────────────────────────────────────────────

class BbqrSplit {
  final List<String> parts;
  final BbqrEncoding encoding;
  final BbqrFileType fileType;
  final int version; // QR version used (1-40)

  BbqrSplit._({
    required this.parts,
    required this.encoding,
    required this.fileType,
    required this.version,
  });

  /// Split [data] into BBQr parts.
  ///
  /// [minVersion] / [maxVersion] constrain the QR version (1-40).
  /// Lower versions = smaller QR = easier to scan, but more parts.
  /// Default targets version 27 (125x125, sweet spot per spec).
  static BbqrSplit encode({
    required Uint8List data,
    BbqrFileType fileType = BbqrFileType.psbt,
    int minVersion = 5,
    int maxVersion = 40,
    int? maxParts,
    bool tryZlib = true,
  }) {
    // Try zlib compression first
    Uint8List payload = data;
    BbqrEncoding encoding = BbqrEncoding.hex;

    if (tryZlib) {
      try {
        final compressed = _zlibCompress(data);
        if (compressed.length < data.length) {
          payload = compressed;
          encoding = BbqrEncoding.zlib;
        }
      } catch (_) {
        // Fall back to hex
      }
    }

    // Encode payload to alphanumeric string
    final encoded = _encodePayload(payload, encoding);

    // Header is 8 chars: B$ + encoding + fileType + 2-digit count + 2-digit index
    const headerLen = 8;

    // Find optimal QR version and split count
    final (version, numParts) = _findOptimalSplit(
      encoded.length,
      headerLen,
      minVersion: minVersion,
      maxVersion: maxVersion,
      maxParts: maxParts,
    );

    // Split encoded data into equal parts (last may be shorter)
    final capacity = _qrAlnumCapacity[version - 1] - headerLen;
    final chunkSize = (encoded.length / numParts).ceil();
    // Hex encoding: must be even chars per chunk (each byte = 2 hex chars)
    final adjustedChunkSize = encoding == BbqrEncoding.hex
        ? (chunkSize % 2 == 0 ? chunkSize : chunkSize + 1)
        : chunkSize;
    final finalChunkSize = adjustedChunkSize > capacity ? capacity : adjustedChunkSize;

    final totalB36 = _toBase36(numParts, 2);
    final headerPrefix = 'B\$${encoding.code}${fileType.code}$totalB36';

    final parts = <String>[];
    for (int i = 0; i < numParts; i++) {
      final start = i * finalChunkSize;
      final end = start + finalChunkSize > encoded.length
          ? encoded.length
          : start + finalChunkSize;
      final chunk = encoded.substring(start, end);
      final indexB36 = _toBase36(i, 2);
      parts.add('$headerPrefix$indexB36$chunk');
    }

    return BbqrSplit._(
      parts: parts,
      encoding: encoding,
      fileType: fileType,
      version: version,
    );
  }

  /// Find QR version + part count, biased toward sizes hardware
  /// signer cameras can actually read.
  ///
  /// The previous "smallest version that fits" algorithm picked v5
  /// (37×37 modules) for typical PSBT sizes — device cameras
  /// dropped 7 of 8 frames because the modules were physically too
  /// small to resolve at scanning distance. The Python BBQr reference
  /// (and the spec recommendation) prefers v27+ for the readability
  /// sweet spot.
  ///
  /// Algorithm matches `coinkite/BBQr` python reference:
  ///   1. Try `v27 → v32 → v37 → v40` in order. First version where
  ///      the encoded payload fits in a SINGLE part is chosen — this
  ///      keeps the QR as small as possible while still being big
  ///      enough to scan.
  ///   2. If even v40 can't fit one part, fall back to a multi-part
  ///      split at the user's `maxVersion` (still bounded above by
  ///      v40), preferring fewer-but-bigger codes over
  ///      many-tiny ones. Each part takes the full per-version
  ///      capacity; we take ceil(len/cap) parts.
  static (int version, int numParts) _findOptimalSplit(
    int encodedLength,
    int headerLen, {
    int minVersion = 5,
    int maxVersion = 40,
    int? maxParts,
  }) {
    final limit = maxParts ?? 1295; // ZZ in base36
    final clampedMax = maxVersion.clamp(minVersion, 40);

    // Single-part attempt: try the spec's recommended sweet-spot
    // versions in ascending order, then any larger versions up to
    // the user's `maxVersion`. First one whose capacity covers the
    // encoded payload wins.
    const sweetSpot = [27, 32, 37, 40];
    for (final v in sweetSpot) {
      if (v < minVersion || v > clampedMax) continue;
      final capacity = _qrAlnumCapacity[v - 1] - headerLen;
      if (capacity <= 0) continue;
      if (encodedLength <= capacity) return (v, 1);
    }

    // Multi-part fallback. Always use the largest available version
    // (capped at the caller's `maxVersion` and the absolute v40 max)
    // to minimize the number of frames the scanning device has to
    // capture in a single animation cycle. Smaller versions = more parts = longer
    // scan time + more chance for a missed frame.
    final ver = clampedMax;
    final capacity = _qrAlnumCapacity[ver - 1] - headerLen;
    if (capacity <= 0) {
      // Pathological: caller forced a maxVersion smaller than the
      // header overhead. Fall back to v40 unconditionally.
      final fallbackCap = _qrAlnumCapacity[39] - headerLen;
      final needed = (encodedLength / fallbackCap).ceil();
      return (40, needed.clamp(1, limit));
    }
    final needed = (encodedLength / capacity).ceil();
    return (ver, needed.clamp(1, limit));
  }
}

// ── Decoder ────────────────────────────────────────────────────────────

class BbqrJoiner {
  BbqrEncoding? _encoding;
  BbqrFileType? _fileType;
  int _totalParts = 0;
  final Map<int, String> _received = {};

  bool get isComplete => _totalParts > 0 && _received.length == _totalParts;
  int get totalParts => _totalParts;
  int get receivedParts => _received.length;
  double get progress => _totalParts > 0 ? _received.length / _totalParts : 0.0;
  BbqrFileType? get fileType => _fileType;

  /// Returns true if the frame was a valid BBQr part.
  bool addPart(String frame) {
    if (frame.length < 8 || !frame.startsWith('B\$')) return false;

    final encCode = frame[2];
    final typeCode = frame[3];
    final totalStr = frame.substring(4, 6);
    final indexStr = frame.substring(6, 8);
    final payload = frame.substring(8);

    final encoding = BbqrEncoding.fromCode(encCode);
    final fileType = BbqrFileType.fromCode(typeCode);
    if (encoding == null || fileType == null) return false;

    final total = _fromBase36(totalStr);
    final index = _fromBase36(indexStr);
    if (total <= 0 || index < 0 || index >= total) return false;

    // Validate consistency
    if (_totalParts == 0) {
      _encoding = encoding;
      _fileType = fileType;
      _totalParts = total;
    } else {
      if (_encoding != encoding || _fileType != fileType || _totalParts != total) {
        return false;
      }
    }

    _received[index] = payload;
    return true;
  }

  /// Reassemble and decode the complete data. Call only when [isComplete].
  Uint8List finish() {
    if (!isComplete) throw StateError('Not all parts received');

    final buffer = StringBuffer();
    for (int i = 0; i < _totalParts; i++) {
      buffer.write(_received[i]!);
    }
    final encoded = buffer.toString();

    return _decodePayload(encoded, _encoding!);
  }
}

// ── Helpers ────────────────────────────────────────────────────────────

String _encodePayload(Uint8List data, BbqrEncoding encoding) {
  switch (encoding) {
    case BbqrEncoding.hex:
      return data.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    case BbqrEncoding.zlib:
      // BBQr spec: Z encoding is zlib-compressed bytes, then BASE32-
      // encoded (RFC 4648, no padding). The previous implementation
      // hex-encoded the compressed bytes here, which produced parts
      // that no spec-compliant BBQr reader (BlueWallet,
      // Sparrow) could decode. Symmetrically the decoder below was
      // also hex — meaning we'd round-trip our own Z parts but fail
      // on every external one. Per the spec, raw bytes go straight
      // to base32; the alphanumeric QR set covers the full base32
      // alphabet so it fits the same QR encoding constraints as
      // hex.
      return _base32Encode(data);
  }
}

Uint8List _decodePayload(String encoded, BbqrEncoding encoding) {
  switch (encoding) {
    case BbqrEncoding.hex:
      return _hexToBytes(encoded);
    case BbqrEncoding.zlib:
      final compressed = _base32Decode(encoded);
      return _zlibDecompress(compressed);
  }
}

Uint8List _hexToBytes(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (int i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

String _toBase36(int value, int width) {
  String result = '';
  int v = value;
  if (v == 0) {
    result = '0';
  } else {
    while (v > 0) {
      result = _base36Chars[v % 36] + result;
      v ~/= 36;
    }
  }
  return result.padLeft(width, '0');
}

int _fromBase36(String s) {
  int result = 0;
  for (int i = 0; i < s.length; i++) {
    result = result * 36 + _base36Chars.indexOf(s[i]);
  }
  return result;
}

// RFC 4648 base32 alphabet (uppercase). BBQr uses no padding.
const _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

String _base32Encode(Uint8List data) {
  if (data.isEmpty) return '';
  final out = StringBuffer();
  int buffer = 0;
  int bits = 0;
  for (final byte in data) {
    buffer = (buffer << 8) | (byte & 0xff);
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.writeCharCode(
          _base32Alphabet.codeUnitAt((buffer >> bits) & 0x1f));
    }
  }
  if (bits > 0) {
    out.writeCharCode(
        _base32Alphabet.codeUnitAt((buffer << (5 - bits)) & 0x1f));
  }
  return out.toString();
}

Uint8List _base32Decode(String encoded) {
  // Be lenient about padding/whitespace — strip both before decoding
  // so inputs from spec-compliant senders (which often include `=`
  // padding) and our own no-pad output both work.
  final clean = encoded.replaceAll('=', '').replaceAll(RegExp(r'\s+'), '');
  if (clean.isEmpty) return Uint8List(0);
  final bytes = <int>[];
  int buffer = 0;
  int bits = 0;
  for (var i = 0; i < clean.length; i++) {
    final ch = clean[i];
    final value = _base32Alphabet.indexOf(ch);
    if (value < 0) {
      throw FormatException('Invalid base32 char "$ch" at $i');
    }
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((buffer >> bits) & 0xff);
    }
  }
  return Uint8List.fromList(bytes);
}

/// Compress with zlib raw deflate (wbits=10, no header).
Uint8List _zlibCompress(Uint8List data) {
  final codec = ZLibCodec(level: 9, windowBits: 10, raw: true);
  return Uint8List.fromList(codec.encode(data));
}

/// Decompress raw deflate (wbits=10).
Uint8List _zlibDecompress(Uint8List compressed) {
  final codec = ZLibCodec(windowBits: 10, raw: true);
  return Uint8List.fromList(codec.decode(compressed));
}
