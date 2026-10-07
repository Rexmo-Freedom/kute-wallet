import 'dart:async';

import 'package:kute/controllers/import_wallet_controller.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/helpers/common_operation_methods.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/helpers/qr_gallery_helper.dart';
import 'package:kute/helpers/scanned_address.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:kute/models/add_wallet_model.dart';
import 'package:kute/models/send_tx_model.dart';
import 'package:kute/providers/add_wallet_provider.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/services/add_wallet_capabilities.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/l10n/l10n.dart';

class SmartScannerScreen extends ConsumerStatefulWidget {
  /// When true, the scanner does NOT route the scanned payload itself
  /// (no xpub import, no confirm_send push, no cross-chain handling).
  /// Instead it pops with the raw scanned/pasted string so the caller
  /// can process it in its own context. Used by the in-flow "Scan"
  /// button on the Send screen so we reuse this richer scanner (paste,
  /// "scan any QR") without stacking a second confirm_send on top of
  /// the one already open.
  final bool returnRawValue;

  const SmartScannerScreen({super.key, this.returnRawValue = false});

  @override
  ConsumerState<SmartScannerScreen> createState() => _SmartScannerScreenState();
}

class _SmartScannerScreenState extends ConsumerState<SmartScannerScreen>
    with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  bool _cameraError = false;

  /// Camera permission is denied (or permanently denied), so retrying the
  /// controller can never succeed; the only way out is the OS Settings.
  bool _cameraDenied = false;

  static final _xpubRegex =
      RegExp(r'^[xyzvtmu]pub[1-9A-HJ-NP-Za-km-z]{100,108}$');
  static final _descriptorRegex = RegExp(
      r'^(tr|wpkh|sh\(wpkh|pkh)\(.*[xyzvtmu]pub[1-9A-HJ-NP-Za-km-z]+.*\)$');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController();
    // mobile_scanner v7 doesn't reliably auto-start, and reopening the
    // scanner right after a previous instance is still releasing the camera
    // trips an "in use" error. Arm explicitly with retry.
    _safeStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Release the camera ASAP so reopening (scan → pay → scan again) doesn't
    // hit "camera already in use". `dispose()` is async in v7; detach our
    // reference and fire it so the OS frees the camera as fast as it can.
    final c = _controller;
    _controller = null;
    unawaited(c?.dispose());
    super.dispose();
  }

  /// Stop the camera when the app backgrounds and re-arm on resume —
  /// otherwise the camera stays held while backgrounded and a foreground
  /// reopen reports it "in use".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_isProcessing) _safeStart();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(c.stop());
        break;
    }
  }

  /// Start the camera, tolerating the transient "camera already in use" the
  /// OS reports while a previous scanner instance is still releasing it
  /// (reopen after a pay). Retries with a short backoff instead of leaving a
  /// dead grey preview; surfaces a tap-to-retry card if it never frees.
  ///
  /// A denied camera permission is not transient: retrying would loop
  /// forever, so it is detected (via the scanner's own error code and
  /// permission_handler) and surfaced as an "open Settings" notice instead.
  Future<void> _safeStart() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      if (!mounted || _controller == null) return;
      try {
        await _controller!.start();
        if (mounted && (_cameraError || _cameraDenied)) {
          setState(() {
            _cameraError = false;
            _cameraDenied = false;
          });
        }
        return;
      } on MobileScannerException catch (e) {
        if (e.errorCode == MobileScannerErrorCode.permissionDenied) break;
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    final denied = await _isCameraDenied();
    if (!mounted) return;
    setState(() {
      _cameraDenied = denied;
      _cameraError = !denied;
    });
  }

  Future<bool> _isCameraDenied() async {
    try {
      final status = await Permission.camera.status;
      return status.isDenied ||
          status.isPermanentlyDenied ||
          status.isRestricted;
    } catch (_) {
      return false;
    }
  }

  /// Send the user to the OS app settings to re-enable the camera. The
  /// scanner re-arms on the next app resume (see
  /// [didChangeAppLifecycleState]), so coming back with access granted
  /// drops straight into a live preview.
  Future<void> _openCameraSettings() async {
    HapticFeedback.lightImpact();
    TrackingService.track('scanner_open_camera_settings');
    await openAppSettings();
  }

  /// Tap-to-retry handler — the failed controller is in a bad state, so swap
  /// in a fresh one and re-arm.
  Future<void> _retryCamera() async {
    final old = _controller;
    setState(() {
      _controller = MobileScannerController();
      _cameraError = false;
    });
    unawaited(old?.dispose());
    _safeStart();
  }

  void _popSafely() {
    if (context.mounted) context.pop();
  }

  /// Push into the send-confirm flow, then re-arm the scanner once the
  /// user navigates back. `context.push` only completes when
  /// confirm_send is popped, so without re-arming here the scanner
  /// stays frozen on the "Processing…" overlay with the camera stopped
  /// (set in `_onDetect`). Resetting on return drops the user straight
  /// back into a live scanner instead of a dead grey card.
  Future<void> _pushToConfirmSend() async {
    if (!mounted) return;
    TrackingService.markEntrySource('send', 'scanner');
    await context.push('/home/pay/confirm_send');
    if (mounted) {
      setState(() => _isProcessing = false);
      _safeStart();
    }
  }

  bool get _isSparkWallet {
    return ref.read(selectedAccountProvider)?.wallet?.isSparkWallet ?? false;
  }

  /// On-chain accounts use their own address parser, never the Spark wallet.
  bool get _needsManualParse {
    return !_isSparkWallet;
  }

  static String? _extractLightningParam(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed != null) {
      final ln = parsed.queryParameters['lightning'];
      if (ln != null && ln.isNotEmpty) return ln;
    }
    return null;
  }

  /// Lowercase an all-uppercase bech32 LNURL / BOLT11 token so Breez's
  /// parser accepts it. bech32 is case-insensitive but must be single-
  /// case; QR encoders (Wallet of Satoshi etc.) emit uppercase. Handles
  /// an optional `lightning:` scheme prefix. Anything else (addresses,
  /// EVM checksummed hex, lightning addresses) is returned untouched so
  /// we never corrupt case-sensitive payloads.
  static String _normalizeBech32Case(String raw) {
    final s = raw.trim();
    final scheme = RegExp(r'^lightning:', caseSensitive: false).firstMatch(s);
    final token = scheme != null ? s.substring(scheme.end) : s;
    final upper = token.toUpperCase();
    final isBech32Ln = upper.startsWith('LNURL') ||
        upper.startsWith('LNBC') ||
        upper.startsWith('LNTB') ||
        upper.startsWith('LNBCRT');
    // Only normalize when the token is entirely uppercase (mixed case is
    // either invalid bech32 or a case-sensitive payload — leave it be).
    if (isBech32Ln && token == upper) {
      final lowered = token.toLowerCase();
      return scheme != null ? 'lightning:$lowered' : lowered;
    }
    return s;
  }

  /// Convert a LUD-17 scheme URL into the plain HTTP(S) URL the LNURL
  /// fetcher expects. LNURL vouchers are shared in two equivalent forms:
  /// the bech32 `LNURL1…` blob (handled by [_normalizeBech32Case]) and
  /// the LUD-17 direct URL (`lnurlw://`, `lnurlp://`, `lnurlc://`,
  /// `lnurla://`, `keyauth://`). Per LUD-17 the scheme maps to `https`,
  /// except `.onion` hosts which use `http`. A bech32 LNURL decodes to
  /// exactly this `https://host/path`, so converting here routes the
  /// LUD-17 form through the identical, already-working SDK parse path.
  /// Non-LUD-17 input is returned untouched.
  static String _normalizeLud17Scheme(String raw) {
    final s = raw.trim();
    final m = RegExp(r'^(lnurlw|lnurlp|lnurlc|lnurla|keyauth)://',
            caseSensitive: false)
        .firstMatch(s);
    if (m == null) return s;
    final rest = s.substring(m.end);
    final host = rest.split(RegExp(r'[/?#]')).first.toLowerCase();
    final proto = host.endsWith('.onion') ? 'http' : 'https';
    return '$proto://$rest';
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    final code = barcode?.rawValue?.trim();
    if (code == null || code.isEmpty) return;

    setState(() => _isProcessing = true);
    await _controller?.stop();
    HapticFeedback.mediumImpact();

    try {
      await _processInput(code);
    } catch (e) {
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: userErrorCopy(context, e,
              fallback: context.l10n.scanCouldNotRead),
          error: true,
        );
        setState(() => _isProcessing = false);
        _safeStart();
      }
    }
  }

  Future<void> _processInput(String rawInput) async {
    // Normalize bech32 LNURL case. LNURL (and BOLT11 invoices) are
    // case-insensitive bech32, but many wallets — Wallet of Satoshi
    // included — encode them UPPERCASE in the QR (alphanumeric mode is
    // denser). Breez's parser only accepts lowercase, so an uppercase
    // `LNURL1…` scans as "not recognized". Lower it before any routing.
    // Also fold LUD-17 scheme URLs (`lnurlw://` etc.) into plain HTTP(S)
    // so a withdraw voucher shared as a URL resolves like its bech32
    // `LNURL1…` twin.
    final input = _normalizeBech32Case(_normalizeLud17Scheme(rawInput));

    // Return-value mode: hand the raw payload back to the caller and
    // stop. The caller (the Send screen's in-flow Scan button) runs
    // its own paste/commit pipeline against it, so we deliberately
    // skip all the routing below.
    if (widget.returnRawValue) {
      if (mounted) context.pop(input);
      return;
    }

    // 1. xpub / zpub / ypub or output descriptor — hardware wallet import
    if (_xpubRegex.hasMatch(input) || _descriptorRegex.hasMatch(input)) {
      TrackingService.track('scan_payload_identified',
          params: {'payload_type': 'xpub'});
      await _handleXpubImport(input);
      return;
    }

    // 2. Hardware / watch-only wallets: skip Breez SDK (no mnemonic available).
    //    Parse input manually using regex patterns.
    if (_needsManualParse) {
      // _processInputManually fires its own scan_payload_identified
      // event with the resolved type per branch.
      await _processInputManually(input);
      return;
    }

    // 3. Unified BIP21 with lightning= parameter: extract lightning part
    //    for Spark wallets before hitting Breez SDK (SDK may misidentify it).
    if (_isSparkWallet &&
        input.toLowerCase().startsWith('bitcoin:') &&
        input.toLowerCase().contains('lightning=')) {
      final lnParam = _extractLightningParam(input);
      if (lnParam != null && lnParam.isNotEmpty) {
        TrackingService.track('scan_payload_identified',
            params: {'payload_type': 'ln_invoice'});
        await _handleLightning(lnParam);
        return;
      }
    }

    // 4. Breez SDK parse — Lightning, Bitcoin, BIP21, Spark
    final analysis = await ref
        .read(identifyInputTypeProvider(input).future)
        .timeout(const Duration(seconds: 10),
            onTimeout: () => AnalyzedPaymentType.unknown);

    switch (analysis) {
      case AnalyzedPaymentType.lightning:
      case AnalyzedPaymentType.lnurl:
        TrackingService.track('scan_payload_identified',
            params: {'payload_type': 'ln_invoice'});
        await _handleLightning(input);
        return;

      case AnalyzedPaymentType.bitcoin:
        TrackingService.track('scan_payload_identified',
            params: {'payload_type': 'bitcoin_address'});
        await _handleBitcoin(input);
        return;

      case AnalyzedPaymentType.bip21:
        TrackingService.track('scan_payload_identified',
            params: {'payload_type': 'bip21'});
        await _handleBip21(input);
        return;

      case AnalyzedPaymentType.spark:
        TrackingService.track('scan_payload_identified',
            params: {'payload_type': 'spark_address'});
        await _handleSpark(input);
        return;

      case AnalyzedPaymentType.unknown:
        TrackingService.track('scan_payload_identified',
            params: {'payload_type': 'external_address'});
        // 4. Fallback: if Breez doesn't recognize it, treat as external address
        //    (could be Solana, ETH, or any altcoin for cross-chain swaps)
        await _handleExternalAddress(input);
        return;
    }
  }

  /// Manual input parsing for hardware / watch-only wallets that can't use Breez SDK.
  /// Handles BIP21, Bitcoin addresses, and cross-chain addresses.
  Future<void> _processInputManually(String input) async {
    final notifier = ref.read(sendTxProvider.notifier);
    final lower = input.toLowerCase();

    // BIP21 URI: bitcoin:ADDRESS?lightning=...&amount=...
    if (lower.startsWith('bitcoin:')) {
      final stripped =
          input.replaceFirst(RegExp(r'^bitcoin:', caseSensitive: false), '');
      final parts = stripped.split('?');
      final address = parts[0];
      int amount = 0;

      if (parts.length > 1) {
        final params = Uri.splitQueryString(parts[1]);
        final amountBtc = double.tryParse(params['amount'] ?? '');
        if (amountBtc != null) amount = (amountBtc * 100000000).round();
      }

      TrackingService.qrScanned('bip21');
      notifier.updateAddress(address);
      notifier.updateAmount(amount);
      notifier.updatePaymentType(PaymentType.Bitcoin);
      if (mounted) await _pushToConfirmSend();
      return;
    }

    // On-chain Bitcoin address
    if (_bitcoinRegex.hasMatch(input)) {
      TrackingService.qrScanned('bitcoin');
      notifier.updateAddress(input);
      notifier.updateAmount(0);
      notifier.updatePaymentType(PaymentType.Bitcoin);
      if (mounted) await _pushToConfirmSend();
      return;
    }

    // Everything else: cross-chain swap
    await _handleExternalAddress(input);
  }

  Future<void> _handleXpubImport(String xpub) async {
    TrackingService.qrScanned('xpub');
    final walletState = ref.read(addWalletProvider);
    final configs = walletState.coldWallets;

    // Every device row here answers to `hardware.wallet`. While Kute
    // withholds it the import does not start: the shared unavailable
    // sheet says why, then the scanner resumes.
    final denial = await addWalletOptionDenial(
        ref.read(runtimeCapabilitiesProvider), 'generic');
    if (!mounted) return;
    if (denial != null) {
      await showCapabilityDecisionSheet(context, denial);
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _safeStart();
      return;
    }

    final selected = await showAppBottomSheet<WalletDeviceConfig>(
      context: context,
      builder: (_) => _XpubWalletPicker(configs: configs),
    );

    if (selected == null) {
      // User dismissed — restart scanner
      setState(() => _isProcessing = false);
      _safeStart();
      return;
    }

    if (!mounted) return;
    // Capture the root navigator and the strings before the scanner
    // pops: the confirmation is pushed once this screen is gone, exactly
    // like the Lightning withdrawal below.
    final navigator = Navigator.of(context, rootNavigator: true);
    final l10n = context.l10n;
    try {
      await ref.read(importWalletControllerProvider.notifier).importXpub(
            xpub: xpub,
            config: selected,
          );
      if (!mounted) return;
      _popSafely();
      pushKuteSuccessOverlay(
        navigator: navigator,
        overlay: KuteConfirmation(
          message: l10n.walletImportedConfirmation,
          detail: l10n.walletImportedWithOthers(selected.title),
          onDone: navigator.pop,
        ),
      );
    } catch (e) {
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: userErrorCopy(context, e,
              fallback: context.l10n.walletImportCouldNotImport),
          error: true,
        );
        setState(() => _isProcessing = false);
        _safeStart();
      }
    }
  }

  Future<void> _handleLightning(String input) async {
    TrackingService.qrScanned('lightning');
    if (!_isSparkWallet) {
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.scanOnlyFromSpendingWallet,
          error: true,
        );
        _popSafely();
      }
      return;
    }

    final parsed = await ref.read(parseInputProvider(input).future);

    // LNURL-withdraw is a RECEIVE, not a send — the remote service pays
    // us. Never route it into confirm_send. Pull the funds via the Breez
    // SDK and show the receive-style success overlay instead.
    if (parsed is spark.InputType_LnurlWithdraw) {
      await _handleLnurlWithdraw(parsed.field0);
      return;
    }

    final notifier = ref.read(sendTxProvider.notifier);
    int amount = 0;

    if (parsed is spark.InputType_Bolt11Invoice) {
      amount = parsed.field0.amountMsat != null
          ? (parsed.field0.amountMsat! ~/ BigInt.from(1000)).toInt()
          : 0;
    } else if (parsed is spark.InputType_Bolt12Offer) {
      if (parsed.field0.minAmount is spark.Amount_Bitcoin) {
        final amt = parsed.field0.minAmount as spark.Amount_Bitcoin;
        amount = (amt.amountMsat ~/ BigInt.from(1000)).toInt();
      }
    }

    notifier.updateAddress(input);
    notifier.updateAmount(amount);
    notifier.updatePaymentType(PaymentType.Lightning);

    if (mounted) await _pushToConfirmSend();
  }

  /// LNURL-withdraw: the remote service pays US. Pull the max allowed via
  /// the Breez SDK and show the receive-style success overlay. Never
  /// routes into confirm_send (that's a send flow).
  Future<void> _handleLnurlWithdraw(
      spark.LnurlWithdrawRequestDetails details) async {
    TrackingService.qrScanned('lnurl_withdraw');

    if (!_isSparkWallet) {
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.scanOnlyFromSpendingWallet,
          error: true,
        );
        _popSafely();
      }
      return;
    }

    // min/maxWithdrawable are in millisats; the SDK takes sats. Claim the
    // maximum the request allows (most withdraw requests are fixed-amount,
    // i.e. min == max).
    final maxSats = (details.maxWithdrawable ~/ BigInt.from(1000)).toInt();
    if (maxSats <= 0) {
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.receiveWithdrawalNoBalance,
          error: true,
        );
        setState(() => _isProcessing = false);
        _safeStart();
      }
      return;
    }

    // Capture the root navigator now so the overlay can be pushed after
    // the scanner pops (its own context is gone by then). Same for the
    // localizations — the overlay strings must resolve before the pop.
    final navigator = Navigator.of(context, rootNavigator: true);
    final l10n = context.l10n;

    // J10 (Wallet Hardening Phase 1b): pulling an LNURL withdrawal into this
    // wallet is session only. It never prompts and never runs behind the
    // lock.
    if (!ref.read(sessionUnlockedProvider)) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _safeStart();
      }
      return;
    }

    try {
      final sdkWrapper = await ref.read(breezSDKProvider.future);
      final sdk = sdkWrapper.instance!;
      await sdk.lnurlWithdraw(
        request: spark.LnurlWithdrawRequest(
          amountSats: BigInt.from(maxSats),
          withdrawRequest: details,
        ),
      );
      TrackingService.track('lnurl_withdraw_success');
      if (!mounted) return;
      _popSafely();
      pushKuteSuccessOverlay(
        navigator: navigator,
        overlay: KuteSuccessOverlay(
          // Same Lightning logo the send-success modal uses
          // (`getAssetImage('Lightning')`), so a withdraw and a send
          // read as the same rail. Keeps the green bolt as a fallback.
          icon: const KuteIconSpec(
            assetImage: 'lib/assets/Bitcoin_lightning_logo.png',
            fallbackIcon: Icons.bolt_rounded,
            // No green backing disc on the Lightning receive overlay.
            tintDisc: false,
          ),
          headlineLabel: l10n.received,
          amount: '${_formatSats(maxSats)} sats',
          subtitle: l10n.receiveLightningWithdrawal,
          onDone: navigator.pop,
        ),
      );
    } catch (e) {
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: _humanizeWithdrawError(e),
          error: true,
        );
        setState(() => _isProcessing = false);
        _safeStart();
      }
    }
  }

  /// Turn a raw LNURL-withdraw SDK error into a short, user-facing
  /// reason. The previous `catch (_)` swallowed everything into a blank
  /// "try again", which hid the common case: withdraw vouchers
  /// (LNbits, ATMs) are usually single-use, so the second attempt 4xxs
  /// as already-spent. Surfacing the reason makes that actionable;
  /// anything else reads as a plain sentence, never the raw SDK text.
  String _humanizeWithdrawError(Object e) {
    final s = e.toString();
    final lower = s.toLowerCase();
    if (lower.contains('already') ||
        lower.contains('spent') ||
        lower.contains('used') ||
        lower.contains('no available') ||
        lower.contains('exhaust')) {
      return context.l10n.receiveWithdrawalLinkAlreadyUsed;
    }
    if (lower.contains('expired')) {
      return context.l10n.receiveWithdrawalLinkExpired;
    }
    if (lower.contains('network') ||
        lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('connection') ||
        lower.contains('socket') ||
        lower.contains('dns')) {
      return context.l10n.receiveWithdrawalServiceUnreachable;
    }
    return userErrorCopy(context, e,
        fallback: context.l10n.receiveWithdrawalCouldNotClaim);
  }

  /// Group a sats integer with thousands separators ("12,345").
  String _formatSats(int sats) {
    final s = sats.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Future<void> _handleBitcoin(String input) async {
    TrackingService.qrScanned('bitcoin');
    final parsed = await ref.read(parseInputProvider(input).future);
    final notifier = ref.read(sendTxProvider.notifier);
    // Always store the BARE address — strip the bitcoin: scheme + BIP21
    // query. When the SDK returns a structured address use that (also
    // bare); otherwise fall back to the stripped raw input rather than
    // the prefixed string, which the on-chain fee calc rejects.
    String address = stripBitcoinAddress(input);

    if (parsed is spark.InputType_BitcoinAddress) {
      address = parsed.field0.address;
    }

    notifier.updateAddress(address);
    notifier.updateAmount(0);
    notifier.updatePaymentType(PaymentType.Bitcoin);

    if (mounted) await _pushToConfirmSend();
  }

  Future<void> _handleBip21(String input) async {
    TrackingService.qrScanned('bip21');
    final parsed = await ref.read(parseInputProvider(input).future);
    final notifier = ref.read(sendTxProvider.notifier);

    if (parsed is spark.InputType_Bip21) {
      final bip21 = parsed.field0;
      final amountSat = bip21.amountSat?.toInt() ?? 0;
      final methods = bip21.paymentMethods;

      if (_isSparkWallet) {
        // Prefer Lightning on Spark wallets
        for (final method in methods) {
          if (method is spark.InputType_Bolt11Invoice) {
            final invoiceAmount = method.field0.amountMsat != null
                ? (method.field0.amountMsat! ~/ BigInt.from(1000)).toInt()
                : amountSat;
            notifier.updateAddress(method.field0.invoice.bolt11);
            notifier.updateAmount(invoiceAmount);
            notifier.updatePaymentType(PaymentType.Lightning);
            if (mounted) await _pushToConfirmSend();
            return;
          }
        }
        // Try LNURL / Lightning Address (used by joint QR codes)
        for (final method in methods) {
          if (method is spark.InputType_LnurlPay) {
            final lnAddress = method.field0.address;
            final addr = (lnAddress != null && lnAddress.isNotEmpty)
                ? lnAddress
                : _extractLightningParam(bip21.uri);
            if (addr != null && addr.isNotEmpty) {
              notifier.updateAddress(addr);
              notifier.updateAmount(amountSat);
              notifier.updatePaymentType(PaymentType.Lightning);
              if (mounted) await _pushToConfirmSend();
              return;
            }
          } else if (method is spark.InputType_LightningAddress) {
            notifier.updateAddress(method.field0.address);
            notifier.updateAmount(amountSat);
            notifier.updatePaymentType(PaymentType.Lightning);
            if (mounted) await _pushToConfirmSend();
            return;
          }
        }
        // Fallback: extract lightning param directly from URI
        final lnParam = _extractLightningParam(bip21.uri);
        if (lnParam != null && lnParam.isNotEmpty) {
          notifier.updateAddress(lnParam);
          notifier.updateAmount(amountSat);
          notifier.updatePaymentType(PaymentType.Lightning);
          if (mounted) await _pushToConfirmSend();
          return;
        }
        // Try Spark
        for (final method in methods) {
          if (method is spark.InputType_SparkAddress) {
            notifier.updateAddress(method.field0.address);
            notifier.updateAmount(amountSat);
            notifier.updatePaymentType(PaymentType.Spark);
            if (mounted) await _pushToConfirmSend();
            return;
          } else if (method is spark.InputType_SparkInvoice) {
            notifier.updateAddress(method.field0.invoice);
            notifier.updateAmount(method.field0.amount?.toInt() ?? amountSat);
            notifier.updatePaymentType(PaymentType.Spark);
            if (mounted) await _pushToConfirmSend();
            return;
          }
        }
      }

      // Default / Hardware: use on-chain Bitcoin
      for (final method in methods) {
        if (method is spark.InputType_BitcoinAddress) {
          notifier.updateAddress(method.field0.address);
          notifier.updateAmount(amountSat);
          notifier.updatePaymentType(PaymentType.Bitcoin);
          if (mounted) await _pushToConfirmSend();
          return;
        }
      }

      // Last resort: parse URI directly
      final uri = Uri.tryParse(bip21.uri);
      final address = uri?.path ??
          bip21.uri
              .replaceFirst(RegExp(r'^bitcoin:', caseSensitive: false), '')
              .split('?')[0];
      notifier.updateAddress(address);
      notifier.updateAmount(amountSat);
      notifier.updatePaymentType(PaymentType.Bitcoin);
      if (mounted) await _pushToConfirmSend();
    } else {
      // Fallback
      notifier.updateAddress(input);
      notifier.updateAmount(0);
      notifier.updatePaymentType(PaymentType.Bitcoin);
      if (mounted) await _pushToConfirmSend();
    }
  }

  Future<void> _handleSpark(String input) async {
    TrackingService.qrScanned('spark');
    if (!_isSparkWallet) {
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.scanOnlyFromSpendingWallet,
          error: true,
        );
        _popSafely();
      }
      return;
    }

    final parsed = await ref.read(parseInputProvider(input).future);
    final notifier = ref.read(sendTxProvider.notifier);
    String address = input;
    int amount = 0;

    if (parsed is spark.InputType_SparkAddress) {
      address = parsed.field0.address;
    } else if (parsed is spark.InputType_SparkInvoice) {
      address = parsed.field0.invoice;
      amount = parsed.field0.amount?.toInt() ?? 0;
    }

    notifier.updateAddress(address);
    notifier.updateAmount(amount);
    notifier.updatePaymentType(PaymentType.Spark);

    if (mounted) await _pushToConfirmSend();
  }

  /// Matches Bitcoin on-chain addresses (mainnet + testnet).
  static final _bitcoinRegex = RegExp(
    r'^(bc1|tb1|bcrt1)[a-z0-9]{25,}$|' // bech32 / bech32m
    r'^[13][1-9A-HJ-NP-Za-km-z]{25,34}$|' // P2PKH / P2SH
    r'^(bitcoin:)', // BIP21 URI
    caseSensitive: false,
  );

  /// Matches Lightning invoices / LNURL / Lightning addresses.
  static final _lightningRegex = RegExp(
    r'^(lnbc|lntb|lnurl|lightning:)',
    caseSensitive: false,
  );

  Future<void> _handleExternalAddress(String input) async {
    // `qr_scanned` fires once per scan: the Bitcoin / Lightning guards
    // below hand off to handlers that report their own type, so
    // 'external' is only logged for a truly external address.

    // Guard: if this looks like a Bitcoin address (Breez SDK timed out
    // or failed to parse), handle it as on-chain Bitcoin, not cross-chain.
    if (_bitcoinRegex.hasMatch(input)) {
      await _handleBitcoin(input);
      return;
    }

    // Guard: if this looks like a Lightning invoice/LNURL, handle natively.
    if (_lightningRegex.hasMatch(input)) {
      await _handleLightning(input);
      return;
    }

    TrackingService.qrScanned('external');
    if (!mounted) return;

    // Everything else: cross-chain swap.
    // Show message and navigate to confirm screen which will auto-open
    // the destination network picker for the user to choose.
    showMessageSnackBar(
      context: context,
      message: context.l10n.scanAddressOnAnotherNetwork,
      error: false,
    );

    final notifier = ref.read(sendTxProvider.notifier);
    // A cross-chain payment URI (`ethereum:0x…@8453`, `solana:…`) is
    // stored as its bare recipient so Send validates the address itself.
    notifier.updateAddress(bareCrossChainRecipient(input));
    notifier.updateAmount(0);
    notifier.updatePaymentType(PaymentType.NonNative);

    if (mounted) await _pushToConfirmSend();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.clipboardEmpty,
          error: true,
        );
      }
      return;
    }

    setState(() => _isProcessing = true);
    await _controller?.stop();

    try {
      await _processInput(text);
    } catch (e) {
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: userErrorCopy(context, e,
              fallback: context.l10n.scanCouldNotReadClipboard),
          error: true,
        );
        setState(() => _isProcessing = false);
        _safeStart();
      }
    }
  }

  /// Pick a QR image from the gallery and run it through the same
  /// detection pipeline as a live scan / paste. Handy on devices with
  /// no camera (simulator) or when the user has a saved QR screenshot.
  ///
  /// We deliberately do NOT stop/start the live `_controller` here:
  /// the decode runs on a separate controller inside
  /// [QrGalleryHelper], and opening the OS file picker backgrounds the
  /// app, so `MobileScanner` already auto-stops/restarts the camera via
  /// its lifecycle. Calling `start()` ourselves on top of that threw
  /// "MobileScannerController is already running". `_isProcessing`
  /// alone is enough to gate `_onDetect` while we're busy.
  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final code = await QrGalleryHelper.pickAndDecode();
      if (!mounted) return;
      if (code == null || code.isEmpty) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.receiveNoQrCodeFoundInImage,
          error: true,
        );
        setState(() => _isProcessing = false);
        return;
      }
      await _processInput(code);
    } catch (e) {
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: userErrorCopy(context, e,
              fallback: context.l10n.scanCouldNotRead),
          error: true,
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep sendTxProvider alive while this screen is on the navigation stack,
    // so the state survives the push to the confirm screen (autoDispose).
    ref.watch(sendTxProvider);
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        leading: KuteBackButton(onPressed: _popSafely),
        actions: [
          IconButton(
            icon: Icon(Icons.flash_on, color: c.textSecondary),
            onPressed: () {
              HapticFeedback.lightImpact();
              _controller?.toggleTorch();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20.r),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  MobileScanner(
                    controller: _controller!,
                    onDetect: _onDetect,
                  ),
                  // Camera couldn't start (still held by a just-closed
                  // scanner, or denied) — tap-to-retry instead of a black
                  // preview that looks frozen.
                  // Camera permission denied: retrying can never succeed,
                  // so point at the OS Settings instead of the retry loop.
                  // Gallery and Paste below stay usable.
                  if (_cameraDenied)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black,
                        alignment: Alignment.center,
                        padding: EdgeInsets.symmetric(horizontal: 24.w),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.no_photography_rounded,
                                color: Colors.white70, size: 40.sp),
                            SizedBox(height: 12.h),
                            Text(
                              context.l10n.scannerCameraAccessOff,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 16.h),
                            AppButton(
                              text: context.l10n.openSettings,
                              compact: true,
                              onPressed: _openCameraSettings,
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_cameraError)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _retryCamera,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          color: Colors.black,
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.no_photography_rounded,
                                  color: Colors.white70, size: 40.sp),
                              SizedBox(height: 12.h),
                              Text(
                                context.l10n.receiveCameraUnavailable,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 4.h),
                              Text(context.l10n.tapToRetry,
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 13.sp)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Scan frame overlay
                  Container(
                    width: 260.sp,
                    height: 260.sp,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20.r),
                      border: Border.all(
                          color: context.colors.accent.withValues(alpha: 0.6),
                          width: 2),
                    ),
                  ),
                  // Processing indicator
                  if (_isProcessing)
                    Container(
                      width: 260.sp,
                      height: 260.sp,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          LoadingAnimationWidget.staggeredDotsWave(
                            color: Colors.white,
                            size: 32.sp,
                          ),
                          SizedBox(height: 16.h),
                          Text(
                            context.l10n.receiveProcessing,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            context.l10n.scanQrCode,
            style: TextStyle(color: c.textSecondary, fontSize: 16.sp),
          ),
          SizedBox(height: 8.h),
          Text(
            context.l10n.scanAnyQRCodeDescription,
            style: TextStyle(color: c.textTertiary, fontSize: 14.sp),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16.h),
          // Gallery + Paste — two equal-weight input alternatives for
          // when the camera can't capture (no QR in view, simulator,
          // or a saved QR screenshot). Same pill style so neither one
          // reads as the odd one out (the lone "Paste from clipboard"
          // pill looked bolted-on).
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Row(
              children: [
                Expanded(
                  child: _ScannerActionButton(
                    icon: Icons.image_outlined,
                    label: context.l10n.receiveGallery,
                    onTap: _isProcessing ? null : _pickFromGallery,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: _ScannerActionButton(
                    icon: Icons.content_paste_rounded,
                    label: context.l10n.paste,
                    onTap: _isProcessing ? null : _pasteFromClipboard,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 24.h),
        ],
      ),
    );
  }
}

