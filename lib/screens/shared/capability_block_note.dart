// lib/screens/shared/capability_block_note.dart
//
// Why a control on this screen is disabled by Kute's runtime policy.
//
// Gated features stay reachable (user decision, September 2026): the
// Advanced page opens, the hardware-wallet screen opens. Only the
// committing control is disabled, and this line sits beside it so the
// dead button and its reason are read together. The text comes from
// [CapabilityDecision.message]: the operator's own words when the policy
// carries some, Kute's wording for the reason code otherwise.
//
// Onramps are the exception (founder decision, October 2026): one the
// policy does not offer is not shown at all, so it never wears this
// note. See lib/services/onramp_visibility.dart.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/theme/app_theme.dart';

class CapabilityBlockNote extends StatelessWidget {
  const CapabilityBlockNote(this.message, {super.key, this.padding});

  final String message;

  /// Defaults to a small gap below, for a note placed above its button.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: padding ?? EdgeInsets.only(bottom: 10.h),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 1.h),
              child: Icon(Icons.lock_outline_rounded,
                  size: 16.sp, color: c.textTertiary),
            ),
            SizedBox(width: 6.w),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
