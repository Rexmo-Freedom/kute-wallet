import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/ledger/ledger_transports_provider.dart';
import 'package:kute/screens/ledger/ledger_failure_copy.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart'
    show SheetNerdDataSection;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:ledger_bitcoin/ledger_bitcoin.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

/// Shows a bottom sheet to scan for and pick a Ledger device.
/// Returns the selected [LedgerDevice] or null if cancelled.
///
/// [requiredApp] is the app the caller needs open once connected. The
/// default keeps every Bitcoin flow as before (fingerprint probe, then
/// OPEN_APP Bitcoin). EVM-only flows pass [LedgerAppId.ethereum] so the
/// device goes straight to the Ethereum app instead of opening Bitcoin
/// first.
Future<LedgerDevice?> showLedgerDevicePicker(
  BuildContext context,
  WidgetRef ref, {
  LedgerAppId requiredApp = LedgerAppId.bitcoin,
}) {
  return showAppBottomSheet<LedgerDevice>(
    context: context,
    builder: (ctx) => _LedgerDevicePickerSheet(requiredApp: requiredApp),
  );
}

class _LedgerDevicePickerSheet extends ConsumerStatefulWidget {
  const _LedgerDevicePickerSheet({required this.requiredApp});

  final LedgerAppId requiredApp;

  @override
  ConsumerState<_LedgerDevicePickerSheet> createState() => _LedgerDevicePickerSheetState();
}

class _LedgerDevicePickerSheetState extends ConsumerState<_LedgerDevicePickerSheet> {
  bool _isConnecting = false;
  String? _connectingDeviceId;
  /// Bluetooth unless the user picks USB (Android, behind
  /// `kLedgerUsbTransportEnabled`, via [ledgerTransportsProvider]).
  LedgerConnectionType _transport = LedgerConnectionType.bluetooth;
  /// Root container captured while live — `ref` is unusable inside
  /// [dispose] (Riverpod tears the element's ref down before
  /// `state.dispose()` on unmount; same class as the 1.3.8 Polymarket
  /// prod fatal), and the old swallowed `ref.read` silently SKIPPED
  /// stopScan on teardown, leaking the BLE scan.
  ProviderContainer? _container;

  /// Inline status after a failed attempt (the app not open on the device,
  /// a device error), shown with a Try again button instead of a snackbar.
  /// [_statusDetail] holds the status word or raw text for nerd data.
  String? _statusMessage;
  String? _statusDetail;
  String _statusReason = 'failure';

  /// The device the last attempt used, so Try again reconnects to it.
  LedgerDevice? _retryDevice;

  /// `hardware_device_scan_empty` once per mount.
  bool _scanEmptyTracked = false;

  String get _transportName =>
      _transport == LedgerConnectionType.usb ? 'usb' : 'bluetooth';

