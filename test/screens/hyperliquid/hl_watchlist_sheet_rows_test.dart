// The watchlist sheet's search is Search's own (founder, 13 November 2026:
// "do exactly like we do in the search"): one result per underlying, so
// "nv" lists Nvidia once, as its most traded listing.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_watchlist_sheet.dart';

HlMarket _perp(String wire, double vol) => HlMarket(
      coin: wire.contains(':') ? wire.split(':').last : wire,
      wireCoin: wire,
      assetId: 0,
      kind: HlMarketKind.perp,
      szDecimals: 3,
      maxLeverage: 20,
      onlyIsolated: false,
      markPx: 160,
      midPx: 160,
      prevDayPx: 165,
      dayNtlVlm: vol,
      category: 'stocks',
      dex: wire.contains(':') ? wire.split(':').first : '',
      isHip3: wire.contains(':'),
    );

void main() {
  final xyz = _perp('xyz:NVDA', 1.6e9);
  final io = _perp('io:NVDA', 35e6);
  final km = _perp('km:NVDA', 1e6);
  final universe = [km, io, xyz];

  test('a search lists Nvidia once, its most traded listing', () async {
    final hits = await hlSearchMarkets(universe, 'nv');
    final rows = hlWatchlistSearchRows('nv', hits);
    expect(rows.map((m) => m.wireCoin), ['xyz:NVDA']);
  });

  test('with no search, one listing per underlying', () {
    final rows = hlWatchlistSheetRows(universe, const []);
    expect(rows.map((m) => m.wireCoin), ['xyz:NVDA']);
  });
}
