// The crypto cards' live odds: read raw from the market feed's book for
// each Up token a visible card registered, else from the CLOB's REST
// midpoint every 1.5 s, dropped when nobody confirmed them for 10 s, and
// not read at all while the app is in the background or no card is
// registered.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/crypto_live_odds_provider.dart';
import 'package:kute/services/polymarket/crypto_live_odds.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';

void main() {
  late PolymarketLiveBooks books;
  late DateTime now;
  late bool foreground;
  late ProviderContainer container;
  late List<List<String>> restCalls;
  late Future<Map<String, double>> Function(Iterable<String>) answer;

  void book(String asset, String bid, String ask) {
    books.apply(PolymarketBookMessage.fromJson({
      'event_type': 'book',
      'asset_id': asset,
      'market': 'm',
      'bids': [
        {'price': bid, 'size': '10'}
      ],
      'asks': [
        {'price': ask, 'size': '10'}
      ],
      'hash': 'h',
    }));
  }

  setUp(() {
    now = DateTime(2026, 10, 12, 12);
    foreground = true;
    restCalls = [];
    answer = (tokens) async => {for (final t in tokens) t: 0.5};
    books = PolymarketLiveBooks.instance..reset();
    books.clock = () => now;
    container = ProviderContainer(overrides: [
      cryptoOddsClockProvider.overrideWithValue(() => now),
      cryptoOddsForegroundProvider.overrideWithValue(() => foreground),
      cryptoOddsBooksProvider.overrideWithValue(books),
      cryptoOddsMidpointsProvider.overrideWithValue((tokens) {
        restCalls.add(tokens.toList());
        return answer(tokens);
      }),
    ]);
  });

  tearDown(() {
    container.dispose();
    books.reset();
  });

  CryptoLiveOddsNotifier listen() {
    container.listen(cryptoLiveOddsProvider, (_, __) {});
    return container.read(cryptoLiveOddsProvider.notifier);
  }

  test('a registered token shows the book as it stands', () {
    final n = listen();
    book('up', '0.58', '0.60');
    n.watch('up');
    expect(container.read(cryptoLiveOddsProvider)['up'],
        const CryptoLiveOdds(0.59, CryptoOddsSource.websocket));
    // A jump well past ±25% of the last chance shows on the next read.
    book('up', '0.10', '0.12');
    n.tick();
    expect(
        container.read(cryptoLiveOddsProvider)['up']!.up, closeTo(0.11, 1e-9));
  });

  test('a chance nobody confirmed for 10 s is dropped', () {
    // REST answers nothing for the token either.
    answer = (_) async => const {};
    final n = listen();
    book('up', '0.58', '0.60');
    n.watch('up');
    expect(container.read(cryptoLiveOddsProvider)['up'], isNotNull);
    // The feed stops: the book is no longer current.
    now = now.add(const Duration(seconds: 6));
    n.tick();
    expect(container.read(cryptoLiveOddsProvider)['up'], isNotNull);
    now = now.add(const Duration(seconds: 5));
    n.tick();
    expect(container.read(cryptoLiveOddsProvider)['up'], isNull);
  });

  test('nothing is read in the background', () {
    final n = listen();
    foreground = false;
    book('up', '0.58', '0.60');
    n.watch('up');
    expect(container.read(cryptoLiveOddsProvider)['up'], isNull);
    foreground = true;
    n.tick();
    expect(container.read(cryptoLiveOddsProvider)['up'], isNotNull);
  });

  test('the last card leaving forgets its token', () async {
    final n = listen();
    book('up', '0.58', '0.60');
    n.watch('up');
    n.watch('up');
    n.unwatch('up');
    expect(n.watched, {'up'});
    n.unwatch('up');
    expect(n.watched, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(cryptoLiveOddsProvider)['up'], isNull);
  });

  group('REST fallback', () {
    test('every 1.5 s while visible, for the tokens off the feed only',
        () async {
      final n = listen();
      book('btc', '0.58', '0.60'); // on the feed
      n.watch('btc');
      n.watch('eth');
      n.watch('sol');
      // One batched request for both tokens the feed lacks.
      expect(restCalls, [
        ['eth']
      ]);
      await Future<void>.delayed(Duration.zero);
      n.tick();
      // eth registered first; sol joined while within the 1.5 s gap.
      expect(restCalls.length, 1);
      now = now.add(const Duration(milliseconds: 1000));
      n.tick();
      expect(restCalls.length, 1, reason: 'not before 1.5 s');
      now = now.add(const Duration(milliseconds: 500));
      book('btc', '0.58', '0.60'); // the feed stays current
      n.tick();
      expect(restCalls.last, unorderedEquals(['eth', 'sol']));
      await Future<void>.delayed(Duration.zero);
      final s = container.read(cryptoLiveOddsProvider);
      expect(s['eth'], const CryptoLiveOdds(0.5, CryptoOddsSource.rest));
      expect(s['btc']!.source, CryptoOddsSource.websocket);
    });

    test('the feed wins over a REST answer that lands after it', () async {
      final completer = Completer<Map<String, double>>();
      answer = (_) => completer.future;
      final n = listen();
      n.watch('up');
      expect(restCalls.length, 1);
      book('up', '0.70', '0.72');
      n.tick();
      completer.complete({'up': 0.40});
      await Future<void>.delayed(Duration.zero);
      expect(container.read(cryptoLiveOddsProvider)['up'],
          const CryptoLiveOdds(0.71, CryptoOddsSource.websocket));
    });

    test('one request at a time, and slower after failures', () async {
      final completer = Completer<Map<String, double>>();
      answer = (_) => completer.future;
      final n = listen();
      n.watch('up');
      now = now.add(const Duration(seconds: 3));
      n.tick();
      expect(restCalls.length, 1, reason: 'the first is still out');
      completer.completeError(Exception('down'));
      await Future<void>.delayed(Duration.zero);
      answer = (_) async => throw Exception('down');
      n.tick(); // 3 s after the first ask, past the 3 s backoff
      expect(restCalls.length, 2);
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 3));
      n.tick();
      expect(restCalls.length, 2, reason: 'two failures wait 6 s');
      now = now.add(const Duration(seconds: 3));
      n.tick();
      expect(restCalls.length, 3);
      expect(cryptoOddsRestInterval(0), const Duration(milliseconds: 1500));
      expect(cryptoOddsRestInterval(9), kCryptoOddsRestMaxBackoff);
    });

    test('broken REST values never show', () async {
      answer = (_) async => {'up': double.nan};
      final n = listen();
      n.watch('up');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(cryptoLiveOddsProvider)['up'], isNull);
    });

    test('runs on its own timer at 1–2 s while visible and stops when hidden',
        () {
      fakeAsync((async) {
        final start = DateTime(2026, 10, 12, 12);
        now = start;
        final c = ProviderContainer(overrides: [
          cryptoOddsClockProvider
              .overrideWithValue(() => start.add(async.elapsed)),
          cryptoOddsForegroundProvider.overrideWithValue(() => foreground),
          cryptoOddsBooksProvider.overrideWithValue(books),
          cryptoOddsMidpointsProvider.overrideWithValue((tokens) {
            restCalls.add(tokens.toList());
            return Future.value({for (final t in tokens) t: 0.5});
          }),
        ]);
        c.listen(cryptoLiveOddsProvider, (_, __) {});
        final n = c.read(cryptoLiveOddsProvider.notifier);
        n.watch('up');
        async.elapse(const Duration(seconds: 15));
        // One at registration, then one every 1.5 s.
        expect(restCalls.length, inInclusiveRange(8, 11));
        // Background: the timer keeps ticking but asks nothing.
        foreground = false;
        final before = restCalls.length;
        async.elapse(const Duration(seconds: 6));
        expect(restCalls.length, before);
        foreground = true;
        // Hidden (the scope unregisters): nothing more.
        n.unwatch('up');
        async.flushMicrotasks();
        final hidden = restCalls.length;
        async.elapse(const Duration(seconds: 10));
        expect(restCalls.length, hidden);
        c.dispose();
      });
    });
  });
}
