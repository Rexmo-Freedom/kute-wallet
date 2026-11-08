// lib/services/polymarket/instant_rounds.dart
//
// Predictions › Instant (founder, 8 November 2026): the crypto rounds, as
// one live card per asset for the chosen length, never a list of windows.
// What the filter offers and which round stands for each asset. Pure: the
// screen and the tests pass the clock and the rows in.
//
// WHY ONE CARD PER ASSET. An earlier Instant tab was removed on 24 May 2026
// (private archive 2f5175c9c, whose message gives no reason). Before that it
// had been cut from four banners stacked to one at a time (#157), and once
// it was gone the five-minute markets were hidden from every list because as
// bare rows they were "visually noisy (one row per 5-min window per asset,
// refreshing constantly)". Four live assets later meant four sockets and a
// CoinGecko 429 freeze until they shared one feed (38a1839d1, August 2026).
// So a length here shows the round in play and nothing ahead of it, and only
// the cards on screen read anything.

import 'package:kute/models/polymarket_model.dart' show PolymarketEvent;
import 'package:kute/services/polymarket/crypto_round.dart';

/// What the person last picked: the asset that leads and the round length.
class PolyInstantChoice {
  const PolyInstantChoice({required this.asset, required this.length});

  /// The ticker ('BTC').
  final String asset;

  /// A Crypto chip's key ('5m', '15m', '1h', '4h').
  final String length;

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
}

/// Bitcoin's five-minute round first, until the person picks otherwise.
const PolyInstantChoice kPolyInstantDefault =
    PolyInstantChoice(asset: 'BTC', length: kPolyInstantCardLength);

/// The one length drawn as the live round cards (the one with the rolling
/// buttons, crypto_next_round.dart); the others are Crypto's window lists.
const String kPolyInstantCardLength = '5m';

/// The round lengths the filter can offer, shortest first: the Crypto chips
/// whose rows are rounds. Daily is not one: "Up or Down on October 5?" has
/// no window to show ([polyCryptoRoundOf]).
const List<String> kPolyInstantLengths = ['5m', '15m', '1h', '4h'];

/// The lengths on offer out of the Crypto row's chips [subKeys] (the site's
/// own counts decide those), Five minutes always, the rest in order.
List<String> polyInstantLengthsOffered(Iterable<String> subKeys) {
  final keys = subKeys.toSet();
  return [
    for (final l in kPolyInstantLengths)
      if (l == kPolyInstantCardLength || keys.contains(l)) l,
  ];
}

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

/// The ticker of a round's slug asset: `btc-updown-15m-…` writes the ticker,
/// the hourly `bitcoin-up-or-down-…` the name.
String polyRoundTicker(String slugAsset) =>
    switch (slugAsset.trim().toLowerCase()) {
      'bitcoin' => 'BTC',
      'ethereum' => 'ETH',
      'solana' => 'SOL',
      'dogecoin' => 'DOGE',
      'hyperliquid' => 'HYPE',
      final other => other.toUpperCase(),
    };

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

/// The one round of each asset among [events]: the round in play at [now],
/// else the soonest ahead. Rows that are not rounds ("Bitcoin above … on"
/// shares the hourly tag) and rounds that have ended are left out. In
/// [polyInstantAssetOrder] by [chosen].
List<PolymarketEvent> polyInstantRows(
  Iterable<PolymarketEvent> events, {
  required String chosen,
  required DateTime now,
}) {
  final best = <String, ({PolymarketEvent event, PolyCryptoRound round})>{};
  for (final e in events) {
    if (e.ended || e.closed) continue;
    final round = polyCryptoRoundOf(e.slug, endDate: e.endDate);
    if (round == null || !round.end.isAfter(now)) continue;
    final asset = polyRoundTicker(round.asset);
    final held = best[asset];
    if (held == null || round.start.isBefore(held.round.start)) {
      best[asset] = (event: e, round: round);
    }
  }
  return [
    for (final a in polyInstantAssetOrder(best.keys, chosen)) best[a]!.event,
  ];
}

/// The ticker of a round row, for the filter's chips; null when it is not
/// a round.
String? polyInstantAssetOf(PolymarketEvent event) {
  final round = polyCryptoRoundOf(event.slug, endDate: event.endDate);
  return round == null ? null : polyRoundTicker(round.asset);
}

/// When the first of [rows] ends: the shown rounds must be read again then.
DateTime? polyInstantNextEnd(Iterable<PolymarketEvent> rows) {
  DateTime? first;
  for (final e in rows) {
    final end = polyCryptoRoundOf(e.slug, endDate: e.endDate)?.end;
    if (end != null && (first == null || end.isBefore(first))) first = end;
  }
  return first;
}

/// How long until the next five-minute round starts (they start on every
/// five minutes of the clock), for the sheet's card: no read at all.
Duration polyNextFiveMinuteRoundIn(DateTime now) {
  const span = 300;
  final s = now.millisecondsSinceEpoch ~/ 1000;
  return Duration(seconds: span - s % span);
}
