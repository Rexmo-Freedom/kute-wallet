// The portfolio Builder's fee row: Kute's fee on every Hyperliquid leg plus
// the venue's taker estimate, totalled across the run, priced exactly as
// placement attaches it.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/screens/shared/hyperliquid_fee_summary.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_legs_provider.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_placement.dart';
import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';

const _builder = HlBuilderInfo(
  builderAddress: '0x0000000000000000000000000000000000000001',
  defaultFeeTenthsBp: 10,
  maxFeeRate: '0.01%',
);

const _fees = {
  'userCrossRate': '0.00045',
  'userAddRate': '0.00015',
  'userSpotCrossRate': '0.0007',
  'userSpotAddRate': '0.0004',
  'activeReferralDiscount': '0.0',
};

const _legs = [
  TradeBuilderLeg(coin: 'BTC', isSpot: false, isLong: true, amountUsd: 10000),
  TradeBuilderLeg(coin: 'ETH', isSpot: false, isLong: false, amountUsd: 5000),
  TradeBuilderLeg(coin: 'HYPE', isSpot: true, amountUsd: 2000),
];

HlMarket _market(TradeBuilderLeg leg, {String dex = ''}) => HlMarket(
      coin: leg.coin,
      wireCoin: leg.coin,
      assetId: 0,
      kind: leg.isSpot ? HlMarketKind.spot : HlMarketKind.perp,
      szDecimals: 4,
      maxLeverage: 40,
      onlyIsolated: false,
      markPx: 1,
      midPx: 1,
      prevDayPx: 1,
      dayNtlVlm: 1,
      dex: dex,
      isHip3: dex.isNotEmpty,
    );

/// The review's fee legs with every market loaded.
List<HyperliquidFeeLeg> _feeLegs(List<TradeBuilderLeg> legs) =>
    [for (final l in legs) builderTradeFeeLeg(l, _market(l))];

/// What the venue charges Kute's builder on a fill of [notional]: the
/// order's `builder.f` (tenths of a basis point) as placement signs it.
double _chargedOn(double notional) {
  final action =
      buildOrderAction(orders: const [], builder: _builder.asOrderFee);
  final f = (action['builder'] as Map)['f'] as int;
  return notional * f / 100000;
}

void main() {
  test('Kute fee is 1 bp of each leg', () {
    final leg = builderTradeFeeLeg(_legs[0], null);
    expect(leg.notional, 10000);
    expect(hyperliquidKuteFeeUsd(leg, feeTenthsBp: _builder.defaultFeeTenthsBp),
        closeTo(1.00, 1e-9));
  });

  test('fees sum across legs: Kute fee plus taker estimate', () {
    final legs = _feeLegs(_legs);
    final totals = hyperliquidFeeTotals(legs,
        builderKnown: true,
        feeTenthsBp: _builder.defaultFeeTenthsBp,
        userFees: _fees);
    // 1 bp on each perp leg; spot buys carry none, as on the order slip.
    expect(totals.kute, closeTo(1.00 + 0.50, 1e-9));
    // Taker rate at the account's tier: perp cross rate, spot cross rate.
    expect(totals.exchange,
        closeTo(10000 * 0.00045 + 5000 * 0.00045 + 2000 * 0.0007, 1e-9));
  });

  test('shown Kute fee equals the builder fee attached at placement', () {
    var charged = 0.0;
    final shown = hyperliquidFeeTotals(
      _feeLegs(_legs),
      builderKnown: true,
      feeTenthsBp: _builder.defaultFeeTenthsBp,
    ).kute!;
    for (final leg in _legs) {
      if (leg.isSpot) continue;
      // placeTradeBuilderLeg opens margin=amountUsd at builderTradeLeverage.
      charged += _chargedOn(leg.amountUsd * builderTradeLeverage);
    }
    expect((shown - charged).abs(), lessThan(0.01));
    expect(shown, closeTo(1.50, 1e-9));
  });

  test('unknown published fee shows no Kute figure; no builder is zero', () {
    final legs = [builderTradeFeeLeg(_legs[0], null)];
    expect(hyperliquidFeeTotals(legs, builderKnown: false).kute, isNull);
    expect(hyperliquidFeeTotals(legs, builderKnown: true).kute, 0);
  });

  test('a HIP-3 or unresolved leg leaves the venue estimate unknown', () {
    const stock = TradeBuilderLeg(coin: 'AAPL', isSpot: false, amountUsd: 1000);
    for (final extra in [
      builderTradeFeeLeg(stock, _market(stock, dex: 'xyz')),
      builderTradeFeeLeg(stock, null),
    ]) {
      final totals = hyperliquidFeeTotals(
          [builderTradeFeeLeg(_legs[0], _market(_legs[0])), extra],
          builderKnown: true,
          feeTenthsBp: _builder.defaultFeeTenthsBp,
          userFees: _fees);
      expect(totals.exchange, isNull);
      // Kute's fee is still exact: 1 bp on both legs.
      expect(totals.kute, closeTo(1.10, 1e-9));
    }
  });
}
