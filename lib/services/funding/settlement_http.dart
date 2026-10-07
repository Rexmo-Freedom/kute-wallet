import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:kute/handlers/response_handlers.dart';
import 'package:kute/services/api/orchestra_api.dart';

/// How an Orchestra call that carries an idempotency key ended.
enum SettlementHttpOutcome {
  success,

  /// A timeout, transport error, 408 or 5xx. Retry with the same key.
  transient,

  /// HTTP 429. Retry with the same key after the reset.
  rateLimited,

  /// A definitive rejection: any other 4xx, or a 2xx the provider flagged
  /// as an error. Flashnet requires a new key for the next attempt.
  rejected,
}

SettlementHttpOutcome classifySettlementResult(Result<Object?> result) {
  final code = result.statusCode;
  if (result.isSuccess && code != null && code >= 200 && code < 300) {
    return SettlementHttpOutcome.success;
  }
  if (code == null) return SettlementHttpOutcome.transient;
  if (code == 429) return SettlementHttpOutcome.rateLimited;
  if (code == 408 || code >= 500) return SettlementHttpOutcome.transient;
  if (code >= 400 || (code >= 200 && code < 300)) {
    return SettlementHttpOutcome.rejected;
  }
  return SettlementHttpOutcome.transient;
}

String? _header(Map<String, String>? headers, String name) {
  if (headers == null) return null;
  final lower = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value.trim();
  }
  return null;
}

/// The server clock from a response's `Date` header, or null when missing
/// or unparseable. Quotes go through Kute's backend, so this is the
/// backend's clock at one second resolution.
DateTime? serverDateFromHeaders(Map<String, String>? headers) {
  final raw = _header(headers, 'date');
  if (raw == null || raw.isEmpty) return null;
  try {
    return HttpDate.parse(raw);
  } catch (_) {
    return null;
  }
}

/// Server clock minus the local clock when the response arrived, or null
/// when the response carried no usable `Date` header.
Duration? clockSkewFromHeaders(
  Map<String, String>? headers, {
  required DateTime receivedAt,
}) {
  final server = serverDateFromHeaders(headers);
  return server?.difference(receivedAt);
}

/// The largest millisecond value DateTime accepts.
const _kMaxEpochMs = 8640000000000000;

/// How long a rate limited response asks the caller to wait. Reads
/// `X-RateLimit-Reset` (seconds to wait, or a Unix time in seconds or
/// milliseconds) and then `Retry-After` (seconds or an HTTP date).
Duration? rateLimitWaitFromHeaders(
  Map<String, String>? headers, {
  required DateTime now,
}) {
  Duration nonNegative(Duration d) => d.isNegative ? Duration.zero : d;
  final reset = _header(headers, 'x-ratelimit-reset');
  final parsed = reset == null ? null : num.tryParse(reset);
  final resetValue = (parsed == null ||
          !parsed.isFinite ||
          parsed < 0 ||
          parsed > _kMaxEpochMs)
      ? null
      : parsed;
  if (resetValue != null) {
    if (resetValue > 1e12) {
      return nonNegative(DateTime.fromMillisecondsSinceEpoch(resetValue.toInt())
          .difference(now));
    }
    if (resetValue > 1e9) {
      return nonNegative(
          DateTime.fromMillisecondsSinceEpoch((resetValue * 1000).toInt())
              .difference(now));
    }
    return nonNegative(Duration(milliseconds: (resetValue * 1000).round()));
  }
  final retryAfter = _header(headers, 'retry-after');
  if (retryAfter == null || retryAfter.isEmpty) return null;
  final seconds = int.tryParse(retryAfter);
  if (seconds != null) {
    return seconds < 0 || seconds > _kMaxEpochMs ~/ 1000
        ? null
        : Duration(seconds: seconds);
  }
  try {
    return nonNegative(HttpDate.parse(retryAfter).difference(now));
  } catch (_) {
    return null;
  }
}

class IdempotentRetryPolicy {
  const IdempotentRetryPolicy({
    this.maxAttempts = 3,
    this.backoff = const [Duration(seconds: 1), Duration(seconds: 3)],
    this.maxRateLimitWait = const Duration(seconds: 30),
  });

  final int maxAttempts;

  /// Wait before attempt n + 2; the last value repeats.
  final List<Duration> backoff;

  /// A rate limit asking for a longer wait ends the call instead of holding
  /// the caller.
  final Duration maxRateLimitWait;

  Duration backoffBefore(int nextAttempt) {
    if (backoff.isEmpty) return Duration.zero;
    return backoff[math.min(nextAttempt - 2, backoff.length - 1)];
  }
}

class IdempotentCallResult<T> {
  const IdempotentCallResult({
    required this.result,
    required this.outcome,
    required this.attempts,
    required this.key,
  });

  final Result<T> result;
  final SettlementHttpOutcome outcome;
  final int attempts;

  /// The idempotency key every attempt of this call sent.
  final String key;
}

Future<void> _delay(Duration d) => Future<void>.delayed(d);

