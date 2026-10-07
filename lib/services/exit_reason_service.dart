import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kute/services/once_flags_service.dart';
import 'package:kute/services/tracking_service.dart';

/// Post-mortem reporter for the telemetry blind spot on Android.
///
/// LMK/OOM kills and native (Rust FFI) aborts never reach the Dart
/// crash handlers, so they show up in NEITHER Crashlytics nor PostHog;
/// Play vitals only reports Play-installed builds on devices whose
/// user opted into diagnostics sharing — and doesn't count LMK kills
/// as crashes at all. Net effect: a low-RAM phone that dies on every
/// refresh produces zero telemetry anywhere ("nothing shows").
///
/// Android 11+ keeps the answer in `ApplicationExitInfo`: on next
/// launch the OS will tell us exactly why the previous process
/// instance died (low_memory, crash_native, anr, ...) plus the
/// process importance and RSS/PSS at death. This service reads those
/// records via a platform channel and forwards the abnormal ones to
/// the analytics event stream (with the previous session's persisted
/// screen/flow snapshot) and, for deaths Crashlytics cannot see itself,
/// to Crashlytics as non-fatals grouped per reason.
///
/// On iOS the only post-mortem signal is Crashlytics'
/// `didCrashOnPreviousExecution`, reported as `app_crash_detected`.
class ExitReasonService {
  ExitReasonService._();

  static const MethodChannel _channel =
      MethodChannel('com.kutewallet.app/exit_info');

  /// Exit reasons worth reporting. Normal lifecycle exits
  /// (exit_self, user_requested, user_stopped, freezer,
  /// package_updated, ...) are noise and skipped.
  static const Set<String> _abnormal = {
    'low_memory',
    'crash',
    'crash_native',
    'anr',
    'signaled',
    'excessive_resource_usage',
    'dependency_died',
    'initialization_failure',
  };

  /// Deaths Crashlytics already captures natively (JVM crash handler, the
  /// NDK crash handler, and its own ApplicationExitInfo ANR reporting).
  /// Recording them again here would double every issue.
  static const Set<String> _capturedNatively = {'crash', 'crash_native', 'anr'};

  /// RunningAppProcessInfo.IMPORTANCE_PERCEPTIBLE: at or below this the
  /// user could see or feel the app when it died.
  static const int _perceptibleImportance = 230;

  /// Crash marker `crash_type` for an exit reason.
  @visibleForTesting
  static String crashTypeFor(String reasonName) {
    switch (reasonName) {
      case 'anr':
        return 'anr';
      case 'low_memory':
      case 'excessive_resource_usage':
        return 'oom';
      default:
        return 'native_crash';
    }
  }

  /// Coarse RSS bucket in MB ('<128' .. '2048+'); never the raw value.
  @visibleForTesting
  static String rssMbBucket(Object? rssKb) {
    final kb = rssKb is num ? rssKb.toInt() : int.tryParse('$rssKb');
    if (kb == null || kb <= 0) return 'unknown';
    final mb = kb ~/ 1024;
    if (mb < 128) return '<128';
    if (mb < 256) return '128-256';
    if (mb < 512) return '256-512';
    if (mb < 1024) return '512-1024';
    if (mb < 2048) return '1024-2048';
    return '2048+';
  }

  /// Query the OS for recent process deaths and report any abnormal
  /// ones we haven't reported before. Fire-and-forget from boot —
  /// never throws, no-ops below Android 11.
  static Future<void> reportLastExit() async {
    if (Platform.isIOS) {
      await _reportIosPreviousCrash();
      return;
    }
    if (!Platform.isAndroid) return;
    try {
      final lowRam = await _channel.invokeMethod<bool>('isLowRamDevice');
      if (lowRam != null) TrackingService.setSessionKey('low_ram', lowRam);
    } catch (_) {}
    try {
      final raw =
          await _channel.invokeMethod<List<dynamic>>('getLastExitReasons');
      if (raw == null || raw.isEmpty) return;
      handleExitRecords(raw, TrackingService.previousSessionSnapshot);
    } catch (_) {
      // Post-mortem reporting must never affect boot.
    }
  }

