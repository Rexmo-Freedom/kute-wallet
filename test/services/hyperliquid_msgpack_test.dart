// Byte known-answer tests for the hand-rolled msgpack encoder, against
// vectors produced by Python `msgpack.packb` (the Hyperliquid reference
// serialization). Regenerate with fixtures/generate_hl_vectors.py.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hyperliquid/hyperliquid_msgpack.dart';

import 'hyperliquid_test_actions.dart';

void main() {
  final vectors = jsonDecode(
          File('test/services/fixtures/hl_vectors.json').readAsStringSync())
      as Map<String, dynamic>;

  String hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  group('scalars match Python msgpack.packb', () {
    final scalars = (vectors['msgpack'] as Map)['scalars'] as List;
    for (final raw in scalars) {
      final entry = raw as Map<String, dynamic>;
      final value = entry['value'];
      test('${_label(value)}', () {
        // JSON round-trips whole doubles (e.g. 4294967296.0) — coerce back.
        final input = value is double && value == value.truncateToDouble()
            ? value.toInt()
            : value;
        expect(hex(packMsgpack(input)), entry['hex']);
      });
    }
  });

  group('full actions match Python msgpack.packb', () {
    final actions = buildHlTestActions();
    final l1 = vectors['l1Actions'] as List;
    for (final raw in l1) {
      final entry = raw as Map<String, dynamic>;
      final name = entry['name'] as String;
      final action = actions[name];
      if (action == null) continue; // vault/expires variants share the action
      test(name, () {
        expect(hex(packMsgpack(action)), entry['msgpackHex']);
      });
    }
  });

  test('doubles are rejected', () {
    expect(() => packMsgpack({'p': 1670.1}), throwsArgumentError);
    expect(() => packMsgpack([0.5]), throwsArgumentError);
  });

  test('non-string map keys are rejected', () {
    expect(() => packMsgpack({1: 'a'}), throwsArgumentError);
  });
}

String _label(Object? value) {
  final s = value.toString();
  return s.length > 24 ? '${s.substring(0, 21)}… (len ${s.length})' : s;
}
