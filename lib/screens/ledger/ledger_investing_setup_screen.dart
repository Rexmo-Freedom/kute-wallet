// lib/screens/ledger/ledger_investing_setup_screen.dart
//
// Ledger investing setup step (Wallet hardening Phase 4, P4.3, B10).
//
// Shown after a Ledger import, and from a Ledger venue tab's "Turn on
// investing", only while a Ledger venue is on (the `ledger.polymarket` /
// `ledger.hyperliquid` runtime capability). Two choices:
//   - "Turn on investing": connect, then `LedgerPairingService`
//     checks the Bitcoin fingerprint, reads the Ethereum address with
//     display for the user to approve on the device, re-checks the
//     fingerprint, and only then stores the public identity. Any failure
//     stores nothing and shows its localized reason.
//   - "Keep Bitcoin only": stores nothing; `evmAddress` stays null.
// Connecting is not approval: nothing is stored until the device flow
// succeeds. There is no phone-side fallback.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/ledger/ledger_failure_copy.dart';
import 'package:kute/screens/ledger/ledger_investment_gate.dart'
    show ledgerAnyVenueAllowed;
import 'package:kute/screens/shared/components/sheet_detail_row.dart'
    show SheetNerdDataSection;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/ledger_device_picker.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_pairing_service.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class LedgerInvestingSetupScreen extends ConsumerStatefulWidget {
  final String walletId;

  /// True when reached straight after the import; finishing lands on Home
  /// (the previous post-import destination) instead of popping.
  final bool fromImport;

  const LedgerInvestingSetupScreen({
    super.key,
    required this.walletId,
    this.fromImport = false,
  });

  @override
  ConsumerState<LedgerInvestingSetupScreen> createState() =>
      _LedgerInvestingSetupScreenState();
}

