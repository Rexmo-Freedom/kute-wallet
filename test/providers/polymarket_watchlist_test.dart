import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';

PolymarketEvent _event(String slug, {String id = '1'}) => PolymarketEvent(
      id: id,
      slug: slug,
      title: slug,
      volume: 0,
      liquidity: 0,
      category: 'politics',
      conditionId: '',
      outcomes: const [],
    );

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('watchlist');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('stars newest first, unstars, and survives a restart', () async {
    final container = ProviderContainer();
    final notifier = container.read(polyWatchlistProvider.notifier);
    expect(notifier.toggle(_event('fed-decision')), isTrue);
    expect(notifier.toggle(_event('nfl-ind-was')), isTrue);
    expect(container.read(polyWatchlistProvider),
        ['nfl-ind-was', 'fed-decision']);
    // A drilled-in outcome carries its parent's slug: same entry.
    expect(notifier.toggle(_event('fed-decision', id: '1-No change')),
        isFalse);
    expect(container.read(polyWatchlistProvider), ['nfl-ind-was']);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    container.dispose();

    final again = ProviderContainer();
    again.read(polyWatchlistProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(again.read(polyWatchlistProvider), ['nfl-ind-was']);
    again.dispose();
  });

  test('the Watchlist pill has its own route', () {
    expect(PolyPill.watchlist.key, 'watchlist');
    expect(polyBrowseSelectionFromRouteKey('predictions/watchlist')?.pill,
        PolyPill.watchlist);
  });
}
