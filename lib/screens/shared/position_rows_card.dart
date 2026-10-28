// What a position is made of, as plain rows on the app's card: a quiet
// label on the left, its figure right-aligned (the position screens'
// Details sheets). And the position screens' shared language: a figure on
// its own tile, two side by side ([PositionStatTiles]), and plain rows
// that open something ([PositionLinkRow]), so the Predictions and
// Investing positions read as one product.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/shared/slip_form_body.dart' show SlipDensity;

import 'package:kute/screens/shared/side_tint_palette.dart' show isSideTinted;
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

  final Key? key;

  const PositionRow(this.label, this.value,
      {this.valueColor, this.child, this.key});
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

  Widget _row(AppColorsExtension c, PositionRow row) => Row(
        key: row.key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.label,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
            ),
          ),
          SizedBox(width: 16.w),
          // The figure takes the rest of the line and wraps under itself
          // when it is long (a team's name as the outcome).
          Expanded(
            child: row.child ??
                Text(
                  row.value,
                  textAlign: TextAlign.right,
                  style: positionRowValueStyle(c, color: row.valueColor),
                ),
          ),
        ],
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

/// One figure of a position on its own tile (the app's card): a quiet
/// label, the figure large, and a quiet line under it. Two sit side by
/// side in [PositionStatTiles], on the Predictions and Investing position
/// screens and the market sheets' "Your investment" cards.
class PositionStatTile extends StatelessWidget {
  final String label;

  /// The figure, in [positionTileValueStyle]; smaller rather than cut.
  final Widget value;

  /// The quiet line under it ([positionTileCaptionStyle]), if any;
  /// smaller rather than cut too.
  final Widget? caption;

  /// Plain, on whatever card holds it: no tile of its own.
  final bool bare;

  const PositionStatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.bare = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // On a slip short of room the tile keeps its label and figure and
    // drops the small line under it.
    final compact = SlipDensity.compact(context);
    final caption = compact ? null : this.caption;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
        SizedBox(height: compact ? 2.h : 4.h),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: value,
        ),
        if (caption != null) ...[
          SizedBox(height: 4.h),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: caption,
          ),
        ],
      ],
    );
    if (bare) return body;
    return Container(
      padding: EdgeInsets.fromLTRB(
          14.w, compact ? 8.h : 12.h, 14.w, compact ? 8.h : 12.h),
      // On a side-tinted sheet (Sell, Close) the tile is the sheet's
      // translucent ink, with no shadow to muddy the colour.
      decoration: isSideTinted(c)
          ? BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: c.borderSubtle, width: 0.5),
            )
          : AppDecorations.card(context),
      child: body,
    );
  }
}

/// Two [PositionStatTile]s side by side, as tall as the taller.
class PositionStatTiles extends StatelessWidget {
  final Widget left;
  final Widget right;
  const PositionStatTiles({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            SizedBox(width: 10.w),
            Expanded(child: right),
          ],
        ),
      );
}

/// A tile's figure: large, bold, tabular.
TextStyle positionTileValueStyle(AppColorsExtension c, {Color? color}) =>
    TextStyle(
      color: color ?? c.textPrimary,
      fontSize: 24.sp,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// The quiet line under a tile's figure (a profit or loss in its colour).
TextStyle positionTileCaptionStyle(AppColorsExtension c, {Color? color}) =>
    TextStyle(
      color: color ?? c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Which side is held, in its colour: a soft pill with an up or down
/// marker when the side has a direction ("You hold Up", "Long"). The
/// Predictions position screen's pill, and the Sell and Close sheets'
/// "You hold" line.
class PositionSidePill extends StatelessWidget {
  final String text;
  final Color color;

  /// True draws the up marker, false the down one, null none (a team, a
  /// many-outcome market's outcome).
  final bool? up;

  const PositionSidePill({
    super.key,
    required this.text,
    required this.color,
    this.up,
  });

  @override
  Widget build(BuildContext context) {
    final dir = up;
    return Container(
      padding: EdgeInsets.fromLTRB(dir != null ? 6.w : 12.w, 5.h, 12.w, 5.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dir != null)
            Icon(
              dir ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
              color: color,
              size: 20.sp,
            ),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain row that opens something, under a hairline: the label, an
/// optional quiet figure ("Sell at", "Stop loss") and a chevron. The
/// position screens' "Protect it", "Add margin" and "Details", the same
/// look as the market sheet's "Rules and resolution" row.
class PositionLinkRow extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;

  /// An optional glyph before the label (the chart screens' "Advanced
  /// chart" row).
  final IconData? icon;

  /// No hairline over it (the first row inside a card).
  final bool divider;

  const PositionLinkRow({
    super.key,
    required this.label,
    this.value,
    required this.onTap,
    this.icon,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 14.h),
          decoration: BoxDecoration(
            border: divider
                ? Border(top: BorderSide(color: c.borderSubtle, width: 0.5))
                : null,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: c.textSecondary, size: 20.sp),
                SizedBox(width: 10.w),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.settingsTitle(context),
                ),
              ),
              if (value != null) ...[
                SizedBox(width: 12.w),
                // The figure right-aligned by the chevron, never more than
                // half the line.
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.45),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
              SizedBox(width: 4.w),
              Icon(Icons.chevron_right_rounded,
                  color: c.textTertiary, size: 22.sp),
            ],
          ),
        ),
      ),
    );
  }
}
