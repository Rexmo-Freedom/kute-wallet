import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

const _key =
    '0x0123456789012345678901234567890101234567890123456789012345678901';
const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';

Matcher _rejectsField(String field) => throwsA(isA<WalletGuardException>()
    .having((e) => e.reason, 'reason',
        WalletGuardReason.withdrawDestinationRejected)
    .having((e) => e.field, 'field', field));

void main() {
  group('exchange backstop', () {
    test('withdraw3 rejects a non-hex destination with no network call',
        () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      });
      final credentials = EthPrivateKey.fromHex(_key);
      final exchange = HyperliquidExchangeService(
        credentials: credentials,
        walletAddress: credentials.address.hexEip55,
      );
      for (final bad in ['lnbc1invoice', '0x1234', _ownSpark, '']) {
        await expectLater(
          http.runWithClient(
              () => exchange.withdraw3(amount: 10, destination: bad),
              () => client),
          _rejectsField('withdraw3'),
          reason: bad,
        );
      }
      expect(calls, 0);
    });
  });
}
