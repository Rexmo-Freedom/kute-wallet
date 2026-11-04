// lib/screens/share/send_pick.dart
//
// WHAT A "SEND A PREDICTION" IS SENT ON (founder, 4 November 2026: "it
// auto-selects No and such. I mean I don't really understand"). A
// [SendPickMarket] is the market a prediction or an investment is sent
// on, with every side the person can send ([SendPickMarket.sides]),
// NONE OF THEM CHOSEN: Send to anyone (send_to_anyone_sheet.dart) opens
// on its side step and the person taps one. The leading outcome is never
// a default any more (it read "No" on a market where No leads).
//
//   * A Yes/No market: Yes and No, as the market page's own pair
//     (MarketPairButton), the two equal.
//   * A two-sided market (Up / Down, two teams): its two outcomes, the
//     positive one first, as the same pair.
//   * A market of several outcomes (candidates): every outcome as a row,
//     the biggest chance first; a row sends that outcome.
//   * An outcome opened from an event (the page's own Yes/No screen of a
//     candidate, PolymarketEvent.isSyntheticBinary): the candidate alone.
//     A link names the event's outcome, and the Claim screen opens the
//     slip on it; "No" on one candidate is not something a link can
//     carry, so the step is skipped and the pick reads the candidate.
//   * An Investing market: Long and Short as a pair; a spot token, Long
//     alone (nothing to short).
//
// A position page's send keeps the position's own side: that is the
// person's pick already, not a default ([SendPickMarket.chosen]).

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/formatters/polymarket_side_labels.dart'
    show PolymarketSideGlyph, polymarketPositiveIndex, polymarketSideGlyph;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart'
    show HlMarket, HlMarketKind;
import 'package:kute/models/polymarket_model.dart' show PolymarketEvent;
import 'package:kute/providers/hyperliquid_search_provider.dart'
    show HlMarketSearchResult;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show formatHlPrice, hlFriendlyName;
import 'package:kute/screens/polymarket/components/price_format.dart'
    show formatPolyChance, formatPolyChanceFigure;
import 'package:kute/screens/search/components/search_rows.dart';
import 'package:kute/screens/shared/market_pair_button.dart';
import 'package:kute/theme/app_theme.dart';

/// The share-link venue of a prediction ([SendPickMarket.venue]).
const String kSendPickVenuePredictions = 'polymarket';

/// The share-link venue of an investment.
const String kSendPickVenueInvesting = 'hyperliquid';

/// One side the person can send: what goes on the link ([label], the
/// outcome's [index] in the event, the order [side]) and what the step
/// shows ([chance], 0 to 1, on a prediction).
@immutable
class SendPickSide {
  const SendPickSide({
    required this.label,
    required this.side,
    this.index,
    this.chance,
  });

  /// "Yes", "No", a candidate, "Up", "Long", "Short".
  final String label;

  /// `buy` for a prediction's outcome, `long` or `short` on Investing.
  final String side;
  final int? index;
  final double? chance;

  bool get isShort => side == 'short';

  @override
  bool operator ==(Object other) =>
      other is SendPickSide &&
      other.label == label &&
      other.side == side &&
      other.index == index;

  @override
  int get hashCode => Object.hash(label, side, index);
}

/// A market a prediction or an investment is sent on (see the file
/// header). [chosen] is a side already picked (a position's own); null
/// asks on the side step.
@immutable
class SendPickMarket {
  const SendPickMarket({
    required this.venue,
    required this.slug,
    required this.title,
    required this.sides,
    this.subtitle,
    this.imageUrl,
    this.coin,
    this.wireCoin,
    this.coinCategory,
    this.coinIconUrl,
    this.price,
    this.chosen,
  });

  /// [kSendPickVenuePredictions] or [kSendPickVenueInvesting].
  final String venue;

  /// The event slug, or the Investing coin.
  final String slug;

  /// The market's name as its page names it.
  final String title;

  /// An Investing market's ticker under its display name.
  final String? subtitle;

  /// A prediction's picture.
  final String? imageUrl;

  /// An Investing market's logo sources (HlCoinIcon).
  final String? coin;
  final String? wireCoin;
  final String? coinCategory;
  final String? coinIconUrl;

  /// An Investing market's price, formatted.
  final String? price;

  /// Every side that can be sent, in the order the step shows them.
  final List<SendPickSide> sides;

  /// A side picked already (a position's); null: the person chooses.
  final SendPickSide? chosen;

  bool get investing => venue == kSendPickVenueInvesting;

  /// Whether the step draws the sides as the market page's pair (two
  /// equal buttons) rather than one row per outcome.
  bool get isPair => sides.length == 2;

  /// Whether there is anything to choose: more than one side and none
  /// picked yet.
  bool get needsSide => chosen == null && sides.length > 1;

  /// The side the link carries without a choice: the one picked, or the
  /// only one there is.
  SendPickSide? get settled =>
      chosen ?? (sides.length == 1 ? sides.single : null);

