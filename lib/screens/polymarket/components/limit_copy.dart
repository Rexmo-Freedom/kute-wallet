// lib/screens/polymarket/components/limit_copy.dart
//
// What the Predictions tickets say about a resting limit order that cannot
// be placed as it stands (limit_order_rules.dart): off the market's tick,
// out of its range, under the venue's minimum. One wording for the buy
// slip, the sell ticket and their Advanced pages, said in red under the
// figure with the button shut.

import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/services/polymarket/limit_order_rules.dart';

/// "5", "5.5": a share minimum as the venue states it.
String polymarketSharesFigure(double shares) =>
    shares == shares.roundToDouble()
        ? shares.toStringAsFixed(0)
        : shares.toStringAsFixed(2);

/// Why [price] cannot rest on a market whose tick is [tick]; null when it
/// can.
String? polymarketLimitIssueText(
    AppLocalizations l10n, double price, double tick) =>
    switch (polymarketLimitPriceIssue(price, tick)) {
      PolymarketLimitPriceIssue.offTick =>
        l10n.betLimitPriceSteps(polymarketLimitCentsLabel(tick)),
      PolymarketLimitPriceIssue.outOfRange => l10n.betLimitPriceRange(
          polymarketLimitCentsLabel(tick),
          polymarketLimitCentsLabel(1 - tick)),
      null => null,
    };

/// What a limit refused before its approval says on the ticket
/// ([PolymarketLimitRefused]): what to change. Nothing was signed.
String polymarketLimitRefusalMessage(
    AppLocalizations l10n, PolymarketLimitRefused e) {
  final tick = e.tick;
  return switch (e.reason) {
    PolymarketLimitRefusal.offTick when tick != null =>
      l10n.betLimitPriceSteps(polymarketLimitCentsLabel(tick)),
    PolymarketLimitRefusal.outOfRange when tick != null =>
      l10n.betLimitPriceRange(polymarketLimitCentsLabel(tick),
          polymarketLimitCentsLabel(1 - tick)),
    PolymarketLimitRefusal.belowMinimum => l10n.betLimitMinimumShares(
        polymarketSharesFigure(
            e.minShares ?? kPolymarketDefaultMinOrderShares)),
    _ => l10n.betConnectionUnavailable,
  };
}
