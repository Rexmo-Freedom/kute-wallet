// lib/services/orchestra/receive_minimums.dart
//
// "What is the smallest deposit this receive address takes?" Shown as one
// "Minimum …" line on the one-time receive's amount sheet (and checked
// there), so people stop sending amounts that are held instead of
// converted.
//
//   * An Orchestra deposit address (another coin into Dollars or Bitcoin):
//     the larger of the route's live minimum (`GET /v1/orchestration/limits`
//     for that exact pair, backend proxy first, the public host second) and
//     the app's $1.00 floor, rounded up to whole cents. The floor covers the
//     moving provider minimums the limits read does not show
//     (`dynamicProviderLimits`). A failed read shows the floor; it never
//     blocks the address and never shows $0.
//   * The wallet's own Bitcoin address (the Breez/Spark static deposit
//     address): the deposit has to pay its own claim. The SDK auto-claims
//     only when the claim quote is within `kSparkAutoClaimMaxFeeSats`, and
//     what is left after the fee must not be dust, so the minimum is that
//     ceiling plus Spark's dust allowance. Anything smaller can sit
//     unclaimed (listed for a manual claim or a refund).
//
// Live limits are kept per route for the session and re-read every time
// the address is shown. Nothing here moves money.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/services/api/orchestra_api.dart';

/// The app's floor under every Orchestra deposit route, in USD cents.
const int kReceiveMinimumFloorCents = 100;

/// Where a shown minimum came from, as analytics names it.
enum ReceiveMinimumSource {
  /// A live `/limits` read for the route (shown no lower than the floor).
  live,

  /// No live read: the app's floor.
  floor,
}

/// The minimum one receive address shows.
class ReceiveMinimum {
  const ReceiveMinimum({required this.source, this.usdCents});

  final ReceiveMinimumSource source;

  /// The minimum in USD cents.
  final int? usdCents;


  /// The properties `receive_address_generated` carries: the exact
  /// minimum shown and where it came from.
  Map<String, Object> get trackingParams => {
        if (usdCents != null) 'min_deposit_usd': usdCents! / 100,
        'min_source': source.name,
      };

  /// "$1.00": the dollar minimum as the Dollars receive prints amounts.
  String? get usdText =>
      usdCents == null ? null : '\$${(usdCents! / 100).toStringAsFixed(2)}';

  @override
  bool operator ==(Object other) =>
      other is ReceiveMinimum &&
      other.source == source &&
      other.usdCents == usdCents;

  @override
  int get hashCode => Object.hash(source, usdCents);
}

/// The floor, for a route whose limits could not be read.
const ReceiveMinimum kReceiveMinimumFloor = ReceiveMinimum(
    source: ReceiveMinimumSource.floor, usdCents: kReceiveMinimumFloorCents);

/// The route's own minimum in whole USD cents (the larger of the order
/// notional and exact-in minimums), or null when the read gave none.
int? orchestraLiveMinimumCents(OrchestraRouteLimits? limits) {
  if (limits == null) return null;
  final candidates = <int?>[
    limits.orderMinUsdCents,
    limits.exactInMinUsdCents,
  ].whereType<int>().where((c) => c > 0);
  if (candidates.isEmpty) return null;
  return candidates.reduce((a, b) => a > b ? a : b);
}

/// The Breez on-chain minimum, with its dollar value when [usdPerBtc] is
/// known (rounded up to the cent, so the dollars never undersell it).
typedef ReceiveLimitsFetcher = Future<OrchestraRouteLimits?> Function(
    RouteKey route);

/// Orchestra receive minimums per route, kept for the session.
class ReceiveMinimums {
  ReceiveMinimums({ReceiveLimitsFetcher? fetch})
      : _fetch = fetch ?? ((route) => OrchestraService.getRouteLimits(route));

  final ReceiveLimitsFetcher _fetch;
  final Map<RouteKey, ReceiveMinimum> _live = {};
  final Map<RouteKey, OrchestraRouteLimits> _limits = {};
  final Map<RouteKey, Future<ReceiveMinimum>> _inFlight = {};

  /// The last live minimum read for [route] this session, or null.
  ReceiveMinimum? cachedLive(RouteKey route) => _live[route];

  /// The last limits read for [route] this session, or null: the one-time
  /// receive's maximum and, for a coin that is neither dollars nor
  /// bitcoin, its price (`oneTimeSourceUnits`).
  OrchestraRouteLimits? cachedLimits(RouteKey route) => _limits[route];

  /// Re-reads [route]'s limits (one read at a time per route). Never
  /// throws: a failed read answers the session's last live minimum for
  /// the route, else the floor.
  Future<ReceiveMinimum> refresh(RouteKey route) =>
      _inFlight[route] ??= _read(route).whenComplete(() {
        _inFlight.remove(route);
      });

  Future<ReceiveMinimum> _read(RouteKey route) async {
    int? liveCents;
    try {
      final limits = await _fetch(route);
      if (limits != null) _limits[route] = limits;
      liveCents = orchestraLiveMinimumCents(limits);
    } catch (_) {
      liveCents = null;
    }
    if (liveCents == null) return _live[route] ?? kReceiveMinimumFloor;
    final minimum = ReceiveMinimum(
      source: ReceiveMinimumSource.live,
      usdCents: liveCents > kReceiveMinimumFloorCents
          ? liveCents
          : kReceiveMinimumFloorCents,
    );
    _live[route] = minimum;
    return minimum;
  }
}

/// The app-wide receive minimums. Not autoDispose: the session cache is
/// the point.
final receiveMinimumsProvider =
    Provider<ReceiveMinimums>((ref) => ReceiveMinimums());
