// lib/screens/ledger/funding/ledger_funding_parts.dart
//
// Copy mapping and small shared widgets for the Ledger funding sheets
// (Wallet hardening Phase 4, P4.10). "Nothing was sent" wording is only
// reached for errors raised before any broadcast or source send; the
// services wrap later failures in `LedgerFundingOutcomeUnknown`.
//
// Every error the sheets show goes through [ledgerFundingErrorMessage]:
// typed failures keep their sentence, anything else goes through the
// app-wide plain-language helper. The raw text only appears in the
// collapsed nerd data section under the error card.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_model.dart' show OrchestraQuote;
import 'package:kute/models/settings_model.dart' show WalletConfig;
import 'package:kute/screens/ledger/ledger_action_ui.dart'
    show LedgerAdvancedDisclosure, LedgerDisclosure;
import 'package:kute/screens/ledger/ledger_failure_copy.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show AmountCurrencyPill, AmountKeypad, BigAmountDisplay;
import 'package:kute/screens/shared/components/sheet_detail_row.dart'
    show SheetDetailRow, SheetNerdDataSection;
import 'package:kute/screens/shared/fee_copy.dart' show feeRateText;
import 'package:kute/screens/shared/money_fee_summary.dart';
import 'package:kute/screens/shared/wallet_icon.dart' show WalletVisual;
import 'package:kute/services/bitcoin/ledger_btc_send_service.dart';
import 'package:kute/services/funding/ledger_hypercore_funding_service.dart';
import 'package:kute/services/funding/ledger_polymarket_funding_service.dart';
import 'package:kute/services/funding/ledger_settlement.dart'
    show LedgerSettlementWriteFailed;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStopped, SettlementStopReason;
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/orchestra/orchestra_fee_amount.dart'
    show orchestraQuoteFeeAmounts;
import 'package:kute/services/orchestra/orchestra_quote_gate.dart';
import 'package:kute/services/release/route_pause_policy.dart'
    show RoutePausedException;
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/theme/app_theme.dart';

