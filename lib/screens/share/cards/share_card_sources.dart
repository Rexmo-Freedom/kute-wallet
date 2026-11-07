// lib/screens/share/cards/share_card_sources.dart
//
// WHERE A SHARE CARD'S FIGURES COME FROM: the providers the market pages
// already read, watched while the preview is up so the card follows the
// live price, never a figure of its own. What a provider has not loaded
// is null on the card (left out), never estimated.
//
//   * A prediction ([predictionCardFor]): the event by its slug
//     (polymarketEventDetailsProvider): its title, picture, topic (its
//     category and tags), the outcome's chance now, whether it is the
//     favourite and the strongest other outcome (not a draw), and the
//     outcome's chance over the last week (polymarketMarketHistoryProvider,
//     `1w`). Before the event lands, what the page handed over (the title,
//     the picture, the chance). A market of named outcomes shared without
//     a pick also reads the market page's chart ([shareCardMarketLines]):
//     the lines the page draws (its top outcomes, a game's teams), their
//     colours, and their real histories over the range the page opens on
//     (polyChartAutoRange, the same history provider and cache); left out
//     (the speedometer) until two of them have landed, never a made-up
//     line.
//   * An Investing market ([investmentCardFor]): the market by its coin
//     (hyperliquidAccountMarketProvider), the live mid, today's change
//     against the previous day's price, and the last 30 daily closes
//     (hyperliquidSparklineProvider, the browse cards' cache) ending on the
//     live price.

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/hyperliquid_market.dart' show HlMarket;
import 'package:kute/models/polymarket_model.dart'
    show PolymarketEvent, PolymarketOutcome, PolymarketPricePoint;
import 'package:kute/models/share_link_model.dart' show ShareLinkKind;
import 'package:kute/providers/hyperliquid_live_prices_provider.dart'
    show hyperliquidLiveMidProvider;
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidAccountMarketProvider;
import 'package:kute/providers/hyperliquid_sparkline_provider.dart'
    show hyperliquidSparklineProvider;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventDetailsProvider, polymarketMarketHistoryProvider;
import 'package:kute/providers/polymarket_game_lines_provider.dart'
    show PolyGameLines;
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show hlFriendlyName;
import 'package:kute/screens/polymarket/components/game_header.dart'
    show polySportsTeams;
import 'package:kute/screens/polymarket/components/game_winner_lines.dart'
    show polyGameWinnerLines;
import 'package:kute/screens/polymarket/components/outcome_leading.dart'
    show kPolyOutcomeColors, polyChartedOutcomes;
import 'package:kute/screens/polymarket/components/poly_chart_history.dart'
    show polyChartAutoRange, polyChartOpenedAt;
import 'package:kute/screens/share/cards/share_card_market_chart.dart'
    show kShareCardChartMaxLines, kShareCardChartThirdLine;
import 'package:kute/screens/share/cards/share_card_copy.dart'
    show shareCardUsdCents, shareCardUsdCentsFull;
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart'
    show hlSparklineWithLivePrice;
import 'package:kute/services/polymarket/event_trading_over.dart'
    show polyTradingOver;
import 'package:kute/services/polymarket/thin_history.dart'
    show polyTokenIsThin, smoothThinHistory;

/// A provider read: `ref.watch` of a WidgetRef in a build.
typedef ShareCardWatch = T Function<T>(ProviderListenable<T> provider);

/// The most points a card's line draws.
const int kShareCardSeriesPoints = 30;

/// The most points each of a market chart's lines keeps.
const int kShareCardMarketPoints = 120;

/// Tags that make a prediction an economics one.
const Set<String> _kEconomyTags = {
  'economy',
  'economics',
  'fed',
  'fed-rates',
  'interest-rates',
  'inflation',
  'finance',
  'business',
  'recession',
  'gdp',
  'jobs-report',
};

/// [event]'s topic for the headline's template.
ShareCardTopic shareCardTopicOf(PolymarketEvent event) {
  final cat = event.category.toLowerCase();
  final tags = {for (final t in event.tags) t.toLowerCase()};
  if (cat == 'crypto') return ShareCardTopic.crypto;
  if (cat == 'sports' || event.isSportsCategory || tags.contains('esports')) {
    return ShareCardTopic.sports;
  }
  if (cat == 'politics' || tags.contains('elections')) {
    return ShareCardTopic.politics;
  }
  if (tags.any(_kEconomyTags.contains)) return ShareCardTopic.economy;
  return ShareCardTopic.other;
}

/// [points] thinned evenly to at most [max], the last point kept.
List<double> shareCardThin(List<double> points,
    {int max = kShareCardSeriesPoints}) {
  if (points.length <= max) return points;
  final step = (points.length - 1) / (max - 1);
  return [for (var i = 0; i < max; i++) points[(i * step).round()]];
}

