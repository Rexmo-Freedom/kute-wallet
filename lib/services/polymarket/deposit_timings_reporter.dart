// lib/services/polymarket/deposit_timings_reporter.dart
//
// Tells the backend when a Predictions deposit's pUSD wrap confirmed and
// when the balance became bettable (`POST /api/v1/orchestra/timings`, the
// wallet session's bearer like every other /orchestra call), so fast-fill
// speed per route is visible server-side. Best-effort and silent: a 404
// (backend not deployed yet), a timeout or no session changes nothing for
// the person; the app never waits on it. Times are RFC 3339 UTC.
//
// Not routed through orchestra_api.dart (another agent's file this round);
// it uses the same session helper and a plain client.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:kute/models/affiliate_model.dart' show AffiliateService;

abstract final class PolymarketDepositTimingsReporter {
  /// Test seam: the client used for the POST.
  static http.Client Function() client = http.Client.new;

  /// Reports [wrappedAt] and/or [bettableAt] for the Orchestra order or
  /// quote [orderId]. Returns when the attempt is over; never throws.
  static Future<void> report({
    required String orderId,
    DateTime? wrappedAt,
    DateTime? bettableAt,
  }) async {
    if (orderId.isEmpty || (wrappedAt == null && bettableAt == null)) return;
    final backend = dotenv.isInitialized ? dotenv.env['BACKEND'] ?? '' : '';
    if (backend.isEmpty) return;
    final body = jsonEncode({
      'orderId': orderId,
      if (wrappedAt != null) 'wrappedAt': wrappedAt.toUtc().toIso8601String(),
      if (bettableAt != null)
        'bettableAt': bettableAt.toUtc().toIso8601String(),
    });
    try {
      await AffiliateService.sendWithSession('orchestra_timings', (auth) {
        return client()
            .post(
              Uri.parse('$backend/api/v1/orchestra/timings'),
              headers: {'Content-Type': 'application/json', ...auth},
              body: body,
            )
            .timeout(const Duration(seconds: 8));
      });
    } catch (_) {
      // Fire-and-forget: a missing route, a slow link or no session is
      // nothing the person needs to know about.
    }
  }
}
