// lib/screens/shared/money_steps_view.dart
//
// The ONE widget that shows a money step graph ([MoneyStepGraph]) as the
// staged sub-steps under a slip's or a sheet's button: every leg on its
// own line, completing on its own ("Moving $8.00 from Bitcoin" → "Moved
// $8.00 from Bitcoin ✓"), the venue's readiness as a stage line with its
// sub-steps indented under it ("Getting your prediction ready" →
// "Converting to pUSD", "Confirming balance"), then the order ("Placing
// $15 on Yes") or the purchase ("Buying $5.00 of Bitcoin", "Arriving in
// Bitcoin"). The `SlipFundingSteps` look: the note's type and colours,
// its small spinner while running, a check once done, the slips' error
// sign when failed. No new chrome.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/shared/kute_motion.dart' show kuteReduceMotion;

/// The balance's own name, as the portfolio names it.
String moneyPlaceName(AppLocalizations l10n, MoneyPlace place) =>
    switch (place) {
      MoneyPlace.bitcoin => l10n.bitcoin,
      MoneyPlace.dollars => l10n.portfolioBalanceDollars,
      MoneyPlace.predictions => l10n.predictions,
      MoneyPlace.investing => l10n.trading,
    };

/// The words of one step in its current state. [money] formats dollars
/// the screen's way; [placeLine] is the order's own line ("Placing $15 on
/// Yes"), which the slip words.
String moneyStepLine(
  AppLocalizations l10n,
  MoneyStep s,
  String Function(double usd) money, {
  String? placeLine,
}) {
  final done = s.status == MoneyStepStatus.done;
  switch (s.kind) {
    case MoneyStepKind.leg:
      final from = moneyPlaceName(l10n, s.from ?? MoneyPlace.dollars);
      if (s.status == MoneyStepStatus.fellBack) {
        return l10n.moneyStepFellBack(from, l10n.portfolioBalanceDollars);
      }
      if (s.status == MoneyStepStatus.failed) {
        return l10n.moneyStepMoveFailed(money(s.usd), from);
      }
      final to = s.to;
      if (to != null) {
        final dest = moneyPlaceName(l10n, to);
        return done
            ? l10n.moneyStepMovedFromTo(money(s.usd), from, dest)
            : l10n.moneyStepMovingFromTo(money(s.usd), from, dest);
      }
      return done
          ? l10n.moneyStepMovedFrom(money(s.usd), from)
          : l10n.moneyStepMovingFrom(money(s.usd), from);
    case MoneyStepKind.convert:
      return done ? l10n.moneyStepConverted : l10n.moneyStepConverting;
    case MoneyStepKind.approve:
      return done ? l10n.moneyStepApproved : l10n.moneyStepApproving;
    case MoneyStepKind.confirm:
      return done ? l10n.moneyStepConfirmed : l10n.moneyStepConfirming;
    case MoneyStepKind.credit:
      return done ? l10n.moneyStepCredited : l10n.moneyStepCrediting;
    case MoneyStepKind.buy:
      return done
          ? l10n.moneyStepBought(money(s.usd))
          : l10n.moneyStepBuying(money(s.usd));
    case MoneyStepKind.arrive:
      return done ? l10n.moneyStepArrived : l10n.moneyStepArriving;
    case MoneyStepKind.place:
      return placeLine ?? '';
  }
}

/// Whether a step is shown: a skipped one never is, and the conversion
/// and the allowance (needed only sometimes) only once they started.
bool moneyStepShown(MoneyStep s) {
  if (s.status == MoneyStepStatus.skipped) return false;
  if ((s.kind == MoneyStepKind.convert || s.kind == MoneyStepKind.approve) &&
      s.status == MoneyStepStatus.waiting) {
    return false;
  }
  return true;
}

/// One rendered line: its words, its state, and whether it is a
/// sub-step (indented under its stage).
@immutable
class MoneyStepLine {
  const MoneyStepLine(this.text, this.status, {this.sub = false, this.id});
  final String text;
  final MoneyStepStatus status;
  final bool sub;
  final String? id;
}

