import 'package:kute/services/tracking_service.dart';
import 'package:kute/helpers/cbor_helper.dart';
import 'package:kute/helpers/psbt_helper.dart';
import 'package:kute/models/add_wallet_model.dart';
import 'package:kute/providers/add_wallet_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/controllers/import_wallet_controller.dart';
import 'package:kute/screens/shared/jade_device_picker.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/ledger/ledger_failure_copy.dart';
import 'package:kute/screens/ledger/ledger_investment_gate.dart'
    show ledgerVenueSetupAfterImport;
import 'package:kute/screens/shared/ledger_device_picker.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/screens/shared/wallet_icon.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/services/add_wallet_capabilities.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/jade_service.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:kute/screens/shared/kute_paste_chip.dart';

class XPubImportScreen extends ConsumerStatefulWidget {
  const XPubImportScreen({super.key});

  @override
  ConsumerState<XPubImportScreen> createState() => _XPubImportScreenState();
}

class _XPubImportScreenState extends ConsumerState<XPubImportScreen> {
  final TextEditingController _controller = TextEditingController();

  /// The screen stays open when Kute withholds this kind of import (a
  /// policy that changed after the Add wallet list was drawn, or a deep
  /// link): the connect, scan, file and confirm buttons go quiet, each
  /// with this reason. A hardware vendor and "Other wallet" (watch-only)
  /// both answer to `hardware.wallet`. `importXpub` re-checks the policy
  /// on submit.
  late final String _capability = xpubImportCapability(_currentConfig().type);

  String? get _hardwareBlock =>
      ref.watch(runtimeCapabilitiesProvider).blockReason(_capability);

  bool _isConnectingLedger = false;
  /// Set when a BLE connect / xpub-fetch attempt fails. Drives the
  /// inline retry card in the Bluetooth method content so the user
  /// sees the common fixes (close Ledger Live, unlock, open Bitcoin
  /// app) and a Retry button instead of a transient snackbar.
  String? _connectError;
  String? _jadeFingerprint;
  String? _ledgerFingerprint;

  /// How the key reached the screen, for `wallet_added`:
  /// usb | ble | qr | file | xpub (typed or pasted).
  String _importMethod = 'xpub';

  String? _expandedMethod;

  BitcoinAddressType _selectedAddressType = BitcoinAddressType.nativeSegwit;
  final TextEditingController _derivationPathController = TextEditingController(text: "m/84'/0'/0'");
  bool _useCustomDerivation = false;

  bool _showAdvancedBtOptions = false;

  /// The device's menu path for the QR export stays one tap away.
  bool _showQrHelp = false;

  // ── wallet_add funnel (categorical only: never the key, path or
  // fingerprint) ──
  final Stopwatch _flowClock = Stopwatch()..start();
  late final String _vendor;
  late final String _walletKind;
  String _flowStep = '';
  String? _lastMethod;
  String? _lastErrorCategory;
  bool _completed = false;
  bool _blockedAtEntry = false;
  bool _customPathTracked = false;

  @override
  void initState() {
    super.initState();
    final config = _currentConfig();
    _vendor = config.id;
    _walletKind = _walletKindFor(config);
    TrackingService.setFlowContext(
        flow: 'wallet_add', step: 'choose_method', walletKind: _walletKind);
    _step('choose_method');
    final block =
        ref.read(runtimeCapabilitiesProvider).blockReason(_capability);
    if (block != null) {
      _blockedAtEntry = true;
      TrackingService.track('wallet_add_blocked_shown', params: {
        'capability': _capability,
        'vendor': _vendor,
        'wallet_kind': _walletKind,
      });
    }
  }

  @override
  void dispose() {
    if (!_completed) {
      TrackingService.track('wallet_add_abandoned', params: {
        'step': _flowStep,
        'vendor': _vendor,
        'wallet_kind': _walletKind,
        if (_lastMethod != null) 'method': _lastMethod!,
        'time_in_flow_bucket': _timeInFlowBucket(_flowClock.elapsed),
        'reason': _blockedAtEntry
            ? 'blocked'
            : _lastErrorCategory != null
                ? 'error'
                : 'user_closed',
        if (_lastErrorCategory != null)
          'last_error_category': _lastErrorCategory!,
      });
    }
    TrackingService.clearFlowContext('wallet_add');
    _controller.dispose();
    _derivationPathController.dispose();
    super.dispose();
  }

  /// The device row picked on Add wallet (same lookup as [build]).
  WalletDeviceConfig _currentConfig() {
    final state = ref.read(addWalletProvider);
    final all = [...state.hotWallets, ...state.coldWallets];
    return all.firstWhere((cfg) => cfg.id == state.selectedWalletConfigId,
        orElse: () => all.last);
  }

  /// Mirrors ImportWalletController: every device row except "Other
  /// wallet" is stored as a hardware wallet.
  static bool _isHardwareConfig(WalletDeviceConfig config) =>
      config.type != 'generic' && config.type != 'spark';

  static String _walletKindFor(WalletDeviceConfig config) =>
      !_isHardwareConfig(config)
          ? 'watch_only'
          : const {'ledger', 'jade', 'keystone'}.contains(config.id)
              ? config.id
              : 'hardware';

  /// `wallet_add_step` on a real step change only (a retry of the same
  /// step does not refire).
  void _step(String step, {String? method, String? transport, String? source}) {
    if (step == _flowStep) return;
    _flowStep = step;
    if (method != null) _lastMethod = method;
    TrackingService.setFlowStep(step);
    TrackingService.track('wallet_add_step', params: {
      'step': step,
      'vendor': _vendor,
      'wallet_kind': _walletKind,
      if (method != null) 'method': method,
      if (transport != null) 'transport': transport,
      // How the key arrived: usb | ble | qr | file.
      if (source != null) 'source': source,
    });
  }

