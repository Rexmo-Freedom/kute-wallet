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
}
