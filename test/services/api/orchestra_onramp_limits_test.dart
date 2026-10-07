import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/api/orchestra_api.dart';

Map<String, Object?> route(String chain, String asset, Object min, Object max,
        {bool supported = true, String source = 'lightning'}) =>
    {
      'sourceChain': source,
      'sourceAsset': 'BTC',
      'destinationChain': chain,
      'destinationAsset': asset,
      'limits': {
        'fiatUsd': {'supported': supported, 'min': min, 'max': max},
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    AffiliateService.debugSessionToken = 'test-session';
  });
  tearDown(() => AffiliateService.debugSessionToken = null);

  test('reads fiat limits from the matching current route only', () {
    final result = OrchestraOnrampLimits.fromResponse({
      'routes': [
        route('hypercore', 'USDC', '2.00', '500.00', source: 'spark'),
        route('polygon', 'USDC.e', '5.00', '200.00'),
        route('hypercore', 'USDC', '1.00', '50000.00'),
      ],
    }, destinationChain: 'hypercore', destinationAsset: 'USDC');
    expect(result?.minFiatUsd, 1);
    expect(result?.maxFiatUsd, 50000);
  });

  test('never uses another route or an unsupported fiat band', () {
    for (final rows in [
      [route('polygon', 'USDC.e', 1, 50000)],
      [route('hypercore', 'USDC', 1, 50000, supported: false)],
      [route('hypercore', 'USDC', 'NaN', 50000)],
      [route('hypercore', 'USDC', 1, 'Infinity')],
      [route('hypercore', 'USDC', 20, 10)],
    ]) {
      expect(
          OrchestraOnrampLimits.fromResponse({
            'routes': rows,
            'minFiatUsd': 1,
            'maxFiatUsd': 50000,
          }, destinationChain: 'hypercore', destinationAsset: 'USDC'),
          isNull);
    }
  });

  test('keeps the old flat limits response compatible', () {
    final result = OrchestraOnrampLimits.fromResponse({
      'limits': {'minFiatUsd': '3.00', 'maxFiatUsd': 1000},
    }, destinationChain: 'bitcoin', destinationAsset: 'BTC');
    expect(result?.minFiatUsd, 3);
    expect(result?.maxFiatUsd, 1000);
  });

  test('backend and public fallback receive the complete selected pair',
      () async {
    final requests = <http.Request>[];
    final result = await http.runWithClient(
      () => OrchestraService.getOnrampLimits(
          destinationChain: 'polygon', destinationAsset: 'USDC.e'),
      () => MockClient((request) async {
        requests.add(request);
        if (request.url.host == 'backend.test') {
          return http.Response('{}', 503);
        }
        return http.Response(
            jsonEncode({
              'routes': [route('polygon', 'USDC.e', '2.50', '400.00')],
            }),
            200);
      }),
    );
    expect(result.data?.minFiatUsd, 2.5);
    expect(result.data?.maxFiatUsd, 400);
    expect(requests, hasLength(2));
    for (final request in requests) {
      expect(request.url.queryParameters, {
        'sourceChain': 'lightning',
        'sourceAsset': 'BTC',
        'destinationChain': 'polygon',
        'destinationAsset': 'USDC.e',
      });
    }
    expect(requests.first.headers['Authorization'], 'Bearer test-session');
    expect(requests.last.headers.containsKey('Authorization'), isFalse);
  });

  test('the existing no-argument caller requests Spark Bitcoin limits',
      () async {
    await http.runWithClient(
      () => OrchestraService.getOnrampLimits(),
      () => MockClient((request) async {
        expect(request.url.queryParameters['destinationChain'], 'spark');
        expect(request.url.queryParameters['destinationAsset'], 'BTC');
        return http.Response(
            jsonEncode({
              'routes': [route('spark', 'BTC', 1, 50000)],
            }),
            200);
      }),
    );
  });
}