bool _isDraw(String name) =>
    const {'draw', 'tie', 'empate'}.contains(name.trim().toLowerCase());

/// The market page's chart of [e] as a card's lines (see the file
/// header): the lines its chart draws, most likely first (two, a third at
/// [kShareCardChartThirdLine] or more), each its real history over the
/// range the page opens on, the newest point pinned to the price now as
/// the page pins it. Null until two lines have their history, or for a
/// market the page draws no such chart for (a yes/no market).
List<ShareCardOutcomeLine>? shareCardMarketLines(
    ShareCardWatch watch, PolymarketEvent e,
    {DateTime? now}) {
  if (e.isBinary || e.outcomes.length < 2) return null;
  final game = !e.isSyntheticBinary &&
      (e.gameId != null || e.metadataGameId != null) &&
      polySportsTeams(e, const []) != null;
  // The page's lines: a game's teams (and a three-way match's draw, its
  // label '' here) from its winner market, else the most likely outcomes.
  final List<({String token, String name, Color color, double price})>
      specs;
  if (game) {
    specs = [
      for (final l in polyGameWinnerLines(
        event: e,
        sportsTeams: polySportsTeams(e, const []),
        lines: PolyGameLines.fromEvent(e),
        drawLabel: '',
      ))
        (token: l.tokenId, name: l.label, color: l.color, price: l.price),
    ];
  } else {
    specs = [
      for (final c in polyChartedOutcomes(e.outcomes, kPolyOutcomeColors,
          max: kShareCardChartMaxLines))
        (
          token: c.outcome.tokenId!,
          name: c.outcome.name.trim(),
          color: c.color,
          price: c.outcome.price,
        ),
    ];
  }
  // The range the page's chart opens on (MarketDetailSheet's prefetch).
  final interval = polyChartAutoRange(
    now: now ?? DateTime.now(),
    gameStart: game && e.isInPlay ? (e.gameStart ?? e.kickoff) : null,
    inPlay: e.isInPlay,
    openedAt: polyChartOpenedAt(e),
    shortMarket: RegExp(r'-(5|15)m-').hasMatch(e.slug),
    resolved: polyTradingOver(e, inPlay: e.isInPlay),
  );
  final ranked = [...specs]..sort((a, b) => b.price.compareTo(a.price));
  final out = <ShareCardOutcomeLine>[];
  for (final spec in ranked) {
    if (out.length >= kShareCardChartMaxLines) break;
    final chance = spec.price.clamp(0.0, 1.0) * 100;
    if (out.length >= 2 && chance < kShareCardChartThirdLine) break;
    List<PolymarketPricePoint>? points;
    try {
      points = watch(polymarketMarketHistoryProvider(
              (tokenId: spec.token, interval: interval)))
          .valueOrNull;
    } catch (_) {
      points = null;
    }
    // The two leading lines or none (the card's figure is the leader's);
    // a third without its history is left out.
    if (points == null || points.length < 2) {
      if (out.length < 2) return null;
      break;
    }
    // A thin market's needles and combs out, as the page draws it (never
    // a game's, where a jump is a goal).
    final drawn = !game && polyTokenIsThin(e, spec.token)
        ? smoothThinHistory(points)
        : points;
    final thinned = drawn.length <= kShareCardMarketPoints
        ? drawn
        : [
            for (var i = 0; i < kShareCardMarketPoints; i++)
              drawn[(i * (drawn.length - 1) / (kShareCardMarketPoints - 1))
                  .round()]
          ];
    out.add(ShareCardOutcomeLine(
      name: spec.name,
      draw: game && spec.name.isEmpty,
      chance: chance,
      color: spec.color,
      points: [
        for (var i = 0; i < thinned.length; i++)
          (
            t: thinned[i].timestamp.millisecondsSinceEpoch,
            // The newest point at the price now, as the page pins it.
            p: i == thinned.length - 1
                ? spec.price.clamp(0.0, 1.0)
                : thinned[i].price.clamp(0.0, 1.0),
          ),
      ],
    ));
  }
  return out.length >= 2 ? out : null;
}

