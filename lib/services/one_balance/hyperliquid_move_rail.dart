// lib/services/one_balance/hyperliquid_move_rail.dart
//
// The rail between Dollars and Investing, as the one-balance layer sees
// it. Investing's `VenueFunder` and the sweeper call this and nothing
// else, so swapping the rail underneath (HyperCore via Orchestra today,
// HyperEVM later) changes one binding line in this file.
//
// P0 bound the interface to `LegacyHyperCoreRail`: a thin wrapper over
// the native HyperCore funding service for deposits, and "not available"
// for everything a later rail has to build (withdraw back to the dollar
// token, live estimates, the gas float). The provider now binds
// `HyperEvmMoveRail` (hyperevm_move_rail.dart), which reads all of that
// live; the legacy wrapper stays as the fallback shape and for its tests.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStepUpHook;
import 'package:kute/services/funding/spark_hypercore_funding_service.dart'
    show SparkFundingAsset, sparkHypercoreFundingServiceProvider;
import 'package:kute/services/one_balance/hyperevm_move_rail.dart'
    show HyperEvmMoveRail;
import 'package:kute/services/one_balance/venue_funder.dart';

/// Smallest move the legacy rail quotes, either direction. A placeholder
/// until the HyperEVM rail reads the real floor from the route.
const double kLegacyHyperCoreMinUsd = 10.0;

/// Largest single move the legacy rail quotes. No real cap is known for
/// the legacy route; the quote guard rejects anything the provider
/// refuses.
const double kLegacyHyperCoreMaxUsd = double.infinity;

abstract interface class HyperliquidMoveRail {
  /// Sends dollars from the spending account into the Investing venue.
  ///
  /// [amountBaseUnits] is the dollar token's six-decimal base units, the
  /// exact figure the send is made with; [usd] is the same money as a
  /// dollar figure for the record. [stepUp] asks the user for the fresh
  /// grant the settlement needs; [purpose] is recorded with the move.
  Future<VenueMoveResult> depositDollars({
    required double usd,
    required BigInt amountBaseUnits,
    SettlementStepUpHook? stepUp,
    String purpose = 'order_funding',
  });

  /// Brings venue cash back to the dollar token.
  Future<VenueMoveResult> withdrawToDollars({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'sweep',
  });

  /// Venue cash that could leave right now.
  Future<double> withdrawableUsd();

  /// What a move of [usd] would cost and deliver in the given direction.
  Future<VenueMoveQuote> estimate({required double usd, required bool deposit});

  /// Smallest move the rail accepts in the given direction.
  Future<double> minimumUsd({required bool deposit});

  /// Makes sure the rail holds enough of its own gas to carry the next
  /// move. A no-op on rails that pay fees out of the moved amount.
  Future<void> ensureGasFloat();

  /// Fires once per move the venue has credited, so the slip waiting on a
  /// deposit can place its order without polling.
  Stream<void> get credited;
}

/// The HyperCore-via-Orchestra rail the app ships today, wrapped.
///
/// Deposits delegate to `SparkHypercoreFundingService.depositFromSpark`
/// with the dollar token as the funding asset and background
/// registration on, so the result's `registration` future is the one the
/// settlement runner hands back. Everything else is what a HyperEVM rail
/// has to add; until then it answers "unavailable" or a constant.
class LegacyHyperCoreRail implements HyperliquidMoveRail {
  LegacyHyperCoreRail(this._read);

  final ProviderReader _read;

  @override
  Future<VenueMoveResult> depositDollars({
    required double usd,
    required BigInt amountBaseUnits,
    SettlementStepUpHook? stepUp,
    String purpose = 'order_funding',
  }) async {
    // The purpose picks the quote's provider tag (an order's funding leg,
    // a sweep); the Activity row the service writes already reads as an
    // Investing deposit.
    final result = await _read(sparkHypercoreFundingServiceProvider)
        .depositFromSpark(
      asset: SparkFundingAsset.dollars,
      amountBaseUnits: amountBaseUnits,
      amountUsd: usd,
      stepUp: stepUp,
      registerInBackground: true,
      purpose: purpose,
    );
    return VenueMoveResult(
      quoteId: result.run.quote.quoteId,
      orderId: result.run.orderId,
      registration: result.run.registration,
      sentUsd: usd,
      arrivingUsdEstimate: result.estimatedOut,
    );
  }

  @override
  Future<VenueMoveResult> withdrawToDollars({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'sweep',
  }) async {
    throw const RouteUnavailable('legacy HyperCore rail has no withdraw');
  }

  @override
  Future<double> withdrawableUsd() async => 0;

  @override
  Future<VenueMoveQuote> estimate(
          {required double usd, required bool deposit}) async =>
      VenueMoveQuote(
        arrivingUsd: usd,
        feeUsd: 0,
        fixedCostUsd: 0,
        minUsd: kLegacyHyperCoreMinUsd,
        maxUsd: kLegacyHyperCoreMaxUsd,
      );

  @override
  Future<double> minimumUsd({required bool deposit}) async =>
      kLegacyHyperCoreMinUsd;

  @override
  Future<void> ensureGasFloat() async {}

  @override
  Stream<void> get credited => const Stream<void>.empty();
}

/// The rail Investing moves ride on: HyperEVM, both directions.
final hyperliquidMoveRailProvider =
    Provider<HyperliquidMoveRail>((ref) => HyperEvmMoveRail(ref.read));
