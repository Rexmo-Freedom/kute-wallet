// lib/services/http/shared_http_client.dart
//
// One keep-alive HTTP client per host, behind the timeout policy in
// http_timeout_policy.dart.
//
// Why: a top-level `http.get` / `http.post` builds a fresh `Client`,
// opens a new TCP connection, runs a new TLS handshake, and throws the
// connection away. On a slow mobile link that is two to three extra
// round trips (close to a second) on every call, and the trading
// screens make several calls a tick. The clients here keep their
// connections pooled for the life of the process, so the second request
// to a host skips the handshake. One client per host keeps a stalled
// host from starving the others and keeps the per-host connection cap
// meaningful.
//
// Every request goes through [HttpTimeoutPolicy]: the per-attempt
// timeout the call site passes (unchanged from before the conversion),
// retries with backoff for background reads only, a deadline per user
// action, and one sampled latency event per request
// (`http_request_latency`, host and outcome only: no path, no query, no
// body).
//
// Call sites that take an injectable `http.Client` for tests pass it as
// [client]; it replaces the pooled client for that call and the policy
// still applies, so a test sees the same timeouts and error types as
// production. Tests that want to intercept every shared request set
// [debugOverride].
//
// A network change recycles every pool ([SharedHttpClient.recycle]): a
// kept-alive socket keeps the route it was opened on, so after a VPN
// switch the next request opens a connection on the new one. The checks
// that decide a region restriction never use these pools at all
// (lib/services/http/fresh_connection.dart).

import 'dart:async';
import 'dart:convert' show Encoding;
import 'dart:io' show HttpClient, SocketException, HandshakeException;
import 'dart:math' show Random;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'package:kute/services/http/http_timeout_policy.dart';
import 'package:kute/services/tracking/latency_tracker.dart';

export 'package:kute/services/http/http_timeout_policy.dart' show HttpCallKind;

abstract final class SharedHttpClient {
  static final Map<String, http.Client> _byHost = <String, http.Client>{};

  /// The `dart:io` client under each pooled [IOClient], so [recycle] can
  /// close a pool gently (in-flight requests finish, idle sockets go).
  static final Map<String, HttpClient> _innerByHost = <String, HttpClient>{};

  /// Pools dropped by [recycle], for tests.
  @visibleForTesting
  static int debugRecycles = 0;

  /// Test-only: when set, every shared request (one without its own
  /// [client]) goes to this client instead of the pooled one.
  @visibleForTesting
  static http.Client? debugOverride;

  /// The pooled client for [host]. Created on first use and kept: the
  /// pool is the point. Only a network change drops it ([recycle]).
  static http.Client forHost(String host) {
    final override = debugOverride;
    if (override != null) return override;
    final key = host.toLowerCase();
    return _byHost.putIfAbsent(key, () {
      final inner = HttpClient()
        ..connectionTimeout =
            HttpTimeoutPolicy.scaled(HttpTimeoutPolicy.connectTimeout)
        ..idleTimeout = HttpTimeoutPolicy.idleTimeout
        ..maxConnectionsPerHost = HttpTimeoutPolicy.maxConnectionsPerHost;
      _innerByHost[key] = inner;
      return IOClient(inner);
    });
  }

  /// The pooled client for [uri]'s host.
  static http.Client forUri(Uri uri) => forHost(uri.host);

  /// The network changed (lib/services/region_freshness.dart): drops every
  /// pool, so the next request to each host opens a connection on the new
  /// route. A kept-alive socket keeps the route it was opened on (on iOS a
  /// connection opened before a VPN came up stays outside the tunnel)
  /// until it idles out, and the servers that place the caller by IP
  /// would keep seeing the old network. Requests already in flight finish
  /// on their old connection; idle ones are closed now. Never throws.
  static void recycle() {
    final pools = Map<String, HttpClient>.of(_innerByHost);
    _byHost.clear();
    _innerByHost.clear();
    debugRecycles++;
    for (final inner in pools.values) {
      try {
        inner.close();
      } catch (_) {}
    }
  }

