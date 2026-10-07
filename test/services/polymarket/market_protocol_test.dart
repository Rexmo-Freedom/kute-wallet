// Polymarket Protocol V2 markets: ids by `version`, the order venue by token
// id, and the signer's refusal to cross them.
//
// Fixtures are live Polymarket data read on 2026-10-07:
//   * V2 canary "polyv2-central-park-high-at-least-65f-2026-10-08" (hidden
//     from Gamma; ids and condition from the CLOB `/clob-markets` answer,
//     whose `"v":"v2"` and book `"version":"v2"` confirm the protocol);
//   * V2 canary "polyv2-central-park-rain-2026-10-01", resolved NO (Data API
//     `/v2/resolutions` payouts [0, 1000000]);
//   * V1 Gamma market 559651, which already lists `positionIds` beside its
//     `clobTokenIds` (version "v1"): ids must follow `version`, not which
//     field is present.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/market_protocol.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey, Market;

// V2 canary (binary module 0x01).
const _v2Yes =
    '834369838335332281222091626449713794621251551518727511203689528701902389248';
const _v2No =
    '834369838335332281222091626449713794621251551518727511203689528701902389249';
const _v2Condition =
    '0x01d83c915cee8a5ec4b4b715d1ac911aa7000000000000000000000000000000';

// V1 market 559651.
const _v1Yes =
    '32338220190071351435772801779725302244575775216413325951443816017994629993401';
const _v1No =
    '25659310674993675562345759665114759892400026242514633218387667107987341231962';
const _v1MigratedYes =
    '895257453734540292493143124621755605615887197499956109032745153687078305792';
const _v1Condition =
    '0xa467b14d51f01b957109d9cbb1d6c124fab2a089d52ed8f471d23c2812e743b7';

Map<String, dynamic> _v1Market() => {
      'id': '559651',
      'question': 'Xi Jinping out before 2027?',
      'conditionId': _v1Condition,
      'outcomes': '["Yes", "No"]',
      'outcomePrices': '["0.1", "0.9"]',
      'clobTokenIds': jsonEncode([_v1Yes, _v1No]),
      'positionIds': [
        _v1MigratedYes,
        '895257453734540292493143124621755605615887197499956109032745153687078305793',
      ],
      'version': 'v1',
      'negRisk': false,
    };

/// Shaped like the docs' V2 Gamma market: `positionIds` an array of
/// decimal strings, `clobTokenIds` possibly present and to be ignored.
Map<String, dynamic> _v2Market({Object? version = 'v2'}) => {
      'id': '9900001',
      'question':
          'Will Central Park’s maximum temperature be at least 65°F on October 8, 2026?',
      'conditionId': _v2Condition,
      'outcomes': '["Yes", "No"]',
      'outcomePrices': '["0.5", "0.5"]',
      'positionIds': [_v2Yes, _v2No],
      'clobTokenIds': jsonEncode([_v1Yes, _v1No]),
      'version': version,
      'negRisk': false,
    };

