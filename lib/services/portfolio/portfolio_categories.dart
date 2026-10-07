// lib/services/portfolio/portfolio_categories.dart
//
// What the Statistics tab's category donut is made of: the kinds of
// markets an account has put its money on, all time.
//
//   * Predictions: every prediction's stake (every share bought at its
//     average price, the "Amount predicted" tile's figure) summed per
//     category. A prediction's category is the first of the Predictions
//     tab's topic pills its market is tagged with ([polyCategoryForTags]),
//     read from Gamma's market list by condition id (tags included), open
//     and closed markets alike. A market Gamma does not answer for, or one
//     tagged with no pill's topic, is "other".
//   * Investing: every fill's notional (price x size, the "Volume traded"
//     tile's figure) summed per category ([hlFillCategory]): the main
//     dex's perps are crypto, a builder dex's perps carry the venue's
//     class (stocks, indices, commodities, fx, pre-IPO), spot tokens are
//     spot unless they track a stock, an index or a commodity.
//
// Both are all time (the Historic sub-tab). The Active sub-tab splits
// what is open now the same way: a live prediction's shares at the live
// price ([predictionOpenCategoryValues]); an open perp's or a spot
// holding's value as the Open tab's card shows it, filed by
// [hlFillCategory].
//
// The all-time splits are all time, whatever range the tab draws. A history cut at its
// read cap has no all-time split: the providers answer null and the donut
// is not drawn, as the tiles write a dash.
//
// A market's category never changes, so a resolved one is kept for the
// session ([_polyCategoryCache]); opening the tab again reads only markets
// not seen yet.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:kute/helpers/hyperliquid_activity.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show HlSpotClass, classifyHlSpotMarket, kHlTradfiCategories;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolyPill, PolyPillX;
import 'package:kute/providers/portfolio_performance_provider.dart';

/// The category of anything the donut cannot place.
const String kPortfolioOtherCategory = 'other';

/// The Predictions tab's topic pills a market is filed under, most
/// specific first: a market tagged both Politics and Geopolitics is
/// Geopolitics, an Esports game (also tagged Sports) is Esports.
const List<PolyPill> kPolyCategoryOrder = [
  PolyPill.esports,
  PolyPill.sports,
  PolyPill.crypto,
  PolyPill.weather,
  PolyPill.mentions,
  PolyPill.finance,
  PolyPill.economy,
  PolyPill.geopolitics,
  PolyPill.elections,
  PolyPill.tech,
  PolyPill.culture,
  PolyPill.politics,
];

/// The pill key ([PolyPillX.key]) for a market tagged [tagSlugs], or
/// [kPortfolioOtherCategory] when none of the topic pills' tags is there.
String polyCategoryForTags(Iterable<String> tagSlugs) {
  final tags = {for (final t in tagSlugs) t.toLowerCase()};
  if (tags.contains('cryptocurrency')) tags.add('crypto');
  for (final pill in kPolyCategoryOrder) {
    if (pill.tagSlugs.any(tags.contains)) return pill.key;
  }
  return kPortfolioOtherCategory;
}

/// Reads the tag slugs of the markets [conditionIds] (lower case) name.
/// A market Gamma does not return is missing from the map. Throws when a
/// read fails.
typedef PolyMarketTagsFetch = Future<Map<String, Set<String>>> Function(
    List<String> conditionIds);

