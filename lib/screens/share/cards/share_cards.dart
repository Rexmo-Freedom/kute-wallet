// lib/screens/share/cards/share_cards.dart
//
// THE SHARE CARD FAMILY, restrained premium (founder, 1 November 2026:
// the Robinhood / Revolut / Apple Card share cards, then "bigger numbers
// and such" and an edgy line on the card; 2 November 2026: the earlier
// cards' colours back, Sal whole and in a mood, the predictions' own
// speedometer). One widget, [ShareCard], drawing [ShareCardData]
// (share_card_data.dart) in the one layout of share_card_frame.dart, 4:5,
// captured at 1080 × 1350, on one solid colour by kind:
//
//   * MONEY (bitcoin orange, dollars green): "FOR DANIEL", the amount
//     huge and centred (a bitcoin send's value in the person's currency,
//     "in bitcoin · ₿12,000" under it), the edgy line, "Claim it on Kute"
//     quiet over the footer; Sal with his briefcase and coin.
//   * PREDICTION (blue): "ANA, A PICK FOR YOU", the market's picture (36)
//     and question (18), then the open-position screen's speedometer with
//     the outcome's chance huge under its hub and "Chance of Gen.G", "$10
//     on Gen.G" when sent as a pick, the edgy line; Sal looking up, weighing
//     it.
//   * INVESTMENT (navy): THE ACTUAL STOCK: its real logo (HlCoinIcon, 36),
//     name and ticker, the price huge, "+3.4% today" in the change's
//     colour, the last 30 days' closes as the line filling the space,
//     "Long · $25" when sent as a pick, the edgy line; Sal smug on a day
//     up, side-eyeing a day down.
//
// Sal stands at the top right ([shareCardPose]); the footer is the
// wordmark and the sharer's code. The headline sentence leads the share
// message (share_card_copy.dart, shareCardMessage); the edgy line is on
// the card only.
//
// The RECIPIENT's version ([ShareCardAudience.recipient]) is the claim
// screen's hero: "DANIEL, A FRIEND SENT YOU", "It's yours. Tap claim." on
// a money card, no code.
//
// Real data only: what is null is left out. The card never reads a
// provider or the screen's scale: the preview is exactly the image.

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/cards/share_card_copy.dart';
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:kute/screens/share/cards/share_card_speedometer.dart';
import 'package:kute/screens/shared/sal_sprite.dart' show SalClip;

/// The logo's side in the identity row.
const double kShareLogoSize = 36;

/// A change this small reads flat (muted, no colour).
const double _kFlatChange = 0.0005;

/// The card's colour by kind: bitcoin orange, dollars green, predictions
/// blue, investing navy.
ShareCardPalette shareCardPalette(ShareCardData data) => switch (data) {
      final MoneyCardData d =>
        d.bitcoin ? ShareCardPalette.bitcoin : ShareCardPalette.dollars,
      PredictionCardData() => ShareCardPalette.prediction,
      InvestmentCardData() => ShareCardPalette.investment,
    };

/// Sal's mood on the card: the briefcase on a send, weighing the odds on
/// a prediction, smug on a stock up, a side-glance on a stock down or
/// flat.
ShareCardPose shareCardPose(ShareCardData data) => switch (data) {
      MoneyCardData() => ShareCardPose.carry,
      PredictionCardData() => ShareCardPose.think,
      final InvestmentCardData d =>
        (d.change ?? 0) > _kFlatChange ? ShareCardPose.smug : ShareCardPose.point,
    };

class ShareCard extends StatelessWidget {
  const ShareCard(
      {super.key, required this.data, this.mark, this.lineSeed = 0});

  final ShareCardData data;

  /// Sal's decoded face (ShareCardSal); null: the tile alone.
  final SalClip? mark;

