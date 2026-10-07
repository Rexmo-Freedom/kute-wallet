// lib/screens/ledger/ledger_tab_actions.dart
//
// Action hooks for the Ledger account tabs (Wallet hardening Phase 4).
// The tabs (P4.4) only read; each money action opens a Ledger sheet owned
// by P4.5 to P4.7 (approval sheet, Polymarket sheets, Hyperliquid sheets).
// Those sheets plug in here, so the tabs never import a hot provider or an
// executor directly. A null hook hides its button.
//
// Every hook receives the Ledger wallet ID the tab shows; a hook must act
// only for that wallet and only through the Ledger executors.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlOpenOrder;
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Position;

import 'package:kute/screens/ledger/ledger_sheet_account_actions.dart';

typedef LedgerWalletAction = void Function(
    BuildContext context, String walletId);
typedef LedgerHlOrderAction = void Function(
    BuildContext context, String walletId, HlOpenOrder order);
typedef LedgerPmPositionAction = void Function(
    BuildContext context, String walletId, Position position);
typedef LedgerPmPositionsAction = void Function(
    BuildContext context, String walletId, List<Position> positions);

/// [requiresDeploy]: the Ledger has no predictions account yet, so the
/// funding explainer must ask for an explicit confirmation to create it.
typedef LedgerPmFundAction = void Function(
    BuildContext context, String walletId,
    {required bool requiresDeploy});

class LedgerAccountActions {
  const LedgerAccountActions({
    this.onFundInvesting,
    this.onWithdrawInvesting,
    this.onOpenOrderTicket,
    this.onCancelOrder,
    this.onSellPosition,
    this.onClaimPosition,
    this.onClaimAll,
    this.onPredictionsFund,
    this.onPredictionsWithdraw,
    this.onPredictionsMakeFundsAvailable,
  });

  // Investing funding (Phase 4b, P4.10): Ledger BTC to and from HyperCore.
  final LedgerWalletAction? onFundInvesting;
  final LedgerWalletAction? onWithdrawInvesting;

  // Investing (Hyperliquid), P4.7.
  final LedgerWalletAction? onOpenOrderTicket;
  final LedgerHlOrderAction? onCancelOrder;

  // Predictions (Polymarket), P4.6.
  final LedgerPmPositionAction? onSellPosition;
  final LedgerPmPositionAction? onClaimPosition;
  final LedgerPmPositionsAction? onClaimAll;

  /// Phase 4b, P4.11: Ledger BTC to Predictions.
  final LedgerPmFundAction? onPredictionsFund;

  /// Null (hidden) unless `kLedgerPolymarketWithdrawEnabled` (O3).
  final LedgerWalletAction? onPredictionsWithdraw;

  /// Phase 4b, P4.11: wrap arrived USDC.e into usable cash (one Ledger
  /// approval). Shown only while arrived funds are not usable yet.
  final LedgerWalletAction? onPredictionsMakeFundsAvailable;
}

/// The hooks the Ledger tabs use, backed by the Phase 4a Ledger sheets
/// (`ledger_sheet_account_actions.dart`). A null hook hides its button.
/// Tests override it.
final ledgerAccountActionsProvider =
    Provider<LedgerAccountActions>((ref) => ledgerSheetAccountActions);
