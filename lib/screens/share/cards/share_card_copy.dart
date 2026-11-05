// lib/screens/share/cards/share_card_copy.dart
//
// THE WORDS OF A SHARE, in the app's language.
//
//   * THE HEADLINE (founder, 1 November 2026: "state the price/odds
//     clearly, in an interesting, topic-aware way"): the clear, neutral
//     fact, now the FIRST LINE OF THE SHARE MESSAGE (the image carries the
//     one big number; restrained premium, founder 1 November 2026). A
//     stock "Tesla is $242.10, up 3.4% today"; a pre-IPO company "OpenAI
//     trades at an implied $X"; oil "Crude oil at $102.50 a barrel", gold
//     "an ounce". A prediction by its topic: politics "Markets give Lula a
//     41% chance", sports "Gen.G are 47% favourites vs T1", crypto "18%
//     odds it happens", economics "71% chance of 25 bps cut", anything
//     else "47% say yes", and "{Outcome}: {chance} chance" when nothing
//     fits. Built only from the market's own data: the market's odds,
//     never our opinion.
//   * THE EDGY LINE ON THE CARD (founder, 1 November 2026: "make it
//     interesting to share"): one short deadpan line per card, built from
//     its figures, a pool per sign and topic ([shareCardEdges]: a stock up
//     "Up 3.4%. You're welcome.", down "Discount, not disaster.", a
//     prediction "47% says I'm early, not wrong.", politics "Polls are
//     opinions. This is money.", a send "Spend it wisely. Or don't.");
//     the preview picks a seed once on open. PG: it leaves the phone; no
//     profanity, no slurs, nothing about real people beyond the market's
//     own subject. The share message does not repeat it.
//   * THE CAPS LINE at the top of the card ([shareCardTopLine]): "For
//     Daniel", "Ana, a prediction for you" (an investment: "Ana, a pick
//     for you"), the recipient's "Daniel, a friend sent you", or the venue
//     on a market shared without a link.
//   * A CHALLENGE (founder, 4 November 2026: "I think Bitcoin will win,
//     wanna fight me?"; PredictionCardData.challenge): the caps line dares
//     ("Ana, I dare you", the recipient's "Ana, a friend dares you"), the
//     edgy line is a dare built from the sender's side ([challengeEdges]:
//     "I'm on Yes. Think I'm wrong? Take the other side.", "I say Gen.G.
//     Wanna fight me?", "Yes. Prove me wrong.", "I picked Yes. Your
//     move."), and the two sides ([challengeSides]) are the sender's
//     outcome and the other one (No for Yes, the strongest rival of a
//     named outcome), each with the market's chance. Never "bet", never a
//     promise of a win.
//   * A RECEIPT'S CARD (ReceiptCardData): its own caps line and edgy
//     lines, receipt_card.dart; no headline.
//   * THE FIGURES: prices, percents and amounts in the locale's own number
//     format ("41 %", "242,10 $" in German).

import 'package:intl/intl.dart';

import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlMarket;
import 'package:kute/screens/share/cards/receipt_card.dart'
    show receiptCardEdges, receiptCardTopLine;
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show hlListPriceDecimals;
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_versus.dart'
    show ShareCardVersusSide;

/// A headline and the parts of it to emphasise.
typedef ShareCardHeadlineText = ({String text, List<String> emphasis});

/// [chance] (0–100) as the locale writes a whole percent: "47%", "47 %".
String shareCardChance(String locale, double chance) {
  final f = NumberFormat.percentPattern(_locale(locale))
    ..maximumFractionDigits = 0;
  return f.format(chance.clamp(0, 100) / 100);
}

/// [fraction] (0.034) unsigned with one decimal: "3.4%", "3,4 %".
String shareCardChangeAbs(String locale, double fraction) =>
    NumberFormat.decimalPercentPattern(
            locale: _locale(locale), decimalDigits: 1)
        .format(fraction.abs());

/// [fraction] signed: "+3.4%", "−1.2%".
String shareCardChangeSigned(String locale, double fraction) =>
    '${fraction < 0 ? '−' : '+'}${shareCardChangeAbs(locale, fraction)}';

