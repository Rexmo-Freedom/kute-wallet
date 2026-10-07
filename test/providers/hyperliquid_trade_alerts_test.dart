// When the in-app trade alerts fire, and that each fires once.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/hyperliquid_order_status.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_trade_alerts_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart';

HlFill _fill({int oid = 1, bool? crossed, bool liquidated = false}) => HlFill(
      coin: 'xyz:TSLA',
      px: 370,
      sz: 1,
      side: 'B',
      time: 1,
      closedPnl: 0,
      fee: 0,
      feeToken: 'USDC',
      oid: oid,
      hash: '0x',
      dir: 'Open Long',
      cloid: null,
      crossed: crossed,
      liquidated: liquidated,
    );

HlOrderUpdate _update(String status, int oid) => HlOrderUpdate(
      status: status,
      statusTimestamp: 1,
      coin: 'BTC',
      oid: oid,
      isBuy: false,
      limitPx: 1,
      sz: 0,
      origSz: 1,
      timestamp: 1,
      cloid: null,
    );

HlPerpPosition _pos({required double mark, double liq = 90}) => HlPerpPosition(
      coin: 'BTC',
      szi: 1,
      entryPx: 100,
      positionValue: mark,
      unrealizedPnl: 0,
      returnOnEquity: 0,
      liquidationPx: liq,
      marginUsed: 10,
      leverageType: 'isolated',
      leverageValue: 10,
      maxLeverage: 40,
    );

