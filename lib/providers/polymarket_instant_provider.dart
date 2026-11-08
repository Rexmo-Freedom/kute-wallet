// lib/providers/polymarket_instant_provider.dart
//
// The filter of Predictions › Instant, asset and length only
// (instant_rounds.dart). Not remembered (founder, 8 November 2026: "do not
// remember the last one we picked"): it lives while Predictions is on
// screen and goes back to Bitcoin's five minutes when the pill is left
// (resetInvestmentsPicks, usd_account_screen.dart). And the round the person
// picked on the card's strip (instant_strip.dart), which lives only while
// that card is on screen.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/services/polymarket/instant_rounds.dart';

final polyInstantChoiceProvider =
    NotifierProvider<PolyInstantChoiceNotifier, PolyInstantChoice>(
        PolyInstantChoiceNotifier.new);

/// The start (UTC seconds) of the round the person tapped on the strip of
/// the card showing this asset at this length; null while the buttons
/// follow the roll. Per asset and length, so a new pick on the filter
/// starts clean; gone with the card (instant_strip.dart decides how long a
/// pick stands).
final polyInstantPickedRoundProvider =
    StateProvider.autoDispose.family<int?, PolyInstantChoice>((_, __) => null);

class PolyInstantChoiceNotifier extends Notifier<PolyInstantChoice> {
  @override
  PolyInstantChoice build() => kPolyInstantDefault;

  void pick(PolyInstantChoice next) => state = next;

  void reset() => state = kPolyInstantDefault;
}
