import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/polymarket/builder_code_resolver.dart';

void main() {
  final code = '0x${'ab' * 32}';
  const zero = PolymarketConstants.bytes32Zero;

  group('parseBuilderCodeResponse', () {
    test('accepts a bytes32 code for the held revision', () {
      expect(
          parseBuilderCodeResponse(
              jsonEncode({'builderCode': code, 'revision': 7}),
              expectedRevision: 7),
          code);
    });

    test('accepts any revision when none is held', () {
      expect(
          parseBuilderCodeResponse(
              jsonEncode({'builderCode': code, 'revision': 3})),
          code);
    });

    test('rejects another revision, malformed codes and the zero code', () {
      for (final body in [
        jsonEncode({'builderCode': code, 'revision': 8}),
        jsonEncode({'builderCode': '', 'revision': 7}),
        jsonEncode({'builderCode': code.substring(2), 'revision': 7}),
        jsonEncode({'builderCode': '0x${'ab' * 31}', 'revision': 7}),
        jsonEncode({'builderCode': '0x${'zz' * 32}', 'revision': 7}),
        jsonEncode({'builderCode': 42, 'revision': 7}),
        jsonEncode({'builderCode': zero, 'revision': 7}),
        jsonEncode(['not', 'a', 'map']),
        'not json',
      ]) {
        expect(parseBuilderCodeResponse(body, expectedRevision: 7), isNull,
            reason: body);
      }
    });
  });

  group('PolymarketBuilderCodeResolver', () {
    late int calls;
    late int? revision;
    late String? session;
    late DateTime now;
    late Future<http.Response> Function(http.Request) handler;

    PolymarketBuilderCodeResolver build({String base = 'https://kute.test'}) {
      final client = MockClient((request) {
        calls++;
        return handler(request);
      });
      return PolymarketBuilderCodeResolver(
        client: () => client,
        baseUrl: () => base,
        revision: () => revision,
        session: () => session,
        clock: () => now,
        timeouts: const [
          Duration(milliseconds: 20),
          Duration(milliseconds: 20)
        ],
      );
    }

    setUp(() {
      calls = 0;
      revision = 7;
      session = 'token';
      now = DateTime.utc(2026, 9, 29);
      handler = (_) async =>
          http.Response(jsonEncode({'builderCode': code, 'revision': 7}), 200);
    });

    test('reads the code from the backend and holds it for the revision',
        () async {
      String? auth;
      String? path;
      handler = (request) async {
        auth = request.headers['Authorization'];
        path = request.url.path;
        return http.Response(
            jsonEncode({'builderCode': code, 'revision': 7}), 200);
      };
      final resolver = build();
      final first = await resolver.resolve();
      expect(first.code, code);
      expect(first.attributed, isTrue);
      expect(auth, 'Bearer token');
      expect(path, '/api/v1/pm/builder-code');
      expect((await resolver.resolve()).code, code);
      expect(calls, 1);
    });

    test('an unreachable backend signs with the zero builder', () async {
      handler = (_) async => throw http.ClientException('offline');
      final resolved = await build().resolve();
      expect(resolved.code, zero);
      expect(resolved.attributed, isFalse);
    });

    test('a timeout on every attempt signs with the zero builder', () async {
      handler = (_) => Completer<http.Response>().future;
      final resolved = await build().resolve();
      expect(resolved.code, zero);
      expect(calls, 2);
    });

    test('an error status or an invalid code signs with the zero builder',
        () async {
      for (final response in [
        http.Response('{"error":"policy_unavailable"}', 503),
        http.Response(jsonEncode({'builderCode': '', 'revision': 7}), 200),
        http.Response(jsonEncode({'builderCode': 'nope', 'revision': 7}), 200),
        http.Response(jsonEncode({'builderCode': code, 'revision': 9}), 200),
      ]) {
        handler = (_) async => response;
        expect((await build().resolve()).code, zero,
            reason: '${response.statusCode} ${response.body}');
      }
    });

    test('no backend configured signs with the zero builder', () async {
      final resolved = await build(base: '').resolve();
      expect(resolved.code, zero);
      expect(calls, 0);
    });

    test('a failure backs off, then asks again', () async {
      handler = (_) async => throw http.ClientException('offline');
      final resolver = build();
      expect((await resolver.resolve()).code, zero);
      final afterFailure = calls;
      expect((await resolver.resolve()).code, zero);
      expect(calls, afterFailure, reason: 'no new request inside the backoff');

      handler = (_) async =>
          http.Response(jsonEncode({'builderCode': code, 'revision': 7}), 200);
      now = now.add(const Duration(minutes: 2));
      expect((await resolver.resolve()).code, code);
    });

    test('a new policy revision or session asks the backend again', () async {
      final resolver = build();
      await resolver.resolve();
      expect(calls, 1);

      revision = 8;
      handler = (_) async =>
          http.Response(jsonEncode({'builderCode': code, 'revision': 8}), 200);
      expect((await resolver.resolve()).code, code);
      expect(calls, 2);

      session = 'other';
      await resolver.resolve();
      expect(calls, 3);
    });

    test('a new revision also clears a failure backoff', () async {
      handler = (_) async => throw http.ClientException('offline');
      final resolver = build();
      expect((await resolver.resolve()).code, zero);

      revision = 8;
      handler = (_) async =>
          http.Response(jsonEncode({'builderCode': code, 'revision': 8}), 200);
      expect((await resolver.resolve()).code, code);
    });

    test('a held code survives a later outage in the same revision', () async {
      final resolver = build();
      expect((await resolver.resolve()).code, code);
      handler = (_) async => throw http.ClientException('offline');
      expect((await resolver.resolve()).code, code);
    });

    test('isZeroBuilderCode', () {
      expect(isZeroBuilderCode(zero), isTrue);
      expect(isZeroBuilderCode(code), isFalse);
    });
  });
}