/// Gamma's keyset market list, tags included, in batches, once for the
/// live markets and once for the closed ones (the list leaves closed
/// markets out unless asked).
Future<Map<String, Set<String>>> fetchPolyMarketTags(
    List<String> conditionIds) async {
  final client = http.Client();
  try {
    final result = <String, Set<String>>{};
    const batchSize = 50;
    for (var offset = 0; offset < conditionIds.length; offset += batchSize) {
      final batch = conditionIds.skip(offset).take(batchSize).toList();
      for (final closed in const [false, true]) {
        final uri = Uri.https('gamma-api.polymarket.com', '/markets/keyset', {
          'condition_ids': batch,
          'limit': '${batch.length}',
          'include_tag': 'true',
          if (closed) 'closed': 'true',
        });
        final response =
            await client.get(uri).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          throw http.ClientException('Market categories could not load');
        }
        final decoded = jsonDecode(response.body);
        final rows = decoded is Map ? decoded['markets'] : null;
        if (rows is! List) throw const FormatException('Expected markets');
        for (final row in rows.whereType<Map>()) {
          final id = '${row['conditionId'] ?? ''}'.toLowerCase();
          if (id.isEmpty) continue;
          final tags = row['tags'];
          result[id] = {
            if (tags is List)
              for (final t in tags.whereType<Map>())
                if ('${t['slug'] ?? ''}'.isNotEmpty)
                  '${t['slug']}'.toLowerCase(),
          };
        }
      }
    }
    return result;
  } finally {
    client.close();
  }
}

final polyMarketTagsFetchProvider =
    Provider<PolyMarketTagsFetch>((ref) => fetchPolyMarketTags);

/// Markets already placed this session: condition id → category key.
final Map<String, String> _polyCategoryCache = {};

/// Forgets the session's placed markets (tests).
void debugClearPolyCategoryCache() => _polyCategoryCache.clear();

/// The category of each of [conditionIds], reading only the markets not
/// placed yet. A market Gamma did not return is "other" and asked again
/// next time.
Future<Map<String, String>> resolvePolyCategories(
    Iterable<String> conditionIds, PolyMarketTagsFetch fetch) async {
  final ids = {
    for (final id in conditionIds)
      if (id.isNotEmpty) id.toLowerCase()
  };
  final missing =
      ids.where((id) => !_polyCategoryCache.containsKey(id)).toList()..sort();
  if (missing.isNotEmpty) {
    final tags = await fetch(missing);
    for (final e in tags.entries) {
      _polyCategoryCache[e.key.toLowerCase()] = polyCategoryForTags(e.value);
    }
  }
  return {
    for (final id in ids) id: _polyCategoryCache[id] ?? kPortfolioOtherCategory,
  };
}

/// What was put on predictions per category, all time: each record's
/// stake under its market's category ([categories], by condition id; a
/// market not in it is "other"). Nothing worth zero or less is kept.
Map<String, double> predictionCategoryStakes(
    PredictionsBook book, Map<String, String> categories) {
  final out = <String, double>{};
  for (final r in book.records) {
    final stake = r.stakeUsd;
    if (!stake.isFinite || stake <= 0) continue;
    final key =
        categories[r.conditionId.toLowerCase()] ?? kPortfolioOtherCategory;
    out[key] = (out[key] ?? 0) + stake;
  }
  return out;
}

/// The category of every prediction's market for [request]'s Predictions
/// account (condition id → category key), all time; null when its
/// history was cut (no all-time split to draw) or it has no predictions
/// book. Throws when the categories cannot be read. The Historic donut
/// and its drill-down read the same answer.
final predictionCategoriesProvider = FutureProvider.autoDispose
    .family<Map<String, String>?, PortfolioPerformanceRequest>(
        (ref, request) async {
  final data = await ref.watch(portfolioPerformanceProvider(request).future);
  final book = data.predictions;
  if (book == null || !book.complete) return null;
  return resolvePolyCategories(book.records.map((r) => r.conditionId),
      ref.read(polyMarketTagsFetchProvider));
});

/// The all-time stake per category for [request]'s Predictions account;
/// null when its history was cut (no all-time split to draw) or it has
/// no predictions book. Throws when the categories cannot be read.
final predictionCategoryStakesProvider = FutureProvider.autoDispose
    .family<Map<String, double>?, PortfolioPerformanceRequest>(
        (ref, request) async {
  final categories =
      await ref.watch(predictionCategoriesProvider(request).future);
  if (categories == null) return null;
  final data = await ref.watch(portfolioPerformanceProvider(request).future);
  final book = data.predictions;
  if (book == null) return null;
  return predictionCategoryStakes(book, categories);
});

