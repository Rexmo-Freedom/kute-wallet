import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import '../helpers/runtime_policy_fixture.dart';

void main() {
  final orderId = '0x${'ab' * 32}';
  final service = PolymarketBackendService(
      apiKey: 'user-api-key',
      secret: base64Url.encode(utf8.encode('test-l2-secret')),
      passphrase: 'pass',
      walletAddress: '0x123');
  final token =
      '${base64Url.encode(utf8.encode('account-a|0|9999999999'))}.signature';
  setUp(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    AffiliateService.debugSessionToken = token;
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
  });
  tearDown(() {
    AffiliateService.debugSessionToken = null;
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
  });

  test('receipt HMAC authorizes only the direct GET order evidence', () async {
    await http.runWithClient(
        () => service.verifyAcceptedOrder(orderId,
            accountingIdentity: 'account-a'),
        () => MockClient((request) async {
              expect(request.method, 'POST');
              expect(request.url.path, '/api/v1/pm/verify-order');
              expect(jsonDecode(request.body), {'orderId': orderId});
              expect(request.headers['Authorization'], 'Bearer $token');
              expect(request.headers['X-Kute-Platform'], 'ios');
              expect(request.headers['POLY_API_KEY'], 'user-api-key');
              final timestamp = request.headers['POLY_TIMESTAMP'];
              final message = '${timestamp}GET/data/order/$orderId';
              final expected = base64Url.encode(
                  Hmac(sha256, utf8.encode('test-l2-secret'))
                      .convert(utf8.encode(message))
                      .bytes);
              expect(request.headers['POLY_SIGNATURE'], expected);
              expect(request.body, isNot(contains('test-l2-secret')));
              return http.Response('{}', 200);
            }));
  });

  test('a linked Polymarket account no longer sends per-order receipts',
      () async {
    FlutterSecureStorage.setMockInitialValues(
        {'kute_venue_owner_v1:polymarket:0x123': 'linked'});
    addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
    await http.runWithClient(
        () => service.verifyAcceptedOrder(orderId,
            accountingIdentity: 'account-a'),
        () => MockClient((request) async => throw StateError('must not send')));
  });

  test('changed account cannot receive another account receipt', () async {
    await http.runWithClient(
        () => service.verifyAcceptedOrder(orderId,
            accountingIdentity: 'account-b'),
        () => MockClient((request) async => throw StateError('must not send')));
  });

  test('successful direct order returns before receipt verification completes',
      () async {
    final verifying = Completer<void>();
    final receipt = Completer<http.Response>();
    final signed = SignedOrderV2(
        order: OrderStructV2(
            salt: BigInt.one,
            maker: '0x123',
            signer: '0x123',
            tokenId: '1',
            makerAmount: BigInt.one,
            takerAmount: BigInt.two,
            side: 0,
            signatureType: 3,
            timestamp: BigInt.one,
            metadata: '0x${'00' * 32}',
            builder: '0x${'00' * 32}'),
        signature: '0xsignature');
    await http.runWithClient(() async {
      final result = await service
          .submitOrder(signedOrder: signed)
          .timeout(const Duration(seconds: 1));
      expect(result['orderID'], orderId);
      await verifying.future;
      receipt.complete(http.Response('{}', 403));
      await Future<void>.delayed(Duration.zero);
    },
        () => MockClient((request) async {
              if (request.url.host == 'clob.polymarket.com') {
                expect(request.url.path, '/order');
                return http.Response(
                    jsonEncode({'orderID': orderId, 'success': true}), 200);
              }
              verifying.complete();
              return receipt.future;
            }));
  });
}
