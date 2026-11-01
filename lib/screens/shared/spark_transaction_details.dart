import 'package:kute/services/spark_deposit_actions.dart'
    show suggestedClaimFeeSats;

import 'package:kute/models/transactions_model.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/currency_conversions_provider.dart'; // NEW: Conversion Provider
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/tracking_service.dart';

export 'package:kute/services/spark_deposit_actions.dart'
    show suggestedClaimFeeSats;

final selectedSparkTransactionProvider =
    StateProvider<BaseTransaction?>((ref) => null);

class TransactionDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isCopiable;
  final bool isAddress;
  final VoidCallback? onCopy;

  const TransactionDetailRow(
      {super.key,
      required this.label,
      required this.value,
      this.valueColor,
      this.isCopiable = false,
      this.isAddress = false,
      this.onCopy});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final displayText = isAddress && value.length > 16
        ? '${value.substring(0, 8)}...${value.substring(value.length - 8)}'
        : value;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: c.textSecondary, fontSize: 16.sp)),
          SizedBox(width: 16.w),
          Expanded(
            child: GestureDetector(
              onTap: onCopy ??
                  (isCopiable
                      ? () {
                          Clipboard.setData(ClipboardData(text: value));
                          showMessageSnackBarInfo(
                              context: context,
                              message: context.l10n.copiedToClipboard);
                        }
                      : null),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      displayText,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: valueColor ?? c.textPrimary,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (isCopiable) ...[
                    SizedBox(width: 8.w),
                    Icon(Icons.copy_rounded,
                        color: context.colors.accent, size: 14.sp)
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Spark claim fee is a quoted total fee, not a mining-speed selection.
/// Return a maximum in sats and enforce the same cap with MaxFee.fixed.
class ClaimFeePickerSheet extends ConsumerStatefulWidget {
  final int depositAmountSats;
  final breez.DepositClaimError? claimError;
  const ClaimFeePickerSheet(
      {super.key, required this.depositAmountSats, this.claimError});

  @override
  ConsumerState<ClaimFeePickerSheet> createState() =>
      _ClaimFeePickerSheetState();
}

class _ClaimFeePickerSheetState extends ConsumerState<ClaimFeePickerSheet> {
  late final TextEditingController _controller;
  int? _lastQuoteSats;

  @override
  void initState() {
    super.initState();
    TrackingService.screenView('claim_fee_picker');
    final error = widget.claimError;
    if (error is breez.DepositClaimError_MaxDepositClaimFeeExceeded) {
      _lastQuoteSats = error.requiredFeeSats.toInt();
    }
    final lastQuote = _lastQuoteSats;
    final suggested = lastQuote == null
        ? null
        : suggestedClaimFeeSats(
            lastQuoteSats: lastQuote,
            depositAmountSats: widget.depositAmountSats);
    _controller = TextEditingController(text: suggested?.toString() ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final amount = int.tryParse(_controller.text) ?? 0;
    final valid = amount > 0 && amount < widget.depositAmountSats;
    final lastQuote = _lastQuoteSats;
    final quoteUsesDeposit = lastQuote != null &&
        suggestedClaimFeeSats(
                lastQuoteSats: lastQuote,
                depositAmountSats: widget.depositAmountSats) ==
            null;
    return AppBottomSheetContainer(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppBottomSheetHeader(
              title: context.l10n.maximumClaimFee,
              subtitle: context.l10n.maximumClaimFeeExplanation,
              icon: Icons.account_balance_wallet_outlined),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: _controller,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(color: c.textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: c.surfaceLight,
                  labelText: context.l10n.maximumClaimFee,
                  labelStyle: TextStyle(color: c.textTertiary),
                  suffixText: 'sats',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.r),
                      borderSide: BorderSide.none),
                ),
              ),
              if (lastQuote != null)
                Padding(
                  padding: EdgeInsets.only(top: 8.h),
                  child: quoteUsesDeposit
                      ? Text(
                          context.l10n
                              .claimFeeQuoteExceedsDeposit('$lastQuote'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.accent, fontSize: 13.sp))
                      : Text(context.l10n.claimFeeLastQuote('$lastQuote'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: c.textTertiary, fontSize: 13.sp)),
                ),
              if (amount > 0)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  child: Text(ref.watch(conversionToFiatProvider(amount)),
                      style: TextStyle(color: c.textSecondary)),
                ),
              if (amount >= widget.depositAmountSats)
                Text(context.l10n.claimFeeExceedsDeposit,
                    style: TextStyle(color: AppColors.error)),
              if (valid && amount > widget.depositAmountSats ~/ 2)
                Text(context.l10n.claimFeeWarning,
                    style: TextStyle(color: c.accent)),
              SizedBox(height: 20.h),
              // THE BAR IS THE BUTTON (founder, 31 October 2026;
              // kute_bar_context.dart): Confirm claim is the floating Sal
              // bar's primary action, off until the cap is valid; Cancel
              // stays a text button above the bar's clearance.
              AppBottomSheetTextButton(
                  text: context.l10n.cancel, onPressed: () => context.pop()),
              KuteBarContextScope(
                  barContext: KuteBarContext.primary(
                      label: context.l10n.confirmClaim,
                      onPrimary: () {
                        TrackingService.sparkDepositClaimFeeConfirmed();
                        context.pop(amount);
                      },
                      enabled: valid,
                      source: 'claim_fee_picker',
                      disabledLabel: context.l10n.barNeedFee,),
                  child: SizedBox(height: kuteBarScrollClearance.h)),
            ]),
          ),
        ]),
      ),
    );
  }
}
