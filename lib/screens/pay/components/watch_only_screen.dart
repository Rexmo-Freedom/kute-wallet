import 'package:kute/services/bitcoin/bitcoin_transaction_review.dart';
import 'package:kute/models/onchain_types.dart' show Network;
import 'dart:async';
import 'dart:convert' show base64Decode;
import 'package:kute/models/add_wallet_model.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/pay/components/animated_qr_view.dart';
import 'package:kute/services/jade_service.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/screens/shared/jade_device_picker.dart';
import 'package:kute/screens/shared/ledger_device_picker.dart';
import 'package:kute/screens/ledger/ledger_failure_copy.dart';
import 'package:kute/screens/ledger/ledger_connect_steps.dart'
    show LedgerOptionTile;
import 'package:kute/screens/pay/components/signing_stage.dart';
import 'package:kute/services/hardware/jade_pairing_check.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/helpers/psbt_helper.dart';
import 'package:kute/helpers/extension.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/providers/add_wallet_provider.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/transaction_modal.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/fee_history_service.dart';
import 'package:kute/screens/shared/wallet_icon.dart';
import 'package:kute/screens/shared/custom_alert_dialog.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';
import 'package:kute/l10n/l10n.dart';

enum SigningMethod { qrCode, sdCard, ledger, clipboard }

class WatchOnlySigningScreen extends ConsumerStatefulWidget {
  final String psbtBase64;
  final String walletType;
  final String? scriptType;
  /// When true the widget renders only its inner body (transaction
  /// summary + signing-method cards + broadcast bar) — no Scaffold,
  /// no AppBar, no PopScope, no background gradient. Used by the
  /// confirm_send Sign step which already provides those wrappers.
  /// `false` (default) keeps the original full-screen behaviour for
  /// any external pusher (legacy routes, deep links).
  final bool embedded;
  /// Recipient amount (sats) the destination address actually
  /// receives — i.e. the principal net of the on-chain fee in drain
  /// sends. When provided, the Transaction Details card shows this
  /// instead of the gross input total so the Amount row mirrors what
  /// the hardware device displays for verification.
  final int? recipientSatsOverride;
  /// On-chain fee (sats) parsed from the PSBT. When provided the
  /// Transaction Details card surfaces a "Fees" row alongside the
  /// recipient amount, matching the device's Amount + Fees breakdown.
  final int? feeSatsOverride;
  /// Destination address to display in the Transaction Details card.
  /// Mirrors the `*SatsOverride` pattern: when set, the embedded
  /// signing screen reads this instead of `sendTxProvider.address`.
  /// The Move sheet (and any future caller that pushes this widget
  /// from a non-Send context) can hand the address in directly so
  /// it doesn't depend on whatever happens to be in the global send
  /// notifier — that was the source of the empty-"To" bug on Move's
  /// hardware-source flows.
  final String? recipientAddressOverride;
  /// Source wallet id whose descriptor was used to build the PSBT.
  /// When provided the screen sources `masterFingerprint`,
  /// `walletType`, and the `FeeHistoryService.log` `walletId` field
  /// from this id rather than the carousel-pinned `activeWallet`.
  /// The Sign step of confirm_send and the Move sheet both run while
  /// `settings.activeWallet` is parked on spending, so reading the
  /// active wallet there silently picked the wrong fingerprint for
  /// fix-ups + tagged the on-chain fee row against spending. Optional
  /// for backwards compatibility — legacy callers that don't pass
  /// it fall back to the active wallet's value.
  final String? walletId;
  /// Horizontal padding the inner scroll view applies to its
  /// children. Defaults to the legacy 20.w so any caller that
  /// doesn't set it (including the Move sheet) keeps the same edge
  /// breathing room. The confirm_send Sign step passes `0` because
  /// the surrounding stepper body already pads horizontally — the
  /// default 20.w would double-pad and squash the device-picker
  /// row into a narrow column.
  final double? horizontalPadding;
  /// Notifies the parent when the PSBT signing state flips
  /// (`true` once signed; `false` when the user goes back and the
  /// signature is dropped). Lets the parent stepper hide controls
  /// that mutate the fee rate / UTXO set — those would invalidate
  /// the already-signed PSBT if the user could still tap them.
  final ValueChanged<bool>? onSignedChange;
  /// Locks parent fee/coin controls from device selection through signing,
  /// import, or broadcast, including retries and cancellation cleanup.
  final ValueChanged<bool>? onBusyChanged;
  /// Reports this PSBT's broadcast outcome to the host: `error` is null
  /// once broadcast; otherwise the failure and its `stage` (sign,
  /// validate, broadcast). The host's funnel only, never shown.
  final void Function(Object? error, String stage)? onBroadcastResult;

  const WatchOnlySigningScreen({
    super.key,
    required this.psbtBase64,
    required this.walletType,
    this.scriptType,
    this.embedded = false,
    this.recipientSatsOverride,
    this.feeSatsOverride,
    this.recipientAddressOverride,
    this.walletId,
    this.horizontalPadding,
    this.onSignedChange,
    this.onBusyChanged,
    this.onBroadcastResult,
  });

  @override
  ConsumerState<WatchOnlySigningScreen> createState() => _WatchOnlySigningScreenState();
}

class _WatchOnlySigningScreenState extends ConsumerState<WatchOnlySigningScreen> {
  SigningMethod? _expandedMethod;

  /// The methods other than the device's own sit behind "Other ways to
  /// sign" and only unfold when asked for.
  bool _showOtherMethods = false;
  String? _signedTxData;
  bool _isBroadcasting = false;
  bool _operationBusy = false;
  bool _isLedgerSigning = false;

  /// Which sentence the Bluetooth panel is telling while the device is
  /// busy. Presentation only: the signing calls below are unchanged, this
  /// just names the moment they are in so the panel can show one thing at
  /// a time instead of a status string with an ellipsis on it.
  _DeviceStage? _deviceStage;

