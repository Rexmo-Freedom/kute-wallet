// lib/screens/scanner/scanner_sheet.dart
//
// THE SCANNER, AS A SHEET (founder decision, October 2026). Every Scan in
// the app opens this one bottom sheet over the screen it was tapped on:
// the live camera edge to edge from the sheet's rounded top to its bottom
// (the whole sheet is the camera), the drag handle and the close X over
// the video at the top, the scan frame centred, and two round controls
// over the bottom: the flash on the left, a QR picked from photos on the
// right. No header, no title: the sheet names itself to a screen reader. No Paste here: Paste stays on the
// field that asked.
//
// Three modes, one camera:
//  * [ScannerMode.route] (Home's scan button): reads the payload and
//    routes it itself (send, LNURL withdraw, xpub import). The sheet
//    closes before Send opens.
//  * [ScannerMode.recipient] (a recipient field): closes with the scanned
//    string, which the field fills in.
//  * [ScannerMode.multiPart] (signed PSBTs, xpubs, recovery QRs): joins
//    animated BBQr / UR codes and closes with the result.
//
// The camera starts when the sheet opens, stops the moment it starts
// closing (X, swipe, a scan) and is released when it is gone; it pauses
// with the app in the background. Nothing scanned ever reaches analytics.

import 'dart:async';

import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/controllers/import_wallet_controller.dart';
import 'package:kute/screens/shared/kute_back_button.dart'
    show KuteCircleButton;
import 'package:kute/helpers/common_operation_methods.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/helpers/qr_gallery_helper.dart';
import 'package:kute/helpers/scanned_address.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:kute/models/add_wallet_model.dart';
import 'package:kute/models/send_tx_model.dart';
import 'package:kute/providers/add_wallet_provider.dart';
import 'package:kute/providers/qr_scanner_provider.dart';
import 'package:kute/screens/scanner/scanner_camera.dart';
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

/// What the scanner does with a code.
enum ScannerMode {
  /// Reads the payload and routes it itself (Home's scan button).
  route,

  /// Closes with the scanned string for the field that asked.
  recipient,

  /// Joins animated BBQr / UR codes and closes with the result.
  multiPart,
}

/// How tall the scanner sheet stands, as a share of the screen: the send
/// sheet's first-step height, so it reads as a sheet over the page.
const double kScannerSheetHeight = 0.64;

/// The route names the scanner's sheets carry, so route observers keep
/// seeing the names the full-screen scanners had.
const String kSmartScannerRouteName = 'smartScanner';
const String kMultiPartScannerRouteName = 'QrScanner';

/// Open the scanner sheet over [context] and hand back what it read,
/// trimmed: a recipient (normalized the way the routing scanner reads
/// it), or with [multiPart] an assembled BBQr / UR payload. Null when the
/// person closed it without a code. [photos] false hides the photo
/// control: a recovery phrase is never read from a screenshot in the
/// library.
Future<String?> showScannerSheet(BuildContext context,
    {bool multiPart = false, bool photos = true}) async {
  final result = await showAppBottomSheet<String>(
    context: context,
    routeSettings: RouteSettings(
        name: multiPart ? kMultiPartScannerRouteName : kSmartScannerRouteName),
    builder: (_) => ScannerSheet(
        mode: multiPart ? ScannerMode.multiPart : ScannerMode.recipient,
        photos: photos),
  );
  final scanned = result?.trim() ?? '';
  return scanned.isEmpty ? null : scanned;
}

/// Open the scanner sheet that routes what it reads (Home's scan button):
/// a payment opens Send once the sheet has closed.
Future<void> showRoutingScannerSheet(BuildContext context) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: kSmartScannerRouteName),
      builder: (_) => const ScannerSheet(mode: ScannerMode.route),
    );

/// A route's page that presents the scanner as the same sheet, over
/// whatever the route sits on (the `/smart-scanner`, `/camera` and
/// `/qr-scanner` links).
class ScannerSheetPage<T> extends Page<T> {
  const ScannerSheetPage({super.key, super.name, required this.mode});

  final ScannerMode mode;

  @override
  Route<T> createRoute(BuildContext context) => ModalBottomSheetRoute<T>(
        settings: this,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierLabel: MaterialLocalizations.of(context).scrimLabel,
        builder: (_) => ScannerSheet(mode: mode),
      );
}

class ScannerSheet extends ConsumerStatefulWidget {
  const ScannerSheet({super.key, required this.mode, this.photos = true});

  final ScannerMode mode;

  /// Whether a QR may be picked from the photo library. Off for the
  /// recovery-phrase scanner only: a seed QR is read from the camera,
  /// never from a screenshot.
  final bool photos;

  @override
  ConsumerState<ScannerSheet> createState() => _ScannerSheetState();
}

