import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/polybolt_price_socket.dart';

/// In-memory stand-in for the WebSocket so the client's auth →
/// subscribe → price flow, error handling and reconnects run without a
/// network.
class FakeTransport implements PolyBoltTransport {
  final Uri url;
  final _incoming = StreamController<dynamic>();
  final sent = <String>[];
  final readyCompleter = Completer<void>();
  bool closedByClient = false;
  @override
  int? closeCode;

  FakeTransport(this.url, {bool readyNow = true}) {
    if (readyNow) readyCompleter.complete();
  }

  @override
  Future<void> get ready => readyCompleter.future;
  @override
  Stream<dynamic> get stream => _incoming.stream;
  @override
  void send(String frame) => sent.add(frame);
  @override
  Future<void> close() async {
    closedByClient = true;
    if (_incoming.isClosed) return;
    // A single-subscription controller's close() future only completes
    // once a listener drains it; during the handshake nobody listens yet.
    if (_incoming.hasListener) {
      await _incoming.close();
    } else {
      unawaited(_incoming.close());
    }
  }

  /// Server → client JSON frame.
  void serverSend(Map<String, dynamic> frame) => _incoming.add(jsonEncode(frame));

  /// Server closes the socket with [code].
  Future<void> serverClose({int? code}) async {
    closeCode = code;
    if (!_incoming.isClosed) await _incoming.close();
  }

  List<Map<String, dynamic>> get sentJson =>
      sent.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
}

const creds = PolyBoltCredentials(
  apiKey: '00000000-0000-4000-8000-000000000000',
  secret: 'c2VjcmV0',
  passphrase: 'pass',
);

const symbols = {'BTC': 'btcusd', 'ETH': 'ethusd', 'SOL': 'solusd', 'XRP': 'xrpusd'};

Map<String, dynamic> twapLive(String symbol, num value,
        {String? exact, int ts = 1788973002000, int seq = 3}) =>
    {
      'v': 1,
      'channel': 'price.crypto.twap',
      'seq': seq,
      'ts': ts,
      'payload': {
        'symbol': symbol,
        'value': value,
        'full_accuracy_value': exact ?? value.toString(),
        'timestamp': ts,
        'window_seconds': 60,
        'source': 'chainlink',
      },
    };

