// lib/screens/hyperliquid/components/hl_execution_target.dart
//
// Execution target for Hyperliquid order actions (Wallet hardening
// Phase 4a, P4.7, O11). A ticket calls the target instead of a notifier:
//
// * [HotHlExecutionTarget] wraps today's hot trading notifier (onboarding,
//   builder fee, nonce retry and tracking stay where they are). Since
//   Phase 1b.3 it asks for the step-up grant itself, bound to the order it
//   is about to place.
// * The Ledger target lives in
//   lib/screens/ledger/hyperliquid/ledger_hl_execution_target.dart and
//   routes every action through the Ledger executor and approval sheet.
//   It never calls `ensureOnboarded` and never falls back to a phone key.
//
// This file is outside the Ledger folders on purpose: the hot adapter
// needs the hot notifier, which the Ledger architecture scan forbids.

import 'package:flutter/widgets.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';

abstract class HlExecutionTarget {
  bool get isLedger;

  /// Places a market order ([marginUsd] times [leverage] notional for
  /// perps, [marginUsd] notional for spot). Returns null when the user
  /// cancelled or the outcome is still pending; throws only for hot
  /// failures, as today.
  Future<HlOrderResult?> placeMarketOrder(
    BuildContext context, {
    required HlMarket market,
    required bool isBuy,
    required double marginUsd,
    int leverage = 1,
    double slippagePct = 1.0,
    String? source,
  });

  /// Cancels one resting order. Returns true when the venue accepted.
  Future<bool> cancelOrder(
    BuildContext context, {
    required HlOpenOrder order,
    int? assetId,
  });
}
