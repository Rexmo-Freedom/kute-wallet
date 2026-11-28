import 'package:flutter_test/flutter_test.dart';
import 'package:kute/platform/breez_web_storage.dart';

void main() {
  group('isBreezDatabaseFor', () {
    const dir = 'breez_wallet-a';

    test('matches the directory and the SDK names built from it', () {
      expect(isBreezDatabaseFor(dir, dir), isTrue);
      expect(isBreezDatabaseFor('$dir-tree', dir), isTrue);
      expect(isBreezDatabaseFor('$dir/mainnet', dir), isTrue);
      expect(isBreezDatabaseFor('$dir/mainnet/abcd-tree', dir), isTrue);
    });

    test('never matches another wallet or other app databases', () {
      expect(isBreezDatabaseFor('breez_wallet-ab', dir), isFalse);
      expect(isBreezDatabaseFor('breez_wallet-a2/mainnet', dir), isFalse);
      expect(isBreezDatabaseFor('breez_wallet', dir), isFalse);
      expect(isBreezDatabaseFor('breez_prefs', dir), isFalse);
      expect(isBreezDatabaseFor('settings', dir), isFalse);
      expect(isBreezDatabaseFor('anything', ''), isFalse);
    });
  });

  test('is a no-op off the web', () async {
    expect(await deleteBreezWebStorage('breez_wallet-a'), 0);
  });
}