/// The lines [graph] shows, in order: the legs, the readiness stage with
/// its sub-steps under [readyLabel], then the rest (the order, the
/// purchase, the arrival). Pure, so the order of lines is tested apart.
List<MoneyStepLine> moneyStepLines(
  AppLocalizations l10n,
  MoneyStepGraph graph,
  String Function(double usd) money, {
  String? readyLabel,
  String? placeLine,
}) {
  final lines = <MoneyStepLine>[];
  final readiness = graph.steps.where((s) => s.kind.readiness).toList();
  var readyShown = false;
  for (final s in graph.steps) {
    if (s.kind.readiness) {
      if (readyShown) continue;
      readyShown = true;
      final stage = stageStatusOf(readiness);
      if (stage == null) continue;
      if (readyLabel != null) {
        lines.add(MoneyStepLine(readyLabel, stage, id: 'ready'));
      }
      for (final r in readiness) {
        if (!moneyStepShown(r)) continue;
        lines.add(MoneyStepLine(moneyStepLine(l10n, r, money), r.status,
            sub: readyLabel != null, id: r.id));
      }
      continue;
    }
    if (!moneyStepShown(s)) continue;
    lines.add(MoneyStepLine(
        moneyStepLine(l10n, s, money, placeLine: placeLine), s.status,
        id: s.id));
  }
  return lines;
}

/// The graph as the staged sub-steps (see the file header). [note] is
/// the one plain line under them once something stopped (what happened
/// and where the money is); [slow] adds "Taking longer than usual".
class MoneyStepsView extends StatelessWidget {
  const MoneyStepsView({
    super.key,
    required this.lines,
    this.slow = false,
    this.note,
  });

  final List<MoneyStepLine> lines;
  final bool slow;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final still = kuteReduceMotion(context);
    Widget lead(int i, MoneyStepStatus status) => switch (status) {
          MoneyStepStatus.failed => Icon(Icons.error_outline_rounded,
              key: ValueKey('money-step-failed-$i'),
              size: 14.r,
              color: c.textPrimary),
          MoneyStepStatus.done || MoneyStepStatus.skipped => Icon(
              Icons.check_rounded,
              key: ValueKey('money-step-done-$i'),
              size: 14.r,
              color: c.textSecondary),
          MoneyStepStatus.fellBack => Icon(Icons.subdirectory_arrow_right,
              key: ValueKey('money-step-fellback-$i'),
              size: 14.r,
              color: c.textSecondary),
          MoneyStepStatus.running => SizedBox.square(
              key: ValueKey('money-step-running-$i'),
              dimension: 12.r,
              child: still
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                          color: c.textSecondary, shape: BoxShape.circle))
                  : CircularProgressIndicator(
                      strokeWidth: 1.6, color: c.textSecondary),
            ),
          MoneyStepStatus.waiting => SizedBox.square(
              key: ValueKey('money-step-waiting-$i'), dimension: 12.r),
        };

    final anyFailed = lines.any((l) => l.status == MoneyStepStatus.failed);
    return Padding(
      key: const ValueKey('money-steps'),
      padding: EdgeInsets.only(top: 10.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++)
            Padding(
              key: ValueKey('money-step-${lines[i].id ?? i}'),
              padding: EdgeInsets.only(
                  top: 3.h, bottom: 3.h, left: lines[i].sub ? 22.w : 0),
              child: Row(
                children: [
                  SizedBox(
                    width: 22.w,
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: lead(i, lines[i].status)),
                  ),
                  Flexible(
                    child: Text(
                      lines[i].text,
                      style: TextStyle(
                        color: switch (lines[i].status) {
                          MoneyStepStatus.failed => c.textPrimary,
                          MoneyStepStatus.waiting => c.textTertiary,
                          _ => c.textSecondary,
                        },
                        fontSize: (lines[i].sub ? 12 : 13).sp,
                        height: 1.35,
                        fontWeight: lines[i].status == MoneyStepStatus.running
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (slow && !anyFailed)
            Padding(
              padding: EdgeInsets.only(top: 4.h, left: 22.w),
              child: Text(
                context.l10n.slipStepTakingLonger,
                key: const ValueKey('money-steps-slow'),
                style: TextStyle(
                    color: c.textTertiary, fontSize: 12.sp, height: 1.35),
              ),
            ),
          if (note case final line?)
            Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: Text(
                line,
                key: const ValueKey('money-steps-note'),
                style: TextStyle(
                    color: c.textSecondary, fontSize: 13.sp, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }
}
