// lib/services/polymarket/placement_diagnostics.dart
//
// Credential-free diagnostics for a placement step that failed before an
// order was built: which step, how long it took, the error's type and a
// short message, then one probe of the venue's public time and geoblock
// endpoints so a log line shows whether the phone can reach Polymarket at
// all and which country the venue sees. Nothing here carries keys,
// signatures, addresses or order bodies.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kute/services/polymarket/order_refusal.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/tracking_service.dart';

class PolymarketPlacementDiagnostics {
  PolymarketPlacementDiagnostics._();

  static Future<void>? _probe;

  /// Whether the order being placed now was signed with Kute's builder
  /// code (set by PolymarketBackendService.signingBuilderCode just before
  /// signing). Carried on the order's outcome as `builder_code` so orders
  /// signed without one can be counted.
  static bool? _lastOrderAttributed;

  static void orderSignedWithBuilderCode(bool attributed) {
    _lastOrderAttributed = attributed;
    if (!attributed) {
      TrackingService.track('polymarket_order_signed_without_builder_code');
    }
  }

  /// Records a failed step. [elapsed] is how long the step ran. The
  /// network the phone is on (wifi / cellular / none / unknown) and the
  /// step's latency go with it so a slow link reads as one.
  static void stepFailed(String step, Object error, Duration elapsed) {
    final type = error.runtimeType.toString();
    TrackingService.track('polymarket_placement_step_failed', params: {
      'step': step,
      'stage': switch (step) {
        'setup' => 'setup',
        'order_book' => 'book',
        'fee_terms' => 'quote',
        'builder_code' => 'builder_code',
        _ => step,
      },
      'error_category': TrackingService.errorCategory(error),
      if (error is TimeoutException) 'timed_out': true,
      'error_type': type,
      'ms': elapsed.inMilliseconds,
      'latency_ms': elapsed.inMilliseconds,
      // Coarse bucket beside the raw ms (kept for existing dashboards).
      'latency_bucket': TrackingService.latencyBucket(elapsed.inMilliseconds),
      'network_type': NetworkTypeHint.current,
    });
    NetworkTypeHint.refresh();
    if (!kDebugMode) return;
    debugPrint('[pm] $step failed after ${elapsed.inMilliseconds}ms: '
        '$type: ${_brief(error)}');
    _probe ??= _probeVenue().whenComplete(() => _probe = null);
  }

  /// One fact line about the placement, credential-free. [facts] carry
  /// prices, sizes, order types, venue status words and error types;
  /// never keys, signatures, addresses or bodies.
  static void note(String stage, Map<String, Object?> facts) {
    if (!kDebugMode) return;
    final text = facts.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}=${e.value}')
        .join(' ');
    debugPrint('[pm] $stage $text');
  }

  /// The step a decline [reason] ended the placement at: one closed word.
  @visibleForTesting
  static String declineStage(String reason) => switch (reason) {
        'region_or_policy' => 'geo_blocked',
        'insufficient_balance' => 'balance_check',
        'approval_not_granted' => 'user_declined',
        'setup_timeout' || 'setup_failed' || 'wallet_not_ready' => 'setup',
        'prepare_failed' || 'no_intent' => 'quote',
        'liquidity_unavailable' => 'book',
        'side_mismatch' => 'sign',
        'advanced_unavailable' => 'policy',
        'previous_order_unconfirmed' ||
        'venue_unreachable' ||
        'order_in_progress' =>
          'guard_pending',
        'outcome_unknown' => 'submit',
        _ => 'unknown',
      };

  /// The placement ended without an accepted order, and why: before an
  /// order was sent, or with one whose answer proves nothing yet
  /// ([reason] outcome_unknown). [context] carries the order's shape
  /// (see PolymarketBetController.placementContext) when it is known.
  static void declined(String reason,
      {Object? error, String? stage, Map<String, Object>? context}) {
    TrackingService.track('polymarket_placement_declined', params: {
      ...?context,
      'reason': reason,
      'stage': stage ?? declineStage(reason),
      'network_type': NetworkTypeHint.current,
      if (error != null) 'error_type': error.runtimeType.toString(),
      if (error != null)
        'error_category': TrackingService.errorCategory(error),
      if (error is PolymarketOrderNotAcceptedException)
        ...polymarketRefusalParams(error.reason),
    });
    if (!kDebugMode) return;
    debugPrint('[pm] declined reason=$reason'
        '${error == null ? '' : ' error=${error.runtimeType}: ${_brief(error)}'}');
  }

  /// What the venue said to one posted order, or why the post failed.
  static void orderOutcome({
    required int rung,
    required double price,
    required double shares,
    required String orderType,
    bool? negRisk,
    Map<String, dynamic>? response,
    Object? error,
    String? failureCode,
    String? stage,
  }) {
    final facts = <String, Object?>{
      'rung': rung,
      'type': orderType,
      'price': price,
      'shares': shares,
      if (response != null) ...{
        'success': response['success'],
        'status': response['status'],
        'orderId': _shortId(response['orderID'] ?? response['orderId']),
        'errorMsg': response['errorMsg'],
        'taking': response['takingAmount'],
        'making': response['makingAmount'],
      },
      if (error != null) ...{
        'failure': failureCode,
        'error': '${error.runtimeType}: ${_brief(error)}',
      },
    };
    final refusal = error is PolymarketOrderNotAcceptedException
        ? error.reason
        : response?['success'] == false && response?['errorMsg'] is String
            ? response!['errorMsg'] as String
            : null;
    final attributed = _lastOrderAttributed;
    TrackingService.track('polymarket_order_outcome', params: {
      'rung': rung,
      'type': orderType,
      'success': response?['success'] == true,
      if (response?['status'] != null) 'status': '${response!['status']}',
      if (failureCode != null) 'failure': failureCode,
      if (stage != null) 'stage': stage,
      if (attributed != null) 'builder_code': attributed ? 'kute' : 'none',
      if (error != null) 'network_type': NetworkTypeHint.current,
      'price': price,
      'shares': shares,
      if (negRisk != null) 'venue_market_type': negRisk ? 'neg_risk' : 'standard',
      'sig_type': 3,
      if (refusal != null && refusal.isNotEmpty)
        ...polymarketRefusalParams(refusal),
    });
    note(error == null ? 'order_response' : 'order_failed', facts);
  }

  /// The venue refused an order inside a placement and the placement
  /// ran [heal] (refreshBalance, approveSpender, repairSetup, rebindKey)
  /// before signing again. Same event as a rung's outcome, told apart by
  /// stage self_heal and `heal`; [result] says how an approval went
  /// (sent, already_set, failed, timed_out). An allowance refusal carries
  /// the spender it named as a contract name, never the address.
  static void selfHeal({
    required String heal,
    required String refusal,
    required int attempt,
    bool? negRisk,
    String? result,
  }) {
    TrackingService.track('polymarket_order_outcome', params: {
      'stage': 'self_heal',
      'heal': heal,
      'attempt': attempt,
      'success': false,
      if (result != null) 'heal_result': result,
      if (negRisk != null) 'venue_market_type': negRisk ? 'neg_risk' : 'standard',
      'sig_type': 3,
      ...polymarketRefusalParams(refusal),
    });
    note('self_heal', {'heal': heal, 'attempt': attempt, 'result': result});
  }

  static String? _shortId(Object? id) {
    final text = id?.toString();
    if (text == null || text.length < 12) return text;
    return '${text.substring(0, 10)}…';
  }

  static String _brief(Object error) {
    final text = error.toString().replaceAll('\n', ' ');
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  static Future<void> _probeVenue() async {
    const targets = [
      ('clob.polymarket.com/time', 'https://clob.polymarket.com/time'),
      ('polymarket.com/api/geoblock', 'https://polymarket.com/api/geoblock'),
    ];
    for (final (name, url) in targets) {
      final clock = Stopwatch()..start();
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 6));
        final body = response.body.replaceAll('\n', ' ');
        debugPrint('[pm] probe $name → http=${response.statusCode} in '
            '${clock.elapsedMilliseconds}ms '
            '${body.length > 120 ? body.substring(0, 120) : body}');
      } catch (e) {
        debugPrint('[pm] probe $name → ${e.runtimeType} after '
            '${clock.elapsedMilliseconds}ms');
      }
    }
  }
}

