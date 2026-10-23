// Fee terms never wait on the builder-code fetch. A backend that answers
// slowly (or not at all) used to push the whole estimate to the documented
// maxima (7% + 100 bps), which could refuse a stake the account covers.
// Now the platform curve is read from the venue regardless, the builder
// part uses the cached code, the last saved rates, or the one-percent
// maximum, and a saved curve answers a later session without a read.
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const condition = '0xcond';
  final code = '0x${'ab' * 32}';
  late RuntimeCapabilitiesService service;
  var backendDelay = Duration.zero;
  var curveReads = 0;
  var now = DateTime(2026, 10, 12, 12);

  MockClient venue() => MockClient((request) async {
        final path = request.url.path;
        if (request.url.host == 'backend.test') {
          if (backendDelay > Duration.zero) await Future.delayed(backendDelay);
          return http.Response(
              jsonEncode({'builderCode': code, 'revision': 1}), 200);
        }
        if (path.startsWith('/markets-by-token/')) {
          return http.Response(jsonEncode({'condition_id': condition}), 200);
        }
        if (path == '/clob-markets/$condition') {
          curveReads++;
          return http.Response(
              jsonEncode({
                'c': condition,
                'fd': {'r': 0.05, 'e': 1}
              }),
              200);
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
    backendDelay = Duration.zero;
    curveReads = 0;
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    PolymarketFeeTerms.resetCacheForTest();
    PolymarketFeeTerms.clock = () => now;
    PolymarketBackendService.resetBuilderCodeForTest();
    service = RuntimeCapabilitiesService.forTesting(
      client: MockClient((_) async {
        final t = DateTime.now().toUtc();
        return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'revision': 1,
              'evaluatedAt': t.toIso8601String(),
              'expiresAt': t.add(const Duration(minutes: 2)).toIso8601String(),
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

  test('a slow backend leaves the platform curve live and caps the builder '
      'part at one percent', () async {
    backendDelay = const Duration(seconds: 3);
    final clock = Stopwatch()..start();
    final terms = await fetch();
    expect(clock.elapsed, lessThan(const Duration(milliseconds: 2500)));
    expect(terms.live, isTrue);
    expect(terms.rate, 0.05);
    expect(terms.builderTakerBps, 100);
    // $8 at 0.50: 16 shares × 0.05 × 0.25 = $0.20, plus 1% = $0.28 (a cent
    // of rounding up at most); the documented maxima would reserve $0.36.
    expect(terms.feeCeilingForNotional(8, 0.5), lessThanOrEqualTo(0.29));
  });

  test('a cached builder code is read without any backend wait', () async {
    await http.runWithClient(
        () => PolymarketBackendService.prefetchBuilderCode(), venue);
    expect(PolymarketBackendService.cachedBuilderCode, code);
    backendDelay = const Duration(seconds: 30);
    final terms = await fetch();
    expect(terms.builderTakerBps, 20);
    expect(terms.rate, 0.05);
  });

  test('the fee curve is saved per market and answers without a read', () async {
    await http.runWithClient(
        () => PolymarketBackendService.prefetchBuilderCode(), venue);
    await fetch();
    expect(curveReads, 1);
    // A later session: the minute cache is gone, the saved curve stays.
    now = now.add(const Duration(hours: 2));
    final terms = await fetch();
    expect(terms.rate, 0.05);
    // Past an hour the saved curve is refreshed behind the answer, once.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(curveReads, 2);
    // Within the hour it is not read at all.
    now = now.add(const Duration(minutes: 2));
    await fetch();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(curveReads, 2);
  });

  test('the slip and a warm-up share one read', () async {
    await http.runWithClient(
        () => PolymarketBackendService.prefetchBuilderCode(), venue);
    final client = venue();
    await http.runWithClient(
        () => Future.wait([
              PolymarketFeeTerms.fetch('token', client: client),
              PolymarketFeeTerms.fetch('token', client: client),
            ]),
        () => client);
    expect(curveReads, 1);
    expect(PolymarketFeeTerms.cached('token')?.rate, 0.05);
  });
}