/// Sends [call] with [key] and retries it with the same key after a
/// timeout, transport error, 408, 5xx or 429. A success or a definitive
/// rejection ends the call.
Future<IdempotentCallResult<T>> callWithIdempotencyKey<T>({
  required String key,
  required Future<Result<T>> Function(String key) call,
  IdempotentRetryPolicy policy = const IdempotentRetryPolicy(),
  Future<void> Function(Duration delay) sleep = _delay,
  DateTime Function() now = DateTime.now,
}) async {
  var attempt = 0;
  while (true) {
    attempt++;
    final result = await call(key);
    final outcome = classifySettlementResult(result);
    IdempotentCallResult<T> done() => IdempotentCallResult<T>(
        result: result, outcome: outcome, attempts: attempt, key: key);
    if (outcome == SettlementHttpOutcome.success ||
        outcome == SettlementHttpOutcome.rejected ||
        attempt >= policy.maxAttempts) {
      return done();
    }
    var wait = policy.backoffBefore(attempt + 1);
    if (outcome == SettlementHttpOutcome.rateLimited) {
      final reset = rateLimitWaitFromHeaders(result.headers, now: now());
      if (reset != null) {
        if (reset > policy.maxRateLimitWait) return done();
        wait = reset;
      }
    }
    await sleep(wait);
  }
}

/// One deliberate quote attempt: a fresh key, reused only for transport
/// retries of this same request. A re-quote calls this again and gets a new
/// key.
Future<IdempotentCallResult<T>> requestQuoteAttempt<T>({
  required Future<Result<T>> Function(String key) createQuote,
  String Function() generateKey = OrchestraService.generateIdempotencyKey,
  IdempotentRetryPolicy policy = const IdempotentRetryPolicy(),
  Future<void> Function(Duration delay) sleep = _delay,
  DateTime Function() now = DateTime.now,
}) =>
    callWithIdempotencyKey<T>(
      key: generateKey(),
      call: createQuote,
      policy: policy,
      sleep: sleep,
      now: now,
    );

/// A stable fingerprint of a `submitDeposit` body. Entries with a null value
/// are dropped and keys are sorted, so the same proof always gives the same
/// value. Stored locally only; never logged.
String submitBodyFingerprint(Map<String, Object?> body) {
  final entries = body.entries.where((e) => e.value != null).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final canonical = jsonEncode({for (final e in entries) e.key: e.value});
  return sha256.convert(utf8.encode(canonical)).toString();
}

/// The submit idempotency keys of one settlement operation. The current key
/// is persisted with the funding proof and reused for every retry, across
/// restarts. A definitive rejection moves it to [history] and the next
/// submit uses a new key. The key is bound to the body it was sent with:
/// a changed proof also moves it to [history].
class SubmitIdempotencyKeys {
  const SubmitIdempotencyKeys({
    required this.current,
    this.history = const [],
    this.fingerprint,
  });

  factory SubmitIdempotencyKeys.create({
    String Function() generateKey = OrchestraService.generateIdempotencyKey,
  }) =>
      SubmitIdempotencyKeys(current: generateKey());

  factory SubmitIdempotencyKeys.fromJson(Map<String, dynamic> json) {
    final history = json['submitHistory'];
    final fingerprint = json['submitFingerprint'];
    return SubmitIdempotencyKeys(
      current: json['submit'] as String,
      history: history is List
          ? List.unmodifiable(history.whereType<String>())
          : const [],
      fingerprint: fingerprint is String ? fingerprint : null,
    );
  }

  final String current;
  final List<String> history;

  /// [submitBodyFingerprint] of the body [current] was first sent with.
  final String? fingerprint;

  Map<String, dynamic> toJson() => {
        'submit': current,
        'submitHistory': history,
        if (fingerprint != null) 'submitFingerprint': fingerprint,
      };

  /// The keys to send a body with [bodyFingerprint]. The first body claims
  /// the current key; a different body gets a new one.
  SubmitIdempotencyKeys forBody(
    String bodyFingerprint, {
    String Function() generateKey = OrchestraService.generateIdempotencyKey,
  }) {
    if (fingerprint == bodyFingerprint) return this;
    if (fingerprint == null) {
      return SubmitIdempotencyKeys(
          current: current, history: history, fingerprint: bodyFingerprint);
    }
    return SubmitIdempotencyKeys(
      current: generateKey(),
      history: List.unmodifiable([...history, current]),
      fingerprint: bodyFingerprint,
    );
  }

  SubmitIdempotencyKeys afterOutcome(
    SettlementHttpOutcome outcome, {
    String Function() generateKey = OrchestraService.generateIdempotencyKey,
  }) {
    if (outcome != SettlementHttpOutcome.rejected) return this;
    return SubmitIdempotencyKeys(
      current: generateKey(),
      history: List.unmodifiable([...history, current]),
      fingerprint: fingerprint,
    );
  }
}

class SubmitAttemptResult<T> {
  const SubmitAttemptResult({required this.call, required this.keys});

  final IdempotentCallResult<T> call;

  /// The keys to persist after this attempt.
  final SubmitIdempotencyKeys keys;
}

/// Sends a deposit submit with the operation's key for [bodyFingerprint],
/// retrying transport failures with that key, and returns the keys to
/// persist.
Future<SubmitAttemptResult<T>> submitWithIdempotencyKeys<T>({
  required SubmitIdempotencyKeys keys,
  required String bodyFingerprint,
  required Future<Result<T>> Function(String key) submit,
  String Function() generateKey = OrchestraService.generateIdempotencyKey,
  IdempotentRetryPolicy policy = const IdempotentRetryPolicy(),
  Future<void> Function(Duration delay) sleep = _delay,
  DateTime Function() now = DateTime.now,
}) async {
  final bound = keys.forBody(bodyFingerprint, generateKey: generateKey);
  final call = await callWithIdempotencyKey<T>(
    key: bound.current,
    call: submit,
    policy: policy,
    sleep: sleep,
    now: now,
  );
  return SubmitAttemptResult<T>(
    call: call,
    keys: bound.afterOutcome(call.outcome, generateKey: generateKey),
  );
}
