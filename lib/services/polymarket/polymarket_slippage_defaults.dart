// lib/services/polymarket/polymarket_slippage_defaults.dart
//
// The slippage a Predictions market order starts with. A short crypto
// round (a 5- or 15-minute Up or Down) moves several cents in the second
// or two between the quote and the post, most of all in its last minute,
// so 5% killed the fill-or-kill again and again ("The price moved to 84¢,
// past your limit of 81¢"). Those rounds start wider; the slip shows the
// resulting maximum price before approval, and a slippage the person
// picks always wins.

import 'package:kute/helpers/formatters/polymarket_side_labels.dart'
    show polymarketMarketType;

/// Every other market.
const double kPolymarketDefaultSlippagePct = 5;

/// A 5- or 15-minute crypto round.
const double kPolymarketFastRoundSlippagePct = 10;

/// The same round in its final minute.
const double kPolymarketFastRoundFinalMinuteSlippagePct = 12;

final RegExp _fastRoundSlug = RegExp(r'-updown-(5|15)m-');

/// Whether this is a short crypto round: its slug names a 5- or 15-minute
/// Up or Down window, or (no slug) an Up or Down market closing within
/// 15 minutes.
bool isPolymarketFastRound({
  String? slug,
  String? question,
  DateTime? endAt,
  DateTime? now,
}) {
  if (slug != null && _fastRoundSlug.hasMatch(slug.toLowerCase())) {
    return true;
  }
  if (question == null || endAt == null) return false;
  final left = endAt.difference(now ?? DateTime.now());
  return polymarketMarketType(question) == 'up_down' &&
      left <= const Duration(minutes: 15);
}

/// The slippage a market order on this market starts with (percent).
double polymarketDefaultSlippagePct({
  String? slug,
  String? question,
  DateTime? endAt,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  if (!isPolymarketFastRound(
      slug: slug, question: question, endAt: endAt, now: at)) {
    return kPolymarketDefaultSlippagePct;
  }
  if (endAt != null && endAt.difference(at) <= const Duration(seconds: 60)) {
    return kPolymarketFastRoundFinalMinuteSlippagePct;
  }
  return kPolymarketFastRoundSlippagePct;
}
