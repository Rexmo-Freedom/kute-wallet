// Table-driven tests for Hyperliquid price/size wire rounding. floatToWire
// vectors come straight from the Python SDK's float_to_wire.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';

void main() {
  final vectors = jsonDecode(
          File('test/services/fixtures/hl_vectors.json').readAsStringSync())
      as Map<String, dynamic>;

  group('floatToWire matches Python float_to_wire', () {
    for (final raw in vectors['floatToWire'] as List) {
      final entry = raw as Map<String, dynamic>;
      final value = (entry['value'] as num).toDouble();
      test('$value → ${entry['wire']}', () {
        expect(floatToWire(value), entry['wire']);
      });
    }
  });

  test('floatToWire rejects values that fixed-8 formatting would round', () {
    expect(() => floatToWire(0.000000001234), throwsArgumentError);
  });

  group('roundPrice', () {
    test('5 significant figures, perp decimal cap', () {
      // ETH-style: szDecimals 4 → cap 2 decimals.
      expect(roundPrice(1670.1234, szDecimals: 4, isSpot: false), '1670.1');
      // BTC-style: szDecimals 5 → cap 1 decimal.
      expect(roundPrice(50000.12345, szDecimals: 5, isSpot: false), '50000');
      expect(roundPrice(50000.55, szDecimals: 5, isSpot: false), '50001');
      // Low-price perp keeps 5 sig figs within cap.
      expect(roundPrice(0.0123456, szDecimals: 0, isSpot: false), '0.012346');
    });

    test('prices above 100k become integers via the sig-fig rule', () {
      // Integer prices are always valid on the venue; above 100k the
      // dollars are kept rather than rounded to five figures.
      expect(roundPrice(123456.7, szDecimals: 5, isSpot: false), '123457');
    });

    test('spot cap is 8 - szDecimals', () {
      expect(roundPrice(172.2149, szDecimals: 4, isSpot: true), '172.21');
      expect(roundPrice(0.00012345, szDecimals: 0, isSpot: true), '0.00012345');
    });

    test('rejects non-positive prices', () {
      expect(() => roundPrice(0, szDecimals: 2, isSpot: false),
          throwsArgumentError);
    });
  });

  group('roundSize / flooredSize', () {
    test('floors to szDecimals without binary-float artifacts', () {
      expect(roundSize(0.29, 2), '0.29');
      expect(roundSize(0.0147, 4), '0.0147');
      expect(roundSize(1.23456, 3), '1.234');
      expect(flooredSize(0.29, 2), 0.29);
    });

    test('throws when size floors to zero', () {
      expect(() => roundSize(0.0001, 2), throwsArgumentError);
    });
  });

  group('sizing helpers', () {
    test('sizeFromUsd floors', () {
      expect(sizeFromUsd(usd: 100, px: 3, szDecimals: 2), 33.33);
      expect(sizeFromUsd(usd: 100, px: 0, szDecimals: 2), 0);
    });

    test('slippagePrice moves through the book and wire-rounds', () {
      expect(
        slippagePrice(
          referencePx: 1670.1,
          isBuy: true,
          slippage: 0.01,
          szDecimals: 4,
          isSpot: false,
        ),
        '1686.8', // 1670.1 * 1.01 = 1686.801 → 5 sig figs
      );
      expect(
        slippagePrice(
          referencePx: 1670.1,
          isBuy: false,
          slippage: 0.01,
          szDecimals: 4,
          isSpot: false,
        ),
        '1653.4', // 1670.1 * 0.99 = 1653.399 → 5 sig figs
      );
    });

    test('meetsMinNotional boundary', () {
      expect(meetsMinNotional(px: 10, sz: 1), isTrue);
      expect(meetsMinNotional(px: 9.99, sz: 1), isFalse);
    });
  });

  group('asset ids', () {
    test('perp = universe index, spot = 10000 + pair index', () {
      expect(perpAssetId(4), 4);
      expect(spotAssetId(8), 10008);
    });
  });
}
