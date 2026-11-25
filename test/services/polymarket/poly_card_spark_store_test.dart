// C · the Predictions cards' tiny charts: their history reads are batched
// (collected until the list comes to rest, a few at a time, one per
// token), cached (10 minutes; 2 for a game in play), cancelled when the
// card goes before its turn, and never asked for under test without a
// fake read.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_card_spark_provider.dart';
import 'package:kute/services/polymarket/poly_card_spark_store.dart';

List<PolymarketPricePoint> _series(double from, double to, {int n = 5}) => [
      for (var i = 0; i < n; i++)
        PolymarketPricePoint(
          timestamp: DateTime.utc(2026, 11, 5).add(Duration(hours: 24 * i)),
          price: from + (to - from) * i / (n - 1),
        ),
    ];

/// A fake history endpoint: every read is held until the test answers it.
class _FakeHistory {
  final List<(String, String)> asked = [];
  final Map<String, Completer<List<PolymarketPricePoint>?>> _open = {};

  Future<List<PolymarketPricePoint>?> read(String token, String interval) {
    asked.add((token, interval));
    return (_open['$token|$interval'] = Completer()).future;
  }

  void answer(String token, String interval, List<PolymarketPricePoint>? p) =>
      _open.remove('$token|$interval')!.complete(p);

  int get open => _open.length;
}

void main() {
  late _FakeHistory api;
  late DateTime now;

  PolyCardSparkStore store({PolyCardSparkPeek? session}) => PolyCardSparkStore(
        fetch: api.read,
        session: session,
        now: () => now,
      );

  setUp(() {
    api = _FakeHistory();
    now = DateTime.utc(2026, 11, 12, 12);
  });

  test('cards that ask while the list moves are read in one batch once it '
      'rests, three at a time, a token once', () {
    fakeAsync((async) {
      final s = store();
      final heard = <String, List<PolymarketPricePoint>>{};
      for (final t in ['a', 'b', 'c', 'd', 'e']) {
        s.watch(t, '1w', (p) => heard[t] = p);
        async.elapse(const Duration(milliseconds: 150));
      }
      // The same token on a second card: no second read.
      s.watch('a', '1w', (_) {});
      // Still moving: nothing asked yet.
      expect(api.asked, isEmpty);
      async.elapse(const Duration(milliseconds: 400));
      expect(api.asked, [('a', '1w'), ('b', '1w'), ('c', '1w')]);
      expect(s.queued, ['d|1w', 'e|1w']);
      api.answer('a', '1w', _series(0.5, 0.6));
      async.flushMicrotasks();
      // A read freed: the next of the batch goes, no new wait.
      expect(api.asked.last, ('d', '1w'));
      expect(heard['a']!.last.price, closeTo(0.6, 1e-9));
      api
        ..answer('b', '1w', _series(0.1, 0.2))
        ..answer('c', '1w', _series(0.1, 0.2));
      async.flushMicrotasks();
      expect(api.asked, hasLength(5));
      expect(s.inFlight, 2);
      s.dispose();
    });
  });

  test('a card that goes before its turn drops its read; one in flight '
      'completes into the cache', () {
    fakeAsync((async) {
      final s = store();
      final goneA = s.watch('a', '1w', (_) {});
      final goneB = s.watch('b', '1w', (_) {});
      goneA();
      async.elapse(const Duration(seconds: 1));
      expect(api.asked, [('b', '1w')]);
      // Scrolled away mid-read: the answer is still kept.
      goneB();
      api.answer('b', '1w', _series(0.3, 0.4));
      async.flushMicrotasks();
      expect(s.cached('b', '1w'), isNotNull);
      // Everyone gone before the batch: no timer left, nothing asked.
      final goneC = s.watch('c', '1w', (_) {});
      goneC();
      async.elapse(const Duration(seconds: 1));
      expect(api.asked, hasLength(1));
      expect(async.pendingTimers, isEmpty);
      s.dispose();
    });
  });

  test('a series is kept 10 minutes (2 for a game in play) and failures '
      'wait before asking again', () {
    fakeAsync((async) {
      final s = store();
      s.watch('a', '1w', (_) {});
      s.watch('g', PolyCardSparkStore.liveInterval, (_) {});
      async.elapse(const Duration(seconds: 1));
      api
        ..answer('a', '1w', _series(0.5, 0.6))
        ..answer('g', '6h', _series(0.4, 0.7));
      async.flushMicrotasks();
      expect(api.asked, hasLength(2));

      // Back on screen within the window: drawn from memory, not read.
      now = now.add(const Duration(minutes: 9));
      s.watch('a', '1w', (_) {});
      s.watch('g', '6h', (_) {});
      async.elapse(const Duration(seconds: 1));
      expect(api.asked.where((a) => a.$1 == 'a'), hasLength(1));
      // The game's line is older than its 2 minutes: read again.
      expect(api.asked.where((a) => a.$1 == 'g'), hasLength(2));
      api.answer('g', '6h', _series(0.4, 0.8));
      async.flushMicrotasks();

      now = now.add(const Duration(minutes: 2));
      s.watch('a', '1w', (_) {});
      async.elapse(const Duration(seconds: 1));
      expect(api.asked.where((a) => a.$1 == 'a'), hasLength(2));
      // A failed read: the old line stays, and no retry for a while.
      api.answer('a', '1w', null);
      async.flushMicrotasks();
      expect(s.cached('a', '1w'), isNotNull);
      s.watch('a', '1w', (_) {});
      async.elapse(const Duration(seconds: 1));
      expect(api.asked.where((a) => a.$1 == 'a'), hasLength(2));
      now = now.add(PolyCardSparkStore.retryAfter);
      s.watch('a', '1w', (_) {});
      async.elapse(const Duration(seconds: 1));
      expect(api.asked.where((a) => a.$1 == 'a'), hasLength(3));
      s.dispose();
    });
  });

  test("what the market sheet's chart already read is drawn at once and "
      'refreshed', () {
    fakeAsync((async) {
      final s = store(
          session: (t, i) => t == 'a' && i == '1w' ? _series(0.2, 0.3) : null);
      var heardDuringWatch = false;
      s.watch('a', '1w', (_) => heardDuringWatch = true);
      expect(heardDuringWatch, isFalse);
      expect(s.cached('a', '1w')!.last.price, closeTo(0.3, 1e-9));
      async.elapse(const Duration(seconds: 1));
      expect(api.asked, [('a', '1w')]);
      s.dispose();
    });
  });

  test('the values a card draws: from kickoff, ending on the figure shown',
      () {
    final points = _series(0.2, 0.6);
    expect(polyCardSparkValues(null), isEmpty);
    expect(polyCardSparkValues(points, live: 0.65),
        [...points.map((p) => p.price), 0.65]);
    final kickoff = points[3].timestamp;
    expect(polyCardSparkValues(points, since: kickoff, live: 0.7),
        [points[3].price, points[4].price, 0.7]);
    // One point is not a line.
    expect(polyCardSparkValues(points.take(1).toList()), isEmpty);
  });

  test('under flutter test the session store asks no network', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      final sub = container.listen(
          polyCardSparkProvider((tokenId: 'a', interval: '1w')), (_, __) {});
      async.elapse(const Duration(seconds: 5));
      expect(sub.read(), isNull);
      expect(container.read(polyCardSparkStoreProvider).fetches, 0);
      expect(async.pendingTimers, isEmpty);
      sub.close();
      container.dispose();
    });
  });
}
