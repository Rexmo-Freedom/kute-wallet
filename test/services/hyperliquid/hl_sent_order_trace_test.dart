// An order whose answer never came may well have been taken: it is looked
// up on the account (by its cloid) before anything is said. A verdict the
// venue gave is never looked up. Fakes only.

import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/hyperliquid_error_message.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/hyperliquid/hl_failure_analytics.dart';
import 'package:kute/services/tracking_service.dart';
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

  // Founder, on device: an Investing order "failed" and was placed. Its
  // send timed out (or the connection dropped, or the gateway answered
  // 5xx) while the exchange was still taking it. Only the close looked
  // the order up, and even that believed the FIRST read that came back
  // empty; the opens, spot orders and limits said "failed" at once.
  group('an order send with no answer is reconciled before anything is said',
      () {
    var events = <(String, Map<String, Object?>?)>[];
    setUp(() {
      events = [];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    });
    tearDown(() => TrackingService.debugTrackObserver = null);

    // The account: empty on the first read, the fill on the second (the
    // exchange was still working through the order the app gave up on).
    Future<HlSentOrderTrace> Function(List<String>, HlMarket) lateFill() {
      var reads = 0;
      return (cloids, market) async => ++reads < 2
          ? const HlSentOrderTrace.none()
          : const HlSentOrderTrace.found(_filled);
    }

    test('the old lookup believed the first empty read (the bug)', () async {
      final trace =
          await hlTraceSentOrder(lateFill(), ['0xc1'], _market, every: Duration.zero);
      expect(trace.known, isTrue);
      expect(trace.found, isNull, reason: 'reported as never placed');
    });

    test('the reconciling lookup reads the whole window and finds it',
        () async {
      final trace = await hlReconcileSentOrder(lateFill(), ['0xc1'], _market,
          every: Duration.zero);
      expect(trace.found?.filledSz, 0.008);
    });

    test('a timeout, then the fill on the account: placed, with the venue\'s '
        'figures', () async {
      final confirming = <bool>[];
      final result = await hlSendReconciled(
        send: () async => throw TimeoutException('15 s'),
        cloid: '0xc1',
        market: _market,
        lookup: lateFill(),
        action: 'open',
        onConfirming: confirming.add,
        every: Duration.zero,
      );
      expect(result.isFilled, isTrue);
      expect(result.filledSz, 0.008);
      expect(result.avgPx, 1391.1);
      expect(confirming, [true, false]);
      final event =
          events.singleWhere((e) => e.$1 == 'hl_order_outcome_reconciled').$2!;
      expect(event['outcome'], 'filled');
      expect(event['cause'], 'timeout');
      expect(event['action'], 'open');
      expect(event.keys, isNot(contains('cloid')));
    });

    test('a resting limit found after a 502: placed (resting)', () async {
      final result = await hlSendReconciled(
        send: () async =>
            throw const HyperliquidApiException(statusCode: 502, body: ''),
        cloid: '0xc1',
        market: _market,
        lookup: (_, __) async => const HlSentOrderTrace.found(
            HlOrderResult(kind: HlOrderResultKind.resting, oid: 3)),
        action: 'open',
        every: Duration.zero,
      );
      expect(result.kind, HlOrderResultKind.resting);
      expect(events.single.$2!['outcome'], 'resting');
      expect(events.single.$2!['cause'], 'gateway');
    });

    test('nowhere for the whole window: not placed (said as such)', () async {
      var reads = 0;
      final sent = hlSendReconciled(
        send: () async => throw const SocketException('reset'),
        cloid: '0xc1',
        market: _market,
        lookup: (_, __) async {
          reads++;
          return const HlSentOrderTrace.none();
        },
        action: 'open',
        // The 20 s / 2 s window, scaled down.
        window: const Duration(milliseconds: 200),
        every: const Duration(milliseconds: 20),
      );
      await expectLater(
          sent, throwsA(isA<HyperliquidOrderNotPlacedException>()));
      // Read across the window (every 20 ms for 200 ms), not once; never
      // more reads than the window holds.
      expect(reads, inInclusiveRange(2, 11));
      expect(events.single.$2!['outcome'], 'not_placed');
      final l10n = l10nForLanguage('en');
      expect(hlTradeErrorMessage(l10n, const HyperliquidOrderNotPlacedException()),
          'This order did not go through. Nothing was placed.');
      expect(hlFailureStage(const HyperliquidOrderNotPlacedException()),
          'not_placed');
    });

    test('slow reads: the window is bounded on the clock, not stretched by '
        'them', () async {
      var reads = 0;
      final clock = Stopwatch()..start();
      final trace = await hlReconcileSentOrder(
        (_, __) async {
          reads++;
          // A read on a bad connection takes a while itself.
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return const HlSentOrderTrace.none();
        },
        const ['0xc1'],
        _market,
        window: const Duration(milliseconds: 200),
        every: const Duration(milliseconds: 20),
      );
      clock.stop();
      expect(trace.known, isTrue);
      expect(trace.found, isNull);
      // Counted in reads alone it would make 11 of them (~1 s); bounded on
      // the clock it ends a read or two past the window.
      expect(reads, lessThan(6));
      expect(clock.elapsed, lessThan(const Duration(milliseconds: 700)));
    });

    test('an empty read followed by unreadable ones: unconfirmed, not "not '
        'placed"', () async {
      var reads = 0;
      final sent = hlSendReconciled(
        send: () async => throw TimeoutException('15 s'),
        cloid: '0xc1',
        market: _market,
        lookup: (_, __) async {
          if (++reads == 1) return const HlSentOrderTrace.none();
          throw StateError('offline');
        },
        action: 'close',
        every: Duration.zero,
      );
      await expectLater(
          sent, throwsA(isA<HyperliquidOrderUnconfirmedException>()));
      expect(events.single.$2!['outcome'], 'unconfirmed');
      final l10n = l10nForLanguage('en');
      // Said as unconfirmed (check your orders), never as a rejection.
      expect(
          hlTradeErrorMessage(l10n, const HyperliquidOrderUnconfirmedException()),
          l10n.investingSubmissionUnknown);
      expect(hlOrderOutcomeUnknown(const HyperliquidOrderUnconfirmedException()),
          isTrue);
      expect(hlOrderOutcomeUnknown(const HyperliquidOrderNotPlacedException()),
          isFalse);
    });

    test('a verdict the venue gave is never looked up', () async {
      var reads = 0;
      final sent = hlSendReconciled(
        send: () async =>
            throw const HyperliquidInsufficientMarginException('margin'),
        cloid: '0xc1',
        market: _market,
        lookup: (_, __) async {
          reads++;
          return const HlSentOrderTrace.found(_filled);
        },
        action: 'open',
        every: Duration.zero,
      );
      await expectLater(
          sent, throwsA(isA<HyperliquidInsufficientMarginException>()));
      expect(reads, 0);
      expect(events, isEmpty);
    });
  });
}