  /// `GET [uri]` under the policy for [kind].
  static Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    required HttpCallKind kind,
    Duration? timeout,
    Duration? deadline,
    http.Client? client,
  }) =>
      _run(
        uri,
        'GET',
        kind,
        (c) => c.get(uri, headers: headers),
        timeout: timeout,
        deadline: deadline,
        client: client,
      );

  /// `POST [uri]` under the policy for [kind].
  static Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    required HttpCallKind kind,
    Duration? timeout,
    Duration? deadline,
    http.Client? client,
  }) =>
      _run(
        uri,
        'POST',
        kind,
        (c) => c.post(uri, headers: headers, body: body, encoding: encoding),
        timeout: timeout,
        deadline: deadline,
        client: client,
      );

  /// `PUT [uri]` under the policy for [kind].
  static Future<http.Response> put(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    required HttpCallKind kind,
    Duration? timeout,
    Duration? deadline,
    http.Client? client,
  }) =>
      _run(
        uri,
        'PUT',
        kind,
        (c) => c.put(uri, headers: headers, body: body, encoding: encoding),
        timeout: timeout,
        deadline: deadline,
        client: client,
      );

  /// `PATCH [uri]` under the policy for [kind].
  static Future<http.Response> patch(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    required HttpCallKind kind,
    Duration? timeout,
    Duration? deadline,
    http.Client? client,
  }) =>
      _run(
        uri,
        'PATCH',
        kind,
        (c) => c.patch(uri, headers: headers, body: body, encoding: encoding),
        timeout: timeout,
        deadline: deadline,
        client: client,
      );

  /// Runs [send] under the policy for [kind]: per-attempt [timeout]
  /// (the kind's default when null), retries with backoff for background
  /// reads, the kind's [deadline] across attempts, one latency sample.
  ///
  /// Error types are the ones a bare `http.get(...).timeout(...)` threw:
  /// [TimeoutException] on a slow answer, [http.ClientException] /
  /// [SocketException] on a transport failure. A deadline that runs out
  /// surfaces as [TimeoutException] too.
  static Future<http.Response> _run(
    Uri uri,
    String method,
    HttpCallKind kind,
    Future<http.Response> Function(http.Client client) send, {
    Duration? timeout,
    Duration? deadline,
    http.Client? client,
  }) async {
    final perAttempt = HttpTimeoutPolicy.scaled(
        timeout ?? HttpTimeoutPolicy.defaultTimeout(kind));
    final total = deadline ?? HttpTimeoutPolicy.deadline(kind);
    final attempts = HttpTimeoutPolicy.attempts(kind);
    final started = Stopwatch()..start();

    Duration remaining() =>
        total == null ? perAttempt : total - started.elapsed;

    for (var attempt = 1;; attempt++) {
      final budget = total == null ? perAttempt : _min(perAttempt, remaining());
      if (budget <= Duration.zero) {
        throw TimeoutException('deadline exceeded', total);
      }
      final sw = Stopwatch()..start();
      http.Response response;
      try {
        // Resolved per attempt: a retry after the pools were recycled
        // (a network change) resolves a new client.
        final c = client ?? forUri(uri);
        response = await send(c).timeout(budget);
      } catch (e) {
        sw.stop();
        _record(uri, method, kind, attempt, sw.elapsedMilliseconds,
            outcome: _outcomeOf(e));
        final canRetry = attempt < attempts &&
            HttpTimeoutPolicy.isRetryable(kind, error: e) &&
            (total == null || remaining() > Duration.zero);
        if (!canRetry) rethrow;
        await Future<void>.delayed(HttpTimeoutPolicy.backoffFor(attempt));
        continue;
      }
      sw.stop();
      _record(uri, method, kind, attempt, sw.elapsedMilliseconds,
          outcome: response.statusCode >= 400 ? 'http_error' : 'ok',
          statusCode: response.statusCode);
      final retry5xx = attempt < attempts &&
          HttpTimeoutPolicy.isRetryable(kind, response: response) &&
          (total == null || remaining() > Duration.zero);
      if (!retry5xx) return response;
      await Future<void>.delayed(HttpTimeoutPolicy.backoffFor(attempt));
    }
  }

  static Duration _min(Duration a, Duration b) => a < b ? a : b;

  static String _outcomeOf(Object e) {
    if (e is TimeoutException) return 'timeout';
    if (e is SocketException ||
        e is HandshakeException ||
        e is http.ClientException) {
      return 'network_error';
    }
    return 'error';
  }

  // ── telemetry ──────────────────────────────────────────────────────
  //
  // `http_request_latency`: one sample per request. Successes are sampled
  // 1 in [okSampleRate]; failures are all sent, capped at
  // [failureCapPerMinute] per process minute so an offline device does
  // not flood. Properties: host (never a path or query), method, call
  // kind, outcome, status class, attempt number, and the exact
  // `duration_ms` with its bucket (added by LatencyTracker). The network
  // type comes from PostHog's own `$network_wifi` / `$network_cellular`
  // event properties.

  /// One in this many successful requests is reported.
  static const int okSampleRate = 20;

  /// Failure samples per rolling minute, process-wide.
  static const int failureCapPerMinute = 20;

  static final Random _sampler = Random();
  static int _failureWindowStartMs = 0;
  static int _failuresInWindow = 0;

  /// Test-only: every request is reported (no sampling, no cap).
  @visibleForTesting
  static bool debugReportEveryRequest = false;

  static void _record(
    Uri uri,
    String method,
    HttpCallKind kind,
    int attempt,
    int durationMs, {
    required String outcome,
    int? statusCode,
  }) {
    try {
      if (!debugReportEveryRequest) {
        if (outcome == 'ok') {
          if (_sampler.nextInt(okSampleRate) != 0) return;
        } else if (!_admitFailure()) {
          return;
        }
      }
      LatencyTracker.record(LatencyKeys.httpRequest, durationMs, params: {
        'host': uri.host,
        'method': method,
        'call_kind': kind.name,
        'outcome': outcome,
        if (statusCode != null) 'status_class': '${statusCode ~/ 100}xx',
        'attempt': attempt,
      });
    } catch (_) {
      // Telemetry never reaches the request.
    }
  }

  static bool _admitFailure() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _failureWindowStartMs >= 60000) {
      _failureWindowStartMs = now;
      _failuresInWindow = 0;
    }
    if (_failuresInWindow >= failureCapPerMinute) return false;
    _failuresInWindow++;
    return true;
  }

  /// Test-only: drop every pooled client and the sampling state.
  @visibleForTesting
  static void debugReset() {
    for (final c in _byHost.values) {
      c.close();
    }
    _byHost.clear();
    _innerByHost.clear();
    debugRecycles = 0;
    debugOverride = null;
    debugReportEveryRequest = false;
    _failureWindowStartMs = 0;
    _failuresInWindow = 0;
  }
}