  /// Reports [raw] exit records (most recent first, as the OS returns
  /// them). The previous session's [snapshot] belongs to the most recent
  /// death only; older records are reported without it.
  @visibleForTesting
  static void handleExitRecords(
      List<dynamic> raw, Map<String, Object?>? snapshot) {
    var newest = true;
    for (final entry in raw) {
      if (entry is! Map) continue;
      final isNewest = newest;
      newest = false;
      final reasonName = entry['reasonName']?.toString() ?? 'unknown';
      if (!_abnormal.contains(reasonName)) continue;

      final timestamp = entry['timestamp']?.toString() ?? '0';
      // One report per unique death — the OS returns the same
      // history on every launch, so dedupe on the exit record's
      // timestamp via the once-flags box.
      if (!OnceFlagsService.claimOnce('exit_$timestamp')) continue;

      final importanceRaw = entry['importance'];
      final importance = importanceRaw is num
          ? importanceRaw.toInt()
          : int.tryParse('$importanceRaw');
      final inForeground =
          importance != null && importance <= _perceptibleImportance;
      final rssMb = rssMbBucket(entry['rssKb']);
      final crashType = crashTypeFor(reasonName);
      final snap = isNewest ? snapshot : null;

      // Analytics event — this is what makes low-RAM deaths finally
      // countable per device class in the dashboards.
      TrackingService.track('app_previous_exit_abnormal', params: {
        ...TrackingService.crashMarkerParams(
          crashType: crashType,
          errorClass: reasonName,
          snapshot: snap ?? const {},
        ),
        'exit_reason': reasonName,
        'importance': '${importance ?? ''}',
        'in_foreground': inForeground,
        'rss_mb': rssMb,
        'snapshot_available': snap != null,
      });

      // Unified crash marker. A background low-memory kill of a cached
      // process is routine Android housekeeping, not a crash.
      if (crashType != 'oom' || inForeground) {
        TrackingService.appCrashDetected(
          crashType: crashType,
          errorClass: reasonName,
          source: 'exit_info',
          snapshot: snap,
          exitReason: reasonName,
          inForeground: inForeground,
          rssMb: rssMb,
        );
      }

      if (_capturedNatively.contains(reasonName)) continue;

      // Crashlytics non-fatal for deaths Crashlytics can't see itself,
      // one issue per reason (distinct type and throw site).
      // `recordCrash` scrubs and release-gates internally.
      final (error, stack) = _exitError(reasonName, rssMb, inForeground);
      TrackingService.recordCrash(
        error,
        stack,
        reason: 'application_exit_info $reasonName',
        information: [
          'exit_reason: $reasonName',
          'importance: ${importance ?? 'unknown'}',
          'rss_mb: $rssMb',
          if (snap != null)
            for (final k in const ['last_screen', 'last_flow', 'last_step'])
              if (snap[k] is String) 'previous_$k: ${snap[k]}',
        ],
      );
    }
  }

  static (Object, StackTrace) _exitError(
      String reason, String rssMb, bool foreground) {
    try {
      switch (reason) {
        case 'low_memory':
          _throwLowMemory(rssMb, foreground);
        case 'excessive_resource_usage':
          _throwExcessiveResource(rssMb, foreground);
        case 'signaled':
          _throwSignaled(rssMb, foreground);
        case 'dependency_died':
          _throwDependencyDied(rssMb, foreground);
        case 'initialization_failure':
          _throwInitializationFailure(rssMb, foreground);
        default:
          throw PreviousProcessExit(reason, rssMb, foreground);
      }
    } catch (e, st) {
      return (e, st);
    }
  }

  static Never _throwLowMemory(String rss, bool fg) =>
      throw LowMemoryExit(rss, fg);
  static Never _throwExcessiveResource(String rss, bool fg) =>
      throw ExcessiveResourceExit(rss, fg);
  static Never _throwSignaled(String rss, bool fg) =>
      throw SignaledExit(rss, fg);
  static Never _throwDependencyDied(String rss, bool fg) =>
      throw DependencyDiedExit(rss, fg);
  static Never _throwInitializationFailure(String rss, bool fg) =>
      throw InitializationFailureExit(rss, fg);

  /// iOS: Crashlytics knows whether the previous run crashed natively.
  static Future<void> _reportIosPreviousCrash() async {
    if (kDebugMode) return;
    try {
      final crashed =
          await FirebaseCrashlytics.instance.didCrashOnPreviousExecution();
      if (!crashed) return;
      TrackingService.appCrashDetected(
        crashType: 'native_crash',
        errorClass: 'ios_crash',
        source: 'crashlytics',
        snapshot: TrackingService.previousSessionSnapshot,
      );
    } catch (_) {}
  }
}

/// A previous process death reported from ApplicationExitInfo. Each
/// reason has its own subtype so Crashlytics groups them separately.
class PreviousProcessExit implements Exception {
  final String reason;
  final String rssMb;
  final bool foreground;
  const PreviousProcessExit(this.reason, this.rssMb, this.foreground);

  @override
  String toString() => 'Previous process died: $reason rss_mb=$rssMb '
      'foreground=$foreground';
}

class LowMemoryExit extends PreviousProcessExit {
  const LowMemoryExit(String rssMb, bool foreground)
      : super('low_memory', rssMb, foreground);
}

class ExcessiveResourceExit extends PreviousProcessExit {
  const ExcessiveResourceExit(String rssMb, bool foreground)
      : super('excessive_resource_usage', rssMb, foreground);
}

class SignaledExit extends PreviousProcessExit {
  const SignaledExit(String rssMb, bool foreground)
      : super('signaled', rssMb, foreground);
}

class DependencyDiedExit extends PreviousProcessExit {
  const DependencyDiedExit(String rssMb, bool foreground)
      : super('dependency_died', rssMb, foreground);
}

class InitializationFailureExit extends PreviousProcessExit {
  const InitializationFailureExit(String rssMb, bool foreground)
      : super('initialization_failure', rssMb, foreground);
}
