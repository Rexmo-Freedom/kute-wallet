// Phase 2 of Advanced trading on Hyperliquid, at the exchange service:
// the TWAP bounds in one place and refused before anything is signed, a
// scale order's legs each carrying a cloid and their statuses read one by
// one, an attached take-profit / stop-loss the venue refused surfacing on
// the result, a trigger and a scale order reconciled by cloid after a send
// with no answer (never sent twice). Fake HTTP only: nothing reaches the
// venue.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/screens/hyperliquid/components/order_placed_overlay.dart'
    show hlOrderResultNotices;
import 'package:kute/services/hyperliquid/hl_sent_order_trace.dart';
import 'package:kute/services/hyperliquid/hl_twap_rules.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

const _btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 60000,
  midPx: 60000,
  prevDayPx: 60000,
  dayNtlVlm: 0,
);

/// An exchange whose POSTs are captured and answered with [answer].
(HyperliquidExchangeService, List<Map<String, dynamic>>) _exchange(
    Map<String, dynamic> Function(Map<String, dynamic> action) answer) {
  final posted = <Map<String, dynamic>>[];
  final key = EthPrivateKey.fromHex(
      '0x0123456789012345678901234567890101234567890123456789012345678901');
  final service = HyperliquidExchangeService(
    credentials: key,
    walletAddress: key.address.hexEip55,
    httpClient: MockClient((request) async {
      final action = (jsonDecode(request.body)
          as Map<String, dynamic>)['action'] as Map<String, dynamic>;
      posted.add(action);
      return http.Response(jsonEncode(answer(action)), 200);
    }),
  );
  return (service, posted);
}

Map<String, dynamic> _statuses(List<Object> statuses) => {
      'status': 'ok',
      'response': {
        'type': 'order',
        'data': {'statuses': statuses},
      },
    };

