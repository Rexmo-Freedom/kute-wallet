// The directed USDB → BTC minimum, checked before quotes or native sends.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/one_balance/route_minimums.dart';

final dollarsToBitcoinRoute = RouteKey(
    fromChain: 'spark', fromAsset: 'USDB', toChain: 'spark', toAsset: 'BTC');

/// Nothing was quoted or sent for this below-minimum remainder.
class DollarsToBitcoinBelowMinimum implements Exception {
  const DollarsToBitcoinBelowMinimum();
}

class DollarsToBitcoinMinimum {
  DollarsToBitcoinMinimum(
      {RouteLimitsFetcher? fetch, DateTime Function()? clock})
      : _fetch = fetch ?? OrchestraService.getRouteLimits,
        _clock = clock ?? DateTime.now;
  final RouteLimitsFetcher _fetch;
  final DateTime Function() _clock;
  DateTime? _readAt;
  OrchestraRouteLimits? _cached;
  Future<OrchestraRouteLimits?>? _inFlight;

  static bool belowFloor(BigInt amount) =>
      amount < BigInt.from((kOneBalanceMinimumUsd * 1000000).round());

  static bool belowLimits(BigInt amount, OrchestraRouteLimits? limits) {
    if (belowFloor(amount)) return true;
    if (limits == null) return false;
    final minimums = <BigInt>[
      if (limits.exactInMinBaseUnits case final n?) n,
      if (limits.exactInMinUsdCents case final n?)
        BigInt.from(n) * BigInt.from(10000),
      if (limits.orderMinUsdCents case final n?)
        BigInt.from(n) * BigInt.from(10000),
    ];
    return minimums.any((minimum) => amount < minimum);
  }

  Future<void> check(BigInt amount) async {
    // Dust needs no network, approval, quote or settlement record.
    if (belowFloor(amount)) throw const DollarsToBitcoinBelowMinimum();
    final limits = await _limits();
    if (belowLimits(amount, limits)) {
      throw const DollarsToBitcoinBelowMinimum();
    }
  }

  Future<OrchestraRouteLimits?> _limits() {
    final readAt = _readAt;
    final ttl =
        _cached == null ? kRouteMinimumsRetryAfter : kRouteMinimumsCacheTtl;
    if (readAt != null && _clock().difference(readAt) < ttl) {
      return Future.value(_cached);
    }
    return _inFlight ??= _read().whenComplete(() => _inFlight = null);
  }

  Future<OrchestraRouteLimits?> _read() async {
    OrchestraRouteLimits? limits;
    try {
      limits = await _fetch(dollarsToBitcoinRoute)
          .timeout(const Duration(seconds: 3));
    } catch (_) {/* Unknown limits leave the verified quote authoritative. */}
    _cached = limits;
    _readAt = _clock();
    return limits;
  }
}

final dollarsToBitcoinMinimumProvider =
    Provider<DollarsToBitcoinMinimum>((ref) => DollarsToBitcoinMinimum());
