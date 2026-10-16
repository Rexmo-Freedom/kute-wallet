import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'package:kute/services/tracking_service.dart';

typedef SdkBalanceReporter = void Function(
    String event, Map<String, Object> properties);

enum UsdCatchUpReason { missingEntry, unchangedNumeric }

enum UsdCatchUpResult { caughtUp, stillBehind, readFailed }

enum UsdSyncResult { ok, error, timeout }

enum UsdRecoveryResult { ok, deferred, failed }

enum UsdRecoveryReason {
  reconnected,
  notConnected,
  walletChanged,
  syncInFlight,
  mutationInFlight,
  optimizationInFlight,
  pendingSend,
  lookupFailed,
  lookupTimeout,
  teardownFailed,
  connectFailed,
}

String _code(Enum value) => value.name.replaceAllMapped(
    RegExp('[A-Z]'), (match) => '_${match[0]!.toLowerCase()}');

String _source(String value) => switch (value) {
      'seed' ||
      'ledger' ||
      'retry' ||
      'resume' ||
      'refresh' ||
      'order_leg' =>
        value,
      _ => 'unknown',
    };

void _track(String event, Map<String, Object> properties) {
  // Keep the closed event set explicit at the capture boundary so the
  // checked-in catalog can be derived from actual production emitters.
  switch (event) {
    case 'usd_balance_catchup':
      TrackingService.track('usd_balance_catchup', params: properties);
      return;
    case 'usd_balance_sync':
      TrackingService.track('usd_balance_sync', params: properties);
      return;
    case 'usd_token_recovery':
      TrackingService.track('usd_token_recovery', params: properties);
      return;
  }
}

/// Bounded outcome events, never per poll. Typed fields prevent balances,
/// payment identifiers and native error messages entering this reporter.
/// The normal TrackingService debug mute and opt-out apply unchanged.
class SdkBalanceTelemetry {
  const SdkBalanceTelemetry({this.reporter = _track});

  final SdkBalanceReporter reporter;

  void _emit(String event, Map<String, Object> properties) {
    // Debug PostHog is intentionally muted. Keep the bounded, typed outcome
    // locally visible so a stalled sync or deferred recovery can be diagnosed
    // on a device without logging balances, identifiers or native errors.
    if (kDebugMode) debugPrint('[sdk-balance] $event $properties');
    try {
      reporter(event, properties);
    } catch (_) {
      // Analytics never change wallet behavior.
    }
  }

  void catchUp({
    required String source,
    required UsdCatchUpReason reason,
    required UsdCatchUpResult result,
    required int durationMs,
    required int retryIndex,
  }) =>
      _emit('usd_balance_catchup', {
        'source': _source(source),
        'reason': _code(reason),
        'result': _code(result),
        'duration_ms': durationMs,
        'retry_index': retryIndex,
      });

  void sync({
    required String source,
    required UsdSyncResult result,
    required int durationMs,
  }) =>
      _emit('usd_balance_sync', {
        'source': _source(source),
        'result': _code(result),
        'duration_ms': durationMs,
      });

  void recovery({
    required String source,
    required UsdRecoveryResult result,
    required UsdRecoveryReason reason,
    required bool attempted,
    required int durationMs,
  }) =>
      _emit('usd_token_recovery', {
        'source': _source(source),
        'result': _code(result),
        'reason': _code(reason),
        'attempted': attempted,
        'duration_ms': durationMs,
      });
}
