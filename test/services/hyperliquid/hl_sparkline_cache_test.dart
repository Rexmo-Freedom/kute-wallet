import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';

/// A venue that answers every coin with [closes] and records each ask.
class _Venue {
  _Venue([this.closes = const [1, 2, 3]]);
  List<double> closes;
  final asked = <String>[];
  Future<List<double>> fetch(String wire) async {
    asked.add(wire);
    return closes;
  }
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  final day1 = DateTime.utc(2026, 10, 5, 9);
  final day1Late = DateTime.utc(2026, 10, 5, 23, 59);
  final day2 = DateTime.utc(2026, 10, 6, 0, 1);

  late Directory dir;
  late Box<String> box;
  var boxSeq = 0;
  late String boxName;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hl_sparkline');
    Hive.init(dir.path);
    boxName = 'hl_spark_test_${boxSeq++}';
    box = await Hive.openBox<String>(boxName);
  });

  tearDown(() async {
    // Let the store's unawaited disk writes land before the box closes.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await Hive.close();
    await dir.delete(recursive: true);
  });

  HlSparklineStore store(_Venue venue, DateTime Function() now,
          {int maxInFlight = 4}) =>
      HlSparklineStore(
        fetch: venue.fetch,
        now: now,
        maxInFlight: maxInFlight,
        boxName: boxName,
      );

  test('one fetch per coin per day, however many cards ask', () async {
    final venue = _Venue();
    var now = day1;
    final s = store(venue, () => now);
    expect(s.cached('BTC'), isNull);
    s.request('BTC');
    s.request('BTC'); // a second card, same coin, while in flight
    await _until(() => s.cached('BTC') != null);
    expect(venue.asked, ['BTC']);
    // Later the same UTC day: drawn from the cache, never asked again.
    now = day1Late;
    s.request('BTC');
    await pumpEventQueue();
    expect(venue.asked, ['BTC']);
    expect(s.cached('BTC')!.closes, [1, 2, 3]);
  });

  test('a later open the same day reuses the disk copy without a request',
      () async {
    final venue = _Venue([10, 11, 12]);
    final first = store(venue, () => day1);
    first.request('xyz:TSLA');
    await _until(() => box.get('xyz:TSLA') != null);
    expect(venue.asked, ['xyz:TSLA']);

    // The app is reopened: a new store over the same box.
    final again = _Venue();
    final second = store(again, () => day1Late);
    final cached = second.cached('xyz:TSLA');
    expect(cached, isNotNull);
    expect(cached!.closes, [10, 11, 12]);
    expect(cached.day, hlUtcDay(day1));
    second.request('xyz:TSLA');
    await pumpEventQueue();
    expect(again.asked, isEmpty);
  });

  test('a series from a previous UTC day is drawn at once and refetched once',
      () async {
    final first = store(_Venue([10, 11, 12]), () => day1);
    first.request('@142');
    await _until(() => box.get('@142') != null);

    final venue = _Venue([11, 12, 13]);
    final s = store(venue, () => day2);
    final updates = <HlSparkline>[];
    s.listen('@142', updates.add);
    // Yesterday's line is there before any request.
    expect(s.cached('@142')!.closes, [10, 11, 12]);
    s.request('@142');
    s.request('@142');
    await _until(() => updates.isNotEmpty);
    expect(venue.asked, ['@142']);
    expect(updates.single.closes, [11, 12, 13]);
    expect(updates.single.day, hlUtcDay(day2));
    s.request('@142');
    await pumpEventQueue();
    expect(venue.asked, ['@142']);
    await _until(() => box.get('@142')!.startsWith('v1;${hlUtcDay(day2)};'));
    expect(HlSparklineStore.decode(box.get('@142')!)!.closes, [11, 12, 13]);
  });

  test('a failed answer is not cached and not asked again for 15 minutes',
      () async {
    final venue = _Venue(const []);
    var now = day1;
    final s = store(venue, () => now);
    s.request('ETH');
    await pumpEventQueue();
    expect(venue.asked, ['ETH']);
    expect(s.cached('ETH'), isNull);
    expect(box.get('ETH'), isNull);
    now = day1.add(const Duration(minutes: 5));
    s.request('ETH');
    await pumpEventQueue();
    expect(venue.asked, ['ETH']);
    now = day1.add(const Duration(minutes: 16));
    venue.closes = [5, 6];
    s.request('ETH');
    await _until(() => s.cached('ETH') != null);
    expect(venue.asked, ['ETH', 'ETH']);
  });

  test('at most four requests in flight; a card gone before its turn drops out',
      () async {
    final pending = <String, Completer<List<double>>>{};
    final s = HlSparklineStore(
      fetch: (wire) => (pending[wire] = Completer<List<double>>()).future,
      now: () => day1,
      boxName: boxName,
    );
    final coins = [for (var i = 0; i < 10; i++) 'C$i'];
    for (final c in coins) {
      s.request(c);
    }
    expect(s.inFlight, 4);
    expect(pending.keys, ['C0', 'C1', 'C2', 'C3']);
    expect(s.queued, ['C4', 'C5', 'C6', 'C7', 'C8', 'C9']);

    // C5 scrolled far away before its turn.
    s.cancel('C5');
    pending['C0']!.complete([1, 2]);
    await pumpEventQueue();
    expect(s.inFlight, 4);
    expect(pending.keys, ['C0', 'C1', 'C2', 'C3', 'C4']);

    for (final c in ['C1', 'C2', 'C3', 'C4']) {
      pending[c]!.complete([1, 2]);
    }
    await pumpEventQueue();
    expect(s.inFlight, 4);
    for (final c in ['C6', 'C7', 'C8', 'C9']) {
      pending[c]!.complete([1, 2]);
    }
    await pumpEventQueue();
    expect(s.inFlight, 0);
    expect(pending.keys, isNot(contains('C5')));
    expect(pending, hasLength(9));
  });

  test('the live price moves only the last point', () {
    // Today's series: the forming candle's close becomes the live price.
    expect(hlSparklineWithLivePrice([100, 102, 104], 105), [100, 102, 105]);
    // Yesterday's series (today's on its way): the live price is today.
    expect(hlSparklineWithLivePrice([100, 102, 104], 105, appendLive: true),
        [100, 102, 104, 105]);
    // The cached list itself is never changed.
    final cached = List<double>.unmodifiable(<double>[100, 102, 104]);
    hlSparklineWithLivePrice(cached, 101);
    expect(cached, [100, 102, 104]);
    // One candle: two points so a line draws.
    expect(hlSparklineWithLivePrice([50], 51), [50, 51]);
    // Non-positive closes are dropped.
    expect(hlSparklineWithLivePrice([0, 100, 104], 105), [100, 105]);
    // Raw spot pair units: rescaled whole, shape kept.
    expect(hlSparklineWithLivePrice([1, 2], 200000), [100000, 200000]);
    // No live price yet: the series as is.
    expect(hlSparklineWithLivePrice([1, 2], 0), [1, 2]);
  });

  test('the disk copy keeps 300 coins and 30 days', () async {
    final today = hlUtcDay(day1);
    for (var i = 0; i < 320; i++) {
      // 320 coins fetched over the last 20 days, plus stale ones below.
      await box.put('K$i', 'v1;${today - (i % 20)};1,2');
    }
    await box.put('OLD', 'v1;${today - 31};1,2');
    await box.put('BAD', 'garbage');
    final s = store(_Venue(), () => day1);
    s.prune(box);
    await _until(() => box.length <= HlSparklineStore.maxEntries);
    expect(box.length, HlSparklineStore.maxEntries);
    expect(box.get('OLD'), isNull);
    expect(box.get('BAD'), isNull);
    // The newest fetches are the ones kept.
    expect(box.get('K0'), isNotNull);
    expect(box.get('K20'), isNotNull);
  });

  test('a series older than 30 days is not drawn and is fetched again',
      () async {
    await box.put('SOL', 'v1;${hlUtcDay(day1) - 40};1,2');
    final venue = _Venue();
    final s = store(venue, () => day1);
    expect(s.cached('SOL'), isNull);
    s.request('SOL');
    await _until(() => s.cached('SOL') != null);
    expect(venue.asked, ['SOL']);
  });

  test('cards share one request per coin and cancel on dispose', () async {
    final pending = <String, Completer<List<double>>>{};
    final asked = <String>[];
    final container = ProviderContainer(overrides: [
      hyperliquidSparklineStoreProvider.overrideWithValue(HlSparklineStore(
        fetch: (wire) {
          asked.add(wire);
          return (pending[wire] = Completer<List<double>>()).future;
        },
        now: () => day1,
        maxInFlight: 1,
        boxName: boxName,
      )),
    ]);
    addTearDown(container.dispose);
    final a = container.listen(hyperliquidSparklineProvider('BTC'), (_, __) {});
    final b = container.listen(hyperliquidSparklineProvider('BTC'), (_, __) {});
    final eth =
        container.listen(hyperliquidSparklineProvider('ETH'), (_, __) {});
    expect(asked, ['BTC']);
    // The ETH card scrolls away while it waits for BTC's slot.
    eth.close();
    await pumpEventQueue();
    pending['BTC']!.complete([1, 2, 3]);
    // The answer reaches the cards after the store's own async steps; wait
    // for it rather than for a fixed number of event-queue turns.
    await _until(() =>
        a.read()?.closes.isNotEmpty == true &&
        b.read()?.closes.isNotEmpty == true);
    expect(a.read()!.closes, [1, 2, 3]);
    expect(b.read()!.closes, [1, 2, 3]);
    expect(asked, ['BTC']);
  });
}
