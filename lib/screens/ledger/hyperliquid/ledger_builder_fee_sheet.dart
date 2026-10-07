// lib/screens/ledger/hyperliquid/ledger_builder_fee_sheet.dart
//
// Registers Kute as the builder on a Ledger account before its first
// Hyperliquid order (Wallet hardening Phase 4a, P4.7, O17).
//
// There used to be a bottom sheet here, headed "Approve trading fee",
// that explained the fee and the builder address and then opened the
// Ledger approval sheet behind it. Two sheets asked the same question:
// the second one is the device prompt, where the rate and the builder
// address are shown on the Ledger's own screen and signed with a button
// the app cannot press. That is the approval. The first sheet added a
// step in front of an order and disclosed nothing the device does not.
//
// So this goes straight to the device prompt. The signed action, the
// readable summary and the venue call are unchanged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/ledger/ledger_action_controller.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/screens/ledger/ledger_approval_sheet.dart';
import 'package:kute/services/hardware/ledger/ledger_hyperliquid_executor.dart';
import 'package:kute/services/tracking_service.dart';

String _short(String address) => address.length <= 12
    ? address
    : '${address.substring(0, 6)}...${address.substring(address.length - 4)}';

/// Authorizes the builder on [walletId], prompting the Ledger once.
///
/// [builder] is the backend config the caller's order will carry; when
/// omitted the backend's current one is read. The app has no builder of
/// its own. Returns true when the venue accepted the approval, and true
/// as well when the backend names no builder (or cannot be reached),
/// since there is then nothing to approve and the order proceeds without
/// one. A rotated builder is approved here exactly like the first one.
Future<bool> approveLedgerHlBuilderFee(
  BuildContext context,
  WidgetRef ref, {
  required String walletId,
  HlBuilderInfo? builder,
}) async {
  final config = builder ?? await HyperliquidFundingService.getBuilder();
  if (config == null) return true;
  if (!context.mounted) return false;
  final paired = ref.read(ledgerIdentityProvider(walletId))?.evmAddress;
  if (paired == null) return false;
  final l10n = context.l10n;
  TrackingService.ledgerActionSheetOpened(action: 'hl_builder_fee');
  final intent = LedgerHyperliquidIntents.approveBuilderFee(
    walletId: walletId,
    account: paired,
    builder: config.builderAddress,
    maxFeeRate: config.maxFeeRate,
    summary: {
      l10n.ledgerSummaryFeeRate: config.maxFeeRate,
      l10n.ledgerSummaryBuilder: _short(config.builderAddress),
    },
  );
  final factory = ref.read(ledgerHlExecutorFactoryProvider);
  final outcome = await showLedgerApprovalSheet<void>(
    context,
    walletId: walletId,
    request: LedgerActionRequest<void>(
      intent: intent,
      execute: (signing) => factory(
        walletId: walletId,
        pairedAddress: signing.pairedAddress,
        signer: signing.signer,
      ).approveBuilderFee(intent),
    ),
  );
  return outcome.isSuccess;
}
