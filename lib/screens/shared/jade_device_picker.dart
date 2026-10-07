import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/jade_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

/// Shows a bottom sheet to scan for and pick a Jade device.
/// Returns the selected [JadeBleDevice] or null if cancelled.
Future<JadeBleDevice?> showJadeDevicePicker(
    BuildContext context, WidgetRef ref) {
  return showAppBottomSheet<JadeBleDevice>(
    context: context,
    builder: (ctx) => const _JadeDevicePickerSheet(),
  );
}

class _JadeDevicePickerSheet extends ConsumerStatefulWidget {
  const _JadeDevicePickerSheet();

  @override
  ConsumerState<_JadeDevicePickerSheet> createState() =>
      _JadeDevicePickerSheetState();
}

class _JadeDevicePickerSheetState
    extends ConsumerState<_JadeDevicePickerSheet> {
  /// Root container captured while live — `ref` is unusable inside
  /// [dispose] (Riverpod tears the element's ref down before
  /// `state.dispose()` on unmount; same class as the 1.3.8 Polymarket
  /// prod fatal), and the old swallowed `ref.read` silently SKIPPED
  /// stopScan on teardown, leaking the BLE scan.
  ProviderContainer? _container;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  /// `hardware_device_scan_empty` once per mount.
  bool _scanEmptyTracked = false;

  @override
  void initState() {
    super.initState();
    // The picker is a sheet, not a route: once per mount.
    TrackingService.track('hardware_device_picker_opened', params: {
      'vendor': 'jade',
      'transport': 'bluetooth',
    });
    TrackingService.setFlowStep('hardware_device_picker');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(jadeServiceProvider.notifier).startScan();
    });
  }

  @override
  void dispose() {
    try {
      _container?.read(jadeServiceProvider.notifier).stopScan();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(jadeServiceProvider);
    // The "no devices found" empty state, once per mount (a real
    // scan-end transition, never a rebuild).
    ref.listen(jadeServiceProvider, (prev, next) {
      if (_scanEmptyTracked ||
          prev == null ||
          !prev.isScanning ||
          next.isScanning ||
          next.foundDevices.isNotEmpty) {
        return;
      }
      _scanEmptyTracked = true;
      TrackingService.track('hardware_device_scan_empty', params: {
        'vendor': 'jade',
        'transport': 'bluetooth',
        'has_failure': next.errorMessage != null,
        if (next.errorMessage != null)
          'error_category': TrackingService.errorCategory(next.errorMessage),
      });
    });

    return AppBottomSheetContainer(
      maxHeight: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          AppBottomSheetHeader(
            title: context.l10n.connectJade,
            subtitle: state.isScanning
                ? context.l10n.hwScanningForDevices
                : state.foundDevices.isEmpty
                    ? context.l10n.hwNoDevicesFound
                    : context.l10n.hwDevicesFound(state.foundDevices.length),
            icon: Icons.bluetooth_rounded,
            iconColor: context.colors.textPrimary,
            trailing: state.isScanning
                ? LoadingAnimationWidget.staggeredDotsWave(
                    color: context.colors.textSecondary, size: 22.sp)
                : IconButton(
                    onPressed: () =>
                        ref.read(jadeServiceProvider.notifier).startScan(),
                    icon: Icon(Icons.refresh_rounded,
                        color: context.colors.textSecondary, size: 22.sp),
                  ),
          ),

          // Device list or empty state
          Flexible(
            child: state.foundDevices.isEmpty
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
              onPressed: () {
                final found = state.foundDevices.length;
                TrackingService.track('hardware_device_picker_cancelled',
                    params: {
                      'vendor': 'jade',
                      'transport': 'bluetooth',
                      'had_error': state.errorMessage != null,
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

  Widget _buildEmptyState(JadeConnectionState state) {
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
              state.isScanning
                  ? Icons.bluetooth_searching_rounded
                  : Icons.bluetooth_disabled_rounded,
              color: context.colors.textTertiary,
              size: 36.sp,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            state.isScanning
                ? context.l10n.hwLookingForDevices('Jade')
                : context.l10n.hwNoBrandDevicesFound('Jade'),
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 16.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!state.isScanning) ...[
            SizedBox(height: 8.h),
            Text(
              context.l10n.hwMakeSureJadeOn,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textTertiary,
                fontSize: 14.sp,
                height: 1.5,
              ),
            ),
          ],
          if (state.errorMessage != null) ...[
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                userErrorCopy(context, state.errorMessage,
                    fallback: context.l10n.walletsConnectionFailed),
                style: TextStyle(color: AppColors.error, fontSize: 14.sp),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceTile(JadeBleDevice device) {
    return AppBottomSheetListTile(
      title: device.name.isNotEmpty ? device.name : context.l10n.hwJadeDevice,
      subtitle: context.l10n.bluetooth,
      icon: Icons.bluetooth_rounded,
      iconColor: context.colors.textPrimary,
      onTap: () {
        TrackingService.hardwareDeviceSelected('jade');
        context.pop(device);
      },
    );
  }
}
