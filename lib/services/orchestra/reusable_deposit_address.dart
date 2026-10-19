// lib/services/orchestra/reusable_deposit_address.dart
//
// The one door every receive goes through for a reusable deposit address,
// so the destination, the refusal handling and the availability memory
// cannot drift. Another coin always arrives in the dollar balance: the
// Dollars receive and the Bitcoin receive's "other coins" (which opens the
// very same Dollars sheet) both ask for it.
//
// STANDING ONLY. Flashnet's current model is the standing deposit address
// (PUT /v1/standing-deposit-addresses/{ref}) to `spark:USDB`, paid to the
// wallet's own Spark address. The legacy accumulation address is never
// created, reused or shown: no deposit to one ever completed, and the
// provider calls it legacy. The addresses already handed out stay watched
// silently by background sync (AccumulationAddressCache.sweepTargets) so a
// late deposit still gets its Activity row.
//
// Where the standing rail has no address for a pair (the destination is
// not listed, the source chain is outside its funding sources, the
// instruction answered with no address on that chain, or the registration
// was refused for the route), the pair is recorded as unavailable, which
// takes it off the pickers, and the receive is refused with the existing
// unavailable copy.
//
// A transient standing failure (session, fee-terms conflict, rate limit,
// outage, network) is not a refusal (a policy revision race and a 5xx are
// retried once inside `StandingDepositStore.register` first): it surfaces
// as the retryable error it is, and the pair stays offered.
//
// Every address shown arms `ReceiveAddressWatch`, so its deposits are read
// on every screen for a while (background_sync_service.dart).

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/services/api/orchestra_api.dart'
    show StandingRequestException;
import 'package:kute/services/orchestra/receive_route_availability.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/orchestra/standing_deposit_sweep.dart'
    show ReceiveAddressWatch;

export 'package:kute/services/orchestra/receive_route_availability.dart'
    show DepositAddressModel, ReceiveRouteUnavailableException;

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
/// [StandingDepositStore.destinations]. The receive pickers list a coin
/// only when its receive's own destination is here; while it loads, or if
/// it cannot be read, nothing is listed.
final standingDestinationsProvider = FutureProvider.autoDispose<Set<String>>(
    (ref) async =>
        await StandingDepositStore.destinations(() => true) ??
        const <String>{});

/// Whether a reusable deposit row from [sourceChain]/[sourceAsset] into
/// [destinationAsset] can get a standing address: its destination is
/// listed in [destinations], the standing rail takes the source, and the
/// pair has not been refused.
bool standingReceiveOffered({
  required Set<String> destinations,
  required String sourceChain,
  required String sourceAsset,
  required String destinationAsset,
}) =>
    destinations.contains('spark:$destinationAsset') &&
    StandingDepositStore.supportsSource(sourceChain, sourceAsset) &&
    !ReceiveRouteAvailability.isUnavailable(
        sourceChain: sourceChain,
        sourceAsset: sourceAsset,
        destinationAsset: destinationAsset);

abstract final class ReusableDepositAddressService {
  /// Test seam: answers [resolve] in place of the standing rail.
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
  /// event can name it. Throws [ReceiveRouteUnavailableException] when
  /// the standing rail has no address for the route (the pair is
  /// recorded as unavailable first, so the picker that follows no longer
  /// lists it), and rethrows anything else.
  static Future<ReusableDepositAddress> resolve({
    required String walletId,
    required String recipient,
    required String destinationAsset,
    required String sourceChain,
    required String sourceAsset,
    required bool Function() wanted,
    void Function(DepositAddressModel model)? onAttempt,
  }) async {
    final debug = debugResolver;
    if (debug != null) {
      return debug(
          sourceChain: sourceChain,
          sourceAsset: sourceAsset,
          destinationAsset: destinationAsset);
    }
    Future<Never> refuse(String category, {bool remember = true}) async {
      if (remember) {
        await ReceiveRouteAvailability.markUnavailable(
            sourceChain: sourceChain,
            sourceAsset: sourceAsset,
            destinationAsset: destinationAsset);
      }
      throw ReceiveRouteUnavailableException(
          sourceChain: sourceChain,
          sourceAsset: sourceAsset,
          destinationAsset: destinationAsset,
          model: DepositAddressModel.standing,
          category: category);
    }

    if (ReceiveRouteAvailability.isUnavailable(
        sourceChain: sourceChain,
        sourceAsset: sourceAsset,
        destinationAsset: destinationAsset)) {
      return refuse('no_route', remember: false);
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
      // A refused route is unavailable; anything else is retryable.
      final category = ReceiveRouteAvailability.refusalCategory(e);
      if (category == null) rethrow;
      if (!wanted()) throw StateError('Wallet changed');
      return refuse(category);
    }
    if (!wanted()) throw StateError('Wallet changed');
    if (standing == null) return refuse('no_route');
    ReceiveAddressWatch.shown();
    return ReusableDepositAddress(
        address: standing.addressFor(sourceChain)!,
        id: standing.response['standingAddressId'] as String,
        kuteFeeBps: standing.kuteFeeBps,
        model: DepositAddressModel.standing,
        standing: standing);
  }
}
