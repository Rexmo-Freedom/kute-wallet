import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/screens/recovery/restore_secrets_screen.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Home banner for a spending wallet whose stored seed this phone cannot
/// read. It links to Restore wallets and never wipes anything.
class SeedUnavailableBanner extends ConsumerStatefulWidget {
  const SeedUnavailableBanner({super.key});

  @override
  ConsumerState<SeedUnavailableBanner> createState() =>
      _SeedUnavailableBannerState();
}

class _SeedUnavailableBannerState extends ConsumerState<SeedUnavailableBanner> {
  bool _reported = false;

  @override
  Widget build(BuildContext context) {
    final unavailable = ref.watch(breezSDKProvider.select(
        (sdk) => sdk is AsyncError && sdk.error is SeedUnavailableException));
    if (!unavailable) return const SizedBox.shrink();
    if (!_reported) {
      _reported = true;
      TrackingService.seedUnavailableBannerShown();
    }
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
      child: Semantics(
        button: true,
        child: GestureDetector(
          key: const ValueKey('seed-unavailable-banner'),
          onTap: () {
            TrackingService.seedUnavailableBannerTapped();
            context.push('/restore_secrets',
                extra: RestoreSecretsReason.walletUnavailable);
          },
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            decoration: AppDecorations.card(context),
            child: Row(
              children: [
                Icon(Icons.key_off_rounded, color: c.error, size: 20.sp),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    context.l10n.seedUnavailableBanner,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                Text(
                  context.l10n.seedUnavailableAction,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: c.textTertiary, size: 20.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
