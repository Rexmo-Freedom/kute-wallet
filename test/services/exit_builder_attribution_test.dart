// Exits are attributed exactly like entries: with the backend reachable a
// close, reduce, cancel-then-reopen or sell carries the backend's builder;
// with it unreachable the same exits still go out, with no builder (or the
// zero Polymarket builder) and nothing built in.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

const _builder = '0x1111111111111111111111111111111111111111';
final _code = '0x${'ab' * 32}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late RuntimeCapabilitiesService policy;
  late bool backendUp;
  late List<Uri> backendCalls;

  final backend = MockClient((request) async {
    backendCalls.add(request.url);
    if (!backendUp) throw const SocketException('backend unreachable');
    return switch (request.url.path) {
      '/api/v1/hl/builder' => http.Response(
          jsonEncode({
            'builderAddress': _builder,
            'defaultFeeTenthsBp': 5,
            'maxFeeRate': '0.01%',
            'revision': 1,
          }),
          200),
      '/api/v1/pm/builder-code' =>
        http.Response(jsonEncode({'builderCode': _code, 'revision': 1}), 200),
      _ => http.Response('', 404),
    };
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('exit_builder');
    Hive.init(tmp.path);
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    backendUp = true;
    backendCalls = [];
    // No session: no policy snapshot, so any builder revision is current.
    policy = RuntimeCapabilitiesService.forTesting(
      client: MockClient((_) async => http.Response('', 503)),
      baseUrl: () => 'https://backend.test',
      sessionToken: () => null,
    );
    RuntimeCapabilitiesService.debugInstance = policy;
    HyperliquidFundingService.resetBuilderCacheForTest();
    PolymarketBackendService.resetBuilderCodeForTest();
  });

  tearDown(() async {
    RuntimeCapabilitiesService.debugInstance = null;
    HyperliquidFundingService.resetBuilderCacheForTest();
    PolymarketBackendService.resetBuilderCodeForTest();
    policy.dispose();
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  /// A hot exchange whose POSTs are captured and answered as accepted.
  (HyperliquidExchangeService, List<Map<String, dynamic>>) exchange() {
    final posted = <Map<String, dynamic>>[];
    final key = EthPrivateKey.fromHex(
        '0x0123456789012345678901234567890101234567890123456789012345678901');
    final service = HyperliquidExchangeService(
      credentials: key,
      walletAddress: key.address.hexEip55,
      httpClient: MockClient((request) async {
        final action =
            (jsonDecode(request.body) as Map<String, dynamic>)['action']
                as Map<String, dynamic>;
        posted.add(action);
        return http.Response(
            jsonEncode(action['type'] == 'cancel'
                ? {
                    'status': 'ok',
                    'response': {
                      'type': 'cancel',
                      'data': {
                        'statuses': ['success']
                      }
                    }
                  }
                : {
                    'status': 'ok',
                    'response': {
                      'type': 'order',
                      'data': {
                        'statuses': [
                          {
                            'resting': {'oid': 77}
                          }
                        ]
                      }
                    }
                  }),
            200);
      }),
    );
    return (service, posted);
  }

  Future<HlBuilderFee?> orderFee() => http.runWithClient(
      () async => (await HyperliquidFundingService.getBuilder())?.asOrderFee,
      () => backend);

  group('Hyperliquid', () {
    test('a close/reduce order carries the same backend builder as an open',
        () async {
      final fee = await orderFee();
      expect(fee, isNotNull);
      expect(backendCalls.map((u) => u.path), contains('/api/v1/hl/builder'));
      final (ex, posted) = exchange();
      await ex.placeLimitOrder(
          assetId: 4, isBuy: true, px: '100', sz: '1', tif: 'Ioc',
          builder: fee);
      await ex.placeLimitOrder(
          assetId: 4, isBuy: false, px: '99', sz: '1', tif: 'Ioc',
          reduceOnly: true, builder: fee);
      final open = posted[0], close = posted[1];
      expect((close['orders'] as List).single['r'], isTrue);
      expect(open['builder'], {'b': _builder, 'f': 5});
      expect(close['builder'], open['builder']);
    });

    test('cancel-then-reopen: the reopened order carries the builder',
        () async {
      final fee = await orderFee();
      final (ex, posted) = exchange();
      await ex.cancelOrder(assetId: 4, oid: 77);
      await ex.placeLimitOrder(
          assetId: 4, isBuy: false, px: '120', sz: '1', tif: 'Gtc',
          reduceOnly: true, builder: fee);
      expect(posted[0]['type'], 'cancel');
      expect(posted[0].containsKey('builder'), isFalse);
      expect(posted[1]['type'], 'order');
      expect(posted[1]['builder'], {'b': _builder, 'f': 5});
    });

    test('backend unreachable: the close still goes out with no builder',
        () async {
      backendUp = false;
      final fee = await orderFee();
      expect(fee, isNull);
      // The exit capability itself stays open during the outage.
      expect(policy.allows('hyperliquid.close'), isTrue);
      final (ex, posted) = exchange();
      await ex.placeLimitOrder(
          assetId: 4, isBuy: false, px: '99', sz: '1', tif: 'Ioc',
          reduceOnly: true, builder: fee);
      expect(posted.single['type'], 'order');
      expect(posted.single.containsKey('builder'), isFalse);
    });

    test('every hot exit order resolves the builder like an entry does', () {
      final source = File('lib/providers/hyperliquid_trading_provider.dart')
          .readAsStringSync();
      String body(String signature) {
        final start = source.indexOf(signature);
        expect(start, isNonNegative, reason: signature);
        final next = source.indexOf(RegExp(r'\n  Future<'), start + 1);
        return source.substring(start, next < 0 ? source.length : next);
      }

      for (final method in [
        'Future<HlOrderResult> openPosition(',
        'Future<HlOrderResult> closePosition(',
        'Future<HlOrderResult> placeLimit(',
        'Future<HlOrderResult> placeTrigger(',
        'Future<HlOrderResult> placeScale(',
      ]) {
        final code = body(method);
        expect(code, contains('await _builderFee()'), reason: method);
        expect(code, contains('builder: builder'), reason: method);
        // Reduce-only (exit) orders are never special-cased out.
        expect(code, isNot(matches(RegExp(r'reduceOnly\s*\?\s*null'))),
            reason: method);
      }
      // _builderFee reads only the backend; nothing built in.
      final fee = body('Future<HlBuilderFee?> _builderFee(');
      expect(fee, contains('HyperliquidFundingService.getBuilder()'));
    });

    test('the Ledger close names the backend builder like the Ledger open',
        () {
      final source =
          File('lib/screens/ledger/hyperliquid/ledger_hl_execution_target.dart')
              .readAsStringSync();
      final close = source.substring(
          source.indexOf('runLedgerHlClose('),
          source.indexOf('void validateLedgerHlClosePosition('));
      expect(close, contains('HyperliquidFundingService.getBuilder()'));
      expect(close, contains('reduceOnly: true'));
      expect(close, contains('builderAddress: builder?.builderAddress'));
      expect(close, contains('builderFeeTenthsBp: builder?.defaultFeeTenthsBp'));
    });
  });

  group('Polymarket', () {
    test('a sell is signed with the backend builder code when it answered',
        () async {
      final code = await http.runWithClient(
          PolymarketBackendService.getBuilderCode, () => backend);
      expect(code, _code);
      expect(code, isNot(PolymarketConstants.bytes32Zero));
      // Buys and sells share one signing path, and it signs this code.
      final source = File('lib/providers/polymarket_trading_provider.dart')
          .readAsStringSync();
      expect(RegExp(r'_buildSignedOrder\(').allMatches(source).length, 2,
          reason: 'one definition, one call shared by buy and sell');
      final signing = source.substring(
          source.indexOf('Future<SignedOrderV2> _buildSignedOrder('));
      expect(
          signing,
          contains(
              'final builderCode = await PolymarketBackendService.getBuilderCode();'));
      expect(signing, contains('builder: builderCode,'));
      expect(signing, contains("side: side == OrderSide.buy ? 0 : 1,"));
      // The Ledger sell reads the same backend code into its intent.
      final ledgerSell =
          File('lib/screens/ledger/polymarket/ledger_sell_sheet.dart')
              .readAsStringSync();
      expect(ledgerSell,
          contains('await PolymarketBackendService.getBuilderCode()'));
      expect(ledgerSell, contains('builderCode: builderCode,'));
    });

    test('backend unreachable: a sell signs with the zero builder', () async {
      backendUp = false;
      final code = await http.runWithClient(
          PolymarketBackendService.getBuilderCode, () => backend);
      expect(code, PolymarketConstants.bytes32Zero);
      expect(policy.allows('polymarket.close'), isTrue);
    });
  });
}
