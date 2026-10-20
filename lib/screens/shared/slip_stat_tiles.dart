// The slips' figures: a small title and one number, two side by side,
// with no tile around them (the position screens keep their tiles), a
// small pill for what the order does to a position already held, and the
// money's journey where the figures were while the money moves.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/animated_balance.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/money_steps_view.dart' show moneyPlaceName;
import 'package:kute/screens/shared/position_rows_card.dart'
    show positionTileValueStyle;
import 'package:kute/screens/shared/slip_form_body.dart' show SlipDensity;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
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

/// What a funded order is paid with, in one quiet line: the venue's own
/// cash first, then each source the money moves from ("$9.86 from
/// Investing + $2.14 from Bitcoin", "$5.00 from Bitcoin"). Null with
/// nothing on the step graph to say it from.
String? slipFundingSourcesLine(AppLocalizations l10n, FundedOrderRecord r,
    String Function(double usd) money) {
  final legs = r.steps.legs.toList();
  if (legs.isEmpty) return null;
  // A leg that carries on what another leg brought (Bitcoin → Dollars,
  // then Dollars onward) is the same money, said once at its source.
  final through = {for (final l in legs) l.to}..remove(null);
  final sources = <MoneyPlace, double>{};
  for (final l in legs) {
    final from = l.from;
    if (from == null || through.contains(from) || l.usd <= 0) continue;
    sources[from] = (sources[from] ?? 0) + l.usd;
  }
  if (sources.isEmpty) return null;
  final venue = _venuePlace(r.label.venue);
  final moved = sources.values.fold<double>(0, (a, b) => a + b);
  final own = r.label.orderUsd - moved;
  return [
    if (own >= 0.01)
      l10n.moveAmountFrom(money(own), moneyPlaceName(l10n, venue)),
    for (final e in sources.entries)
      l10n.moveAmountFrom(money(e.value), moneyPlaceName(l10n, e.key)),
  ].join(' + ');
}

/// Where a leg's money lands for an order on [venue]: the venue itself
/// (a leg with no destination of its own goes to the order's venue).
bool _landsInVenue(MoneyStep leg, MoneyPlace venue) =>
    leg.to == null || leg.to == venue;

MoneyPlace _venuePlace(OneBalanceVenue venue) => switch (venue) {
      OneBalanceVenue.predictions => MoneyPlace.predictions,
      OneBalanceVenue.investing => MoneyPlace.investing,
    };

/// How long the order's figure takes to roll up to a leg that landed.
const Duration kSlipOrderRollDuration = Duration(milliseconds: 600);

/// While the money moves, the top of a buy slip: one big number, the
/// order being bought, as big as the slip's amount, and the order's line
/// under it ("UP · pays $20.68 if you win", "Long ETH · Market order").
///
/// The number starts at the part of the order the venue already holds
/// (the order less what the plan moves into it) and rolls up by each
/// leg's own amount as it lands (the app's [AnimatedBalance] roll,
/// [kSlipOrderRollDuration]; at once under Reduce Motion), ending at
/// exactly the order. A [record] of null (money made ready before
/// Confirm) shows the order as it is.
class SlipOrderFigure extends StatelessWidget {
  const SlipOrderFigure({
    super.key,
    required this.venue,
    required this.record,
    required this.orderUsd,
    required this.money,
    required this.orderLine,
  });

  final OneBalanceVenue venue;
  final FundedOrderRecord? record;

  /// The order when there is no [record] to read it from.
  final double orderUsd;
  final String Function(double usd) money;
  final String orderLine;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = record;
    var value = orderUsd;
    if (r != null) {
      final place = _venuePlace(venue);
      final total = r.label.orderUsd;
      final legs = r.steps.legs.where((l) => _landsInVenue(l, place));
      final moving = legs.fold<double>(0, (a, l) => a + l.usd);
      final landed = legs
          .where((l) => l.status == MoneyStepStatus.done)
          .fold<double>(0, (a, l) => a + l.usd);
      value = ((total - moving).clamp(0.0, total) + landed)
          .clamp(0.0, total)
          .toDouble();
    }
    // The whole width, always: the figure growing a digit as it rolls
    // must never resize (and clip) the block around it.
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
            child: AnimatedBalance(
              key: const ValueKey('slip-order-figure-amount'),
              text: money(value),
              duration: kSlipOrderRollDuration,
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
            orderLine,
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
/// `SlipFundingSteps`), then [line] quietly under it. Grows in and fades
/// in as the figures fold away ([StepsReveal]); null shows nothing.
class SlipJourney extends StatelessWidget {
  const SlipJourney({super.key, this.steps, this.line});

  final Widget? steps;
  final String? line;

  @override
  Widget build(BuildContext context) {
    final shown = steps;
    final c = context.colors;
    return StepsReveal(
      child: shown == null
          ? null
          : Padding(
              padding: EdgeInsets.only(top: 18.h, bottom: 8.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  shown,
                  if (line != null) ...[
                    SizedBox(height: 10.h),
                    Text(
                      line!,
                      key: const ValueKey('slip-journey-sources'),
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