class _ScannerSheetState extends ConsumerState<ScannerSheet>
    with WidgetsBindingObserver {
  ScannerCamera? _camera;
  bool _isProcessing = false;
  bool _cameraError = false;

  /// Camera permission is denied (or permanently denied), so retrying the
  /// camera can never succeed; the only way out is the OS Settings.
  bool _cameraDenied = false;

  /// This device has no camera to scan with (the simulator): nothing to
  /// retry, photos are the way in. Never shown on a phone with a camera.
  bool _noCamera = false;

  /// The last QR picked from photos held no code: a plain caption under
  /// the preview says so until the next try.
  bool _galleryMiss = false;

  /// The sheet started closing (or closed): no second pop, no restart.
  bool _closing = false;

  /// Multi-part: a code was handed back, so dispose reports no dismiss.
  /// Nothing about the code itself is ever sent: this mode also reads
  /// recovery phrases and PSBTs.
  bool _completed = false;
  bool _animatedSeen = false;
  double _lastProgress = 0;

  bool get _multiPart => widget.mode == ScannerMode.multiPart;

  static final _xpubRegex =
      RegExp(r'^[xyzvtmu]pub[1-9A-HJ-NP-Za-km-z]{100,108}$');
  static final _descriptorRegex = RegExp(
      r'^(tr|wpkh|sh\(wpkh|pkh)\(.*[xyzvtmu]pub[1-9A-HJ-NP-Za-km-z]+.*\)$');

  ScannerCamera _newCamera() =>
      ref.read(scannerCameraFactoryProvider)(multiPart: _multiPart);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera = _newCamera();
    // mobile_scanner v7 doesn't reliably auto-start, and reopening the
    // scanner right after a previous instance is still releasing the camera
    // trips an "in use" error. Arm explicitly with retry.
    _safeStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_multiPart && !_completed) {
      TrackingService.track('qr_scanner_dismissed', params: {
        'animated_in_progress': _animatedSeen,
        'progress_pct': (_lastProgress * 100).round(),
        'progress_bucket': _progressBucket(_lastProgress),
      });
    }
    // Release the camera ASAP so reopening (scan → pay → scan again) doesn't
    // hit "camera already in use".
    final c = _camera;
    _camera = null;
    unawaited(c?.dispose());
    super.dispose();
  }

  static String _progressBucket(double p) {
    if (p <= 0) return 'none';
    if (p < 0.5) return '<50%';
    if (p < 1) return '50-99%';
    return 'complete';
  }

  /// Stop the camera when the app backgrounds and re-arm on resume —
  /// otherwise the camera stays held while backgrounded and a foreground
  /// reopen reports it "in use".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _camera;
    if (c == null || _closing) return;
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
      if (!mounted || _camera == null || _closing) return;
      try {
        await _camera!.start();
        if (mounted && (_cameraError || _cameraDenied || _noCamera)) {
          setState(() {
            _cameraError = false;
            _cameraDenied = false;
            _noCamera = false;
          });
        }
        return;
      } on ScannerCameraDenied {
        break;
      } on ScannerCameraUnavailable {
        if (!mounted || _closing) return;
        setState(() {
          _noCamera = true;
          _cameraError = false;
          _cameraDenied = false;
        });
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    final denied = await _isCameraDenied();
    if (!mounted || _closing) return;
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

  /// Tap-to-retry handler — the failed camera is in a bad state, so swap
  /// in a fresh one and re-arm. The old one is released after the frame
  /// that drops its preview.
  Future<void> _retryCamera() async {
    final old = _camera;
    setState(() {
      _camera = _newCamera();
      _cameraError = false;
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(old?.dispose()));
    _safeStart();
  }

  /// The sheet is going (X, swipe, a scan, or a hand-off): stop the camera
  /// now rather than when the closing animation ends. It is released in
  /// [dispose].
  void _onClosing() {
    if (_closing) return;
    _closing = true;
    unawaited(_camera?.stop());
  }

  /// Close the sheet, with [value] for the caller.
  void _close([String? value]) {
    if (!mounted || _closing) return;
    _onClosing();
    Navigator.of(context).pop(value);
  }

  void _popSafely() => _close();

  /// Hand a payment to Send: the sheet closes, then Send opens over the
  /// screen the scan started from.
  Future<void> _pushToConfirmSend() async {
    if (!mounted) return;
    TrackingService.markEntrySource('send', 'scanner');
    final router = GoRouter.of(context);
    _close();
    unawaited(router.push('/home/pay/confirm_send'));
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
    if (_closing) return;
    if (_multiPart) {
      // The assembler joins animated frames; its result closes the sheet
      // (see the listener in [build]).
      ref.read(qrScannerProvider.notifier).onDetect(capture);
      return;
    }
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    final code = barcode?.rawValue?.trim();
    if (code == null || code.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _galleryMiss = false;
    });
    await _camera?.stop();
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

    // Recipient mode: hand the payload back to the field that asked and
    // stop. The caller (the Send field's Scan) runs its own paste/commit
    // pipeline against it, so we deliberately skip all the routing below.
    if (widget.mode == ScannerMode.recipient) {
      _close(input);
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

    if (!mounted) return;
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
          contextLine: l10n.walletImportedWithOthers(selected.title),
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
        overlay: KuteConfirmation(
          message: l10n.received,
          amount: '${_formatSats(maxSats)} sats',
          contextLine: l10n.receiveLightningWithdrawal,
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

    // A recovery phrase or a private key is never an address: nothing of
    // it goes into Send, where a network pick and a quote would send it
    // out of the device.
    var secret = false;
    try {
      secret = await AdvisorInputGuard.holdsSecret(input);
    } catch (_) {}
    if (secret) {
      TrackingService.qrScanned('secret_refused');
      if (!mounted) return;
      showMessageSnackBar(
        context: context,
        message: context.l10n.scanSecretRefused,
        error: true,
      );
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

  /// Pick a QR image from photos and run it through the same pipeline as
  /// a live scan. Handy on devices with no camera (simulator) or when the
  /// person has a saved QR screenshot. An image with no code says so in a
  /// plain caption under the preview.
  ///
  /// We deliberately do NOT stop/start the live camera here: the decode
  /// runs on a separate controller inside [QrGalleryHelper], and opening
  /// the OS file picker backgrounds the app, so `MobileScanner` already
  /// auto-stops/restarts the camera via its lifecycle. Calling `start()`
  /// ourselves on top of that threw "MobileScannerController is already
  /// running". `_isProcessing` alone is enough to gate `_onDetect` while
  /// we're busy.
  Future<void> _pickFromGallery() async {
    if (_isProcessing || _closing) return;
    setState(() {
      _isProcessing = true;
      _galleryMiss = false;
    });
    try {
      final code = await QrGalleryHelper.pickAndDecode();
      if (!mounted || _closing) return;
      if (code == null || code.isEmpty) {
        setState(() {
          _isProcessing = false;
          _galleryMiss = true;
        });
        return;
      }
      if (_multiPart) {
        setState(() => _isProcessing = false);
        ref
            .read(qrScannerProvider.notifier)
            .onDetect(BarcodeCapture(barcodes: [Barcode(rawValue: code)]));
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

  void _toggleTorch(bool isOn) {
    TrackingService.track('qr_scanner_torch_toggled',
        params: {'enabled': !isOn});
    unawaited(_camera?.toggleTorch());
  }

  /// Multi-part: the assembler finished, so the sheet closes with it.
  void _onMultiPart(QrScannerState? previous, QrScannerState next) {
    if (next.isScanningAnimated) {
      _animatedSeen = true;
      _lastProgress = next.progress;
    }
    if (next.hasResult && next.resultData != null && !_completed) {
      _completed = true;
      TrackingService.track('qr_scanner_completed', params: {
        'animated': next.isScanningAnimated || _animatedSeen,
      });
      _close(next.resultData);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Route mode: keep sendTxProvider alive while the sheet is up, so what
    // a scan writes survives into Send (autoDispose).
    if (widget.mode == ScannerMode.route) ref.watch(sendTxProvider);
    QrScannerState? multi;
    if (_multiPart) {
      multi = ref.watch(qrScannerProvider);
      ref.listen<QrScannerState>(qrScannerProvider, _onMultiPart);
    }
    final l10n = context.l10n;

    // The whole sheet is the camera (founder decision, October 2026): no
    // header, the preview runs from under the sheet's rounded top corners
    // to its bottom edge, and the drag handle and the close X float over
    // the video. Shorter than the full-height sheets so it reads as a
    // sheet over the page, the send sheet's first-step height.
    return PopScope<Object?>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _onClosing();
      },
      child: Semantics(
        container: true,
        label: l10n.scanQrCode,
        child: ClipRRect(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * kScannerSheetHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _preview(context, multi),
                // The drag handle, over the video.
                Positioned(
                  top: 12.h,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 36.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 16.w,
                  left: 16.w,
                  child: _ScannerControl(
                    key: const ValueKey('scanner-close'),
                    icon: Icons.close_rounded,
                    label: l10n.close,
                    onPressed: _close,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The preview, edge to edge: the camera (or a dark field with why it
  /// is off), the scan frame, the one line the scan needs under it, and
  /// the flash and photo controls over its bottom edge above the home
  /// indicator.
  Widget _preview(BuildContext context, QrScannerState? multi) {
    final camera = _camera!;
    final l10n = context.l10n;
    final live = !_cameraDenied && !_cameraError && !_noCamera;
    final bottomInset = MediaQuery.paddingOf(context).bottom + 16.w;
    // The caption under the frame, when there is one.
    final String? caption;
    if (multi != null && multi.isScanningAnimated) {
      caption = l10n.scannerKeepInFrame;
    } else if (_galleryMiss) {
      caption = l10n.receiveNoQrCodeFoundInImage;
    } else {
      caption = null;
    }
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          KeyedSubtree(
            key: ObjectKey(camera),
            child: camera.buildPreview(_onDetect),
          ),
          // Camera permission denied: retrying can never succeed, so
          // point at the OS Settings instead of the retry loop. The
          // photo control stays usable.
          if (_cameraDenied)
            _CameraOff(
              message: l10n.scannerCameraAccessOff,
              action: AppButton(
                text: l10n.openSettings,
                compact: true,
                onPressed: _openCameraSettings,
              ),
            )
          // No camera on this device (the simulator): nothing to retry,
          // photos are the way in.
          else if (_noCamera)
            _CameraOff(message: l10n.receiveCameraUnavailable)
          // Camera couldn't start (still held by a just-closed scanner):
          // tap-to-retry instead of a black field that looks frozen.
          else if (_cameraError)
            GestureDetector(
              onTap: _retryCamera,
              behavior: HitTestBehavior.opaque,
              child: _CameraOff(
                message: l10n.receiveCameraUnavailable,
                detail: l10n.tapToRetry,
              ),
            ),
          // Scan frame overlay, with the caption and the progress of an
          // animated code under it. Scaled down, never overflowing, on a
          // preview shorter than the frame (a small window).
          if (live)
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    if (multi != null && multi.isScanningAnimated) ...[
                      SizedBox(height: 16.h),
                      SizedBox(
                        width: 260.sp,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4.r),
                          child: LinearProgressIndicator(
                            value: multi.progress > 0 ? multi.progress : null,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                context.colors.accent),
                            minHeight: 4.h,
                          ),
                        ),
                      ),
                    ],
                    if (caption != null) ...[
                      SizedBox(height: 12.h),
                      SizedBox(
                        width: 300.w,
                        child: Text(
                          caption,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13.sp,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else if (caption != null)
            Positioned(
              left: 24.w,
              right: 24.w,
              bottom: bottomInset + 52.w + 16.h,
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white70, fontSize: 13.sp, height: 1.4),
              ),
            ),
          // Processing indicator
          if (_isProcessing)
            Center(
              child: Container(
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
                      l10n.receiveProcessing,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (live)
            Positioned(
              left: 16.w,
              bottom: bottomInset,
              child: ValueListenableBuilder<bool>(
                valueListenable: camera.torchOn,
                builder: (context, isOn, _) => _ScannerControl(
                  key: const ValueKey('scanner-torch'),
                  icon: isOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  label: l10n.flash,
                  onPressed: () => _toggleTorch(isOn),
                ),
              ),
            ),
          if (widget.photos)
            Positioned(
              right: 16.w,
              bottom: bottomInset,
              child: _ScannerControl(
                key: const ValueKey('scanner-gallery'),
                icon: Icons.photo_library_rounded,
                label: l10n.receiveGallery,
                onPressed: _isProcessing ? null : _pickFromGallery,
              ),
            ),
        ],
      ),
    );
  }
}

/// The dark field shown in place of the camera: one centred line, an
/// optional second (tap to retry) and an optional action (Open Settings).
class _CameraOff extends StatelessWidget {
  const _CameraOff({required this.message, this.detail, this.action});

  final String message;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 32.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.no_photography_rounded,
              color: Colors.white70, size: 40.sp),
          SizedBox(height: 12.h),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white,
                fontSize: 16.sp,
                fontWeight: FontWeight.w700),
          ),
          if (detail != null) ...[
            SizedBox(height: 4.h),
            Text(detail!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13.sp)),
          ],
          if (action != null) ...[
            SizedBox(height: 16.h),
            action!,
          ],
        ],
      ),
    );
  }
}

/// A round control over the camera preview (flash, photos): the header
/// buttons' circle, in the one tint allowed here, a translucent dark fill
/// that reads over live video in light and dark mode alike.
class _ScannerControl extends StatelessWidget {
  const _ScannerControl({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final onPressed = this.onPressed;
    return IgnorePointer(
      ignoring: onPressed == null,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1.0,
        child: KuteCircleButton(
          size: 52,
          semanticsLabel: label,
          fill: Colors.black.withValues(alpha: 0.45),
          borderColor: Colors.white.withValues(alpha: 0.24),
          onPressed: onPressed ?? () {},
          child: Icon(icon, color: Colors.white, size: 24.sp),
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