void main() {
  group('TWAP bounds (hyperliquid docs: 5 min to 7 days, \$100 total)', () {
    test('one place, as documented', () {
      expect(HlTwapRules.minMinutes, 5);
      expect(HlTwapRules.maxMinutes, 10080);
      expect(HlTwapRules.minNotionalUsd, 100);
      expect(HyperliquidExchangeService.minTwapMinutes, HlTwapRules.minMinutes);
      expect(HyperliquidExchangeService.maxTwapMinutes, HlTwapRules.maxMinutes);
      expect(HyperliquidExchangeService.minTwapNotionalUsd,
          HlTwapRules.minNotionalUsd);
      expect(HlTwapRules.minutesValid(4), isFalse);
      expect(HlTwapRules.minutesValid(5), isTrue);
      expect(HlTwapRules.minutesValid(10080), isTrue);
      expect(HlTwapRules.minutesValid(10081), isFalse);
      expect(HlTwapRules.minutesValid(null), isFalse);
    });

    test('the ticket minimum is what clears \$100 once the size is floored',
        () {
      final min = HlTwapRules.minAmountUsd(
          referencePx: 60000, szDecimals: 5, leverage: 1);
      // \$100 at 60,000 floors to 0.00166 BTC (\$99.60): never enough.
      expect(min, greaterThan(100));
      final size = sizeFromUsd(usd: min, px: 60000, szDecimals: 5);
      expect(HlTwapRules.meetsMinimum(referencePx: 60000, size: size), isTrue);
      final at100 = sizeFromUsd(usd: 100, px: 60000, szDecimals: 5);
      expect(
          HlTwapRules.meetsMinimum(referencePx: 60000, size: at100), isFalse);
    });

    for (final minutes in [4, 10081]) {
      test('$minutes minutes is refused before anything is signed', () async {
        final (ex, posted) = _exchange((_) => {});
        await expectLater(
          ex.placeTwapOrder(
              market: _btc,
              isBuy: true,
              size: 0.01,
              durationMinutes: minutes,
              referencePx: 60000),
          throwsA(isA<HyperliquidRejectedException>()),
        );
        expect(posted, isEmpty);
      });
    }

    test('under \$100 is refused before anything is signed', () async {
      final (ex, posted) = _exchange((_) => {});
      await expectLater(
        ex.placeTwapOrder(
            market: _btc,
            isBuy: true,
            size: 0.00166,
            durationMinutes: 30,
            referencePx: 60000),
        throwsA(isA<HyperliquidMinNotionalException>()),
      );
      expect(posted, isEmpty);
    });
  });

  group('scale order legs', () {
    final cloids = hlScaleLegCloids('0x${'ab' * 15}00', 3);

    test('derived cloids: one per leg, distinct, the venue format', () {
      expect(cloids.toSet(), hasLength(3));
      for (final c in cloids) {
        expect(c, matches(RegExp(r'^0x[0-9a-f]{32}$')));
      }
      expect(cloids.last, endsWith('02'));
    });

    test('every leg goes out with its own cloid, at the legs the ticket checks',
        () async {
      final (ex, posted) = _exchange((_) => _statuses([
            {'resting': {'oid': 1}},
            {'resting': {'oid': 2}},
            {'resting': {'oid': 3}},
          ]));
      final result = await ex.placeScaleOrder(
          market: _btc,
          isBuy: true,
          totalSize: 0.003,
          startPx: 59000,
          endPx: 58000,
          count: 3,
          legCloids: cloids);
      final orders = (posted.single['orders'] as List).cast<Map>();
      expect([for (final o in orders) o['c']], cloids);
      final legs = hlScaleLegs(
          market: _btc,
          totalSize: 0.003,
          startPx: 59000,
          endPx: 58000,
          count: 3);
      expect([for (final o in orders) o['p']], [for (final l in legs) l.px]);
      expect([for (final o in orders) o['s']], [for (final l in legs) l.sz]);
      expect(result.legsPlaced, 3);
      expect(result.legsTotal, 3);
      expect(result.legsMissing, isFalse);
      expect(result.error, isNull);
    });

    test('a refused FIRST leg with the others resting is a partial placement, '
        'never a failure', () async {
      final (ex, _) = _exchange((_) => _statuses([
            {'error': 'Order price cannot be more than 80% away'},
            {'resting': {'oid': 2}},
            {'resting': {'oid': 3}},
          ]));
      final result = await ex.placeScaleOrder(
          market: _btc,
          isBuy: true,
          totalSize: 0.003,
          startPx: 59000,
          endPx: 58000,
          count: 3,
          legCloids: cloids);
      expect(result.kind, HlOrderResultKind.resting);
      expect(result.oid, 2);
      expect(result.legsPlaced, 2);
      expect(result.legsTotal, 3);
      expect(result.legsMissing, isTrue);
      final l10n = l10nForLanguage('en');
      expect(hlOrderResultNotices(l10n, result),
          ['Only 2 of 3 orders were placed.']);
    });

    test('every leg refused throws the venue\'s reason', () async {
      final (ex, _) = _exchange((_) => _statuses([
            {'error': 'Insufficient margin to place order.'},
            {'error': 'Insufficient margin to place order.'},
          ]));
      await expectLater(
        ex.placeScaleOrder(
            market: _btc,
            isBuy: true,
            totalSize: 0.002,
            startPx: 59000,
            endPx: 58000,
            count: 2),
        throwsA(isA<HyperliquidInsufficientMarginException>()),
      );
    });
  });

  group('an attached take-profit / stop-loss the venue refused', () {
    test('surfaces on the result, named', () async {
      final (ex, _) = _exchange((_) => _statuses([
            {
              'filled': {'oid': 9, 'totalSz': '0.001', 'avgPx': '60000'}
            },
            'waitingForFill',
            {'error': 'Invalid TP/SL price'},
          ]));
      final result = await ex.placeOrderWithTpsl(
          market: _btc,
          isBuy: true,
          px: '60600',
          sz: '0.001',
          tif: 'Ioc',
          takeProfitPx: 66000,
          stopLossPx: 50000);
      expect(result.isFilled, isTrue);
      expect(result.takeProfitRejected, isFalse);
      expect(result.stopLossRejected, isTrue);
      expect(hlOrderResultNotices(l10nForLanguage('en'), result),
          ['The stop-loss was not placed.']);
    });

    test('both refused say both', () {
      const r = HlOrderResult(
          kind: HlOrderResultKind.filled,
          takeProfitRejected: true,
          stopLossRejected: true);
      expect(hlOrderResultNotices(l10nForLanguage('en'), r),
          ['The take-profit and stop-loss were not placed.']);
      expect(hlOrderResultNotices(l10nForLanguage('en'), null), isEmpty);
    });
  });

  group('a trigger or scale send with no answer is looked up, never resent',
      () {
    test('a trigger carries its cloid, found by it after a timeout', () async {
      var sends = 0;
      List<String>? asked;
      final result = await hlSendReconciled(
        send: () async {
          sends++;
          throw TimeoutException('15 s');
        },
        cloid: '0x${'1' * 32}',
        market: _btc,
        action: 'trigger',
        window: const Duration(milliseconds: 30),
        every: const Duration(milliseconds: 10),
        lookup: (cloids, _) async {
          asked = cloids;
          return const HlSentOrderTrace.found(HlOrderResult(
              kind: HlOrderResultKind.resting, oid: 5, cloid: '0x1'));
        },
      );
      expect(sends, 1);
      expect(asked, ['0x${'1' * 32}']);
      expect(result.oid, 5);
    });

    test('a scale order is looked up by every leg: one found means placed',
        () async {
      final legs = hlScaleLegCloids('0x${'cd' * 15}00', 5);
      var sends = 0;
      List<String>? asked;
      final result = await hlSendReconciled(
        send: () async {
          sends++;
          throw TimeoutException('15 s');
        },
        cloid: legs.first,
        cloids: legs,
        market: _btc,
        action: 'open',
        window: const Duration(milliseconds: 30),
        every: const Duration(milliseconds: 10),
        lookup: (cloids, _) async {
          asked = cloids;
          return const HlSentOrderTrace.found(
              HlOrderResult(kind: HlOrderResultKind.resting, oid: 12));
        },
      );
      expect(sends, 1);
      expect(asked, legs);
      expect(result.oid, 12);
    });

    test('nowhere for the whole window: not placed; unreadable: unconfirmed',
        () async {
      Future<HlOrderResult> run(HlSentOrderTrace trace) => hlSendReconciled(
            send: () async => throw TimeoutException('15 s'),
            cloid: '0x${'2' * 32}',
            market: _btc,
            action: 'trigger',
            window: const Duration(milliseconds: 20),
            every: const Duration(milliseconds: 10),
            lookup: (_, __) async => trace,
          );
      await expectLater(run(const HlSentOrderTrace.none()),
          throwsA(isA<HyperliquidOrderNotPlacedException>()));
      await expectLater(run(const HlSentOrderTrace.unknown()),
          throwsA(isA<HyperliquidOrderUnconfirmedException>()));
    });
  });

  group('prices are bound as the wire sends them', () {
    test('wireRoundedPrice is roundPrice, and stays put when sent again', () {
      for (final px in [60000.123456, 1.23456789, 3.14159, 112345.7]) {
        final wire = wireRoundedPrice(px, szDecimals: 5, isSpot: false)!;
        expect(wire, double.parse(roundPrice(px, szDecimals: 5, isSpot: false)));
        // The notifier rounds again on the wire: the same figure.
        expect(double.parse(roundPrice(wire, szDecimals: 5, isSpot: false)),
            wire);
      }
      expect(wireRoundedPrice(60000.123456, szDecimals: 5, isSpot: false),
          60000);
      expect(wireRoundedPrice(null, szDecimals: 5, isSpot: false), isNull);
      expect(wireRoundedPrice(-1, szDecimals: 5, isSpot: false), isNull);
    });
  });
}
