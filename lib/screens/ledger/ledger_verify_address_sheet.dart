// lib/screens/ledger/ledger_verify_address_sheet.dart
//
// On-device check of a Ledger Bitcoin receive address (Wallet hardening
// Phase 4a, P4.8, owner decision O10).
//
// The caller passes the exact address it is about to hand to a provider and
// the derivation index `walletReceiveInfoProvider` chose for it. The Ledger
// derives the address at that index and shows it on its own screen; the
// sheet only reports `verified` when the device returns the SAME string.
// Connecting is not verifying: a connected device that rejects, disconnects,
// times out or shows a different address never produces `verified`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart' show WalletConfig;
import 'package:kute/screens/ledger/ledger_failure_copy.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/ledger_device_picker.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

enum LedgerAddressCheckOutcome {
  /// The device showed and returned exactly the expected address.
  verified,

  /// The device returned a different address. The caller must block.
  mismatch,

  /// The user closed the sheet before any device attempt.
  cancelled,

  /// A device attempt failed (rejected, disconnected, locked, timeout...)
  /// and the user closed the sheet without a later success.
  failed,
}

@immutable
class LedgerAddressCheckResult {
  const LedgerAddressCheckResult(this.outcome, {this.failureCode});

  final LedgerAddressCheckOutcome outcome;

  /// The last typed device failure, for analytics. Never an address.
  final LedgerFailureCode? failureCode;

  bool get isVerified => outcome == LedgerAddressCheckOutcome.verified;
}

/// Asks the Ledger behind [wallet] to show the receive address at
/// [addressIndex] and compares it to [expectedAddress].
///
/// Always resolves; a dismissed or failed sheet never reads as verified.
Future<LedgerAddressCheckResult> showLedgerVerifyAddressSheet(
  BuildContext context, {
  required WalletConfig wallet,
  required String expectedAddress,
  required int addressIndex,
}) async {
  final result = await showAppBottomSheet<LedgerAddressCheckResult>(
    context: context,
    // Dismissal goes through the sheet's own buttons so a device prompt in
    // flight is never abandoned by a stray swipe.
    isDismissible: false,
    enableDrag: false,
    builder: (_) => LedgerVerifyAddressSheet(
      wallet: wallet,
      expectedAddress: expectedAddress,
      addressIndex: addressIndex,
    ),
  );
  return result ??
      const LedgerAddressCheckResult(LedgerAddressCheckOutcome.cancelled);
}

enum _Stage { idle, connecting, confirming, mismatch, failed }

class LedgerVerifyAddressSheet extends ConsumerStatefulWidget {
  const LedgerVerifyAddressSheet({
    super.key,
    required this.wallet,
    required this.expectedAddress,
    required this.addressIndex,
  });

  final WalletConfig wallet;
  final String expectedAddress;
  final int addressIndex;

  @override
  ConsumerState<LedgerVerifyAddressSheet> createState() =>
      _LedgerVerifyAddressSheetState();
}

