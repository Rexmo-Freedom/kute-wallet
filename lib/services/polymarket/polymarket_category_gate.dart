import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/venue_analytics.dart';

/// The two prediction categories the runtime policy can withdraw per
/// jurisdiction on top of `polymarket.trade`: sports (every league
/// included) and politics or elections. The category comes from the same
/// tag classifier analytics uses, so what the operator sees under
/// `market_category` is exactly what the gate acts on.
///
/// Where a gate denies, the app refuses NEW bets on the category's markets
/// and hides nothing (founder decision, 12 November 2026: "we should not
/// hide, we can show, just not allow to purchase. Showing the price is
/// ok."). The category, its pills and its markets stay in browse, search,
/// Sal and shared links with their prices; the bet slip opens shut under
/// the policy's own reason (`_resolveOpenGate` in bet_slip_sheet.dart,
/// [CapabilityBlockNote]) before Face ID and before any money moves, and
/// every placement re-checks [polymarketBetCapabilities]. Positions already
/// held stay visible and sell or claim under `polymarket.close` as before.
/// Both gates fail closed: a policy the app cannot read refuses the bets
/// while the markets still show.
const kPolymarketSportsCapability = 'polymarket.sports';
const kPolymarketPoliticsCapability = 'polymarket.politics';

/// The gate capability a market with this coarse [category] and these
/// Gamma [tags] answers to, or null when it belongs to neither category.
String? polymarketCategoryCapability(String? category, List<String> tags) {
  switch (VenueAnalytics.marketCategory(category, tags)) {
    case 'sports':
      return kPolymarketSportsCapability;
    case 'politics':
      return kPolymarketPoliticsCapability;
  }
  return null;
}

/// The capabilities a NEW bet on a market of this category needs: opening
/// predictions, plus the category gate when one applies. Hot and Ledger
/// bet paths both check exactly this list.
List<String> polymarketBetCapabilities(String? category, List<String> tags) => [
      'polymarket.trade',
      if (polymarketCategoryCapability(category, tags) case final gate?) gate,
    ];

/// [polymarketBetCapabilities] for a market known only by its public ids
/// (token, condition, slug): the category analytics remembered for it,
/// else the caller's coarse [fallbackCategory]. A market never seen
/// classifies by the coarse category alone.
List<String> polymarketBetCapabilitiesFor(Iterable<String?> ids,
    {String? fallbackCategory}) {
  final category = VenueAnalytics.pmKindParams(ids,
      fallbackCategory: fallbackCategory)['market_category'] as String?;
  return polymarketBetCapabilities(category, const []);
}

/// Whether the category gate lets a NEW bet on a market of this category
/// be composed under the policy. Never a browse filter (see the header).
bool polymarketCategoryBettable(
    String? category, List<String> tags, RuntimeCapabilitiesService policy) {
  final gate = polymarketCategoryCapability(category, tags);
  return gate == null || policy.allows(gate);
}

/// [polymarketCategoryBettable] for [event].
bool polymarketEventBettable(
        PolymarketEvent event, RuntimeCapabilitiesService policy) =>
    polymarketCategoryBettable(event.category, event.tags, policy);

/// [events] a bet may be composed on under the policy: for the Portfolio
/// Builder's pick list only, whose picks are bets. Browse, search and Sal
/// list every event.
List<PolymarketEvent> polymarketEventsBettable(
    List<PolymarketEvent> events, RuntimeCapabilitiesService policy) {
  if (policy.allows(kPolymarketSportsCapability) &&
      policy.allows(kPolymarketPoliticsCapability)) {
    return events;
  }
  return [
    for (final e in events)
      if (polymarketEventBettable(e, policy)) e
  ];
}

/// [polymarketCategoryBettable] for a tag [slug] alone.
bool polymarketTagBettable(String slug, RuntimeCapabilitiesService policy) =>
    polymarketCategoryBettable(null, [slug], policy);
