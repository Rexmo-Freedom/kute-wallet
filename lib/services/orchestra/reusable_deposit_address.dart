// lib/services/orchestra/reusable_deposit_address.dart
//
// The one door every receive goes through for a reusable deposit address,
// so the destination, the refusal handling and the availability memory
// cannot drift.
//
// Founder, 2026-10-19: another coin is received through a REUSABLE
// (standing) address first, and through a one-time quoted address only
// when the standing route cannot serve it.
//
//   * Dollars receive: a standing address to `spark:USDB`, shown with no
//     Kute fee line (the fee is charged, never shown under an address).
//   * Bitcoin receive, "other coins": the very same `spark:USDB` address
//     (the money lands in Investments, said in a note), remembered so its
//     deposits also show in the Bitcoin Activity (BitcoinReceiveMarks).
//   * Fallback: the one-time flow (onetime_receive.dart) into the
//     receive's own destination (`spark:USDB` / `spark:BTC`).
//
// "Cannot serve" ([StandingFallbackReason]):
//   * `standing_unserved`: the coin and network are not on the standing
//     rail (a source it does not fund, a refused pair, or `spark:USDB`
//     missing from the provider's standing destinations);
//   * `standing_refused`: the backend refused the registration (422
//     `unsupported_route`, what it answers while its switch
//     `orchestra.standing_addresses` is off, or any other route refusal).
//     Remembered for the session ([StandingReceiveRefusal]) so every coin
//     tap does not ask again; forgotten when a new policy revision lands;
//   * `standing_policy_off`: the published policy denies
//     `orchestra.standing_addresses` (or the standing route's own gates):
//     no registration is made at all. An id the policy does not carry (a
//     backend older than the switch) is NOT a denial: the registration is
//     tried and the backend's own refusal decides ([standingAddressPolicy]);
//   * `no_source_address`: the provider's instruction has no address on
//     the source chain (that pair is remembered as unavailable).
//
// STANDING ONLY. The legacy accumulation address
// (POST /orchestra/accumulation-addresses) is never created, reused or
// shown. The addresses already handed out stay watched silently by
// background sync (AccumulationAddressCache.sweepTargets) so a late
// deposit still gets its Activity row.
//
// A transient standing failure (session, fee-terms conflict, rate limit,
// outage, network) is not a refusal (a policy revision race and a 5xx are
// retried once inside `StandingDepositStore.register` first): it surfaces
// as the retryable error it is, and nothing falls back.
//
// Every address shown arms `ReceiveAddressWatch`, so its deposits are read
// on every screen for a while (background_sync_service.dart).

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/api/orchestra_api.dart'
    show StandingRequestException;
import 'package:kute/services/orchestra/onetime_receive.dart'
    show oneTimeReceiveOptions;
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
import 'package:kute/services/orchestra/receive_route_availability.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/orchestra/standing_deposit_sweep.dart'
    show ReceiveAddressWatch;
import 'package:kute/services/orchestra_routes.dart'
    show
        isVenueInternalRoute,
        kOrchestraUsdAssetCode,
        orchestraCanAccumulatePair;
import 'package:kute/services/runtime_capabilities_service.dart';

export 'package:kute/services/orchestra/receive_route_availability.dart'
    show DepositAddressModel, ReceiveRouteUnavailableException;

/// Why a receive used a one-time address instead of the standing one.
/// Analytics carry [analytics] as `fallback_reason`.
enum StandingFallbackReason {
  standingUnserved('standing_unserved'),
  standingRefused('standing_refused'),
  standingPolicyOff('standing_policy_off'),
  noSourceAddress('no_source_address');

  const StandingFallbackReason(this.analytics);

  final String analytics;
}

/// The standing rail will not serve this coin and network ([reason]):
/// the receive falls back to a one-time address when one can serve it,
/// and says the coin is unavailable otherwise.
class StandingUnavailableException extends ReceiveRouteUnavailableException {
  const StandingUnavailableException({
    required super.sourceChain,
    required super.sourceAsset,
    required this.reason,
    super.category = 'no_route',
  }) : super(
            destinationAsset: kOrchestraUsdAssetCode,
            model: DepositAddressModel.standing);