OrderStructV2 _order(String tokenId, String wallet) => OrderStructV2(
      salt: BigInt.from(479249096354),
      maker: wallet,
      signer: wallet,
      tokenId: tokenId,
      makerAmount: BigInt.from(5000000),
      takerAmount: BigInt.from(10000000),
      side: 0,
      signatureType: 3,
      timestamp: BigInt.from(1791401404372), // milliseconds, as the CLOB
      metadata: PolymarketConstants.bytes32Zero,
      builder: PolymarketConstants.bytes32Zero,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ids follow the market version', () {
    test('missing or "v1" is a CTF market; anything else unknown', () {
      expect(PolyMarketProtocol.of({}), PolyProtocol.v1);
      expect(PolyMarketProtocol.of({'version': 'v1'}), PolyProtocol.v1);
      expect(PolyMarketProtocol.of({'version': ' V2 '}), PolyProtocol.v2);
      expect(
          PolyMarketProtocol.of({'version': 'v3'}), PolyProtocol.unsupported);
    });

    test('a v1 market trades clobTokenIds even when positionIds are listed',
        () {
      expect(PolyMarketProtocol.outcomeIds(_v1Market()), [_v1Yes, _v1No]);
      final v1 = _v1Market();
      expect(identical(PolyMarketProtocol.withTradingIds(v1), v1), isTrue);
    });

    test('a v2 market trades positionIds, never its clobTokenIds', () {
      expect(PolyMarketProtocol.outcomeIds(_v2Market()), [_v2Yes, _v2No]);
      // JSON-text positionIds read the same.
      expect(
          PolyMarketProtocol.outcomeIds({
            ..._v2Market(),
            'positionIds': jsonEncode([_v2Yes, _v2No])
          }),
          [_v2Yes, _v2No]);
    });

    test('unknown versions and non-decimal ids give nothing to trade', () {
      expect(PolyMarketProtocol.outcomeIds(_v2Market(version: 'v3')), isEmpty);
      expect(
          PolyMarketProtocol.outcomeIds({
            ..._v2Market(),
            'positionIds': ['0x01', _v2No]
          }),
          isEmpty);
      expect(PolyMarketProtocol.outcomeIds({'version': 'v2'}), isEmpty);
    });

    test('the SDK Market model reads the traded ids after normalising', () {
      final m = Market.fromJson(PolyMarketProtocol.withTradingIds(_v2Market()));
      expect(m.tokenIdsList, [_v2Yes, _v2No]);
      final event = PolyMarketProtocol.eventWithTradingIds({
        'id': 'e',
        'markets': [_v1Market(), _v2Market()],
      });
      final markets = event['markets'] as List;
      expect(Market.fromJson(markets[0]).tokenIdsList, [_v1Yes, _v1No]);
      expect(Market.fromJson(markets[1]).tokenIdsList, [_v2Yes, _v2No]);
    });

    test('event outcomes carry the V2 position ids', () {
      final events = PolymarketModel().parseEventsRaw([
        {
          'id': '1148909',
          'slug': 'polyv2-central-park-temperature-thresholds-2026-10-08',
          'title': 'Central Park temperature',
          'markets': [_v2Market()],
        },
        {
          'id': '2',
          'slug': 'multi',
          'title': 'Multi',
          'markets': [
            {..._v2Market(), 'groupItemTitle': 'At least 65°F'},
            {..._v1Market(), 'groupItemTitle': 'Xi'},
          ],
        },
      ]);
      expect(events[0].outcomes.map((o) => o.tokenId), [_v2Yes, _v2No]);
      expect(events[1].outcomes[0].tokenId, _v2Yes);
      expect(events[1].outcomes[0].noTokenId, _v2No);
      expect(events[1].outcomes[1].tokenId, _v1Yes);
    });
  });

  group('V2 position ids', () {
    test('classified by module byte and reserved bits, like the SDK', () {
      expect(PolyMarketProtocol.isV2PositionId(_v2Yes), isTrue);
      expect(PolyMarketProtocol.isV2PositionId(_v2No), isTrue);
      expect(PolyMarketProtocol.isV2PositionId(_v1MigratedYes), isTrue);
      expect(PolyMarketProtocol.isV2PositionId(_v1Yes), isFalse);
      expect(PolyMarketProtocol.isV2PositionId(_v1No), isFalse);
      expect(PolyMarketProtocol.isV2PositionId('1'), isFalse);
      expect(PolyMarketProtocol.isV2PositionId('abc'), isFalse);
    });

    test('condition ids: the 66-char padded form and the 31-byte form', () {
      final c31 = _v2Condition.substring(0, 64);
      expect(PolyMarketProtocol.v2ConditionId(_v2Condition), c31);
      expect(PolyMarketProtocol.v2ConditionId(c31), c31);
      expect(PolyMarketProtocol.v2ConditionId(_v1Condition), isNull);
      expect(PolyMarketProtocol.splitV2(_v2No),
          (conditionId: c31, outcomeIndex: 1));
      expect(PolyMarketProtocol.v2PositionId(c31, 0), _v2Yes);
      expect(PolyMarketProtocol.v2PositionId(c31, 1), _v2No);
    });

    test('CLOB balance refreshes use CONDITIONAL-V2 for V2 shares', () {
      expect(PolyMarketProtocol.conditionalAssetType(_v2Yes), 'CONDITIONAL-V2');
      expect(PolyMarketProtocol.conditionalAssetType(_v1Yes), 'CONDITIONAL');
      expect(
          PolymarketBackendService.balanceAllowanceAssetType(
              'CONDITIONAL', _v2No),
          'CONDITIONAL-V2');
      expect(
          PolymarketBackendService.balanceAllowanceAssetType(
              'CONDITIONAL', _v1No),
          'CONDITIONAL');
      expect(
          PolymarketBackendService.balanceAllowanceAssetType(
              'COLLATERAL', null),
          'COLLATERAL');
    });
  });

  group('order venue', () {
    test('V2 always ExchangeV3 / "3", whatever negRisk says', () {
      for (final negRisk in [false, true]) {
        final v = PolyOrderVenue.forToken(_v2Yes, negRisk: negRisk);
        expect(v.isV2, isTrue);
        expect(v.exchange, PolymarketConstants.comboExchangeV3Address);
        expect(v.domainVersion, '3');
      }
    });

    test('CTF tokens keep their exchange by negRisk and domain "2"', () {
      expect(PolyOrderVenue.forToken(_v1Yes, negRisk: false).exchange,
          PolymarketConstants.exchangeAddress);
      expect(PolyOrderVenue.forToken(_v1Yes, negRisk: true).exchange,
          PolymarketConstants.negRiskExchangeAddress);
      expect(PolyOrderVenue.forToken(_v1Yes, negRisk: true).domainVersion, '2');
    });
  });

  group('signing', () {
    final key = EthPrivateKey.fromHex(
        '0x0123456789012345678901234567890101234567890123456789012345678901');
    const wallet = '0x3434343434343434343434343434343434343434';

    test('a V2 order signs under ExchangeV3 domain "3"', () async {
      final order = _order(_v2Yes, wallet);
      final sig = await signOrderV2Poly1271(
        order: order,
        credentials: key,
        verifyingContract: PolymarketConstants.comboExchangeV3Address,
      );
      expect(sig, startsWith('0x'));
      final typed = orderV2Poly1271TypedData(
          order: order,
          verifyingContract: PolymarketConstants.comboExchangeV3Address);
      expect(typed.domain['version'], '3');
      // The guard's order hash (exchange given, version derived) is the
      // ExchangeV3 domain hash, the order id the CLOB reports.
      expect(
          orderV2TypedData(
                  order: order,
                  verifyingContract: PolymarketConstants.comboExchangeV3Address)
              .digest,
          orderV2TypedData(
                  order: order,
                  verifyingContract: PolymarketConstants.comboExchangeV3Address,
                  domainVersion: '3')
              .digest);
    });

    test('a V2 order is never signed for a CTF exchange, nor V1 for V3',
        () async {
      for (final exchange in [
        PolymarketConstants.exchangeAddress,
        PolymarketConstants.negRiskExchangeAddress,
      ]) {
        await expectLater(
            signOrderV2Poly1271(
                order: _order(_v2Yes, wallet),
                credentials: key,
                verifyingContract: exchange),
            throwsA(isA<PolymarketOrderVenueMismatch>()));
        await expectLater(
            signOrderV2(
                order: _order(_v2Yes, wallet),
                credentials: key,
                verifyingContract: exchange),
            throwsA(isA<PolymarketOrderVenueMismatch>()));
      }
      await expectLater(
          signOrderV2Poly1271(
              order: _order(_v1Yes, wallet),
              credentials: key,
              verifyingContract: PolymarketConstants.comboExchangeV3Address),
          throwsA(isA<PolymarketOrderVenueMismatch>()));
      // A forced domain that does not match the exchange is refused too.
      await expectLater(
          signOrderV2Poly1271(
              order: _order(_v2Yes, wallet),
              credentials: key,
              verifyingContract: PolymarketConstants.comboExchangeV3Address,
              domainVersion: '2'),
          throwsA(isA<PolymarketOrderVenueMismatch>()));
      // The CTF path is unchanged.
      expect(
          await signOrderV2Poly1271(
              order: _order(_v1Yes, wallet),
              credentials: key,
              verifyingContract: PolymarketConstants.exchangeAddress),
          startsWith('0x'));
    });
  });

  group('kill switch', () {
    late DateTime now;
    RuntimeCapabilitiesService service(Map<String, dynamic> caps) =>
        RuntimeCapabilitiesService.forTesting(
          client: MockClient((_) async => http.Response(
              jsonEncode({
                'schemaVersion': 1,
                'revision': 1,
                'evaluatedAt': now.toIso8601String(),
                'expiresAt':
                    now.add(const Duration(minutes: 5)).toIso8601String(),
                'capabilities': caps,
              }),
              200)),
          baseUrl: () => 'https://backend.test',
          sessionToken: () => 'wallet-a',
          clock: () => now,
          appVersion: () async => '2.1.1',
        );

    setUp(() => now = DateTime.utc(2026, 10, 7, 12));
    tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

    Future<void> install(Map<String, dynamic> caps) async {
      final s = service(caps);
      expect(await s.refresh(), isTrue);
      RuntimeCapabilitiesService.debugInstance = s;
    }

    test('on by default, and when a policy does not list it yet', () async {
      await install({
        'polymarket.protocol_v2': {'allowed': true}
      });
      expect(PolyMarketProtocol.tradingEnabled, isTrue);
      PolyMarketProtocol.ensureSignable(_v2Yes);
      await install({
        'polymarket.trade': {'allowed': true}
      });
      expect(PolyMarketProtocol.tradingEnabled, isTrue);
    });

    test('switched off: V2 orders refused, V1 untouched', () async {
      await install({
        'polymarket.protocol_v2': {'allowed': false, 'reason': 'disabled'}
      });
      expect(PolyMarketProtocol.tradingEnabled, isFalse);
      expect(() => PolyMarketProtocol.ensureSignable(_v2Yes),
          throwsA(isA<PolymarketProtocolUnavailable>()));
      PolyMarketProtocol.ensureSignable(_v1Yes);
    });

    test('a Ledger never signs V2 for now', () async {
      await install({
        'polymarket.protocol_v2': {'allowed': true}
      });
      expect(() => PolyMarketProtocol.ensureSignable(_v2Yes, hardware: true),
          throwsA(isA<PolymarketProtocolUnavailable>()));
      PolyMarketProtocol.ensureSignable(_v1Yes, hardware: true);
    });
  });

  group('V1/V2 twins in one event', () {
    Map<String, dynamic> twinV1() =>
        {..._v1Market(), 'groupItemTitle': 'At least 65°F'};
    Map<String, dynamic> twinV2({bool accepting = true}) => {
          ..._v2Market(),
          'groupItemTitle': 'At least 65°F',
          'acceptingOrders': accepting,
        };

    test('one entry: V2 once it accepts orders, V1 until then', () {
      final live = PolyMarketProtocol.withoutTwins([twinV1(), twinV2()]);
      expect(live.map((m) => (m as Map)['version']), ['v2']);
      final notYet =
          PolyMarketProtocol.withoutTwins([twinV1(), twinV2(accepting: false)]);
      expect(notYet.map((m) => (m as Map)['version']), ['v1']);
    });

    test('distinct titles and same-version pairs are left alone', () {
      final other = {..._v1Market(), 'groupItemTitle': 'At least 70°F'};
      expect(PolyMarketProtocol.withoutTwins([other, twinV2()]), hasLength(2));
      expect(
          PolyMarketProtocol.withoutTwins([twinV1(), twinV1()]), hasLength(2));
    });

    test('the parsed event shows the twin once', () {
      final e = PolymarketModel().parseEventsRaw([
        {
          'id': '3',
          'slug': 'twins',
          'title': 'Twins',
          'markets': [
            twinV1(),
            twinV2(),
            {..._v1Market(), 'groupItemTitle': 'At least 70°F'},
          ],
        },
      ]).single;
      expect(e.outcomes.map((o) => o.name), ['At least 65°F', 'At least 70°F']);
      expect(e.outcomes.first.tokenId, _v2Yes);
    });
  });

  group('debug V2 routing', () {
    tearDown(() => PolyMarketProtocol.debugV2MarketIdsOverride = null);

    test('a named market with positionIds reads as V2 (never in release)', () {
      PolyMarketProtocol.debugV2MarketIdsOverride = {'559651'};
      expect(PolyMarketProtocol.of(_v1Market()), PolyProtocol.v2);
      expect(PolyMarketProtocol.outcomeIds(_v1Market()).first, _v1MigratedYes);
      // Without positionIds (a synthesized row) nothing changes.
      final bare = {..._v1Market()}..remove('positionIds');
      expect(PolyMarketProtocol.of(bare), PolyProtocol.v1);
    });
  });
}