String ledgerFundingErrorMessage(BuildContext context, Object error) {
  final l10n = context.l10n;
  if (error is LedgerFailure) return ledgerFailureMessage(l10n, error);
  if (error is RoutePausedException) return l10n.routePausedBody;
  if (error is WalletGuardException) return error.messageFor(l10n);
  if (error is LedgerFundingOutcomeUnknown) return l10n.ledgerFundOutcomeUnknown;
  if (error is LedgerPmFundingOutcomeUnknown) {
    return l10n.ledgerFundOutcomeUnknown;
  }
  if (error is LedgerFundingQuoteExpiredException) {
    return ledgerQuoteRefreshedNote(l10n,
        duringApproval: error.duringApproval);
  }
  if (error is LedgerPmFundingRefused) {
    return switch (error.reason) {
      LedgerPmFundingRefusal.releaseFlagOff ||
      LedgerPmFundingRefusal.routeUnavailable ||
      LedgerPmFundingRefusal.withdrawDisabled =>
        l10n.ledgerFundRouteUnavailable,
      LedgerPmFundingRefusal.notPaired => l10n.ledgerTurnOnInvestingFirst,
      LedgerPmFundingRefusal.accountUnsupported =>
        l10n.ledgerPmFundErrorAccountUnsupported,
      LedgerPmFundingRefusal.deployNotConfirmed =>
        l10n.ledgerPmFundErrorDeployNotConfirmed,
      LedgerPmFundingRefusal.depositWalletPending =>
        l10n.ledgerPmFundErrorAccountPending,
      LedgerPmFundingRefusal.addressNotOwned =>
        l10n.ledgerPmFundErrorAddressNotOwned,
      LedgerPmFundingRefusal.balanceUnknown =>
        l10n.ledgerPmFundErrorBalanceUnknown,
      LedgerPmFundingRefusal.nothingToMove ||
      LedgerPmFundingRefusal.collateralNotAvailable ||
      LedgerPmFundingRefusal.unwrapRequired =>
        l10n.ledgerFundInvalidAmount,
    };
  }
  if (error is SettlementStopped) {
    return switch (error.reason) {
      SettlementStopReason.blockedPending => l10n.settlementBlockedPending,
      SettlementStopReason.routeUnavailable => l10n.ledgerFundRouteUnavailable,
      SettlementStopReason.quoteExpired => l10n.guardQuoteExpired,
      SettlementStopReason.quoteReplaced =>
        l10n.settlementQuoteChangedConfirmAgain,
      SettlementStopReason.declined => l10n.ledgerFundGenericError,
    };
  }
  // A record write before the broadcast failed: nothing was sent.
  if (error is LedgerSettlementWriteFailed) return l10n.ledgerFundGenericError;
  if (error is OrchestraQuoteFailure) return l10n.ledgerFundQuoteFailed;
  if (error is LedgerBtcSendException) {
    return switch (error.error) {
      LedgerBtcSendError.walletChanged => l10n.sendWalletChangedMidPrepare,
      LedgerBtcSendError.addressMismatch => l10n.ledgerFundAddressMismatch,
      LedgerBtcSendError.missingFingerprint =>
        l10n.ledgerFundFingerprintMissing,
      LedgerBtcSendError.signedTxMismatch => l10n.ledgerFundSignedTxMismatch,
      LedgerBtcSendError.invalidAmount => l10n.ledgerFundInvalidAmount,
      // B10: not exactly one output pays the quote. Nothing was signed.
      LedgerBtcSendError.depositOutputMissing => l10n.guardQuoteRejected,
      // F4: an earlier transfer's outcome is still unknown.
      LedgerBtcSendError.mustSpendUnavailable => l10n.settlementBlockedPending,
      _ => l10n.ledgerFundBuildFailed,
    };
  }
  if (error is LedgerFundingException) {
    return switch (error.error) {
      LedgerFundingError.routeUnavailable => l10n.ledgerFundRouteUnavailable,
      LedgerFundingError.evmNotVerified => l10n.ledgerTurnOnInvestingFirst,
      LedgerFundingError.reverseNotReady => l10n.ledgerWithdrawNotAvailableYet,
      LedgerFundingError.invalidAmount => l10n.ledgerFundInvalidAmount,
      _ => l10n.guardQuoteRejected,
    };
  }
  // A missing signed txid or an unsupported leg stops before any broadcast.
  if (error is StateError || error is UnsupportedError) {
    return l10n.ledgerFundRouteUnavailable;
  }
  return userErrorCopy(context, error, fallback: l10n.ledgerFundGenericError);
}

/// Raw text for the nerd data section under an error card. Only errors
/// with no typed mapping carry one; typed failures already say it all.
String? ledgerFundingErrorDetail(Object error) {
  if (ledgerFundingOutcomeCode(error) != 'unknown') return null;
  final text = errorDetailText(error);
  return text.isEmpty ? null : text;
}

/// Analytics outcome. No amounts, addresses or ids.
String ledgerFundingOutcomeCode(Object error) {
  if (error is LedgerFailure) return 'ledger_${error.code.name}';
  if (error is RoutePausedException) return 'route_paused';
  if (error is WalletGuardException) return error.reason.code;
  if (error is LedgerFundingOutcomeUnknown) return 'outcome_unknown';
  if (error is LedgerPmFundingOutcomeUnknown) return 'outcome_unknown';
  if (error is LedgerFundingQuoteExpiredException) return 'quote_expired';
  if (error is LedgerPmFundingRefused) return error.reason.name;
  if (error is SettlementStopped) return 'settlement_${error.reason.name}';
  if (error is LedgerSettlementWriteFailed) return 'store_${error.code}';
  if (error is OrchestraQuoteFailure) return 'quote_failed';
  if (error is LedgerBtcSendException) return error.error.code;
  if (error is LedgerFundingException) return error.error.code;
  if (error is StateError) return 'store_unavailable';
  if (error is UnsupportedError) return 'unsupported';
  return 'unknown';
}

