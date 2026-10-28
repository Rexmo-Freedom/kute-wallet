// The slips' figures: a small title and one number, two side by side,
// with no tile around them (the position screens keep their tiles), a
// small pill for what the order does to a position already held, and the
// money's journey where the figures were while the money moves.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/position_rows_card.dart'
    show positionTileValueStyle;
import 'package:kute/screens/shared/slip_form_body.dart' show SlipDensity;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/theme/app_theme.dart';

/// A money figure's zero, as a slip's figure shows it before there is
/// one: the formatted zero without its decimals ("$0.00" reads "$0",
/// "0,00 €" reads "0 €").
String slipZeroFigure(String formattedZero) =>
    formattedZero.replaceFirst(RegExp(r'[.,]0+(?!\d)'), '');

/// One of a slip's two figures: a small quiet title and one number under
/// it, with no box, no background and no line under the number. Lined up
/// with the amount above it. [dim] keeps a figure that is being worked
/// out again on screen, quieter. [onTap] (the fee) opens what is behind
/// the number; a small chevron after the title says so.
class SlipFigure extends StatelessWidget {
  const SlipFigure({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.dim = false,
    this.onTap,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool dim;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final compact = SlipDensity.compact(context);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(
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
          ),
          if (onTap != null)
            Icon(Icons.chevron_right_rounded,
                size: 16.sp, color: c.textTertiary),
        ]),
        SizedBox(height: compact ? 2.h : 4.h),
        AnimatedOpacity(
          opacity: dim ? 0.45 : 1,
          duration: kuteMotion(context, const Duration(milliseconds: 160)),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                maxLines: 1,
                style: positionTileValueStyle(c, color: valueColor)),
          ),
        ),
      ],
    );
    if (onTap == null) return body;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: body,
      ),
    );
  }
}

/// Two [SlipFigure]s side by side, each in its own half, tops aligned.
class SlipFigures extends StatelessWidget {
  const SlipFigures({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          SizedBox(width: 16.w),
          Expanded(child: right),
        ],
      );
}

/// A small pill under the amount: what the order does to the position
/// held on this side ("▲ Adds to your Long").
class SlipPositionPill extends StatelessWidget {
  const SlipPositionPill({super.key, required this.long, required this.text});

  final bool long;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('slip-position-pill'),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Text(
        '${long ? '▲' : '▼'} $text',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: c.textPrimary,
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

/// While the money moves, the top of a buy slip: one big number, the
/// order being bought (the amount placed at the tap, as big as the slip's
/// amount), and the order's line under it ("UP · pays $20.68 if you
/// win", "Long ETH · Market order").
///
/// The number is the order and only the order, steady from the tap until
/// the order is done or stopped: never what the venue already holds,
/// never zero while it runs. The [record]'s own amount (captured at the
/// tap) wins; before there is one, [orderUsd]; a rebuild that hands in
/// nothing keeps the last amount shown.
class SlipOrderFigure extends StatefulWidget {
  const SlipOrderFigure({
    super.key,
    required this.record,
    required this.orderUsd,
    required this.money,
    required this.orderLine,
  });

  final FundedOrderRecord? record;

  /// The order when there is no [record] to read it from.
  final double orderUsd;
  final String Function(double usd) money;
  final String orderLine;

  @override
  State<SlipOrderFigure> createState() => _SlipOrderFigureState();
}

class _SlipOrderFigureState extends State<SlipOrderFigure> {
  double? _shown;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final placed = widget.record?.label.orderUsd;
    final value = placed != null && placed > 0
        ? placed
        : widget.orderUsd > 0
            ? widget.orderUsd
            : _shown ?? 0;
    if (value > 0) _shown = value;
    // The whole width, always: a longer figure must never resize (and
    // clip) the block around it.
    return SizedBox(
      key: const ValueKey('slip-order-figure'),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              widget.money(value),
              key: const ValueKey('slip-order-figure-amount'),
              maxLines: 1,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 56.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(height: 10.h),
          Text(
            widget.orderLine,
            key: const ValueKey('slip-order-figure-line'),
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The money's journey where the slip's figures were: [steps] (a
/// `SlipFundingSteps`, whose status line says what is moving). Grows in
/// and fades in as the figures fold away ([StepsReveal]); null shows
/// nothing.
class SlipJourney extends StatelessWidget {
  const SlipJourney({super.key, this.steps});

  final Widget? steps;

  @override
  Widget build(BuildContext context) {
    final shown = steps;
    return StepsReveal(
      child: shown == null
          ? null
          : Padding(
              padding: EdgeInsets.only(top: 18.h, bottom: 8.h),
              child: shown,
            ),
    );
  }
}
