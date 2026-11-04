// What a Hyperliquid market IS, in a sentence or two, for the top of the
// "About (market)" sheet. Hyperliquid's API carries no description, so
// the text is a bundled table of curated English descriptions keyed by
// [hlUnderlyingKey] (one text for gold whether it trades as xyz:GOLD,
// flx:GOLD or km:GOLD), and every market the table does not cover gets a
// plain sentence built from what the app already knows: its name, its
// ticker, its asset class and kind, and the venue that lists it.

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';

/// The curated descriptions, read from the bundle once per app run.
class HlMarketDescriptions {
  HlMarketDescriptions._();

  static const String assetPath = 'lib/assets/markets/hl_descriptions_en.json';

  static Future<Map<String, String>>? _loading;

  /// The table, read from [bundle] (the app bundle by default) on the
  /// first call; later calls share that read. An unreadable asset is an
  /// empty table: every market then falls back to [hlMarketDescription]'s
  /// template.
  static Future<Map<String, String>> load({AssetBundle? bundle}) =>
      _loading ??= _read(bundle ?? rootBundle);

  static Future<Map<String, String>> _read(AssetBundle bundle) async {
    try {
      // Bytes, decoded here: loadString hands big files to an isolate.
      final data = await bundle.load(assetPath);
      return parse(utf8.decode(data.buffer.asUint8List(
          data.offsetInBytes, data.lengthInBytes)));
    } catch (_) {
      return const {};
    }
  }

  /// `{ "<underlying key>": "<text>" }`; anything that is not a non-empty
  /// string is skipped.
  static Map<String, String> parse(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return const {};
    return {
      for (final e in decoded.entries)
        if (e.key is String && e.value is String &&
            (e.value as String).trim().isNotEmpty)
          e.key as String: (e.value as String).trim(),
    };
  }

  @visibleForTesting
  static void debugReset() => _loading = null;
}

/// The curated table, kept for the app run once read.
final hlMarketDescriptionsProvider =
    FutureProvider<Map<String, String>>((ref) => HlMarketDescriptions.load());

/// [m]'s curated description, or null when the table has none.
String? hlCuratedDescription(Map<String, String> table, HlMarket m) =>
    table[hlUnderlyingKey(m)];

/// What [m] is: its curated description from [table], else the template
/// sentence ([hlMarketDescriptionFallback]).
String hlMarketDescription(
        AppLocalizations l10n, HlMarket m, Map<String, String> table) =>
    hlCuratedDescription(table, m) ?? hlMarketDescriptionFallback(l10n, m);

/// "Tesla (TSLA) · a stock-linked perpetual traded on XYZ via
/// Hyperliquid." Built only from what the app has: the name the rows show
/// (else the ticker alone), the asset class and kind, and the venue
/// ([HlDexNames.venueOf]); a market on Hyperliquid's own exchange says
/// "traded on Hyperliquid."
String hlMarketDescriptionFallback(AppLocalizations l10n, HlMarket m) {
  final name = hlFriendlyName(m.coin) ?? m.unitAssetName;
  final market = name == null ||
          hlNormalizeName(name) == hlNormalizeName(m.coin)
      ? m.coin
      : l10n.hlAboutMarketLabel(name, m.coin);
  final kind = hlCategoryPhrase(l10n, m);
  final venue = HlDexNames.venueOf(m);
  return m.isHip3 && venue != 'Hyperliquid'
      ? l10n.hlAboutFallbackBuilder(market, kind, venue)
      : l10n.hlAboutFallbackMain(market, kind);
}

/// "a stock-linked perpetual", "a spot token": [m]'s asset class and kind
/// in the words the fallback sentence uses.
String hlCategoryPhrase(AppLocalizations l10n, HlMarket m) {
  if (m.isSpot) {
    return switch (m.category) {
      'stocks' => l10n.hlAboutKindStockSpot,
      'commodities' => l10n.hlAboutKindCommoditySpot,
      'indices' => l10n.hlAboutKindIndexSpot,
      _ => l10n.hlAboutKindSpot,
    };
  }
  return switch (m.category) {
    'crypto' => l10n.hlAboutKindCryptoPerp,
    'stocks' => l10n.hlAboutKindStockPerp,
    'commodities' => l10n.hlAboutKindCommodityPerp,
    'indices' => l10n.hlAboutKindIndexPerp,
    'fx' => l10n.hlAboutKindFxPerp,
    'preipo' => l10n.hlAboutKindPreIpoPerp,
    'rates' => l10n.hlAboutKindRatesPerp,
    _ => l10n.hlAboutKindPerp,
  };
}