/// The note a re-review shows after a quote was replaced before anything
/// was sent (Phase 5 plan B5): the Ledger copy when the price ran out
/// during the device approval, otherwise the Phase 2 expiry copy.
String ledgerQuoteRefreshedNote(AppLocalizations l10n,
        {required bool duringApproval}) =>
    duringApproval
        ? l10n.settlementLedgerExpiredDuringApproval
        : l10n.guardQuoteExpired;

String formatSatsAsBtc(int sats) {
  final whole = sats ~/ 100000000;
  final frac = (sats % 100000000).toString().padLeft(8, '0');
  final trimmed = frac.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.isEmpty ? '$whole' : '$whole.$trimmed';
}

class LedgerFundingRow extends StatelessWidget {
  const LedgerFundingRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(color: c.textSecondary, fontSize: 14.sp)),
          ),
          SizedBox(width: 12.w),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// One plain sentence above the amount: the whole story in one line. The
/// bullets it summarises sit in [LedgerFundingHowThisWorks].
class LedgerFundingIntroLine extends StatelessWidget {
  const LedgerFundingIntroLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: context.colors.textSecondary,
          fontSize: 14.sp,
          height: 1.4,
        ),
      );
}

/// The explainer bullets behind a collapsed "How this works" row.
class LedgerFundingHowThisWorks extends StatelessWidget {
  const LedgerFundingHowThisWorks({super.key, required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) => LedgerDisclosure(
        label: context.l10n.ledgerHowThisWorks,
        children: [LedgerFundingExplainerCard(lines: lines)],
      );
}

/// One "Fees" row on a review. The provider, Kute and Bitcoin network fee
/// breakdown sits behind the chevron instead of being three rows. The
/// headline is the provider and Kute fees together, as the quote charges
/// them ([orchestraQuoteFeeAmounts]).
class LedgerFundingFeesRow extends ConsumerWidget {
  LedgerFundingFeesRow({
    super.key,
    required OrchestraQuote quote,
    required num amountSats,
  })  : fees = orchestraQuoteFeeAmounts(quote, amountSats),
        kuteFeeBps = quote.appFeeBps;

  final ({double provider, double? kute, double total}) fees;

  /// Null when the quote carried no app fee list.
  final int? kuteFeeBps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final provider = feeAmountText(ref, sats: fees.provider);
    final kuteBps = kuteFeeBps;
    final kuteSats = fees.kute;
    return MoneyFeeSummary(
      label: 'Fees',
      sats: fees.total,
      note:
          'Included in the conversion. Network fees and exchange-rate spread may also apply.',
      details: [
        SheetDetailRow(label: l10n.providerFee, value: provider.primary),
        SheetDetailRow(
          label: kuteBps == null
              ? l10n.feeUiKuteFee
              : l10n.feeUiKuteFeeWithRate(feeRateText(kuteBps)),
          value: kuteSats == null
              ? l10n.feeUiIncludedInTheAmountYouReceive
              : feeAmountText(ref, sats: kuteSats).primary,
        ),
        SheetDetailRow(
          label: l10n.feeUiBitcoinNetworkFee,
          value: l10n.feeUiShownOnLedgerBeforeSigning,
        ),
      ],
    );
  }
}

/// Addresses and the provider name on a review, behind "Advanced". Long
/// values are middle-truncated and copied in full on tap.
class LedgerFundingAdvancedRows extends StatelessWidget {
  const LedgerFundingAdvancedRows({super.key, required this.rows});

  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) => LedgerAdvancedDisclosure(
        children: [
          for (final entry in rows.entries)
            SheetDetailRow(
              label: entry.key,
              value: entry.value,
              truncate: entry.value.length > 24,
              copiable: entry.value.length > 24,
            ),
        ],
      );
}

