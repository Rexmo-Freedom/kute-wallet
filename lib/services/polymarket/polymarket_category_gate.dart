import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/venue_analytics.dart';

/// The two prediction categories the runtime policy can withdraw per
/// jurisdiction on top of `polymarket.trade`: sports (every league
/// included) and politics or elections. The category comes from the same
/// tag classifier analytics uses, so what the operator sees under
/// `market_category` is exactly what the gate acts on.
///
/// Where a gate denies, the app hides the category and its markets from
/// browse, search and Sal and refuses NEW bets on them. Positions already
/// held are looked up by their own providers, stay visible, and sell or
/// claim under `polymarket.close` as before. Both gates fail closed: a
/// policy the app cannot read hides the categories.
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

/// Whether a market of this category may be offered under the policy.
bool polymarketCategoryOffered(
    String? category, List<String> tags, RuntimeCapabilitiesService policy) {
  final gate = polymarketCategoryCapability(category, tags);
  return gate == null || policy.allows(gate);
}

/// Whether [event] may be offered under the policy.
bool polymarketEventOffered(
        PolymarketEvent event, RuntimeCapabilitiesService policy) =>
    polymarketCategoryOffered(event.category, event.tags, policy);

/// [events] minus the ones the policy hides.
List<PolymarketEvent> polymarketEventsOffered(
    List<PolymarketEvent> events, RuntimeCapabilitiesService policy) {
  if (policy.allows(kPolymarketSportsCapability) &&
      policy.allows(kPolymarketPoliticsCapability)) {
    return events;
  }
  return [
    for (final e in events)
      if (polymarketEventOffered(e, policy)) e
  ];
}

/// Whether a browse pill for the tag [slug] may be shown: a pill whose
/// tag alone classifies as a hidden category disappears with its markets.
bool polymarketTagOffered(String slug, RuntimeCapabilitiesService policy) =>
    polymarketCategoryOffered(null, [slug], policy);
