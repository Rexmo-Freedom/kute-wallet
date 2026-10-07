import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/orchestra/orchestra_history.dart';

const _spark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _legacySpark =
    'sp1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9hvvq4l';
const _otherSpark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
const _deposit = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

Map<String, dynamic> _order([Map<String, Object?> changes = const {}]) => {
      'id': 'ord_deposit',
      'status': 'completed',
      'sourceChain': 'polygon',
      'sourceAsset': 'USDC.e',
      'destinationChain': 'spark',
      'destinationAsset': 'BTC',
      'depositAddress': _deposit,
      'recipientAddress': _spark,
      'amountIn': '5000000',
      'amountOut': '5000',
      'createdAt': '2026-09-23T12:00:00Z',
      ...changes,
    };

bool _matches(Map<String, dynamic> order) => orchestraHistoryMatchesDeposit(
      OrchestraOrder.fromJson(order),
      sourceChain: 'POLYGON',
      sourceAsset: 'USDC.E',
      destinationAsset: 'BTC',
      depositAddress: _deposit,
      recipientSparkAddress: _spark,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    AffiliateService.debugSessionToken = 'test-session';
  });
  tearDown(() => AffiliateService.debugSessionToken = null);

  test('queries private recipient history and parses the provider envelope',
      () async {
    final result = await http.runWithClient(
      () => OrchestraService.getHistory(_spark),
      () => MockClient((request) async {
        expect(request.url.host, 'backend.test');
        expect(request.url.path, '/api/v1/orchestra/history');
        expect(request.url.queryParameters, {'address': _spark});
        expect(request.headers['Authorization'], 'Bearer test-session');
        return http.Response(
            jsonEncode({
              'orders': [_order()]
            }),
            200);
      }),
    );
    expect(result.data?.single.id, 'ord_deposit');
    expect(result.data?.single.depositAddress, _deposit);
    expect(result.statusCode, 200);
  });

  test('accepts legacy arrays and valid empty history', () async {
    for (final payload in [
      [_order()],
      {'orders': <Object>[]},
      <Object>[],
    ]) {
      final result = await http.runWithClient(
        () => OrchestraService.getHistory(_spark),
        () => MockClient((_) async => http.Response(jsonEncode(payload), 200)),
      );
      expect(result.error, isNull);
      expect(result.data, isNotNull);
    }
  });

  test('malformed or forbidden history is not an empty successful history',
      () async {
    for (final reply in [
      http.Response('{}', 200),
      http.Response('{"orders":null}', 200),
      http.Response('{"orders":[42]}', 200),
      http.Response('null', 200),
      http.Response('{"error":"recipient owner mismatch"}', 403),
      http.Response('{"error":"unavailable"}', 503),
    ]) {
      var calls = 0;
      final result = await http.runWithClient(
        () => OrchestraService.getHistory(_spark),
        () => MockClient((request) async {
          calls++;
          expect(request.url.host, 'backend.test');
          return reply;
        }),
      );
      expect(result.data, isNull);
      expect(result.error, isNotNull);
      expect(calls, 1, reason: 'No public fallback for private history');
    }
  });

  test('accepts the exact deposit route with equivalent address encodings', () {
    expect(_matches(_order()), isTrue);
    expect(_matches(_order({'recipientAddress': _legacySpark})), isTrue);
    expect(
        _matches(_order({'depositAddress': _deposit.toLowerCase()})), isTrue);
  });

  test('never attributes another recipient, deposit or asset to this screen',
      () {
    for (final changes in [
      {'recipientAddress': _otherSpark},
      {'recipientAddress': null},
      {'depositAddress': '0x0000000000000000000000000000000000000001'},
      {'depositAddress': null},
      {'sourceChain': 'base'},
      {'sourceAsset': 'USDC'},
      {'destinationChain': 'bitcoin'},
      {'destinationAsset': 'USDB'},
      {'sourceChain': null},
    ]) {
      expect(_matches(_order(changes)), isFalse, reason: '$changes');
    }
  });
}