/// Pill button used in the smart scanner's bottom action row (Gallery
/// / Paste). Kept visually identical so the two alternatives read as
/// peers.
class _ScannerActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ScannerActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1.0,
        child: Container(
          height: 48.h,
          decoration: BoxDecoration(
            color: c.surfaceLight,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: c.borderSubtle),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: c.textSecondary, size: 18.sp),
              SizedBox(width: 8.w),
              Text(
                label,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _XpubWalletPicker extends StatelessWidget {
  final List<WalletDeviceConfig> configs;

  const _XpubWalletPicker({required this.configs});

  @override
  Widget build(BuildContext context) {
    return AppBottomSheetContainer(
      maxHeight: 0.6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBottomSheetHeader(
            title: context.l10n.selectWalletType,
            subtitle: context.l10n.chooseDeviceForXpub,
            icon: Icons.account_balance_wallet_rounded,
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              itemCount: configs.length,
              separatorBuilder: (_, __) => SizedBox(height: 4.h),
              itemBuilder: (context, index) {
                final config = configs[index];
                return AppBottomSheetListTile(
                  title: config.titleIn(context.l10n),
                  subtitle: config.subtitleIn(context.l10n),
                  leading: config.svgAsset != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8.r),
                          child: SvgPicture.asset(config.svgAsset!,
                              width: 40.sp, height: 40.sp),
                        )
                      : null,
                  onTap: () => context.pop(config),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
