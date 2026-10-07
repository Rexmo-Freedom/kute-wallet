// lib/screens/shared/charts/kute_chart_range_pills.dart
//
// The range row under every chart (the Predictions market chart's: LIVE
// 1H 6H 1D 1W 1M ALL), shared so the Price chart on Home and the wallet
// screens, the Dollars Earn chart, the Investing and Predictions
// statistics and the venue charts all read the same (the Balance charts
// of Bitcoin wallets and Dollars have no range row: whole history): the ranges share the width, the
// selected one sits on the elevated surface in the primary colour, the
// others are quiet. [KuteRangePill] is one pill of it, for a row that
// scrolls (the Investing chart's candle sizes).

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/theme/app_theme.dart';

/// One range pill.
class KuteRangePill extends StatelessWidget {
  const KuteRangePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.expand = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// A small mark before the label (the LIVE dot).
  final Widget? leading;

  /// Fill the slot the row gives it (a row of equal pills) rather than
  /// hugging the label (a scrolling row).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final text = Text(
      label,
      maxLines: 1,
      style: TextStyle(
        color: selected ? c.textPrimary : c.textTertiary,
        fontSize: 14.sp,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: expand ? 0 : 12.w,
            vertical: 8.h,
          ),
          margin: EdgeInsets.symmetric(horizontal: 2.w),
          decoration: BoxDecoration(
            color: selected ? c.surfaceElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(8.r),
          ),
          alignment: expand ? Alignment.center : null,
          child: leading == null
              ? text
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [leading!, SizedBox(width: 4.w), text],
                  ),
                ),
        ),
      ),
    );
  }
}

/// A row of range pills sharing the width.
class KuteRangePills extends StatelessWidget {
  const KuteRangePills({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.isShown,
    this.leadingFor,
  });

  final List<String> labels;
  final int selectedIndex;

  /// Called with the index tapped, the selected one included (a chart
  /// may put its view back on the whole range then).
  final ValueChanged<int> onSelected;

  /// Leaves a range out of the row (one with nothing to draw).
  final bool Function(int index)? isShown;

  /// A small mark before a label (the LIVE dot).
  final Widget? Function(int index, bool selected)? leadingFor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          if (i == selectedIndex || (isShown?.call(i) ?? true))
            Expanded(
              child: KuteRangePill(
                label: labels[i],
                selected: i == selectedIndex,
                expand: true,
                leading: leadingFor?.call(i, i == selectedIndex),
                onTap: () => onSelected(i),
              ),
            ),
      ],
    );
  }
}