class _LedgerVerifyAddressSheetState
    extends ConsumerState<LedgerVerifyAddressSheet> {
  _Stage _stage = _Stage.idle;
  LedgerFailure? _failure;

  /// The error behind [_failure], for the plain-language copy.
  Object? _error;

  bool get _busy => _stage == _Stage.connecting || _stage == _Stage.confirming;

  /// One attempt's outcome. Categorical only: never the address, the
  /// index or the device.
  void _trackResult(String outcome, {LedgerFailure? failure, Object? error}) {
    TrackingService.track('ledger_verify_address_result', params: {
      'outcome': outcome,
      if (failure != null) 'failure_code': failure.code.name,
      if (error != null) 'error_category': TrackingService.errorCategory(error),
    });
  }

  @override
  void initState() {
    super.initState();
    // A sheet, not a route: once per mount.
    TrackingService.track('ledger_verify_address_sheet_opened');
  }

  Future<void> _verify() async {
    if (_busy) return;
    TrackingService.track('ledger_verify_address_started', params: {
      'retry': _stage == _Stage.failed || _stage == _Stage.mismatch,
    });
    final wallet = widget.wallet;
    if (!wallet.isLedger ||
        wallet.scriptType == null ||
        widget.expectedAddress.trim().isEmpty) {
      _trackResult('invalid_request');
      setState(() {
        _stage = _Stage.failed;
        _failure = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _stage = _Stage.connecting;
      _failure = null;
      _error = null;
    });
    final device = await showLedgerDevicePicker(context, ref);
    if (!mounted) return;
    if (device == null) {
      // Closing the picker is not a failure; stay ready to try again.
      _trackResult('picker_cancelled');
      setState(() => _stage = _failure == null ? _Stage.idle : _Stage.failed);
      return;
    }
    setState(() => _stage = _Stage.confirming);
    final ledger = ref.read(ledgerServiceProvider.notifier);
    String? deviceAddress;
    LedgerFailure? failure;
    Object? error;
    try {
      deviceAddress = await ledger.verifyReceiveAddress(
        scriptType: wallet.scriptType,
        addressIndex: widget.addressIndex,
      );
      if (deviceAddress == null) {
        failure = ref.read(ledgerServiceProvider).failure ??
            const LedgerFailure(LedgerFailureCode.disconnected);
      }
    } catch (e) {
      error = e;
      failure = LedgerFailure.from(e);
    } finally {
      try {
        await ledger.disconnect();
      } catch (_) {}
    }
    if (!mounted) return;
    if (failure != null || deviceAddress == null) {
      _trackResult('failed', failure: failure, error: error);
      setState(() {
        _stage = _Stage.failed;
        _failure = failure;
        _error = error;
      });
      return;
    }
    if (deviceAddress != widget.expectedAddress) {
      _trackResult('mismatch');
      setState(() => _stage = _Stage.mismatch);
      return;
    }
    _trackResult('verified');
    Navigator.of(context).pop(
        const LedgerAddressCheckResult(LedgerAddressCheckOutcome.verified));
  }

  void _close() {
    if (_busy) return;
    final LedgerAddressCheckResult result;
    switch (_stage) {
      case _Stage.mismatch:
        result =
            const LedgerAddressCheckResult(LedgerAddressCheckOutcome.mismatch);
      case _Stage.failed:
        result = LedgerAddressCheckResult(LedgerAddressCheckOutcome.failed,
            failureCode: _failure?.code);
      case _Stage.idle:
      case _Stage.connecting:
      case _Stage.confirming:
        result =
            const LedgerAddressCheckResult(LedgerAddressCheckOutcome.cancelled);
    }
    TrackingService.track('ledger_verify_address_closed', params: {
      'outcome': result.outcome.name,
      if (result.failureCode != null) 'failure_code': result.failureCode!.name,
    });
    Navigator.of(context).pop(result);
  }

  /// Groups of four so the user can compare against the device screen.
  static String _grouped(String address) {
    final buf = StringBuffer();
    for (var i = 0; i < address.length; i += 4) {
      if (i > 0) buf.write(' ');
      final end = i + 4 < address.length ? i + 4 : address.length;
      buf.write(address.substring(i, end));
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final String? statusText;
    Color statusColor = c.textSecondary;
    switch (_stage) {
      case _Stage.idle:
        statusText = null;
      case _Stage.connecting:
        statusText = null;
      case _Stage.confirming:
        statusText = l10n.ledgerVerifyAddressWaiting;
      case _Stage.mismatch:
        statusText = l10n.ledgerVerifyAddressMismatch;
        statusColor = c.error;
      case _Stage.failed:
        statusText = _error != null
            ? ledgerErrorCopy(context, _error!)
            : _failure != null
                ? ledgerFailureMessage(l10n, _failure!)
                : l10n.ledgerVerifyAddressUnavailable;
        statusColor = c.error;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AppBottomSheetContainer(
        maxHeight: 0.9,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBottomSheetHeader(
                title: l10n.ledgerVerifyAddressTitle,
                subtitle: l10n.ledgerVerifyAddressSubtitle(widget.wallet.name),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Semantics(
                  label: l10n.ledgerVerifyAddressLabel,
                  value: widget.expectedAddress,
                  child: Container(
                    padding: EdgeInsets.all(16.w),
                    decoration: AppDecorations.innerCard(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Text(
                            l10n.ledgerVerifyAddressLabel,
                            style: TextStyle(
                              color: c.textTertiary,
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(height: 8.h),
                        ExcludeSemantics(
                          child: SelectableText(
                            _grouped(widget.expectedAddress),
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 17.sp,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                              height: 1.4,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_stage == _Stage.confirming) ...[
                SizedBox(height: 20.h),
                Center(
                  child: LoadingAnimationWidget.staggeredDotsWave(
                    color: c.textPrimary,
                    size: 28.sp,
                  ),
                ),
              ],
              if (statusText != null) ...[
                SizedBox(height: 16.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ],
              SizedBox(height: 24.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_stage != _Stage.mismatch)
                      AppButton(
                        text: _stage == _Stage.failed
                            ? l10n.tryAgain
                            : l10n.ledgerVerifyAddressButton,
                        isLoading: _busy,
                        onPressed: _busy ? null : _verify,
                      ),
                    SizedBox(height: 8.h),
                    AppTextButton(
                      text: _stage == _Stage.mismatch ? l10n.close : l10n.cancel,
                      onPressed: _busy ? null : _close,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
