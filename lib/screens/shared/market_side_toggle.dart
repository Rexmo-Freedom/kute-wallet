// lib/screens/shared/market_side_toggle.dart
//
// The one Long / Short (Buy / Sell) switch every trading ticket uses.
//
// Built like the prediction slip's Yes / No: a leading glyph plate, the
// label beside it, and the selected half carrying the weight.
//
// On a plain surface the selected half takes the direction's own colour.
// On a sheet already painted in that colour it takes a brighter tier of
// the sheet's ink instead, because a green fill on a green sheet is
// invisible and left the switch reading backwards.
//
// Shared so the hot Hyperliquid slip, its Advanced page and the Ledger
// ticket cannot drift apart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/screens/shared/side_tint_palette.dart';
import 'package:kute/theme/app_theme.dart';

class MarketSideToggle extends StatelessWidget {
  const MarketSideToggle({
    super.key,
    required this.isUp,
    required this.upLabel,
    required this.downLabel,
    required this.onChanged,
    this.enabled = true,
  });

  /// True when the "up" side (Long / Buy) is the selected one.
  final bool isUp;

  final String upLabel;
  final String downLabel;

  /// Called with the newly picked side. Never fired for the half that is
  /// already selected.
  final ValueChanged<bool> onChanged;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Expanded(
          child: _half(
            context,
            label: upLabel,
            icon: Icons.trending_up_rounded,
            fill: AppColors.marketUp,
            selected: isUp,
            up: true,
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: _half(
            context,
            label: downLabel,
            icon: Icons.trending_down_rounded,
            fill: AppColors.marketDown,
            selected: !isUp,
            up: false,
          ),
        ),
      ],
    );
    return enabled ? row : Opacity(opacity: 0.5, child: row);
  }

  Widget _half(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color fill,
    required bool selected,
    required bool up,
  }) {
    final c = context.colors;
    // On a sheet already painted in a direction colour, a solid fill of
    // that same colour vanishes, and the quiet half's translucent veil
    // ends up looking like the selected one. That inversion is what made
    // this switch read backwards next to the prediction slip's, so on a
    // tinted sheet both halves are tiers of the sheet's own contrast ink,
    // exactly the way the prediction slip does it. On a plain surface the
    // direction colour is still the clearest signal, so it stays.
    final tinted = isSideTinted(c);
    final on = c.textPrimary;
    final Color background;
    final Color ink;
    final Color chipFill;
    final Color chipInk;
    final Color borderColor;
    if (tinted) {
      background =
          on.withValues(alpha: selected ? 0.32 : 0.10);
      ink = selected ? on : on.withValues(alpha: 0.82);
      chipFill = on.withValues(alpha: selected ? 0.40 : 0.18);
      chipInk = selected ? on : on.withValues(alpha: 0.82);
      borderColor =
          selected ? on.withValues(alpha: 0.62) : on.withValues(alpha: 0.24);
    } else {
      final onFill = contrastingOnColor(fill);
      background = selected ? fill : c.surface;
      ink = selected ? onFill : c.textSecondary;
      chipFill =
          selected ? onFill.withValues(alpha: 0.22) : c.surfaceLight;
      chipInk = selected ? onFill : c.textSecondary;
      borderColor =
          selected ? onFill.withValues(alpha: 0.45) : c.borderSubtle;
    }
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: (!enabled || selected)
            ? null
            : () {
                HapticFeedback.selectionClick();
                onChanged(up);
              },
        child: AnimatedContainer(
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 60.h,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.0 : 0.5,
            ),
          ),
          child: Row(
            children: [
              // The leading plate is what gives the prediction slip's
              // switch its weight, and what this one was missing.
              Container(
                width: 32.sp,
                height: 32.sp,
                decoration: BoxDecoration(
                  color: chipFill,
                  borderRadius: BorderRadius.circular(9.r),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18.sp, color: chipInk),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: -0.2,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
