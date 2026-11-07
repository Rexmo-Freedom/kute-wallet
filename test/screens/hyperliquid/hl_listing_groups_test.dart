// One underlying, one primary listing (founder, 7 November 2026: search
// for "nv" listed Nvidia twice and two Nvidia tokens, "why on search there
// are many things the same?"). Nvidia trades as xyz:NVDA and io:NVDA and
// as the NVDAX and EQNVDA tokens; the numbers below are the venue's own
// on 7 November 2026. The grouping (hlListingGroups) picks the most
// liquid perp as the primary and keeps the rest as alternatives, and the
// lists, the big squares and the market map show the same primary. The
// tokens read as Nvidia and show its logo, never EQNVDA's blank plate.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_map.dart';
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart'
    show hlTrendingStrip;

HlMarket _perp(String dex, String coin,
        {required double volume,
        double oi = 0,
        double px = 187.42,
        String category = 'stocks'}) =>
    HlMarket(
      coin: coin,
      wireCoin: '$dex:$coin',
      assetId: 110000,
      kind: HlMarketKind.perp,
      szDecimals: 3,
      maxLeverage: 20,
      onlyIsolated: false,
      markPx: px,
      midPx: px,
      prevDayPx: 188.6,
      dayNtlVlm: volume,
      openInterest: oi,
      category: category,
      dex: dex,
      isHip3: true,
      iconUrl: HlMarket.hlIconUrl('$dex:$coin'),
    );

HlMarket _spot(String coin, String wire,
        {required double volume, double px = 188.13}) =>
    HlMarket(
      coin: coin,
      wireCoin: wire,
      assetId: 10000 + int.parse(wire.substring(1)),
      kind: HlMarketKind.spot,
      szDecimals: 2,
      maxLeverage: 1,
      onlyIsolated: false,
      markPx: px,
      midPx: px,
      prevDayPx: 188.28,
      dayNtlVlm: volume,
      iconUrl: HlMarket.hlSpotIconUrl(coin),
    );

/// The four Nvidia listings, as the browse universe resolves them: io's
/// perp arrives unannotated, the tokens as plain crypto.
List<HlMarket> nvidiaUniverse({double xyzVolume = 14296610}) =>
    resolveHlBrowseUniverse([
      _perp('xyz', 'NVDA', volume: xyzVolume, oi: 486914),
      _perp('io', 'NVDA',
          volume: 1234312, oi: 10651.8, px: 187.48, category: 'other'),
      _perp('xyz', 'TSLA', volume: 4826836, px: 410),
    ], [
      _spot('NVDAX', '@702', volume: 23818),
      _spot('EQNVDA', '@1155', volume: 2171, px: 187.39),
    ]);

HlMarket _byWire(List<HlMarket> l, String wire) =>
    l.firstWhere((m) => m.wireCoin == wire);

List<String> _wires(Iterable<HlMarket> l) => [for (final m in l) m.wireCoin];