/// A dollar price as the list writes it (four significant figures, the
/// market's decimals at most), in the locale's format: "$242.10".
String shareCardPrice(String locale, double price, {int? decimalCap}) =>
    NumberFormat.currency(
            locale: _locale(locale),
            symbol: r'$',
            decimalDigits: hlListPriceDecimals(price, decimalCap))
        .format(price);

/// Dollars from cents: "$10" when whole, else "$10.50".
String shareCardUsdCents(String locale, int cents) => NumberFormat.currency(
            locale: _locale(locale),
            symbol: r'$',
            decimalDigits: cents % 100 == 0 ? 0 : 2)
        .format(cents / 100);

/// Dollars from cents with the cents always: "$10.00".
String shareCardUsdCentsFull(String locale, int cents) => NumberFormat.currency(
        locale: _locale(locale), symbol: r'$', decimalDigits: 2)
        .format(cents / 100);

String _locale(String locale) {
  try {
    NumberFormat.decimalPattern(locale);
    return locale;
  } catch (_) {
    return 'en';
  }
}

/// "Yes" / "No" in the app's language; a named outcome as it is.
String shareCardOutcome(AppLocalizations l10n, String outcome) =>
    switch (outcome.trim().toLowerCase()) {
      'yes' => l10n.shareCardOutcomeYes,
      'no' => l10n.shareCardOutcomeNo,
      _ => outcome.trim(),
    };

/// The headline of a prediction card (see the file header); null without
/// a chance.
ShareCardHeadlineText? predictionHeadline(
    AppLocalizations l10n, PredictionCardData d) {
  final chance = d.chance;
  if (chance == null) return null;
  final loc = l10n.localeName;
  final outcome = shareCardOutcome(l10n, d.outcome);
  final c = shareCardChance(loc, chance);
  final yes = d.yesChance;
  final y = yes == null ? c : shareCardChance(loc, yes);
  final named = !d.binary;
  final isNo = d.outcome.trim().toLowerCase() == 'no';
  ShareCardHeadlineText h(String text, String number) =>
      (text: text, emphasis: [number]);
  switch (d.topic) {
    case ShareCardTopic.politics:
      return named
          ? h(l10n.shareCardHeadlinePoliticsNamed(outcome, c), c)
          : h(l10n.shareCardHeadlinePoliticsBinary(y), y);
    case ShareCardTopic.sports:
      if (named) {
        final opp = d.opponent?.trim();
        if (!d.leading)
          return h(l10n.shareCardHeadlineSportsToWin(outcome, c), c);
        return opp != null && opp.isNotEmpty
            ? h(l10n.shareCardHeadlineSportsVs(outcome, c, opp), c)
            : h(l10n.shareCardHeadlineSportsFav(outcome, c), c);
      }
      break;
    case ShareCardTopic.crypto:
      return named
          ? h(l10n.shareCardHeadlineCryptoNamed(c, outcome), c)
          : h(l10n.shareCardHeadlineCryptoBinary(y), y);
    case ShareCardTopic.economy:
      return named
          ? h(l10n.shareCardHeadlineEconomyNamed(c, outcome), c)
          : h(l10n.shareCardHeadlineEconomyBinary(y), y);
    case ShareCardTopic.other:
      break;
  }
  if (!named) {
    return isNo
        ? h(l10n.shareCardHeadlineSayNo(c), c)
        : h(l10n.shareCardHeadlineSayYes(c), c);
  }
  return h(l10n.shareCardHeadlineFallback(outcome, c), c);
}

/// Oil is priced by the barrel, the precious metals by the ounce.
enum _Unit { barrel, ounce, none }

_Unit _unitOf(InvestmentCardData d) {
  final words = '${d.title} ${d.coin ?? ''}'.toLowerCase();
  if (words.contains('oil') || RegExp(r'\b(cl|wti)\b').hasMatch(words)) {
    return _Unit.barrel;
  }
  if (RegExp(r'gold|silver|platinum|palladium|xau|paxg').hasMatch(words)) {
    return _Unit.ounce;
  }
  return _Unit.none;
}

