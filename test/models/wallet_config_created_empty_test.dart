// `createdEmpty` marks a wallet created fresh on this device (balance
// known to be 0 before any sync). It round-trips through storage, and
// every wallet persisted before the field existed reads as false.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';

void main() {
  test('defaults to false and is absent-key false', () {
    expect(WalletConfig(id: 'w', name: 'n').createdEmpty, isFalse);
    expect(WalletConfig.fromMap({'id': 'w', 'name': 'n'}).createdEmpty,
        isFalse);
  });

  test('round-trips through toMap / fromMap and copyWith', () {
    final fresh = WalletConfig(id: 'w', name: 'n', createdEmpty: true);
    expect(fresh.toMap()['createdEmpty'], isTrue);
    expect(WalletConfig.fromMap(fresh.toMap()).createdEmpty, isTrue);
    expect(fresh.copyWith(name: 'renamed').createdEmpty, isTrue);
    expect(fresh.copyWith(createdEmpty: false).createdEmpty, isFalse);
  });
}