void main() {
  test(
      'two exchanges and two tokens: one primary, by volume, and three '
      'alternatives', () {
    final universe = nvidiaUniverse();
    final groups = hlListingGroups(universe);
    final nvidia = groups.singleWhere((g) => g.primary.coin == 'NVDA');
    expect(nvidia.primary.wireCoin, 'xyz:NVDA');
    // Perps first, the more traded first; then the tokens, the same way.
    expect(_wires(nvidia.alternatives), ['io:NVDA', '@702', '@1155']);
    expect(nvidia.ticker, 'NVDA');
    // Tesla trades once: a group of its own, nothing behind it.
    final tesla = groups.singleWhere((g) => g.primary.coin == 'TSLA');
    expect(tesla.alternatives, isEmpty);
    expect(groups, hasLength(2));

    // The primary follows the volume: io more traded, io leads.
    final flipped = hlListingGroups(nvidiaUniverse(xyzVolume: 900000))
        .singleWhere((g) => g.ticker == 'NVDA');
    expect(flipped.primary.wireCoin, 'io:NVDA');
    expect(_wires(flipped.alternatives), ['xyz:NVDA', '@702', '@1155']);
  });

  test(
      'equal volume: the larger open interest in dollars leads, and a perp '
      'always leads a token', () {
    final a = _perp('xyz', 'NVDA', volume: 100, oi: 10);
    final b = _perp('io', 'NVDA', volume: 100, oi: 20);
    expect(hlCompareListings(b, a), lessThan(0));
    // A token traded far more is still not the primary while a perp is.
    final token = _spot('NVDAX', '@702', volume: 1e9);
    final group = hlListingGroups(resolveHlBrowseUniverse([a], [token])).single;
    expect(group.primary.wireCoin, 'xyz:NVDA');
  });

  test(
      'without the perps (the stock gate closed) the most traded token '
      'is the primary, still Nvidia', () {
    final universe = nvidiaUniverse();
    final tokensOnly = [
      for (final m in universe)
        if (m.isSpot) m
    ];
    final group = hlListingGroups(tokensOnly).single;
    expect(group.primary.wireCoin, '@702');
    expect(_wires(group.alternatives), ['@1155']);
    expect(group.ticker, 'NVDA');
  });

  test(
      'a token that holds a stock files under that stock: class, name, '
      'logo and keywords', () {
    final universe = nvidiaUniverse();
    final nvdax = _byWire(universe, '@702');
    final eqnvda = _byWire(universe, '@1155');
    for (final token in [nvdax, eqnvda]) {
      expect(token.wrappedTicker, 'NVDA');
      expect(token.category, 'stocks');
      // The xyz perp's logo, not the token's own art.
      expect(token.iconUrl, 'https://app.hyperliquid.xyz/coins/xyz:NVDA.svg');
      expect(hlUnderlyingKey(token),
          hlUnderlyingKey(_byWire(universe, 'xyz:NVDA')));
    }
    // A perp is never a wrapper, and an ordinary token is its own coin.
    expect(_byWire(universe, 'xyz:NVDA').wrappedTicker, isNull);
    expect(_spot('HYPE', '@107', volume: 1).wrappedTicker, isNull);
  });

  test(
      'the browse lists show one row per underlying; the Watchlist lists '
      'what was starred', () {
    final universe = nvidiaUniverse();
    expect(
        _wires(hlBrowseListForTab(HlBrowseTab.tradfi, universe,
            sub: HlBrowseSub.stocks)),
        ['xyz:NVDA', 'xyz:TSLA']);
    expect(_wires(hlBrowseListForTab(HlBrowseTab.perps, universe)),
        ['xyz:NVDA', 'xyz:TSLA']);
    // Spot lists tokens only: the more traded Nvidia token stands for both.
    expect(_wires(hlBrowseListForTab(HlBrowseTab.spot, universe)), ['@702']);
    expect(_wires(hlBrowseListForTab(HlBrowseTab.trending, universe)),
        ['xyz:NVDA', 'xyz:TSLA']);
    expect(
        _wires(hlBrowseListForTab(HlBrowseTab.watchlist, universe,
            watchlist: ['perp:io:NVDA', 'perp:xyz:NVDA'])),
        ['io:NVDA', 'xyz:NVDA']);
  });

  test('the stock gate: the perps go, the tokens stay, one Nvidia row', () {
    // hlMarketsOfferedUnderPolicy with hyperliquid.stocks denied keeps
    // exactly the markets that are not stock perps.
    final universe = [
      for (final m in nvidiaUniverse())
        if (!isHlStockPerp(m)) m
    ];
    expect(universe.where((m) => !m.isSpot), isEmpty);
    expect(
        _wires(hlBrowseListForTab(HlBrowseTab.tradfi, universe,
            sub: HlBrowseSub.stocks)),
        ['@702']);
  });

  test('the market map and the big squares show the same primary', () {
    final universe = nvidiaUniverse();
    final tiles = [for (final e in hlMarketMapEntries(universe)) e.market];
    expect(
        tiles.where((m) => m.underlyingTicker == 'NVDA').map((m) => m.wireCoin),
        ['xyz:NVDA']);
    final squares =
        hlTrendingStrip(universe, const [], min: 1, fallback: false);
    expect(
        squares
            .where((m) => m.underlyingTicker == 'NVDA')
            .map((m) => m.wireCoin),
        ['xyz:NVDA']);
  });

  group('logo', () {
    setUp(() => HlMarketDirectory.remember(nvidiaUniverse()));

    test('a token that holds a stock shows the stock perp\'s logo first', () {
      final urls = hlIconUrlsFor(
          'EQNVDA', '@1155', HlMarket.hlSpotIconUrl('EQNVDA'), 'stocks');
      expect(urls.first, 'https://app.hyperliquid.xyz/coins/xyz:NVDA.svg');
      // Its own art only after the stock's, and the stock logo CDN by the
      // stock's ticker.
      expect(urls.indexOf('https://app.hyperliquid.xyz/coins/EQNVDA_spot.svg'),
          greaterThan(0));
      expect(urls, contains('https://assets.parqet.com/logos/symbol/NVDA'));
      expect(urls,
          isNot(contains('https://assets.parqet.com/logos/symbol/EQNVDA')));
      expect(hlIconUnderlying('NVDAX'), 'NVDA');
      expect(hlIconUnderlying('EQSPY'), 'SP500');
    });

    test(
        'art drawn inside a nested <svg> is a miss: the next candidate or '
        'the letter tile, never a blank plate', () {
      // EQNVDA_spot.svg as the venue serves it: a beige plate, the mark in
      // a nested <svg> that flutter_svg drops.
      const eqx = '<svg xmlns="http://www.w3.org/2000/svg" width="512" '
          'height="512" viewBox="0 0 512 512"><rect width="512" height="512" '
          'fill="#f3ead6"></rect><svg x="98.57" y="151.93" width="314.85" '
          'height="208.15" viewBox="0.040 4.080 23.960 15.840"><path '
          'fill="#76B900" d="M8.9 8.8v-1.4a6.7 6.7 0 0 1 .4 0z"/></svg></svg>';
      expect(hlSvgNestsSvg(eqx), isTrue);
      expect(hlIconArtFromSvg(Uint8List.fromList(utf8.encode(eqx))), isNull);
      // A plain logo still draws.
      const plain = '<svg xmlns="http://www.w3.org/2000/svg" '
          'viewBox="0 0 10 10"><path fill="#76B900" d="M0 0h10v10z"/></svg>';
      expect(hlSvgNestsSvg(plain), isFalse);
      expect(
          hlIconArtFromSvg(Uint8List.fromList(utf8.encode(plain))), isNotNull);
    });
  });
}
