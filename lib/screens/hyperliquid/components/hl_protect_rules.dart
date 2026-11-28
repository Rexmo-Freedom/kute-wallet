// lib/screens/hyperliquid/components/hl_protect_rules.dart
//
// The side rules of a protective order (stop loss, take profit) on an
// open position, shared by the close sheet's Advanced page and the
// chart's drag-to-move, so both say the same thing BEFORE any approval:
//
//   * the order closes the position, so it is on the opposite side
//     (a sell closes a long, a buy closes a short);
//   * a stop loss fires on the way against the position: a sell stop
//     below the price now, a buy stop above it;
//   * a take profit fires on the way for it: a sell take above the price
//     now, a buy take below it;
//   * a stop or take with a limit rests that limit once triggered: a sell
//     limit at or under its trigger, a buy limit at or over it, so the
//     triggered order can fill;
//   * a stop past the liquidation price would never fire before the
//     venue liquidates the position: a warning, not a block.
//
// A trigger on the wrong side of the price, or the price itself, fires at
// once (the venue triggers on the mark), which is never what a protective
// order is for.

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlOpenOrder;

/// A protective order on a position: a stop loss, take profit or trailing
/// stop that only closes (reduce-only, or the venue's position TP/SL). An
/// entry trigger (one that would open) is not one. A row only the
/// WebSocket has seen is not known to be one yet.
bool hlIsProtectiveOrder(HlOpenOrder o) =>
    o.detailsKnown &&
    (o.isTrailingStop || o.isTrigger) &&
    (o.reduceOnly || o.isPositionTpsl);

/// [coin]'s protective orders among [orders] (wire coin, exact), the
/// stops first, then the takes, then the trailing stops.
List<HlOpenOrder> hlProtectiveOrdersFor(List<HlOpenOrder> orders, String coin) {
  int rank(HlOpenOrder o) => o.isTrailingStop ? 2 : (o.tpsl == 'tp' ? 1 : 0);
  final mine = [
    for (final o in orders)
      if (o.coin == coin && hlIsProtectiveOrder(o)) o,
  ];
  // Stable: each kind keeps the account's own order (newest first).
  return [
    for (var r = 0; r < 3; r++)
      for (final o in mine)
        if (rank(o) == r) o,
  ];
}

/// [coin]'s stop losses among [orders] (not the trailing stops).
List<HlOpenOrder> hlStopLossesFor(List<HlOpenOrder> orders, String coin) => [
      for (final o in hlProtectiveOrdersFor(orders, coin))
        if (!o.isTrailingStop && o.tpsl == 'sl') o,
    ];

/// Why a protective trigger cannot be placed as typed; [none] when it can.
enum HlProtectIssue {
  none,
  stopAboveMark,
  stopBelowMark,
  takeBelowMark,
  takeAboveMark,
  limitAboveTrigger,
  limitBelowTrigger,
}

/// The rule for a trigger order on the side [closeIsBuy] (the closing
/// side: a buy closes a short). [tpsl] is 'sl' or 'tp'. [limitPx] is the
/// resting price of a stop / take limit, null for a market trigger.
HlProtectIssue hlProtectIssue({
  required bool closeIsBuy,
  required String tpsl,
  required double trigger,
  required double mark,
  double? limitPx,
}) {
  if (mark > 0 && trigger > 0) {
    if (tpsl == 'sl') {
      if (!closeIsBuy && trigger >= mark) return HlProtectIssue.stopAboveMark;
      if (closeIsBuy && trigger <= mark) return HlProtectIssue.stopBelowMark;
    } else {
      if (!closeIsBuy && trigger <= mark) return HlProtectIssue.takeBelowMark;
      if (closeIsBuy && trigger >= mark) return HlProtectIssue.takeAboveMark;
    }
  }
  final limit = limitPx;
  if (limit != null && limit > 0 && trigger > 0) {
    if (!closeIsBuy && limit > trigger) return HlProtectIssue.limitAboveTrigger;
    if (closeIsBuy && limit < trigger) return HlProtectIssue.limitBelowTrigger;
  }
  return HlProtectIssue.none;
}

/// The inline line for [issue], null for [HlProtectIssue.none].
String? hlProtectIssueText(AppLocalizations l10n, HlProtectIssue issue) =>
    switch (issue) {
      HlProtectIssue.none => null,
      HlProtectIssue.stopAboveMark => l10n.hlProtectStopBelowPrice,
      HlProtectIssue.stopBelowMark => l10n.hlProtectStopAbovePrice,
      HlProtectIssue.takeBelowMark => l10n.hlProtectTakeAbovePrice,
      HlProtectIssue.takeAboveMark => l10n.hlProtectTakeBelowPrice,
      HlProtectIssue.limitAboveTrigger => l10n.hlProtectLimitAtOrBelowTrigger,
      HlProtectIssue.limitBelowTrigger => l10n.hlProtectLimitAtOrAboveTrigger,
    };

/// A stop at or past the liquidation price: the venue would liquidate the
/// position before the stop fires. [closeIsBuy] is the closing side.
bool hlStopPastLiquidation({
  required bool closeIsBuy,
  required double trigger,
  required double? liquidation,
}) {
  final liq = liquidation;
  if (liq == null || !liq.isFinite || liq <= 0 || trigger <= 0) return false;
  // Closing a long (a sell) the stop is under the price: past the
  // liquidation when at or under it; a short's mirror.
  return closeIsBuy ? trigger >= liq : trigger <= liq;
}

/// A resting limit that would cross the book at once (a sell under the
/// price, a buy over it): it fills now, as a taker, at the taker fee.
bool hlLimitCrossesNow({
  required bool isBuy,
  required double limitPx,
  required double mark,
}) {
  if (mark <= 0 || limitPx <= 0) return false;
  return isBuy ? limitPx > mark : limitPx < mark;
}