/// The headline of an Investing card (see the file header); null without
/// a price.
ShareCardHeadlineText? investmentHeadline(
    AppLocalizations l10n, InvestmentCardData d) {
  final price = d.price;
  if (price == null || price <= 0 || !price.isFinite) return null;
  final loc = l10n.localeName;
  final p = shareCardPrice(loc, price, decimalCap: d.decimalCap);
  final name = d.title;
  final category = HlMarket.normalizeCategory(d.category);
  if (category == 'preipo') {
    return (text: l10n.shareCardHeadlinePreIpo(name, p), emphasis: [p]);
  }
  final unit = _unitOf(d);
  if (category == 'commodities' || unit != _Unit.none) {
    return switch (unit) {
      _Unit.barrel => (
          text: l10n.shareCardHeadlineBarrel(name, p),
          emphasis: [p]
        ),
      _Unit.ounce => (
          text: l10n.shareCardHeadlineOunce(name, p),
          emphasis: [p]
        ),
      _Unit.none => (text: l10n.shareCardHeadlineAt(name, p), emphasis: [p]),
    };
  }
  final change = d.change;
  if (change == null || change.abs() < 0.0005) {
    return (text: l10n.shareCardHeadlineIs(name, p), emphasis: [p]);
  }
  final ch = shareCardChangeAbs(loc, change);
  return change > 0
      ? (text: l10n.shareCardHeadlineUp(name, p, ch), emphasis: [p, ch])
      : (text: l10n.shareCardHeadlineDown(name, p, ch), emphasis: [p, ch]);
}

/// The edgy lines that may go on [data]'s card (see the file header),
/// built from its own figures: a stock's sign and change, a prediction's
/// chance and topic, a send's asset.
List<String> shareCardEdges(AppLocalizations l10n, ShareCardData data) {
  final loc = l10n.localeName;
  switch (data) {
    case final MoneyCardData d:
      return [
        l10n.shareEdgeMoneyWisely,
        l10n.shareEdgeMoneyFlex,
        if (d.bitcoin) l10n.shareEdgeMoneyBitcoin,
      ];
    case final PredictionCardData d when d.challenge:
      return challengeEdges(l10n, d);
    case final PredictionCardData d:
      final chance = d.chance?.clamp(0.0, 100.0);
      final outcome = shareCardOutcome(l10n, d.outcome);
      return [
        // "47% says I'm early": only for the underdog.
        if (chance != null && chance < 50)
          l10n.shareEdgePredictionEarly(shareCardChance(loc, chance)),
        // "The crowd is 53% wrong": everyone not on this side, from the
        // whole percent the card shows, so the two add up to 100.
        if (chance != null && chance.round() <= 99)
          l10n.shareEdgePredictionCrowd(
              shareCardChance(loc, 100.0 - chance.round())),
        l10n.shareEdgePredictionDare,
        if (d.topic == ShareCardTopic.politics)
          l10n.shareEdgePredictionPolitics,
        if (d.topic == ShareCardTopic.sports && !d.binary)
          l10n.shareEdgePredictionSports(outcome),
      ];
    case final InvestmentCardData d:
      final change = d.change;
      if (change == null || change.abs() < 0.0005) {
        return [l10n.shareEdgeStockEarly, l10n.shareEdgePatience];
      }
      if (change > 0) {
        return [
          l10n.shareEdgeStockEarly,
          l10n.shareEdgeStockWelcome(shareCardChangeAbs(loc, change)),
          l10n.shareEdgeStockToldYou(d.title),
        ];
      }
      return [l10n.shareEdgeStockDiscount, l10n.shareEdgeStockPanic];
    case final ReceiptCardData d:
      return receiptCardEdges(l10n, d);
  }
}

/// The dares on a challenge card (see the file header), built from the
/// sender's side.
List<String> challengeEdges(AppLocalizations l10n, PredictionCardData d) {
  final side = shareCardOutcome(l10n, d.outcome);
  return [
    l10n.challengeEdgeWrong(side),
    l10n.challengeEdgeFight(side),
    l10n.challengeEdgeProve(side),
    l10n.challengeEdgeMove(side),
  ];
}

