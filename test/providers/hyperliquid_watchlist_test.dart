import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';

HlMarket _m(String coin,
        {String? wire,
        HlMarketKind kind = HlMarketKind.perp,
        double volume = 1000}) =>
    HlMarket(
      coin: coin,
      wireCoin: wire ?? coin,
      assetId: 0,
      kind: kind,
      szDecimals: 2,
      maxLeverage: 10,
      onlyIsolated: false,
      markPx: 1,
      midPx: 1,
      prevDayPx: 1,
      dayNtlVlm: volume,
    );

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hl_watchlist');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('stars newest first, unstars, and survives a restart', () async {
    final container = ProviderContainer();
    final notifier = container.read(hlWatchlistProvider.notifier);
    await _settle();
    expect(notifier.toggle(_m('BTC')), isTrue);
    expect(notifier.toggle(_m('TSLA', wire: 'xyz:TSLA')), isTrue);
    expect(container.read(hlWatchlistProvider), ['perp:xyz:TSLA', 'perp:BTC']);
    expect(notifier.contains(_m('BTC')), isTrue);
    expect(notifier.toggle(_m('BTC')), isFalse);
    expect(container.read(hlWatchlistProvider), ['perp:xyz:TSLA']);
    await _settle();
    container.dispose();

    final again = ProviderContainer();
    again.read(hlWatchlistProvider);
    await _settle();
    expect(again.read(hlWatchlistProvider), ['perp:xyz:TSLA']);
    again.dispose();
  });

  test('a perp and the spot token of one symbol are starred apart', () {
    expect(hlWatchlistKey(_m('HYPE')), 'perp:HYPE');
    expect(hlWatchlistKey(_m('HYPE', wire: '@107', kind: HlMarketKind.spot)),
        'spot:@107');
  });

  test('stars made as Favourites are carried over, once', () async {
    final legacy =
        await Hive.openBox<String>(HlWatchlistNotifier.legacyBoxName);
    await legacy.put('keys', jsonEncode(['perp:BTC', 'spot:@142']));
    await legacy.close();

    final container = ProviderContainer();
    container.read(hlWatchlistProvider);
    await _settle();
    expect(container.read(hlWatchlistProvider), ['perp:BTC', 'spot:@142']);
    // Unstarring one must stick: the old box is not read back in.
    container.read(hlWatchlistProvider.notifier).toggle(_m('BTC'));
    await _settle();
    container.dispose();

    final again = ProviderContainer();
    again.read(hlWatchlistProvider);
    await _settle();
    expect(again.read(hlWatchlistProvider), ['spot:@142']);
    again.dispose();
  });

  test('the Watchlist lists what was starred, newest first, in place', () {
    final universe = [
      _m('BTC', volume: 900),
      _m('ETH', volume: 800),
      _m('UBTC', wire: '@142', kind: HlMarketKind.spot, volume: 700),
    ];
    // Starred order, not volume order; a market the venue dropped is out.
    final watchlist = ['spot:@142', 'perp:GONE', 'perp:ETH'];
    expect(
        hlWatchlistMarkets(watchlist, universe).map((m) => m.coin).toList(),
        ['UBTC', 'ETH']);
    expect(
        hlBrowseListForTab(HlBrowseTab.watchlist, universe,
                watchlist: watchlist)
            .map((m) => m.coin)
            .toList(),
        ['UBTC', 'ETH']);
    // Nothing starred: an empty list, so the pill is hidden.
    expect(hlBrowseListForTab(HlBrowseTab.watchlist, universe), isEmpty);
    expect(hlSubsForTab(HlBrowseTab.watchlist, universe), isEmpty);
    expect(HlBrowseTab.values.first, HlBrowseTab.watchlist);
    expect(HlBrowseTab.watchlist.key, 'watchlist');
  });
}
