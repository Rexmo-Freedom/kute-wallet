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
//   * A PICK SENT, A GIFT (founder, 7 November 2026, of the investment
//     card with Bitcoin's price huge: "Make this more clear we are
//     sending"; share_card_gift.dart): read as the money cards, the gift
//     first. "ANA, AN INVESTMENT FOR YOU" / "ANA, A PREDICTION FOR YOU"
//     (two lines beside Sal rather than cut), THE AMOUNT SENT huge beside
//     Sal with the coin on his head, the position right under it in big
//     type, its side word in its colour ("Short Bitcoin", "Long Tesla",
//     "Yes · Lula to win", "Yes"), then the context smaller: the logo and
//     the name (an investment's ticker, price and "−0.2% today" at the
//     right, the last 30 days' line under them; a prediction's question,
//     its speedometer small with "47%" and "Chance of Gen.G" beside it),
//     the edgy line. Navy for an investment, blue for a prediction.
//   * PREDICTION (blue): "PREDICTIONS", the market's picture (36)
//     and question (18, wrapping, never cut while it can be read), then
//     the open-position screen's speedometer with the outcome's chance huge
//     under its hub and "Chance of Gen.G", the edgy line; Sal looking up,
//     weighing it. A MARKET of named
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
//   * GOAL (a level on the Bitcoin home's Goals, goal_share.dart; founder,
//     8 November 2026: "we should be able to share the goals"): "MY LEVEL",
//     "Level 3" huge, the level's name under it, Sal as that level's own
//     still standing on the rule, a deadpan line, the footer. On the app's
//     ink, as the invite. NO MONEY: no balance, no threshold, no percent, no
//     currency.
//   * INVESTMENT (navy, a market shared): THE ACTUAL STOCK: its real logo
//     (HlCoinIcon, 36), name and ticker, the price huge, "+3.4% today" in
//     the change's colour, the last 30 days' closes as the line filling
//     the space, the edgy line; Sal lounging on a day up (eyes shut at
//     +10%), flopped on a day down.
//
// Sal ([shareCardPose]) sits at the top right over a graphic, else stands
// on the rule; the footer is the wordmark and the sharer's code. The headline sentence leads the share
// message (share_card_copy.dart, shareCardMessage); the edgy line is on
// the card only.
//
// The RECIPIENT's version ([ShareCardAudience.recipient]) is the claim
// screen's hero: "DANIEL, A FRIEND SENT YOU" over any gift, money or a
// pick, "It's yours. Tap claim." on a money card, no code.
//
// Real data only: what is null is left out. The card never reads a
// provider or the screen's scale: the preview is exactly the image.

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/cards/receipt_card.dart';
import 'package:kute/screens/share/cards/share_card_copy.dart';
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:kute/screens/share/cards/share_card_gift.dart';
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
      // The app's ink, Sal's orange popping on it, the figure in orange.
      InviteCardData() => ShareCardPalette.bitcoinClaim,
      // The invite's ink: the level's Sal, orange, pops on it, where on
      // bitcoin orange he and his gold melt into the ground.
      GoalCardData() => ShareCardPalette.bitcoinClaim,
    };

/// A stock up this much today (a fraction) gets Sal's big win.
const double kShareCardBigChange = 0.10;

