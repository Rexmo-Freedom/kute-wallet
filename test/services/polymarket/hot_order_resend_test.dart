// A hot order on a connection that drops: looked up by its hash first, sent
// again only as the identical order, never signed again, never past its
// minute or its approval. A fake clock and fake transports; nothing is sent.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/auth_grant.dart' show GrantExpired;
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/services/polymarket/order_connection.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderType;

const _account = '0x1111111111111111111111111111111111111111';
const _exchange = '0x2222222222222222222222222222222222222222';

SignedOrderV2 _signed() => SignedOrderV2(
    order: OrderStructV2(
        salt: BigInt.from(424242),
        maker: _account,
        signer: _account,
        tokenId: '7',
        makerAmount: BigInt.from(5000000),
        takerAmount: BigInt.from(2500000),
        // A sell: no capability read before the POST.
        side: 1,
        signatureType: 3,
        timestamp: BigInt.from(1762650000),
        metadata: '0x${'00' * 32}',
        builder: '0x${'00' * 32}'),
    signature: '0xsignature');

String _hash(SignedOrderV2 o) {
  final digest =
      orderV2TypedData(order: o.order, verifyingContract: _exchange).digest;
  return '0x${digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

const _noBuyers =
    'no orders found to match with FAK order. FAK orders are partially filled or killed if no match is found.';
final _timeout = TimeoutException('no answer');
final _dns = http.ClientException(
    "SocketException: Failed host lookup: 'clob.polymarket.com'");

void main() {
  late Directory directory;
  late Box<String> box;
  late DateTime now;
  late List<Duration> slept;
  late List<String> script;
  late int lookups;
  late int posts;
  late int signatures;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('order-resend-');
    Hive.init(directory.path);
    box = await Hive.openBox<String>(HotPolymarketOrderGuard.boxName);
    now = DateTime.now();
    slept = [];
    script = [];
    lookups = 0;
    posts = 0;
    signatures = 0;
    PolymarketOrderAttempts.last = 0;
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  HotOrderResendPolicy policy() => HotOrderResendPolicy(
        now: () => now,
        sleep: (d) async {
          slept.add(d);
          now = now.add(d);
        },
      );

  Map<String, dynamic> record(String status, {String matched = '0'}) => {
        'id': _hash(_signed()),
        'maker_address': _account,
        'status': status,
        'size_matched': matched,
        'asset_id': '7',
      };

  Map<String, dynamic> ack([String status = 'matched']) => {
        'success': true,
        'orderID': _hash(_signed()),
        'status': status,
      };

  /// One placement: signs once, posts through [post], looks up through
  /// [lookup]. Everything the transports see is logged in [script].
  Future<Map<String, dynamic>> place({
    required Future<Map<String, dynamic>> Function(int attempt) post,
    required Future<Map<String, dynamic>?> Function() lookup,
    void Function()? ensureCurrent,
    bool retries = true,
  }) async {
    final signed = _signed();
    signatures++;
    return HotPolymarketOrderGuard(resend: retries ? policy() : null).run(
      walletId: 'spending',
      depositWallet: _account,
      tokenId: '7',
      lookup: (id) {
        expect(id, _hash(signed));
        lookups++;
        script.add('lookup');
        return lookup();
      },
      action: (submit) => submit(
        order: signed,
        exchange: _exchange,
        ensureCurrent: ensureCurrent ?? () {},
        send: (beforePost) async {
          beforePost();
          posts++;
          script.add('post');
          return post(posts);
        },
      ),
    );
  }

  String stage() => jsonDecode(box.get('$_account:7')!)['stage'] as String;

  test('without a policy one POST is all: nothing is retried', () async {
    await expectLater(
        place(
            retries: false,
            post: (_) async => throw _timeout,
            lookup: () async => null),
        throwsA(isA<PolymarketOrderOutcomeUnknown>()
            .having((e) => e.lookedUp, 'lookedUp', isFalse)));
    expect(posts, 1);
    expect(lookups, 0);
  });

  test('looks the order up before it sends it again', () async {
    final answer = await place(
        post: (n) async => n == 1 ? throw _timeout : ack(),
        lookup: () async => null);
    expect(script, ['post', 'lookup', 'post']);
    expect(answer['orderID'], _hash(_signed()));
    expect(stage(), 'accepted');
    expect(signatures, 1);
    expect(PolymarketOrderAttempts.last, 2);
  });

  test('found: the venue\'s answer is used and nothing is sent again',
      () async {
    final answer = await place(
        post: (_) async => throw _timeout,
        lookup: () async => record('MATCHED', matched: '10'));
    expect(script, ['post', 'lookup']);
    expect(answer['status'], 'matched');
    expect(answer['recovered'], isTrue);
    expect(stage(), 'accepted');
  });

  test(
      'found killed with nothing matched: the venue refused it, and the row '
      'lets the ladder sign its next rung', () async {
    await expectLater(
        place(
            post: (_) async => throw _timeout,
            lookup: () async => record('CANCELED')),
        throwsA(isA<PolymarketOrderNotAcceptedException>()
            .having((e) => e.reason, 'reason', _noBuyers)));
    expect(stage(), 'rejected');
  });

  test('found killed after a part fill: accepted, the settlement reads it',
      () async {
    final answer = await place(
        post: (_) async => throw _timeout,
        lookup: () async => record('CANCELED', matched: '3'));
    expect(answer['status'], 'matched');
    expect(stage(), 'accepted');
  });

  test('a record that is not this order proves nothing and sends nothing',
      () async {
    await expectLater(
        place(
            post: (_) async => throw _timeout,
            lookup: () async => {...record('MATCHED'), 'id': '0x${'b' * 64}'}),
        throwsA(isA<PolymarketOrderOutcomeUnknown>()));
    expect(posts, 1);
    expect(stage(), 'submitting');
  });

  test('a lookup that fails is not "not found": nothing is sent', () async {
    await expectLater(
        place(
            post: (_) async => throw _timeout,
            lookup: () async => throw const SocketException('offline')),
        throwsA(isA<PolymarketOrderOutcomeUnknown>()));
    expect(posts, 1);
    expect(stage(), 'submitting');
  });

  test('a POST that really times out is reported as a timeout and retried',
      () async {
    // Future.timeout's own exception: the backend's `on TimeoutException`
    // used to name the Polymarket package's class and never matched it.
    expect(isPolymarketOrderNoAnswer(TimeoutException('x')), isTrue);
    expect(
        isPolymarketOrderNoAnswer(const PolymarketOrderPostTimedOut()), isTrue);
    expect(isPolymarketOrderNoAnswer(StateError('x')), isFalse);
  });

  test(
      'the bytes sent again are the bytes sent first, hash and signature '
      'included, through the real transport', () async {
    final bodies = <String>[];
    final responses = <http.Response>[
      http.Response('upstream', 500),
      http.Response(jsonEncode(ack()), 200),
    ];
    final backend = PolymarketBackendService(
        apiKey: 'k',
        secret: base64Url.encode(utf8.encode('secret')),
        passphrase: 'p',
        walletAddress: _account);
    final signed = _signed();
    final answer = await http.runWithClient(
        () => HotPolymarketOrderGuard(resend: policy()).run(
              walletId: 'spending',
              depositWallet: _account,
              tokenId: '7',
              lookup: (_) async => null,
              action: (submit) => submit(
                order: signed,
                exchange: _exchange,
                ensureCurrent: () {},
                send: (beforePost) => backend.submitOrder(
                    signedOrder: signed,
                    orderType: OrderType.fak,
                    beforePost: beforePost),
              ),
            ),
        () => MockClient((request) async {
              bodies.add(request.body);
              return responses.removeAt(0);
            }));
    expect(answer['success'], isTrue);
    expect(bodies, hasLength(2));
    expect(bodies[1], bodies[0]);
    expect((jsonDecode(bodies[0]) as Map)['order']['signature'], '0xsignature');
  });

  group('the venue\'s duplicate answer', () {
    // https://docs.polymarket.com/resources/error-codes
    final duplicate = 'order ${_hash(_signed())} is invalid. Duplicated.';

    test('is never a refusal, though it is a 400 with an error', () {
      final response = http.Response(jsonEncode({'error': duplicate}), 400);
      expect(polymarketHttpRejection(response), isNull);
      expect(isDefinitivePolymarketHttpRejection(response), isFalse);
    });

    test('the real transport reports it as such', () async {
      final backend = PolymarketBackendService(
          apiKey: 'k',
          secret: base64Url.encode(utf8.encode('secret')),
          passphrase: 'p',
          walletAddress: _account);
      await expectLater(
          http.runWithClient(
              () => backend.submitOrder(signedOrder: _signed()),
              () => MockClient((_) async =>
                  http.Response(jsonEncode({'error': duplicate}), 400))),
          throwsA(isA<PolymarketOrderDuplicated>()));
    });

    test('means accepted, go look it up: never sent a third time', () async {
      var reads = 0;
      final answer = await place(
          post: (n) async =>
              n == 1 ? throw _timeout : throw const PolymarketOrderDuplicated(),
          lookup: () async => ++reads < 3 ? null : record('MATCHED'));
      expect(posts, 2);
      expect(answer['status'], 'matched');
      expect(stage(), 'accepted');
    });

    test('in a 200 body too', () async {
      var reads = 0;
      final answer = await place(
          post: (n) async => n == 1
              ? throw _timeout
              : {'success': false, 'errorMsg': duplicate},
          lookup: () async => ++reads < 2 ? null : record('LIVE'));
      expect(posts, 2);
      expect(answer['status'], 'live');
    });

    test('that never shows up stays unknown, not a failure', () async {
      await expectLater(
          place(
              post: (n) async => n == 1
                  ? throw _timeout
                  : throw const PolymarketOrderDuplicated(),
              lookup: () async => null),
          throwsA(isA<PolymarketOrderOutcomeUnknown>()));
      expect(posts, 2);
      expect(stage(), 'submitting');
    });
  });

  test('stops at 60 s: unknown stays unknown, the row keeps blocking',
      () async {
    final start = now;
    await expectLater(
        place(post: (_) async => throw _timeout, lookup: () async => null),
        throwsA(isA<PolymarketOrderOutcomeUnknown>()
            .having((e) => e.lookedUp, 'lookedUp', isTrue)
            .having((e) => e.orderId, 'orderId', _hash(_signed()))));
    expect(now.difference(start), const Duration(seconds: 60));
    expect(signatures, 1);
    expect(stage(), 'submitting');
    expect(await HotPolymarketOrderGuard.hasUnsettled(_account), isTrue);
    // The next tap is blocked, not signed again.
    await expectLater(
        HotPolymarketOrderGuard().run<void>(
            walletId: 'spending',
            depositWallet: _account,
            tokenId: '7',
            lookup: (_) async => null,
            action: (_) async => fail('Must not reach a new order')),
        throwsA(isA<PendingPolymarketOrder>()));
  });

  test('backs off: 2 s, 4 s, then 8 s', () async {
    await expectLater(
        place(post: (_) async => throw _timeout, lookup: () async => null),
        throwsA(isA<PolymarketOrderOutcomeUnknown>()));
    expect(slept.take(3).map((d) => d.inSeconds), [2, 4, 8]);
    expect(slept.skip(2).every((d) => d.inSeconds <= 8), isTrue);
  });

  test('a clock jump past the window (the app was suspended) sends nothing',
      () async {
    await expectLater(
        place(
            post: (_) async {
              now = now.add(const Duration(minutes: 5));
              throw _timeout;
            },
            lookup: () async => null),
        throwsA(isA<PolymarketOrderOutcomeUnknown>()));
    expect(posts, 1);
    expect(lookups, 0);
  });

  group('an approval that runs out stops the retries', () {
    test('with a copy possibly out there: pending, nothing more sent',
        () async {
      var checks = 0;
      await expectLater(
          place(
              post: (_) async => throw _timeout,
              lookup: () async => null,
              ensureCurrent: () {
                if (++checks > 4) throw const GrantExpired();
              }),
          throwsA(isA<PolymarketOrderOutcomeUnknown>()));
      expect(stage(), 'submitting');
      final sent = posts;
      expect(sent, lessThan(4));
    });

    test('with nothing ever sent: proven, and the row lets go', () async {
      var checks = 0;
      await expectLater(
          place(
              post: (_) async => throw _dns,
              lookup: () async => throw _dns,
              ensureCurrent: () {
                if (++checks > 2) throw const GrantExpired();
              }),
          throwsA(isA<PolymarketOrderNeverSent>()));
      expect(stage(), 'rejected');
    });
  });

  test('every attempt failing before a connection opened is proven not sent',
      () async {
    await expectLater(
        place(post: (_) async => throw _dns, lookup: () async => null),
        throwsA(isA<PolymarketOrderNeverSent>()));
    expect(stage(), 'rejected');
    expect(await HotPolymarketOrderGuard.hasUnsettled(_account), isFalse);
  });

  test('one attempt that may have arrived spoils the proof', () async {
    await expectLater(
        place(
            post: (n) async => n == 2 ? throw _timeout : throw _dns,
            lookup: () async => null),
        throwsA(isA<PolymarketOrderOutcomeUnknown>()));
    expect(stage(), 'submitting');
  });

  test('only an unopened connection counts as never left', () {
    expect(polymarketPostNeverLeftDevice(_dns), isTrue);
    expect(
        polymarketPostNeverLeftDevice(
            const HandshakeException('bad certificate')),
        isTrue);
    for (final e in [
      _timeout,
      const PolymarketOrderPostTimedOut(),
      const SocketException('Connection reset by peer'),
      http.ClientException('Connection closed before full header was received'),
    ]) {
      expect(polymarketPostNeverLeftDevice(e), isFalse, reason: '$e');
    }
  });

  group('a documented refusal', () {
    test('of the first POST is not retried', () async {
      await expectLater(
          place(
              post: (_) async =>
                  {'success': false, 'errorMsg': 'invalid expiration'},
              lookup: () async => fail('Nothing to look up')),
          throwsA(isA<PolymarketOrderNotAcceptedException>()));
      expect(posts, 1);
      expect(lookups, 0);
      expect(stage(), 'rejected');
    });

    test('thrown by the transport is not retried either', () async {
      await expectLater(
          place(
              post: (_) async =>
                  throw const PolymarketOrderNotAcceptedException(_noBuyers),
              lookup: () async => fail('Nothing to look up')),
          throwsA(isA<PolymarketOrderNotAcceptedException>()));
      expect(posts, 1);
    });

    test(
        'of a resend proves nothing about the copy that may be out there: '
        'pending, and the row blocks a new signature', () async {
      await expectLater(
          place(
              post: (n) async => n == 1
                  ? throw _timeout
                  : {
                      'success': false,
                      'errorMsg': kPolymarketBalanceRefusal,
                    },
              lookup: () async => null),
          throwsA(isA<PolymarketOrderOutcomeUnknown>()));
      expect(posts, 2);
      expect(stage(), 'submitting');
    });

    test('of a resend when no earlier copy can have arrived is a refusal',
        () async {
      await expectLater(
          place(
              post: (n) async => n == 1
                  ? throw _dns
                  : {'success': false, 'errorMsg': _noBuyers},
              lookup: () async => null),
          throwsA(isA<PolymarketOrderNotAcceptedException>()));
      expect(stage(), 'rejected');
    });

    test('a 401 on a resend does not free the row either', () async {
      await expectLater(
          place(
              post: (n) async =>
                  n == 1 ? throw _timeout : throw InvalidApiKeyException(),
              lookup: () async => null),
          throwsA(isA<PolymarketOrderOutcomeUnknown>()));
      expect(stage(), 'submitting');
    });
  });

  test('every retry re-checks before it posts and each copy re-arms the grace',
      () async {
    var checks = 0;
    await place(
        post: (n) async => n == 1 ? throw _timeout : ack(),
        lookup: () async => null,
        ensureCurrent: () => checks++);
    // Before the first POST (guard + transport), before the lookup, before
    // the second POST.
    expect(checks, greaterThanOrEqualTo(4));
    final row = jsonDecode(box.get('$_account:7')!);
    expect(row['submittedAtMs'], now.millisecondsSinceEpoch);
  });
}
