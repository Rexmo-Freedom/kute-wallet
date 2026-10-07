// Isolated margin: what can come out, where liquidation moves, and the
// step-up intent binding market, side, direction and exact amount.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show isolatedMarginTarget;
import 'package:kute/screens/hyperliquid/components/hl_adjust_margin_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart';

const _long = HlPerpPosition(
  coin: 'xyz:TSLA',
  szi: 2,
  entryPx: 350,
  positionValue: 740,
  unrealizedPnl: 40,
  returnOnEquity: 0.2,
  liquidationPx: 300,
  marginUsed: 200,
  leverageType: 'isolated',
  leverageValue: 5,
  maxLeverage: 10,
);

const _market = HlMarket(
  coin: 'TSLA',
  wireCoin: 'xyz:TSLA',
  assetId: 110001,
  kind: HlMarketKind.perp,
  szDecimals: 3,
  maxLeverage: 10,
  onlyIsolated: false,
  markPx: 370,
  midPx: 370,
  prevDayPx: 360,
  dayNtlVlm: 1,
  dex: 'xyz',
  isHip3: true,
);

void main() {
  test('removable margin keeps the initial margin of the leverage', () {
    // 740 / 5 = 148 must stay; 52 can come out.
    expect(HlAdjustMarginSheet.removableMargin(_long), 52);
  });

  test('what stays covers 10% of the notional above 10x', () {
    // 25x: the initial margin is 40, but the venue keeps 10% (100) of a
    // 1,000 position, so 50 of 150 can come out, not 110.
    const p = HlPerpPosition(
      coin: 'BTC',
      szi: 0.01,
      entryPx: 100000,
      positionValue: 1000,
      unrealizedPnl: 0,
      returnOnEquity: 0,
      liquidationPx: 96000,
      marginUsed: 150,
      leverageType: 'isolated',
      leverageValue: 25,
      maxLeverage: 40,
    );
    expect(hlRemovableMargin(p), 50);
  });

  test('the money in an isolated position is its margin plus live P&L', () {
    // The venue's marginUsed already holds the snapshot P&L (40); a live
    // mid of 380 makes it 60, so 20 more.
    expect(hlPositionMoney(_long), 200);
    expect(hlPositionMoney(_long, liveMid: 380), 220);
    // A cross position's margin is the account's, not the position's.
    expect(
        hlPositionMoney(const HlPerpPosition(
          coin: 'BTC',
          szi: 1,
          entryPx: 1,
          positionValue: 1,
          unrealizedPnl: 0,
          returnOnEquity: 0,
          liquidationPx: null,
          marginUsed: 1,
          leverageType: 'cross',
          leverageValue: 1,
          maxLeverage: 1,
        )),
        isNull);
  });

  group('the margin lands on the position it was approved for', () {
    test('the same instrument, open, same side, isolated', () {
      expect(
          isolatedMarginTarget(
              market: _market, position: _long, live: const [_long]),
          same(_long));
    });

    test('a market on another dex or a bare symbol is refused', () {
      // Same ticker, the default dex: a different asset id.
      const otherDex = HlMarket(
        coin: 'TSLA',
        wireCoin: 'TSLA',
        assetId: 7,
        kind: HlMarketKind.perp,
        szDecimals: 3,
        maxLeverage: 10,
        onlyIsolated: false,
        markPx: 370,
        midPx: 370,
        prevDayPx: 360,
        dayNtlVlm: 1,
      );
      const heldThere = HlPerpPosition(
        coin: 'TSLA',
        szi: 1,
        entryPx: 350,
        positionValue: 370,
        unrealizedPnl: 20,
        returnOnEquity: 0.1,
        liquidationPx: 300,
        marginUsed: 90,
        leverageType: 'isolated',
        leverageValue: 5,
        maxLeverage: 10,
      );
      // Even with a matching isolated long held on that market, margin
      // approved for xyz:TSLA never goes there.
      expect(
          () => isolatedMarginTarget(
              market: otherDex,
              position: _long,
              live: const [_long, heldThere]),
          throwsStateError);
    });

    test('a closed, flipped or cross position is refused', () {
      expect(
          () => isolatedMarginTarget(
              market: _market, position: _long, live: const []),
          throwsStateError);
      const flipped = HlPerpPosition(
        coin: 'xyz:TSLA',
        szi: -2,
        entryPx: 350,
        positionValue: 740,
        unrealizedPnl: 0,
        returnOnEquity: 0,
        liquidationPx: 400,
        marginUsed: 200,
        leverageType: 'isolated',
        leverageValue: 5,
        maxLeverage: 10,
      );
      expect(
          () => isolatedMarginTarget(
              market: _market, position: _long, live: const [flipped]),
          throwsStateError);
      const cross = HlPerpPosition(
        coin: 'xyz:TSLA',
        szi: 2,
        entryPx: 350,
        positionValue: 740,
        unrealizedPnl: 0,
        returnOnEquity: 0,
        liquidationPx: 300,
        marginUsed: 148,
        leverageType: 'cross',
        leverageValue: 5,
        maxLeverage: 10,
      );
      expect(
          () => isolatedMarginTarget(
              market: _market, position: _long, live: const [cross]),
          throwsStateError);
    });
  });

  test('added margin moves liquidation away, removed brings it closer', () {
    expect(HlAdjustMarginSheet.liquidationAfter(_long, 20), 290);
    expect(HlAdjustMarginSheet.liquidationAfter(_long, -20), 310);
  });

  test('the grant names the direction and the exact amount', () {
    final add = HlIntents.isolatedMargin(
        walletId: 'w', market: _market, positionIsLong: true, usd: 25.5);
    final remove = HlIntents.isolatedMargin(
        walletId: 'w', market: _market, positionIsLong: true, usd: -25.5);
    expect(add.limits['margin_direction'], 'add');
    expect(remove.limits['margin_direction'], 'remove');
    expect(add.amountMax, remove.amountMax);
    expect(add.limits, isNot(equals(remove.limits)));
  });
}
