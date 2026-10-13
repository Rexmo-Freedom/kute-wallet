// lib/services/one_balance/route_minimums.dart
//
// "What is the smallest sweep the route takes right now?" The sweeper
// asks this before every pass so cash below the floor shows as "$X
// unavailable until balancing completes" instead of being quoted and refused. The live
// figure comes from Orchestra's `/limits` (the backend proxy, then the
// public host) for the two swap-back routes, cached ten minutes; the
// app's own $1 floor sits under it. A quote that still answers
// `amount_too_small` raises the floor for that venue until the cache
// turns over, because provider legs add moving minimums `/limits`
// does not show.
//
// Nothing here moves money; a failed read falls back to the floor.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';

/// The app's floor for a USD leg, under whatever the route says.
const double kOneBalanceMinimumUsd = 1.0;

/// How long a live limit (or a refused-amount hint) is trusted.
const Duration kRouteMinimumsCacheTtl = Duration(minutes: 10);

/// How long a failed `/limits` read is remembered before another try.
const Duration kRouteMinimumsRetryAfter = Duration(minutes: 1);

/// The route a sweep from [venue] rides back to Dollars on.
RouteKey sweepRouteOf(OneBalanceVenue venue) => switch (venue) {
      OneBalanceVenue.predictions => RouteKey(
          fromChain: 'polygon',
          fromAsset: 'USDC.e',
          toChain: 'spark',
          toAsset: 'USDB',
        ),
      OneBalanceVenue.investing => RouteKey(
          fromChain: 'hypercore',
          fromAsset: 'USDC',
          toChain: 'spark',
          toAsset: 'USDB',
        ),
    };

typedef RouteLimitsFetcher = Future<OrchestraRouteLimits?> Function(
    RouteKey route);

class _CachedMinimum {
  _CachedMinimum({required this.liveUsd, required this.readAt});

  /// The route's own minimum, or null when the read gave none.
  final double? liveUsd;
  final DateTime readAt;
}

class _RefusedHint {
  _RefusedHint({required this.usd, required this.at});

  final double usd;
  final DateTime at;
}

/// Live swap-back minimums with a floor, a cache and quote feedback.
class RouteMinimums {
  RouteMinimums({
    RouteLimitsFetcher? fetch,
    DateTime Function()? clock,
    this.floorUsd = kOneBalanceMinimumUsd,
  })  : _fetch = fetch ?? ((route) => OrchestraService.getRouteLimits(route)),
        _clock = clock ?? DateTime.now;

  final RouteLimitsFetcher _fetch;
  final DateTime Function() _clock;
  final double floorUsd;

  final Map<OneBalanceVenue, _CachedMinimum> _cache = {};
  final Map<OneBalanceVenue, Future<double?>> _inFlight = {};
  final Map<OneBalanceVenue, _RefusedHint> _refused = {};

  /// The smallest sweep [venue] accepts right now: the larger of the
  /// live route minimum, the floor and any amount a quote refused.
  Future<double> minimumUsd(OneBalanceVenue venue) async {
    final live = await _liveMinimum(venue);
    return _combine(venue, live);
  }

  /// What [minimumUsd] would answer from memory alone (null before the
  /// first read): for callers that must not wait.
  double? cachedMinimumUsd(OneBalanceVenue venue) {
    final cached = _cache[venue];
    if (cached == null) return null;
    return _combine(venue, cached.liveUsd);
  }

  /// A quote for [usd] came back `amount_too_small`: the real minimum is
  /// above it. Remembered for the cache's lifetime.
  void noteAmountTooSmall(OneBalanceVenue venue, double usd) {
    if (!usd.isFinite || usd <= 0) return;
    final now = _clock();
    final current = _refused[venue];
    if (current != null &&
        now.difference(current.at) < kRouteMinimumsCacheTtl &&
        current.usd >= usd) {
      return;
    }
    _refused[venue] = _RefusedHint(usd: usd, at: now);
  }

  double _combine(OneBalanceVenue venue, double? live) {
    var min = floorUsd;
    if (live != null && live.isFinite && live > min) min = live;
    final hint = _refused[venue];
    if (hint != null) {
      if (_clock().difference(hint.at) >= kRouteMinimumsCacheTtl) {
        _refused.remove(venue);
      } else if (hint.usd + 0.01 > min) {
        // The refused amount itself is below the minimum, so the next
        // attempt needs strictly more.
        min = hint.usd + 0.01;
      }
    }
    return min;
  }

  Future<double?> _liveMinimum(OneBalanceVenue venue) {
    final cached = _cache[venue];
    if (cached != null) {
      final age = _clock().difference(cached.readAt);
      final ttl = cached.liveUsd == null
          ? kRouteMinimumsRetryAfter
          : kRouteMinimumsCacheTtl;
      if (age < ttl) return Future.value(cached.liveUsd);
    }
    return _inFlight[venue] ??= _read(venue).whenComplete(() {
      _inFlight.remove(venue);
    });
  }

  Future<double?> _read(OneBalanceVenue venue) async {
    double? live;
    try {
      final limits = await _fetch(sweepRouteOf(venue));
      live = _minimumFrom(limits);
    } catch (_) {
      live = null;
    }
    _cache[venue] = _CachedMinimum(liveUsd: live, readAt: _clock());
    return live;
  }

  static double? _minimumFrom(OrchestraRouteLimits? limits) {
    if (limits == null) return null;
    final candidates = <int?>[
      limits.orderMinUsdCents,
      limits.exactInMinUsdCents,
    ].whereType<int>().where((c) => c > 0);
    if (candidates.isEmpty) return null;
    return candidates.reduce((a, b) => a > b ? a : b) / 100;
  }
}

/// The app-wide minimums. Not autoDispose: the cache is the point.
final routeMinimumsProvider = Provider<RouteMinimums>((ref) => RouteMinimums());
