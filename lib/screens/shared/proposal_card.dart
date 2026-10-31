// lib/screens/shared/proposal_card.dart
//
// The one confirm surface for money. A proposal names what will happen,
// how much, where the money comes from, what it costs and the worst case,
// then offers one button; the person confirms it in the app, every time.
// The slips already read this way. The Move sheet, and anything Sal or a
// connected assistant (MCP) prepares, show the same card: a proposal from
// any door is confirmed the same way, and a prepared one says who prepared
// it ([ProposalCard.originLabel]) and can be dismissed as easily as taken.
//
// A proposal is never confirmed by the thing that prepared it. The card
// has no way to confirm itself: [onConfirm] is the person's tap, behind
// whatever step-up the flow asks for.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/theme/app_theme.dart';

/// One fact of a proposal: "From · Dollars", "Fee · $0.05", "Worst case ·
/// $4.90". [valueColor] colours a result that is a profit or a loss.
class ProposalLine {
  const ProposalLine(this.label, this.value, {this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;
}

class ProposalCard extends StatelessWidget {
  const ProposalCard({
    super.key,
    required this.title,
    required this.amountText,
    required this.confirmLabel,
    required this.onConfirm,
    this.subtitle,
    this.lines = const [],
    this.originLabel,
    this.dismissLabel,
    this.onDismiss,
    this.leading,
  });

  /// What will happen, in the person's words: "Put $5 in Gold",
  /// "Send $20 to Rina", "Move $10 to Dollars".
  final String title;

  /// One line under the title: the market, the recipient, the route.
  final String? subtitle;

  /// The figure, large: what leaves (or arrives).
  final String amountText;

  /// The facts under the figure, in order.
  final List<ProposalLine> lines;

  /// Who prepared it, when it was not the person just now ("Prepared by
  /// Sal"). Null for a proposal the person built themselves.
  final String? originLabel;

  /// The one button. A null [onConfirm] draws it disabled.
  final String confirmLabel;
  final VoidCallback? onConfirm;

  /// A quiet second action under the button ("Not now"); nothing when
  /// null.
  final String? dismissLabel;
  final VoidCallback? onDismiss;

  /// The mark of what the proposal is about (a market crest, a coin, a
  /// contact), 40 pt; nothing when null.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      key: const ValueKey('proposal-card'),
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : c.surface,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: isLight ? c.border : c.borderSubtle,
          width: isLight ? 1.0 : 0.5,
        ),
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (originLabel != null) ...[
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    size: 14.sp, color: c.textTertiary),
                SizedBox(width: 6.w),
                Expanded(
                  child: Text(
                    originLabel!,
                    key: const ValueKey('proposal-origin'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[
                SizedBox.square(dimension: 40.sp, child: leading),
                SizedBox(width: 12.w),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      key: const ValueKey('proposal-title'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          height: 1.2),
                    ),
                    if (subtitle != null) ...[
                      SizedBox(height: 2.h),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13.5.sp,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 12.w),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  amountText,
                  key: const ValueKey('proposal-amount'),
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 24.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ],
          ),
          if (lines.isNotEmpty) ...[
            SizedBox(height: 14.h),
            Container(
                height: isLight ? 1 : 0.5,
                color: isLight ? c.border : c.borderSubtle),
            for (final line in lines)
              Padding(
                padding: EdgeInsets.only(top: 10.h),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        line.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Flexible(
                      child: Text(
                        line.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: line.valueColor ?? c.textPrimary,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ]),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          SizedBox(height: 16.h),
          AppButton(text: confirmLabel, onPressed: onConfirm),
          if (dismissLabel != null && onDismiss != null) ...[
            SizedBox(height: 4.h),
            TextButton(
              key: const ValueKey('proposal-dismiss'),
              onPressed: onDismiss,
              child: Text(
                dismissLabel!,
                style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
