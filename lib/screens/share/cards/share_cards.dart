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
//     huge at the left (a bitcoin send's value in the person's currency,
//     "in bitcoin · ₿12,000" under it), Sal with his briefcase and coin
//     standing on the rule beside it, the edgy line, "Claim it on Kute"
//     quiet over the footer.
//   * PREDICTION (blue): "ANA, A PICK FOR YOU", the market's picture (36)
//     and question (18, wrapping, never cut while it can be read), then
//     the open-position screen's speedometer with the outcome's chance huge
//     under its hub and "Chance of Gen.G", "$10 on Gen.G" when sent as a
//     pick, the edgy line; Sal looking up, weighing it. A MARKET of named
//     outcomes shared without a pick (Lula vs Bolsonaro) draws the market
//     page's own chart instead (share_card_market_chart.dart): its top
//     outcomes' real lines filling the card, each labelled "Lula da Silva
//     41%"; the speedometer until the history is read.
//   * CHALLENGE (blue, a pick sent as a dare; founder, 4 November 2026):
//     "ANA, I DARE YOU", the market's picture and question, then BOTH
//     SIDES (share_card_versus.dart): the sender's marked ("MY SIDE",
//     "Yes", "62%"), the other open ("YOUR SIDE?", "No", "38%"), "VS"
//     between; "$10 to play, on me", the dare as the edgy line
//     (challengeEdges); Sal's side-eye ("and?").
//   * RECEIPT (a transaction's own card, founder, 5 November 2026; its
//     colour by kind): receipt_card.dart.
//   * INVESTMENT (navy): THE ACTUAL STOCK: its real logo (HlCoinIcon, 36),
//     name and ticker, the price huge, "+3.4% today" in the change's
//     colour, the last 30 days' closes as the line filling the space,
//     "Long · $25" when sent as a pick, the edgy line; Sal lounging on a
//     day up (eyes shut at +10%), flopped on a day down.
//
// Sal ([shareCardPose]) sits at the top right over a graphic, else stands
// on the rule; the footer is the wordmark and the sharer's code. The headline sentence leads the share
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
import 'package:kute/screens/share/cards/receipt_card.dart';
import 'package:kute/screens/share/cards/share_card_copy.dart';
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:kute/screens/share/cards/share_card_market_chart.dart';
import 'package:kute/screens/share/cards/share_card_speedometer.dart';
import 'package:kute/screens/share/cards/share_card_versus.dart';
import 'package:kute/screens/shared/sal_sprite.dart' show SalClip;

/// The logo's side in the identity row.
const double kShareLogoSize = 36;

/// A change this small reads flat (muted, no colour).
const double _kFlatChange = 0.0005;

/// The card's colour by kind: dollars green, predictions blue, investing
/// navy; every bitcoin send, the sender's card and the claim hero, the
/// app's ink with the amount in orange ([ShareCardPalette.bitcoinClaim];
/// founder, 2 November 2026: "this was just to send bitcoin").
ShareCardPalette shareCardPalette(ShareCardData data) => switch (data) {
      final MoneyCardData d =>
        d.bitcoin ? ShareCardPalette.bitcoinClaim : ShareCardPalette.dollars,
      PredictionCardData() => ShareCardPalette.prediction,
      InvestmentCardData() => ShareCardPalette.investment,
      final ReceiptCardData d => receiptCardPalette(d),
    };

/// A stock up this much today (a fraction) gets Sal's big win.
const double kShareCardBigChange = 0.10;

/// Sal's pose on the card: the briefcase on a dollars send, the coin
/// balanced on her head on every bitcoin send, squinting at the odds
/// on a prediction, the side-eye on a dare; on a stock, today's change:
/// lounging up, eyes shut at
/// [kShareCardBigChange] or more, a flop down, a side-eye flat.
ShareCardPose shareCardPose(ShareCardData data) => switch (data) {
      final MoneyCardData d =>
        d.bitcoin ? ShareCardPose.claim : ShareCardPose.send,
      // A dare: the slow side-eye, "and?".
      PredictionCardData(challenge: true) => ShareCardPose.flat,
      PredictionCardData() => ShareCardPose.predict,
      final InvestmentCardData d => switch (d.change ?? 0) {
          final c when c >= kShareCardBigChange => ShareCardPose.bigWin,
          final c when c > _kFlatChange => ShareCardPose.win,
          final c when c < -_kFlatChange => ShareCardPose.loss,
          _ => ShareCardPose.flat,
        },
      final ReceiptCardData d => receiptCardPose(d),
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
      // A transaction's receipt (receipt_card.dart).
      case final ReceiptCardData d:
        return ReceiptShareCard(data: d, caps: caps, line: line, mark: mark);
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
          numberBase: kShareCardMoneyHeroMax,
          line: line,
          quiet: recipient ? l10n.claimCardTapClaim : l10n.shareCardClaimOnKute,
          code: code,
          mark: mark,
          pose: pose,
        );
      case final PredictionCardData d when d.challenge:
        final sides = challengeSides(l10n, d);
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
          ),
          graphic: ShareCardVersus(
            key: const ValueKey('share-card-odds'),
            palette: p,
            mine: sides.mine,
            theirs: sides.theirs,
          ),
          graphicFills: true,
          graphicBelowSal: true,
          plain: d.amount == null ? null : l10n.challengeStake(d.amount!),
          line: line,
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
          ),
          // The market shared with its chart read: the market page's own
          // lines fill the card, each labelled with its name and chance.
          // Else the chance on the open-position screen's speedometer, huge
          // under its hub; without a chance, the outcome alone.
          number: chance == null ? outcome : null,
          numberMax: kShareCardHeroMax,
          graphic: d.charted
              ? ShareCardMarketChart(
                  key: const ValueKey('share-card-odds'),
                  lines: d.lines!,
                  palette: p,
                  chanceText: (c) => shareCardChance(loc, c),
                  drawLabel: l10n.betDraw,
                )
              : chance == null
                  ? null
                  : ShareCardSpeedometer(
                      key: const ValueKey('share-card-odds'),
                      palette: p,
                      fraction: chance / 100,
                      figure: shareCardChance(loc, chance),
                      caption: l10n.shareCardChanceOf(outcome),
                    ),
          graphicFills: d.charted || chance != null,
          graphicBelowSal: d.charted,
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