  /// `hardware_connection_failed` for a device attempt on this screen.
  /// [failureCode] is a LedgerFailureCode name (categorical) when known.
  void _trackHardwareFailed(String device, String stage,
      {Object? error, String? failureCode}) {
    final category = error == null
        ? 'hardware_wallet'
        : TrackingService.errorCategory(error);
    _lastErrorCategory = category;
    TrackingService.track('hardware_connection_failed', params: {
      'device': device,
      'stage': stage,
      'error_category': category,
      if (failureCode != null) 'failure_code': failureCode,
      'surface': 'wallet_add',
    });
  }

  String get _effectiveDerivationPath =>
      _useCustomDerivation ? _derivationPathController.text.trim() : _selectedAddressType.derivationPath;

  Future<void> _connectLedgerAndGetXpub(WalletDeviceConfig config) async {
    setState(() {
      _isConnectingLedger = true;
      _connectError = null;
    });
    _step('hardware_connect', method: 'bluetooth');

    try {
      final ledger = ref.read(ledgerServiceProvider.notifier);

      // Device picker now handles connection + Bitcoin app verification
      final device = await showLedgerDevicePicker(context, ref);
      if (device == null) {
        if (mounted) setState(() => _isConnectingLedger = false);
        return;
      }

      _importMethod = device.connectionType.name; // usb | ble
      _step('fetching_key', transport: _importMethod);
      // Device is already connected with Bitcoin app verified
      // Get master fingerprint for PSBT signing
      try {
        final fp = await ledger.getMasterFingerprint();
        if (fp != null) _ledgerFingerprint = fp;
      } catch (_) {}

      // Scan xpub — Bitcoin app should already be open
      await _scanLedgerWithRetry(config, ledger);
    } catch (e) {
      _trackHardwareFailed('ledger', 'xpub_fetch',
          error: e, failureCode: LedgerFailure.from(e).code.name);
      if (mounted) {
        setState(() => _connectError =
            context.l10n.walletsCouldntConnectToDevice(config.title));
      }
    } finally {
      if (mounted) setState(() => _isConnectingLedger = false);
    }
  }

  Future<void> _scanLedgerWithRetry(WalletDeviceConfig config, LedgerService ledger) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final xpub = await ledger.getXpub(
          derivationPath: _effectiveDerivationPath,
        );
        // Read the typed failure before disconnect resets the state.
        final failure = ref.read(ledgerServiceProvider).failure;
        if ((xpub == null || xpub.isEmpty) &&
            failure?.code == LedgerFailureCode.wrongApp &&
            mounted) {
          if (await _openLedgerBitcoinApp(ledger)) continue;
          return;
        }
        await ledger.disconnect();