void main() {
  var n = 0;
  int seq() => ++n;

  test('a resting order filled alerts once; taker fills do not', () {
    final r = HlTradeAlertRules();
    expect(r.onFills([_fill(crossed: true)], seq), isEmpty);
    final a = r.onFills([_fill(oid: 7, crossed: false)], seq);
    expect(a.single.type, HlTradeAlertType.filled);
    expect(a.single.coin, 'TSLA');
    // A second partial fill of the same order stays quiet.
    expect(r.onFills([_fill(oid: 7, crossed: false)], seq), isEmpty);
  });

  test('a liquidation fill alerts', () {
    final r = HlTradeAlertRules();
    final a = r.onFills([_fill(liquidated: true, crossed: true)], seq);
    expect(a.single.type, HlTradeAlertType.liquidated);
  });

  test('triggers name TP or SL from the order list; some cancels alert', () {
    final r = HlTradeAlertRules();
    final a = r.onOrderUpdates([
      _update('triggered', 1),
      _update('triggered', 2),
      _update('marginCanceled', 3),
      _update('siblingFilledCanceled', 4),
      _update('canceled', 5),
    ], (oid) => oid == 1 ? 'Take Profit Market' : 'Stop Market', seq);
    expect(a.map((x) => x.type), [
      HlTradeAlertType.takeProfit,
      HlTradeAlertType.stopLoss,
      HlTradeAlertType.venueCancel,
    ]);
    expect(a.last.status, 'marginCanceled');
    // Seen once.
    expect(r.onOrderUpdates([_update('triggered', 1)], (_) => null, seq),
        isEmpty);
  });

  test('liquidation risk at 10%, again at 5%, re-armed past 15%', () {
    final r = HlTradeAlertRules();
    expect(r.onPositions([_pos(mark: 120)], (_) => null, seq), isEmpty);
    final first = r.onPositions([_pos(mark: 99)], (_) => null, seq);
    expect(first.single.type, HlTradeAlertType.liquidationRisk);
    expect(first.single.distance, closeTo(9 / 99, 1e-9));
    expect(r.onPositions([_pos(mark: 98)], (_) => null, seq), isEmpty);
    expect(r.onPositions([_pos(mark: 94)], (_) => null, seq), hasLength(1));
    expect(r.onPositions([_pos(mark: 93)], (_) => null, seq), isEmpty);
    r.onPositions([_pos(mark: 110)], (_) => null, seq); // > 15% away
    expect(r.onPositions([_pos(mark: 99)], (_) => null, seq), hasLength(1));
  });

  test('a take-profit or stop-loss within 1% alerts once per approach', () {
    HlOpenOrder order(int oid, String type, double trigger,
            {String coin = 'BTC', bool isTrigger = true}) =>
        HlOpenOrder(
          coin: coin,
          oid: oid,
          isBuy: false,
          limitPx: trigger,
          sz: 1,
          origSz: 1,
          timestamp: 1,
          cloid: null,
          reduceOnly: true,
          orderType: type,
          isTrigger: isTrigger,
          triggerPx: isTrigger ? trigger : null,
        );
    final orders = [
      order(1, 'Take Profit Market', 110),
      order(2, 'Stop Market', 95),
      // A plain limit and another market's stop are not this position's
      // levels.
      order(3, 'Limit', 100.5, isTrigger: false),
      order(4, 'Stop Market', 100.2, coin: 'ETH'),
    ];
    final r = HlTradeAlertRules();
    expect(r.onLevels([_pos(mark: 100)], orders, seq), isEmpty);
    final tp = r.onLevels([_pos(mark: 109.2)], orders, seq);
    expect(tp.single.type, HlTradeAlertType.takeProfitNear);
    expect(tp.single.price, 110);
    expect(tp.single.distance, closeTo(0.8 / 109.2, 1e-9));
    // Hovering at the level stays quiet, and so does backing off a little.
    expect(r.onLevels([_pos(mark: 109.5)], orders, seq), isEmpty);
    expect(r.onLevels([_pos(mark: 108.5)], orders, seq), isEmpty);
    expect(r.onLevels([_pos(mark: 109.3)], orders, seq), isEmpty);
    // Past 2% away it re-arms.
    expect(r.onLevels([_pos(mark: 105)], orders, seq), isEmpty);
    expect(r.onLevels([_pos(mark: 109.4)], orders, seq), hasLength(1));
    final sl = r.onLevels([_pos(mark: 95.5)], orders, seq);
    expect(sl.single.type, HlTradeAlertType.stopLossNear);
    expect(sl.single.type.isWarning, isTrue);
    expect(sl.single.type.isLevelApproach, isTrue);
    // No position, no level.
    expect(HlTradeAlertRules().onLevels(const [], orders, seq), isEmpty);
  });

  test('funding spike only when the position pays, once per 8 hours', () {
    final r = HlTradeAlertRules();
    final t0 = DateTime(2026, 10, 4, 12);
    // Long pays positive funding.
    final a = r.onPositions([_pos(mark: 200)], (_) => 0.0002, seq, now: t0);
    expect(a.single.type, HlTradeAlertType.fundingSpike);
    expect(a.single.dailyCost, closeTo(200 * 0.0002 * 24, 1e-9));
    expect(
        r.onPositions([_pos(mark: 200)], (_) => 0.0002, seq,
            now: t0.add(const Duration(hours: 1))),
        isEmpty);
    // Doubling re-alerts.
    expect(
        r.onPositions([_pos(mark: 200)], (_) => 0.0004, seq,
            now: t0.add(const Duration(hours: 2))),
        hasLength(1));
    // Receiving funding is not a spike.
    expect(
        HlTradeAlertRules()
            .onPositions([_pos(mark: 200)], (_) => -0.001, seq, now: t0),
        isEmpty);
  });

  test('venue statuses read in plain words', () {
    final l10n = l10nForLanguage('en');
    expect(hlStatusIsVenueDecision('canceled'), isFalse);
    expect(hlStatusIsVenueDecision('filled'), isFalse);
    expect(hlStatusIsVenueDecision('reduceOnlyCanceled'), isTrue);
    expect(hlOrderStatusReason(l10n, 'marginCanceled'), l10n.hlOrderEndedMargin);
    expect(hlOrderStatusReason(l10n, 'tickRejected'), l10n.hlOrderEndedRejected);
    expect(hlOrderStatusReason(l10n, 'somethingNew'), l10n.hlOrderEndedOther);
  });
}