  final StandingFallbackReason reason;
}

/// What the published policy says of [kStandingAddressCapability].
enum StandingPolicy { allowed, denied, unknown }

/// The decision on [kStandingAddressCapability], read so that an id the
/// published policy does not carry (a backend older than the switch) is
/// [StandingPolicy.unknown], never a denial: a fresh session policy
/// answers such an id `unknown_capability`, and with none fresh the public
/// policy's silence falls through to the offline table
/// (`policy_unavailable`). Unknown tries the registration; the backend's
/// own refusal (422) then decides. Only an explicit denial (the operator
/// switched it off, a version or region rule) skips straight to one-time.
StandingPolicy standingAddressPolicy(RuntimeCapabilitiesService policy) {
  final decision = policy.decision(kStandingAddressCapability);
  if (decision.allowed && !decision.comingSoon) return StandingPolicy.allowed;
  if (!decision.comingSoon &&
      (decision.reason == 'unknown_capability' ||
          decision.reason == 'policy_unavailable')) {
    return StandingPolicy.unknown;
  }
  return StandingPolicy.denied;
}

/// The backend's refusal of a standing registration, remembered so the
/// next coin tap goes straight to one-time instead of asking again. It
/// holds for [ttl] and only while the policy revision is the one it was
/// refused under: a new policy (the operator switching standing back on
/// publishes one) forgets it. Memory only.
abstract final class StandingReceiveRefusal {
  static const Duration ttl = Duration(minutes: 15);

  static DateTime? _at;
  static int? _revision;

  static int? _policyRevision(RuntimeCapabilitiesService policy) =>
      policy.snapshot?.revision ?? policy.publicSnapshot?.revision;

  static void remember(RuntimeCapabilitiesService policy, {DateTime? now}) {
    _at = now ?? DateTime.now();
    _revision = _policyRevision(policy);
  }

  /// Whether a refusal is remembered under [policy]'s current revision.
  static bool active(RuntimeCapabilitiesService policy, {DateTime? now}) {
    final at = _at;
    if (at == null) return false;
    final age = (now ?? DateTime.now()).difference(at);
    if (age < Duration.zero ||
        age >= ttl ||
        _policyRevision(policy) != _revision) {
      clear();
      return false;
    }
    return true;
  }

  static void clear() {
    _at = null;
    _revision = null;
  }
}

/// A reusable deposit address the screen may show, and which model it
/// came from.
class ReusableDepositAddress {
  const ReusableDepositAddress({
    required this.address,
    required this.id,
    required this.kuteFeeBps,
    required this.model,
    this.standing,
  });

  final String address;

  /// The instruction's `standingAddressId`.
  final String id;
  final int? kuteFeeBps;
  final DepositAddressModel model;

  /// The standing record (null only from the test seam).
  final StandingDepositRecord? standing;
}

/// The provider's standing destination pairs ('chain:ASSET'), memoised by
/// [StandingDepositStore.destinations]. Null while unknown (not read yet,
/// unreadable, or not asked because the policy denies standing): the
/// pickers then offer a standing row on the other rules alone, and the
/// registration answers for it.
final standingDestinationsProvider =
    FutureProvider.autoDispose<Set<String>?>((ref) async {
  if (standingAddressPolicy(RuntimeCapabilitiesService.instance) ==
      StandingPolicy.denied) {
    return null;
  }
  try {
    return await StandingDepositStore.destinations(() => true);
  } catch (_) {
    return null;
  }
});