class _LedgerInvestingSetupScreenState
    extends ConsumerState<LedgerInvestingSetupScreen> {
  bool _busy = false;
  LedgerPairingStep? _step;
  LedgerFailure? _failure;

  /// The error behind [_failure], for the plain-language copy.
  Object? _error;

  /// The address the device is about to display, read silently right
  /// before the approval prompt so the user can compare it on screen.
  String? _previewAddress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only asked while a Ledger venue is on (its runtime capability).
      // Reached any other way (a stale link), it leaves without asking.
      if (!ledgerAnyVenueAllowed()) {
        _finish();
        return;
      }
      TrackingService.ledgerInvestingSetupViewed();
    });
  }

  WalletConfig? get _wallet {
    for (final w in ref.read(settingsProvider).wallets) {
      if (w.id == widget.walletId) return w;
    }
    return null;
  }

  void _finish() {
    if (!mounted) return;
    if (widget.fromImport || !context.canPop()) {
      context.go('/home');
    } else {
      context.pop();
    }
  }

  Future<void> _verify() async {
    if (_busy) return; // double tap gives one flow
    final wallet = _wallet;
    if (wallet == null || !wallet.isLedger) return;

    setState(() {
      _busy = true;
      _failure = null;
      _error = null;
      _step = null;
      _previewAddress = null;
    });
    TrackingService.ledgerEvmVerifyStarted();

    final ledger = ref.read(ledgerServiceProvider.notifier);
    try {
      if (ledger.deviceSession == null) {
        final device = await showLedgerDevicePicker(context, ref);
        if (!mounted) return;
        if (device == null) {
          TrackingService.ledgerEvmVerifyResult('cancelled');
          setState(() => _busy = false);
          return;
        }
      }
      final session = ledger.deviceSession;
      if (session == null) {
        throw const LedgerFailure(LedgerFailureCode.disconnected);
      }

      final settings = ref.read(settingsProvider.notifier);
      final pairing = LedgerPairingService(
        session: session,
        persist: (identity) => settings.setLedgerEvmIdentity(
          identity.walletId,
          evmAddress: identity.address,
          evmDerivationPath: identity.derivationPath,
          verifiedAtMs: identity.verifiedAtMs,
        ),
      );
      await pairing.verifyEthereumIdentity(
        wallet,
        onStep: (step) {
          if (mounted) setState(() => _step = step);
        },
        onAddressPreview: (address) {
          if (mounted) setState(() => _previewAddress = address);
        },
      );

      TrackingService.ledgerEvmVerifyResult('success');
      if (!mounted) return;
      setState(() => _busy = false);
      final navigator = Navigator.of(context, rootNavigator: true);
      pushKuteSuccessOverlay(
        navigator: navigator,
        overlay: KuteSuccessOverlay(
          headlineLabel: context.l10n.ledgerSetupTurnedOnTitle,
          onDone: () {
            navigator.pop();
            _finish();
          },
        ),
      );
    } catch (error) {
      final failure = LedgerFailure.from(error);
      TrackingService.ledgerEvmVerifyResult(failure.code.name);
      if (!mounted) return;
      setState(() {
        _busy = false;
        // The step stays so the list shows where the flow stopped.
        _failure = failure;
        _error = error;
      });
    } finally {
      // The pairing flow ends here; release the link so the Bitcoin
      // screens start from a clean connection.
      try {
        await ledger.disconnect();
      } catch (_) {}
    }
  }

  void _keepBitcoinOnly() {
    if (_busy) return;
    HapticFeedback.selectionClick();
    TrackingService.ledgerBitcoinOnlyChosen();
    _finish();
  }

  /// Position in the step list (connect, check, confirm, save); null
  /// before the flow starts. The device-level detail (which app is open,
  /// the fingerprint checks) is the caption under the current step.
  int? get _stepIndex {
    if (!_busy && _failure == null) return null;
    switch (_step) {
      case null:
        return 0;
      case LedgerPairingStep.openingBitcoinApp:
      case LedgerPairingStep.checkingFingerprint:
      case LedgerPairingStep.openingEthereumApp:
      case LedgerPairingStep.checkingAppVersion:
        return 1;
      case LedgerPairingStep.awaitingAddressApproval:
        return 2;
      case LedgerPairingStep.recheckingFingerprint:
      case LedgerPairingStep.saving:
      case LedgerPairingStep.done:
        return 3;
    }
  }

  /// What the device asks for right now, shown under the current step.
  String? _stepCaption(BuildContext context) {
    if (!_busy) return null;
    final l10n = context.l10n;
    switch (_step) {
      case null:
        return null;
      case LedgerPairingStep.openingBitcoinApp:
        return l10n.ledgerSetupStepOpenBitcoinApp;
      case LedgerPairingStep.checkingFingerprint:
      case LedgerPairingStep.checkingAppVersion:
      case LedgerPairingStep.recheckingFingerprint:
        return l10n.ledgerSetupStepCheckingAccount;
      case LedgerPairingStep.openingEthereumApp:
        return l10n.ledgerSetupStepOpenEthereumApp;
      case LedgerPairingStep.awaitingAddressApproval:
        return l10n.ledgerSetupStepApproveAddress;
      case LedgerPairingStep.saving:
      case LedgerPairingStep.done:
        return l10n.ledgerSetupStepSaving;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // No Ledger venue on: nothing to ask. The frame callback in initState
    // leaves; until then the screen is blank, never the prompt.
    if (!ledgerAnyVenueAllowed()) {
      return Scaffold(backgroundColor: c.background);
    }
    final l10n = context.l10n;
    final stepIndex = _stepIndex;
    final failure = _failure;
    final errorDetail =
        _error == null ? null : ledgerErrorDetail(context, _error!);
    final previewAddress = _previewAddress;
    final showAddress = _busy &&
        _step == LedgerPairingStep.awaitingAddressApproval &&
        previewAddress != null;

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: c.background,
        body: Container(
          decoration: AppDecorations.screenGradient(context),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 8.h),
                    // A Row keeps the button left: KuteBackButton centers
                    // itself and would fill a stretched Column otherwise.
                    child: Row(
                      children: [
                        KuteBackButton(
                          fallbackRoute: '/home',
                          onPressed: _busy
                              ? () {}
                              : () {
                                  HapticFeedback.lightImpact();
                                  _finish();
                                },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(top: 24.h, bottom: 24.h),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SetupLogos(),
                          SizedBox(height: 24.h),
                          Semantics(
                            header: true,
                            child: Text(
                              l10n.ledgerSetupTitle,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 28.sp,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6,
                                height: 1.15,
                              ),
                            ),
                          ),
                          SizedBox(height: 12.h),
                          Text(
                            l10n.ledgerSetupBodyPlain,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 16.sp,
                              height: 1.45,
                            ),
                          ),
                          if (stepIndex != null) ...[
                            SizedBox(height: 24.h),
                            _SetupStepList(
                              current: stepIndex,
                              failed: failure != null,
                              caption: _stepCaption(context),
                            ),
                            // Why the Bitcoin app is visited before and
                            // after, and any device code: nerd data.
                            SheetNerdDataSection(children: [
                              Text(
                                l10n.ledgerSetupWhyBothApps,
                                style: TextStyle(
                                  color: c.textTertiary,
                                  fontSize: 13.sp,
                                  height: 1.4,
                                ),
                              ),
                              if (errorDetail != null) ...[
                                SizedBox(height: 6.h),
                                Text(
                                  errorDetail,
                                  style: TextStyle(
                                    color: c.textTertiary,
                                    fontSize: 13.sp,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ]),
                          ],
                          if (showAddress) ...[
                            SizedBox(height: 20.h),
                            _SetupAddressPanel(address: previewAddress),
                          ],
                          if (failure != null) ...[
                            SizedBox(height: 24.h),
                            _SetupErrorLine(
                              text: ledgerErrorCopy(context, _error ?? failure,
                                  fallbackApp: LedgerAppId.ethereum),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  AppButton(
                    text: failure == null
                        ? l10n.ledgerSetupTurnOnCta
                        : l10n.ledgerSetupTryAgainCta,
                    isLoading: _busy,
                    onPressed: _busy ? null : _verify,
                  ),
                  SizedBox(height: 10.h),
                  AppButton(
                    text: l10n.ledgerSetupBitcoinOnlyCta,
                    variant: AppButtonVariant.secondary,
                    onPressed: _busy ? null : _keepBitcoinOnly,
                  ),
                  SizedBox(height: 16.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupLogos extends StatelessWidget {
  const _SetupLogos();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget tile(Widget child) => Container(
          width: 52.sp,
          height: 52.sp,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surfaceLight,
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: c.borderSubtle, width: 0.5),
          ),
          child: child,
        );
    return ExcludeSemantics(
      child: Row(
        children: [
          tile(SvgPicture.asset(
            'lib/assets/ledger-logo.svg',
            width: 28.sp,
            height: 28.sp,
            colorFilter: ColorFilter.mode(c.textPrimary, BlendMode.srcIn),
          )),
          SizedBox(width: 10.w),
          tile(SvgPicture.asset('lib/assets/hyperliquid-logo.svg',
              width: 28.sp, height: 28.sp)),
          SizedBox(width: 10.w),
          tile(SvgPicture.asset('lib/assets/polymarket-logo.svg',
              width: 28.sp, height: 28.sp)),
        ],
      ),
    );
  }
}

/// The pairing flow as four plain steps (connect, check, confirm, save),
/// current step highlighted, with the device instruction as the caption
/// under it. The Bitcoin app is visited before and after on purpose (same
/// device, same passphrase); the nerd data line under the list says so.
class _SetupStepList extends StatelessWidget {
  final int current;
  final bool failed;
  final String? caption;

  const _SetupStepList({
    required this.current,
    required this.failed,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final steps = [
      l10n.ledgerSetupStepConnecting,
      l10n.ledgerSetupStepCheck,
      l10n.ledgerSetupStepConfirm,
      l10n.ledgerSetupStepSave,
    ];
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: 10.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22.sp,
                    height: 22.sp,
                    child: _marker(context, i),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i],
                          style: TextStyle(
                            color: i == current
                                ? c.textPrimary
                                : i < current
                                    ? c.textSecondary
                                    : c.textTertiary,
                            fontSize: 15.sp,
                            fontWeight: i == current
                                ? FontWeight.w700
                                : FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                        if (i == current && caption != null)
                          Text(
                            caption!,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 13.sp,
                              height: 1.35,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _marker(BuildContext context, int index) {
    final c = context.colors;
    if (index < current) {
      return Icon(Icons.check_circle_rounded, size: 20.sp, color: c.success);
    }
    if (index == current) {
      if (failed) {
        return Icon(Icons.error_outline_rounded, size: 20.sp, color: c.error);
      }
      return Center(
        child: LoadingAnimationWidget.staggeredDotsWave(
            color: c.textPrimary, size: 18.sp),
      );
    }
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.borderSubtle),
      ),
      child: Text(
        '${index + 1}',
        style: TextStyle(
          color: c.textTertiary,
          fontSize: 11.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The address the device is showing, in large grouped chunks (0x, then
/// four characters at a time) so the eye can compare it with the Ledger
/// screen. Selectable; there is no tap-to-copy on purpose.
class _SetupAddressPanel extends StatelessWidget {
  final String address;

  const _SetupAddressPanel({required this.address});

  static String grouped(String address) {
    final hex = address.startsWith('0x') ? address.substring(2) : address;
    final groups = <String>['0x'];
    for (var i = 0; i < hex.length; i += 4) {
      groups.add(hex.substring(i, math.min(i + 4, hex.length)));
    }
    return groups.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            grouped(address),
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 22.sp,
              fontWeight: FontWeight.w700,
              height: 1.5,
              letterSpacing: 0.5,
              fontFamilyFallback: const ['Menlo', 'Courier New', 'monospace'],
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(height: 10.h),
          Text(
            l10n.ledgerSetupCompareAddress,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 14.sp,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupErrorLine extends StatelessWidget {
  final String text;
  const _SetupErrorLine({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18.sp, color: c.error),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15.sp,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
