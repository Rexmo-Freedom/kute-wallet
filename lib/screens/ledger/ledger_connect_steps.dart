// lib/screens/ledger/ledger_connect_steps.dart
//
// Step visuals and copy for the Ledger approval sheet (Wallet hardening
// Phase 4a, P4.5). Pure presentation: every decision lives in
// LedgerActionController. Copy never claims the Ledger verified content
// it only shows as a code, and "Nothing was sent" appears only when no
// signature was obtained.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/ledger/ledger_action_controller.dart';
import 'package:kute/screens/ledger/ledger_action_ui.dart'
    show LedgerAdvancedDisclosure;
import 'package:kute/screens/ledger/ledger_failure_copy.dart';
import 'package:kute/services/hardware/ledger/ledger_action_intent.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:ledger_flutter_plus/ledger_flutter_plus.dart'
    show ConnectionType, LedgerDevice;

// ──────────────────────────────── copy ─────────────────────────────────

String ledgerApprovalTitle(AppLocalizations l10n, LedgerApprovalState state) {
  switch (state.step) {
    case LedgerApprovalStep.chooseTransport:
      return l10n.ledgerApprovalConnectTitle;
    case LedgerApprovalStep.scanning:
      return l10n.ledgerApprovalScanningTitle;
    case LedgerApprovalStep.connecting:
      return l10n.ledgerApprovalConnectingTitle;
    case LedgerApprovalStep.unlock:
      return l10n.ledgerUnlockStep;
    case LedgerApprovalStep.openApp:
      return l10n.ledgerOpenAppStep;
    case LedgerApprovalStep.installApp:
      return l10n.ledgerInstallAppStep;
    case LedgerApprovalStep.updateApp:
      return l10n.ledgerUpdateAppStep;
    case LedgerApprovalStep.checkingAccount:
      return l10n.ledgerCheckingAccountStep;
    case LedgerApprovalStep.review:
      return l10n.ledgerReviewTitle;
    case LedgerApprovalStep.approveOnDevice:
      return l10n.ledgerApproveStep;
    case LedgerApprovalStep.submitting:
      return l10n.ledgerSubmittingStep;
    case LedgerApprovalStep.pending:
      return l10n.ledgerPendingStatus;
    case LedgerApprovalStep.success:
      return l10n.ledgerSubmittingStep;
    case LedgerApprovalStep.failed:
      return l10n.ledgerApprovalFailedTitle;
  }
}

String? ledgerApprovalSubtitle(
    AppLocalizations l10n, LedgerApprovalState state) {
  switch (state.step) {
    case LedgerApprovalStep.chooseTransport:
      return l10n.ledgerApprovalConnectBody;
    case LedgerApprovalStep.scanning:
      return l10n.ledgerApprovalScanningBody;
    case LedgerApprovalStep.connecting:
      return l10n.ledgerApprovalConnectingBody;
    case LedgerApprovalStep.unlock:
      return l10n.ledgerUnlockStepBody;
    case LedgerApprovalStep.openApp:
      return state.failure != null
          ? l10n.ledgerOpenAppRetryBody
          : l10n.ledgerOpenAppStepBody;
    case LedgerApprovalStep.installApp:
    case LedgerApprovalStep.updateApp:
      return l10n.ledgerAppStoreRetryBody;
    case LedgerApprovalStep.checkingAccount:
      return l10n.ledgerCheckingAccountBody;
    case LedgerApprovalStep.review:
      return l10n.ledgerReviewBody;
    case LedgerApprovalStep.approveOnDevice:
      return l10n.ledgerApproveStepBody;
    case LedgerApprovalStep.submitting:
    case LedgerApprovalStep.success:
      return l10n.ledgerSubmittingBody;
    case LedgerApprovalStep.pending:
      return l10n.ledgerPendingBody;
    case LedgerApprovalStep.failed:
      return null;
  }
}

