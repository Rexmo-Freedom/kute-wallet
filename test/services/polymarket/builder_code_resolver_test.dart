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

    test(
        'a new policy revision keeps the last code for signing and asks the '
        'backend again for a read that may wait', () async {
      final resolver = build();
      await resolver.resolve();
      expect(calls, 1);

      revision = 8;
      expect(resolver.cachedCode, code, reason: 'signing never waits');
      handler = (_) async =>
          http.Response(jsonEncode({'builderCode': code, 'revision': 8}), 200);
      final read = await resolver.resolve();
      expect(read.code, code);
      expect(read.source, BuilderCodeSource.backend);
      expect(calls, 2);

      // A new session with the same revision: the copy answers at once and
      // the backend is asked in the background.
      session = 'other';
      final atOnce = await resolver.resolve();
      expect(atOnce.code, code);
      expect(atOnce.source, BuilderCodeSource.persisted);
      await pumpEventQueue();
      expect(calls, 3);
    });

    test('the device copy answers with no network and no wait', () async {
      handler = (_) => Completer<http.Response>().future;
      var persisted = 0;
      final resolver = PolymarketBuilderCodeResolver(
        client: () => MockClient((request) {
          calls++;
          return handler(request);
        }),
        baseUrl: () => 'https://kute.test',
        revision: () => revision,
        session: () => session,
        clock: () => now,
        timeouts: const [Duration(milliseconds: 20)],
        loadPersisted: () async => PersistedBuilderCode(code, 7),
        persist: (_) async => persisted++,
      );
      expect(resolver.cachedCode, isNull, reason: 'not hydrated yet');
      await resolver.hydrate();
      expect(resolver.cachedCode, code);
      final resolved = await resolver.resolve();
      expect(resolved.code, code);
      expect(resolved.source, BuilderCodeSource.persisted);
      expect(resolved.attributed, isTrue);
      // The backend is asked again in the background; its hang changes
      // nothing about what the order signs with.
      await pumpEventQueue();
      expect(calls, 1);
      expect(resolver.cachedCode, code);
      expect(persisted, 0);
    });

    test('a backend answer is kept on the device and read back', () async {
      PersistedBuilderCode? onDisk;
      PolymarketBuilderCodeResolver withDisk() => PolymarketBuilderCodeResolver(
            client: () => MockClient((request) {
              calls++;
              return handler(request);
            }),
            baseUrl: () => 'https://kute.test',
            revision: () => revision,
            session: () => session,
            clock: () => now,
            timeouts: const [Duration(milliseconds: 20)],
            loadPersisted: () async => onDisk,
            persist: (value) async => onDisk = value,
          );
      final first = withDisk();
      expect(first.cachedCode, isNull);
      await first.refresh();
      expect(first.cachedCode, code);
      expect(onDisk?.code, code);
      expect(onDisk?.revision, 7);

      // A later run: the copy is there before any request, and an offline
      // backend leaves it in place.
      handler = (_) async => throw http.ClientException('offline');
      final later = withDisk();
      await later.hydrate();
      expect(later.cachedCode, code);
      await later.refresh();
      expect(later.cachedCode, code);
      expect((await later.resolve()).code, code);
    });

    test(
        'a device copy from an older revision signs at once, while a read '
        'that may wait gets the new code', () async {
      final newCode = '0x${'cd' * 32}';
      handler = (_) async => http.Response(
          jsonEncode({'builderCode': newCode, 'revision': 7}), 200);
      final resolver = PolymarketBuilderCodeResolver(
        client: () => MockClient((request) {
          calls++;
          return handler(request);
        }),
        baseUrl: () => 'https://kute.test',
        revision: () => revision,
        session: () => session,
        clock: () => now,
        timeouts: const [Duration(milliseconds: 20)],
        loadPersisted: () async => PersistedBuilderCode(code, 6),
        persist: (_) async {},
      );
      await resolver.hydrate();
      expect(resolver.cachedCode, code, reason: 'signing never waits');
      final resolved = await resolver.resolve();
      expect(resolved.code, newCode);
      expect(resolved.source, BuilderCodeSource.backend);
      expect(resolver.cachedCode, newCode);

      // Offline with only an old-revision copy: the read falls back to it.
      handler = (_) async => throw http.ClientException('offline');
      revision = 8;
      expect((await resolver.resolve()).code, newCode);
      expect(resolver.cachedCode, newCode);
    });

    test('the policy snapshot\'s code wins, with no request, and is kept',
        () async {
      final policy = '0x${'ef' * 32}';
      PersistedBuilderCode? onDisk;
      String? fromPolicy = policy;
      handler = (_) => Completer<http.Response>().future;
      final resolver = PolymarketBuilderCodeResolver(
        client: () => MockClient((request) {
          calls++;
          return handler(request);
        }),
        baseUrl: () => 'https://kute.test',
        revision: () => revision,
        session: () => session,
        clock: () => now,
        timeouts: const [Duration(milliseconds: 20)],
        loadPersisted: () async => PersistedBuilderCode(code, 7),
        persist: (copy) async => onDisk = copy,
        policyCode: () => fromPolicy,
      );
      expect(resolver.cachedCode, policy);
      final resolved = await resolver.resolve();
      expect(resolved.code, policy);
      expect(resolved.source, BuilderCodeSource.policy);
      expect(calls, 0);
      await pumpEventQueue();
      expect(onDisk?.code, policy);
      expect(onDisk?.revision, 7);

      // A policy without the code falls back to the device copy (now the
      // policy's) with no wait.
      fromPolicy = null;
      expect(resolver.cachedCode, policy);
      // The zero code or junk on the policy counts as none.
      fromPolicy = zero;
      expect(resolver.cachedCode, policy);
      fromPolicy = 'nope';
      expect(resolver.cachedCode, policy);
    });

    test('refresh inside the failure backoff asks nothing', () async {
      handler = (_) async => throw http.ClientException('offline');
      final resolver = build();
      await resolver.refresh();
      expect(calls, 1);
      await resolver.refresh();
      expect(calls, 1);
      await resolver.refresh(force: true);
      expect(calls, 2);
      expect(resolver.cachedCode, isNull);
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
