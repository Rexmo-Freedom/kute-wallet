import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/theme/app_theme.dart';

/// Rows stacked inside a single card (AppDecorations.card): the Settings
/// section card, the same grouped card as the add-wallet device list.
/// No hairline between rows: the card's own edge groups them.
class KuteListGroup extends StatelessWidget {
  final List<Widget> children;
  const KuteListGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// The Settings row, shared: neutral 44 tile (surfaceLight, hairline,
/// 12.r) holding [icon] or [glyph], a 15sp w600 title, the one 13sp w500
/// secondary subtitle, and a trailing slot that defaults to the tertiary
/// 20sp chevron. Press feedback is a flat surfaceLight wash plus a haptic
/// (light impact; a selection click with [selectionHaptic]); no tinted
/// fills, no ripple.
class KuteListRow extends StatefulWidget {
  final String title;
  final IconData? icon;

  /// Drawn inside the 44 tile instead of [icon] (the Kute dog on Sal's
  /// questions).
  final Widget? glyph;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selectionHaptic;

  const KuteListRow({
    super.key,
    required this.title,
    this.icon,
    this.glyph,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.selectionHaptic = false,
  });

  @override
  State<KuteListRow> createState() => _KuteListRowState();
}

class _KuteListRowState extends State<KuteListRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final row = AnimatedContainer(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      color: _pressed ? c.surfaceLight : Colors.transparent,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44.sp,
            height: 44.sp,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: c.borderSubtle, width: 0.5),
            ),
            child: widget.glyph ??
                Icon(widget.icon, color: c.textSecondary, size: 22.sp),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  SizedBox(height: 2.h),
                  Text(
                    widget.subtitle!,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 8.w),
          widget.trailing ??
              Icon(
                Icons.chevron_right_rounded,
                color: c.textTertiary,
                size: 20.sp,
              ),
        ],
      ),
    );

    final onTap = widget.onTap;
    if (onTap == null) {
      return row;
    }

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          if (widget.selectionHaptic) {
            HapticFeedback.selectionClick();
          } else {
            HapticFeedback.lightImpact();
          }
          onTap();
        },
        child: row,
      ),
    );
  }
}
