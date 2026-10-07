import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';

void main() {
  test('modify action wraps one order under the venue order id', () {
    final action = buildModifyAction(
      oid: 91490942,
      order: HlOrderWire(
        assetId: 3,
        isBuy: true,
        px: '29800',
        sz: '5',
        reduceOnly: false,
        orderType: limitOrderType('Alo'),
      ),
    );
    expect(action, {
      'type': 'modify',
      'oid': 91490942,
      'order': {
        'a': 3,
        'b': true,
        'p': '29800',
        's': '5',
        'r': false,
        't': {
          'limit': {'tif': 'Alo'}
        },
      },
    });
  });
}
