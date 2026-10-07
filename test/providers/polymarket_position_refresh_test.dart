import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Position;

Position position(
        {bool redeemable = false, double size = 5, double price = 1}) =>
    Position(
        proxyWallet: 'wallet',
        asset: '1',
        conditionId: 'condition',
        size: size,
        avgPrice: 0.5,
        initialValue: 2.5,
        currentValue: 5,
        cashPnl: 2.5,
        percentPnl: 100,
        totalBought: 5,
        realizedPnl: 0,
        percentRealizedPnl: 0,
        curPrice: price,
        redeemable: redeemable,
        title: 'Market',
        slug: 'market',
        eventSlug: 'market',
        outcome: 'Yes',
        outcomeIndex: 0,
        oppositeOutcome: 'No',
        oppositeAsset: '2');

void main() {
  test(
      'claimability changes notify even when position identity and price match',
      () {
    final open = position();
    final claimable = position(redeemable: true);
    expect(open, claimable, reason: 'Upstream equality only compares identity');
    expect(PolymarketTradingState(openPositions: [open]),
        isNot(PolymarketTradingState(openPositions: [claimable])));
  });
  test('partial sales and price updates notify, identical refreshes stay equal',
      () {
    final state = PolymarketTradingState(openPositions: [position()]);
    expect(state, PolymarketTradingState(openPositions: [position()]));
    expect(state,
        isNot(PolymarketTradingState(openPositions: [position(size: 4)])));
    expect(state,
        isNot(PolymarketTradingState(openPositions: [position(price: 0.8)])));
  });
}