  /// Name of the device currently being talked to, for the connecting
  /// sentence.
  String? _deviceName;

  /// Last failure from the Bluetooth path, shown in the panel with what to
  /// do next instead of a snackbar that slides away.
  String? _deviceFailure;
  final TextEditingController _pasteController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _pasteFocusNode = FocusNode();

  bool _sdStep1Done = false;

  /// `pay_transaction_signed` already fired for the loaded PSBT. Reset
  /// when a new PSBT is loaded, so re-pastes / re-scans of the same
  /// signature do not count again.
  bool _signedTracked = false;
  late String? _reviewedWalletId;
  late String _reviewedRecipient;
  late int _reviewedAmount;

  void _captureReview() {
    final send = ref.read(sendTxProvider);
    _reviewedWalletId = widget.walletId ?? ref.read(settingsProvider).activeWalletId;
    _reviewedRecipient = widget.recipientAddressOverride ?? send.address;
    _reviewedAmount = widget.recipientSatsOverride ?? send.amount;
  }

  /// Resolve only the wallet captured with the review. Removing that wallet
  /// must never fall back to another wallet's fingerprint or signing model.
  WalletConfig? get _sourceWallet {
    final settings = ref.read(settingsProvider);
    final id = _reviewedWalletId;
    if (id != null) {
      for (final w in settings.wallets) {
        if (w.id == id) return w;
      }
      return null;
    }
    return null;
  }

  String get _fixedPsbtBase64 {
    return PsbtHelper.fixFingerprints(
      widget.psbtBase64,
      _sourceWallet?.masterFingerprint,
    );
  }

  @override
  void initState() {
    super.initState();
    _pasteFocusNode.addListener(_onPasteFocus);
    _captureReview();
    // The device's own method opens ready to go; Bluetooth signing only
    // starts when the user taps Connect, never on arrival.
    _expandedMethod = _primaryMethod;
  }

  /// The method this device signs with first: Bluetooth for Ledger and
  /// Jade, the QR code for air gapped devices, paste for everything else.
  SigningMethod get _primaryMethod {
    final config = _getDeviceConfig();
    if (config?.isBluetooth ?? false) return SigningMethod.ledger;
    if (config?.isQrCodeSigning ?? true) return SigningMethod.qrCode;
    return SigningMethod.clipboard;
  }

  /// "Approve on your Ledger" or "Approve on your Jade" for Bluetooth
  /// devices, plain "Send" for everything else.
  String _screenTitle(BuildContext context) {
    final wt = widget.walletType.toLowerCase();
    if (wt.contains('jade')) return context.l10n.hwApproveOnJade;
    if (wt.contains('ledger')) return context.l10n.hwApproveOnLedger;
    return context.l10n.send;
  }

