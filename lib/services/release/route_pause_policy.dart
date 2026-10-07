// lib/services/release/route_pause_policy.dart
//
// Remote pause switches for money routes (Wallet hardening Phase 5 plan
// B13, F16).
//
// The injectable port remains for settlement regression tests. Production uses
// purpose-specific authenticated capabilities at the quote/signing boundary;
// no analytics flag can disable fund recovery or control business availability.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads one remote flag and returns null when its value is unknown. Only
/// tests bind one; production never reads an analytics flag.
typedef RemoteFlagReader = Future<Object?> Function(String key);

enum PausableRoute {
  /// Direct Spark to and from HyperCore funding (S2).
  directHypercore('route_pause_direct_hypercore', 'direct_hypercore'),

  /// Ledger Bitcoin to and from HyperCore and Polymarket funding (S3).
  ledgerFunding('route_pause_ledger_funding', 'ledger_funding'),

  /// Ledger orders, cancels, sells, claims and transfers (S3).
  ledgerInvestingActions(
      'route_pause_ledger_investing_actions', 'ledger_investing_actions');

  const PausableRoute(this.flagKey, this.analyticsName);

  /// The remote flag key.
  final String flagKey;

  /// Value of the `route` property on `route_paused_shown`.
  final String analyticsName;
}

/// Thrown by [RoutePausePolicy.ensureNewOperationAllowed] when a new
/// operation on [route] is paused. Nothing was sent.
class RoutePausedException implements Exception {
  const RoutePausedException(this.route);

  final PausableRoute route;

  @override
  String toString() => 'RoutePausedException(${route.analyticsName})';
}

Future<Object?> _unknownRemoteFlag(String key) async => null;

class RoutePausePolicy {
  const RoutePausePolicy({
    RemoteFlagReader readFlag = _unknownRemoteFlag,
    this.readTimeout = const Duration(seconds: 3),
  }) : _readFlag = readFlag;

  final RemoteFlagReader _readFlag;

  /// A read slower than this is unknown, so it does not pause.
  final Duration readTimeout;

  /// The whole rule: only a value known to be `true` pauses.
  static bool pausesFor(Object? value) => value == true;

  /// Whether a NEW operation on [route] is paused. Never throws.
  Future<bool> isPaused(PausableRoute route) async {
    try {
      final value = await _readFlag(route.flagKey).timeout(readTimeout);
      return pausesFor(value);
    } catch (_) {
      return false;
    }
  }

  /// For service entry points that start a new operation. Throws
  /// [RoutePausedException] before anything is quoted, signed or sent.
  Future<void> ensureNewOperationAllowed(PausableRoute route) async {
    if (await isPaused(route)) throw RoutePausedException(route);
  }
}

/// Broad analytics pauses are retired. New operations now use the authenticated
/// runtime capabilities at their quote/signing boundary, with separate exit
/// permissions. The injectable legacy gate remains for settlement tests.
final routePausePolicyProvider =
    Provider<RoutePausePolicy>((ref) => const RoutePausePolicy());
