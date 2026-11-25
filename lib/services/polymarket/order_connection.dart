// lib/services/polymarket/order_connection.dart
//
// What a Predictions order knows about the connection it went out on: how
// many times it was posted, whether the connection read slow, and the one
// sentence that blames it.

import 'dart:async';
import 'dart:io' show HandshakeException, SocketException;

import 'package:http/http.dart' as http;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/http/connection_health.dart';
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/services/polymarket/placement_waits.dart';
import 'package:kute/services/polymarket_onboarding_service.dart'
    show PolymarketReadException;

/// POSTs of the latest order placed (0: it ended before any). Placements on
/// an account never overlap, so one count is enough. Analytics only.
abstract final class PolymarketOrderAttempts {
  static int last = 0;
}

/// `connection_slow` and `attempts`, for an order's outcome events.
Map<String, Object> polymarketOrderConnectionParams() => {
      'connection_slow': ConnectionHealth.instance.isSlow,
      'attempts': PolymarketOrderAttempts.last,
    };

/// Whether [error] proves the order did not go through, and that the network
/// is why. Every ambiguous end after a POST is a [PendingPolymarketOrder]
/// (hot_order_guard.dart), so these are all failures before one, or the proven
/// [PolymarketOrderNeverSent].
bool polymarketOrderEndedOnNetwork(Object error) {
  if (error is PendingPolymarketOrder || error is ResolvedPolymarketOrder) {
    return false;
  }
  if (error is PolymarketSetupIncomplete) {
    final cause = error.cause;
    return cause != null && polymarketOrderEndedOnNetwork(cause);
  }
  return error is PolymarketOrderNeverSent ||
      error is PolymarketReadException ||
      error is TimeoutException ||
      error is SocketException ||
      error is HandshakeException ||
      error is http.ClientException ||
      error
          .toString()
          .toLowerCase()
          .contains('could not connect to polymarket');
}

/// The slip's error line when the order ended on the network with the
/// connection reading slow; null otherwise, and the existing copy stands.
String? polymarketSlowConnectionLine(AppLocalizations l10n, Object error,
        {ConnectionHealth? health}) =>
    polymarketOrderEndedOnNetwork(error) &&
            (health ?? ConnectionHealth.instance).isSlow
        ? l10n.betConnectionSlowNotSent
        : null;