/// The failure line. "Nothing was sent" only while no signature exists.
String ledgerApprovalErrorMessage(
    AppLocalizations l10n, LedgerApprovalState state) {
  final signed = state.signatureObtained;
  switch (state.error) {
    case LedgerApprovalError.device:
      final failure =
          state.failure ?? const LedgerFailure(LedgerFailureCode.unknown);
      switch (failure.code) {
        case LedgerFailureCode.rejected:
          return signed
              ? l10n.ledgerRejectedAfterSignature
              : l10n.ledgerErrorRejected;
        case LedgerFailureCode.disconnected:
        case LedgerFailureCode.timeout:
          return signed
              ? l10n.ledgerDisconnectedAfterSignature
              : ledgerFailureMessage(l10n, failure,
                  fallbackApp: LedgerAppId.ethereum);
        default:
          return signed
              ? l10n.ledgerErrorCheckActivity
              : ledgerFailureMessage(l10n, failure,
                  fallbackApp: LedgerAppId.ethereum);
      }
    case LedgerApprovalError.notPaired:
      return l10n.ledgerTurnOnInvestingFirst;
    case LedgerApprovalError.appAuthDeclined:
      return l10n.ledgerErrorAppAuthDeclined;
    case LedgerApprovalError.blocked:
      return l10n.ledgerErrorActionBlocked;
    case LedgerApprovalError.geoBlocked:
      return l10n.ledgerErrorGeoBlocked;
    case LedgerApprovalError.tradingDisabled:
      return l10n.ledgerErrorTradingDisabled;
    case LedgerApprovalError.accountUnsupported:
      return l10n.ledgerErrorAccountUnsupported;
    case LedgerApprovalError.intentMismatch:
      return signed
          ? l10n.ledgerErrorCheckActivity
          : l10n.ledgerErrorDetailsChanged;
    case LedgerApprovalError.nonceRejected:
      return l10n.ledgerErrorNonceRejected;
    case LedgerApprovalError.venueRejected:
      return l10n.ledgerErrorVenueRejected;
    case LedgerApprovalError.orderIdMismatch:
      return l10n.ledgerErrorCheckActivity;
    case LedgerApprovalError.unknown:
    case null:
      return signed ? l10n.ledgerErrorCheckActivity : l10n.ledgerErrorUnknown;
  }
}

// ─────────────────────────────── widgets ───────────────────────────────

/// Spinner or glyph above the step copy.
class LedgerStepGlyph extends StatelessWidget {
  const LedgerStepGlyph({super.key, required this.step});

  final LedgerApprovalStep step;

  bool get _busy => const {
        LedgerApprovalStep.scanning,
        LedgerApprovalStep.connecting,
        LedgerApprovalStep.openApp,
        LedgerApprovalStep.checkingAccount,
        LedgerApprovalStep.approveOnDevice,
        LedgerApprovalStep.submitting,
        LedgerApprovalStep.pending,
      }.contains(step);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = switch (step) {
      LedgerApprovalStep.unlock => Icons.lock_outline_rounded,
      LedgerApprovalStep.installApp ||
      LedgerApprovalStep.updateApp =>
        Icons.system_update_alt_rounded,
      LedgerApprovalStep.failed => Icons.error_outline_rounded,
      _ => Icons.shield_outlined,
    };
    return SizedBox(
      height: 56.h,
      child: Center(
        child: _busy
            ? LoadingAnimationWidget.staggeredDotsWave(
                color: c.textSecondary, size: 32.sp)
            : ExcludeSemantics(
                child: Icon(icon, size: 36.sp, color: c.textSecondary)),
      ),
    );
  }
}

/// Bluetooth or USB (only offered when more than one transport exists).
class LedgerTransportOptions extends StatelessWidget {
  const LedgerTransportOptions({
    super.key,
    required this.transports,
    required this.onSelected,
  });

  final List<LedgerConnectionType> transports;
  final ValueChanged<LedgerConnectionType> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final t in transports)
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: LedgerOptionTile(
              icon: t == LedgerConnectionType.usb
                  ? Icons.usb_rounded
                  : Icons.bluetooth_rounded,
              label: t == LedgerConnectionType.usb
                  ? context.l10n.ledgerApprovalUsb
                  : context.l10n.ledgerApprovalBluetooth,
              onTap: () => onSelected(t),
            ),
          ),
      ],
    );
  }
}

