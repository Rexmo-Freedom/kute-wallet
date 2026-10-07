// lib/services/tracking/latency_tracker.dart
//
// Duration-only latency events. Each measurement becomes exactly ONE
// PostHog event named after its key, carrying the exact `duration_ms`
// plus the coarse `duration_bucket` dashboards group by, and nothing
// else beyond the categorical props the call site passes (route legs,
// venue, order kind, outcome). Never per-frame, never money, never ids.
//
// Two shapes:
//   * [start] / [stop] by key for measurements that span files (boot
//     stamps read from a widget or an SDK callback). A stop without a
//     matching start is a no-op, so a call site can never emit a bogus
//     zero. Overlapping measurements under one key are not supported:
//     the second start replaces the first.
//   * [record] for measurements that already have their own stopwatch
//     (an HTTP round-trip inside one function), which is also what keeps
//     concurrent quotes/orders from clobbering each other.
//
// Everything funnels through [TrackingService.track], so the analytics
// opt-out and the debug mute apply unchanged, the outbound scrubber runs,
// and nothing here can throw into the caller or block a flow.
import 'package:flutter/foundation.dart';
import 'package:kute/services/tracking_service.dart';

/// Event names for the latency measurements wired across the app. Each
/// is emitted at most once per measurement; the boot ones at most once
/// per process.
abstract final class LatencyKeys {
  /// First line of `main()` to the first rendered Flutter frame.
  static const appTimeToFirstFrame = 'app_time_to_first_frame';

  /// First line of `main()` to the first real (non-skeleton) balance on
  /// the home card.
  static const balanceLoaded = 'balance_loaded_latency';

  /// Spark SDK `connect()` to the first `synced` event of the boot session.
  static const sparkSync = 'spark_sync_latency';

  /// Orchestra quote request to its response (or failure).
  static const quoteRoundtrip = 'quote_roundtrip_latency';

  /// Venue order submit to the venue's acknowledgement (or failure).
  static const orderSubmitAck = 'order_submit_ack_latency';
}

abstract final class LatencyTracker {
  static final Map<String, Stopwatch> _running = <String, Stopwatch>{};

  /// Starts (or restarts) the measurement for [key].
  static void start(String key) {
    _running[key] = Stopwatch()..start();
  }

  /// True while [key] has a started, not yet stopped, measurement.
  static bool isRunning(String key) => _running.containsKey(key);

  /// Drops the measurement for [key] without emitting anything.
  static void cancel(String key) => _running.remove(key);

  /// Stops the measurement for [key] and emits one event named [key].
  /// Returns the elapsed milliseconds, or null (and emits nothing) when
  /// no measurement was started. [params] must be categorical only.
  static int? stop(String key, {Map<String, Object>? params}) {
    final sw = _running.remove(key);
    if (sw == null) return null;
    sw.stop();
    final ms = sw.elapsedMilliseconds;
    record(key, ms, params: params);
    return ms;
  }

  /// Emits one latency event for an already-measured duration.
  static void record(String event, int durationMs,
      {Map<String, Object>? params}) {
    if (durationMs < 0) return;
    try {
      TrackingService.track(event, params: {
        'duration_ms': durationMs,
        'duration_bucket': bucket(durationMs),
        if (params != null) ...params,
      });
    } catch (_) {/* never throw into a flow for a timing */}
  }

  /// Coarse duration bucket: '<500ms' | '500ms-1s' | '1-3s' | '3-10s' |
  /// '>10s'.
  static String bucket(int ms) {
    if (ms < 500) return '<500ms';
    if (ms < 1000) return '500ms-1s';
    if (ms < 3000) return '1-3s';
    if (ms < 10000) return '3-10s';
    return '>10s';
  }

  /// Test-only: forget every running measurement.
  @visibleForTesting
  static void debugReset() => _running.clear();
}
