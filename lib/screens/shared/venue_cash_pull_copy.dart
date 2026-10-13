// lib/screens/shared/venue_cash_pull_copy.dart
//
// The words an action shows while it pulls venue cash home to Dollars
// (lib/services/one_balance/venue_cash_source.dart), built only from the
// one-balance strings the Investments header already uses: one
// "$X coming back from Predictions" line per leg, and, when the money has
// not landed in time, the same lines plus "It can take a few minutes to
// show in your balance."

import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';

/// The venue's name as the Investments header names it.
String venueCashVenueName(AppLocalizations l10n, OneBalanceVenue venue) =>
    switch (venue) {
      OneBalanceVenue.investing => l10n.trading,
      OneBalanceVenue.predictions => l10n.predictions,
    };

String _usd(double usd) => '\$${usd.toStringAsFixed(2)}';

/// One line per leg of [plan], fastest first.
String venueCashProgressText(AppLocalizations l10n, VenueCashPlan plan) => [
      for (final p in plan.pulls)
        l10n.oneBalanceComingBack(
            _usd(p.usd), venueCashVenueName(l10n, p.venue)),
    ].join('\n');

/// Why the action stopped after a pull, or null when nothing was pulled
/// (the caller then shows its own failure). Names each leg that went,
/// then says the money can take a few minutes to show.
String? venueCashStoppedText(
    AppLocalizations l10n, VenueCashPullOutcome outcome) {
  final sent = [
    for (final l in outcome.legs)
      if (l.ok)
        // A leg that went straight to the destination is moving there.
        l.direct
            ? l10n.oneBalanceMovingTo(
                _usd(l.sentUsd), venueCashDestinationName(l10n, l.landsIn))
            : l10n.oneBalanceComingBack(
                _usd(l.sentUsd), venueCashVenueName(l10n, l.venue)),
  ];
  if (sent.isEmpty) return null;
  return '${sent.join('\n')}\n${l10n.activityBitcoinAddedPending}';
}

/// Where a move's money is going, as the app names it.
String venueCashDestinationName(
        AppLocalizations l10n, VenueCashDestination destination) =>
    switch (destination) {
      VenueCashDestination.dollars => l10n.assetDollars,
      VenueCashDestination.bitcoin => l10n.bitcoin,
      VenueCashDestination.predictions => l10n.predictions,
      VenueCashDestination.investing => l10n.trading,
    };

/// The one Activity row's title for [move]: what the person asked for.
/// "Send $50" once the send went; otherwise "Move $50 to Bitcoin" (a send
/// that never went says where its money did go: Dollars).
String multiSourceMoveTitle(AppLocalizations l10n, MultiSourceMove move) {
  final amount = _usd(move.totalUsd);
  if (move.forAction == VenueCashFor.send && move.finalOperationId != null) {
    return l10n.multiMoveSendTitle(amount);
  }
  return l10n.multiMoveTitle(
      amount, venueCashDestinationName(l10n, move.destination));
}

/// "$29.80 delivered · $20.20 remaining" for a move a leg failed for,
/// else null.
String? multiSourceMoveProgress(AppLocalizations l10n, MultiSourceMove move) =>
    move.partial
        ? l10n.multiMoveDeliveredRemaining(
            _usd(move.deliveredUsd), _usd(move.remainingUsd))
        : null;
