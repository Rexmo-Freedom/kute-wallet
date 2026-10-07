// Neutral action chip shared by the affiliate screen and the pool balance
// header. Callers own taps, navigation and analytics.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/theme/app_theme.dart';

/// Neutral surface chip.
/// 54h, 16r corners, w800 label, 22sp icon. White in light mode and
/// surface in dark so it stays distinct from the screen gradient.
class NeutralActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool disabled;

  const NeutralActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = isLight ? Colors.white : c.surface;
    final fg = disabled ? c.textTertiary : c.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.55 : 1.0,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: 54.h),
          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppRadius.buttonBorder,
            border: Border.all(
              color: isLight ? c.border : c.borderSubtle,
              width: isLight ? 1.0 : 0.5,
            ),
            boxShadow: isLight
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 22.sp),
              SizedBox(width: 8.w),
              Flexible(
                  child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: fg,
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}