  /// This market with [side] picked.
  SendPickMarket choose(SendPickSide? side) => SendPickMarket(
        venue: venue,
        slug: slug,
        title: title,
        sides: sides,
        subtitle: subtitle,
        imageUrl: imageUrl,
        coin: coin,
        wireCoin: wireCoin,
        coinCategory: coinCategory,
        coinIconUrl: coinIconUrl,
        price: price,
        chosen: side,
      );

  /// A prediction market (see the file header for the sides).
  factory SendPickMarket.prediction(PolymarketEvent e, {SendPickSide? chosen}) =>
      SendPickMarket(
        venue: kSendPickVenuePredictions,
        slug: e.slug,
        title: e.title,
        imageUrl: e.displayIconUrl ?? e.imageUrl,
        sides: sendPickPredictionSides(e),
        chosen: chosen,
      );

  /// An Investing market from the universe.
  factory SendPickMarket.investing(HlMarket m, {required AppLocalizations l10n}) {
    final name = hlFriendlyName(m.coin) ?? m.coin;
    return SendPickMarket(
      venue: kSendPickVenueInvesting,
      slug: m.coin,
      title: name,
      subtitle: name != m.coin ? m.coin : null,
      coin: m.coin,
      wireCoin: m.wireCoin,
      coinCategory: m.category,
      coinIconUrl: m.iconUrl,
      price: formatHlPrice(m.midPx > 0 ? m.midPx : m.markPx,
          decimalCap: m.pxDecimalCap),
      sides: sendPickInvestingSides(l10n, spot: m.isSpot),
    );
  }

  /// An Investing market from the search.
  factory SendPickMarket.investingResult(HlMarketSearchResult r,
      {required AppLocalizations l10n}) {
    final market = r.market;
    if (market != null) return SendPickMarket.investing(market, l10n: l10n);
    final name = (r.name?.trim().isNotEmpty ?? false)
        ? r.name!.trim()
        : (hlFriendlyName(r.coin) ?? r.coin);
    return SendPickMarket(
      venue: kSendPickVenueInvesting,
      slug: r.coin,
      title: name,
      subtitle: name != r.coin ? r.coin : null,
      coin: r.coin,
      wireCoin: r.wireCoin,
      coinCategory: r.category,
      coinIconUrl: r.iconUrl,
      price: formatHlPrice(r.markPx, decimalCap: r.pxDecimalCap),
      sides:
          sendPickInvestingSides(l10n, spot: r.kind == HlMarketKind.spot),
    );
  }
}

/// The sides of a prediction market, none chosen (see the file header).
List<SendPickSide> sendPickPredictionSides(PolymarketEvent e) {
  final outcomes = e.outcomes;
  if (outcomes.isEmpty) return const [];
  if (e.isSyntheticBinary) {
    // The candidate's own Yes/No screen: the candidate, as the event names
    // it (the link resolves it by name on the event).
    return [
      SendPickSide(
          label: e.title, side: 'buy', chance: e.yesPrice.clamp(0.0, 1.0)),
    ];
  }
  if (outcomes.length == 2 && outcomes.every((o) => o.noTokenId == null)) {
    // Yes / No, Up / Down, two teams: the positive side first.
    final positive =
        polymarketPositiveIndex([for (final o in outcomes) o.name]);
    return [
      for (final i in [positive, 1 - positive])
        SendPickSide(
          label: outcomes[i].name,
          side: 'buy',
          index: i,
          chance: outcomes[i].price.clamp(0.0, 1.0),
        ),
    ];
  }
  // Several outcomes: each one, the biggest chance first.
  final order = [for (var i = 0; i < outcomes.length; i++) i]
    ..sort((a, b) => outcomes[b].price.compareTo(outcomes[a].price));
  return [
    for (final i in order)
      SendPickSide(
        label: outcomes[i].name,
        side: 'buy',
        index: i,
        chance: outcomes[i].price.clamp(0.0, 1.0),
      ),
  ];
}

/// Long and Short; Long alone on a spot token.
List<SendPickSide> sendPickInvestingSides(AppLocalizations l10n,
        {required bool spot}) =>
    [
      SendPickSide(label: l10n.longLabel, side: 'long'),
      if (!spot) SendPickSide(label: l10n.shortLabel, side: 'short'),
    ];

/// Whether an Investing wire coin names a spot pair (`@107`, `PURR/USDC`)
/// rather than a perp ("BTC", "xyz:XYZ100").
bool sendPickWireIsSpot(String? wireCoin) {
  final w = wireCoin?.trim() ?? '';
  return w.startsWith('@') || w.contains('/');
}

/// [side]'s label as the market page writes it: Yes and No in the app's
/// language, any other outcome (a candidate, Up, a team) as it is named.
String sendPickSideLabel(AppLocalizations l10n, SendPickSide side) {
  final l = side.label.trim().toLowerCase();
  if (l == 'yes') return l10n.yes;
  if (l == 'no') return l10n.betNo;
  return side.label;
}