  /// Picks the edgy line from the card's pool (shareCardEdge): the
  /// preview's random seed, so each share may read differently.
  final int lineSeed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loc = l10n.localeName;
    final recipient = data.audience == ShareCardAudience.recipient;
    final code = recipient ? null : data.referralCode;
    final caps = shareCardTopLine(l10n, data);
    final line = shareCardEdge(l10n, data, lineSeed);
    final key = ValueKey('share-card-${data.kind}');
    final p = shareCardPalette(data);
    final pose = shareCardPose(data);
    switch (data) {
      case final MoneyCardData d:
        final sub = d.amountSub;
        final bitcoin = d.bitcoin;
        return ShareCardFrame(
          key: key,
          palette: p,
          caps: caps,
          // A bitcoin send reads in the person's currency, the bitcoin
          // under it; without the value, the bitcoin alone.
          number: bitcoin && sub != null ? sub : d.amount,
          fact:
              bitcoin && sub != null ? l10n.shareCardInBitcoin(d.amount) : null,
          center: true,
          line: line,
          quiet: recipient ? l10n.claimCardTapClaim : l10n.shareCardClaimOnKute,
          code: code,
          mark: mark,
          pose: pose,
        );
      case final PredictionCardData d:
        final outcome = shareCardOutcome(l10n, d.outcome);
        final chance = d.chance;
        return ShareCardFrame(
          key: key,
          palette: p,
          caps: caps,
          identity: ShareCardIdentity(
            palette: p,
            logo: ShareCardLogo(
              key: const ValueKey('share-card-logo'),
              size: kShareLogoSize,
              title: d.question,
              investing: false,
              palette: p,
              imageUrl: d.imageUrl,
            ),
            name: d.question,
            nameMaxLines: 2,
          ),
          // The chance on the open-position screen's speedometer, huge
          // under its hub; without a chance, the outcome alone.
          number: chance == null ? outcome : null,
          numberMax: kShareCardHeroMax,
          graphic: chance == null
              ? null
              : ShareCardSpeedometer(
                  key: const ValueKey('share-card-odds'),
                  palette: p,
                  fraction: chance / 100,
                  figure: shareCardChance(loc, chance),
                  caption: l10n.shareCardChanceOf(outcome),
                ),
          graphicFills: chance != null,
          plain: d.picked && d.amount != null
              ? l10n.shareCardAmountOn(d.amount!, outcome)
              : null,
          line: line,
          code: code,
          mark: mark,
          pose: pose,
        );
      case final InvestmentCardData d:
        final price = d.price;
        final change = d.change;
        final series = d.series;
        final ticker = d.ticker;
        final side = d.side;
        final sideLabel = side == null
            ? null
            : side == 'short'
                ? l10n.shortLabel
                : l10n.longLabel;
        final accent = p.signed(change, flat: _kFlatChange);
        final hasChart = series != null && series.length >= 2;
        return ShareCardFrame(
          key: key,
          palette: p,
          caps: caps,
          identity: ShareCardIdentity(
            palette: p,
            logo: ShareCardLogo(
              key: const ValueKey('share-card-logo'),
              size: kShareLogoSize,
              title: d.title,
              investing: true,
              palette: p,
              coin: d.coin,
              wireCoin: d.wireCoin,
              iconUrl: d.iconUrl,
              category: d.category,
            ),
            name: d.title,
            meta: ticker != null && ticker != d.title ? ticker : null,
          ),
          number: price == null || price <= 0 || !price.isFinite
              ? null
              : shareCardPrice(loc, price, decimalCap: d.decimalCap),
          fact: change == null
              ? null
              : l10n.shareCardToday(shareCardChangeSigned(loc, change)),
          factColor:
              change == null || change.abs() <= _kFlatChange ? null : accent,
          graphic: hasChart
              ? ShareCardSparkline(
                  key: const ValueKey('share-card-chart'),
                  points: series,
                  color: change == null || change.abs() <= _kFlatChange
                      ? p.ink
                      : accent,
                )
              : null,
          graphicFills: hasChart,
          plain: sideLabel == null
              ? null
              : d.amount == null
                  ? sideLabel
                  : '$sideLabel · ${d.amount}',
          line: line,
          code: code,
          mark: mark,
          pose: pose,
        );
    }
  }
}
