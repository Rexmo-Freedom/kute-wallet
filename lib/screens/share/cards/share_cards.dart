// lib/screens/share/cards/share_cards.dart
//
// THE SHARE CARD FAMILY, restrained premium (founder, 1 November 2026:
// the Robinhood / Revolut / Apple Card share cards). One widget,
// [ShareCard], drawing [ShareCardData] (share_card_data.dart) in the one
// layout of share_card_frame.dart, 4:5, captured at 1080 × 1350:
//
//   * MONEY (near-black): "FOR DANIEL", the asset (₿ on bitcoin orange,
//     $ on green) and its name, the amount big (a bitcoin send's value in
//     the person's currency, "in bitcoin · ₿12,000" under it), no graphic.
//   * PREDICTION (white with a hairline): "ANA, A PICK FOR YOU", the
//     market's picture and question, the outcome's chance big, "Chance of
//     Gen.G", the 6 px odds bar with the two outcomes under it, "$10 on
//     Gen.G" when sent as a pick.
//   * INVESTMENT (near-black): THE ACTUAL STOCK: its real logo
//     (HlCoinIcon), name and ticker, the price big, "+3.4% today" in the
//     change's colour, the last 30 days' closes as a 1.6 px line, "Long ·
//     $25" when sent as a pick.
//
// Every card ends on Sal's small mark, the wordmark and the sharer's code.
// The headline sentence and Sal's line are not on the image: they lead
// the share message (share_card_copy.dart, shareCardMessage).
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

/// Bitcoin orange and Kute green, the money cards' asset tiles.
const Color kShareBitcoinOrange = Color(0xFFF7931A);
const Color kShareDollarsGreen = Color(0xFF12A150);

/// The logo's side in the identity row.
const double kShareLogoSize = 26;

/// A change this small reads flat (muted, no colour).
const double _kFlatChange = 0.0005;

class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.data, this.mark});

  final ShareCardData data;

  /// Sal's decoded face (ShareCardSal); null: the tile alone.
  final SalClip? mark;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loc = l10n.localeName;
    final recipient = data.audience == ShareCardAudience.recipient;
    final code = recipient ? null : data.referralCode;
    final caps = shareCardTopLine(l10n, data);
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
          identity: ShareCardIdentity(
            palette: p,
            logo: ShareCardGlyphLogo(
              glyph: bitcoin ? '₿' : r'$',
              color: bitcoin ? kShareBitcoinOrange : kShareDollarsGreen,
            ),
            name: bitcoin ? l10n.bitcoin : l10n.assetDollars,
          ),
          // A bitcoin send reads in the person's currency, the bitcoin
          // under it; without the value, the bitcoin alone.
          number: bitcoin && sub != null ? sub : d.amount,
          fact: bitcoin && sub != null ? l10n.shareCardInBitcoin(d.amount) : null,
          plain: recipient ? l10n.claimCardTapClaim : null,
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
          fact: chance == null ? null : l10n.shareCardChanceOf(outcome),
          graphic: chance == null
              ? null
              : ShareCardOddsBar(
                  key: const ValueKey('share-card-odds'),
                  palette: p,
                  fraction: chance / 100,
                  left: outcome,
                  right: other,
                ),
          plain: d.picked && d.amount != null
              ? l10n.shareCardAmountOn(d.amount!, outcome)
              : null,
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
          factColor: accent,
          graphic: series != null && series.length >= 2
              ? ShareCardSparkline(
                  key: const ValueKey('share-card-chart'),
                  points: series,
                  color: change == null || change.abs() <= _kFlatChange
                      ? p.ink
                      : accent,
                )
              : null,
          graphicFills: true,
          plain: sideLabel == null
              ? null
              : d.amount == null
                  ? sideLabel
                  : '$sideLabel · ${d.amount}',
          code: code,
          mark: mark,
        );
    }
  }
}
