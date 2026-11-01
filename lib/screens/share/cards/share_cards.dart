// lib/screens/share/cards/share_cards.dart
//
// THE SHARE CARD FAMILY, restrained premium (founder, 1 November 2026:
// the Robinhood / Revolut / Apple Card share cards, then "bigger numbers
// and such" and an edgy line on the card). One widget, [ShareCard],
// drawing [ShareCardData] (share_card_data.dart) in the one layout of
// share_card_frame.dart, 4:5, captured at 1080 × 1350:
//
//   * MONEY (near-black): "FOR DANIEL", the amount huge and centred (a
//     bitcoin send's value in the person's currency, "in bitcoin ·
//     ₿12,000" under it), the asset's mark as a faint watermark, the edgy
//     line, "Claim it on Kute" quiet over the footer.
//   * PREDICTION (white with a hairline): "ANA, A PICK FOR YOU", the
//     market's picture (36) and question (18), the outcome's chance huge
//     (80), "Chance of Gen.G", the 10 px odds bar with both sides named
//     and their percents ("Gen.G 47%" in the bar's blue, "T1 53%" muted)
//     and the two crests at its ends when both are known, "$10 on Gen.G"
//     when sent as a pick, the edgy line.
//   * INVESTMENT (near-black): THE ACTUAL STOCK: its real logo
//     (HlCoinIcon, 36), name and ticker, the price huge, "+3.4% today" in
//     the change's colour, the last 30 days' closes as the line filling
//     the space, "Long · $25" when sent as a pick, the edgy line.
//
// Every card ends on Sal's small mark, the wordmark and the sharer's code.
// The headline sentence leads the share message (share_card_copy.dart,
// shareCardMessage); the edgy line is on the card only.
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
import 'package:kute/screens/shared/sal_sprite.dart' show SalClip;

/// The logo's side in the identity row.
const double kShareLogoSize = 36;

/// A crest's side at the odds bar's ends.
const double kShareCrestSize = ShareCardOddsBar.crestSize;

/// A change this small reads flat (muted, no colour).
const double _kFlatChange = 0.0005;

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
    switch (data) {
      case final MoneyCardData d:
        const p = ShareCardPalette.dark;
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
          watermark: bitcoin ? '₿' : r'$',
          line: line,
          quiet: recipient ? l10n.claimCardTapClaim : l10n.shareCardClaimOnKute,
          code: code,
          mark: mark,
        );
      case final PredictionCardData d:
        const p = ShareCardPalette.light;
        final outcome = shareCardOutcome(l10n, d.outcome);
        final chance = d.chance;
        final String? other = d.binary
            ? shareCardOutcome(
                l10n, d.outcome.trim().toLowerCase() == 'no' ? 'Yes' : 'No')
            : d.opponent?.trim().isNotEmpty == true
                ? d.opponent!.trim()
                : null;
        final otherChance = d.otherChance;
        // The crests only when each side has its own picture (a market
        // whose outcomes all carry the event's picture shows none).
        final a = d.outcomeImageUrl, b = d.opponentImageUrl;
        final crests = !d.binary &&
            a != null &&
            b != null &&
            a.isNotEmpty &&
            b.isNotEmpty &&
            a != b;
        Widget? crest(String? url, String label) => !crests || url == null
            ? null
            : ShareCardLogo(
                size: kShareCrestSize,
                title: label,
                investing: false,
                palette: p,
                imageUrl: url,
                round: true,
              );
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
          number: chance == null ? outcome : shareCardChance(loc, chance),
          numberMax: kShareCardHeroMax,
          fact: chance == null ? null : l10n.shareCardChanceOf(outcome),
          factSize: 16,
          graphic: chance == null
              ? null
              : ShareCardOddsBar(
                  key: const ValueKey('share-card-odds'),
                  palette: p,
                  fraction: chance / 100,
                  left: outcome,
                  leftValue: shareCardChance(loc, chance),
                  right: other,
                  rightValue: other == null || otherChance == null
                      ? null
                      : shareCardChance(loc, otherChance),
                  leftImage: crest(d.outcomeImageUrl, outcome),
                  rightImage:
                      other == null ? null : crest(d.opponentImageUrl, other),
                ),
          plain: d.picked && d.amount != null
              ? l10n.shareCardAmountOn(d.amount!, outcome)
              : null,
          line: line,
          code: code,
          mark: mark,
        );
      case final InvestmentCardData d:
        const p = ShareCardPalette.dark;
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
        );
    }
  }
}