/// A Predictions account's positions still in play: held and not yet
/// decided. A resolved one waiting to be claimed is settled (the Open P&L
/// leaves it out and the realised figure counts it).
List<PredictionRecord> livePredictionRecords(PredictionsBook book) => [
      for (final r in book.records)
        if (r.open && !r.redeemable) r
    ];

/// What a live position is worth now: its shares at [livePrices]' price
/// for its token, its last Data API price where there is none.
double predictionLiveValueUsd(
    PredictionRecord r, Map<String, double> livePrices) {
  final live = livePrices[r.tokenId];
  final price = live != null && live.isFinite ? live : r.currentPrice;
  return price * r.size;
}

/// What the live predictions [records] are worth now per category
/// ([categories], by condition id; a market not in it is "other").
/// Nothing worth zero or less is kept.
Map<String, double> predictionOpenCategoryValues(
    Iterable<PredictionRecord> records,
    Map<String, String> categories,
    Map<String, double> livePrices) {
  final out = <String, double>{};
  for (final r in records) {
    final value = predictionLiveValueUsd(r, livePrices);
    if (!value.isFinite || value <= 0) continue;
    final key =
        categories[r.conditionId.toLowerCase()] ?? kPortfolioOtherCategory;
    out[key] = (out[key] ?? 0) + value;
  }
  return out;
}

/// The category of each live prediction's market for [request]'s
/// Predictions account (condition id → category key); null when it has
/// no predictions book. A history cut at its read cap still has every
/// open position. Throws when the categories cannot be read.
final predictionOpenCategoriesProvider = FutureProvider.autoDispose
    .family<Map<String, String>?, PortfolioPerformanceRequest>(
        (ref, request) async {
  final data = await ref.watch(portfolioPerformanceProvider(request).future);
  final book = data.predictions;
  if (book == null) return null;
  final live = livePredictionRecords(book);
  if (live.isEmpty) return const {};
  return resolvePolyCategories(
      live.map((r) => r.conditionId), ref.read(polyMarketTagsFetchProvider));
});

/// The category key of a fill on [coin] (the wire coin), from its market
/// when known: 'crypto', 'stocks', 'indices', 'commodities', 'fx',
/// 'preipo', 'spot' or [kPortfolioOtherCategory].
String hlFillCategory(String coin, HlMarket? market) {
  if (market == null) {
    if (coin.startsWith('@') || coin.contains('/')) return 'spot';
    // A builder dex's coin whose market is not known: no class to file it.
    if (coin.contains(':')) return kPortfolioOtherCategory;
    return 'crypto';
  }
  if (market.isSpot) {
    return switch (classifyHlSpotMarket(market)) {
      HlSpotClass.stock => 'stocks',
      HlSpotClass.indices => 'indices',
      HlSpotClass.commodity => 'commodities',
      HlSpotClass.otherSpot => 'spot',
    };
  }
  if (kHlTradfiCategories.contains(market.category)) return market.category;
  if (!market.isHip3 || market.category == 'crypto') return 'crypto';
  return kPortfolioOtherCategory;
}

/// The notional traded per category, all time; null when the fills were
/// cut at the read cap. [marketsByWire] places each fill's coin.
Map<String, double>? tradingCategoryVolumes(
    TradingBook book, Map<String, HlMarket> marketsByWire) {
  if (!book.complete) return null;
  final out = <String, double>{};
  for (final f in book.fills) {
    final notional = f.px * f.sz;
    if (!notional.isFinite || notional <= 0) continue;
    final key = hlFillCategory(f.coin, marketsByWire[f.coin]);
    out[key] = (out[key] ?? 0) + notional;
  }
  return out;
}

/// What an Investing account has open now per category: each holding's
/// value (the wire coin, its market when known, and what the Open tab's
/// card shows it worth) under [hlFillCategory]. Nothing worth zero or
/// less is kept.
Map<String, double> tradingOpenCategoryValues(
    Iterable<(String coin, HlMarket? market, double value)> holdings) {
  final out = <String, double>{};
  for (final (coin, market, value) in holdings) {
    if (!value.isFinite || value <= 0) continue;
    final key = hlFillCategory(coin, market);
    out[key] = (out[key] ?? 0) + value;
  }
  return out;
}
