import 'package:kute/screens/shared/money_fee_summary.dart';
// lib/screens/ledger/hyperliquid/ledger_transfer_sheet.dart
//
// Move money between cash (spot) and the investing balance (perps) of a
// Ledger's Hyperliquid account (`usdClassTransfer`, Wallet hardening
// Phase 4a, P4.7). The copy says cash and investing balance. Readable on the
// device (amount and direction), so it is not behind the opaque flag.
// The entered amount survives cancel, rejection and disconnect.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/ledger/ledger_action_controller.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/screens/ledger/hyperliquid/ledger_hl_execution_target.dart';
import 'package:kute/screens/ledger/ledger_action_ui.dart';
import 'package:kute/screens/ledger/ledger_approval_sheet.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/hardware/ledger/ledger_hyperliquid_executor.dart';
import 'package:kute/services/tracking_service.dart';

class LedgerTransferSheet extends ConsumerStatefulWidget {
  const LedgerTransferSheet({
    super.key,
    required this.walletId,
    this.initialToPerp = true,
  });

  final String walletId;
  final bool initialToPerp;

  static Future<void> show(
    BuildContext context, {
    required String walletId,
    bool toPerp = true,
  }) {
    TrackingService.ledgerActionSheetOpened(action: 'hl_transfer');
    return showAppBottomSheet<void>(
      context: context,
      builder: (_) =>
          LedgerTransferSheet(walletId: walletId, initialToPerp: toPerp),
    );
  }

  @override
  ConsumerState<LedgerTransferSheet> createState() =>
      _LedgerTransferSheetState();
}

class _LedgerTransferSheetState extends ConsumerState<LedgerTransferSheet> {
  final _controller = TextEditingController();
  late bool _toPerp = widget.initialToPerp;
  bool _busy = false;
  bool _pending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? _available(LedgerHlAccount? hl) {
    final snapshot = hl?.account;
    if (snapshot == null) return null;
    if (_toPerp) {
      for (final HlSpotBalance b in snapshot.spotBalances) {
        if (b.coin == 'USDC') return b.available;
      }
      return 0;
    }
    return snapshot.withdrawable;
  }

  Future<void> _move(String paired, double amount) async {
    if (_busy || _pending) return;
    final l10n = context.l10n;
    final cents = (amount * 100 + 1e-9).floor();
    if (cents <= 0) return;
    final wire = (cents / 100).toStringAsFixed(2);
    setState(() => _busy = true);
    final walletId = widget.walletId;
    final intent = LedgerHyperliquidIntents.usdClassTransfer(
      walletId: walletId,
      account: paired,
      amount: wire,
      toPerp: _toPerp,
      summary: {
        l10n.ledgerSummaryAmount: ledgerFormatUsd(cents / 100),
        l10n.ledgerSummaryFrom:
            _toPerp ? l10n.ledgerHlCash : l10n.ledgerHlInvestingBalance,
        l10n.ledgerSummaryTo:
            _toPerp ? l10n.ledgerHlInvestingBalance : l10n.ledgerHlCash,
      },
    );
    final factory = ref.read(ledgerHlExecutorFactoryProvider);
    final navigator = Navigator.of(context, rootNavigator: true);
    final outcome = await showLedgerApprovalSheet<void>(
      context,
      walletId: walletId,
      request: LedgerActionRequest<void>(
        intent: intent,
        amountUsd: cents / 100,
        execute: (signing) => factory(
          walletId: walletId,
          pairedAddress: signing.pairedAddress,
          signer: signing.signer,
        ).usdClassTransfer(intent),
        reconcile: ledgerHlReconcile(ref, walletId),
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pending = outcome.isPending;
    });
    if (outcome.isSuccess || outcome.isPending) {
      ref.invalidate(ledgerHlAccountProvider(walletId));
    }
    if (outcome.isSuccess) {
      Navigator.of(context).pop();
      showLedgerConfirmation(navigator, message: l10n.ledgerTransferDone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hl = ref.watch(ledgerHlAccountProvider(widget.walletId)).valueOrNull;
    final paired = hl?.address;
    final available = _available(hl);
    final amount = ledgerParseAmount(_controller.text);
    final valid = paired != null &&
        amount != null &&
        available != null &&
        amount <= available + 1e-9;

    return LedgerActionSheetFrame(
      title: l10n.ledgerTransferTitle,
      subtitle: l10n.ledgerTransferSubtitlePlain,
      body: [
        LedgerChoiceChips<bool>(
          options: const [true, false],
          selected: _toPerp,
          enabled: !_busy && !_pending,
          label: (toPerp) => toPerp
              ? l10n.ledgerTransferToInvesting
              : l10n.ledgerTransferToCash,
          onSelected: (toPerp) => setState(() => _toPerp = toPerp),
        ),
        SizedBox(height: 12.h),
        LedgerAmountField(
          controller: _controller,
          semanticLabel: l10n.ledgerSummaryAmount,
          enabled: !_busy && !_pending,
          onChanged: (_) => setState(() {}),
          maxLabel: l10n.max,
          onMax: available == null
              ? null
              : () => setState(() => _controller.text =
                  ((available * 100).floor() / 100).toStringAsFixed(2)),
          availableText: available == null
              ? l10n.ledgerPartialLoad
              : l10n.ledgerAvailableAmount(ledgerFormatUsd(available)),
        ),
        SizedBox(height: 8.h),
        const MoneyFeeSummary(label: 'Transfer fee', usd: 0, bitcoinFirst: false),
        if (_pending)
          LedgerNote(
              text: l10n.ledgerPendingStatus, icon: Icons.schedule_rounded),
      ],
      buttons: [
        if (!_pending) ...[
          AppButton(
            text: l10n.ledgerMoveCta,
            isLoading: _busy,
            onPressed: valid && !_busy ? () => _move(paired, amount) : null,
          ),
          SizedBox(height: 10.h),
        ],
        AppButton(
          text: _pending ? l10n.ledgerApprovalClose : l10n.cancel,
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
