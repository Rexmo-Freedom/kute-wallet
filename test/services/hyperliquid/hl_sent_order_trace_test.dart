// An order whose answer never came may well have been taken: it is looked
// up on the account (by its cloid) before anything is said. A verdict the
// venue gave is never looked up. Fakes only.

import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/hyperliquid/hl_sent_order_trace.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';

const _market = HlMarket(
  coin: 'OAI',
  wireCoin: 'io:OAI',
  assetId: 110000,
  kind: HlMarketKind.perp,
  szDecimals: 3,
  maxLeverage: 20,
  onlyIsolated: false,
  markPx: 1405.2,
  midPx: 1405.2,
  prevDayPx: 1405.2,
  dayNtlVlm: 0,
  dex: 'io',
  isHip3: true,
);

const _filled = HlOrderResult(
    kind: HlOrderResultKind.filled, oid: 9, filledSz: 0.008, avgPx: 1391.1);

void main() {
  group('an order send with no verdict is unknown', () {
    test('a timeout, a broken connection, a gateway error', () {
      expect(hlOrderOutcomeUnknown(TimeoutException('15 s')), isTrue);
      expect(hlOrderOutcomeUnknown(const SocketException('reset')), isTrue);
      expect(
          hlOrderOutcomeUnknown(
              const HyperliquidApiException(statusCode: 502, body: '')),
          isTrue);
      expect(
          hlOrderOutcomeUnknown(
              const HyperliquidApiException(statusCode: 200, body: '<html>')),
          isTrue);
    });

    test('the venue\'s own answer is a verdict, never looked up', () {
      expect(
          hlOrderOutcomeUnknown(
              const HyperliquidMinNotionalException('minimum value of \$10')),
          isFalse);
      expect(
          hlOrderOutcomeUnknown(
              const HyperliquidInsufficientMarginException('margin')),
          isFalse);
      expect(
          hlOrderOutcomeUnknown(const HyperliquidRejectedException('x')),
          isFalse);
      expect(
          hlOrderOutcomeUnknown(
              const HyperliquidApiException(statusCode: 422, body: 'bad')),
          isFalse);
      expect(hlOrderOutcomeUnknown(StateError('No open position')), isFalse);
    });
  });

  group('the lookup', () {
    test('found on the first read: the order as it stands', () async {
      var reads = 0;
      final trace = await hlTraceSentOrder((cloids, market) async {
        reads++;
        expect(cloids, ['0xc1']);
        expect(market.dex, 'io');
        return const HlSentOrderTrace.found(_filled);
      }, ['0xc1'], _market, every: Duration.zero);
      expect(reads, 1);
      expect(trace.found?.filledSz, 0.008);
    });

    test('unreadable, then nowhere: known as nowhere', () async {
      var reads = 0;
      final trace = await hlTraceSentOrder((_, __) async {
        reads++;
        return reads < 2
            ? const HlSentOrderTrace.unknown()
            : const HlSentOrderTrace.none();
      }, ['0xc1'], _market, every: Duration.zero);
      expect(reads, 2);
      expect(trace.known, isTrue);
      expect(trace.found, isNull);
    });

    test('never readable (or throwing): unknown after the bounded reads',
        () async {
      var reads = 0;
      final trace = await hlTraceSentOrder((_, __) async {
        reads++;
        throw StateError('offline');
      }, ['0xc1'], _market, every: Duration.zero);
      expect(reads, kHlSentOrderTraceReads);
      expect(trace.known, isFalse);
    });
  });
}
