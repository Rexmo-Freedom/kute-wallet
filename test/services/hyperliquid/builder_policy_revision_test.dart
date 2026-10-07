import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('published revision invalidates both signed-order builder caches',
      () async {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    var revision = 1;
    final service = RuntimeCapabilitiesService.forTesting(
      client: MockClient((_) async {
        final now = DateTime.now().toUtc();
        return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'revision': revision,
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
    HyperliquidFundingService.resetBuilderCacheForTest();
    final backend = MockClient((request) async => http.Response(
        jsonEncode(
          request.url.path == '/api/v1/hl/builder'
              ? {
                  'builderAddress':
                      '0x1111111111111111111111111111111111111111',
                  'defaultFeeTenthsBp': revision == 1 ? 5 : 9,
                  'maxFeeRate': '0.01%',
                  'revision': revision
                }
              : {
                  'builderCode': '0x${(revision == 1 ? 'ab' : 'cd') * 32}',
                  'revision': revision
                },
        ),
        200));
    try {
      await service.refresh();
      await http.runWithClient(() async {
        expect(
            (await HyperliquidFundingService.getBuilder())!.defaultFeeTenthsBp,
            5);
        expect(
            await PolymarketBackendService.getBuilderCode(), '0x${'ab' * 32}');
        revision = 2;
        await service.refresh();
        expect(
            (await HyperliquidFundingService.getBuilder())!.defaultFeeTenthsBp,
            9);
        expect(
            await PolymarketBackendService.getBuilderCode(), '0x${'cd' * 32}');
      }, () => backend);
    } finally {
      RuntimeCapabilitiesService.debugInstance = null;
      HyperliquidFundingService.resetBuilderCacheForTest();
      service.dispose();
    }
  });
}
