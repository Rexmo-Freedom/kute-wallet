// The shared Chainlink layer behind the crypto Up/Down cards
// (`cryptoReferencePricesProvider`): PolyBolt is its only source, so
// these cover the subscription it opens, how frames land in the series,
// and how it reconnects (socket drop, refused credentials, credentials
// that appear or change) with an in-memory transport.

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/services/polymarket/polybolt_price_socket.dart';
import 'package:kute/services/polymarket/polymarket_price_source.dart';

class _FakeTransport implements PolyBoltTransport {
  final Uri url;
  final _incoming = StreamController<dynamic>();
  final sent = <String>[];
  bool closedByClient = false;
  @override
  int? closeCode;

  _FakeTransport(this.url);

  @override
  Future<void> get ready => Future.value();
  @override
  Stream<dynamic> get stream => _incoming.stream;
  @override
  void send(String frame) => sent.add(frame);
  @override
  Future<void> close() async {
    closedByClient = true;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  void serverSend(Map<String, dynamic> frame) =>
      _incoming.add(jsonEncode(frame));

  void serverClose({int? code}) {
    closeCode = code;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  List<Map<String, dynamic>> get sentJson =>
      sent.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
}

const _creds = PolyBoltCredentials(
  apiKey: '00000000-0000-4000-8000-000000000000',
  secret: 'c2VjcmV0',
  passphrase: 'pass',
);

Map<String, dynamic> _snapshot(String symbol, List<(int, double)> points) => {
      'v': 1,
      'channel': 'price.crypto.twap',
      'seq': 1,
      'ts': points.last.$1,
      'snapshot': true,
      'payload': {
        'symbol': symbol,
        'window_seconds': 60,
        'source': 'chainlink',
        'data': [
          for (final p in points)
            {
              'timestamp': p.$1,
              'value': p.$2,
              'full_accuracy_value': p.$2.toStringAsFixed(8),
            },
        ],
      },
    };

Map<String, dynamic> _live(String symbol, int ts, double value) => {
      'v': 1,
      'channel': 'price.crypto.twap',
      'seq': 2,
      'ts': ts,
      'payload': {
        'symbol': symbol,
        'value': value,
        'full_accuracy_value': value.toStringAsFixed(8),
        'timestamp': ts,
        'window_seconds': 60,
        'source': 'chainlink',
      },
    };

void main() {
  late List<_FakeTransport> transports;
  late PolyBoltCredentials? creds;

  ProviderContainer makeContainer() {
    transports = [];
    return ProviderContainer(overrides: [
      pmReferenceCredentialsProvider.overrideWithValue(() => creds),
      pmReferenceTransportProvider.overrideWithValue((url) {
        final t = _FakeTransport(url);
        transports.add(t);
        return t;
      }),
      // A banner on screen keeps the feed wanted outside Predictions.
      cryptoCardsOnScreenProvider.overrideWith((_) => 1),
    ]);
  }

  setUp(() => creds = _creds);

  test('authenticates, then subscribes the 60 s TWAP for every Up/Down asset',
      () async {
    fakeAsync((async) {
      final c = makeContainer();
      final sub = c.listen(cryptoReferencePricesProvider, (_, __) {});
      async.flushMicrotasks();

      expect(transports, hasLength(1));
      final t = transports.single;
      expect(t.url.toString(), 'wss://ws-live-v2.polymarket.com/ws');
      expect(t.sentJson.single['op'], 'auth');
      expect(
          c.read(cryptoReferencePricesProvider).awaitingCredentials, isFalse);
      expect(c.read(cryptoReferencePricesProvider).streaming, isTrue);

      t.serverSend({'op': 'authed', 'rid': 'a1'});
      async.flushMicrotasks();
      final subscribe = t.sentJson[1];
      expect(subscribe['op'], 'subscribe');
      final subs =
          (subscribe['subscriptions'] as List).cast<Map<String, dynamic>>();
      expect(subs.map((s) => s['channel']).toSet(), {'price.crypto.twap'});
      expect(subs.map((s) => s['filter']).toList(), [
        for (final s in ['btcusd', 'ethusd', 'solusd', 'xrpusd'])
          {'symbol': s, 'window_seconds': 60},
      ]);

      sub.close();
      c.dispose();
    });
    // The socket's teardown awaits futures completed outside the fake
    // zone, so its close lands on the real event queue.
    await pumpEventQueue();
    expect(transports.single.closedByClient, isTrue);
  });

  test('the snapshot seeds the series and live points extend it', () {
    fakeAsync((async) {
      final c = makeContainer();
      final sub = c.listen(cryptoReferencePricesProvider, (_, __) {});
      async.flushMicrotasks();
      final t = transports.single;
      t.serverSend({'op': 'authed', 'rid': 'a1'});
      t.serverSend(_snapshot('btcusd', [
        (1788973001000, 64120.0),
        (1788973002000, 64121.0),
      ]));
      t.serverSend(_live('btcusd', 1788973003000, 64122.5));
      t.serverSend(_live('ethusd', 1788973003000, 3210.5));
      async.flushMicrotasks();

      final state = c.read(cryptoReferencePricesProvider);
      expect(state.seriesFor('BTC').map((p) => p.price).toList(),
          [64120.0, 64121.0, 64122.5]);
      expect(state.seriesFor('BTC').last.timestamp.millisecondsSinceEpoch,
          1788973003000);
      expect(state.seriesFor('ETH').single.price, 3210.5);
      expect(state.isLive('BTC', DateTime.now()), isTrue);

      sub.close();
      c.dispose();
    });
  });

  test('a dropped socket reconnects, re-authenticates and resubscribes', () {
    fakeAsync((async) {
      final c = makeContainer();
      final sub = c.listen(cryptoReferencePricesProvider, (_, __) {});
      async.flushMicrotasks();
      transports.single.serverSend({'op': 'authed', 'rid': 'a1'});
      async.flushMicrotasks();

      transports.single.serverClose(code: 1006);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(transports, hasLength(2));
      final t = transports[1];
      expect(t.sentJson.single['op'], 'auth');
      t.serverSend({'op': 'authed', 'rid': 'a1'});
      async.flushMicrotasks();
      expect(t.sentJson[1]['op'], 'subscribe');

      sub.close();
      c.dispose();
    });
  });

  test('refused credentials wait the long delay before trying again', () {
    fakeAsync((async) {
      final c = makeContainer();
      final sub = c.listen(cryptoReferencePricesProvider, (_, __) {});
      async.flushMicrotasks();
      transports.single
          .serverSend({'op': 'error', 'rid': 'a1', 'code': 'auth_invalid'});
      async.flushMicrotasks();

      async.elapse(kPmReferenceHardRetryDelay - const Duration(seconds: 1));
      expect(transports, hasLength(1), reason: 'no retry hammering');
      async.elapse(const Duration(seconds: 2));
      expect(transports, hasLength(2));
      expect(transports[1].sentJson.single['op'], 'auth');

      sub.close();
      c.dispose();
    });
  });

  test('a credential change cuts the wait short', () {
    fakeAsync((async) {
      final c = makeContainer();
      final sub = c.listen(cryptoReferencePricesProvider, (_, __) {});
      async.flushMicrotasks();
      transports.single
          .serverSend({'op': 'error', 'rid': 'a1', 'code': 'auth_invalid'});
      async.flushMicrotasks();

      creds = const PolyBoltCredentials(
          apiKey: '11111111-1111-4111-8111-111111111111',
          secret: 'bmV3',
          passphrase: 'new');
      async.elapse(const Duration(seconds: 2));
      expect(transports, hasLength(2));
      expect((transports[1].sentJson.single['auth'] as Map)['apiKey'],
          '11111111-1111-4111-8111-111111111111');

      sub.close();
      c.dispose();
    });
  });

  test('without credentials no socket opens until they appear', () {
    fakeAsync((async) {
      creds = null;
      final c = makeContainer();
      final sub = c.listen(cryptoReferencePricesProvider, (_, __) {});
      async.flushMicrotasks();

      expect(transports, isEmpty);
      final waiting = c.read(cryptoReferencePricesProvider);
      expect(waiting.awaitingCredentials, isTrue);
      expect(waiting.streaming, isTrue, reason: 'cards should fall back');

      async.elapse(const Duration(seconds: 5));
      expect(transports, isEmpty);

      creds = _creds;
      async.elapse(const Duration(seconds: 1));
      expect(transports, hasLength(1));
      expect(
          c.read(cryptoReferencePricesProvider).awaitingCredentials, isFalse);

      // Credentials gone again (switched to a Ledger account): the
      // layer drops the socket and waits; nothing it sends lands.
      final t = transports.single;
      t.serverSend({'op': 'authed', 'rid': 'a1'});
      async.flushMicrotasks();
      creds = null;
      async.elapse(const Duration(seconds: 1));
      t.serverSend(_live('btcusd', 1788973003000, 64122.5));
      async.flushMicrotasks();
      final after = c.read(cryptoReferencePricesProvider);
      expect(after.awaitingCredentials, isTrue);
      expect(after.seriesFor('BTC'), isEmpty);
      expect(transports, hasLength(1));

      sub.close();
      c.dispose();
    });
  });

  test('nothing streams while no card is on screen', () {
    fakeAsync((async) {
      transports = [];
      final c = ProviderContainer(overrides: [
        pmReferenceCredentialsProvider.overrideWithValue(() => creds),
        pmReferenceTransportProvider.overrideWithValue((url) {
          final t = _FakeTransport(url);
          transports.add(t);
          return t;
        }),
      ]);
      final sub = c.listen(cryptoReferencePricesProvider, (_, __) {});
      async.elapse(const Duration(seconds: 3));
      expect(transports, isEmpty);
      expect(c.read(cryptoReferencePricesProvider).streaming, isFalse);
      sub.close();
      c.dispose();
    });
  });
}
