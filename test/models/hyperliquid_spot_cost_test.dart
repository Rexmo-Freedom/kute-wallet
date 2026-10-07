// spotClearinghouseState balances carry entryNtl, what the venue records
// as paid for the balance (live shape below). Zero means no cost on record.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';

void main() {
  test('entryNtl is the cost basis when there is one', () {
    final bought = HlSpotBalance.fromJson(const {
      'coin': 'HYPE',
      'token': 150,
      'total': '12.5',
      'hold': '0.0',
      'entryNtl': '500.25',
    });
    expect(bought.costBasis, 500.25);
    final transferred = HlSpotBalance.fromJson(const {
      'coin': 'UBTC',
      'total': '0.1',
      'hold': '0.0',
      'entryNtl': '0.0',
    });
    expect(transferred.costBasis, isNull);
    expect(
        HlSpotBalance.fromJson(const {'coin': 'X', 'total': '1', 'hold': '0'})
            .costBasis,
        isNull);
  });
}
