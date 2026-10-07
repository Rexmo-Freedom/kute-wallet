// lib/services/polymarket/placement_diagnostics.dart
//
// Credential-free diagnostics for a placement step that failed before an
// order was built: which step, how long it took, the error's type and a
// short message, then one probe of the venue's public time and geoblock
// endpoints so a log line shows whether the phone can reach Polymarket at
// all and which country the venue sees. Nothing here carries keys,
// signatures, addresses or order bodies.

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kute/services/tracking_service.dart';

class PolymarketPlacementDiagnostics {
  PolymarketPlacementDiagnostics._();

  static Future<void>? _probe;

  /// Records a failed step. [elapsed] is how long the step ran.
  static void stepFailed(String step, Object error, Duration elapsed) {
    final type = error.runtimeType.toString();
    TrackingService.track('polymarket_placement_step_failed', params: {
      'step': step,
      'error_type': type,
      'ms': elapsed.inMilliseconds,
      // Coarse bucket beside the raw ms (kept for existing dashboards).
      'latency_bucket': TrackingService.latencyBucket(elapsed.inMilliseconds),
    });
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

  /// The placement ended before an order was sent, and why.
  static void declined(String reason, {Object? error}) {
    TrackingService.track('polymarket_placement_declined', params: {
      'reason': reason,
      if (error != null) 'error_type': error.runtimeType.toString(),
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
    Map<String, dynamic>? response,
    Object? error,
    String? failureCode,
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
    TrackingService.track('polymarket_order_outcome', params: {
      'rung': rung,
      'type': orderType,
      'success': response?['success'] == true,
      if (response?['status'] != null) 'status': '${response!['status']}',
      if (failureCode != null) 'failure': failureCode,
    });
    note(error == null ? 'order_response' : 'order_failed', facts);
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
