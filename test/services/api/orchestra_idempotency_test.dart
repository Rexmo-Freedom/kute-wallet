import '../../helpers/runtime_policy_fixture.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/models/affiliate_model.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/handlers/response_handlers.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/funding/settlement_http.dart';

final _quoteBody = jsonEncode({
  'quoteId': 'q_1',
  'depositAddress': 'deposit',
  'amountIn': '10000',
  'estimatedOut': '6000000',
  'feeAmount': '0',
  'feeBps': 0,
  'expiresAt': '2026-09-01T12:02:00Z',
});

final _fingerprint = submitBodyFingerprint({'quoteId': 'q_1'});

final _submitBody = jsonEncode({
  'order': {'id': 'ord_1', 'status': 'processing'}
});

/// Replies with [responses] in order and records each request's key.
class _Scripted {
  _Scripted(this.responses);

  final List<FutureOr<http.Response> Function()> responses;
  final keys = <String?>[];
  final paths = <String>[];

  MockClient get client => MockClient((request) async {
        keys.add(request.headers['X-Idempotency-Key']);
        paths.add(request.url.path);
        return responses[keys.length - 1]();
      });
}

Future<Result<OrchestraQuote>> _createQuote(String key) =>
    OrchestraService.createQuote(
      sourceChain: 'spark',
      sourceAsset: 'BTC',
      destinationChain: 'polygon',
      destinationAsset: 'USDC.e',
      amount: '10000',
      recipientAddress: 'recipient',
      refundAddress: 'refund',
      idempotencyKey: key,
    );

Future<Result<OrchestraSubmitResponse>> _submit(String key) =>
    OrchestraService.submitDeposit(
      quoteId: 'q_1',
      sparkTxHash: 'payment',
      sourceSparkAddress: 'source',
      idempotencyKey: key,
    );

int _generated = 0;
String _nextKey() => 'key-${++_generated}';

