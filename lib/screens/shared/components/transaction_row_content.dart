import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// The layout of one activity row: the icon tile, a one-line title over
/// a one-line context line, and the amount over at most one secondary
/// figure on the right. Text never wraps: titles and context ellipsize,
/// and the figures shrink to fit their column instead of breaking, so
/// every row keeps the same height at any text size.
class TransactionRowContent extends StatelessWidget {
  final Widget leading;
  final Widget title;
  final Widget subtitle;
  final Widget amount;
  final Widget? secondaryAmount;

  const TransactionRowContent({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.secondaryAmount,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // The figures get up to 45% of the row; the text takes the rest.
      final figuresMax = constraints.maxWidth * 0.45;
      Widget figure(Widget value) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: value,
          );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading,
          SizedBox(width: 12.w),
          Expanded(
            child: DefaultTextStyle.merge(
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  SizedBox(height: 2.h),
                  subtitle,
                ],
              ),
            ),
          ),
          SizedBox(width: 12.w),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: figuresMax),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                figure(amount),
                if (secondaryAmount != null) ...[
                  SizedBox(height: 2.h),
                  figure(secondaryAmount!),
                ],
              ],
            ),
          ),
        ],
      );
    });
  }
}