/// A prediction market's card (see the file header). [outcome] is the pick
/// sent (null: the market shared, its leading outcome); [chance] (0–100)
/// and [imageUrl] are what the page had, used until the event lands.
PredictionCardData predictionCardFor(
  ShareCardWatch watch, {
  required String? slug,
  required String title,
  String? outcome,
  double? chance,
  String? imageUrl,
  bool picked = false,
  bool challenge = false,
  String? amount,
  String? recipient,
  String? referralCode,
  ShareCardAudience audience = ShareCardAudience.sender,
}) {
  final dare = picked && challenge;
  final s = slug?.trim() ?? '';
  PolymarketEvent? event;
  if (s.isNotEmpty) {
    try {
      event = watch(polymarketEventDetailsProvider(s)).valueOrNull;
    } catch (_) {
      event = null;
    }
  }
  if (event == null || event.outcomes.isEmpty) {
    final label = outcome?.trim() ?? '';
    final binary =
        label.isEmpty || const {'yes', 'no'}.contains(label.toLowerCase());
    return PredictionCardData(
      question: title,
      outcome: label.isEmpty ? 'Yes' : label,
      chance: chance,
      binary: binary,
      imageUrl: imageUrl,
      picked: picked,
      challenge: dare,
      amount: amount,
      recipient: recipient,
      referralCode: referralCode,
      audience: audience,
    );
  }
  final e = event;
  final binary = e.isBinary;
  final outcomes = e.outcomes;
  // The outcome the card is about and its chance now.
  String label;
  double? pct;
  String? tokenId;
  var leading = true;
  String? opponent;
  double? opponentChance;
  String? outcomeImage;
  String? opponentImage;
  if (binary) {
    final yes = e.yesPrice.clamp(0.0, 1.0);
    final want = outcome?.trim().toLowerCase();
    final isNo = want == 'no' || (want == null && yes < 0.5);
    label = isNo ? 'No' : 'Yes';
    pct = (isNo ? 1 - yes : yes) * 100;
    tokenId = isNo ? e.noTokenId : e.yesTokenId;
    leading = pct >= 50;
  } else {
    var best = 0;
    for (var i = 1; i < outcomes.length; i++) {
      if (outcomes[i].price > outcomes[best].price) best = i;
    }
    final want = outcome?.trim().toLowerCase();
    var index = want == null
        ? best
        : outcomes.indexWhere((o) => o.name.trim().toLowerCase() == want);
    if (index < 0) index = best;
    final o = outcomes[index];
    label = o.name.trim();
    pct = o.price.clamp(0.0, 1.0) * 100;
    tokenId = o.tokenId;
    leading = index == best;
    // The strongest other side, not a draw: "vs T1".
    int? other;
    for (var i = 0; i < outcomes.length; i++) {
      if (i == index || _isDraw(outcomes[i].name)) continue;
      if (other == null || outcomes[i].price > outcomes[other].price) {
        other = i;
      }
    }
    if (other != null) {
      final rival = outcomes[other];
      opponent = rival.name.trim();
      opponentChance = rival.price.clamp(0.0, 1.0) * 100;
    }
    // Each side's own picture: its team crest, else its outcome image.
    String? pictureOf(PolymarketOutcome x) {
      final crest = PolymarketEvent.logoFromTeams(e.teams, x.name);
      if (crest != null && crest.isNotEmpty) return crest;
      final img = x.imageUrl;
      return img != null && img.isNotEmpty ? img : null;
    }

    outcomeImage = pictureOf(o);
    if (other != null) opponentImage = pictureOf(outcomes[other]);
  }
  List<double>? series;
  final t = tokenId;
  if (t != null && t.isNotEmpty) {
    try {
      final points =
          watch(polymarketMarketHistoryProvider((tokenId: t, interval: '1w')))
          .valueOrNull;
      if (points != null && points.length >= 2) {
        series = shareCardThin([for (final p in points) p.price]);
      }
    } catch (_) {
      series = null;
    }
  }
  final image = e.displayIconUrl;
  final lines = picked ? null : shareCardMarketLines(watch, e);
  return PredictionCardData(
    question: e.title.isEmpty ? title : e.title,
    outcome: label,
    chance: pct,
    binary: binary,
    topic: shareCardTopicOf(e),
    leading: leading,
    opponent: binary ? null : opponent,
    opponentChance: binary ? null : opponentChance,
    outcomeImageUrl: outcomeImage,
    opponentImageUrl: opponentImage,
    imageUrl: (image?.isNotEmpty ?? false) ? image : imageUrl,
    picked: picked,
    challenge: dare,
    amount: amount,
    series: series,
    lines: lines,
    recipient: recipient,
    referralCode: referralCode,
    audience: audience,
  );
}