class LedgerOptionTile extends StatelessWidget {
  const LedgerOptionTile({
    super.key,
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            child: Row(
              children: [
                Icon(icon, size: 22.sp, color: c.textPrimary),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                trailing ??
                    Icon(Icons.chevron_right_rounded,
                        size: 22.sp, color: c.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Devices found by the current scan.
class LedgerFoundDevices extends ConsumerWidget {
  const LedgerFoundDevices({super.key, required this.onSelected});

  final ValueChanged<LedgerDevice> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices =
        ref.watch(ledgerServiceProvider.select((s) => s.foundDevices));
    final c = context.colors;
    if (devices.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Text(
          context.l10n.ledgerApprovalNoDevices,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textTertiary, fontSize: 14.sp),
        ),
      );
    }
    return Column(
      children: [
        for (final device in devices)
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: LedgerOptionTile(
              icon: device.connectionType == ConnectionType.usb
                  ? Icons.usb_rounded
                  : Icons.bluetooth_rounded,
              label: device.name.isNotEmpty ? device.name : 'Ledger',
              onTap: () => onSelected(device),
            ),
          ),
      ],
    );
  }
}

/// The reviewed action: summary rows exactly as built at review time, plus
/// the clarity note. Readable kinds ask the user to compare with the
/// device; every other kind says the device shows a code.
///
/// The money rows (market, side, amount) stay on the card. Coin sizes,
/// leverage, worst prices and the fee recipient sit behind Advanced for
/// the kinds where they are mechanics rather than the point of the
/// approval; a leverage approval keeps its leverage row on the card.
class LedgerReviewCard extends StatelessWidget {
  const LedgerReviewCard({super.key, required this.intent});

  final LedgerActionIntent intent;

  /// Labels that sit behind Advanced for [kind]. Built from the same l10n
  /// strings the intents use as keys, so the match is exact.
  static Set<String> advancedLabels(
      AppLocalizations l10n, LedgerActionKind kind) {
    switch (kind) {
      case LedgerActionKind.hlOrder:
      case LedgerActionKind.hlCancel:
        return {
          l10n.ledgerSummarySize,
          l10n.ledgerSummaryLeverage,
          l10n.ledgerSummaryLimitPrice,
        };
      case LedgerActionKind.hlApproveBuilderFee:
        return {l10n.ledgerSummaryBuilder};
      default:
        return const <String>{};
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final actionClass = classifyLedgerAction(intent.kind);
    final hidden = advancedLabels(l10n, intent.kind);
    final primary = <MapEntry<String, String>>[];
    final advanced = <MapEntry<String, String>>[];
    for (final entry in intent.summary.entries) {
      (hidden.contains(entry.key) ? advanced : primary).add(entry);
    }
    // Never an empty card: with no primary row the whole summary shows.
    final rows = primary.isEmpty ? intent.summary.entries.toList() : primary;
    final extra = primary.isEmpty ? const <MapEntry<String, String>>[] : advanced;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
          decoration: BoxDecoration(
            color: c.surfaceLight,
            borderRadius: BorderRadius.circular(16.r),
          ),
          child: Column(
            children: [
              for (final entry in rows)
                LedgerSummaryRow(label: entry.key, value: entry.value),
            ],
          ),
        ),
        if (extra.isNotEmpty)
          LedgerAdvancedDisclosure(children: [
            for (final entry in extra)
              LedgerSummaryRow(label: entry.key, value: entry.value),
          ]),
        SizedBox(height: 12.h),
        LedgerClarityNote(needsOpaqueNote: actionClass.needsOpaqueNote),
      ],
    );
  }
}

class LedgerSummaryRow extends StatelessWidget {
  const LedgerSummaryRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: c.textSecondary, fontSize: 14.sp),
            ),
          ),
          SizedBox(width: 12.w),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LedgerClarityNote extends StatelessWidget {
  const LedgerClarityNote({super.key, required this.needsOpaqueNote});

  final bool needsOpaqueNote;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            needsOpaqueNote
                ? Icons.info_outline_rounded
                : Icons.visibility_outlined,
            size: 18.sp,
            color: c.textTertiary,
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            needsOpaqueNote
                ? context.l10n.ledgerOpaqueNote
                : context.l10n.ledgerReadableNote,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 13.sp,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
