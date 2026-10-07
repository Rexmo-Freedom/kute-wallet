import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/recovery/restore_secrets_screen.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/secure/storage_bootstrap.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Shown when secure storage could not be read at cold start (D-21). It
/// never shows a keypad, never counts PIN attempts and never offers a wipe.
/// After repeated definitive failures it also offers Restore wallets.
class StorageUnavailableScreen extends StatefulWidget {
  const StorageUnavailableScreen({super.key, required this.result});

  final StorageBootResult result;

  static int _retriesThisProcess = 0;

  @visibleForTesting
  static void debugReset() => _retriesThisProcess = 0;

  @override
  State<StorageUnavailableScreen> createState() =>
      _StorageUnavailableScreenState();
}

class _StorageUnavailableScreenState extends State<StorageUnavailableScreen> {
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final retries = StorageUnavailableScreen._retriesThisProcess;
    if (retries > 0) _startCooldown(min(30, 1 << min(retries, 5)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldown = seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  void _retry() {
    StorageUnavailableScreen._retriesThisProcess++;
    // Same event as [TrackingService.storageUnavailableRetry], plus which
    // retry this is in the process (small int, capped by the cooldown).
    TrackingService.track('storage_unavailable_retry', params: {
      'attempt': StorageUnavailableScreen._retriesThisProcess,
      'state': widget.result.state.name,
    });
    context.go('/splash');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Icon(Icons.lock_clock_rounded,
                    size: 48.sp, color: c.textSecondary),
                SizedBox(height: 20.h),
                Text(
                  l10n.storageUnavailableTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 10.h),
                Text(
                  l10n.storageUnavailableBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                AppButton(
                  key: const ValueKey('storage-retry'),
                  text: _cooldown > 0
                      ? '${l10n.storageUnavailableRetry} (${_cooldown}s)'
                      : l10n.storageUnavailableRetry,
                  onPressed: _cooldown > 0 ? null : _retry,
                ),
                if (widget.result.offerRestore) ...[
                  SizedBox(height: 10.h),
                  AppButton(
                    key: const ValueKey('storage-restore'),
                    text: l10n.restoreWalletsAction,
                    variant: AppButtonVariant.secondary,
                    onPressed: () {
                      TrackingService.track(
                          'storage_unavailable_restore_tapped');
                      context.go(
                        '/restore_secrets',
                        extra: RestoreSecretsReason.storageUnavailable,
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