/// This Ledger's Bitcoin side of a funding move, with the wallet's own
/// icon and colour.
LedgerFundingEndpoint ledgerWalletEndpoint(
  BuildContext context,
  WalletConfig? wallet, {
  VoidCallback? onTap,
}) {
  final visual = wallet == null
      ? null
      : WalletVisual.fromWallet(
          walletType: wallet.walletType,
          isHardware: wallet.isHardware,
          isWatchOnly: wallet.isWatchOnly,
          isSigner: wallet.isSigner,
          isDark: Theme.of(context).brightness == Brightness.dark,
        );
  return LedgerFundingEndpoint(
    title: wallet?.name ?? 'Ledger',
    subtitle: context.l10n.ledgerTabBitcoin,
    asset: visual?.svgAsset ?? 'lib/assets/ledger-logo.svg',
    assetTint: visual?.svgAsset != null ? visual!.color : null,
    onTap: onTap,
  );
}

class LedgerFundingExplainerCard extends StatelessWidget {
  const LedgerFundingExplainerCard({super.key, required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) SizedBox(height: 10.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 6.h),
                  child: Container(
                    width: 6.w,
                    height: 6.w,
                    decoration: BoxDecoration(
                        color: c.textTertiary, shape: BoxShape.circle),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(lines[i],
                      style: TextStyle(
                          color: c.textPrimary, fontSize: 14.sp, height: 1.35)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class LedgerFundingMessageCard extends StatelessWidget {
  const LedgerFundingMessageCard({
    super.key,
    required this.message,
    this.isError = false,
    this.detail,
  });

  final String message;
  final bool isError;

  /// Raw error text for the collapsed nerd data section under the card.
  /// Null or empty hides the section.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? AppColors.error : c.textPrimary,
          fontSize: 14.sp,
          height: 1.35,
        ),
      ),
    );
    final detail = this.detail;
    if (detail == null || detail.isEmpty) return card;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        SheetNerdDataSection(children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 6.w),
            child: SelectableText(
              detail,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 13.sp,
                height: 1.4,
              ),
            ),
          ),
        ]),
      ],
    );
  }
}

class LedgerFundingBusyCard extends StatelessWidget {
  const LedgerFundingBusyCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 28.h),
      child: Column(
        children: [
          LoadingAnimationWidget.staggeredDotsWave(
              color: c.textSecondary, size: 28.sp),
          SizedBox(height: 16.h),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textPrimary, fontSize: 15.sp),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Move sheet structure ─────────────────────────
//
// The Ledger funding sheets read like the Move sheet on the main screen:
// a From chip and a To chip, one big number with the currency pill beside
// it, the shared fee block on review and one primary CTA. The Move sheet
// itself never takes a Ledger source for a HyperCore deposit (its
// dispatcher requires the spending wallet), so these mirror its parts.

/// One endpoint of a Ledger funding move.
class LedgerFundingEndpoint {
  const LedgerFundingEndpoint({
    required this.title,
    required this.subtitle,
    required this.asset,
    this.assetTint,
    this.onTap,
  });

  final String title;
  final String subtitle;

  /// SVG asset path.
  final String asset;
  final Color? assetTint;

  /// A tap opens a picker; null pins the endpoint.
  final VoidCallback? onTap;
}

/// From and To chips with the direction glyph between them, as on the
/// Move sheet. Direction is fixed here, so the glyph is a static marker.
class LedgerFundingEndpoints extends StatelessWidget {
  const LedgerFundingEndpoints({
    super.key,
    required this.from,
    required this.to,
  });

  final LedgerFundingEndpoint from;
  final LedgerFundingEndpoint to;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(child: _LedgerEndpointChip(endpoint: from)),
        SizedBox(width: 8.w),
        Container(
          width: 44.sp,
          height: 44.sp,
          decoration: BoxDecoration(
            color: c.surface,
            shape: BoxShape.circle,
            border: Border.all(color: c.borderSubtle, width: 0.5),
          ),
          alignment: Alignment.center,
          child: ExcludeSemantics(
            child: Icon(Icons.arrow_forward_rounded,
                color: c.textTertiary, size: 22.sp),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(child: _LedgerEndpointChip(endpoint: to)),
      ],
    );
  }
}

