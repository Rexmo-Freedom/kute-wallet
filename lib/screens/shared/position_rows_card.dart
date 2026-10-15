// What a position is made of, as plain rows on the app's card: a quiet
// label on the left, its figure right-aligned. Shared by the open
// Predictions position screen and the open Investing position screen so
// the two read as one product. A row can also be one plain sentence (the
// position's risk line) or open something (the position's "Protect it").

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/theme/app_theme.dart';

/// One row of a [PositionRowsCard].
class PositionRow {
  final String label;
  final String value;

  /// The figure's colour; the primary text colour when null. Only a
  /// profit or a loss takes the app's up / down colours.
  final Color? valueColor;

  /// A figure the plain text cannot carry (part of it coloured), in place
  /// of [value]; still right-aligned and wrapping under itself.
  final Widget? child;

  /// A small button right beside the figure (the Investing position's
  /// "Add margin"), moving under it when both do not fit on the line; the
  /// row centres on it.
  final Widget? action;

  /// Opens what the row names (the position's "Protect it"): the whole
  /// row is the tap target and a chevron follows the figure.
  final VoidCallback? onTap;

  /// A plain sentence across the whole row in the label's style, in place
  /// of the label and figure (the position's risk line).
  final bool note;

  final Key? key;

  const PositionRow(this.label, this.value,
      {this.valueColor, this.child, this.action, this.onTap, this.key})
      : note = false;

  /// One sentence across the row, in the labels' quiet style.
  const PositionRow.note(this.label, {this.key})
      : value = '',
        valueColor = null,
        child = null,
        action = null,
        onTap = null,
        note = true;
}

class PositionRowsCard extends StatelessWidget {
  final List<PositionRow> rows;
  const PositionRowsCard({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: AppDecorations.card(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SizedBox(height: 12.h),
            _row(c, rows[i]),
          ],
        ],
      ),
    );
  }

  static TextStyle _labelStyle(AppColorsExtension c) => TextStyle(
        color: c.textSecondary,
        fontSize: 14.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
      );

  Widget _row(AppColorsExtension c, PositionRow row) {
    if (row.note) {
      return SizedBox(
        key: row.key,
        width: double.infinity,
        child: Text(row.label,
            style: _labelStyle(c).copyWith(height: 1.35)),
      );
    }
    final line = Row(
      key: row.onTap == null ? row.key : null,
      crossAxisAlignment: row.action == null && row.onTap == null
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(row.label, style: _labelStyle(c)),
        SizedBox(width: 16.w),
        // The figure takes the rest of the line and wraps under
        // itself when it is long (a team's name as the outcome).
        Expanded(
          child: row.action == null
              ? _figure(c, row)
              // The button beside the figure while both fit on
              // the line; under it, right-aligned, when they do
              // not (a narrow phone, large text, a long word).
              : Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10.w,
                  runSpacing: 6.h,
                  children: [_figure(c, row), row.action!],
                ),
        ),
        if (row.onTap != null) ...[
          SizedBox(width: 4.w),
          Icon(Icons.chevron_right_rounded,
              color: c.textTertiary, size: 22.sp),
        ],
      ],
    );
    final onTap = row.onTap;
    if (onTap == null) return line;
    return Semantics(
      button: true,
      child: InkWell(
        key: row.key,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: line,
      ),
    );
  }

  Widget _figure(AppColorsExtension c, PositionRow row) =>
      row.child ??
      Text(
        row.value,
        textAlign: TextAlign.right,
        style: positionRowValueStyle(c, color: row.valueColor),
      );
}

/// The figure's style on a [PositionRowsCard] row, for a custom
/// [PositionRow.child] that should read the same.
TextStyle positionRowValueStyle(AppColorsExtension c, {Color? color}) =>
    TextStyle(
      color: color ?? c.textPrimary,
      fontSize: 15.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
