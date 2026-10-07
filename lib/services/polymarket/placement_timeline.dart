// lib/services/polymarket/placement_timeline.dart
//
// Wall-clock stage marks for one prediction placement, so the five-minute
// market path (spending wallet, funded pUSD, approve, filled) can be
// measured on a device without logging keys, credentials, signatures or
// request bodies. Durations only, in milliseconds, per stage.
//
// One placement is active at a time. Marks made while none is active are
// ignored, so the shared placement engine can mark freely for sells and
// resting orders too.

import 'package:flutter/foundation.dart';
import 'package:kute/services/tracking_service.dart';

class PolymarketPlacementTimeline {
  PolymarketPlacementTimeline._();

  static PolymarketPlacementTimeline? _active;
  final Stopwatch _clock = Stopwatch()..start();
  final Map<String, int> _stages = <String, int>{};
  int _last = 0;

  /// Starts timing a placement. Any previous timeline is dropped unsent.
  static void begin() => _active = PolymarketPlacementTimeline._();

  /// Attributes the time since the previous mark to [stage].
  static void mark(String stage) {
    final active = _active;
    if (active == null) return;
    final now = active._clock.elapsedMilliseconds;
    active._stages[stage] = (active._stages[stage] ?? 0) + (now - active._last);
    active._last = now;
  }

  /// Debug builds only: prints [step] with the milliseconds since the tap
  /// and since the previous trace, to read the await chain between the
  /// approval and the post on a device. Never sent anywhere; no amounts.
  static void trace(String step) {
    if (!kDebugMode) return;
    final active = _active;
    if (active == null) return;
    final now = active._clock.elapsedMilliseconds;
    final since = now - active._lastTrace;
    active._lastTrace = now;
    debugPrint('[pm-latency] +${now}ms (+${since}ms) $step');
  }

  int _lastTrace = 0;

  /// Emits the stage durations and clears the timeline. [outcome] is a
  /// closed vocabulary: filled, pending, failed, declined, cancelled.
  static void finish(String outcome, {String? reason}) {
    final active = _active;
    _active = null;
    if (active == null) return;
    // Time after the last mark counts as the tail.
    final now = active._clock.elapsedMilliseconds;
    if (now > active._last) active._stages['tail'] = now - active._last;
    final params = <String, Object>{
      'outcome': outcome,
      if (reason != null) 'reason': reason,
      'ms_total': now,
      // Coarse bucket beside the raw ms (kept for existing dashboards).
      'total_latency_bucket': TrackingService.latencyBucket(now),
      for (final entry in active._stages.entries) 'ms_${entry.key}': entry.value,
    };
    if (kDebugMode) {
      debugPrint('polymarket placement timeline: $params');
    }
    TrackingService.track('polymarket_bet_timeline', params: params);
  }

  @visibleForTesting
  static Map<String, int>? get debugStages => _active?._stages;
}