/// Why the standing route will not serve [sourceChain]/[sourceAsset] into
/// the dollar balance, or null when it should be tried: the policy denies
/// it ([standingAddressPolicy], or the standing route's own gates), a
/// refusal is remembered ([StandingReceiveRefusal]), the standing rail
/// does not take the source or the pair, or [destinations] (when known)
/// do not list `spark:USDB`. Asks nothing.
StandingFallbackReason? standingReceiveFallback({
  required String sourceChain,
  required String sourceAsset,
  Set<String>? destinations,
  RuntimeCapabilitiesService? policy,
}) {
  final rules = policy ?? RuntimeCapabilitiesService.instance;
  if (standingAddressPolicy(rules) == StandingPolicy.denied) {
    return StandingFallbackReason.standingPolicyOff;
  }
  for (final gate in orchestraReceiveAddressCapabilities(
      sourceChain: sourceChain,
      sourceAsset: sourceAsset,
      destinationAsset: kOrchestraUsdAssetCode)) {
    if (!rules.allows(gate)) return StandingFallbackReason.standingPolicyOff;
  }
  if (StandingReceiveRefusal.active(rules)) {
    return StandingFallbackReason.standingRefused;
  }
  if (isVenueInternalRoute(sourceChain, sourceAsset) ||
      !StandingDepositStore.supportsSource(sourceChain, sourceAsset) ||
      !orchestraCanAccumulatePair(
          sourceChain, sourceAsset, kOrchestraUsdAssetCode)) {
    return StandingFallbackReason.standingUnserved;
  }
  if (destinations != null &&
      !destinations.contains('spark:$kOrchestraUsdAssetCode')) {
    return StandingFallbackReason.standingUnserved;
  }
  return null;
}

/// Every coin and network the receive of another coin into
/// spark:[destinationAsset] offers: a REUSABLE row (`reusableAddress:
/// true`, a standing address to `spark:USDB`) wherever the standing route
/// may serve it ([standingReceiveFallback] answers null), else a ONE-TIME
/// row (`reusableAddress: false`, [oneTimeReceiveOptions] into
/// [destinationAsset]) while `orchestra.onetime_addresses` allows it. A
/// coin only one-time can serve is listed and goes straight to one-time.
/// Venue rails are never listed. Sorted by coin, then network.
List<OrchestraReceiveOption> receiveOtherCoinOptions(
  OrchestraRoutesCatalog catalog, {
  required String destinationAsset,
  Set<String>? standingDestinations,
  RuntimeCapabilitiesService? policy,
}) {
  final rules = policy ?? RuntimeCapabilitiesService.instance;
  String id(OrchestraReceiveOption o) =>
      '${o.chain}:${o.assetCode.toUpperCase()}';
  final rows = <String, OrchestraReceiveOption>{};
  for (final o in catalog.receiveOptions(
      destinationChain: 'spark', destinationAsset: kOrchestraUsdAssetCode)) {
    if (!o.reusableAddress) continue;
    if (standingReceiveFallback(
            sourceChain: o.chain,
            sourceAsset: o.assetCode,
            destinations: standingDestinations,
            policy: rules) !=
        null) {
      continue;
    }
    rows[id(o)] = o;
  }
  if (oneTimeReceiveAllowed(rules)) {
    for (final o
        in oneTimeReceiveOptions(catalog, destinationAsset: destinationAsset)) {
      rows.putIfAbsent(id(o), () => o);
    }
  }
  return rows.values.toList()
    ..sort((a, b) {
      final bySymbol = a.displaySymbol
          .toLowerCase()
          .compareTo(b.displaySymbol.toLowerCase());
      if (bySymbol != 0) return bySymbol;
      return a.chainDisplayName
          .toLowerCase()
          .compareTo(b.chainDisplayName.toLowerCase());
    });
}

/// The one-time row of [option] into spark:[destinationAsset] when a
/// one-time receive can serve it now (live route, offered network,
/// `orchestra.onetime_addresses` and the row's own gates allowed), or null.
OrchestraReceiveOption? oneTimeFallbackOption(
  OrchestraRoutesCatalog catalog,
  OrchestraReceiveOption option, {
  required String destinationAsset,
  RuntimeCapabilitiesService? policy,
}) {
  final rules = policy ?? RuntimeCapabilitiesService.instance;
  if (!oneTimeReceiveAllowed(rules)) return null;
  for (final o
      in oneTimeReceiveOptions(catalog, destinationAsset: destinationAsset)) {
    if (o.chain != option.chain ||
        o.assetCode.toUpperCase() != option.assetCode.toUpperCase()) {
      continue;
    }
    final offered = orchestraOptionsOfferedUnderPolicy([o], rules,
        otherLegAsset: destinationAsset, depositAddress: true);
    return offered.offered.isEmpty ? null : o;
  }
  return null;
}