  @override
  void didUpdateWidget(covariant WatchOnlySigningScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.psbtBase64 != widget.psbtBase64 ||
        oldWidget.walletId != widget.walletId) {
      _signedTxData = null;
      _signedTracked = false;
      _captureReview();
    }
  }

  void _onPasteFocus() {
    if (_pasteFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (_scrollController.hasClients && mounted) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _pasteFocusNode.removeListener(_onPasteFocus);
    _pasteFocusNode.dispose();
    _pasteController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  WalletDeviceConfig? _getDeviceConfig() {
    final state = ref.read(addWalletProvider);
    try {
      return state.coldWallets.firstWhere((w) => w.type == widget.walletType,
          orElse: () => state.coldWallets.last);
    } catch (_) {
      return null;
    }
  }

  List<_SigningMethodOption> _getAvailableMethods() {
    final config = _getDeviceConfig();
    final methods = <_SigningMethodOption>[];

    final bool canQr = config?.isQrCodeSigning ?? true;
    final bool canSdCard = config?.isSdCard ?? false;
    final bool canBluetooth = config?.isBluetooth ?? false;

    if (canQr) {
      methods.add(_SigningMethodOption(
        method: SigningMethod.qrCode,
        icon: Icons.qr_code_scanner_rounded,
        label: context.l10n.receiveQrCodeLabel,
      ));
    }

    if (canSdCard) {
      methods.add(_SigningMethodOption(
        method: SigningMethod.sdCard,
        icon: Icons.sd_card_rounded,
        label: context.l10n.sdCard,
      ));
    }

    if (canBluetooth) {
      methods.add(_SigningMethodOption(
        method: SigningMethod.ledger,
        icon: Icons.bluetooth_connected_rounded,
        label: context.l10n.bluetooth,
      ));
    }

    // Always add Copy & Paste as the last option
    methods.add(_SigningMethodOption(
      method: SigningMethod.clipboard,
      icon: Icons.content_paste_rounded,
      label: context.l10n.receiveCopyAndPaste,
    ));

    return methods;
  }

  /// Picks the way this payment gets signed. One method is on screen at a
  /// time now, so this always selects rather than collapsing to nothing.
  void _selectMethod(SigningMethod method) {
    if (_operationBusy) return;
    HapticFeedback.selectionClick();
    TrackingService.track('hw_sign_method_selected', params: {
      'method': method.name,
      'wallet_type': widget.walletType,
    });
    setState(() {
      _expandedMethod = method;
      // Reset step progression when switching methods
      _sdStep1Done = false;
      _deviceFailure = null;
      if (method == SigningMethod.ledger) {
        if (widget.walletType == 'jade') {
          _handleJadeSigning();
        } else {
          _handleLedgerSigning();
        }
      }
    });
  }

  /// Parks a Bluetooth failure in the panel. The sentence is the same one
  /// the snackbar used to carry; it now stays put next to the retry.
  void _setDeviceFailure(String message) {
    if (!mounted) return;
    setState(() => _deviceFailure = message);
  }

  Future<void> _withBusy(Future<void> Function() operation) async {
    if (_operationBusy || !mounted) return;
    setState(() => _operationBusy = true);
    widget.onBusyChanged?.call(true);
    try {
      await operation();
    } finally {
      // Event-handler callbacks, never build-time notifications. A disposed
      // child must not unlock a replacement signing screen in its parent.
      if (mounted) {
        setState(() => _operationBusy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  Future<void> _handleLedgerSigning() => _withBusy(_handleLedgerSigningImpl);
  Future<void> _handleJadeSigning() => _withBusy(_handleJadeSigningImpl);
  Future<void> _onScanSignedTx() => _withBusy(_onScanSignedTxImpl);
  Future<void> _onImportFile() => _withBusy(_onImportFileImpl);
  Future<void> _onBroadcast() => _withBusy(_onBroadcastImpl);

  Future<void> _exportFile() async {
    await PsbtHelper.sharePsbtFile(_fixedPsbtBase64, "tx");
    if (mounted) setState(() => _sdStep1Done = true);
  }

  Future<void> _copyPsbt() async {
    await Clipboard.setData(ClipboardData(text: _fixedPsbtBase64));
    if (mounted) {
      showMessageSnackBar(
          message: context.l10n.hwUnsignedTransactionCopied,
          context: context,
          error: false);
    }
  }

  Future<void> _onScanSignedTxImpl() async {
    final result = await context.pushNamed<String>('QrScanner');
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      _processImportedTx(result);
    }
  }

  Future<void> _onImportFileImpl() async {
    try {
      final base64Tx = await PsbtHelper.importFromFile();
      if (!mounted) return;
      if (base64Tx != null && base64Tx.isNotEmpty) {
        _processImportedTx(base64Tx);
      }
    } catch (e) {
      if (mounted) {
        showMessageSnackBar(
            message: userErrorCopy(context, e,
                fallback: context.l10n.hwCouldNotReadSignedFile),
            error: true,
            context: context);
      }
    }
  }

  void _onSubmitPastedTx() {
    if (_operationBusy) return;
    final text = _pasteController.text.trim();
    if (text.isNotEmpty) {
      _processImportedTx(text);
    }
  }

  void _processImportedTx(String txData, {String? signerType}) {
    if (!mounted) return;
    setState(() => _signedTxData = txData);
    widget.onSignedChange?.call(true);
    // `pay_transaction_signed` — fires once per signed PSBT, regardless
    // of which signing transport delivered it (Ledger USB, Jade BLE,
    // gallery import, paste). The `signer_type` param defaults
    // from `widget.walletType` when the caller didn't pass an explicit
    // hint — covers QR/file/paste paths where we only know which
    // wallet type they signed against, not the actual device.
    String resolvedSigner;
    if (signerType != null) {
      resolvedSigner = signerType;
    } else {
      final wt = widget.walletType.toLowerCase();
      if (wt.contains('jade')) {
        resolvedSigner = 'jade';
      } else if (wt.contains('ledger')) {
        resolvedSigner = 'ledger';
      } else {
        resolvedSigner = 'psbt_clipboard';
      }
    }
    // Only a signature that verifies against the reviewed PSBT counts,
    // and only once per loaded PSBT (paste / scan can deliver it again).
    if (_signedTracked || !_verifySignedOutputsMatch(txData)) return;
    _signedTracked = true;
    TrackingService.track('pay_transaction_signed', params: {
      'payment_type': 'bitcoin',
      'signer_type': resolvedSigner,
    });
  }

  /// `send_completed` / `send_failed` for the broadcast of this PSBT.
  void _trackSendOutcome({
    String? txId,
    Object? error,
    String stage = 'broadcast',
  }) {
    final source = _sourceWallet;
    final walletKind = source == null
        ? null
        : TrackingService.walletKind(
            isLedger: source.isLedger,
            isHardware: source.isHardware,
            isWatchOnly: source.isWatchOnly,
            isSigner: source.isSigner,
            isExternalAddress: source.isExternalAddress,
          );
    final amountSats = _reviewedAmount > 0 ? _reviewedAmount : null;
    final feeSats = widget.feeSatsOverride;
    double? amountUsd;
    double? feeUsd;
    String? currency;
    try {
      final usdPerBtc = ref.read(selectedCurrencyProvider('usd')).toDouble();
      if (usdPerBtc > 0) {
        if (amountSats != null) amountUsd = amountSats / 1e8 * usdPerBtc;
        if (feeSats != null && feeSats > 0) {
          feeUsd = feeSats / 1e8 * usdPerBtc;
        }
      }
      currency = ref.read(settingsProvider).currency;
    } catch (_) {}
    if (error == null) {
      TrackingService.sendCompleted(
        flow: 'watch_only',
        network: 'bitcoin',
        asset: 'btc',
        walletKind: walletKind,
        provider: 'psbt',
        amountUsd: amountUsd,
        amountSats: amountSats,
        currency: currency,
        feeSats: feeSats,
        feeUsd: feeUsd,
        networkFeeUsd: feeUsd,
        dedupeKey: txId,
      );
      TrackingService.moneyFlowFinished('send');
    } else {
      TrackingService.sendFailed(
        flow: 'watch_only',
        network: 'bitcoin',
        asset: 'btc',
        error: error,
        walletKind: walletKind,
        provider: 'psbt',
        amountUsd: amountUsd,
        amountSats: amountSats,
        currency: currency,
        feeSats: feeSats,
        feeUsd: feeUsd,
        stage: stage,
      );
      TrackingService.moneyFlowError('send', error);
    }
    widget.onBroadcastResult?.call(error, stage);
  }

  Future<void> _handleLedgerSigningImpl() async {
    final ledger = ref.read(ledgerServiceProvider.notifier);
    if (mounted && _deviceFailure != null) {
      setState(() => _deviceFailure = null);
    }

    // Device picker now handles connection + Bitcoin app verification
    final device = await showLedgerDevicePicker(context, ref);
    // The screen can unmount while the picker sheet is up (parent
    // stepper pop, deep-link, etc.) — bail before touching state, but
    // still drop the connection the picker opened so the next attempt
    // starts clean instead of hitting a half-open BLE session.
    if (device == null || !mounted) {
      if (device != null) {
        try {
          await ledger.disconnect();
        } catch (_) {}
      }
      return;
    }

    try {
      setState(() {
        _isLedgerSigning = true;
        _deviceName = device.name;
        // The picker already connected and checked the Bitcoin app, so
        // the only thing left is the user's approval on the device.
        _deviceStage = _DeviceStage.approve;
      });

      // Device is already connected — try to sign
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          if (!mounted) break;
          setState(() => _deviceStage = _DeviceStage.approve);
          // The stored fingerprint gates signing: a different Ledger (or
          // passphrase) fails with wrongDevice before any PSBT reaches
          // the device. A null stored fingerprint keeps today's flow and
          // is never silently overwritten with the device value.
          final signedPsbt = await ledger.signPsbt(
            _fixedPsbtBase64,
            scriptType: widget.scriptType,
            expectedFingerprint: _sourceWallet?.masterFingerprint,
          );
          if (!mounted) break;

          if (signedPsbt != null) {
            _processImportedTx(signedPsbt, signerType: 'ledger');
          } else {
            final failure = ref.read(ledgerServiceProvider).failure;
            if (failure?.code == LedgerFailureCode.wrongApp) {
              final shouldRetry = await _showOpenBitcoinAppDialog();
              if (shouldRetry && mounted) continue;
              break; // User cancelled
            }
            _setDeviceFailure(failure != null
                ? ledgerFailureMessage(context.l10n, failure)
                : context.l10n.receiveSigningCancelledOrFailed);
          }
          break; // Success or user-rejected — done
        } catch (e) {
          if (LedgerFailure.from(e).code == LedgerFailureCode.wrongApp &&
              mounted) {
            final shouldRetry = await _showOpenBitcoinAppDialog();
            if (shouldRetry && mounted) continue;
            break; // User cancelled
          }
          rethrow; // Other error
        }
      }
    } catch (e) {
      if (mounted) {
        _setDeviceFailure(ledgerErrorMessage(context.l10n, e));
      }
    } finally {
      // Disconnect on EVERY exit — the old flow skipped it when the
      // sign attempt rethrew, leaving the BLE session open and the
      // next Connect and sign attempt flaky until the device timed
      // itself out.
      try {
        await ledger.disconnect();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isLedgerSigning = false;
          _deviceStage = null;
        });
      }
    }
  }

  Future<bool> _showOpenBitcoinAppDialog() async {
    // App-standard alert chrome (blurred barrier + stacked full-width
    // AppButtons) — replaced the one-off Material AlertDialog with its
    // 10.r ElevatedButton that the CTA sweep flagged.
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) {
        return CustomAlertDialog(
          title: ctx.l10n.openBitcoinApp,
          content: ctx.l10n.ledgerBitcoinAppNotOpenMessage,
          actions: [
            AppButton(
              text: ctx.l10n.retry,
              compact: true,
              onPressed: () => ctx.pop(true),
            ),
            AppButton(
              text: ctx.l10n.cancel,
              variant: AppButtonVariant.secondary,
              compact: true,
              onPressed: () => ctx.pop(false),
            ),
          ],
        );
      },
    ) ?? false;
  }

  Future<void> _handleJadeSigningImpl() async {
    final jade = ref.read(jadeServiceProvider.notifier);
    if (mounted && _deviceFailure != null) {
      setState(() => _deviceFailure = null);
    }

    final device = await showJadeDevicePicker(context, ref);
    // Screen can unmount while the picker is up — bail before any
    // setState. The Jade picker returns an UNCONNECTED device (unlike
    // Ledger's), so there is nothing to disconnect here.
    if (device == null || !mounted) return;

    try {
      setState(() {
        _isLedgerSigning = true;
        _deviceName = device.name;
        _deviceStage = _DeviceStage.connecting;
      });

      final connected = await jade.connectToDevice(device);
      if (!mounted) return;
      if (!connected) {
        final jadeState = ref.read(jadeServiceProvider);
        _setDeviceFailure(userErrorCopy(context, jadeState.errorMessage,
            fallback: context.l10n.receiveConnectionFailed));
        return;
      }

      // Jade requires PIN authentication
      setState(() => _deviceStage = _DeviceStage.unlock);
      final authenticated = await jade.authenticate();
      if (!mounted) return;
      if (!authenticated) {
        final jadeState = ref.read(jadeServiceProvider);
        _setDeviceFailure(userErrorCopy(context, jadeState.errorMessage,
            fallback: context.l10n.receiveAuthenticationFailed));
        return;
      }

      // The connected Jade must be the one paired with the reviewed
      // wallet (`_sourceWallet`, never the spending wallet). A wallet
      // with no fingerprint yet is paired to this Jade now; a different
      // stored fingerprint stops here and is never overwritten.
      setState(() => _deviceStage = _DeviceStage.approve);
      final actualFp = await jade.getMasterFingerprint();
      if (!mounted) return;
      try {
        await verifyJadePairing(
          wallet: _sourceWallet,
          actualFingerprint: actualFp,
          save: ref.read(settingsProvider.notifier).updateWalletConfig,
        );
      } on JadeWrongDeviceException {
        if (!mounted) return;
        _setDeviceFailure(context.l10n.jadeErrorWrongDevice);
        return;
      }
      if (!mounted) return;

      // Log PSBT fingerprints before fix
      PsbtHelper.debugLogPsbtFingerprints(widget.psbtBase64, 'JadeSign-before');

      final psbtToSign = actualFp != null
          ? PsbtHelper.fixFingerprints(widget.psbtBase64, actualFp)
          : _fixedPsbtBase64;

      // Log PSBT fingerprints after fix
      PsbtHelper.debugLogPsbtFingerprints(psbtToSign, 'JadeSign-after');

      final signedPsbt = await jade.signPsbt(
        psbtToSign,
        scriptType: widget.scriptType,
      );
      if (!mounted) return;

      if (signedPsbt != null) {
        _processImportedTx(signedPsbt, signerType: 'jade');
      } else {
        final jadeState = ref.read(jadeServiceProvider);
        _setDeviceFailure(userErrorCopy(context, jadeState.errorMessage,
            fallback: context.l10n.receiveSigningCancelledOrFailed));
      }
    } catch (e) {
      if (mounted) {
        _setDeviceFailure(userErrorCopy(context, e,
            fallback: context.l10n.hwCouldNotSignWithJade));
      }
    } finally {
      // Disconnect on EVERY exit path — the old flow only did it on
      // the success and auth-failure branches, so a thrown sign step
      // (or connection failure mid-flow) left the BLE session open.
      try {
        await jade.disconnect();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isLedgerSigning = false;
          _deviceStage = null;
        });
      }
    }
  }

  bool _verifySignedOutputsMatch(String signedData) =>
      signedBitcoinTransactionMatches(
        reviewedPsbt: widget.psbtBase64,
        signedData: signedData,
      );

  Future<void> _onBroadcastImpl() async {
    if (_signedTxData == null) return;

    // Verify signed tx outputs match the original PSBT
    if (!_verifySignedOutputsMatch(_signedTxData!)) {
      _trackSendOutcome(error: 'signed_tx_mismatch', stage: 'sign');
      if (mounted) {
        showMessageSnackBar(
          message: context.l10n.signedTransactionDoesNotMatchOriginalBroadcastAborted,
          error: true,
          context: context,
        );
      }
      return;
    }

    setState(() => _isBroadcasting = true);

    var broadcastDone = false;
    try {
      final source = _sourceWallet;
      if (source == null) throw StateError('The reviewed wallet is unavailable.');
      final reviewedPsbt = widget.psbtBase64;
      final signedData = _signedTxData!;
      final model =
          await ref.read(bitcoinModelForWalletProvider(source.id).future);
      if (!mounted || widget.psbtBase64 != reviewedPsbt ||
          _signedTxData != signedData || _sourceWallet?.id != source.id) {
        throw StateError('The reviewed payment changed. Review it again.');
      }
      if (!reviewedBitcoinSummaryMatches(
        reviewedPsbt: reviewedPsbt,
        recipient: _reviewedRecipient,
        amountSats: _reviewedAmount,
        mainnet: model.config.network == Network.bitcoin,
      )) {
        throw StateError('The transaction does not match the reviewed recipient and amount.');
      }
      final txId = await model.broadcastSignedTransaction(signedData);
      broadcastDone = true;
      _trackSendOutcome(txId: txId);
      // BDK counts the send only once a sync sees it in the mempool, and
      // nothing else re-scans a hardware / watch-only wallet until the
      // person pulls to refresh. Same as the software send.
      unawaited(BackgroundSyncService()
          .scanBdkScope(source: 'watch_only_send', walletId: source.id)
          .catchError((_) {}));
      if (mounted) {
        final settings = ref.read(settingsProvider);
        // The success view uses exactly the values shown before signing.
        final amount = _reviewedAmount;
        final address = _reviewedRecipient;
        final sourceWallet = _sourceWallet;

        // Phase 9 — log the on-chain fee paid by the savings /
        // watch-only / hardware wallet send. The Total Fees
        // analytics card was missing every L1 fee from these
        // wallets because the only fee logging lived on the Spark
        // / Breez send path. Now hardware-broadcast PSBTs feed
        // the same FeeHistoryService ledger as everything else.
        // Tag the fee against the SOURCE wallet (via `walletId`
        // override) so analytics attribute the spend to the right
        // wallet card — using `settings.activeWalletId` mis-tagged
        // every hardware-source fee against spending.
        final feeSats = widget.feeSatsOverride ?? 0;
        if (feeSats > 0) {
          try {
            final usdPerBtc =
                ref.read(selectedCurrencyProvider('usd')).toDouble();
            final feeUsd = (feeSats / 1e8) * usdPerBtc;
            if (feeUsd > 0) {
              FeeHistoryService.log(
                id: 'btc-onchain-savings-${DateTime.now().millisecondsSinceEpoch}',
                kind: FeeKind.btcOnchain,
                microUsd: (feeUsd * 1000000).round(),
                nativeAmount: feeSats.toString(),
                nativeUnit: 'sats',
                source: 'Savings',
                walletId:
                    sourceWallet?.id ?? settings.activeWalletId,
              );
            }
          } catch (_) {}
        }

        // `transaction_sent` is emitted centrally from
        // `transactions_provider` (`_reportNewSends`) when the broadcast
        // tx appears in the snapshot, so it's not fired here.

        showFullscreenTransactionSendModal(
          context: context,
          asset: 'Bitcoin',
          // Empty when the amount is unknown — the overlay hides its
          // amount line entirely instead of rendering a bare "-".
          amount: amount > 0
              ? '${amount.toFormattedString(settings.btcFormat)} ${settings.btcFormat}'
              : '',
          fiat: false,
          txid: txId,
          receiveAddress: address,
          confirmationBlocks: ref.read(sendBlocksProvider),
        );

        ref.read(sendTxProvider.notifier).resetToDefault();
        ref.read(selectedUtxosProvider.notifier).state = [];
        // Don't `context.replace('/home')` here — it tears the
        // success overlay down before it mounts. The overlay's
        // Done button (`PaymentTransactionOverlay`) does the
        // navigation home itself.
      }
    } catch (e) {
      // After a successful broadcast only the success UI can throw; the
      // send already reported send_completed.
      if (!broadcastDone) {
        _trackSendOutcome(
            error: e, stage: e is StateError ? 'validate' : 'broadcast');
      }
      if (mounted) {
        setState(() => _isBroadcasting = false);
        // The review guards above throw sentences written for people;
        // everything else reads as "Couldn't send".
        showMessageSnackBar(
            message: userErrorCopy(context, e is StateError ? e.message : e,
                fallback: context.l10n.sendCouldNotSend),
            error: true,
            context: context);
      }
    }
  }

  /// What the user is about to approve, in the order they care about it:
  /// the amount, then where it lands, then what the network takes. Stays
  /// on screen through every signing method so the destination is never
  /// out of sight while a device is waiting.
  Widget _buildTransactionSummary(AppColorsExtension c) {
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    // Keep the reviewed values fixed even if another flow changes the shared
    // send provider while the hardware signature is pending.
    final amount = _reviewedAmount;
    final feeSats = widget.feeSatsOverride;
    final address = _reviewedRecipient;

    if (amount <= 0 && address.isEmpty) return const SizedBox.shrink();

    final amountStr = amount > 0 ? amount.toFormattedString(btcFormat) : '--';
    final feeStr = feeSats != null && feeSats > 0
        ? feeSats.toFormattedString(btcFormat)
        : null;

    return SigningSummaryCard(
      amount: '$amountStr $btcFormat',
      addressLabel: context.l10n.to,
      address: address,
      feeLabel: context.l10n.fee,
      fee: feeStr != null ? '$feeStr $btcFormat' : null,
      note: context.l10n.receiveVerifyDetailsMatchDevice,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final config = _getDeviceConfig();
    final methods = _getAvailableMethods();

    // Embedded mode — drop the Scaffold/AppBar/Stack/PopScope and
    // return only the inner Column body. The parent (confirm_send's
    // Sign step) provides the screen chrome + back navigation.
    if (widget.embedded) {
      return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: _buildSigningBody(c, config, methods, embedded: true),
      );
    }

    return PopScope(
      canPop: !_isBroadcasting && !_isLedgerSigning && !_operationBusy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: KuteBackButton(
            onPressed: () {
              if (!_isBroadcasting && !_isLedgerSigning && !_operationBusy && context.mounted) {
                context.pop();
              }
            },
          ),
          centerTitle: true,
          title: Text(_screenTitle(context), style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 18.sp)),
        ),
        body: Stack(
          children: [
            Container(decoration: AppDecorations.screenGradient(context)),
            Positioned(
              top: -100.h,
              left: 0,
              right: 0,
              height: 400.h,
              child: Container(decoration: AppDecorations.ambientGlow(context)),
            ),
            SafeArea(
              bottom: false,
              child: _buildSigningBody(c, config, methods, embedded: false),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// The signing page: what is being approved on top, the one active way
  /// of signing it underneath, and everything else folded away. Only one
  /// method is ever open, so there is a single thing to do at a time.
  Widget _buildSigningBody(
      AppColorsExtension c,
      WalletDeviceConfig? config,
      List<_SigningMethodOption> methods,
      {required bool embedded}) {
    // Once the signed PSBT/hex comes back, the signing UI becomes
    // irrelevant — swap the whole body to the ready-to-send page.
    if (_signedTxData != null) {
      return _buildReadyToBroadcast(c);
    }
    // Embedded mode tightens vertical rhythm — the parent stepper
    // (confirm_send Sign step) already provides plenty of vertical
    // chrome via the step title + the network-settings row.
    final topGap = embedded ? 4.h : 8.h;
    final tailPad = MediaQuery.of(context).viewInsets.bottom > 0
        ? 16.h
        : (embedded ? 32.h : 100.h);
    final active = _expandedMethod ?? _primaryMethod;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.symmetric(
                horizontal: widget.horizontalPadding ?? 20.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: topGap),
                _buildTransactionSummary(c),
                SizedBox(height: 12.h),
                _buildActivePanel(active, config, c),
                ..._buildOtherWays(methods, active, c),
                _buildNerdData(c),
                SizedBox(height: tailPad),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// PSBT wording lives here only: the format, size and wallet
  /// fingerprint the device is expected to match, plus the unsigned
  /// payload itself for anyone who needs to copy it.
  Widget _buildNerdData(AppColorsExtension c) {
    final psbt = _fixedPsbtBase64;
    int bytes;
    try {
      bytes = base64Decode(psbt).length;
    } catch (_) {
      bytes = 0;
    }
    final fingerprint = _sourceWallet?.masterFingerprint;
    return SheetNerdDataSection(children: [
      SheetDetailRow(label: context.l10n.hwNerdFormat, value: 'PSBT (base64)'),
      if (bytes > 0)
        SheetDetailRow(
            label: context.l10n.hwNerdSize,
            value: context.l10n.hwNerdBytes(bytes.toString())),
      if (fingerprint != null && fingerprint.isNotEmpty)
        SheetDetailRow(
            label: context.l10n.hwNerdFingerprint,
            value: fingerprint,
            copiable: true),
      SheetDetailRow(
          label: context.l10n.hwNerdUnsignedTransaction,
          value: psbt,
          truncate: true,
          copiable: true),
    ]);
  }

  /// The one method that is open, on the device card it belongs to.
  Widget _buildActivePanel(
      SigningMethod method, WalletDeviceConfig? config, AppColorsExtension c) {
    return SigningPanel(
      header: config == null
          ? null
          : SigningDeviceRow(
              title: config.titleIn(context.l10n),
              subtitle: config.subtitleIn(context.l10n),
              leading: WalletIcon(
                visual: WalletVisual(
                  svgAsset: config.svgAsset,
                  icon: config.icon,
                  color: config.color,
                ),
                size: 36,
              ),
            ),
      child: _buildMethodContent(method, c),
    );
  }

  /// Everything the active method is not, folded away behind one line.
  /// Tapping a row swaps the panel above; nothing else moves.
  List<Widget> _buildOtherWays(
      List<_SigningMethodOption> methods,
      SigningMethod active,
      AppColorsExtension c) {
    final rest = methods.where((m) => m.method != active).toList();
    if (rest.isEmpty) return const <Widget>[];
    return [
      InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _showOtherMethods = !_showOtherMethods);
          TrackingService.track('hw_sign_other_methods_toggled',
              params: {'open': _showOtherMethods});
        },
        borderRadius: BorderRadius.circular(10.r),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 6.w),
          child: Row(
            children: [
              Icon(
                _showOtherMethods
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 18.sp,
                color: c.textTertiary,
              ),
              SizedBox(width: 4.w),
              Text(
                context.l10n.hwOtherWaysToSign,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
      SheetAnimatedSize(
        child: _showOtherMethods
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final m in rest)
                    Padding(
                      padding: EdgeInsets.only(bottom: 8.h),
                      child: LedgerOptionTile(
                        icon: m.icon,
                        label: m.label,
                        onTap: _operationBusy
                            ? null
                            : () => _selectMethod(m.method),
                      ),
                    ),
                ],
              )
            : const SizedBox.shrink(),
      ),
    ];
  }

  /// Signed, not sent. One calm page with the payment still on it and the
  /// send button underneath; while the broadcast runs the same page says
  /// what is happening rather than swapping to a spinner on its own.
  Widget _buildReadyToBroadcast(AppColorsExtension c) {
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    final amountSats = _reviewedAmount;
    final amountStr =
        amountSats > 0 ? amountSats.toFormattedString(btcFormat) : '';
    final address = _reviewedRecipient;
    final shortAddress = address.length > 16
        ? '${address.substring(0, 8)}…${address.substring(address.length - 6)}'
        : address;
    final hasSummary = amountStr.isNotEmpty && address.isNotEmpty;
    // Honour the parent's horizontalPadding override (Move sheet /
    // confirm_send Sign step pass 0 because the surrounding stepper
    // already pads). Default 20.w preserves the standalone send-flow look.
    final hPad = widget.horizontalPadding ?? 20.w;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SigningStage(
                      tone: _isBroadcasting
                          ? SigningStageTone.working
                          : SigningStageTone.done,
                      icon: _isBroadcasting
                          ? Icons.north_east_rounded
                          : Icons.check_circle_outline_rounded,
                      title: _isBroadcasting
                          ? context.l10n.hwSignSendingTitle
                          : context.l10n.hwSignReadyTitle,
                      body: _isBroadcasting
                          ? context.l10n.hwSignSendingBody
                          : (hasSummary
                              ? context.l10n.receiveSendingBitcoinTo(
                                  amountStr, btcFormat, shortAddress)
                              : context.l10n.hwSignReadyBody),
                    ),
                    if (!_isBroadcasting && hasSummary) ...[
                      SizedBox(height: 10.h),
                      Text(
                        context.l10n.hwSignReadyBody,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 13.sp,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              text: context.l10n.sendTransaction,
              onPressed: _isBroadcasting ? null : _onBroadcast,
              isLoading: _isBroadcasting,
              icon: Icons.send_rounded,
            ),
          ),
          // The signed transaction is ready, so the only thing left to
          // do is send it. The escape hatch back to the method panel
          // used to sit here; it offered to throw away a signature the
          // device had just produced, which is not a choice this step
          // should be putting in front of anyone (user decision
          // September 2026). Backing out of the step is still the way
          // to change method.
          // Standalone mode honours the device SafeArea bottom inset.
          // Embedded callers (Move sheet, confirm_send Sign step) sit
          // inside a SafeArea / stepper that already handles it.
          SizedBox(
              height: (widget.embedded
                      ? 16.h
                      : MediaQuery.of(context).padding.bottom + 16.h)),
        ],
      ),
    );
  }

  Widget _buildMethodContent(SigningMethod method, AppColorsExtension c) {
    switch (method) {
      case SigningMethod.qrCode:
        return _buildQrContent(c);
      case SigningMethod.sdCard:
        return _buildSdContent(c);
      case SigningMethod.ledger:
        return _buildDeviceContent(c);
      case SigningMethod.clipboard:
        return _buildClipboardContent(c);
    }
  }

  Widget _buildQrContent(AppColorsExtension c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SigningHint(
            context.l10n.showThisQrCodeToYourSigningDeviceAndLetItScanAllFrames),
        if (widget.walletType == 'jade')
          Padding(
            padding: EdgeInsets.only(bottom: 10.h),
            child: InkWell(
              onTap: () => launchUrl(
                Uri.parse('https://jadefw.blockstream.com/pinqr/qrpin.html'),
                mode: LaunchMode.externalApplication,
              ),
              borderRadius: BorderRadius.circular(8.r),
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: c.borderSubtle),
                ),
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, size: 14.sp, color: c.textSecondary),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        context.l10n.receiveUsingQrPinUnlockJade,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        AnimatedQrView(
          psbtString: _fixedPsbtBase64,
          // Legacy tolerance: wallets stored with the retired
          // 'coldcard' type still get BBQr frames (the only format
          // those devices scan) so existing users can keep signing.
          // Everything else uses BC-UR.
          format: widget.walletType.toLowerCase().contains('coldcard')
              ? QrPsbtFormat.bbqr
              : QrPsbtFormat.ur,
        ),
        SizedBox(height: 18.h),
        SigningHint(context
            .l10n.afterYourDeviceSignsTheTransactionScanTheSignedQrCodeItDisplays),
        AppButton(
          text: context.l10n.scanSignedQr,
          onPressed: _onScanSignedTx,
          icon: Icons.camera_alt,
          compact: true,
        ),
      ],
    );
  }

  Widget _buildSdContent(AppColorsExtension c) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SigningHint(context.l10n.hwExportUnsignedTransactionStep),
        AppButton(
          text: _sdStep1Done
              ? context.l10n.exported
              : context.l10n.hwSaveUnsignedTransaction,
          onPressed: _exportFile,
          icon: _sdStep1Done ? Icons.check_circle : Icons.file_download_outlined,
          // Demotes to the quiet tier once done — the primary
          // emphasis moves down to the import step.
          variant: _sdStep1Done
              ? AppButtonVariant.secondary
              : AppButtonVariant.primary,
          compact: true,
        ),
        SizedBox(height: 18.h),
        SigningHint(
            context.l10n.loadTheFileOnYourSigningDeviceAndApproveTheTransaction),
        SizedBox(height: 8.h),
        // Step three only lights up once the file has actually left.
        AnimatedOpacity(
          opacity: _sdStep1Done ? 1.0 : 0.4,
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SigningHint(context.l10n.importTheSignedFileBackFromYourSdCard),
              AppButton(
                text: context.l10n.importSignedFile,
                onPressed: _sdStep1Done ? _onImportFile : null,
                icon: Icons.folder_open,
                compact: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The flagship: a Ledger (or Jade) over Bluetooth. Idle asks for one
  /// tap, busy says what the device is doing, a failure says what went
  /// wrong and offers the way out. Never more than one of the three.
  Widget _buildDeviceContent(AppColorsExtension c) {
    final isJade = widget.walletType == 'jade';
    final l10n = context.l10n;
    final start = isJade ? _handleJadeSigning : _handleLedgerSigning;

    if (_isLedgerSigning) {
      final stage = _deviceStage ?? _DeviceStage.connecting;
      final String title;
      final String body;
      switch (stage) {
        case _DeviceStage.connecting:
          title = l10n.ledgerApprovalConnectingTitle;
          body = l10n.hwSignKeepDeviceNearby(
              _deviceName ?? (isJade ? 'Jade' : 'Ledger'));
        case _DeviceStage.unlock:
          title = l10n.hwSignUnlockJadeTitle;
          body = l10n.hwSignUnlockJadeBody;
        case _DeviceStage.approve:
          title = isJade ? l10n.hwApproveOnJade : l10n.hwApproveOnLedger;
          body = isJade
              ? l10n.receiveVerifyOnJadeScreenBeforeConfirming
              : l10n.receiveVerifyOnLedgerScreenBeforeConfirming;
      }
      return SigningStage(
        tone: SigningStageTone.working,
        icon: Icons.shield_outlined,
        title: title,
        body: body,
      );
    }

    if (_deviceFailure != null) {
      return SigningStage(
        tone: SigningStageTone.problem,
        icon: Icons.error_outline_rounded,
        title: l10n.ledgerApprovalFailedTitle,
        body: _deviceFailure,
        actions: [
          AppButton(
            text: l10n.tryAgain,
            icon: Icons.refresh_rounded,
            compact: true,
            onPressed: _operationBusy
                ? null
                : () {
                    TrackingService.track('hw_sign_retry', params: {
                      'signer_type': isJade ? 'jade' : 'ledger',
                    });
                    start();
                  },
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SigningHint(isJade
            ? l10n.turnOnYourJadeAndEnableBluetooth
            : l10n.ledgerApprovalScanningBody),
        AppButton(
          // The picker sheet is already up while `_operationBusy` is on;
          // the button greys out rather than sitting live behind it.
          text: l10n.connectSign,
          onPressed: _operationBusy ? null : start,
          icon: Icons.bluetooth_searching,
          compact: true,
        ),
      ],
    );
  }

  Widget _buildClipboardContent(AppColorsExtension c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SigningHint(context.l10n.hwCopyUnsignedTransactionStep),
        // One button instead of the base64 blob; the payload itself
        // stays readable and copiable in the Nerd data section below.
        AppButton(
          text: context.l10n.hwCopyUnsignedTransaction,
          icon: Icons.copy_rounded,
          variant: AppButtonVariant.secondary,
          compact: true,
          onPressed: _copyPsbt,
        ),
        SizedBox(height: 18.h),
        SigningHint(context.l10n.signTheTransactionWithYourExternalToolOrDevice),
        SigningHint(context.l10n.pasteTheSignedTransactionBelowAndSubmit),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: c.borderSubtle),
          ),
          child: TextField(
            controller: _pasteController,
            focusNode: _pasteFocusNode,
            maxLines: 3,
            style: TextStyle(
                color: c.textPrimary, fontSize: 14.sp, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: context.l10n.pasteSignedTransactionHere,
              hintStyle: TextStyle(color: c.textTertiary, fontSize: 14.sp),
              contentPadding: EdgeInsets.all(10.w),
              border: InputBorder.none,
            ),
          ),
        ),
        SizedBox(height: 10.h),
        Row(
          children: [
            Expanded(
              // Quiet picker → secondary tier, compact for the row.
              child: AppButton(
                text: context.l10n.paste,
                icon: Icons.paste,
                variant: AppButtonVariant.secondary,
                compact: true,
                fontSize: 15.sp,
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    _pasteController.text = data!.text!;
                  }
                },
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: AppButton(
                text: context.l10n.submit,
                compact: true,
                fontSize: 15.sp,
                onPressed: _onSubmitPastedTx,
              ),
            ),
          ],
        ),
      ],
    );
  }

}

/// The moment a Bluetooth signing device is in. Names the sentence on
/// screen, nothing else.
enum _DeviceStage { connecting, unlock, approve }

class _SigningMethodOption {
  final SigningMethod method;
  final IconData icon;
  final String label;

  const _SigningMethodOption({
    required this.method,
    required this.icon,
    required this.label,
  });
}