        if (xpub != null && xpub.isNotEmpty && mounted) {
          await _importCapturedKey(config, xpub);
        } else if (mounted) {
          _trackHardwareFailed('ledger', 'xpub_fetch',
              failureCode: failure?.code.name ?? 'empty_key');
          showMessageSnackBar(
            context: context,
            message: failure != null
                ? ledgerFailureMessage(context.l10n, failure)
                : context.l10n.failedToRetrieveWalletData,
            error: true,
          );
        }
        return; // Success
      } catch (e) {
        if (LedgerFailure.from(e).code == LedgerFailureCode.wrongApp &&
            mounted) {
          if (await _openLedgerBitcoinApp(ledger)) continue;
          return;
        }

        // Not a Bitcoin-app error — rethrow
        rethrow;
      }
    }
  }

  /// Asks the Ledger to open the Bitcoin app and waits up to 30 seconds
  /// for it. Returns false (after disconnecting) when it never opened.
  Future<bool> _openLedgerBitcoinApp(LedgerService ledger) async {
    _step('open_bitcoin_app');
    await ledger.openBitcoinApp();
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return false;
      final fp = await ledger.getMasterFingerprint();
      if (fp != null) return true;
    }
    _trackHardwareFailed('ledger', 'open_app',
        error: 'timeout', failureCode: 'app_not_open');
    if (mounted) {
      showMessageSnackBar(context: context, message: context.l10n.ledgerBitcoinAppNotOpenMessage, error: true);
    }
    await ledger.disconnect();
    return false;
  }

  Future<void> _connectJadeAndGetXpub(WalletDeviceConfig config) async {
    setState(() {
      _isConnectingLedger = true;
      _connectError = null;
    });
    _step('hardware_connect', method: 'bluetooth');
    // Where the attempt got to, for `hardware_connection_failed`.
    var stage = 'picker';

    try {
      final jade = ref.read(jadeServiceProvider.notifier);

      // Show Jade device picker
      final device = await showJadeDevicePicker(context, ref);
      if (device == null) {
        if (mounted) setState(() => _isConnectingLedger = false);
        return;
      }
      stage = 'connect';
      TrackingService.hardwareConnectionStarted('jade');

      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.connectingToDevice(device.name),
          error: false,
          info: true,
        );
      }

      final connected = await jade.connectToDevice(device);
      if (!connected) {
        _trackHardwareFailed('jade', 'connect',
            error: ref.read(jadeServiceProvider).errorMessage ?? 'device');
        if (mounted) {
          final jadeState = ref.read(jadeServiceProvider);
          showMessageSnackBar(
            context: context,
            message: userErrorCopy(context, jadeState.errorMessage,
                fallback: context.l10n.walletsConnectionFailed),
            error: true,
          );
        }
        return;
      }

      // Jade requires PIN authentication before wallet operations
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.enterPINOnJadeDevice,
          error: false,
          info: true,
        );
      }

      stage = 'auth';
      _step('device_auth', transport: 'ble');
      final authenticated = await jade.authenticate();
      if (!authenticated) {
        _trackHardwareFailed('jade', 'auth',
            error: ref.read(jadeServiceProvider).errorMessage ?? 'device');
        if (mounted) {
          final jadeState = ref.read(jadeServiceProvider);
          showMessageSnackBar(
            context: context,
            message: userErrorCopy(context, jadeState.errorMessage,
                fallback: context.l10n.walletsAuthenticationFailed),
            error: true,
          );
        }
        await jade.disconnect();
        return;
      }

      TrackingService.track('hardware_connection_completed', params: {
        'device': 'jade',
        'transport': 'ble',
        'surface': 'wallet_add',
      });
      stage = 'xpub_fetch';
      _step('fetching_key', transport: 'ble');
      // Get master fingerprint for PSBT signing (before disconnect)
      final fingerprint = await jade.getMasterFingerprint();
      if (fingerprint != null) {
        _jadeFingerprint = fingerprint;
      }

      // Fetch the xpub for the selected address type (default: Native SegWit)
      final xpub = await jade.getXpub(
        derivationPath: _selectedAddressType.derivationPath,
      );
      await jade.disconnect();

      if (xpub != null && xpub.isNotEmpty && mounted) {
        _importMethod = 'ble';
        await _importCapturedKey(config, xpub);
      } else if (mounted) {
        _trackHardwareFailed('jade', 'xpub_fetch');
        showMessageSnackBar(context: context, message: context.l10n.failedToRetrieveWalletData, error: true);
      }
    } catch (e) {
      _trackHardwareFailed('jade', stage, error: e);
      if (mounted) {
        setState(() =>
            _connectError = context.l10n.walletsCouldntConnectToDevice(config.title));
      }
    } finally {
      if (mounted) setState(() => _isConnectingLedger = false);
    }
  }

  static String _scriptTypeString(BitcoinAddressType type) {
    switch (type) {
      case BitcoinAddressType.nativeSegwit: return 'bip84';
      case BitcoinAddressType.taproot: return 'bip86';
      case BitcoinAddressType.nestedSegwit: return 'bip49';
      case BitcoinAddressType.legacy: return 'bip44';
    }
  }

  /// Analytics-friendly script-type label. Distinct from
  /// `_scriptTypeString` (which returns BIP numbers used by the
  /// derivation path) — the funnel dashboard groups by user-meaningful
  /// terms (`segwit` / `taproot`) instead of BIP slugs.
  static String _scriptTypeLabel(BitcoinAddressType type) {
    switch (type) {
      case BitcoinAddressType.nativeSegwit: return 'segwit';
      case BitcoinAddressType.taproot: return 'taproot';
      case BitcoinAddressType.nestedSegwit: return 'nested_segwit';
      case BitcoinAddressType.legacy: return 'legacy';
    }
  }

  /// `wallet_added` script_type vocabulary.
  static String _walletAddedScriptType(BitcoinAddressType type) {
    switch (type) {
      case BitcoinAddressType.nativeSegwit: return 'native_segwit';
      case BitcoinAddressType.taproot: return 'taproot';
      case BitcoinAddressType.nestedSegwit: return 'nested_segwit';
      case BitcoinAddressType.legacy: return 'legacy';
    }
  }

  Future<void> _onScanPressed(WalletDeviceConfig config) async {
    _step('scan_qr', method: 'qr');
    final result = await context.pushNamed<String>('QrScanner');
    if (result != null && result.isNotEmpty && mounted) {
      _importMethod = 'qr';
      await _importCapturedKey(config, _processImportedKey(result));
    }
  }

  Future<void> _onImportFile(WalletDeviceConfig config) async {
    _step('pick_file', method: 'file');
    try {
      final result = await PsbtHelper.importFromFile();
      if (result != null && result.isNotEmpty && mounted) {
        _importMethod = 'file';
        await _importCapturedKey(config, _processImportedKey(result));
      }
    } catch (e) {
      final category = TrackingService.errorCategory(e);
      _lastErrorCategory = category;
      TrackingService.track('wallet_add_failed', params: {
        'stage': 'file_read',
        'error_category': category,
        'import_method': 'file',
        'vendor': _vendor,
        'wallet_kind': _walletKind,
      });
      if (mounted) {
        showMessageSnackBar(
            context: context,
            message: userErrorCopy(context, e,
                fallback: context.l10n.errorCopyReadFile),
            error: true);
      }
    }
  }

  Future<void> _onImportPressed(WalletDeviceConfig config) async {
    // Extends walletAddStarted(): the commit point of this screen.
    _step('importing');
    TrackingService.track('wallet_add_started', params: {
      // wallet_added's import_method vocabulary: usb|ble|qr|file|xpub.
      'import_method': _importMethod,
      'vendor': _vendor,
      'wallet_kind': _walletKind,
      'script_type': _walletAddedScriptType(_selectedAddressType),
      'custom_derivation': _useCustomDerivation,
    });
    FocusScope.of(context).unfocus();
    final importController = ref.read(importWalletControllerProvider.notifier);

    final scriptType = _scriptTypeString(_selectedAddressType);
    final fingerprint = _jadeFingerprint ?? _ledgerFingerprint;
    // Errors surface through the `ref.listen` in build, which already
    // snackbars every AsyncError; a second snackbar here doubled them.
    await importController.importXpub(
      xpub: _controller.text.trim(),
      config: config,
      scriptType: scriptType,
      masterFingerprint: fingerprint,
    );
  }

  /// A key captured from a device, a QR code or a file is authoritative:
  /// import it right away and let the success confirmation be the only
  /// feedback. The earlier "Public key captured" card plus a separate
  /// Confirm tap read as an extra step that never asked anything new.
  Future<void> _importCapturedKey(
      WalletDeviceConfig config, String xpub) async {
    _step('key_captured', source: _importMethod);
    setState(() {
      _controller.text = xpub;
      _autoDetectAddressType(xpub);
    });
    await _onImportPressed(config);
    if (!mounted) return;
    // A failed import (duplicate key, capability off, storage error) has
    // shown its message; drop the captured key so the method picker is
    // ready for another attempt instead of an orphaned Confirm bar.
    if (ref.read(importWalletControllerProvider) is AsyncError) {
      setState(_controller.clear);
    }
  }

  /// True when the pasted/typed text plausibly is an extended public
  /// key or an output descriptor. Drives the inline validation row in
  /// the paste card and gates the bottom Confirm CTA so garbage input
  /// never reaches the import controller.
  static bool _isValidKey(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    // Extended public key: known prefix + base58 body. Real keys are
    // ~111 chars; 100 leaves headroom without accepting fragments.
    if (RegExp(r"^[xyzvtu]pub[1-9A-HJ-NP-Za-km-z]+$").hasMatch(t) &&
        t.length >= 100) {
      return true;
    }
    // Output descriptor (tr(...), wpkh(...), sh(wpkh(...)), pkh(...)).
    if (RegExp(r'^(tr|wpkh|sh\(wpkh|pkh)\(').hasMatch(t) && t.contains(')')) {
      return true;
    }
    return false;
  }

  String _processImportedKey(String raw) {
    final trimmed = raw.trim();
    // Accept plain xpub/zpub/ypub or output descriptors (tr(...), wpkh(...), etc.)
    if (RegExp(r'^[xyzvtmu]pub[1-9A-HJ-NP-Za-km-z]').hasMatch(trimmed)) {
      return trimmed;
    }
    if (RegExp(r'^(tr|wpkh|sh\(wpkh|pkh)\(').hasMatch(trimmed)) {
      return trimmed;
    }

    if (CborToXpubConverter.isLikelyCbor(trimmed)) {
      try {
        return CborToXpubConverter.convertCborToXpub(trimmed);
      } catch (_) {
        // intentionally empty
      }
    }

    // Base64-encoded CBOR (e.g. from multi-part UR fallback)?
    final decoded = CborToXpubConverter.tryDecodeBase64Xpub(trimmed);
    if (decoded != null) return decoded;

    return trimmed;
  }

  void _autoDetectAddressType(String key) {
    if (key.startsWith('tr(')) {
      _selectedAddressType = BitcoinAddressType.taproot;
    } else if (key.startsWith('zpub') || key.startsWith('vpub')) {
      _selectedAddressType = BitcoinAddressType.nativeSegwit;
    } else if (key.startsWith('ypub') || key.startsWith('upub')) {
      _selectedAddressType = BitcoinAddressType.nestedSegwit;
    } else if (key.startsWith('wpkh(')) {
      _selectedAddressType = BitcoinAddressType.nativeSegwit;
    } else if (key.startsWith('sh(wpkh(')) {
      _selectedAddressType = BitcoinAddressType.nestedSegwit;
    } else if (key.startsWith('pkh(')) {
      _selectedAddressType = BitcoinAddressType.legacy;
    } else {
      // Plain xpub/tpub defaults to legacy (BIP44). This matches the
      // path hardware wallets typically use when exporting a bare
      // "Account 0" BIP44 xpub from the device's UI; flipping this
      // to BIP84 broke the existing wallet whose funds were at the
      // BIP44 addresses the original xpub described. The address
      // type chip on the import screen is right there for users
      // who want a different derivation.
      _selectedAddressType = BitcoinAddressType.legacy;
    }
  }

  Widget _buildStepRow(int stepNumber, String text, AppColorsExtension c, {bool isActive = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22.sp,
            height: 22.sp,
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: isActive ? c.textPrimary : c.borderSubtle),
            ),
            child: Center(
              child: Text(
                "$stepNumber",
                style: TextStyle(
                  color: isActive ? c.textPrimary : c.textSecondary,
                  fontSize: 13.sp,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2.h),
              child: Text(
                text,
                style: TextStyle(color: c.textSecondary, fontSize: 14.sp, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableMethodCard({
    required AppColorsExtension c,
    required String methodKey,
    required IconData icon,
    required String label,
    required String description,
    required Widget Function(AppColorsExtension c) contentBuilder,
    bool isLoading = false,
  }) {
    final isExpanded = _expandedMethod == methodKey;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(
          color: isExpanded ? c.border : c.borderSubtle,
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              final newMethod = isExpanded ? null : methodKey;
              if (newMethod != null) {
                TrackingService.xpubImportMethodSelected(newMethod);
                _lastMethod = newMethod;
              }
              setState(() {
                _expandedMethod = newMethod;
              });
            },
            borderRadius: BorderRadius.circular(18.r),
            child: Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: 18.w, vertical: 18.h),
              child: Row(
                children: [
                  Container(
                    width: 44.sp,
                    height: 44.sp,
                    decoration: BoxDecoration(
                      color: c.textPrimary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: isLoading
                        ? Padding(
                            padding: EdgeInsets.all(10.sp),
                            child:
                                LoadingAnimationWidget.staggeredDotsWave(
                                    color: c.textPrimary, size: 20.sp),
                          )
                        : Icon(icon, color: c.textPrimary, size: 22.sp),
                  ),
                  SizedBox(width: 14.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            )),
                        SizedBox(height: 3.h),
                        Text(description,
                            style: TextStyle(
                              color: c.textTertiary,
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.1,
                            )),
                      ],
                    ),
                  ),
                  SizedBox(width: 8.w),
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
                    child: Icon(Icons.chevron_right,
                        color: c.textTertiary,
                        size: 22.sp),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: isExpanded
                ? contentBuilder(c)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildQrContent(AppColorsExtension c, WalletDeviceConfig config) {
    final isJade = config.type == 'jade';
    return Padding(
      padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: c.border, height: 1),
          SizedBox(height: 12.h),
          // Most people only need "scan the code on the screen"; the
          // device's menu path opens on demand.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final expanded = !_showQrHelp;
              TrackingService.track('xpub_qr_help_toggled',
                  params: {'expanded': expanded});
              setState(() => _showQrHelp = expanded);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 4.h),
              child: Row(
                children: [
                  Icon(Icons.help_outline_rounded,
                      color: c.textTertiary, size: 16.sp),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      context.l10n.importWhereIsQr,
                      style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(
                    _showQrHelp ? Icons.expand_less : Icons.expand_more,
                    color: c.textTertiary,
                    size: 18.sp,
                  ),
                ],
              ),
            ),
          ),
          if (_showQrHelp) ...[
            SizedBox(height: 10.h),
            if (isJade) ...[
              _buildStepRow(1, context.l10n.walletsJadeUnlockExportXpub, c),
              Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: InkWell(
                  onTap: () {
                    TrackingService.track('xpub_jade_qr_pin_help_opened');
                    launchUrl(
                      Uri.parse(
                          'https://jadefw.blockstream.com/pinqr/qrpin.html'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  borderRadius: BorderRadius.circular(10.r),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: c.borderSubtle, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.open_in_new, size: 14.sp, color: c.textSecondary),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            context.l10n.walletsUsingQrPinUnlockJade,
                            style: TextStyle(color: c.textPrimary, fontSize: 14.sp, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _buildStepRow(2, context.l10n.walletsJadeQrAppearScan, c, isActive: true),
            ] else ...[
              _buildStepRow(1, context.l10n.walletsNavigateExportXpubQr(config.title), c),
              _buildStepRow(2, context.l10n.walletsTapToScanQrFromDevice, c, isActive: true),
            ],
          ],
          SizedBox(height: 12.h),
          if (_hardwareBlock case final reason?) CapabilityBlockNote(reason),
          AppButton(
            text: context.l10n.scanQrCode,
            onPressed:
                _hardwareBlock != null ? null : () => _onScanPressed(config),
            icon: Icons.camera_alt,
            compact: true,
          ),
        ],
      ),
    );
  }

  Widget _buildBluetoothContent(AppColorsExtension c, WalletDeviceConfig config) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: c.border, height: 1),
          SizedBox(height: 12.h),
          // Connect failure → inline retry card with the common fixes,
          // shown in place of a transient snackbar so the user can act
          // on it. Only while not mid-connect and no key captured yet.
          if (_connectError != null &&
              !_isConnectingLedger &&
              _controller.text.isEmpty) ...[
            _buildConnectErrorCard(c, config),
            SizedBox(height: 12.h),
          ],
          if (config.type == 'jade') ...[
            _buildStepRow(1, context.l10n.walletsTurnOnJadeBluetoothEnabled, c),
            _buildStepRow(2, context.l10n.walletsTapConnectEnterPinJade, c, isActive: !_isConnectingLedger),
          ] else ...[
            _buildStepRow(1, context.l10n.walletsCloseLedgerLiveCompletely, c),
            _buildStepRow(2, context.l10n.walletsTurnOnUnlockLedger, c),
            _buildStepRow(3, context.l10n.tapBelowToConnectYouLlBePromptedToOpenTheBitcoinAppIfNeeded, c, isActive: !_isConnectingLedger),
          ],

          // Advanced options toggle
          SizedBox(height: 12.h),
          GestureDetector(
            onTap: () {
              final expanded = !_showAdvancedBtOptions;
              // Was payAdvancedToggled, which filed this under the Pay
              // funnel; this is the hardware import screen's own toggle.
              TrackingService.track('xpub_advanced_toggled',
                  params: {'expanded': expanded, 'vendor': _vendor});
              setState(() => _showAdvancedBtOptions = expanded);
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: c.surfaceLight.withValues(alpha:0.5),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: c.borderSubtle, width: 0.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, color: c.textTertiary, size: 16.sp),
                  SizedBox(width: 8.w),
                  Text(
                    context.l10n.walletsAdvanced,
                    style: TextStyle(color: c.textSecondary, fontSize: 14.sp, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  // Name a value only when it differs from the default,
                  // so the closed row reads "Advanced" and nothing else.
                  if (!_showAdvancedBtOptions &&
                      (_useCustomDerivation ||
                          _selectedAddressType !=
                              BitcoinAddressType.nativeSegwit))
                    Text(
                      _useCustomDerivation
                          ? context.l10n.importCustomPath
                          : _selectedAddressType.label,
                      style: TextStyle(color: c.textTertiary, fontSize: 13.sp),
                    ),
                  SizedBox(width: 4.w),
                  Icon(
                    _showAdvancedBtOptions ? Icons.expand_less : Icons.expand_more,
                    color: c.textTertiary,
                    size: 18.sp,
                  ),
                ],
              ),
            ),
          ),

          // Advanced options content
          if (_showAdvancedBtOptions) ...[
            SizedBox(height: 10.h),

            // Section label
            Text(
              context.l10n.walletsAddressType,
              style: TextStyle(color: c.textSecondary, fontSize: 13.sp, fontWeight: FontWeight.w600, letterSpacing: 0.3),
            ),
            SizedBox(height: 4.h),
            // Helper: most users should never touch this. Spell out the
            // safe default so they don't second-guess the dropdown.
            Text(
              context.l10n.walletsAddressTypeHelper,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 12.sp,
                height: 1.35,
              ),
            ),
            SizedBox(height: 8.h),

            // Address type selector
            ...BitcoinAddressType.values.map((type) {
              final isSelected = !_useCustomDerivation && type == _selectedAddressType;
              return GestureDetector(
                onTap: () {
                  // Stable enum identifier, NOT the display label — labels get
                  // localized eventually and analytics must never fork
                  // by language.
                  TrackingService.xpubAddressTypeSelected(type.name);
                  setState(() {
                    _selectedAddressType = type;
                    _useCustomDerivation = false;
                    _derivationPathController.text = type.derivationPath;
                  });
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                  margin: EdgeInsets.only(bottom: 4.h),
                  decoration: BoxDecoration(
                    color: isSelected ? c.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(
                      color: isSelected ? c.border : c.borderSubtle,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: isSelected ? c.textPrimary : c.textTertiary,
                        size: 16.sp,
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(type.label,
                                style: TextStyle(color: c.textPrimary, fontSize: 15.sp, fontWeight: FontWeight.w600)),
                            SizedBox(height: 1.h),
                            Text(type.derivationPath,
                                style: TextStyle(color: c.textTertiary, fontSize: 13.sp, fontFamily: 'Courier')),
                          ],
                        ),
                      ),
                      Text(
                        type.description.split('(').last.replaceAll(')', ''),
                        style: TextStyle(color: c.textTertiary, fontSize: 13.sp),
                      ),
                    ],
                  ),
                ),
              );
            }),

            // Custom derivation path
            SizedBox(height: 10.h),
            Text(
              context.l10n.walletsDerivationPath,
              style: TextStyle(color: c.textSecondary, fontSize: 13.sp, fontWeight: FontWeight.w600, letterSpacing: 0.3),
            ),
            SizedBox(height: 6.h),
            Container(
              decoration: BoxDecoration(
                color: _useCustomDerivation ? c.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(
                  color: _useCustomDerivation ? c.border : c.borderSubtle,
                  width: 0.5,
                ),
              ),
              child: TextField(
                controller: _derivationPathController,
                style: TextStyle(color: c.textPrimary, fontSize: 15.sp, fontFamily: 'Courier'),
                cursorColor: context.colors.accent,
                decoration: InputDecoration(
                  hintText: "m/84'/0'/0'",
                  hintStyle: TextStyle(color: c.textDisabled, fontSize: 15.sp, fontFamily: 'Courier'),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (value) {
                  setState(() => _useCustomDerivation = value.trim() != _selectedAddressType.derivationPath);
                  // Once per mount; never the path itself.
                  if (_useCustomDerivation && !_customPathTracked) {
                    _customPathTracked = true;
                    TrackingService.track('xpub_custom_derivation_entered',
                        params: {'vendor': _vendor});
                  }
                },
              ),
            ),
            if (_useCustomDerivation)
              Padding(
                padding: EdgeInsets.only(top: 4.h),
                child: Text(
                  context.l10n.walletsUsingCustomPathWarning,
                  style: TextStyle(color: c.warning, fontSize: 13.sp),
                ),
              ),
          ],

          if (_isConnectingLedger) ...[
            SizedBox(height: 8.h),
            Center(
              child: Column(
                children: [
                  LoadingAnimationWidget.staggeredDotsWave(color: context.colors.accent, size: 32.sp),
                  SizedBox(height: 12.h),
                  Text(
                    context.l10n.connectingToDevice(
                        config.type == 'jade' ? 'Jade' : 'Ledger'),
                    style: TextStyle(color: c.textPrimary, fontSize: 16.sp, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ] else ...[
            SizedBox(height: 8.h),
            // Merge: nav's AppButton + main's l10n label. Label is
            // "Connect" (not "Connect & Import"): this only opens the BLE
            // session + pulls the xpub. The actual import is the single
            // bottom "Confirm Import" CTA that appears once the key is
            // captured.
            if (_hardwareBlock case final reason?) CapabilityBlockNote(reason),
            AppButton(
              text: context.l10n.walletsConnect,
              onPressed: _hardwareBlock != null
                  ? null
                  : () => config.type == 'jade'
                      ? _connectJadeAndGetXpub(config)
                      : _connectLedgerAndGetXpub(config),
              icon: Icons.bluetooth_searching,
              compact: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileContent(AppColorsExtension c, WalletDeviceConfig config) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: c.border, height: 1),
          SizedBox(height: 12.h),
          _buildStepRow(1, context.l10n.walletsExportWalletToFile(config.title), c),
          _buildStepRow(2, context.l10n.walletsTapToImportFile, c, isActive: true),
          SizedBox(height: 4.h),
          if (_hardwareBlock case final reason?) CapabilityBlockNote(reason),
          AppButton(
            text: context.l10n.importFile,
            onPressed:
                _hardwareBlock != null ? null : () => _onImportFile(config),
            icon: Icons.folder_open,
            compact: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPasteContent(AppColorsExtension c) {
    final text = _controller.text.trim();
    final isValid = _isValidKey(text);
    return Padding(
      padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: c.border, height: 1),
          SizedBox(height: 14.h),
          // Input styled like the rest of the app's fields (surface
          // tint + subtle hairline, 12 radius), tall enough that a
          // full xpub wraps and stays readable while pasting.
          Container(
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                color: text.isEmpty
                    ? c.borderSubtle
                    : (isValid
                        ? AppColors.success.withValues(alpha: 0.45)
                        : c.border),
                width: text.isEmpty ? 0.5 : 1,
              ),
            ),
            child: TextField(
              controller: _controller,
              minLines: 3,
              maxLines: 5,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15.sp,
                  fontFamily: 'Courier',
                  height: 1.4),
              cursorColor: context.colors.accent,
              // Live rebuild so the validation row and the bottom
              // Confirm bar track manual typing, not just the Paste
              // button path.
              onChanged: (value) => setState(() {
                if (_isValidKey(value)) _autoDetectAddressType(value.trim());
              }),
              decoration: InputDecoration(
                hintText: context.l10n.importPasteHint,
                hintStyle: TextStyle(color: c.textTertiary, fontSize: 14.sp),
                contentPadding: EdgeInsets.all(12.w),
                border: InputBorder.none,
              ),
            ),
          ),
          SizedBox(height: 10.h),
          // One quiet row under the field: validation feedback on the
          // left (only when there is something to judge), the paste
          // chip on the right. Replaces the old numbered how-to steps
          // and full-width outlined button, which crowded the card.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: text.isEmpty
                    ? const SizedBox.shrink()
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isValid
                                ? Icons.check_circle_rounded
                                : Icons.info_outline_rounded,
                            color:
                                isValid ? AppColors.success : c.textTertiary,
                            size: 16.sp,
                          ),
                          SizedBox(width: 6.w),
                          Expanded(
                            child: Text(
                              isValid
                                  ? context.l10n.importKeyLooksGood
                                  : context.l10n.walletsInvalidKeyHint,
                              style: TextStyle(
                                color: isValid
                                    ? AppColors.success
                                    : c.textTertiary,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              SizedBox(width: 10.w),
              KutePasteChip(onPressed: _onPasteFromClipboard),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onPasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      setState(() {
        _controller.text = _processImportedKey(data!.text!);
        _autoDetectAddressType(_controller.text);
      });
      TrackingService.track('xpub_paste_clipboard_tapped', params: {
        'valid': _isValidKey(_controller.text),
      });
    }
  }

  /// "Other ways to import" section divider — visually demotes the
  /// non-recommended import methods below the device's primary path.
  Widget _buildOtherMethodsDivider(AppColorsExtension c) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(
        children: [
          Expanded(child: Divider(color: c.border, height: 1)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Text(
              context.l10n.walletsOtherWaysToImport,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(child: Divider(color: c.border, height: 1)),
        ],
      ),
    );
  }

  /// Inline BLE connect-failure card. Surfaces the canonical fixes
  /// (close Ledger Live / unlock / open the Bitcoin app) plus a Retry
  /// button that re-runs the connect for the active device. Replaces
  /// the old transient snackbar, which vanished before the user could
  /// read it.
  Widget _buildConnectErrorCard(
      AppColorsExtension c, WalletDeviceConfig config) {
    final isJade = config.type == 'jade';
    final fixes = isJade
        ? [
            context.l10n.walletsFixTurnOnJadeUnlockPin,
            context.l10n.walletsFixBluetoothOnBothDevices,
            context.l10n.walletsFixKeepJadeClose,
          ]
        : [
            context.l10n.walletsFixCloseLedgerLive,
            context.l10n.walletsFixUnlockLedgerOpenBitcoinApp,
            context.l10n.walletsFixBluetoothOnBothDevices,
          ];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: AppColors.error, size: 18.sp),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  _connectError ?? context.l10n.walletsConnectionFailed,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          ...fixes.map((f) => Padding(
                padding: EdgeInsets.only(bottom: 6.h),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•',
                        style: TextStyle(
                            color: c.textTertiary, fontSize: 13.sp)),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        f,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13.sp,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          SizedBox(height: 4.h),
          AppButton(
            text: context.l10n.walletsTryAgain,
            onPressed: () {
              TrackingService.track('hardware_connection_retry_tapped', params: {
                'device': isJade ? 'jade' : 'ledger',
                'surface': 'wallet_add',
              });
              setState(() => _connectError = null);
              isJade
                  ? _connectJadeAndGetXpub(config)
                  : _connectLedgerAndGetXpub(config);
            },
            icon: Icons.refresh_rounded,
            compact: true,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // 1. Providers
    final addWalletState = ref.watch(addWalletProvider);
    final allConfigs = [...addWalletState.hotWallets, ...addWalletState.coldWallets];
    final config = allConfigs.firstWhere(
            (cfg) => cfg.id == addWalletState.selectedWalletConfigId,
        orElse: () => allConfigs.last
    );
    final importState = ref.watch(importWalletControllerProvider);

    ref.listen(importWalletControllerProvider, (prev, next) {
      if (next is AsyncData) {
        _completed = true;
        TrackingService.clearFlowContext('wallet_add');
        // Was `config.type == 'cold'`, which no row has, so every device
        // import was counted as watch-only and hardware_wallet_added never
        // fired. Same rule as ImportWalletController now.
        final isHardware = _isHardwareConfig(config);
        TrackingService.walletCreated(
          type: isHardware ? 'hardware' : 'watch_only',
          // config.id, not the display title: titles are shown to the
          // user and may be localized/renamed — the id is the stable
          // analytics dimension.
          hardwareDevice: isHardware ? config.id : null,
          authMode: isHardware ? 'hardware' : 'watch_only',
        );
        // Only the key's network prefix is read (t/u/vpub = testnet);
        // the key itself never leaves the device.
        final isTestnet =
            RegExp(r'\b[tuv]pub').hasMatch(_controller.text.trim());
        TrackingService.walletAdded(
          walletKind: _walletKindFor(config),
          importMethod: _importMethod,
          vendor: isHardware ? config.id : null,
          scriptType: _walletAddedScriptType(_selectedAddressType),
          network: isTestnet ? 'testnet' : 'bitcoin',
          source: 'add_wallet',
        );
        // Distinct from `walletCreated`: only fires for hardware
        // wallets and includes the script-type funnel breakdown so
        // the admin board can see whether segwit or taproot is the
        // dominant import path per device. `walletCount` comes from
        // the settings provider (post-import), giving us a "n-th
        // hardware wallet added" signal for power-user segmentation.
        if (isHardware) {
          try {
            // The stable row id (ledger, jade, ...), not the display title.
            final device = config.id;
            final scriptType = _scriptTypeLabel(_selectedAddressType);
            final walletCount =
                ref.read(settingsProvider).wallets.length;
            TrackingService.hardwareWalletAdded(
              device: device,
              scriptType: scriptType,
              walletCount: walletCount,
            );
          } catch (_) {}
        }
        // A freshly imported Ledger continues to the investing setup step
        // only while a Ledger venue is on (its runtime capability, Phase
        // 4, P4.3). With both off a Ledger connects as a plain bitcoin
        // hardware wallet: no venue setup, no Ethereum address, straight
        // to Home like everything else; the setup is asked later, the
        // first time a Ledger venue that is on is opened.
        final importer = ref.read(importWalletControllerProvider.notifier);
        final ledgerSetupWalletId = ledgerVenueSetupAfterImport(
          importedWalletId: importer.lastImportedWalletId,
          importedWalletType: importer.lastImportedWalletType,
        );
        // The same confirmation every money moment ends on: one check,
        // one line, Done. Done tears down the imperative routes under the
        // overlay and lands where the import used to navigate directly.
        final router = GoRouter.of(context);
        final rootNav = Navigator.of(context, rootNavigator: true);
        TrackingService.track('wallet_import_confirmation_shown',
            params: {'device': config.id});
        pushKuteSuccessOverlay(
          navigator: rootNav,
          overlay: KuteConfirmation(
            message: context.l10n.walletImportedConfirmation,
            onDone: () {
              while (rootNav.canPop()) {
                rootNav.pop();
              }
              if (ledgerSetupWalletId != null) {
                router.goNamed(
                  'ledgerInvestingSetup',
                  pathParameters: {'walletId': ledgerSetupWalletId},
                  queryParameters: const {'from': 'import'},
                );
              } else {
                router.go('/home');
              }
            },
          ),
        );
      }
      if (next is AsyncError) {
        final category = TrackingService.errorCategory(next.error);
        _lastErrorCategory = category;
        TrackingService.track('wallet_add_failed', params: {
          'stage': 'import',
          'error_category': category,
          'import_method': _importMethod,
          'vendor': _vendor,
          'wallet_kind': _walletKind,
        });
        showMessageSnackBar(
            context: context,
            message: userErrorCopy(context, next.error,
                fallback: context.l10n.errorCopyImportWallet),
            error: true);
      }
    });

    return KeyboardDismissOnTap(
      child: Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: Theme.of(context).brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        centerTitle: true,
        leading: const KuteBackButton(),
        title: Text(
            config.id == 'ledger'
                ? context.l10n.ledgerConnectTitle
                : config.importTitleIn(context.l10n),
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 20.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
            ),
        ),
        actions: const [],
      ),
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: -100.h,
              left: 0,
              right: 0,
              height: 400.h,
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.0,
                    colors: [
                      c.textPrimary.withValues(alpha:0.04),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),

            SafeArea(
              bottom: false,
              child: _buildActionPage(config, importState),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildActionPage(WalletDeviceConfig config, AsyncValue<void> importState) {
    final c = context.colors;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 8.h),

                // Device header — chromeless to match the rest of
                // the design language. Wallet icon + title + subtitle
                // sit directly on the screen background, no boxed
                // card chrome.
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 4.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          WalletIcon(
                            visual: WalletVisual(
                              svgAsset: config.svgAsset,
                              icon: config.icon,
                              color: config.color,
                            ),
                            size: 56,
                          ),
                          SizedBox(width: 16.w),
                          // The AppBar title already names the device
                          // ("Connect Ledger"), so the body doesn't
                          // repeat it — the hero shows the supported
                          // models next to the device icon instead.
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    context.l10n.walletsSupportedModels
                                        .toUpperCase(),
                                    style: TextStyle(
                                      color: c.textTertiary,
                                      fontSize: 11.sp,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    )),
                                SizedBox(height: 4.h),
                                Text(config.subtitleIn(context.l10n),
                                    style: TextStyle(
                                      color: c.textPrimary,
                                      fontSize: 18.sp,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                      height: 1.2,
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 14.h),
                      // One-line explainer so the screen states its
                      // purpose before listing methods: import the
                      // public key, keys never leave the device.
                      Text(
                        context.l10n.walletsImportXpubExplainer,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                          height: 1.45,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20.h),

                // Device, QR and file captures import immediately and end
                // on the shared success confirmation, so the method picker
                // is the whole screen: no "Public key captured" card, no
                // second Confirm step. Paste keeps its inline validation
                // row plus the bottom Confirm bar.
                ...[
                  // Expandable method cards — Bluetooth first when available
                  // Recommended method first: Bluetooth for BLE
                  // devices, otherwise QR. Secondary methods drop below
                  // the "Other ways to import" divider so the screen
                  // has one obvious happy path.
                  if (config.isBluetooth) ...[
                    _buildExpandableMethodCard(
                      c: c,
                      methodKey: 'bluetooth',
                      icon: Icons.bluetooth_rounded,
                      label: context.l10n.bluetooth,
                      description: context.l10n.connectViaBluetooth(config.title),
                      isLoading: _isConnectingLedger,
                      contentBuilder: (c) => _buildBluetoothContent(c, config),
                    ),
                    SizedBox(height: 8.h),
                  ] else ...[
                    _buildExpandableMethodCard(
                      c: c,
                      methodKey: 'qr',
                      icon: Icons.qr_code_scanner_rounded,
                      label: context.l10n.scanQrCode,
                      description: context.l10n.importScanQrDescription,
                      contentBuilder: (c) => _buildQrContent(c, config),
                    ),
                    SizedBox(height: 8.h),
                  ],

                  _buildOtherMethodsDivider(c),

                  // QR as a secondary method only when Bluetooth was
                  // the primary above (otherwise it's already shown).
                  if (config.isBluetooth) ...[
                    _buildExpandableMethodCard(
                      c: c,
                      methodKey: 'qr',
                      icon: Icons.qr_code_scanner_rounded,
                      label: context.l10n.scanQrCode,
                      description: context.l10n.importScanQrDescription,
                      contentBuilder: (c) => _buildQrContent(c, config),
                    ),
                    SizedBox(height: 8.h),
                  ],

                  if (config.isSdCard) ...[
                    _buildExpandableMethodCard(
                      c: c,
                      methodKey: 'file',
                      icon: Icons.folder_open_rounded,
                      label: context.l10n.importFile,
                      description: context.l10n.importFileDescription,
                      contentBuilder: (c) => _buildFileContent(c, config),
                    ),
                    SizedBox(height: 8.h),
                  ],

                  _buildExpandableMethodCard(
                    c: c,
                    methodKey: 'paste',
                    icon: Icons.paste_rounded,
                    label: context.l10n.paste,
                    description: context.l10n.importPasteDescription,
                    contentBuilder: (c) => _buildPasteContent(c),
                  ),

                  SizedBox(height: 100.h),
                ],
              ],
            ),
          ),
        ),

        // Bottom confirm bar (always visible)
        if (_controller.text.isNotEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, MediaQuery.of(context).padding.bottom + 16.h),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_hardwareBlock case final reason?)
                CapabilityBlockNote(reason),
              AppButton(
                text: context.l10n.confirmImport,
                // Disabled until the captured/typed key actually parses
                // as an xpub or descriptor, so the CTA can never submit
                // garbage to the import controller, and while Kute
                // withholds hardware wallets for this account or build.
                onPressed: (importState.isLoading ||
                        _hardwareBlock != null ||
                        !_isValidKey(_controller.text))
                    ? null
                    : () {
                        _importMethod = 'xpub';
                        _onImportPressed(config);
                      },
                isLoading: importState.isLoading,
              ),
            ]),
          ),
      ],
    );
  }
}

/// `time_in_flow_bucket` for `wallet_add_abandoned`.
String _timeInFlowBucket(Duration d) {
  final s = d.inSeconds;
  if (s < 10) return '<10s';
  if (s < 30) return '10-30s';
  if (s < 120) return '30s-2m';
  if (s < 600) return '2-10m';
  return '10m+';
}
