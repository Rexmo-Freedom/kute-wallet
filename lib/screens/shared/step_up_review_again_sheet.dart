// lib/screens/shared/step_up_review_again_sheet.dart
//
// C8 (Wallet Hardening Phase 1b, spec 4.2). Shown when what is about to be
// submitted drifted from what the user approved (`ReauthRequired`).
// Nothing was sent. "Review again" closes the sheet and leaves the user on
// the review, where confirming again asks for a fresh approval.
//
// Open it through `showStepUpReviewAgain` in `require_fresh_auth.dart`,
// which also emits `step_up_reauth_required`.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class StepUpReviewAgainSheet extends StatelessWidget {
  const StepUpReviewAgainSheet({super.key, required this.onReviewAgain});

  final VoidCallback onReviewAgain;

  /// [actionType] is the `SensitiveAction` name, used only for the event.
  static Future<void> show(
    BuildContext context, {
    required String actionType,
  }) {
    return showAppBottomSheet<void>(
      context: context,
      builder: (ctx) => StepUpReviewAgainSheet(
        onReviewAgain: () {
          TrackingService.track('step_up_review_again_tapped', params: {
            'action_type': actionType,
          });
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 12.h),
            child: AppDecorations.dragHandle(context),
          ),
          SizedBox(height: 28.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Text(
              context.l10n.stepUpDetailsChanged,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                height: 1.3,
              ),
            ),
          ),
          SizedBox(height: 28.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: AppButton(
              text: context.l10n.stepUpReviewAgain,
              onPressed: onReviewAgain,
            ),
          ),
        ],
      ),
    );
  }
}
