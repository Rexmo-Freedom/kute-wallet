// lib/services/http/http_timeout_policy.dart
//
// The one timeout policy every converted HTTP call site follows. The
// numbers live here so a slow-link fix is one edit, not a hunt through
// forty `.timeout(const Duration(...))` calls.
//
// Policy
// ------
// * Connect fast, read patiently. Opening the connection (DNS, TCP, TLS)
//   gets a short budget: a server that cannot be reached in a few seconds
//   will not be reached by waiting longer, and failing fast lets the
//   failover paths (the next Polygon RPC, the cached value) take over.
//   Reading the answer gets a longer budget, because a slow mobile link
//   still delivers a correct answer, only late. The connect budget is set
//   once on the shared `HttpClient` ([connectTimeout]); the read budget is
//   the per-attempt [timeout] a call site passes (its pre-existing
//   `.timeout(...)` value) or [defaultTimeout] for its [HttpCallKind].
// * Retries only where they are safe. Only [HttpCallKind.backgroundRead]
//   (an idempotent read nobody is waiting on: a poll tick, a prefetch, a
//   catalog refresh) is retried, up to [maxBackgroundRetries] times, on a
//   timeout, a transport error or a 5xx answer. Each retry waits
//   [backoffFor]: exponential from [backoffBase], with ±50 % jitter so a
//   screen full of pollers does not retry in lockstep. A user action and
//   an order submit are sent exactly once: a second submit could place a
//   second order, and a user waiting on a spinner is better served by a
//   clear failure (and the caller's own fallback) than by a silent retry.
// * A deadline per user action. [HttpCallKind.userAction] calls are bound
//   by [userActionDeadline] in total (the caller may pass a tighter
//   `deadline`), so the retries and failovers a caller stacks on top can
//   never hold a tap for longer than that. Background reads have their own
//   [backgroundDeadline] covering all attempts.
// * More generous on cellular. When the network profile is known to be
//   cellular ([NetworkProfile.cellular]) every budget is multiplied by
//   [cellularFactor]. The profile is fed by [networkProfile]; the app
//   does not ship `connectivity_plus`, so it stays [NetworkProfile.unknown]
//   (no scaling) until a connectivity source sets it. PostHog's own
//   `$network_wifi` / `$network_cellular` event properties are what the
//   latency telemetry is split by; they need no code here.
// * Screens never wait on background reads: that is a call-site rule (show
//   the saved value, refresh behind it), not something this helper can
//   enforce, but [HttpCallKind.backgroundRead] names the intent at every
//   site so a reviewer can see when a screen does.
//
// Everything here is pure policy: no sockets, no clients. The shared
// client ([SharedHttpClient]) applies it.

import 'dart:async';
import 'dart:io' show SocketException, HandshakeException;
import 'dart:math' show Random, min, pow;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

/// What a request is for; decides retries and deadlines.
enum HttpCallKind {
  /// An idempotent read nobody is waiting on (a poll tick, a prefetch, a
  /// catalog or icon fetch). Retried with backoff and jitter inside
  /// [HttpTimeoutPolicy.backgroundDeadline]. Never for anything that
  /// changes server state.
  backgroundRead,

  /// A read or write on the user's critical path (a quote, a balance the
  /// user is looking at, a credential derivation). One attempt, bounded by
  /// [HttpTimeoutPolicy.userActionDeadline].
  userAction,

  /// An order submit, a transfer, anything that moves money. One attempt,
  /// never retried, never shortened below its own timeout.
  submit,
}

/// The network the device is on, as far as the app knows.
enum NetworkProfile { unknown, wifi, cellular }

abstract final class HttpTimeoutPolicy {
  /// Budget for DNS + TCP + TLS on a new connection. Set on the shared
  /// `HttpClient`; a pooled keep-alive connection pays it once.
  static const Duration connectTimeout = Duration(seconds: 5);

  /// How long an idle pooled connection is kept before it is closed.
  static const Duration idleTimeout = Duration(seconds: 30);

  /// Parallel connections per host. Six covers the trading screen's
  /// five-read tick plus one user action without queueing.
  static const int maxConnectionsPerHost = 6;

  /// Read budget per attempt when the call site does not pass one.
  static Duration defaultTimeout(HttpCallKind kind) => switch (kind) {
        HttpCallKind.backgroundRead => const Duration(seconds: 10),
        HttpCallKind.userAction => const Duration(seconds: 8),
        HttpCallKind.submit => const Duration(seconds: 15),
      };

  /// Longest a user action may take across every attempt and failover.
  static const Duration userActionDeadline = Duration(seconds: 20);

  /// Longest a background read may take across its retries.
  static const Duration backgroundDeadline = Duration(seconds: 30);

  /// Retries after the first attempt, background reads only.
  static const int maxBackgroundRetries = 2;

  /// First backoff; doubles per retry before jitter.
  static const Duration backoffBase = Duration(milliseconds: 400);

  /// Budgets are multiplied by this on cellular.
  static const double cellularFactor = 1.5;

  /// The device's network as last reported. Nothing in the app sets it
  /// yet (no `connectivity_plus`); a connectivity source can assign it
  /// and every budget scales from the next request on.
  static NetworkProfile networkProfile = NetworkProfile.unknown;

  static final Random _random = Random();

  /// [base] scaled for the current network profile.
  static Duration scaled(Duration base) {
    if (networkProfile != NetworkProfile.cellular) return base;
    return Duration(
        milliseconds: (base.inMilliseconds * cellularFactor).round());
  }

  /// Whether [kind] may be retried at all.
  static bool retries(HttpCallKind kind) =>
      kind == HttpCallKind.backgroundRead;

  /// Attempts in total for [kind] (first try included).
  static int attempts(HttpCallKind kind) =>
      retries(kind) ? 1 + maxBackgroundRetries : 1;

  /// Deadline across every attempt for [kind]; null for a submit, whose
  /// single attempt is bounded by its own timeout only.
  static Duration? deadline(HttpCallKind kind) => switch (kind) {
        HttpCallKind.backgroundRead => scaled(backgroundDeadline),
        HttpCallKind.userAction => scaled(userActionDeadline),
        HttpCallKind.submit => null,
      };

  /// Wait before retry number [retry] (1-based): exponential from
  /// [backoffBase] with ±50 % jitter, capped at 5 s.
  static Duration backoffFor(int retry, {Random? random}) {
    final rng = random ?? _random;
    final base = backoffBase.inMilliseconds * pow(2, retry - 1).toDouble();
    final jitter = 0.5 + rng.nextDouble(); // 0.5 .. 1.5
    return Duration(milliseconds: min(5000, (base * jitter).round()));
  }

  /// Whether a failed attempt of [kind] may be tried again given the
  /// error (or the 5xx [response]).
  static bool isRetryable(HttpCallKind kind,
      {Object? error, http.Response? response}) {
    if (!retries(kind)) return false;
    if (response != null) return response.statusCode >= 500;
    return error is TimeoutException ||
        error is SocketException ||
        error is HandshakeException ||
        error is http.ClientException;
  }

  /// Test-only: the current profile is restored by the caller.
  @visibleForTesting
  static void debugSetProfile(NetworkProfile profile) =>
      networkProfile = profile;
}
