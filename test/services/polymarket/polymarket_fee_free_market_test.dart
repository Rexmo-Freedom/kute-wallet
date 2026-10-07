import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

// A fee-free market (Gamma's feesEnabled false) comes back from
// /clob-markets with no `fd`. The venue charges it no platform fee, only the
// builder fee the order's code carries. The slip used to show "Estimate
// unavailable" there and size with the documented maxima (7% curve, 100 bps),
// reserving $0.37 on an $8 stake that pays $0.016.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const condition = '0xfeefree';
  final code = '0x${'f8' * 32}';
  late RuntimeCapabilitiesService service;

  Map<String, dynamic>? clobMarket;

  MockClient venue() => MockClient((request) async {
        final path = request.url.path;
        if (request.url.host == 'backend.test') {
          return http.Response(
              jsonEncode({'builderCode': code, 'revision': 1}), 200);
        }
        if (path.startsWith('/markets-by-token/')) {
          return http.Response(jsonEncode({'condition_id': condition}), 200);
        }
        if (path == '/clob-markets/$condition') {
          return http.Response(jsonEncode(clobMarket), 200);
        }
        if (path == '/fees/builder-fees/$code') {
          return http.Response(
              jsonEncode({
                'builder_taker_fee_rate_bps': 20,
                'builder_maker_fee_rate_bps': 0,
              }),
              200);
        }
        return http.Response('{}', 404);
      });

  setUp(() async {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    PolymarketFeeTerms.resetCacheForTest();
    PolymarketBackendService.resetBuilderCodeForTest();
    service = RuntimeCapabilitiesService.forTesting(
      client: MockClient((_) async {
        final now = DateTime.now().toUtc();
        return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'revision': 1,
              'evaluatedAt': now.toIso8601String(),
              'expiresAt':
                  now.add(const Duration(minutes: 2)).toIso8601String(),
              'capabilities': {},
              'fees': {},
              'ai': {'dailyLimit': 5}
            }),
            200);
      }),
      baseUrl: () => 'https://backend.test',
      sessionToken: () => 'session',
    );
    RuntimeCapabilitiesService.debugInstance = service;
    await service.refresh();
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    PolymarketBackendService.resetBuilderCodeForTest();
    PolymarketFeeTerms.resetCacheForTest();
    service.dispose();
  });

  Future<PolymarketFeeTerms> fetch() => http.runWithClient(
      () => PolymarketFeeTerms.fetch('token', client: venue()), venue);

  test('a market served with no fee curve pays only the builder fee', () async {
    clobMarket = {'c': condition, 'mts': 0.001, 'v': 'v1'};
    final terms = await fetch();
    expect(terms.live, isTrue);
    expect(terms.rate, 0);
    expect(terms.builderTakerBps, 20);
    // What the venue charges: no platform fee, 20 bps of notional.
    for (final (stake, price) in [(2.48, 0.72), (8.0, 0.5), (250.0, 0.03)]) {
      final shares = stake / price;
      expect(terms.platformFee(shares, price), 0);
      expect(terms.totalFee(shares, price), closeTo(stake * 0.002, 1e-9));
    }
    // $8 at 0.50 reserves the cent the builder fee rounds up to, not $0.36.
    expect(terms.feeCeilingForNotional(8, 0.5), closeTo(0.02, 1e-9));
    expect(PolymarketFeeTerms.worstCase.feeCeilingForNotional(8, 0.5),
        greaterThanOrEqualTo(0.36));
  });

  test('a fee-enabled market still reads its own curve', () async {
    clobMarket = {
      'c': condition,
      'fd': {'r': 0.05, 'e': 1, 'to': true}
    };
    final terms = await fetch();
    expect(terms.rate, 0.05);
    // The $8 screenshot: 13.33 shares at 0.60 → $0.16 + $0.016 = $0.18.
    expect((terms.totalFee(8 / 0.6, 0.6) * 100).round() / 100, 0.18);
  });

  test('a record for another market, or a malformed curve, is not fee-free',
      () async {
    clobMarket = {'c': '0xsomethingelse'};
    await expectLater(fetch(), throwsStateError);
    PolymarketFeeTerms.resetCacheForTest();
    clobMarket = {'c': condition, 'fd': 'n/a'};
    await expectLater(fetch(), throwsStateError);
    PolymarketFeeTerms.resetCacheForTest();
    clobMarket = {'c': condition, 'fd': null};
    await expectLater(fetch(), throwsStateError);
  });
}
