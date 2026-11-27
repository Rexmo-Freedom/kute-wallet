// The side rules of a protective order, the same on the close sheet's
// Advanced page and the chart's drag: a long's stop under the price and
// take over it, a short's the mirror; a limit on the closing side of its
// trigger; a stop past liquidation warned; a limit across the price said.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/screens/hyperliquid/components/hl_protect_rules.dart';

HlOpenOrder _order({
  int oid = 1,
  String coin = 'BTC',
  bool isBuy = false,
  String orderType = 'Stop Market',
  bool isTrigger = true,
  bool reduceOnly = true,
  bool isPositionTpsl = false,
  bool detailsKnown = true,
  double? triggerPx = 60000,
}) =>
    HlOpenOrder(
      coin: coin,
      oid: oid,
      isBuy: isBuy,
      limitPx: 57000,
      sz: 0.5,
      origSz: 0.5,
      timestamp: oid,
      cloid: null,
      reduceOnly: reduceOnly,
      orderType: orderType,
      isTrigger: isTrigger,
      triggerPx: triggerPx,
      isPositionTpsl: isPositionTpsl,
      detailsKnown: detailsKnown,
    );

void main() {
  const mark = 66000.0;

  group('stop and take, long and short', () {
    test('long (closed by a sell): stop under the price, take over it', () {
      expect(
          hlProtectIssue(
              closeIsBuy: false, tpsl: 'sl', trigger: 60000, mark: mark),
          HlProtectIssue.none);
      expect(
          hlProtectIssue(
              closeIsBuy: false, tpsl: 'sl', trigger: 67000, mark: mark),
          HlProtectIssue.stopAboveMark);
      // The untouched prefill the sheet used to offer: the price itself.
      expect(
          hlProtectIssue(
              closeIsBuy: false, tpsl: 'sl', trigger: mark, mark: mark),
          HlProtectIssue.stopAboveMark);
      expect(
          hlProtectIssue(
              closeIsBuy: false, tpsl: 'tp', trigger: 70000, mark: mark),
          HlProtectIssue.none);
      expect(
          hlProtectIssue(
              closeIsBuy: false, tpsl: 'tp', trigger: 65000, mark: mark),
          HlProtectIssue.takeBelowMark);
    });

    test('short (closed by a buy): stop over the price, take under it', () {
      expect(
          hlProtectIssue(
              closeIsBuy: true, tpsl: 'sl', trigger: 70000, mark: mark),
          HlProtectIssue.none);
      expect(
          hlProtectIssue(
              closeIsBuy: true, tpsl: 'sl', trigger: 65000, mark: mark),
          HlProtectIssue.stopBelowMark);
      expect(
          hlProtectIssue(
              closeIsBuy: true, tpsl: 'tp', trigger: 60000, mark: mark),
          HlProtectIssue.none);
      expect(
          hlProtectIssue(
              closeIsBuy: true, tpsl: 'tp', trigger: 67000, mark: mark),
          HlProtectIssue.takeAboveMark);
    });

    test('a stop / take limit rests on the closing side of its trigger', () {
      expect(
          hlProtectIssue(
              closeIsBuy: false,
              tpsl: 'sl',
              trigger: 60000,
              mark: mark,
              limitPx: 59500),
          HlProtectIssue.none);
      expect(
          hlProtectIssue(
              closeIsBuy: false,
              tpsl: 'sl',
              trigger: 60000,
              mark: mark,
              limitPx: 60500),
          HlProtectIssue.limitAboveTrigger);
      expect(
          hlProtectIssue(
              closeIsBuy: true,
              tpsl: 'sl',
              trigger: 70000,
              mark: mark,
              limitPx: 69000),
          HlProtectIssue.limitBelowTrigger);
      expect(
          hlProtectIssue(
              closeIsBuy: true,
              tpsl: 'tp',
              trigger: 60000,
              mark: mark,
              limitPx: 60100),
          HlProtectIssue.none);
    });
  });

  test('a stop past the liquidation price is a warning case', () {
    // Long liquidated at 58,000: a stop at 57,000 never fires first.
    expect(
        hlStopPastLiquidation(
            closeIsBuy: false, trigger: 57000, liquidation: 58000),
        isTrue);
    expect(
        hlStopPastLiquidation(
            closeIsBuy: false, trigger: 60000, liquidation: 58000),
        isFalse);
    // Short liquidated at 74,000.
    expect(
        hlStopPastLiquidation(
            closeIsBuy: true, trigger: 75000, liquidation: 74000),
        isTrue);
    expect(
        hlStopPastLiquidation(
            closeIsBuy: true, trigger: 70000, liquidation: 74000),
        isFalse);
    expect(
        hlStopPastLiquidation(
            closeIsBuy: false, trigger: 57000, liquidation: null),
        isFalse);
  });

  test('a limit across the price fills now as a taker', () {
    expect(hlLimitCrossesNow(isBuy: false, limitPx: 65000, mark: mark), isTrue);
    expect(
        hlLimitCrossesNow(isBuy: false, limitPx: 67000, mark: mark), isFalse);
    expect(hlLimitCrossesNow(isBuy: true, limitPx: 67000, mark: mark), isTrue);
    expect(hlLimitCrossesNow(isBuy: true, limitPx: 65000, mark: mark), isFalse);
  });

  test('protective orders: reduce-only or position triggers and trailing '
      'stops whose kind is known; never an entry trigger or a WS-only row', () {
    final sl = _order(oid: 1);
    final tp = _order(oid: 2, orderType: 'Take Profit Market', triggerPx: 70000);
    final trail = _order(
        oid: 3, orderType: 'Trailing Stop Market', isTrigger: false);
    final entry = _order(oid: 4, reduceOnly: false);
    final pending = _order(
        oid: 5,
        orderType: '',
        isTrigger: false,
        triggerPx: null,
        detailsKnown: false);
    final limit = _order(oid: 6, orderType: 'Limit', isTrigger: false);
    final position = _order(oid: 7, reduceOnly: false, isPositionTpsl: true);
    final other = _order(oid: 8, coin: 'ETH');
    final all = [trail, tp, entry, pending, limit, position, other, sl];
    expect(hlProtectiveOrdersFor(all, 'BTC').map((o) => o.oid),
        [position, sl, tp, trail].map((o) => o.oid));
    expect(hlStopLossesFor(all, 'BTC').map((o) => o.oid), [7, 1]);
  });
}