Future<void> pump([int ms = 0]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('frame builders', () {
    test('auth frame carries the CLOB credential trio under auth', () {
      expect(
        jsonEncode(PolyBoltPriceSocket.authFrame(creds)),
        '{"op":"auth","rid":"a1","auth":{"apiKey":"00000000-0000-4000-8000-000000000000",'
        '"secret":"c2VjcmV0","passphrase":"pass"}}',
      );
    });

    test('twap subscribe frame batches symbols with window_seconds 60', () {
      final frame = PolyBoltPriceSocket.subscribeFrame(['btcusd', 'ethusd']);
      expect(
        jsonEncode(frame),
        '{"op":"subscribe","rid":"s1","subscriptions":['
        '{"channel":"price.crypto.twap","filter":{"symbol":"btcusd","window_seconds":60}},'
        '{"channel":"price.crypto.twap","filter":{"symbol":"ethusd","window_seconds":60}}]}',
      );
    });

    test('spot subscribe frame has no window_seconds', () {
      final frame = PolyBoltPriceSocket.subscribeFrame(['btcusd'],
          channel: kPolyBoltCryptoSpotChannel);
      expect(
        jsonEncode(frame),
        '{"op":"subscribe","rid":"s1","subscriptions":['
        '{"channel":"price.crypto","filter":{"symbol":"btcusd"}}]}',
      );
    });

    test('ping frame', () {
      expect(jsonEncode(PolyBoltPriceSocket.pingFrame()), '{"op":"ping","rid":"p1"}');
    });
  });

  group('polyBoltSymbolForAsset', () {
    test('lowercases and appends usd', () {
      expect(polyBoltSymbolForAsset('BTC'), 'btcusd');
      expect(polyBoltSymbolForAsset('xrp'), 'xrpusd');
    });

    test('normalises legacy RTDS spellings', () {
      expect(polyBoltSymbolForAsset('btc/usd'), 'btcusd');
      expect(polyBoltSymbolForAsset('ETH-USD'), 'ethusd');
      expect(polyBoltSymbolForAsset('solusdt'), 'solusd');
      expect(polyBoltSymbolForAsset('BTCUSD'), 'btcusd');
    });
  });

  group('parsePriceFrame', () {
    test('live twap envelope prefers full_accuracy_value', () {
      final p = PolyBoltPriceSocket.parsePriceFrame(
          twapLive('btcusd', 64120.7, exact: '64120.70000001'));
      expect(p, isNotNull);
      expect(p!.symbol, 'btcusd');
      expect(p.price, 64120.70000001);
      expect(p.timestampMs, 1788973002000);
      expect(p.channel, 'price.crypto.twap');
      expect(p.isSnapshot, isFalse);
    });

    test('falls back to float value when exact string is absent', () {
      final json = twapLive('ethusd', 3210.5);
      (json['payload'] as Map).remove('full_accuracy_value');
      expect(PolyBoltPriceSocket.parsePriceFrame(json)!.price, 3210.5);
    });

    test('snapshot batch yields the newest point', () {
      final p = PolyBoltPriceSocket.parsePriceFrame({
        'v': 1,
        'channel': 'price.crypto.twap',
        'seq': 1,
        'ts': 1788973000000,
        'snapshot': true,
        'payload': {
          'symbol': 'btcusd',
          'window_seconds': 60,
          'source': 'chainlink',
          'data': [
            {'timestamp': 1788972881000, 'value': 64125.1, 'full_accuracy_value': '64125.10000000'},
            {'timestamp': 1788972880000, 'value': 64123.5, 'full_accuracy_value': '64123.50000000'},
          ],
        },
      });
      expect(p, isNotNull);
      expect(p!.price, 64125.1);
      expect(p.timestampMs, 1788972881000);
      expect(p.isSnapshot, isTrue);
    });

    test('empty snapshot batch yields nothing', () {
      expect(
        PolyBoltPriceSocket.parsePriceFrame({
          'v': 1,
          'channel': 'price.crypto.twap',
          'seq': 1,
          'ts': 1,
          'snapshot': true,
          'payload': {'symbol': 'btcusd', 'window_seconds': 60, 'source': 'chainlink', 'data': []},
        }),
        isNull,
      );
    });

    test('docs realtime-data variant (topic/type, string value) parses', () {
      final p = PolyBoltPriceSocket.parsePriceFrame({
        'topic': 'prices.crypto.twap',
        'type': 'update',
        'timestamp': 1788886177000,
        'seq': 3,
        'payload': {
          'symbol': 'btcusd',
          'timestamp': 1788886177000,
          'value': '78803.715261094101516288',
          'windowSeconds': 60,
        },
      });
      expect(p, isNotNull);
      expect(p!.price, closeTo(78803.7152610941, 1e-6));
      expect(p.channel, 'prices.crypto.twap');
    });

    test('symbol is lowercased', () {
      expect(PolyBoltPriceSocket.parsePriceFrame(twapLive('BTCUSD', 1.0))!.symbol, 'btcusd');
    });

    test('acks, errors and pongs are not prices', () {
      expect(PolyBoltPriceSocket.parsePriceFrame({'op': 'authed', 'rid': 'a1'}), isNull);
      expect(PolyBoltPriceSocket.parsePriceFrame({'op': 'subscribed', 'channel': 'price.crypto.twap'}), isNull);
      expect(PolyBoltPriceSocket.parsePriceFrame({'op': 'error', 'code': 'auth_required'}), isNull);
      expect(PolyBoltPriceSocket.parsePriceFrame({'op': 'pong', 'rid': 'p1'}), isNull);
    });

    test('non-positive, missing or malformed prices are dropped', () {
      expect(PolyBoltPriceSocket.parsePriceFrame(twapLive('btcusd', 0, exact: '0')), isNull);
      expect(PolyBoltPriceSocket.parsePriceFrame(twapLive('btcusd', -1, exact: '-1')), isNull);
      expect(PolyBoltPriceSocket.parsePriceFrame(twapLive('btcusd', 1, exact: 'nan-ish'))?.price, 1.0,
          reason: 'bad exact string falls back to the float value');
      expect(PolyBoltPriceSocket.parsePriceFrame({'v': 1, 'channel': 'price.crypto.twap', 'payload': 'x'}), isNull);
      expect(PolyBoltPriceSocket.parsePriceFrame({'v': 1, 'channel': 'price.crypto.twap', 'payload': {'value': 5}}), isNull);
      expect(PolyBoltPriceSocket.parsePriceFrame({'payload': {'symbol': 'btcusd', 'value': 5}}), isNull,
          reason: 'no channel/topic');
    });
  });

  group('parsePricePoints', () {
    test('snapshot batch keeps the whole history, oldest first, in event time', () {
      final points = PolyBoltPriceSocket.parsePricePoints({
        'v': 1,
        'channel': 'price.crypto.twap',
        'seq': 1,
        'ts': 1788973003000,
        'snapshot': true,
        'payload': {
          'symbol': 'btcusd',
          'window_seconds': 60,
          'source': 'chainlink',
          'data': [
            {'timestamp': 1788973002000, 'value': 64121.0, 'full_accuracy_value': '64121.00000000'},
            {'timestamp': 1788973001000, 'value': 64120.0, 'full_accuracy_value': '64120.00000000'},
            {'timestamp': 1788973003000, 'value': 'bad'},
          ],
        },
      });
      expect(points.map((p) => p.t.millisecondsSinceEpoch).toList(),
          [1788973001000, 1788973002000]);
      expect(points.map((p) => p.p).toList(), [64120.0, 64121.0]);
    });

    test('live frame yields one point at the source timestamp', () {
      final points = PolyBoltPriceSocket.parsePricePoints(
          twapLive('ethusd', 3210.5, exact: '3210.50000000', ts: 1788973005000));
      expect(points, hasLength(1));
      expect(points.single.p, 3210.5);
      expect(points.single.t.millisecondsSinceEpoch, 1788973005000);
    });

    test('an E18-scaled exact value never reaches the screen', () {
      final points = PolyBoltPriceSocket.parsePricePoints(twapLive(
          'btcusd', 64120.7, exact: '64120700000000000000000'));
      expect(points.single.p, 64120.7);
    });

    test('acks and errors carry no points', () {
      expect(PolyBoltPriceSocket.parsePricePoints({'op': 'authed', 'rid': 'a1'}), isEmpty);
      expect(PolyBoltPriceSocket.parsePricePoints(
          {'v': 1, 'channel': 'price.crypto.twap', 'snapshot': true, 'payload': []}), isEmpty);
    });
  });

  group('PolyBoltPriceSocket.isHardFailure', () {
    test('refused credentials and policy closes are hard', () {
      for (final code in ['auth_invalid', 'auth_expired', 'auth_required',
          'auth_attempts', 'close_4001']) {
        expect(PolyBoltPriceSocket.isHardFailure(PolyBoltAuthException(code)),
            isTrue, reason: code);
      }
      expect(
          PolyBoltPriceSocket.isHardFailure(
              const PolyBoltDisconnectedException('policy', closeCode: 4008)),
          isTrue);
    });

    test('an unreachable verifier, missing credentials and dropped sockets are transient', () {
      expect(PolyBoltPriceSocket.isHardFailure(
          const PolyBoltAuthException('auth_unavailable')), isFalse);
      expect(PolyBoltPriceSocket.isHardFailure(
          const PolyBoltAuthException('no_credentials')), isFalse);
      expect(PolyBoltPriceSocket.isHardFailure(
          const PolyBoltDisconnectedException('budget', closeCode: 1006)), isFalse);
      expect(PolyBoltPriceSocket.isHardFailure(
          const PolyBoltDisconnectedException('budget')), isFalse);
      expect(PolyBoltPriceSocket.isHardFailure(StateError('x')), isFalse);
    });
  });

  group('PolyBoltPriceSocket stream', () {
    late List<FakeTransport> transports;
    PolyBoltPriceSocket build({
      PolyBoltCredentials? Function()? credentials,
      int maxReconnectAttempts = 5,
      Duration base = const Duration(milliseconds: 5),
      Duration ping = const Duration(seconds: 30),
    }) {
      transports = [];
      return PolyBoltPriceSocket(
        credentials: credentials ?? () => creds,
        reconnectBaseDelay: base,
        maxReconnectDelay: const Duration(milliseconds: 20),
        maxReconnectAttempts: maxReconnectAttempts,
        pingInterval: ping,
        transportFactory: (url) {
          final t = FakeTransport(url);
          transports.add(t);
          return t;
        },
      );
    }

    test('authenticates first, subscribes on authed, emits {asset: price}', () async {
      final socket = build();
      final out = <Map<String, double>>[];
      final sub = socket.pricesByAsset(symbols).listen(out.add);
      await pump();

      expect(transports, hasLength(1));
      final t = transports.single;
      expect(t.url.toString(), kPolyBoltWsUrl);
      expect(t.sentJson, hasLength(1));
      expect(t.sentJson.single['op'], 'auth');
      expect(t.sentJson.single['auth'], {
        'apiKey': creds.apiKey,
        'secret': creds.secret,
        'passphrase': creds.passphrase,
      });

      t.serverSend({'op': 'authed', 'rid': 'a1'});
      await pump();
      expect(t.sentJson, hasLength(2));
      final subscribe = t.sentJson[1];
      expect(subscribe['op'], 'subscribe');
      final subs = (subscribe['subscriptions'] as List).cast<Map<String, dynamic>>();
      expect(subs.map((s) => s['channel']).toSet(), {'price.crypto.twap'});
      expect(subs.map((s) => (s['filter'] as Map)['symbol']).toList(),
          ['btcusd', 'ethusd', 'solusd', 'xrpusd']);
      expect(subs.every((s) => (s['filter'] as Map)['window_seconds'] == 60), isTrue);

      t.serverSend({'op': 'subscribed', 'channel': 'price.crypto.twap', 'rid': 's1'});
      t.serverSend(twapLive('btcusd', 64120.7));
      t.serverSend(twapLive('xrpusd', 0.5123, exact: '0.51230000'));
      t.serverSend(twapLive('dogeusd', 0.1)); // not subscribed → dropped
      t.serverSend({'op': 'pong', 'rid': 'p1'});
      await pump();

      expect(out, [
        {'BTC': 64120.7},
        {'XRP': 0.5123},
      ]);

      await sub.cancel();
      expect(t.closedByClient, isTrue);
    });

    test('spot channel subscribes without window_seconds and maps a single asset', () async {
      transports = [];
      final socket = PolyBoltPriceSocket(
        credentials: () => creds,
        channel: kPolyBoltCryptoSpotChannel,
        transportFactory: (url) {
          final t = FakeTransport(url);
          transports.add(t);
          return t;
        },
      );
      final out = <Map<String, double>>[];
      final sub = socket.pricesByAsset({'BTC': 'btcusd'}).listen(out.add);
      await pump();
      final t = transports.single;
      t.serverSend({'op': 'authed', 'rid': 'a1'});
      await pump();
      expect(
        jsonEncode(t.sentJson[1]),
        '{"op":"subscribe","rid":"s1","subscriptions":['
        '{"channel":"price.crypto","filter":{"symbol":"btcusd"}}]}',
      );
      t.serverSend({
        'v': 1,
        'channel': 'price.crypto',
        'seq': 2,
        'ts': 1788973001000,
        'payload': {
          'symbol': 'btcusd',
          'value': 64126.0,
          'full_accuracy_value': '64126.00000000',
          'timestamp': 1788973001000,
          'source': 'pyth',
        },
      });
      t.serverSend(twapLive('ethusd', 3000)); // not subscribed here
      await pump();
      expect(out, [{'BTC': 64126.0}]);
      await sub.cancel();
    });

    test('snapshot frame seeds the price before live ticks', () async {
      final socket = build();
      final out = <Map<String, double>>[];
      final sub = socket.pricesByAsset(symbols).listen(out.add);
      await pump();
      final t = transports.single;
      t.serverSend({'op': 'authed', 'rid': 'a1'});
      t.serverSend({
        'v': 1,
        'channel': 'price.crypto.twap',
        'seq': 1,
        'ts': 1,
        'snapshot': true,
        'payload': {
          'symbol': 'ethusd',
          'window_seconds': 60,
          'source': 'chainlink',
          'data': [
            {'timestamp': 10, 'value': 3000.0, 'full_accuracy_value': '3000.00000000'},
            {'timestamp': 11, 'value': 3001.0, 'full_accuracy_value': '3001.00000000'},
          ],
        },
      });
      await pump();
      expect(out, [{'ETH': 3001.0}]);
      await sub.cancel();
    });

    test('auth_invalid surfaces as PolyBoltAuthException then closes', () async {
      final socket = build();
      final errors = <Object>[];
      var done = false;
      final sub = socket.pricesByAsset(symbols).listen((_) {},
          onError: errors.add, onDone: () => done = true);
      await pump();
      final t = transports.single;
      t.serverSend({'op': 'error', 'rid': 'a1', 'code': 'auth_invalid'});
      await pump();
      await pump();
      expect(errors, hasLength(1));
      expect(errors.single, isA<PolyBoltAuthException>());
      expect((errors.single as PolyBoltAuthException).code, 'auth_invalid');
      expect(done, isTrue);
      expect(t.closedByClient, isTrue);
      await sub.cancel();
    });

    test('auth_required on subscribe is treated as an auth failure', () async {
      final socket = build();
      final errors = <Object>[];
      final sub = socket.pricesByAsset(symbols).listen((_) {}, onError: errors.add);
      await pump();
      transports.single.serverSend(
          {'op': 'error', 'channel': 'price.crypto.twap', 'rid': 's1', 'code': 'auth_required'});
      await pump();
      expect(errors.single, isA<PolyBoltAuthException>());
      await sub.cancel();
    });

    test('non-auth error acks are logged and do not kill the stream', () async {
      final socket = build();
      final errors = <Object>[];
      final out = <Map<String, double>>[];
      final sub = socket.pricesByAsset(symbols).listen(out.add, onError: errors.add);
      await pump();
      final t = transports.single;
      t.serverSend({'op': 'authed', 'rid': 'a1'});
      t.serverSend({'op': 'error', 'channel': 'price.crypto.twap', 'rid': 's1', 'code': 'bad_filter'});
      t.serverSend(twapLive('solusd', 150.25));
      await pump();
      expect(errors, isEmpty);
      expect(out, [{'SOL': 150.25}]);
      await sub.cancel();
    });

    test('missing credentials fail immediately without opening a socket', () async {
      final socket = build(credentials: () => null);
      final errors = <Object>[];
      final sub = socket.pricesByAsset(symbols).listen((_) {}, onError: errors.add);
      await pump();
      expect(transports, isEmpty);
      expect(errors.single, isA<PolyBoltAuthException>());
      expect((errors.single as PolyBoltAuthException).code, 'no_credentials');
      await sub.cancel();
    });

    test('server close reconnects with backoff, re-auths and resubscribes', () async {
      final socket = build();
      final out = <Map<String, double>>[];
      final errors = <Object>[];
      final sub = socket.pricesByAsset(symbols).listen(out.add, onError: errors.add);
      await pump();
      final first = transports.single;
      first.serverSend({'op': 'authed', 'rid': 'a1'});
      await pump();
      await first.serverClose(code: 1006);
      await pump(40);

      expect(transports, hasLength(2));
      final second = transports[1];
      expect(second.sentJson.single['op'], 'auth', reason: 're-auth on reconnect');
      second.serverSend({'op': 'authed', 'rid': 'a1'});
      await pump();
      expect(second.sentJson[1]['op'], 'subscribe');
      second.serverSend(twapLive('btcusd', 70000));
      await pump();
      expect(out, [{'BTC': 70000.0}]);
      expect(errors, isEmpty);
      await sub.cancel();
    });

    test('reconnect budget exhausted → PolyBoltDisconnectedException and close', () async {
      final socket = build(maxReconnectAttempts: 1);
      final errors = <Object>[];
      var done = false;
      final sub = socket.pricesByAsset(symbols).listen((_) {},
          onError: errors.add, onDone: () => done = true);
      await pump();
      await transports[0].serverClose(code: 1006);
      await pump(40);
      expect(transports, hasLength(2));
      await transports[1].serverClose(code: 1006);
      await pump(40);
      expect(transports, hasLength(2), reason: 'no third attempt');
      expect(errors.single, isA<PolyBoltDisconnectedException>());
      expect(done, isTrue);
      await sub.cancel();
    });

    test('close 4008 (policy violation) is not retried', () async {
      final socket = build();
      final errors = <Object>[];
      final sub = socket.pricesByAsset(symbols).listen((_) {}, onError: errors.add);
      await pump();
      await transports.single.serverClose(code: 4008);
      await pump(40);
      expect(transports, hasLength(1));
      expect(errors.single, isA<PolyBoltDisconnectedException>());
      expect((errors.single as PolyBoltDisconnectedException).closeCode, 4008);
      await sub.cancel();
    });

    test('close 4001 (auth failed) surfaces as an auth failure', () async {
      final socket = build();
      final errors = <Object>[];
      final sub = socket.pricesByAsset(symbols).listen((_) {}, onError: errors.add);
      await pump();
      await transports.single.serverClose(code: 4001);
      await pump(40);
      expect(transports, hasLength(1));
      expect(errors.single, isA<PolyBoltAuthException>());
      await sub.cancel();
    });

    test('application-level ping is sent on the interval', () async {
      final socket = build(ping: const Duration(milliseconds: 10));
      final sub = socket.pricesByAsset(symbols).listen((_) {});
      await pump(35);
      final pings = transports.single.sentJson.where((f) => f['op'] == 'ping');
      expect(pings.length, greaterThanOrEqualTo(2));
      expect(pings.first, {'op': 'ping', 'rid': 'p1'});
      await sub.cancel();
    });

    test('cancel during handshake closes the socket and sends nothing', () async {
      transports = [];
      final socket = PolyBoltPriceSocket(
        credentials: () => creds,
        transportFactory: (url) {
          final t = FakeTransport(url, readyNow: false);
          transports.add(t);
          return t;
        },
      );
      final sub = socket.pricesByAsset(symbols).listen((_) {});
      await pump();
      final t = transports.single;
      await sub.cancel();
      t.readyCompleter.complete();
      await pump();
      expect(t.sent, isEmpty);
      expect(t.closedByClient, isTrue);
    });
  });
}
