// A modify whose answer never came is looked up by the new cloid AND by the
// order's own oid (the venue's docs say neither which cloid the modified
// order carries nor whether its oid changes): moved either way is moved,
// the old order resting at its old price is "not moved", anything else is
// unconfirmed, never "not moved". Fakes only.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/hyperliquid/hl_sent_order_trace.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/tracking_service.dart';

const _market = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 66000,
  midPx: 66000,
  prevDayPx: 66000,
  dayNtlVlm: 0,
);

HlOpenOrder _order(
        {int oid = 7,
        String? cloid = '0xold',
        double limitPx = 60000,
        double? triggerPx,
        bool isTrigger = false}) =>
    HlOpenOrder(
      coin: 'BTC',
      oid: oid,
      isBuy: false,
      limitPx: limitPx,
      sz: 0.01,
      origSz: 0.01,
      timestamp: 1,
      cloid: cloid,
      reduceOnly: true,
      orderType: isTrigger ? 'Stop Market' : 'Limit',
      isTrigger: isTrigger,
      triggerPx: triggerPx,
    );

HlFill _fill({required int oid, String? cloid}) => HlFill(
    coin: 'BTC',
    px: 61000,
    sz: 0.01,
    side: 'A',
    time: 0,
    closedPnl: 0,
    fee: 0,
    feeToken: 'USDC',
    oid: oid,
    hash: '',
    dir: 'Close Long',
    cloid: cloid);

void main() {
  final before = _order();

  group('hlTraceModifyOf', () {
    test('the new cloid resting: moved', () {
      final t = hlTraceModifyOf(
          before: before,
          newCloid: '0xnew',
          newPx: 61000,
          open: [_order(oid: 8, cloid: '0xnew', limitPx: 61000)],
          fills: const []);
      expect(t.found?.oid, 8);
    });

    test('the old oid resting at the new price (oid and cloid kept): moved',
        () {
      final t = hlTraceModifyOf(
          before: before,
          newCloid: '0xnew',
          newPx: 61000,
          open: [_order(limitPx: 61000)],
          fills: const []);
      expect(t.found?.oid, 7);
      expect(t.found?.kind, HlOrderResultKind.resting);
    });

    test('a trigger moved: its trigger price is what moved', () {
      final stop = _order(isTrigger: true, triggerPx: 62000, limitPx: 58000);
      final t = hlTraceModifyOf(
          before: stop,
          newCloid: '0xnew',
          newPx: 63000,
          open: [_order(isTrigger: true, triggerPx: 63000, limitPx: 58000)],
          fills: const []);
      expect(t.found, isNotNull);
    });

    test('the old order resting at its old price: as it was (nowhere)', () {
      final t = hlTraceModifyOf(
          before: before,
          newCloid: '0xnew',
          newPx: 61000,
          open: [_order()],
          fills: const []);
      expect(t.known, isTrue);
      expect(t.found, isNull);
    });

    test('the old oid gone and nothing under the new cloid: unknown', () {
      final t = hlTraceModifyOf(
          before: before,
          newCloid: '0xnew',
          newPx: 61000,
          open: const [],
          fills: const []);
      expect(t.known, isFalse);
    });

    test('the old order filled: unknown, never "moved" or "not moved"', () {
      final t = hlTraceModifyOf(
          before: before,
          newCloid: '0xnew',
          newPx: 61000,
          open: const [],
          fills: [_fill(oid: 7, cloid: '0xold')]);
      expect(t.known, isFalse);
    });

    test('filled under the new cloid: moved (and filled)', () {
      final t = hlTraceModifyOf(
          before: before,
          newCloid: '0xNEW',
          newPx: 61000,
          open: const [],
          fills: [_fill(oid: 9, cloid: '0xnew')]);
      expect(t.found?.isFilled, isTrue);
    });
  });

  group('the reconciliation decision of a modify with no answer', () {
    setUp(() => TrackingService.debugTrackObserver = (_, __) {});
    tearDown(() => TrackingService.debugTrackObserver = null);

    Future<HlOrderResult> reconcile(List<HlOpenOrder> open) =>
        hlSendReconciled(
          send: () async => throw TimeoutException('15 s'),
          cloid: '0xnew',
          market: _market,
          lookup: (_, __) async => hlTraceModifyOf(
              before: before,
              newCloid: '0xnew',
              newPx: 61000,
              open: open,
              fills: const []),
          action: 'modify',
          window: Duration.zero,
          every: Duration.zero,
        );

    test('kept its oid and cloid, at the new price: the move went through',
        () async {
      final r = await reconcile([_order(limitPx: 61000)]);
      expect(r.oid, 7);
    });

    test('still at the old price for the window: not moved', () async {
      await expectLater(reconcile([_order()]),
          throwsA(isA<HyperliquidOrderNotPlacedException>()));
    });

    test('gone from the book with no new cloid: unconfirmed', () async {
      await expectLater(reconcile(const []),
          throwsA(isA<HyperliquidOrderUnconfirmedException>()));
    });
  });

  test('a market is confirming while one of its orders is looked up', () {
    expect(hlMarketConfirming(const {'0xa': 'BTC'}, 'BTC'), isTrue);
    expect(hlMarketConfirming(const {'0xa': 'ETH'}, 'BTC'), isFalse);
    expect(hlMarketConfirming(const {}, 'BTC'), isFalse);
  });
}