/// The kind of link the phone is on, from the network interfaces it has up
/// (no plugin): `wifi`, `cellular`, `none` or `unknown`. Read as a cached
/// word so an event never waits on it; [refresh] re-reads in the
/// background. Interface names only; never an address.
abstract final class NetworkTypeHint {
  static String _current = 'unknown';
  static DateTime? _readAt;
  static Future<void>? _reading;
  static DateTime? _readingSince;

  /// How long one interface scan keeps the next [refresh] waiting. The
  /// scan is a plain `dart:io` read that nothing awaits, so a wedged one
  /// is simply abandoned by the next refresh instead of raced against a
  /// timer: the 2 s `.timeout` this replaced left a pending Timer behind
  /// every placement event, which the widget tests report as a leak.
  static const _kReadStale = Duration(seconds: 2);

  /// Test seam: a fixed answer instead of the interface scan.
  @visibleForTesting
  static String? debugOverride;

  static String get current {
    final override = debugOverride;
    if (override != null) return override;
    final readAt = _readAt;
    if (readAt == null ||
        DateTime.now().difference(readAt) > const Duration(seconds: 30)) {
      refresh();
    }
    return _current;
  }

  static void refresh() {
    if (debugOverride != null) return;
    final since = _readingSince;
    if (_reading != null &&
        since != null &&
        DateTime.now().difference(since) < _kReadStale) {
      return;
    }
    late final Future<void> read;
    _readingSince = DateTime.now();
    read = _reading = () async {
      try {
        final interfaces = await NetworkInterface.list(
            includeLoopback: false, includeLinkLocal: false);
        _current = classify(interfaces.map((i) => i.name));
      } catch (_) {
        _current = 'unknown';
      } finally {
        _readAt = DateTime.now();
        // A stale read a later refresh replaced must not clear the newer
        // one.
        if (identical(_reading, read)) {
          _reading = null;
          _readingSince = null;
        }
      }
    }();
  }

  /// `wifi` beats `cellular` when both are up (the phone routes over
  /// Wi-Fi); no interface at all is `none`.
  @visibleForTesting
  static String classify(Iterable<String> interfaceNames) {
    var wifi = false;
    var cellular = false;
    var other = false;
    for (final raw in interfaceNames) {
      final name = raw.toLowerCase();
      if (name.startsWith('wlan') || name == 'en0' || name.startsWith('ap')) {
        wifi = true;
      } else if (name.startsWith('rmnet') ||
          name.startsWith('ccmni') ||
          name.startsWith('pdp_ip') ||
          name.startsWith('wwan') ||
          name.startsWith('v4-rmnet') ||
          name.startsWith('clat')) {
        cellular = true;
      } else {
        other = true;
      }
    }
    if (wifi) return 'wifi';
    if (cellular) return 'cellular';
    if (other) return 'unknown';
    return 'none';
  }
}
