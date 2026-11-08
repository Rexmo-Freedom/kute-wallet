// lib/services/polymarket/instant_rounds.dart
//
// Predictions › Instant (founder, 8 November 2026): the crypto Up-or-Down
// rounds on their own full screen (instant_screen.dart), ONE asset and ONE
// length at a time: what the filter offers, how the coins are ordered, and
// what the person last picked. The rounds themselves, and which one the
// buttons bet on, are instant_strip.dart. Pure: the screen and the tests
// pass the clock and the rows in.
//
// WHY ONE CARD. An earlier Instant tab was removed on 24 May 2026 (private
// archive 2f5175c9c, whose message gives no reason). Before that it had been
// cut from four banners stacked to one at a time (#157), and once it was gone
// the five-minute markets were hidden from every list because as bare rows
// they were "visually noisy (one row per 5-min window per asset, refreshing
// constantly)". Four live assets later meant four sockets and a CoinGecko 429
// freeze until they shared one feed (38a1839d1, August 2026). A first Instant
// page (8 November 2026, the same day) stacked a card per asset, and the
// founder found "many buttons up and down, does not look good". So: one
// asset's card, one live chart, one pair of buttons, and the other rounds
// of that asset as a strip of small markers on the card.

import 'package:kute/models/polymarket_model.dart' show PolymarketEvent;
import 'package:kute/services/polymarket/crypto_round.dart';

export 'package:kute/services/polymarket/crypto_round.dart'
    show polyRoundTicker;

/// What the person last picked: the asset and the round length.
class PolyInstantChoice {
  const PolyInstantChoice({required this.asset, required this.length});

  /// The ticker ('BTC').
  final String asset;

  /// A Crypto chip's key ('5m', '15m', '1h', '4h').
  final String length;

  /// The round length in minutes.
  int get minutes => polyInstantMinutes(length);

  PolyInstantChoice copyWith({String? asset, String? length}) =>
      PolyInstantChoice(
          asset: asset ?? this.asset, length: length ?? this.length);

  @override
  bool operator ==(Object other) =>
      other is PolyInstantChoice &&
      other.asset == asset &&
      other.length == length;

  @override
  int get hashCode => Object.hash(asset, length);

  @override
  String toString() => 'PolyInstantChoice($asset, $length)';
}

/// Bitcoin's five-minute round first, until the person picks otherwise.
const PolyInstantChoice kPolyInstantDefault =
    PolyInstantChoice(asset: 'BTC', length: '5m');

/// The round lengths the filter can offer, shortest first: the Crypto chips
/// whose rows are rounds. Daily is not one: "Up or Down on October 5?" has
/// no window to show ([polyCryptoRoundOf]).
const List<String> kPolyInstantLengths = ['5m', '15m', '1h', '4h'];

/// A length's minutes: 5, 15, 60 or 240.
int polyInstantMinutes(String length) => switch (length) {
      '15m' => 15,
      '1h' => 60,
      '4h' => 240,
      _ => 5,
    };

/// The lengths on offer out of the Crypto row's chips [subKeys] (the site's
/// own counts decide those), Five minutes always, the rest in order.
List<String> polyInstantLengthsOffered(Iterable<String> subKeys) {
  final keys = subKeys.toSet();
  return [
    for (final l in kPolyInstantLengths)
      if (l == '5m' || keys.contains(l)) l,
  ];
}

/// The deep-link key of the Instant screen (`predictions/instant`). It is
/// a screen of its own, not a Predictions category, so the browse
/// selection's parser does not know it.
const String kPolyInstantRouteKey = 'predictions/instant';

/// Whether [key] names the Instant screen.
bool polyIsInstantRouteKey(String key) =>
    key.split('/').where((p) => p.isNotEmpty).join('/') ==
    kPolyInstantRouteKey;

/// How polymarket.com orders the coins, for a stable filter.
const List<String> _kOrder = [
  'BTC',
  'ETH',
  'SOL',
  'XRP',
  'DOGE',
  'BNB',
  'HYPE',
];

/// [assets] with [chosen] first and the others in the coins' usual order
/// (an asset the order does not know last, by name). [chosen] leads only
/// when it is among them.
List<String> polyInstantAssetOrder(Iterable<String> assets, String chosen) {
  int rank(String a) {
    final i = _kOrder.indexOf(a);
    return i < 0 ? _kOrder.length : i;
  }

  return assets.toSet().toList()
    ..sort((a, b) {
      if (a == chosen) return b == chosen ? 0 : -1;
      if (b == chosen) return 1;
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
}

/// The ticker of a round row, for the filter's chips; null when it is not
/// a round.
String? polyInstantAssetOf(PolymarketEvent event) {
  final round = polyCryptoRoundOf(event.slug, endDate: event.endDate);
  return round == null ? null : polyRoundTicker(round.asset);
}

/// The assets the filter offers at a length: the ones among the Crypto
/// list's [rows] (the venue's own list of that length's rounds), in the
/// coins' order, [chosen] kept among them whatever the list says; every
/// known [fallback] asset while the list has not come in (empty [rows]).
List<String> polyInstantAssetsOffered(
  Iterable<PolymarketEvent> rows, {
  required String chosen,
  required Iterable<String> fallback,
}) {
  final found = <String>{
    for (final e in rows)
      if (polyInstantAssetOf(e) case final a?) a,
  };
  if (found.isEmpty) return polyInstantAssetOrder(fallback, '');
  return polyInstantAssetOrder([...found, chosen], '');
}
