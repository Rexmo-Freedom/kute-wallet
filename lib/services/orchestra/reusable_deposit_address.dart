// lib/services/orchestra/reusable_deposit_address.dart
//
// The one door both receive screens (bitcoin and dollars) go through for a
// reusable deposit address, so the rail choice, the refusal handling and
// the availability memory cannot drift between them.
//
// STANDING FIRST. Flashnet's current model is the standing deposit address
// (PUT /v1/standing-deposit-addresses/{ref}); the accumulation address is
// its legacy model ("new integrations use standing deposit addresses").
// Every receive therefore asks the standing rail first and reaches the
// legacy rail only where the provider offers no standing address:
//
//   * the destination is not a standing destination — spark:BTC was absent
//     from GET /v1/standing-deposit-addresses/destinations on 2026-09-25
//     and the bitcoin receive is still served by the legacy rail for that
//     reason alone; the day the provider lists it, the bitcoin receive
//     moves over with no release;
//   * the source chain is outside the standing rail's funding sources
//     (`StandingDepositStore.supportsSource`), or the instruction answered
//     with no address on that chain;
//   * the standing registration itself was refused for the route (4xx).
//
// A transient standing failure (session, fee-terms conflict, rate limit,
// outage, network) is NOT a reason to mint a legacy address: the next visit
// would show a different address, breaking "one address per coin and
// network", so it surfaces as the retryable error it is.

import 'package:kute/services/accumulation_address_cache.dart';
import 'package:kute/services/api/orchestra_api.dart'
    show StandingRequestException;
import 'package:kute/services/orchestra/receive_route_availability.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/orchestra_routes.dart' show orchestraAssetCodeFor;

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

  /// `standingAddressId` or the legacy `accumulationAddressId`.
  final String id;
  final int? kuteFeeBps;
  final DepositAddressModel model;

  /// The standing record, when [model] is standing.
  final StandingDepositRecord? standing;
}

abstract final class ReusableDepositAddressService {
  /// Resolves the reusable address for [sourceChain]/[sourceAsset] into
  /// [destinationAsset] (BTC or USDB) on the person's own Spark
  /// [recipient], standing first and legacy second.
  ///
  /// [onAttempt] is told which model is being asked before each request,
  /// so a failure event can name it. Throws
  /// [ReceiveRouteUnavailableException] once both rails have refused the
  /// route (the pair is recorded as unavailable first, so the picker that
  /// follows no longer offers it), and rethrows anything else.
  static Future<ReusableDepositAddress> resolve({
    required String walletId,
    required String recipient,
    required String destinationAsset,
    required String sourceChain,
    required String sourceAsset,
    required bool Function() wanted,
    void Function(DepositAddressModel model)? onAttempt,
  }) async {
    Never refuse(DepositAddressModel model, String category) =>
        throw ReceiveRouteUnavailableException(
            sourceChain: sourceChain,
            sourceAsset: sourceAsset,
            destinationAsset: destinationAsset,
            model: model,
            category: category);

    if (ReceiveRouteAvailability.isUnavailable(
        sourceChain: sourceChain,
        sourceAsset: sourceAsset,
        destinationAsset: destinationAsset)) {
      refuse(DepositAddressModel.standing, 'no_route');
    }

    onAttempt?.call(DepositAddressModel.standing);
    try {
      final standing = await StandingDepositStore.register(
          walletId: walletId,
          recipient: recipient,
          destinationAsset: destinationAsset,
          sourceChain: sourceChain,
          sourceAsset: sourceAsset,
          wanted: wanted);
      if (standing != null) {
        return ReusableDepositAddress(
            address: standing.addressFor(sourceChain)!,
            id: standing.response['standingAddressId'] as String,
            kuteFeeBps: standing.kuteFeeBps,
            model: DepositAddressModel.standing,
            standing: standing);
      }
    } on StandingRequestException catch (e) {
      // A refused route falls through to the legacy rail; anything else
      // is retryable and must not mint a second address.
      if (ReceiveRouteAvailability.refusalCategory(e) == null) rethrow;
    }
    if (!wanted()) throw StateError('Wallet changed');

    onAttempt?.call(DepositAddressModel.accumulation);
    final result = await AccumulationAddressCache.getOrCreate(
        sourceChain: sourceChain,
        sourceAsset: orchestraAssetCodeFor(sourceAsset),
        destinationAsset: destinationAsset,
        recipientSparkAddress: recipient);
    final minted = result.data;
    final address = minted?.depositAddress ?? '';
    if (minted == null || address.isEmpty) {
      final category = ReceiveRouteAvailability.refusalCategoryOf(result);
      if (category != null) {
        await ReceiveRouteAvailability.markUnavailable(
            sourceChain: sourceChain,
            sourceAsset: sourceAsset,
            destinationAsset: destinationAsset);
        refuse(DepositAddressModel.accumulation, category);
      }
      throw result.error ?? 'Failed to create deposit address';
    }
    return ReusableDepositAddress(
        address: address,
        id: minted.id,
        kuteFeeBps: minted.kuteFeeBps,
        model: DepositAddressModel.accumulation);
  }
}
