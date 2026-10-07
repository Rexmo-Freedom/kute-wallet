// lib/models/orchestra_route_limits.dart
//
// Live route limits from GET /v1/orchestration/limits and the typed
// amount errors a quote can return (Phase 5 plan B3). Limits are
// presentation only: the sheet shows them and disables its CTA outside
// them, and the quote stays the enforcement.

import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;

final RegExp _digits = RegExp(r'^\d+$');

BigInt? _readBaseUnits(Object? raw) {
  if (raw is int) return raw < 0 ? null : BigInt.from(raw);
  if (raw is String) {
    final s = raw.trim();
    return _digits.hasMatch(s) ? BigInt.parse(s) : null;
  }
  return null;
}

int? _readCents(Object? raw) {
  final value = _readBaseUnits(raw);
  if (value == null || value.bitLength > 62) return null;
  return value.toInt();
}

bool _sameLabel(Object? a, String b) =>
    a is String && a.trim().toLowerCase() == b.trim().toLowerCase();

/// Where an amount sits against the live limits.
enum RouteAmountCheck { withinLimits, belowMinimum, aboveMaximum, unknown }

class OrchestraRouteLimits {
  const OrchestraRouteLimits({
    this.orderMinUsdCents,
    this.orderMaxUsdCents,
    this.exactInSupported,
    this.exactInMinBaseUnits,
    this.exactInMaxBaseUnits,
    this.exactInMinUsdCents,
    this.exactInMaxUsdCents,
    this.exactOutSupported,
  });

  /// `limits.orderNotionalUsd` bounds, in USD cents.
  final int? orderMinUsdCents;
  final int? orderMaxUsdCents;

  final bool? exactInSupported;

  /// `limits.exactIn.requestAmount` bounds in the source asset's smallest
  /// unit. Null when the row's request leg is not the route's source.
  final BigInt? exactInMinBaseUnits;
  final BigInt? exactInMaxBaseUnits;
  final int? exactInMinUsdCents;
  final int? exactInMaxUsdCents;
  final bool? exactOutSupported;

  bool get hasBaseUnitBounds =>
      exactInMinBaseUnits != null || exactInMaxBaseUnits != null;

  /// Checks an exact-in [amountBaseUnits] against the smallest-unit bounds.
  RouteAmountCheck checkBaseUnits(BigInt amountBaseUnits) {
    if (!hasBaseUnitBounds) return RouteAmountCheck.unknown;
    final min = exactInMinBaseUnits;
    final max = exactInMaxBaseUnits;
    if (min != null && amountBaseUnits < min) {
      return RouteAmountCheck.belowMinimum;
    }
    if (max != null && amountBaseUnits > max) {
      return RouteAmountCheck.aboveMaximum;
    }
    return RouteAmountCheck.withinLimits;
  }

  /// Parses one route row's `limits` object for [key]. Null when the row
  /// carries nothing usable.
  static OrchestraRouteLimits? fromLimitsJson(Object? json, RouteKey key) {
    if (json is! Map) return null;
    int? orderMin;
    int? orderMax;
    final notional = json['orderNotionalUsd'];
    if (notional is Map) {
      orderMin = _readCents(notional['minCents']);
      orderMax = _readCents(notional['maxCents']);
      if (orderMin != null && orderMax != null && orderMin > orderMax) {
        orderMin = null;
        orderMax = null;
      }
    }

    bool? exactInSupported;
    BigInt? minUnits;
    BigInt? maxUnits;
    int? minUsd;
    int? maxUsd;
    final exactIn = json['exactIn'];
    if (exactIn is Map) {
      final supported = exactIn['supported'];
      if (supported is bool) exactInSupported = supported;
      final request = exactIn['requestAmount'];
      if (request is Map) {
        // The bounds scale by the leg's decimals. A leg naming another
        // chain or asset than the route's source is not used.
        final chain = request['chain'];
        final asset = request['asset'];
        final legMatches =
            (chain == null || _sameLabel(chain, key.fromChain)) &&
                (asset == null || _sameLabel(asset, key.fromAsset));
        if (legMatches) {
          minUnits = _readBaseUnits(request['minAmountSmallest']);
          maxUnits = _readBaseUnits(request['maxAmountSmallest']);
          if (minUnits != null && maxUnits != null && minUnits > maxUnits) {
            minUnits = null;
            maxUnits = null;
          }
        }
        minUsd = _readCents(request['minUsdCents']);
        maxUsd = _readCents(request['maxUsdCents']);
        if (minUsd != null && maxUsd != null && minUsd > maxUsd) {
          minUsd = null;
          maxUsd = null;
        }
      }
    }

    bool? exactOutSupported;
    final exactOut = json['exactOut'];
    if (exactOut is Map && exactOut['supported'] is bool) {
      exactOutSupported = exactOut['supported'] as bool;
    }

    final limits = OrchestraRouteLimits(
      orderMinUsdCents: orderMin,
      orderMaxUsdCents: orderMax,
      exactInSupported: exactInSupported,
      exactInMinBaseUnits: minUnits,
      exactInMaxBaseUnits: maxUnits,
      exactInMinUsdCents: minUsd,
      exactInMaxUsdCents: maxUsd,
      exactOutSupported: exactOutSupported,
    );
    final empty = orderMin == null &&
        orderMax == null &&
        exactInSupported == null &&
        minUnits == null &&
        maxUnits == null &&
        minUsd == null &&
        maxUsd == null &&
        exactOutSupported == null;
    return empty ? null : limits;
  }

