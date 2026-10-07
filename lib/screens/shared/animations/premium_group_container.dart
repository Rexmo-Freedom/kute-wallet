import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/theme/app_theme.dart';

class PremiumGroupContainer extends StatelessWidget {
  final Widget child;
  const PremiumGroupContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = context.isDark;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: isDark ? c.border : c.border.withValues(alpha:0.5),
          width: isDark ? 1 : 0.5,
        ),
        // Box shadows kept STRICTLY below the card (offset_y >=
        // blurRadius) so the shadow blur never bleeds above the
        // rounded top edge. Previously offset (0, 4) + blurRadius 16
        // leaked ~12px of shadow above the card, which read as a
        // faint horizontal strip above the rounded top — looked like
        // a partial card peek under the date header.
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 16),
                  spreadRadius: -4,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 14),
                  spreadRadius: -2,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 4),
                  spreadRadius: -1,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.r),
        child: child,
      ),
    );
  }
}
