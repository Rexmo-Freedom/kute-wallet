// lib/screens/ledger/ledger_actions.dart
//
// Entry points the Ledger account tabs call (Wallet hardening Phase 4a,
// P4.5 to P4.7). Every Ledger action goes through one of these, so claim
// all, direct buttons and open order rows all route through the Ledger
// executors and the approval sheet, never a hot provider.
//
// Each call takes the Ledger wallet ID explicitly; nothing follows the
// active or spending wallet.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Position;

import 'package:kute/constants/feature_flags.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/screens/hyperliquid/components/hl_execution_target.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/ledger/hyperliquid/ledger_hl_execution_target.dart';
import 'package:kute/screens/ledger/hyperliquid/ledger_transfer_sheet.dart';
import 'package:kute/screens/ledger/polymarket/ledger_claim_sheet.dart';
import 'package:kute/screens/ledger/polymarket/ledger_sell_sheet.dart';
import 'package:kute/screens/ledger/polymarket/ledger_withdraw_sheet.dart';
import 'package:kute/services/hardware/ledger/deposit_wallet_call_allowlist.dart';
import 'package:kute/screens/shared/route_pause_gate.dart';
import 'package:kute/services/release/route_pause_policy.dart';

abstract final class LedgerActions {
  // ── availability (flags stay off until Phase 5 acceptance) ──

  /// Orders, cancels and leverage show a code on the device (O1). While false, their sheets explain instead of submitting.
  static bool get opaqueHyperliquidAvailable =>
      kLedgerHyperliquidOpaqueActionsEnabled;

  /// Remote pause switch for NEW Ledger investing actions (Phase 5 F16).
  /// Pending actions and their status checks never go through here.
  static Future<bool> _investingAllowed(BuildContext context) async =>
      await ensureRouteNotPaused(
          context, PausableRoute.ledgerInvestingActions) &&
      context.mounted;

  /// Polymarket withdrawal (O3). While false, hide the entry entirely.
  static bool get polymarketWithdrawAvailable => LedgerWithdrawSheet.isAvailable;

  // ── Polymarket (Predictions tab) ──

  static Future<void> sellPosition(
    BuildContext context, {
    required String walletId,
    required Position position,
  }) async {
    if (!await _investingAllowed(context)) return;
    if (!context.mounted) return;
    await LedgerSellSheet.show(context, walletId: walletId, position: position);
  }

  /// Claim one or all redeemable positions; one approval per condition.
  static Future<void> claim(
    BuildContext context, {
    required String walletId,
    required List<Position> positions,
  }) async {
    if (!await _investingAllowed(context)) return;
    if (!context.mounted) return;
    await LedgerClaimSheet.show(context,
        walletId: walletId, positions: positions);
  }

  /// Phase 4b supplies the Orchestra quote binding. No-op while O3 is off.
  /// A withdrawal to the Ledger is a new Ledger funding operation, so the
  /// `ledgerFunding` pause switch stops it before the sheet opens (F16).
  static Future<void> withdrawPolymarket(
    BuildContext context, {
    required String walletId,
    required BigInt amount,
    required LedgerWithdrawalBinding binding,
    required bool Function(String address) belongsToLedger,
    ValueChanged<String?>? onSubmitted,
  }) async {
    if (!await ensureRouteNotPaused(context, PausableRoute.ledgerFunding)) {
      return;
    }
    if (!context.mounted) return;
    await LedgerWithdrawSheet.show(
      context,
      walletId: walletId,
      amount: amount,
      binding: binding,
      belongsToLedger: belongsToLedger,
      onSubmitted: onSubmitted,
    );
  }

  // ── Hyperliquid (Investing tab) ──

  /// The same order ticket the hot account gets, pinned to this Ledger:
  /// one sheet, two signers (see HlOrderSlipSheet.ledgerWalletId).
  static Future<void> placeOrder(
    BuildContext context,
    WidgetRef ref, {
    required String walletId,
    required HlMarket market,
    bool isBuy = true,
  }) async {
    if (!await _investingAllowed(context)) return;
    if (!context.mounted) return;
    await HlOrderSlipSheet.show(
      context,
      ref,
      market: market,
      isLong: isBuy,
      source: 'ledger_investing',
      ledgerWalletId: walletId,
    );
  }

  static Future<bool> cancelOrder(
    BuildContext context,
    WidgetRef ref, {
    required String walletId,
    required HlOpenOrder order,
    int? assetId,
  }) =>
      runLedgerHlCancel(context, ref,
          walletId: walletId, order: order, assetId: assetId);

  /// Spot and perps USDC move (readable, not behind O1).
  static Future<void> transfer(
    BuildContext context, {
    required String walletId,
    bool toPerp = true,
  }) async {
    if (!await _investingAllowed(context)) return;
    if (!context.mounted) return;
    await LedgerTransferSheet.show(context, walletId: walletId, toPerp: toPerp);
  }

  /// For a ticket that takes an execution target (O11).
  static HlExecutionTarget hyperliquidTarget(WidgetRef ref, String walletId) =>
      LedgerHlExecutionTarget(walletId: walletId, ref: ref);
}
