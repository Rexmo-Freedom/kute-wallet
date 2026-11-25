import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';

PolymarketEvent _event(String slug,
        {String id = '1', bool closed = false, bool ended = false}) =>
    PolymarketEvent(
      id: id,
      slug: slug,
      closed: closed,
      ended: ended,
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
    PolyWatchlistNotifier.resetCheck();
    PolyWatchlistNotifier.reader = (_) async => throw StateError('offline');
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
    // Every toggle on disk, in order, before the "restart".
    await notifier.saved;
    container.dispose();

    final again = ProviderContainer();
    again.read(polyWatchlistProvider);
    await again.read(polyWatchlistProvider.notifier).loaded;
    expect(again.read(polyWatchlistProvider), ['nfl-ind-was']);
    again.dispose();
  });

  test('markets that are over or gone leave the list and its count',
      () async {
    final container = ProviderContainer();
    final notifier = container.read(polyWatchlistProvider.notifier);
    notifier.toggle(_event('fed-decision'));
    notifier.toggle(_event('nfl-ind-was'));
    notifier.toggle(_event('ceasefire'));
    notifier.toggle(_event('gone'));
    final asked = container.read(polyWatchlistProvider);
    // Starred while the read was out: kept.
    notifier.toggle(_event('new-star'));
    notifier.forgetOver(asked, [
      _event('fed-decision'),
      _event('nfl-ind-was', ended: true),
      _event('ceasefire', closed: true),
    ]);
    expect(container.read(polyWatchlistProvider),
        ['new-star', 'fed-decision']);
    await notifier.loaded;
    await notifier.saved;
    container.dispose();
  });

  test('the stored list is checked on load; a failed read keeps it',
      () async {
    final first = ProviderContainer();
    final n = first.read(polyWatchlistProvider.notifier);
    n.toggle(_event('fed-decision'));
    n.toggle(_event('nfl-ind-was'));
    await n.saved;
    first.dispose();
    await Hive.close();

    // Offline: nothing is dropped.
    final offline = ProviderContainer();
    offline.read(polyWatchlistProvider);
    final o = offline.read(polyWatchlistProvider.notifier);
    await o.loaded;
    await o.checked;
    expect(offline.read(polyWatchlistProvider), hasLength(2));
    offline.dispose();
    await Hive.close();

    // The ended market goes as soon as the list loads.
    PolyWatchlistNotifier.resetCheck();
    PolyWatchlistNotifier.reader = (slugs) async =>
        [_event('fed-decision'), _event('nfl-ind-was', ended: true)];
    final online = ProviderContainer();
    online.read(polyWatchlistProvider);
    final w = online.read(polyWatchlistProvider.notifier);
    await w.loaded;
    await w.checked;
    expect(online.read(polyWatchlistProvider), ['fed-decision']);
    await w.saved;
    online.dispose();
  });

  test('the Watchlist pill has its own route', () {
    expect(PolyPill.watchlist.key, 'watchlist');
    expect(polyBrowseSelectionFromRouteKey('predictions/watchlist')?.pill,
        PolyPill.watchlist);
  });
}
