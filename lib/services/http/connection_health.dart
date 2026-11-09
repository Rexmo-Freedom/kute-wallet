// lib/services/http/connection_health.dart
//
// Whether this phone's connection is slow right now, from the requests it
// has been making. Fed by [SharedHttpClient] for every request (before the
// telemetry sampling), and by the order POST and the order lookup, which do
// not go through the shared client. Hosts only: no path, no query, no body.
//
// It decides one thing: whether a failed order may blame the connection.
// One provider being down is not the person's connection, so a single host
// never trips it, however dead. Nothing here is sent anywhere.

import 'package:flutter/foundation.dart' show visibleForTesting;

class ConnectionHealth {
  ConnectionHealth({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static final ConnectionHealth instance = ConnectionHealth();

  /// How far back a request counts. Twice the order's retry window (60 s,
  /// HotOrderResendPolicy): while an order retries, the background polls are
  /// paused, so what other hosts did just before the order must still be in
  /// the window when the order ends.
  static const Duration window = Duration(minutes: 2);

  /// Failures a host needs inside [window]. One timeout on a good connection
  /// happens to everyone (PostHog: 2% of requests on the best phones).
  static const int minFailuresPerHost = 2;

  /// The share of a host's requests that must have failed. Set at half
  /// because a phone losing fewer than one request in two still gets most
  /// things through, and blaming its connection would be wrong.
  static const double minFailureShare = 0.5;

  /// Failing hosts needed, and they must also outnumber the hosts answering:
  /// two dead providers on a phone that reaches everything else is two dead
  /// providers.
  static const int minFailingHosts = 2;

  /// Samples kept per host, so a busy poller costs bounded memory.
  static const int maxSamplesPerHost = 32;

  final DateTime Function() _now;
  final Map<String, List<_Sample>> _byHost = {};

  /// A request to [host] got an answer, any answer: a 500 is a working
  /// connection to a server with a problem.
  void noteAnswered(String host) => _note(host, failed: false);

  /// A request to [host] timed out or failed on the transport.
  void noteFailed(String host) => _note(host, failed: true);

  void _note(String host, {required bool failed}) {
    if (host.isEmpty) return;
    final samples = _byHost.putIfAbsent(host.toLowerCase(), () => <_Sample>[]);
    samples.add(_Sample(_now(), failed));
    if (samples.length > maxSamplesPerHost) samples.removeAt(0);
    _prune();
  }

  void _prune() {
    final oldest = _now().subtract(window);
    _byHost.removeWhere((_, samples) {
      samples.removeWhere((s) => s.at.isBefore(oldest));
      return samples.isEmpty;
    });
  }

  /// Whether the connection reads slow. A host whose latest request got an
  /// answer is not failing, so a connection that came back reads healthy on
  /// the next answers, without waiting for the window to drain.
  bool get isSlow {
    _prune();
    var failing = 0;
    var answering = 0;
    for (final samples in _byHost.values) {
      if (!samples.last.failed) {
        answering++;
        continue;
      }
      final failures = samples.where((s) => s.failed).length;
      if (failures >= minFailuresPerHost &&
          failures / samples.length >= minFailureShare) {
        failing++;
      }
    }
    return failing >= minFailingHosts && failing > answering;
  }

  /// The network changed: what the old one did says nothing about this one.
  void reset() => _byHost.clear();

  /// Test-only: forces the shared instance to read slow.
  @visibleForTesting
  void debugMakeSlow() {
    for (final host in const ['a.test', 'b.test']) {
      noteFailed(host);
      noteFailed(host);
    }
  }
}

class _Sample {
  const _Sample(this.at, this.failed);
  final DateTime at;
  final bool failed;
}
