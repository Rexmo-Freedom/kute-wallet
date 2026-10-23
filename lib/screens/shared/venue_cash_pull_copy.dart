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

/// One line per leg of [plan], fastest first: "$X moving to Bitcoin" for
/// a leg going straight to [destination] (its venue is in [direct]),
/// "$X coming back from Investing" for one that comes home to Dollars.
String venueCashProgressText(AppLocalizations l10n, VenueCashPlan plan,
        {VenueCashDestination destination = VenueCashDestination.dollars,
        Set<OneBalanceVenue> direct = const {}}) =>
    [
      for (final p in plan.pulls)
        destination != VenueCashDestination.dollars &&
                direct.contains(p.venue)
            ? l10n.oneBalanceMovingTo(
                _usd(p.usd), venueCashDestinationName(l10n, destination))
            : l10n.oneBalanceComingBack(
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

/// [venueCashStoppedText] for an action that stopped at its first failed
/// leg while other legs of [plan] were still on their way: [reported] are
/// the legs that have answered so far. Each that went, and each still
/// going, is named as coming home (a leg is only started to come home);
/// a failed one stays on its venue and is not named. Null when nothing
/// went and nothing is still going.
String? venueCashStoppedEarlyText(AppLocalizations l10n, VenueCashPlan plan,
    List<VenueCashLegOutcome> reported) {
  final answered = {for (final l in reported) l.venue};
  final going = [
    for (final l in reported)
      if (l.ok)
        l.direct
            ? l10n.oneBalanceMovingTo(
                _usd(l.sentUsd), venueCashDestinationName(l10n, l.landsIn))
            : l10n.oneBalanceComingBack(
                _usd(l.sentUsd), venueCashVenueName(l10n, l.venue)),
    for (final p in plan.pulls)
      if (!answered.contains(p.venue))
        l10n.oneBalanceComingBack(
            _usd(p.usd), venueCashVenueName(l10n, p.venue)),
  ];
  if (going.isEmpty) return null;
  return '${going.join('\n')}\n${l10n.activityBitcoinAddedPending}';
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