class _LedgerEndpointChip extends StatelessWidget {
  const _LedgerEndpointChip({required this.endpoint});

  final LedgerFundingEndpoint endpoint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = Container(
      height: 70.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38.sp,
            height: 38.sp,
            child: Center(
              child: SvgPicture.asset(
                endpoint.asset,
                width: 34.sp,
                height: 34.sp,
                colorFilter: endpoint.assetTint != null
                    ? ColorFilter.mode(endpoint.assetTint!, BlendMode.srcIn)
                    : null,
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    endpoint.title,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  endpoint.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
          if (endpoint.onTap != null) ...[
            SizedBox(width: 4.w),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: c.textTertiary, size: 18.sp),
          ],
        ],
      ),
    );
    if (endpoint.onTap == null) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          endpoint.onTap!();
        },
        borderRadius: BorderRadius.circular(16.r),
        child: body,
      ),
    );
  }
}

/// The Move sheet's one big number: a large typed amount with the currency
/// pill beside it, a conversion line and an available line underneath, and
/// the app's own keypad below it. Nothing here takes focus, so the OS
/// keyboard never opens on the funding sheets.
///
/// The [controller] stays the contract with the owning sheet — every key
/// press writes the whole new string into it, so the sheets' parsing,
/// review and Max handlers are untouched.
class LedgerFundingBigAmountField extends StatelessWidget {
  const LedgerFundingBigAmountField({
    super.key,
    required this.controller,
    required this.unitFlag,
    required this.unitCode,
    required this.semanticLabel,
    this.conversionLabel,
    this.availableLabel,
    this.availableExceeded = false,
    this.enabled = true,
    this.maxLabel,
    this.onMax,
    this.maxDecimals,
  });

  final TextEditingController controller;

  /// Glyph in the currency pill.
  final String unitFlag;
  final String unitCode;
  final String semanticLabel;
  final String? conversionLabel;
  final String? availableLabel;
  final bool availableExceeded;
  final bool enabled;

  /// A Max action beside the pill; both must be set for it to show.
  final String? maxLabel;
  final VoidCallback? onMax;

  /// Decimals the keypad allows. Null derives them from [unitCode], the
  /// same rule the sheets parse with: sats are whole, BTC has eight,
  /// dollars have cents.
  final int? maxDecimals;

  int get _decimals {
    if (maxDecimals != null) return maxDecimals!;
    if (unitCode == 'sats') return 0;
    if (unitCode == 'BTC') return 8;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final text = controller.text;
    final showMax = onMax != null && maxLabel != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: semanticLabel,
          value: text.isEmpty ? '0' : text,
          child: BigAmountDisplay(
            amountText: text,
            conversionLabel: conversionLabel,
            availableLabel: availableLabel,
            availableExceeded: availableExceeded,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showMax) ...[
                  _LedgerFundingMaxChip(
                    label: maxLabel!,
                    onTap: enabled ? onMax : null,
                  ),
                  SizedBox(width: 8.w),
                ],
                AmountCurrencyPill(flag: unitFlag, code: unitCode),
              ],
            ),
          ),
        ),
        SizedBox(height: 16.h),
        AmountKeypad(
          value: text,
          maxDecimals: _decimals,
          enabled: enabled,
          onChanged: (value) => controller.text = value,
        ),
      ],
    );
  }
}

/// Neutral Max chip beside the currency pill. Surface fill and a hairline
/// border, never a tint.
class _LedgerFundingMaxChip extends StatelessWidget {
  const _LedgerFundingMaxChip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 60),
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: c.borderSubtle, width: 0.5),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: onTap == null ? c.textTertiary : c.textPrimary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