/// An Investing market's card (see the file header). [coin] is the
/// market's coin (the link's slug); [title], [ticker], [wireCoin],
/// [iconUrl] and [category] are what the page had, used until the market
/// lands. [side] is the pick sent (`long` | `short`); null: shared.
InvestmentCardData investmentCardFor(
  ShareCardWatch watch, {
  required String coin,
  String? title,
  String? ticker,
  String? wireCoin,
  String? iconUrl,
  String? category,
  String? side,
  String? amount,
  String? recipient,
  String? referralCode,
  ShareCardAudience audience = ShareCardAudience.sender,
}) {
  HlMarket? market;
  try {
    market = watch(hyperliquidAccountMarketProvider(wireCoin ?? coin)) ??
        (wireCoin != null
            ? watch(hyperliquidAccountMarketProvider(coin))
            : null);
  } catch (_) {
    market = null;
  }
  final m = market;
  final displayCoin = m?.coin ?? coin;
  final name = title?.trim().isNotEmpty == true
      ? title!.trim()
      : hlFriendlyName(displayCoin) ?? m?.unitAssetName ?? displayCoin;
  if (m == null) {
    return InvestmentCardData(
      title: name,
      ticker: ticker ?? coin,
      coin: coin,
      wireCoin: wireCoin,
      iconUrl: iconUrl,
      category: category ?? 'other',
      side: side,
      amount: amount,
      recipient: recipient,
      referralCode: referralCode,
      audience: audience,
    );
  }
  double? mid;
  try {
    mid = watch(hyperliquidLiveMidProvider(m.coin)) ??
        watch(hyperliquidLiveMidProvider(m.wireCoin));
  } catch (_) {
    mid = null;
  }
  final snapshot = m.midPx > 0 ? m.midPx : m.markPx;
  final price =
      (mid != null && mid > 0) ? mid : (snapshot > 0 ? snapshot : null);
  final change = price != null && m.prevDayPx > 0
      ? (price - m.prevDayPx) / m.prevDayPx
      : null;
  List<double>? series;
  try {
    final closes = watch(hyperliquidSparklineProvider(m.wireCoin))?.closes;
    if (closes != null && closes.length >= 2) {
      final live = price != null
          ? hlSparklineWithLivePrice(closes, price)
          : closes.where((v) => v > 0).toList();
      if (live.length >= 2) {
        series =
            live.sublist(math.max(0, live.length - kShareCardSeriesPoints));
      }
    }
  } catch (_) {
    series = null;
  }
  return InvestmentCardData(
    title: name,
    ticker: ticker ?? m.coin,
    coin: m.coin,
    wireCoin: m.wireCoin,
    iconUrl: m.iconUrl ?? iconUrl,
    category: m.category,
    price: price,
    decimalCap: m.pxDecimalCap,
    change: change,
    series: series,
    side: side,
    amount: amount,
    recipient: recipient,
    referralCode: referralCode,
    audience: audience,
  );
}

/// The card for a share link (a send to anyone): the pick's card when the
/// link carries one (an Investing market by its coin, a prediction by its
/// slug), else the money card. [amountMinor] is cents for dollars, sats
/// for bitcoin; [bitcoinAmount] and [bitcoinFiat] are the bitcoin send's
/// own labels ("₿12,000", "$9.40"). [locale] formats the dollars.
/// [challenge]: a prediction pick sent as a dare (an Investing pick and a
/// money link ignore it).
ShareCardData shareCardForLink(
  ShareCardWatch watch, {
  required String locale,
  required ShareLinkKind kind,
  required int amountMinor,
  String? recipient,
  String? marketSlug,
  String? marketTitle,
  String? venue,
  String? outcome,
  String? side,
  String? bitcoinAmount,
  String? bitcoinFiat,
  String? referralCode,
  ShareCardAudience audience = ShareCardAudience.sender,
  bool challenge = false,
}) {
  final pickLabel = outcome?.trim() ?? '';
  final slug = marketSlug?.trim() ?? '';
  final name = recipient?.trim().isEmpty ?? true ? null : recipient!.trim();
  final dollars = kind == ShareLinkKind.dollars;
  final amount =
      dollars ? shareCardUsdCents(locale, amountMinor) : bitcoinAmount;
  if (pickLabel.isNotEmpty && slug.isNotEmpty) {
    if (venue == 'hyperliquid') {
      final s = side ?? (pickLabel.toLowerCase() == 'short' ? 'short' : 'long');
      return investmentCardFor(
        watch,
        coin: slug,
        title: marketTitle == slug ? null : marketTitle,
        side: s == 'short' ? 'short' : 'long',
        amount: amount,
        recipient: name,
        referralCode: referralCode,
        audience: audience,
      );
    }
    return predictionCardFor(
      watch,
      slug: slug,
      title: marketTitle?.trim().isNotEmpty == true
          ? marketTitle!.trim()
          : slug.replaceAll('-', ' '),
      outcome: pickLabel,
      picked: true,
      challenge: challenge,
      amount: amount,
      recipient: name,
      referralCode: referralCode,
      audience: audience,
    );
  }
  return MoneyCardData(
    bitcoin: !dollars,
    amount: dollars
        ? shareCardUsdCentsFull(locale, amountMinor)
        : (bitcoinAmount ?? '$amountMinor sats'),
    amountSub: dollars ? null : bitcoinFiat,
    recipient: name,
    referralCode: referralCode,
    audience: audience,
  );
}