abstract final class ReusableDepositAddressService {
  /// Test seam: answers [resolve] in place of the standing rail, after
  /// the checks that ask nothing ([standingReceiveFallback]).
  @visibleForTesting
  static Future<ReusableDepositAddress> Function({
    required String sourceChain,
    required String sourceAsset,
    required String destinationAsset,
  })? debugResolver;

  /// Resolves the standing address for [sourceChain]/[sourceAsset] into
  /// [destinationAsset] (`spark:USDB`) on the wallet's own Spark
  /// [recipient].
  ///
  /// [onAttempt] is told the model before the request, so a failure
  /// event can name it. Throws [StandingUnavailableException] when the
  /// standing route cannot serve the coin (its reason says why; nothing
  /// is registered when the policy denies standing or a refusal is
  /// remembered), and rethrows anything else (a transient failure, or a
  /// [CapabilityUnavailableException] from the route's own gates).
  static Future<ReusableDepositAddress> resolve({
    required String walletId,
    required String recipient,
    required String destinationAsset,
    required String sourceChain,
    required String sourceAsset,
    required bool Function() wanted,
    void Function(DepositAddressModel model)? onAttempt,
    RuntimeCapabilitiesService? policy,
  }) async {
    final rules = policy ?? RuntimeCapabilitiesService.instance;
    Never unavailable(StandingFallbackReason reason,
            {String category = 'no_route'}) =>
        throw StandingUnavailableException(
            sourceChain: sourceChain,
            sourceAsset: sourceAsset,
            reason: reason,
            category: category);

    final early = standingReceiveFallback(
        sourceChain: sourceChain,
        sourceAsset: sourceAsset,
        destinations: StandingDepositStore.cachedDestinations,
        policy: rules);
    if (early != null) unavailable(early);

    final debug = debugResolver;
    if (debug != null) {
      return debug(
          sourceChain: sourceChain,
          sourceAsset: sourceAsset,
          destinationAsset: destinationAsset);
    }

    onAttempt?.call(DepositAddressModel.standing);
    final StandingDepositRecord? standing;
    try {
      standing = await StandingDepositStore.register(
          walletId: walletId,
          recipient: recipient,
          destinationAsset: destinationAsset,
          sourceChain: sourceChain,
          sourceAsset: sourceAsset,
          wanted: wanted);
    } on StandingRequestException catch (e) {
      // A refused route falls back; anything else is retryable.
      final category = ReceiveRouteAvailability.refusalCategory(e);
      if (category == null) rethrow;
      if (!wanted()) throw StateError('Wallet changed');
      // The backend's switch refuses every coin alike: remembered for the
      // session, never per pair on disk, so switching it back on (a new
      // policy revision) restores standing at once.
      StandingReceiveRefusal.remember(rules);
      unavailable(StandingFallbackReason.standingRefused, category: category);
    }
    if (!wanted()) throw StateError('Wallet changed');
    if (standing == null) {
      // Either `spark:USDB` is not a standing destination, or the
      // instruction has no address on this source chain.
      Set<String>? pairs;
      try {
        pairs = await StandingDepositStore.destinations(wanted);
      } catch (_) {
        pairs = null;
      }
      if (!wanted()) throw StateError('Wallet changed');
      if (pairs == null || !pairs.contains('spark:$destinationAsset')) {
        unavailable(StandingFallbackReason.standingUnserved);
      }
      await ReceiveRouteAvailability.markUnavailable(
          sourceChain: sourceChain,
          sourceAsset: sourceAsset,
          destinationAsset: destinationAsset);
      unavailable(StandingFallbackReason.noSourceAddress);
    }
    ReceiveAddressWatch.shown();
    return ReusableDepositAddress(
        address: standing.addressFor(sourceChain)!,
        id: standing.response['standingAddressId'] as String,
        kuteFeeBps: standing.kuteFeeBps,
        model: DepositAddressModel.standing,
        standing: standing);
  }
}
