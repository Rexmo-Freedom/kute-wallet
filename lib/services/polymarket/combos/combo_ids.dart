// lib/services/polymarket/combos/combo_ids.dart
//
// Combo position ids (Polymarket Positions Framework).
//
// A position id is 32 bytes: a 31-byte condition id followed by one outcome
// byte (0 = YES, 1 = NO). The condition id's first byte names the module:
// 0x01 binary, 0x02 neg-risk, 0x03 combinatorial. Combo legs are binary or
// neg-risk outcome position ids (Gamma `positionIds`, NOT `clobTokenIds`).
//
// A combo's condition id is derived from its legs, so the app can check
// that the YES position an RFQ quotes is exactly the combo of the legs the
// user picked before signing an order for it:
//
//   legs      = sort(legPositionIds) ascending as uint256
//   hash      = keccak256(abi.encode(uint256 3, bytes abi.encode(uint256[] legs)))
//   condition = 0x03 || hash[16..32] || 14 zero bytes          (31 bytes)
//   YES / NO  = condition || 0x00 / 0x01
//
// Mirrors `@polymarket/client` (protocol v2 helpers). Pinned against live
// combos read from the Data API in test/services/polymarket/combos.

import 'dart:typed_data';

import 'package:pointycastle/digests/keccak.dart';

/// Thrown when a leg set cannot form a combo. The text is English on
/// purpose; screens never show it.
class ComboLegsException implements Exception {
  const ComboLegsException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class ComboIds {
  static const int minLegs = 2;
  static const int maxLegs = 50;
  static const int _moduleBinary = 0x01;
  static const int _moduleNegRisk = 0x02;
  static const int _moduleCombinatorial = 0x03;
  static final BigInt _maxUint256 = (BigInt.one << 256) - BigInt.one;

  /// A decimal uint256 position id, or null when [raw] is not one.
  static BigInt? parse(String raw) {
    final v = BigInt.tryParse(raw.trim());
    if (v == null || v.isNegative || v > _maxUint256) return null;
    return v;
  }

  static String _hex64(BigInt v) => v.toRadixString(16).padLeft(64, '0');

  /// The 31-byte condition id (0x-prefixed, lowercase) and the outcome
  /// index of a Positions Framework position id.
  static ({String conditionId, int outcomeIndex}) split(String positionId) {
    final v = parse(positionId);
    if (v == null) throw const ComboLegsException('not a position id');
    final hex = _hex64(v);
    final outcome = int.parse(hex.substring(62), radix: 16);
    if (outcome > 1) throw const ComboLegsException('not a YES/NO position');
    return (conditionId: '0x${hex.substring(0, 62)}', outcomeIndex: outcome);
  }

  /// The legs as the RFQ wants them: validated, deduplicated by refusal,
  /// sorted ascending. Throws [ComboLegsException] for a set the protocol
  /// rejects (wrong count, not a binary/neg-risk outcome, a duplicate, or
  /// both outcomes of one market).
  static List<String> canonicalLegs(Iterable<String> legPositionIds) {
    final parsed = <BigInt>[];
    for (final raw in legPositionIds) {
      final v = parse(raw);
      if (v == null) throw const ComboLegsException('not a position id');
      final hex = _hex64(v);
      final module = int.parse(hex.substring(0, 2), radix: 16);
      final outcome = int.parse(hex.substring(62), radix: 16);
      if ((module != _moduleBinary && module != _moduleNegRisk) ||
          outcome > 1) {
        throw const ComboLegsException('leg is not a YES/NO outcome');
      }
      parsed.add(v);
    }
    if (parsed.length < minLegs || parsed.length > maxLegs) {
      throw const ComboLegsException('a combo has 2 to 50 legs');
    }
    parsed.sort();
    for (var i = 1; i < parsed.length; i++) {
      if (parsed[i] == parsed[i - 1]) {
        throw const ComboLegsException('duplicate leg');
      }
      if (_hex64(parsed[i]).substring(0, 62) ==
          _hex64(parsed[i - 1]).substring(0, 62)) {
        throw const ComboLegsException('both outcomes of one market');
      }
    }
    return [for (final v in parsed) v.toString()];
  }

  /// The combo condition id and its YES / NO position ids (decimal) for
  /// [legPositionIds]. Order of the input does not matter.
  static ({String conditionId, String yesPositionId, String noPositionId})
      derive(Iterable<String> legPositionIds) {
    final legs = canonicalLegs(legPositionIds).map(BigInt.parse).toList();
    // abi.encode(uint256[]): offset, length, items.
    final inner = BytesBuilder()
      ..add(_word(BigInt.from(32)))
      ..add(_word(BigInt.from(legs.length)));
    for (final leg in legs) {
      inner.add(_word(leg));
    }
    final data = inner.toBytes();
    // abi.encode(uint256 moduleId, bytes data): data is a multiple of 32.
    final outer = BytesBuilder()
      ..add(_word(BigInt.from(_moduleCombinatorial)))
      ..add(_word(BigInt.from(64)))
      ..add(_word(BigInt.from(data.length)))
      ..add(data);
    final hash = KeccakDigest(256).process(outer.toBytes());
    final tail = hash
        .sublist(16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final condition = '03$tail${'00' * 14}';
    return (
      conditionId: '0x$condition',
      yesPositionId: BigInt.parse('${condition}00', radix: 16).toString(),
      noPositionId: BigInt.parse('${condition}01', radix: 16).toString(),
    );
  }

  /// The Router's `bytes31` argument for a 31-byte condition id.
  static Uint8List conditionBytes31(String conditionId) {
    final clean = conditionId.toLowerCase().replaceFirst('0x', '');
    if (clean.length != 62 || !RegExp(r'^[0-9a-f]+$').hasMatch(clean)) {
      throw const ComboLegsException('not a 31-byte condition id');
    }
    return Uint8List.fromList([
      for (var i = 0; i < 62; i += 2)
        int.parse(clean.substring(i, i + 2), radix: 16),
    ]);
  }

  static Uint8List _word(BigInt v) {
    final out = Uint8List(32);
    var t = v;
    for (var i = 31; i >= 0; i--) {
      out[i] = (t & BigInt.from(0xff)).toInt();
      t = t >> 8;
    }
    return out;
  }
}
