// A fake Investing universe for the Trending strip's tests and its
// on-demand render: main-dex crypto with the day's big obscure movers
// (XPL, LIT), builder-dex stocks, indices and pre-IPO markets (Anthropic
// on three builders and as a spot token), commodities (gold twice), a
// thin stock, one with no previous-day price and an FX pair.

import 'package:kute/models/hyperliquid_market.dart';

HlMarket hlFixtureMarket(
  String coin, {
  String dex = '',
  String category = 'crypto',
  double px = 100,
  double prev = 100,
  double vlm = 1e6,
  bool spot = false,
  String? wire,
  String? annotatedName,
  String? unitAssetName,
}) =>
    HlMarket(
      coin: coin,
      wireCoin: wire ?? (dex.isEmpty ? coin : '$dex:$coin'),
      assetId: coin.hashCode & 0xffff,
      kind: spot ? HlMarketKind.spot : HlMarketKind.perp,
      szDecimals: 2,
      maxLeverage: 10,
      onlyIsolated: false,
      markPx: px,
      midPx: px,
      prevDayPx: prev,
      dayNtlVlm: vlm,
      category: category,
      dex: dex,
      isHip3: dex.isNotEmpty,
      annotatedName: annotatedName,
      unitAssetName: unitAssetName,
    );

/// A move of [pct] percent from 100.
double up(double pct) => 100 * (1 + pct / 100);

/// The universe, most traded first like the provider's.
///
/// Hype (volume × (1 + |change %| / 10)), one per underlying:
///   TSLA   4.0e8 × 1.3  = 5.20e8
///   NVDA   3.0e8 × 1.1  = 3.30e8
///   GOLD   2.5e8 × 1.15 = 2.875e8 (xyz; flx:GOLD is the same gold)
///   ANTH   1.5e8 × 1.8  = 2.70e8  (io; xyz:ANT moved more on less
///                                  volume, para:ANTH and the ANT token
///                                  traded less: all one Anthropic)
///   SP500  2.0e8 × 1.05 = 2.10e8
///   AAPL   1.2e8 × 1.02 = 1.224e8
///   SILVER 8.0e7 × 1.2  = 9.6e7
///   MSFT   9.0e7 × 1.01 = 9.09e7
///   CL     6.0e7 × 1.4  = 8.4e7
///   NATGAS 4.0e7 × 1.6  = 6.4e7
/// Left out: MU (thin), META (no previous-day price), EUR (FX), and the
/// crypto.
final List<HlMarket> hlTrendingFixture = [
  hlFixtureMarket('BTC', px: up(1), vlm: 9e9),
  hlFixtureMarket('ETH', px: up(2), vlm: 8e9),
  hlFixtureMarket('SOL', px: up(3), vlm: 7e9),
  hlFixtureMarket('NEAR', px: up(-9), vlm: 1e9),
  hlFixtureMarket('EUR', dex: 'xyz', category: 'fx', px: up(0.1), vlm: 5e8),
  hlFixtureMarket('TSLA', dex: 'xyz', category: 'stocks', px: up(3), vlm: 4e8),
  hlFixtureMarket('XPL', px: up(25), vlm: 3e8),
  hlFixtureMarket('NVDA', dex: 'xyz', category: 'stocks', px: up(1), vlm: 3e8),
  hlFixtureMarket('GOLD',
      dex: 'xyz', category: 'commodities', px: up(1.5), vlm: 2.5e8),
  hlFixtureMarket('LIT', px: up(20), vlm: 2e8),
  hlFixtureMarket('SP500',
      dex: 'xyz', category: 'indices', px: up(0.5), vlm: 2e8),
  hlFixtureMarket('ANTH',
      dex: 'io',
      category: 'preipo',
      px: up(8),
      vlm: 1.5e8,
      annotatedName: 'ANT'),
  hlFixtureMarket('AAPL',
      dex: 'xyz', category: 'stocks', px: up(0.2), vlm: 1.2e8),
  hlFixtureMarket('ANT',
      dex: 'xyz',
      category: 'preipo',
      px: up(30),
      vlm: 1e8,
      annotatedName: 'ANT'),
  hlFixtureMarket('MSFT',
      dex: 'xyz', category: 'stocks', px: up(-0.1), vlm: 9e7),
  hlFixtureMarket('SILVER',
      dex: 'xyz', category: 'commodities', px: up(2), vlm: 8e7),
  hlFixtureMarket('CL',
      dex: 'xyz',
      category: 'commodities',
      px: up(-4),
      vlm: 6e7,
      annotatedName: 'WTIOIL'),
  hlFixtureMarket('GOLD',
      dex: 'flx', category: 'commodities', px: up(1.6), vlm: 5e7),
  hlFixtureMarket('NATGAS',
      dex: 'xyz', category: 'commodities', px: up(6), vlm: 4e7),
  hlFixtureMarket('ANTH',
      dex: 'para',
      category: 'preipo',
      px: up(9),
      vlm: 2e7,
      annotatedName: 'ANT'),
  hlFixtureMarket('META',
      dex: 'xyz', category: 'stocks', px: 700, prev: 0, vlm: 1e8),
  hlFixtureMarket('ANT',
      spot: true,
      wire: '@62',
      category: 'preipo',
      px: up(5),
      vlm: 6e4,
      annotatedName: 'ANT'),
  hlFixtureMarket('MU', dex: 'xyz', category: 'stocks', px: up(40), vlm: 1e4),
];
