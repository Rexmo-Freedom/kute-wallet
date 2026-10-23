import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/http/http_timeout_policy.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/tracking_service.dart';

void main() {
  final uri = Uri.parse('https://example.test/v1/thing?id=123');

  setUp(() {
    SharedHttpClient.debugReset();
    SharedHttpClient.debugReportEveryRequest = true;
  });
  tearDown(() {
    SharedHttpClient.debugReset();
    TrackingService.debugTrackObserver = null;
    HttpTimeoutPolicy.networkProfile = NetworkProfile.unknown;
  });

  test('one pooled client per host, reused across calls', () {
    final a = SharedHttpClient.forHost('clob.polymarket.com');
    final b = SharedHttpClient.forHost('CLOB.polymarket.com');
    final c = SharedHttpClient.forHost('api.hyperliquid.xyz');
    expect(identical(a, b), isTrue);
    expect(identical(a, c), isFalse);
  });

  test('network recycling drops each host pool for subsequent requests', () {
    final before = SharedHttpClient.forHost('api.hyperliquid.xyz');
    SharedHttpClient.recycle();
    final after = SharedHttpClient.forHost('api.hyperliquid.xyz');
    expect(identical(before, after), isFalse);
    expect(SharedHttpClient.debugRecycles, 1);
  });

  test('background reads retry a 5xx with backoff, then return', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return calls < 2
          ? http.Response('', 503)
          : http.Response('{"ok":true}', 200);
    });
    final res = await SharedHttpClient.get(uri,
        kind: HttpCallKind.backgroundRead, client: client);
    expect(res.statusCode, 200);
    expect(calls, 2);
  });

  test('background reads retry a transport error, up to the cap', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      throw http.ClientException('connection reset');
    });
    await expectLater(
        SharedHttpClient.get(uri,
            kind: HttpCallKind.backgroundRead, client: client),
        throwsA(isA<http.ClientException>()));
    expect(calls, 1 + HttpTimeoutPolicy.maxBackgroundRetries);
  });

  test('user actions and submits are sent exactly once', () async {
    for (final kind in [HttpCallKind.userAction, HttpCallKind.submit]) {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('', 503);
      });
      final res = await SharedHttpClient.post(uri,
          kind: kind, body: '{}', client: client);
      expect(res.statusCode, 503);
      expect(calls, 1, reason: '$kind must never retry');
    }
  });

  test('a slow answer is a TimeoutException, one attempt for a submit',
      () async {
    var calls = 0;
    final client = MockClient((_) {
      calls++;
      return Completer<http.Response>().future;
    });
    await expectLater(
        SharedHttpClient.post(uri,
            kind: HttpCallKind.submit,
            timeout: const Duration(milliseconds: 30),
            client: client),
        throwsA(isA<TimeoutException>()));
    expect(calls, 1);
  });

  test('a user action deadline bounds the attempt', () async {
    final client = MockClient((_) => Completer<http.Response>().future);
    final sw = Stopwatch()..start();
    await expectLater(
        SharedHttpClient.get(uri,
            kind: HttpCallKind.userAction,
            timeout: const Duration(seconds: 8),
            deadline: const Duration(milliseconds: 40),
            client: client),
        throwsA(isA<TimeoutException>()));
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });

  test('cellular scales every budget', () {
    HttpTimeoutPolicy.networkProfile = NetworkProfile.cellular;
    expect(HttpTimeoutPolicy.scaled(const Duration(seconds: 10)),
        const Duration(seconds: 15));
    HttpTimeoutPolicy.networkProfile = NetworkProfile.wifi;
    expect(HttpTimeoutPolicy.scaled(const Duration(seconds: 10)),
        const Duration(seconds: 10));
  });

  test('backoff grows and jitters within bounds', () {
    for (var retry = 1; retry <= 4; retry++) {
      final base =
          HttpTimeoutPolicy.backoffBase.inMilliseconds * (1 << (retry - 1));
      for (var i = 0; i < 20; i++) {
        final ms = HttpTimeoutPolicy.backoffFor(retry).inMilliseconds;
        expect(ms, inInclusiveRange((base * 0.5).round(), 5000));
        expect(ms, lessThanOrEqualTo((base * 1.5).round() + 1));
      }
    }
  });

  test('latency telemetry carries the host and outcome, never the path',
      () async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    final client = MockClient((_) async => http.Response('{}', 404));
    await SharedHttpClient.get(uri,
        kind: HttpCallKind.userAction, client: client);
    final sample = events.where((e) => e.$1 == 'http_request_latency');
    expect(sample, hasLength(1));
    final p = sample.single.$2!;
    expect(p['host'], 'example.test');
    expect(p['method'], 'GET');
    expect(p['call_kind'], 'userAction');
    expect(p['outcome'], 'http_error');
    expect(p['status_class'], '4xx');
    expect(p['attempt'], 1);
    expect(p['duration_ms'], isA<int>());
    expect(p['duration_bucket'], isA<String>());
    expect(
        p.values
            .map((v) => '$v')
            .any((v) => v.contains('/v1') || v.contains('123')),
        isFalse);
  });

  test('a timeout is reported as such', () async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    final client = MockClient((_) => Completer<http.Response>().future);
    await expectLater(
        SharedHttpClient.get(uri,
            kind: HttpCallKind.submit,
            timeout: const Duration(milliseconds: 20),
            client: client),
        throwsA(isA<TimeoutException>()));
    final p = events.singleWhere((e) => e.$1 == 'http_request_latency').$2!;
    expect(p['outcome'], 'timeout');
    expect(p.containsKey('status_class'), isFalse);
  });
}