  /// Parses a `/limits` response for [key]: the documented `routes` list
  /// (matched on the exact directed pair), or a single top-level `limits`
  /// object. Null when no row matches.
  static OrchestraRouteLimits? fromResponse(Object? json, RouteKey key) {
    if (json is! Map) return null;
    final routes = json['routes'];
    if (routes is List) {
      for (final row in routes) {
        if (row is! Map) continue;
        if (_sameLabel(row['sourceChain'], key.fromChain) &&
            _sameLabel(row['sourceAsset'], key.fromAsset) &&
            _sameLabel(row['destinationChain'], key.toChain) &&
            _sameLabel(row['destinationAsset'], key.toAsset)) {
          return fromLimitsJson(row['limits'], key);
        }
      }
      return null;
    }
    return fromLimitsJson(json['limits'], key);
  }
}

/// Flashnet's amount and availability errors from `/quote` and
/// `/estimate`.
enum RouteQuoteErrorCode {
  amountTooSmall('amount_too_small'),
  amountTooLarge('amount_too_large'),
  amountExceedsLiquidity('amount_exceeds_liquidity'),
  routeUnavailable('route_unavailable');

  const RouteQuoteErrorCode(this.code);

  /// Flashnet's code and the analytics value.
  final String code;

  static RouteQuoteErrorCode? fromCode(String? code) {
    final c = code?.trim().toLowerCase();
    for (final value in values) {
      if (value.code == c) return value;
    }
    return null;
  }
}

/// Reads a [RouteQuoteErrorCode] from an error response body. Accepts
/// `{"error": {"code": ...}}`, `{"error": "<code>"}`, `{"code": ...}` and
/// `{"errorCode": ...}`, then a message that names exactly one code.
RouteQuoteErrorCode? parseRouteQuoteErrorCode(Object? json) {
  if (json is! Map) return null;
  final error = json['error'];
  final candidates = <Object?>[
    if (error is Map) error['code'],
    if (error is String) error,
    json['code'],
    json['errorCode'],
  ];
  for (final c in candidates) {
    if (c is String) {
      final parsed = RouteQuoteErrorCode.fromCode(c);
      if (parsed != null) return parsed;
    }
  }
  final messages = <Object?>[
    if (error is Map) error['message'],
    json['message'],
  ];
  for (final m in messages) {
    if (m is! String) continue;
    final found = RouteQuoteErrorCode.values
        .where((v) => RegExp('\\b${v.code}\\b').hasMatch(m.toLowerCase()))
        .toList();
    if (found.length == 1) return found.single;
  }
  return null;
}

/// A quote refused for amount or availability. [minimum] and [maximum]
/// are locally formatted display strings and never enter events.
class RouteQuoteError implements Exception {
  const RouteQuoteError(this.code);

  final RouteQuoteErrorCode code;

  String messageFor(
    AppLocalizations l10n, {
    String? minimum,
    String? maximum,
  }) {
    switch (code) {
      case RouteQuoteErrorCode.amountTooSmall:
        return minimum == null
            ? l10n.routeAmountTooSmallGeneric
            : l10n.routeAmountTooSmall(minimum);
      case RouteQuoteErrorCode.amountTooLarge:
        return maximum == null
            ? l10n.routeAmountTooLargeGeneric
            : l10n.routeAmountTooLarge(maximum);
      case RouteQuoteErrorCode.amountExceedsLiquidity:
        return l10n.routeAmountLiquidity;
      case RouteQuoteErrorCode.routeUnavailable:
        return l10n.routeUnavailableNothingSent;
    }
  }

  @override
  String toString() => 'RouteQuoteError(${code.code})';
}
