// A Hyperliquid move rail for tests: records what it was asked and answers
// from fields. Deposits succeed unless [depositError] is set; withdraws
// always report RouteUnavailable, as the legacy rail does.

import 'dart:async';

import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStepUpHook;
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/venue_funder.dart';

/// A rail that records what it was asked and answers from fields.
class FakeHyperliquidMoveRail implements HyperliquidMoveRail {
  final deposits = <({double usd, BigInt units, String purpose})>[];
  SettlementStepUpHook? lastStepUp;
  int gasFloatCalls = 0;
  Object? depositError;
  Object? estimateError;
  double withdrawable = 0;
  VenueMoveQuote quote = const VenueMoveQuote(
      arrivingUsd: 0, feeUsd: 0, fixedCostUsd: 0, minUsd: 1, maxUsd: 1000);
  final creditedController = StreamController<void>.broadcast();

  @override
  Future<VenueMoveResult> depositDollars({
    required double usd,
    required BigInt amountBaseUnits,
    SettlementStepUpHook? stepUp,
    String purpose = 'order_funding',
  }) async {
    lastStepUp = stepUp;
    final error = depositError;
    if (error != null) throw error;
    deposits.add((usd: usd, units: amountBaseUnits, purpose: purpose));
    return VenueMoveResult(
        quoteId: 'q1', sentUsd: usd, arrivingUsdEstimate: usd * 0.999);
  }

  @override
  Future<VenueMoveResult> withdrawToDollars({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'sweep',
  }) async =>
      throw const RouteUnavailable('fake rail has no withdraw');

  @override
  Future<double> withdrawableUsd() async => withdrawable;

  @override
  Future<VenueMoveQuote> estimate(
      {required double usd, required bool deposit}) async {
    final error = estimateError;
    if (error != null) throw error;
    return quote;
  }

  @override
  Future<double> minimumUsd({required bool deposit}) async => quote.minUsd;

  @override
  Future<void> ensureGasFloat() async {
    gasFloatCalls++;
  }

  @override
  Stream<void> get credited => creditedController.stream;
}

