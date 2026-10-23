// The in-progress lines an action shows while venue cash moves for it: a
// leg going straight to the destination says it is moving there ("$X
// moving to Bitcoin"); only a leg that comes home to Dollars first says
// it is coming back.

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/venue_cash_pull_copy.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final plan = planDollarsShortfall(neededUsd: 40, dollarsUsd: 0, sources: [
    (
      venue: OneBalanceVenue.predictions,
      availableUsd: 10,
      eta: kVenuePullEta[OneBalanceVenue.predictions]!,
      minimumUsd: 1,
    ),
    (
      venue: OneBalanceVenue.investing,
      availableUsd: 100,
      eta: kVenuePullEta[OneBalanceVenue.investing]!,
      minimumUsd: 1,
    ),
  ]);

  test(
      'a direct leg is moving to the destination; a leg via Dollars is '
      'coming back', () {
    final p = plan.pullFrom(OneBalanceVenue.predictions)!.usd;
    final i = plan.pullFrom(OneBalanceVenue.investing)!.usd;
    String usd(double v) => '\$${v.toStringAsFixed(2)}';
    expect(
        venueCashProgressText(l10n, plan,
            destination: VenueCashDestination.bitcoin,
            direct: {OneBalanceVenue.investing}),
        '${l10n.oneBalanceComingBack(usd(p), l10n.predictions)}\n'
        '${l10n.oneBalanceMovingTo(usd(i), l10n.bitcoin)}');
    // A Dollars destination: every leg is coming back, whatever is passed.
    expect(
        venueCashProgressText(l10n, plan,
            direct: {OneBalanceVenue.investing, OneBalanceVenue.predictions}),
        '${l10n.oneBalanceComingBack(usd(p), l10n.predictions)}\n'
        '${l10n.oneBalanceComingBack(usd(i), l10n.trading)}');
  });

  test(
      'stopped at the first failed leg: a leg that went and a leg still on '
      'its way are coming home; the failed one is not named', () {
    final p = plan.pullFrom(OneBalanceVenue.predictions)!;
    final i = plan.pullFrom(OneBalanceVenue.investing)!;
    String usd(double v) => '\$${v.toStringAsFixed(2)}';
    final failed = VenueCashLegOutcome(
        pull: p, error: const RouteUnavailable('paused'));
    // Investing has not answered yet: it is still on its way home.
    expect(
        venueCashStoppedEarlyText(l10n, plan, [failed]),
        '${l10n.oneBalanceComingBack(usd(i.usd), l10n.trading)}\n'
        '${l10n.activityBitcoinAddedPending}');
    // Investing failed and Predictions went: only Predictions is named.
    final went = VenueCashLegOutcome(
        pull: p,
        result: VenueMoveResult(
            quoteId: 'q', sentUsd: p.usd, arrivingUsdEstimate: p.usd));
    final investingFailed = VenueCashLegOutcome(
        pull: i, error: const RouteUnavailable('paused'));
    expect(
        venueCashStoppedEarlyText(l10n, plan, [investingFailed, went]),
        '${l10n.oneBalanceComingBack(usd(p.usd), l10n.predictions)}\n'
        '${l10n.activityBitcoinAddedPending}');
    // Nothing went and nothing is going.
    expect(
        venueCashStoppedEarlyText(l10n, plan, [failed, investingFailed]),
        isNull);
  });
}