  /// Outcome of one connect attempt. Categorical only: the transport,
  /// the app asked for and a LedgerFailureCode name, never a device
  /// name or id.
  void _trackConnectionResult(String outcome,
      {String? failureCode, Object? error}) {
    TrackingService.track('hardware_connection_result', params: {
      'vendor': 'ledger',
      'outcome': outcome,
      'transport': _transportName,
      'required_app': widget.requiredApp.name,
      if (failureCode != null) 'failure_code': failureCode,
      if (error != null) 'error_category': TrackingService.errorCategory(error),
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    // The picker is a sheet, not a route: once per mount.
    TrackingService.track('hardware_device_picker_opened', params: {
      'vendor': 'ledger',
      'required_app': widget.requiredApp.name,
      'transport': _transportName,
    });
    TrackingService.setFlowStep('hardware_device_picker');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ledgerServiceProvider.notifier).startScan(_transport);
    });
  }

  @override
  void dispose() {
    try {
      _container?.read(ledgerServiceProvider.notifier).stopScan();
    } catch (_) {}
    super.dispose();
  }

  void _selectTransport(LedgerConnectionType transport) {
    if (_isConnecting || transport == _transport) return;
    setState(() {
      _transport = transport;
      _statusMessage = null;
      _statusDetail = null;
    });
    TrackingService.ledgerTransportSelected(
        transport == LedgerConnectionType.usb ? 'usb' : 'bluetooth');
    ref.read(ledgerServiceProvider.notifier).startScan(transport);
  }

  void _showStatus(String message,
      {String? detail, required String reason}) {
    setState(() {
      _statusMessage = message;
      _statusDetail = detail;
      _statusReason = reason;
    });
  }

  void _retry() {
    if (_isConnecting) return;
    TrackingService.track('ledger_picker_retry',
        params: {'reason': _statusReason});
    final device = _retryDevice;
    setState(() {
      _statusMessage = null;
      _statusDetail = null;
    });
    if (device != null) {
      _connectAndVerify(device);
    } else {
      ref.read(ledgerServiceProvider.notifier).startScan(_transport);
    }
  }

  Future<void> _connectAndVerify(LedgerDevice device) async {
    if (_isConnecting) return;
    setState(() {
      _isConnecting = true;
      _connectingDeviceId = device.id;
      _retryDevice = device;
      _statusMessage = null;
      _statusDetail = null;
    });

    TrackingService.hardwareConnectionStarted('ledger');
    TrackingService.setFlowStep('hardware_connecting');
    try {
      final ledger = ref.read(ledgerServiceProvider.notifier);
      final connected = await ledger.connectToDevice(device);
      if (!mounted) return;
      if (!connected) {
        _trackConnectionResult('connect_failed',
            failureCode: ref.read(ledgerServiceProvider).failure?.code.name);
        setState(() { _isConnecting = false; _connectingDeviceId = null; });
        return;
      }

      if (widget.requiredApp != LedgerAppId.bitcoin) {
        // EVM-only flow: the serialized session quits whatever app is
        // running and opens the requested one through the dashboard
        // (same OPEN_APP APDU, plus the poll until it reports as running).
        final session = ledger.deviceSession;
        if (session == null) {
          throw const LedgerFailure(LedgerFailureCode.disconnected);
        }
        await session.run((scope) => scope.ensureApp(widget.requiredApp));
        _trackConnectionResult('connected');
        if (mounted) context.pop(device);
        return;
      }

      // Try to access Bitcoin app to verify it's open
      var fp = await ledger.getMasterFingerprint();
      if (fp != null && mounted) {
        // Bitcoin app is open — return device
        _trackConnectionResult('connected');
        context.pop(device);
        return;
      }

      // Bitcoin app not open — send APDU command to open it on the device
      if (mounted) {
        await ledger.openBitcoinApp();

        // Wait for the user to confirm on the Ledger screen
        // and for the Bitcoin app to finish loading.
        // Poll for up to 30 seconds.
        for (int i = 0; i < 15; i++) {
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
          fp = await ledger.getMasterFingerprint();
          if (fp != null) {
            _trackConnectionResult('connected');
            if (mounted) context.pop(device);
            return;
          }
        }

        // Timed out: the user did not confirm or the app did not load.
        // Said inline, with Try again, instead of a snackbar.
        _trackConnectionResult('app_not_open');
        if (mounted) {
          _showStatus(
            context.l10n.ledgerErrorOpenApp(LedgerAppId.bitcoin.deviceName),
            reason: 'app_not_open',
          );
        }
        await ledger.disconnect();
      }
    } catch (e) {
      _trackConnectionResult('failure',
          failureCode: LedgerFailure.from(e).code.name, error: e);
      if (mounted) {
        _showStatus(
          ledgerErrorCopy(context, e, fallbackApp: widget.requiredApp),
          detail: ledgerErrorDetail(context, e),
          reason: 'failure',
        );
      }
      if (widget.requiredApp != LedgerAppId.bitcoin) {
        // The caller expects a connected device with its app open; a
        // failed open leaves nothing worth keeping.
        try {
          await ref.read(ledgerServiceProvider.notifier).disconnect();
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() { _isConnecting = false; _connectingDeviceId = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerServiceProvider);
    final transports = ref.watch(ledgerTransportsProvider);
    final isUsb = _transport == LedgerConnectionType.usb;
    // The "no devices found" empty state, once per mount (a real
    // scan-end transition, never a rebuild).
    ref.listen(ledgerServiceProvider, (prev, next) {
      if (_scanEmptyTracked ||
          prev == null ||
          !prev.isScanning ||
          next.isScanning ||
          next.foundDevices.isNotEmpty ||
          _isConnecting) {
        return;
      }
      _scanEmptyTracked = true;
      TrackingService.track('hardware_device_scan_empty', params: {
        'vendor': 'ledger',
        'transport': _transportName,
        'has_failure': next.failure != null,
        if (next.failure != null) 'failure_code': next.failure!.code.name,
      });
    });

    return AppBottomSheetContainer(
      maxHeight: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          AppBottomSheetHeader(
            title: context.l10n.connectLedger,
            subtitle: _isConnecting
                ? context.l10n.receiveConnecting
                : state.isScanning
                    ? context.l10n.hwScanningForDevices
                    : state.foundDevices.isEmpty
                        ? context.l10n.hwNoDevicesFound
                        : context.l10n.hwDevicesFound(state.foundDevices.length),
            icon: isUsb ? Icons.usb_rounded : Icons.bluetooth_rounded,
            iconColor: context.colors.textPrimary,
            trailing: _isConnecting
                ? LoadingAnimationWidget.staggeredDotsWave(
                    color: context.colors.textSecondary, size: 22.sp)
                : state.isScanning
                    ? LoadingAnimationWidget.staggeredDotsWave(
                        color: context.colors.textSecondary, size: 22.sp)
                    : IconButton(
                        onPressed: () =>
                            ref.read(ledgerServiceProvider.notifier).startScan(_transport),
                        icon: Icon(Icons.refresh_rounded,
                            color: context.colors.textSecondary, size: 22.sp),
                      ),
          ),

          // Transport choice: only rendered when more than one transport is
          // offered (Android with the USB flag on).
          if (transports.length > 1)
            _LedgerTransportChoice(
              transports: transports,
              selected: _transport,
              enabled: !_isConnecting,
              onSelected: _selectTransport,
            ),

          // What went wrong on the last attempt, with Try again.
          if (_statusMessage != null && !_isConnecting)
            _LedgerPickerStatus(
              message: _statusMessage!,
              detail: _statusDetail,
              onRetry: _retry,
            ),

          // Device list or empty state
          Flexible(
            child: state.foundDevices.isEmpty && !_isConnecting
                ? _buildEmptyState(state)
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    itemCount: state.foundDevices.length,
                    separatorBuilder: (_, __) => SizedBox(height: 4.h),
                    itemBuilder: (context, index) {
                      final device = state.foundDevices[index];
                      return _buildDeviceTile(device);
                    },
                  ),
          ),

          // Cancel button
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
            child: AppBottomSheetTextButton(
              text: context.l10n.cancel,
              onPressed: _isConnecting
                  ? null
                  : () {
                      final found = state.foundDevices.length;
                      TrackingService.track('hardware_device_picker_cancelled',
                          params: {
                            'vendor': 'ledger',
                            'transport': _transportName,
                            'had_error': _statusMessage != null,
                            'devices_found': found == 0
                                ? '0'
                                : found == 1
                                    ? '1'
                                    : '2+',
                          });
                      context.pop();
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(LedgerConnectionState state) {
    final isUsb = _transport == LedgerConnectionType.usb;
    final failure = state.failure;
    final failureDetail =
        failure == null ? null : ledgerFailureDetail(context.l10n, failure);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 32.h, horizontal: 24.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(16.sp),
            decoration: BoxDecoration(
              color: context.colors.surfaceLight,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(
              isUsb
                  ? Icons.usb_rounded
                  : state.isScanning
                      ? Icons.bluetooth_searching_rounded
                      : Icons.bluetooth_disabled_rounded,
              color: context.colors.textTertiary,
              size: 36.sp,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            state.isScanning
                ? context.l10n.hwLookingForDevices('Ledger')
                : context.l10n.hwNoBrandDevicesFound('Ledger'),
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 16.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!state.isScanning) ...[
            SizedBox(height: 8.h),
            Text(
              isUsb
                  ? context.l10n.ledgerMakeSureUnlockedUsb
                  : context.l10n.hwMakeSureLedgerUnlocked,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textTertiary,
                fontSize: 14.sp,
                height: 1.5,
              ),
            ),
          ],
          if (failure != null) ...[
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                ledgerFailureMessage(context.l10n, failure,
                    fallbackApp: LedgerAppId.bitcoin),
                style: TextStyle(color: AppColors.error, fontSize: 14.sp),
                textAlign: TextAlign.center,
              ),
            ),
            if (failureDetail != null)
              SheetNerdDataSection(children: [
                Text(
                  failureDetail,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: context.colors.textTertiary, fontSize: 13.sp),
                ),
              ]),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceTile(LedgerDevice device) {
    final isBluetooth = device.connectionType == ConnectionType.ble;
    final isThisConnecting = _isConnecting && _connectingDeviceId == device.id;

    return AppBottomSheetListTile(
      title: device.name.isNotEmpty ? device.name : context.l10n.hwLedgerDevice,
      subtitle: isThisConnecting
          ? context.l10n.receiveConnecting
          : (isBluetooth ? context.l10n.bluetooth : context.l10n.hwUsb),
      icon: isBluetooth ? Icons.bluetooth_rounded : Icons.usb_rounded,
      iconColor: context.colors.textPrimary,
      onTap: _isConnecting ? null : () {
        TrackingService.hardwareDeviceSelected('ledger');
        _connectAndVerify(device);
      },
    );
  }
}

/// One plain sentence about the last attempt ("Open the Bitcoin app on
/// your Ledger and try again.") with a Try again button. The status word
/// or raw error text sits in a collapsed nerd data section under it.
class _LedgerPickerStatus extends StatelessWidget {
  const _LedgerPickerStatus({
    required this.message,
    required this.onRetry,
    this.detail,
  });

  final String message;
  final String? detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final detail = this.detail;
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 4.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
          if (detail != null)
            SheetNerdDataSection(children: [
              Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textTertiary, fontSize: 13.sp),
              ),
            ]),
          SizedBox(height: 10.h),
          AppButton(
            text: context.l10n.tryAgain,
            compact: true,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// Neutral two-way transport choice (no tinted fills): the selected
/// option uses the surface tone and primary text, the other stays flat.
class _LedgerTransportChoice extends StatelessWidget {
  const _LedgerTransportChoice({
    required this.transports,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final List<LedgerConnectionType> transports;
  final LedgerConnectionType selected;
  final bool enabled;
  final ValueChanged<LedgerConnectionType> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 4.h),
      child: Semantics(
        label: context.l10n.ledgerTransportLabel,
        container: true,
        child: Row(
          children: [
            for (final transport in transports)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.w),
                  child: Semantics(
                    button: true,
                    selected: transport == selected,
                    child: InkWell(
                      key: ValueKey('ledger_transport_${transport.name}'),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: enabled ? () => onSelected(transport) : null,
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 10.h),
                        decoration: BoxDecoration(
                          color: transport == selected
                              ? c.surfaceLight
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: c.surfaceLight),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              transport == LedgerConnectionType.usb
                                  ? Icons.usb_rounded
                                  : Icons.bluetooth_rounded,
                              size: 18.sp,
                              color: transport == selected
                                  ? c.textPrimary
                                  : c.textSecondary,
                            ),
                            SizedBox(width: 6.w),
                            Text(
                              transport == LedgerConnectionType.usb
                                  ? context.l10n.hwUsb
                                  : context.l10n.bluetooth,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                                color: transport == selected
                                    ? c.textPrimary
                                    : c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