/// [side]'s figure: a prediction's chance ("64%"); none on Investing.
String? sendPickSideFigure(SendPickSide side) =>
    side.chance == null ? null : formatPolyChance(side.chance!);

/// "64% chance": [side]'s chance in words; null without one.
String? sendPickChanceLine(AppLocalizations l10n, SendPickSide side) =>
    side.chance == null
        ? null
        : l10n.shareMarketChance(formatPolyChanceFigure(side.chance!));

/// "Yes 64% · No 36%": every side of a pair with its chance, the two
/// equal (the Sal sheet's card and preview; nothing reads as chosen).
String sendPickSidesLine(AppLocalizations l10n, SendPickMarket market) => [
      for (final s in market.sides)
        [sendPickSideLabel(l10n, s), sendPickSideFigure(s)]
            .whereType<String>()
            .join(' '),
    ].join(' · ');

/// The market's picture, as its page draws it: an Investing market's
/// logo (HlCoinIcon), a prediction's event image.
Widget sendPickLogo(BuildContext context, SendPickMarket market,
    {double size = kSearchRowLogo}) {
  final coin = market.coin;
  if (market.investing && coin != null && coin.isNotEmpty) {
    return HlCoinIcon(
      coin: coin,
      wireCoin: market.wireCoin ?? coin,
      category: market.coinCategory,
      iconUrl: market.coinIconUrl,
      size: size,
    );
  }
  return searchEventLogo(context, market.imageUrl, size: size);
}

/// What is being sent, at the top of the side step: the market's picture,
/// its name on up to two lines (an Investing market's ticker under it)
/// and, on Investing, the price at the right. Flat, in the search rows'
/// type; not a button.
class SendPickMarketHeader extends StatelessWidget {
  const SendPickMarketHeader({super.key, required this.market});

  final SendPickMarket market;

  @override
  Widget build(BuildContext context) {
    final subtitle = market.subtitle;
    final price = market.price;
    return ConstrainedBox(
      key: const ValueKey('send-pick-market-header'),
      constraints: const BoxConstraints(minHeight: kSearchRowHeight),
      child: Row(
        children: [
          sendPickLogo(context, market, size: 44),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  market.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SearchListRow.titleStyle(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  SizedBox(height: 2.h),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SearchListRow.subtitleStyle(context)),
                ],
              ],
            ),
          ),
          if (market.investing && price != null && price.isNotEmpty) ...[
            SizedBox(width: 12.w),
            Text(price, style: SearchListRow.figureStyle(context)),
          ],
        ],
      ),
    );
  }
}

/// Every side of [market], none chosen: two sides as the market page's
/// own pair (MarketPairButton, the positive side green on the left, the
/// other red, the two equal), more as one search row per outcome with
/// its chance. A tap is the choice ([onPicked]).
class SendPickSideChooser extends StatelessWidget {
  const SendPickSideChooser(
      {super.key, required this.market, required this.onPicked});

  final SendPickMarket market;
  final ValueChanged<SendPickSide> onPicked;

  static IconData _icon(SendPickMarket market, SendPickSide side) {
    if (market.investing) {
      return side.isShort
          ? Icons.arrow_downward_rounded
          : Icons.arrow_upward_rounded;
    }
    return switch (polymarketSideGlyph(side.label)) {
      PolymarketSideGlyph.yes => Icons.check_rounded,
      PolymarketSideGlyph.no => Icons.close_rounded,
      PolymarketSideGlyph.up => Icons.arrow_upward_rounded,
      PolymarketSideGlyph.down => Icons.arrow_downward_rounded,
      PolymarketSideGlyph.neutral => Icons.bolt_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sides = market.sides;
    if (market.isPair) {
      Widget button(int i) => Expanded(
            child: MarketPairButton(
              key: ValueKey('send-pick-side-$i'),
              label: sendPickSideLabel(l10n, sides[i]),
              value: sendPickSideFigure(sides[i]),
              icon: _icon(market, sides[i]),
              iconDisc: true,
              glow: true,
              color: i == 0 ? AppColors.marketUp : AppColors.marketDown,
              onTap: () => onPicked(sides[i]),
            ),
          );
      return Row(
        key: const ValueKey('send-pick-side-pair'),
        children: [button(0), SizedBox(width: 12.w), button(1)],
      );
    }
    return SearchRowList(
      key: const ValueKey('send-pick-outcomes'),
      children: [
        for (var i = 0; i < sides.length; i++)
          SearchListRow(
            key: ValueKey('send-pick-outcome-$i'),
            title: sendPickSideLabel(l10n, sides[i]),
            titleLines: 2,
            trailing: sides[i].chance == null
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SearchChanceGauge(chance: sides[i].chance!),
                      SizedBox(width: 8.w),
                      Text(sendPickSideFigure(sides[i])!,
                          style: SearchListRow.figureStyle(context)),
                    ],
                  ),
            onTap: () => onPicked(sides[i]),
          ),
      ],
    );
  }
}