/// The two sides of a challenge card (see the file header): the sender's
/// outcome, marked, and the side the friend is dared to take: the other
/// of Yes and No, else the market's strongest rival ("?" while the
/// market has not been read), each with its chance when known.
({ShareCardVersusSide mine, ShareCardVersusSide theirs}) challengeSides(
    AppLocalizations l10n, PredictionCardData d) {
  final loc = l10n.localeName;
  final recipient = d.audience == ShareCardAudience.recipient;
  final label = d.outcome.trim().toLowerCase();
  final yesNo = d.binary && (label == 'yes' || label == 'no');
  final String other;
  if (yesNo) {
    other = shareCardOutcome(l10n, label == 'no' ? 'Yes' : 'No');
  } else {
    final rival = d.opponent?.trim() ?? '';
    other = rival.isEmpty ? '?' : rival;
  }
  final mine = d.chance;
  final theirs = d.otherChance;
  return (
    mine: ShareCardVersusSide(
      tag: recipient ? l10n.challengeFriendSide : l10n.challengeMySide,
      name: shareCardOutcome(l10n, d.outcome),
      chance: mine == null ? null : shareCardChance(loc, mine),
      imageUrl: yesNo ? null : d.outcomeImageUrl,
    ),
    theirs: ShareCardVersusSide(
      tag: l10n.challengeYourSide,
      name: other,
      chance: theirs == null || other == '?'
          ? null
          : shareCardChance(loc, theirs),
      imageUrl: yesNo ? null : d.opponentImageUrl,
    ),
  );
}

/// The edgy line for [data] at [seed] (any int: the preview's random pick
/// on open, so each share may read differently).
String shareCardEdge(AppLocalizations l10n, ShareCardData data, int seed) {
  final pool = shareCardEdges(l10n, data);
  return pool[seed.abs() % pool.length];
}

/// The caps line at the top of [data]'s card (see the file header).
String shareCardTopLine(AppLocalizations l10n, ShareCardData data) {
  if (data is ReceiptCardData) return receiptCardTopLine(l10n, data);
  final n = data.recipient?.trim() ?? '';
  final recipient = data.audience == ShareCardAudience.recipient;
  final bool pick = switch (data) {
    MoneyCardData() => true,
    PredictionCardData(:final picked) => picked,
    InvestmentCardData(:final picked) => picked,
    ReceiptCardData() => true,
  };
  if (!pick) {
    return data is InvestmentCardData ? l10n.trading : l10n.predictions;
  }
  if (data is MoneyCardData) {
    if (recipient) {
      return n.isEmpty
          ? l10n.claimCardFromFriend
          : l10n.claimCardFromFriendNamed(n);
    }
    return n.isEmpty ? l10n.shareCardForYou : l10n.shareCardForNamed(n);
  }
  if (data is PredictionCardData && data.challenge) {
    if (recipient) {
      return n.isEmpty
          ? l10n.challengeCapsRecipient
          : l10n.challengeCapsRecipientNamed(n);
    }
    return n.isEmpty ? l10n.challengeCaps : l10n.challengeCapsNamed(n);
  }
  if (recipient) {
    return n.isEmpty ? l10n.claimCardPick : l10n.claimCardPickNamed(n);
  }
  // A prediction says it is one (founder, 5 November 2026: "more clear we
  // are sending the prediction").
  if (data is PredictionCardData) {
    return n.isEmpty
        ? l10n.shareCardPredictionForYou
        : l10n.shareCardPredictionForNamed(n);
  }
  return n.isEmpty ? l10n.shareCardPickForYou : l10n.shareCardPickForNamed(n);
}

/// The headline of [data] (see the file header); null on a money card, a
/// receipt's card or without the figure.
ShareCardHeadlineText? shareCardHeadline(
        AppLocalizations l10n, ShareCardData data) =>
    switch (data) {
      MoneyCardData() || ReceiptCardData() => null,
      final PredictionCardData d => predictionHeadline(l10n, d),
      final InvestmentCardData d => investmentHeadline(l10n, d),
    };

/// The share message: the headline first, then [message] (the entry
/// point's own text, with the link). A card without a headline (money)
/// is [message] alone. The edgy line is on the card, so the message never
/// says it again.
String shareCardMessage(
    AppLocalizations l10n, ShareCardData data, String message) {
  final headline = shareCardHeadline(l10n, data)?.text;
  return [
    if (headline != null) headline,
    message,
  ].join('\n');
}