void main() {
  late List<Duration> sleeps;
  Future<void> fakeSleep(Duration d) async => sleeps.add(d);

  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
  });

  setUp(() {
    sleeps = [];
    AffiliateService.debugSessionToken = 'test-session';
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
  });
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  group('quote retries', () {
    test('the same key on each retry after a timeout, 429 or 5xx', () async {
      final script = _Scripted([
        () => throw TimeoutException('slow'),
        () => http.Response('{}', 429, headers: {'x-ratelimit-reset': '2'}),
        () => http.Response('{}', 503),
        () => http.Response(_quoteBody, 200),
      ]);
      final call = await http.runWithClient(
        () => requestQuoteAttempt<OrchestraQuote>(
          createQuote: _createQuote,
          generateKey: _nextKey,
          policy: const IdempotentRetryPolicy(maxAttempts: 4),
          sleep: fakeSleep,
        ),
        () => script.client,
      );

      expect(call.outcome, SettlementHttpOutcome.success);
      expect(call.attempts, 4);
      expect(script.keys.toSet(), {call.key});
      expect(call.result.data!.quoteId, 'q_1');
      expect(sleeps, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 3),
      ]);
    });

    test('a deliberate re-quote uses a new key', () async {
      final script = _Scripted([
        () => http.Response(_quoteBody, 200),
        () => http.Response(_quoteBody, 200),
      ]);
      final first = await http.runWithClient(
        () => requestQuoteAttempt<OrchestraQuote>(
            createQuote: _createQuote, sleep: fakeSleep),
        () => script.client,
      );
      final second = await http.runWithClient(
        () => requestQuoteAttempt<OrchestraQuote>(
            createQuote: _createQuote, sleep: fakeSleep),
        () => script.client,
      );
      expect(first.key, isNot(second.key));
      expect(script.keys, [first.key, second.key]);
    });

    test('a definitive rejection is not retried', () async {
      final script = _Scripted([
        () => http.Response('{"error":"amount_too_small"}', 400),
      ]);
      final call = await http.runWithClient(
        () => requestQuoteAttempt<OrchestraQuote>(
            createQuote: _createQuote, sleep: fakeSleep),
        () => script.client,
      );
      expect(call.outcome, SettlementHttpOutcome.rejected);
      expect(call.attempts, 1);
      expect(sleeps, isEmpty);
    });

    test('a rate limit longer than the cap ends the call without waiting',
        () async {
      final script = _Scripted([
        () => http.Response('{}', 429, headers: {'retry-after': '120'}),
      ]);
      final call = await http.runWithClient(
        () => requestQuoteAttempt<OrchestraQuote>(
            createQuote: _createQuote, sleep: fakeSleep),
        () => script.client,
      );
      expect(call.outcome, SettlementHttpOutcome.rateLimited);
      expect(call.attempts, 1);
      expect(sleeps, isEmpty);
    });

    test("a quote response's Date header is exposed for skew", () async {
      final serverTime = DateTime.utc(2026, 9, 1, 12, 0, 30);
      final script = _Scripted([
        () => http.Response(_quoteBody, 200,
            headers: {'date': HttpDate.format(serverTime)}),
      ]);
      final result = await http.runWithClient(
          () => _createQuote('k'), () => script.client);

      expect(serverDateFromHeaders(result.headers), serverTime);
      expect(
        clockSkewFromHeaders(result.headers,
            receivedAt: serverTime.subtract(const Duration(seconds: 90))),
        const Duration(seconds: 90),
      );
      expect(
        clockSkewFromHeaders(result.headers,
            receivedAt: serverTime.add(const Duration(seconds: 90))),
        const Duration(seconds: -90),
      );
      expect(serverDateFromHeaders(const {}), isNull);
      expect(serverDateFromHeaders(const {'date': 'yesterday'}), isNull);
    });
  });

  group('submit keys', () {
    test('submitDeposit sends the key it is given', () async {
      final script = _Scripted([() => http.Response(_submitBody, 200)]);
      final result = await http.runWithClient(
          () => _submit('persisted-key'), () => script.client);
      expect(result.data!.orderId, 'ord_1');
      expect(script.paths.single, '/api/v1/orchestra/submit');
      expect(script.keys.single, 'persisted-key');
    });

    test('submitDeposit without a key still sends one', () async {
      final script = _Scripted([() => http.Response(_submitBody, 200)]);
      await http.runWithClient(
        () => OrchestraService.submitDeposit(quoteId: 'q_1'),
        () => script.client,
      );
      expect(script.keys.single, isNotNull);
      expect(script.keys.single, isNotEmpty);
    });

    test('the submit key stays the same across a process restart', () async {
      final keys = SubmitIdempotencyKeys.create(generateKey: _nextKey);

      final beforeKill = _Scripted([
        () => http.Response('{}', 502),
        () => throw TimeoutException('slow'),
        () => http.Response('{}', 503),
      ]);
      final first = await http.runWithClient(
        () => submitWithIdempotencyKeys<OrchestraSubmitResponse>(
          keys: keys,
          bodyFingerprint: _fingerprint,
          submit: _submit,
          generateKey: _nextKey,
          sleep: fakeSleep,
        ),
        () => beforeKill.client,
      );
      expect(first.call.outcome, SettlementHttpOutcome.transient);
      final persisted = jsonEncode(first.keys.toJson());

      final restored = SubmitIdempotencyKeys.fromJson(
          jsonDecode(persisted) as Map<String, dynamic>);
      final afterRestart = _Scripted([() => http.Response(_submitBody, 200)]);
      final second = await http.runWithClient(
        () => submitWithIdempotencyKeys<OrchestraSubmitResponse>(
          keys: restored,
          bodyFingerprint: _fingerprint,
          submit: _submit,
          generateKey: _nextKey,
          sleep: fakeSleep,
        ),
        () => afterRestart.client,
      );

      expect(second.call.outcome, SettlementHttpOutcome.success);
      expect({...beforeKill.keys, ...afterRestart.keys}, {keys.current});
      expect(second.keys.current, keys.current);
      expect(second.keys.history, isEmpty);
    });

    test('a definitive 4xx rejection makes the next submit use a new key',
        () async {
      final keys = SubmitIdempotencyKeys.create(generateKey: _nextKey);
      final script = _Scripted([
        () => http.Response('{"error":"deposit_not_found"}', 422),
        () => http.Response(_submitBody, 200),
      ]);

      final rejected = await http.runWithClient(
        () => submitWithIdempotencyKeys<OrchestraSubmitResponse>(
          keys: keys,
          bodyFingerprint: _fingerprint,
          submit: _submit,
          generateKey: _nextKey,
          sleep: fakeSleep,
        ),
        () => script.client,
      );
      expect(rejected.call.outcome, SettlementHttpOutcome.rejected);
      expect(rejected.call.attempts, 1);
      expect(rejected.keys.current, isNot(keys.current));
      expect(rejected.keys.history, [keys.current]);

      final roundTrip = SubmitIdempotencyKeys.fromJson(
          jsonDecode(jsonEncode(rejected.keys.toJson()))
              as Map<String, dynamic>);
      expect(roundTrip.history, [keys.current]);

      final accepted = await http.runWithClient(
        () => submitWithIdempotencyKeys<OrchestraSubmitResponse>(
          keys: roundTrip,
          bodyFingerprint: _fingerprint,
          submit: _submit,
          generateKey: _nextKey,
          sleep: fakeSleep,
        ),
        () => script.client,
      );
      expect(accepted.call.outcome, SettlementHttpOutcome.success);
      expect(script.keys, [keys.current, rejected.keys.current]);
      expect(accepted.keys.history, [keys.current]);
    });

    test('a changed proof body rotates the key into history', () async {
      final keys = SubmitIdempotencyKeys.create(generateKey: _nextKey);
      final proofA = submitBodyFingerprint(
          {'quoteId': 'q_1', 'sparkTxHash': 'A', 'bitcoinVout': null});
      final proofB =
          submitBodyFingerprint({'quoteId': 'q_1', 'sparkTxHash': 'B'});
      expect(proofA,
          submitBodyFingerprint({'sparkTxHash': 'A', 'quoteId': 'q_1'}));
      expect(proofA, isNot(proofB));

      final script = _Scripted([
        () => throw TimeoutException('slow'),
        () => throw TimeoutException('slow'),
        () => throw TimeoutException('slow'),
        () => http.Response(_submitBody, 200),
      ]);
      final first = await http.runWithClient(
        () => submitWithIdempotencyKeys<OrchestraSubmitResponse>(
          keys: keys,
          bodyFingerprint: proofA,
          submit: _submit,
          generateKey: _nextKey,
          sleep: fakeSleep,
        ),
        () => script.client,
      );
      expect(first.call.outcome, SettlementHttpOutcome.transient);
      expect(first.keys.current, keys.current);
      expect(first.keys.fingerprint, proofA);

      final restored = SubmitIdempotencyKeys.fromJson(
          jsonDecode(jsonEncode(first.keys.toJson())) as Map<String, dynamic>);
      expect(restored.fingerprint, proofA);
      final second = await http.runWithClient(
        () => submitWithIdempotencyKeys<OrchestraSubmitResponse>(
          keys: restored,
          bodyFingerprint: proofB,
          submit: _submit,
          generateKey: _nextKey,
          sleep: fakeSleep,
        ),
        () => script.client,
      );
      expect(second.call.outcome, SettlementHttpOutcome.success);
      expect(second.keys.current, isNot(keys.current));
      expect(second.keys.history, [keys.current]);
      expect(second.keys.fingerprint, proofB);
      expect(script.keys.last, second.keys.current);
      expect(script.keys.take(3), everyElement(keys.current));

      expect(second.keys.forBody(proofB, generateKey: _nextKey).current,
          second.keys.current);
    });

    test('408 and 429 keep the key', () {
      final keys = SubmitIdempotencyKeys.create(generateKey: _nextKey);
      for (final code in [408, 429, 500, 503]) {
        final outcome = classifySettlementResult(
            Result<void>(error: 'x', statusCode: code));
        expect(keys.afterOutcome(outcome, generateKey: _nextKey).current,
            keys.current,
            reason: '$code');
      }
      expect(classifySettlementResult(Result<void>(error: 'timeout')),
          SettlementHttpOutcome.transient);
    });
  });

  group('rate limit headers', () {
    final now = DateTime.utc(2026, 9, 1, 12);

    test('seconds to wait', () {
      expect(rateLimitWaitFromHeaders({'X-RateLimit-Reset': '7'}, now: now),
          const Duration(seconds: 7));
    });

    test('a Unix time in seconds or milliseconds', () {
      final reset = now.add(const Duration(seconds: 12));
      expect(
          rateLimitWaitFromHeaders(
              {'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}'},
              now: now),
          const Duration(seconds: 12));
      expect(
          rateLimitWaitFromHeaders(
              {'x-ratelimit-reset': '${reset.millisecondsSinceEpoch}'},
              now: now),
          const Duration(seconds: 12));
    });

    test('Retry-After seconds or date, never negative', () {
      expect(rateLimitWaitFromHeaders({'retry-after': '3'}, now: now),
          const Duration(seconds: 3));
      expect(
          rateLimitWaitFromHeaders({
            'retry-after': HttpDate.format(now.add(const Duration(seconds: 4)))
          }, now: now),
          const Duration(seconds: 4));
      expect(
          rateLimitWaitFromHeaders({
            'x-ratelimit-reset': '${now.millisecondsSinceEpoch ~/ 1000 - 60}'
          }, now: now),
          Duration.zero);
      expect(rateLimitWaitFromHeaders(const {}, now: now), isNull);
    });

    for (final value in ['NaN', 'Infinity', '-Infinity', '1e20', '-5']) {
      test('an unusable reset of $value is ignored, never thrown', () {
        expect(rateLimitWaitFromHeaders({'x-ratelimit-reset': value}, now: now),
            isNull);
        expect(
            rateLimitWaitFromHeaders(
                {'x-ratelimit-reset': value, 'retry-after': '2'},
                now: now),
            const Duration(seconds: 2));
      });
    }

    test('a huge Retry-After is ignored', () {
      expect(
          rateLimitWaitFromHeaders({'retry-after': '9000000000000000'},
              now: now),
          isNull);
    });

    test('a 429 with an unusable reset ends as a rate limited result',
        () async {
      final result = await callWithIdempotencyKey<int>(
        key: 'k',
        call: (_) async => Result<int>(
            error: 'slow down',
            statusCode: 429,
            headers: const {'X-RateLimit-Reset': 'NaN'}),
        sleep: (_) async {},
        now: () => now,
      );
      expect(result.outcome, SettlementHttpOutcome.rateLimited);
      expect(result.attempts, 3);
    });
  });
}
