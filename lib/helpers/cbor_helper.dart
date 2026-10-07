import 'dart:convert' show base64Decode;
import 'dart:typed_data';
import 'package:hex/hex.dart';
import 'package:bs58check/bs58check.dart' as bs58check;
import 'package:cbor/cbor.dart';

class CborToXpubConverter {
  static bool isLikelyCbor(String hex) {
    // Check for CBOR map tag (a2) or UR type tag
    return hex.toLowerCase().startsWith('a2') && hex.length > 100;
  }

  /// Reconstruct an xpub from raw public key and chain code byte arrays.
  /// Uses [purpose] (BIP number from derivation path, e.g. 44, 49, 84, 86)
  /// to select the correct SLIP-132 version prefix.
  static String fromKeyComponents(Uint8List pubKey, Uint8List chainCode, {bool isTestnet = false, int? purpose}) {
    final version = Uint8List.fromList(_versionBytes(purpose: purpose, isTestnet: isTestnet));

    final depth = Uint8List.fromList([0x03]);
    final parentFp = Uint8List.fromList([0x00, 0x00, 0x00, 0x00]);
    final childNumber = Uint8List.fromList([0x80, 0x00, 0x00, 0x00]);

    final builder = BytesBuilder();
    builder.add(version);
    builder.add(depth);
    builder.add(parentFp);
    builder.add(childNumber);
    builder.add(chainCode);
    builder.add(pubKey);

    return bs58check.encode(builder.toBytes());
  }

  /// SLIP-132 version bytes for each BIP purpose.
  static List<int> _versionBytes({int? purpose, bool isTestnet = false}) {
    if (isTestnet) {
      switch (purpose) {
        case 49: return [0x04, 0x4a, 0x52, 0x62]; // upub
        case 84: return [0x04, 0x5f, 0x1c, 0xf6]; // vpub
        default: return [0x04, 0x35, 0x87, 0xcf]; // tpub (44, 86, or unknown)
      }
    }
    switch (purpose) {
      case 49: return [0x04, 0x9d, 0x7c, 0xb2]; // ypub
      case 84: return [0x04, 0xb2, 0x47, 0x46]; // zpub
      default: return [0x04, 0x88, 0xb2, 0x1e]; // xpub (44, 86, or unknown)
    }
  }

  /// Extract the BIP purpose (44, 49, 84, 86) from a crypto-keypath origin.
  /// Key 6 in crypto-hdkey is a crypto-keypath map whose key 1 is a list of
  /// path components. Each hardened component is [index, true].
  static int? _extractPurpose(dynamic origin) {
    if (origin is! Map || !origin.containsKey(1)) return null;
    final components = origin[1];
    if (components is! List || components.isEmpty) return null;
    final first = components[0];
    // Hardened component: [purpose, true]
    if (first is List && first.isNotEmpty) return first[0] as int?;
    // Unhardened component (unlikely for purpose, but handle)
    if (first is int) return first;
    return null;
  }

  /// Try to extract an xpub from any decoded CBOR structure.
  /// Handles crypto-hdkey (keys 3+4 at root) and crypto-account (keys nested in descriptors).
  /// Uses the derivation path origin (key 6) to pick the correct SLIP-132 prefix.
  static String? tryExtractXpub(dynamic decoded, {bool isTestnet = false, int? purposeHint}) {
    if (decoded is Map) {
      // crypto-hdkey: keys 3 (pubKey) and 4 (chainCode) at root
      if (decoded.containsKey(3) && decoded[3] is Uint8List &&
          decoded.containsKey(4) && decoded[4] is Uint8List) {
        final purpose = _extractPurpose(decoded[6]) ?? purposeHint;
        return fromKeyComponents(decoded[3] as Uint8List, decoded[4] as Uint8List,
            isTestnet: isTestnet, purpose: purpose);
      }

      // crypto-account: key 2 is a list of output descriptors
      if (decoded.containsKey(2) && decoded[2] is List) {
        for (final desc in decoded[2] as List) {
          final result = tryExtractXpub(desc, isTestnet: isTestnet, purposeHint: purposeHint);
          if (result != null) return result;
        }
      }

      // Recurse into all map values
      for (final value in decoded.values) {
        final result = tryExtractXpub(value, isTestnet: isTestnet, purposeHint: purposeHint);
        if (result != null) return result;
      }
    }

    if (decoded is List) {
      for (final item in decoded) {
        final result = tryExtractXpub(item, isTestnet: isTestnet, purposeHint: purposeHint);
        if (result != null) return result;
      }
    }

    return null;
  }

  /// Convert CborValue tree to plain Dart types for tryExtractXpub compatibility.
  static dynamic _cborToPlain(CborValue value) {
    if (value is CborBytes) return Uint8List.fromList(value.bytes);
    if (value is CborString) return value.toString();
    if (value is CborSmallInt) return value.value;
    if (value is CborInt) return value.toInt();
    if (value is CborBool) return value.value;
    if (value is CborList) return value.map(_cborToPlain).toList();
    if (value is CborMap) {
      final map = <dynamic, dynamic>{};
      for (final entry in value.entries) {
        map[_cborToPlain(entry.key)] = _cborToPlain(entry.value);
      }
      return map;
    }
    return value;
  }

  static String convertCborToXpub(String cborHex, {bool isTestnet = false}) {
    final bytes = Uint8List.fromList(HEX.decode(cborHex));
    final decoded = cbor.decode(bytes);
    final data = _cborToPlain(decoded);

    if (data is! Map) {
      throw FormatException("Invalid CBOR: Root element is not a map");
    }

    final xpub = tryExtractXpub(data, isTestnet: isTestnet);
    if (xpub != null) return xpub;

    throw FormatException("Could not extract public key and chain code from CBOR");
  }

  /// Try to decode a base64 string as CBOR and extract an xpub.
  static String? tryDecodeBase64Xpub(String base64Str) {
    try {
      final bytes = Uint8List.fromList(base64Decode(base64Str));
      final decoded = cbor.decode(bytes);
      return tryExtractXpub(_cborToPlain(decoded));
    } catch (_) {
      return null;
    }
  }
}