/// Sal's pose on the card: the coin balanced on her head on every gift
/// (money, a pick sent), squinting at the odds on a prediction market,
/// the side-eye on a dare; on a stock shared, today's change: lounging
/// up, eyes shut at [kShareCardBigChange] or more, a flop down, a
/// side-eye flat.
ShareCardPose shareCardPose(ShareCardData data) => switch (data) {
      MoneyCardData() =>
        // Every money send has the coin on her head (founder, 5 November
        // 2026: not the briefcase-and-glasses one).
        ShareCardPose.claim,
      // A dare: the slow side-eye, "and?".
      PredictionCardData(challenge: true) => ShareCardPose.flat,
      // A pick sent is a gift: the coin, as money's.
      PredictionCardData(picked: true) => ShareCardPose.claim,
      PredictionCardData() => ShareCardPose.predict,
      InvestmentCardData(picked: true) => ShareCardPose.claim,
      final InvestmentCardData d => switch (d.change ?? 0) {
          final c when c >= kShareCardBigChange => ShareCardPose.bigWin,
          final c when c > _kFlatChange => ShareCardPose.win,
          final c when c < -_kFlatChange => ShareCardPose.loss,
          _ => ShareCardPose.flat,
        },
      final ReceiptCardData d => receiptCardPose(d),
      // An invite is a gift: the coin on her head.
      InviteCardData() => ShareCardPose.claim,
      // Never drawn: the card hands the frame its level's still.
      GoalCardData() => ShareCardPose.flat,
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
      case final InviteCardData d:
        final discount = d.discount;
        return ShareCardFrame(
          key: key,
          palette: p,
          caps: caps,
          number: discount == null ? null : l10n.inviteCardDiscount(discount),
          numberBase: kShareCardMoneyHeroMax,
          fact: discount == null ? null : l10n.inviteCardFees,
          plain: discount == null ? l10n.inviteCardJoin : null,
          plainStrong: discount == null,
          line: line,
          quiet: l10n.inviteCardUseCode,
          code: code,
          mark: mark,
          pose: pose,
        );
      case final GoalCardData d:
        return ShareCardFrame(
          key: key,
          palette: p,
          caps: caps,
          number: l10n.balanceGoalLevel(d.level),
          numberBase: kShareCardMoneyHeroMax,
          plain: d.name,
          plainStrong: true,
          line: line,
          code: code,
          mark: mark,
          still: d.still,
        );
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
      // A pick sent: the gift first (share_card_gift.dart).
      case final PredictionCardData d when d.picked:
        final outcome = shareCardOutcome(l10n, d.outcome);
        final chance = d.chance;
        return ShareCardFrame(
          key: key,
          palette: p,
          caps: caps,
          capsLines: 2,
          number: d.amount,
          numberBase: kShareCardMoneyHeroMax,
          numberBesideSal: true,
          position: _positionLine(l10n, d, p),
          graphic: ShareCardGiftContext(
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
            below: chance == null
                ? null
                : ShareCardSpeedometerRow(
                    key: const ValueKey('share-card-odds'),
                    palette: p,
                    fraction: chance / 100,
                    figure: shareCardChance(loc, chance),
                    caption: l10n.shareCardChanceOf(outcome),
                  ),
          ),
          graphicFills: true,
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
        final accent = p.signed(change, flat: _kFlatChange);
        final flat = change == null || change.abs() <= _kFlatChange;
        final hasChart = series != null && series.length >= 2;
        final priceText = price == null || price <= 0 || !price.isFinite
            ? null
            : shareCardPrice(loc, price, decimalCap: d.decimalCap);
        final changeText = change == null
            ? null
            : l10n.shareCardToday(shareCardChangeSigned(loc, change));
        final logo = ShareCardLogo(
          key: const ValueKey('share-card-logo'),
          size: kShareLogoSize,
          title: d.title,
          investing: true,
          palette: p,
          coin: d.coin,
          wireCoin: d.wireCoin,
          iconUrl: d.iconUrl,
          category: d.category,
        );
        final meta = ticker != null && ticker != d.title ? ticker : null;
        final chart = hasChart
            ? ShareCardSparkline(
                key: const ValueKey('share-card-chart'),
                points: series,
                color: flat ? p.ink : accent,
              )
            : null;
        // A pick sent: the gift first, the market as its context
        // (share_card_gift.dart).
        if (d.picked) {
          return ShareCardFrame(
            key: key,
            palette: p,
            caps: caps,
            capsLines: 2,
            number: d.amount,
            numberBase: kShareCardMoneyHeroMax,
            numberBesideSal: true,
            position: _positionLine(l10n, d, p),
            graphic: ShareCardGiftContext(
              palette: p,
              logo: logo,
              name: d.title,
              meta: meta,
              trailing: priceText == null && changeText == null
                  ? null
                  : ShareCardPriceColumn(
                      palette: p,
                      price: priceText,
                      change: changeText,
                      changeColor: flat ? null : accent,
                    ),
              below: chart,
            ),
            graphicFills: true,
            line: line,
            code: code,
            mark: mark,
            pose: pose,
          );
        }
        return ShareCardFrame(
          key: key,
          palette: p,
          caps: caps,
          identity: ShareCardIdentity(
            palette: p,
            logo: logo,
            name: d.title,
            meta: meta,
          ),
          number: priceText,
          fact: changeText,
          factColor: flat ? null : accent,
          graphic: chart,
          graphicFills: hasChart,
          line: line,
          code: code,
          mark: mark,
          pose: pose,
        );
    }
  }
}

/// A gift's position line under the amount ([shareCardPosition]).
Widget? _positionLine(
    AppLocalizations l10n, ShareCardData d, ShareCardPalette p) {
  final position = shareCardPosition(l10n, d);
  if (position == null) return null;
  return ShareCardPositionLine(
    textKey: const ValueKey('share-card-position'),
    position: position,
    palette: p,
  );
}
