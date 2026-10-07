// The first prediction after a deposit never ends on "A previous prediction
// is still being confirmed". The venue can refuse it for balance while it
// still counts the wallet's old pUSD, and it says so with its figures
// appended. Read as ambiguous, that refusal kept the order "unaccounted
// for": the slip blamed a previous prediction that never existed, and the
// refusal's retry (convert, refresh the venue's count, sign again) never
// ran.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/polymarket_order_v2.dart';

const _detailed = 'not enough balance / allowance: the balance is not '
    'enough -> balance: 0, order amount: 5000000';

void main() {
  group('the balance refusal is recognised with its figures', () {
    test('as the bare sentence and with the detail the venue appends', () {
      expect(isPolymarketBalanceRefusal('not enough balance / allowance'),
          isTrue);
      expect(isPolymarketBalanceRefusal(_detailed), isTrue);
      expect(
          isPolymarketBalanceRefusal(
              'not enough balance / allowance — balance: 0, order amount: 1'),
          isTrue);
      expect(isDefinitivePolymarketOrderRejection(_detailed), isTrue);
    });

    test('and nothing else', () {
      expect(isPolymarketBalanceRefusal(null), isFalse);
      expect(isPolymarketBalanceRefusal('not enough balance / allowances'),
          isFalse);
      expect(isPolymarketBalanceRefusal('order match delayed'), isFalse);
      expect(
          isDefinitivePolymarketOrderRejection(
              'order match delayed due to market conditions'),
          isFalse);
    });

    test('a 400 carrying it is a refusal, not an ambiguous answer', () {
      expect(
          isDefinitivePolymarketHttpRejection(
              http.Response(jsonEncode({'error': _detailed}), 400)),
          isTrue);
      expect(
          isDefinitivePolymarketHttpRejection(http.Response(
              jsonEncode({'error': _detailed, 'orderID': '0x${'e' * 64}'}),
              400)),
          isTrue);
      expect(
          isDefinitivePolymarketHttpRejection(
              http.Response(jsonEncode({'error': _detailed}), 502)),
          isFalse);
    });
  });

  group('the order journal', () {
    const account = '0x1111111111111111111111111111111111111111';
    const exchange = '0xE111180000d2663C0091e4f400237545B87B996B';
    late Directory directory;
    late Box<String> box;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('first-bet-');
      Hive.init(directory.path);
      box = await Hive.openBox<String>(HotPolymarketOrderGuard.boxName);
    });
    tearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    final order = OrderStructV2(
        salt: BigInt.one,
        maker: account,
        signer: account,
        tokenId: '7',
        makerAmount: BigInt.from(2800000),
        takerAmount: BigInt.from(18600000),
        side: 0,
        signatureType: 3,
        timestamp: BigInt.from(1700000000000),
        metadata: '0x${'0' * 64}',
        builder: '0x${'0' * 64}');

    Future<void> placeOnce(Future<Map<String, dynamic>> Function() answer) =>
        HotPolymarketOrderGuard().run<void>(
            walletId: 'spending',
            depositWallet: account,
            tokenId: '7',
            lookup: (_) async => fail('No earlier order exists'),
            action: (submit) async {
              await submit(
                  order: SignedOrderV2(order: order, signature: 'fixture'),
                  exchange: exchange,
                  ensureCurrent: () {},
                  send: (beforePost) async {
                    beforePost();
                    return answer();
                  });
            });

    test('a refused first prediction is settled, and the next one is sent',
        () async {
      await expectLater(
          placeOnce(() async => {'success': false, 'errorMsg': _detailed}),
          throwsA(isA<PolymarketOrderNotAcceptedException>()
              .having((e) => isPolymarketBalanceRefusal(e.reason),
                  'balance refusal', isTrue)));
      expect(jsonDecode(box.get('$account:7')!)['stage'], 'rejected');

      // The retry (or the person's next tap) is not refused for an
      // "earlier prediction".
      var sent = false;
      await HotPolymarketOrderGuard().run<void>(
          walletId: 'spending',
          depositWallet: account,
          tokenId: '7',
          lookup: (_) async => fail('Nothing to look up'),
          action: (_) async => sent = true);
      expect(sent, isTrue);
    });

    test('the same refusal thrown by the transport settles it too', () async {
      await expectLater(
          placeOnce(() async =>
              throw const PolymarketOrderNotAcceptedException(_detailed)),
          throwsA(isA<PolymarketOrderNotAcceptedException>()));
      expect(jsonDecode(box.get('$account:7')!)['stage'], 'rejected');
      expect(await HotPolymarketOrderGuard.hasUnsettled(account), isFalse);
    });
  });
}
