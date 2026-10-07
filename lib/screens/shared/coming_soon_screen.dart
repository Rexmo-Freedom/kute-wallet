import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  /// Stable snake_case identifier for analytics. NEVER derive tracking
  /// from [title] — it's display text and will eventually be localized,
  /// which would fork the `coming_soon_viewed` feature dimension by
  /// language (PostHog events must be language-independent).
  final String analyticsKey;

  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.analyticsKey,
    this.color = Colors.blueAccent,
  });

  @override
  Widget build(BuildContext context) {
    TrackingService.comingSoonViewed(feature: analyticsKey);
    final c = context.colors;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: const KuteBackButton(),
        centerTitle: true,
        title: Text(
          title,
          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 18.sp),
        ),
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
          PlatformSafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 40.w),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 100.sp,
                      height: 100.sp,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha:0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withValues(alpha:0.2), width: 2),
                      ),
                      child: Icon(icon, color: color, size: 44.sp),
                    ),
                    SizedBox(height: 32.h),
                    Text(
                      context.l10n.comingSoon,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 28.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      context.l10n.comingSoonWorkingOn(title),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 15.sp,
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: 40.h),
                    SizedBox(
                      width: double.infinity,
                      child: AppButton(
                        text: context.l10n.goBack,
                        onPressed: () => context.pop(),
                        color: color,
                        textColor: color,
                        isOutlined: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
