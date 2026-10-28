// lib/services/orchestra/receive_route_availability.dart
//
// Which (source chain, source asset, destination) pairs the standing
// deposit-address rail has REFUSED at runtime, so the Receive pickers stop
// listing them.
//
// The swap catalog (GET /v2/orchestration/routes) says what Orchestra can
// convert, and the standing destination list says where a standing address
// can deliver; neither says which source pairs the provider has configured
// for each destination. So beyond the hand-kept
// `kOrchestraAccumulationDeniedPairs`, the app learns the rest the only way
// it can: a standing registration that answers 4xx / `unsupported_route` /
// "Unsupported source", or that has no address on the source chain, marks
// the pair here, and every offering surface consults this set through
// `orchestraCanAccumulatePair`.
//
// HyperCore is refused outright, never learned: Flashnet says "HyperCore
// source address creation is unavailable until independent deposit
// verification is supported". No flow in the app ever requested one
// (HyperCore is the Investing venue's own rail and never reaches a Receive
// picker), and `isHyperCoreSource` keeps it that way at every choke point.

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_ce/hive.dart';
import 'package:kute/services/api/orchestra_api.dart'
    show StandingRequestException;
import 'package:kute/services/runtime_capabilities_service.dart'
    show CapabilityUnavailableException;

/// Which reusable-address model served (or refused) a receive: always
/// `standing` (PUT /v1/standing-deposit-addresses/{ref}). The legacy
/// accumulation model is never asked for any more. Analytics carry `name`
/// as `model`.
enum DepositAddressModel { standing }

/// The provider will not serve a reusable deposit address for this pair.
///
/// Thrown by the receive flows once the rails have been asked and refused
/// (or the pair is already known to be refused), AFTER the pair was
/// recorded in [ReceiveRouteAvailability], so the picker that follows no
/// longer offers it. [toString] is the fixed analytics category so
/// `TrackingService.errorCategory` passes it through unchanged; no
/// address, id or provider text is carried.
class ReceiveRouteUnavailableException implements Exception {
  const ReceiveRouteUnavailableException({
    required this.sourceChain,
    required this.sourceAsset,
    required this.destinationAsset,
    required this.model,
    this.category = 'unsupported_source',
  });

  final String sourceChain, sourceAsset, destinationAsset;

  /// The model that refused.
  final DepositAddressModel model;

  /// `unsupported_source` when the provider named the source as
  /// unconfigured, `no_route` when the pair is simply not offered.
  final String category;

  @override
  String toString() => category;
}

abstract final class ReceiveRouteAvailability {
  static const boxName = 'receive_route_availability_v1';

  /// A refusal is remembered this long. The provider's configuration
  /// changes by support request, not by the hour, and a pair that comes
  /// back is re-offered after this without a release.
  static const Duration ttl = Duration(hours: 24);

  static final Map<String, DateTime> _refused = {};
  static bool _loaded = false;

  static String _key(String chain, String asset, String destinationAsset) =>
      '${chain.trim().toLowerCase()}:${asset.trim().toUpperCase()}:'
      '${destinationAsset.trim().toUpperCase()}';

  /// Whether [chain] is HyperCore, the one source the app must never ask
  /// a deposit address for.
  static bool isHyperCoreSource(String chain) {
    final slug = chain.trim().toLowerCase();
    return slug == 'hypercore' || slug == 'hyperliquid';
  }

  /// Whether the rails have refused this pair within [ttl]. HyperCore is
  /// always unavailable.
  static bool isUnavailable({
    required String sourceChain,
    required String sourceAsset,
    required String destinationAsset,
    DateTime? now,
  }) {
    if (isHyperCoreSource(sourceChain)) return true;
    final at = _refused[_key(sourceChain, sourceAsset, destinationAsset)];
    if (at == null) return false;
    final age = (now ?? DateTime.now()).difference(at);
    return age >= Duration.zero && age < ttl;
  }

  /// Records a refusal. Persisted best-effort so the next launch does not
  /// re-offer a pair the provider refused an hour ago.
  static Future<void> markUnavailable({
    required String sourceChain,
    required String sourceAsset,
    required String destinationAsset,
    DateTime? now,
  }) async {
    final key = _key(sourceChain, sourceAsset, destinationAsset);
    _refused[key] = now ?? DateTime.now();
    try {
      final box = await _box();
      await box?.put(key, jsonEncode(_refused[key]!.millisecondsSinceEpoch));
    } catch (_) {
      // Memory still holds it for this session.
    }
  }

  /// Loads persisted refusals (once). Safe to call before Hive is ready:
  /// a failed load keeps whatever memory holds.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final box = await _box();
      if (box == null) return;
      final now = DateTime.now();
      for (final key in box.keys.whereType<String>().toList()) {
        final raw = box.get(key);
        final ms = raw == null ? null : jsonDecode(raw);
        if (ms is! int) continue;
        final at = DateTime.fromMillisecondsSinceEpoch(ms);
        if (now.difference(at) >= ttl) {
          await box.delete(key);
          continue;
        }
        _refused.putIfAbsent(key, () => at);
      }
    } catch (_) {
      // Persistence is best-effort.
    }
  }

  static Future<Box<String>?> _box() async {
    try {
      return Hive.isBoxOpen(boxName)
          ? Hive.box<String>(boxName)
          : await Hive.openBox<String>(boxName);
    } catch (_) {
      return null;
    }
  }

  /// Forgets every refusal (memory and disk). Tests, and wallet wipe.
  static Future<void> clear() async {
    _refused.clear();
    _loaded = false;
    try {
      final box = await _box();
      await box?.clear();
    } catch (_) {}
  }

  @visibleForTesting
  static Set<String> get refusedKeys => _refused.keys.toSet();

  /// HTTP statuses that mean the request itself was refused for this
  /// route, as opposed to a session, a fee-terms conflict, a rate limit
  /// or an outage that a retry can clear.
  static const Set<int> _refusingStatuses = {400, 403, 404, 422};

  /// The category a refusal reports, or null when [error] is not a route
  /// refusal: `unsupported_source` when the provider named the source as
  /// unconfigured ("Unsupported deposit source: tron:TRX", "Unsupported
  /// source chain: bitcoin", `unsupported_route`), `no_route` for a
  /// catalogue miss or any other 4xx the rails answer for the route.
  ///
  /// A policy denial (the operator's switch) is never a route refusal:
  /// it carries its own sentence and lifts without the provider changing
  /// anything.
  static String? refusalCategory(Object? error,
      {int? statusCode, String? errorCode}) {
    if (error == null && statusCode == null && errorCode == null) return null;
    if (error is CapabilityUnavailableException) return null;
    if (error is ReceiveRouteUnavailableException) return error.category;
    final code = (errorCode ?? '').toLowerCase();
    if (code == 'unsupported_route' || code == 'unsupported_source') {
      return 'unsupported_source';
    }
    final text = (error?.toString() ?? '').toLowerCase();
    if (text.contains('unsupported deposit source') ||
        text.contains('unsupported source') ||
        text.contains('unsupported route') ||
        text.contains('unsupported_route')) {
      return 'unsupported_source';
    }
    if (text.contains('no longer available')) return 'no_route';
    final status =
        error is StandingRequestException ? error.status : statusCode;
    if (status != null && _refusingStatuses.contains(status)) return 'no_route';
    return null;
  }
}
