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
//   * SAL'S LINE: the playful one-liner, a pool per card, the message's
//     line after the headline ([shareCardMessage]); the preview picks a
//     seed once on open. PG: the message leaves the phone.
//   * THE CAPS LINE at the top of the card ([shareCardTopLine]): "For
//     Daniel", "Ana, a pick for you", the recipient's "Daniel, a friend
//     sent you", or the venue on a market shared without a link.
//   * THE FIGURES: prices, percents and amounts in the locale's own number
//     format ("41 %", "242,10 $" in German).

import 'package:intl/intl.dart';

import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlMarket;
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show hlListPriceDecimals;
import 'package:kute/screens/share/cards/share_card_data.dart';

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
    NumberFormat.decimalPercentPattern(locale: _locale(locale), decimalDigits: 1)
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
String shareCardUsdCents(String locale, int cents) =>
    NumberFormat.currency(
            locale: _locale(locale),
            symbol: r'$',
            decimalDigits: cents % 100 == 0 ? 0 : 2)
        .format(cents / 100);

/// Dollars from cents with the cents always: "$10.00".
String shareCardUsdCentsFull(String locale, int cents) =>
    NumberFormat.currency(locale: _locale(locale), symbol: r'$', decimalDigits: 2)
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
        if (!d.leading) return h(l10n.shareCardHeadlineSportsToWin(outcome, c), c);
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
      _Unit.barrel => (text: l10n.shareCardHeadlineBarrel(name, p), emphasis: [p]),
      _Unit.ounce => (text: l10n.shareCardHeadlineOunce(name, p), emphasis: [p]),
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

/// Sal's lines for [data] (see the file header).
List<String> shareCardLines(AppLocalizations l10n, ShareCardData data) {
  return switch (data) {
    MoneyCardData() => [
        l10n.shareCardLineClaimIt,
        l10n.shareCardLineDontSpend,
        l10n.shareCardLineFreeMoney,
      ],
    PredictionCardData(picked: true) => [
        l10n.shareCardLineTrustMe,
        l10n.shareCardLineKnowEnding,
        l10n.shareCardLineEasyMoney,
      ],
    PredictionCardData() => [
        l10n.shareCardLineWhatDoYouThink,
        l10n.shareCardLineYourCall,
        l10n.shareCardLinePickASide,
      ],
    InvestmentCardData() => [
        l10n.shareCardLineGoingPlaces,
        l10n.shareCardLineBuyHigh,
        l10n.shareCardLineBetterTaste,
      ],
  };
}

/// The line for [data] at [seed] (any int).
String shareCardLine(AppLocalizations l10n, ShareCardData data, int seed) {
  final pool = shareCardLines(l10n, data);
  return pool[seed.abs() % pool.length];
}

/// The caps line at the top of [data]'s card (see the file header).
String shareCardTopLine(AppLocalizations l10n, ShareCardData data) {
  final n = data.recipient?.trim() ?? '';
  final recipient = data.audience == ShareCardAudience.recipient;
  final bool pick = switch (data) {
    MoneyCardData() => true,
    PredictionCardData(:final picked) => picked,
    InvestmentCardData(:final picked) => picked,
  };
  if (!pick) {
    return data is InvestmentCardData ? l10n.trading : l10n.predictions;
  }
  if (data is MoneyCardData) {
    if (recipient) {
      return n.isEmpty ? l10n.claimCardFromFriend : l10n.claimCardFromFriendNamed(n);
    }
    return n.isEmpty ? l10n.shareCardForYou : l10n.shareCardForNamed(n);
  }
  if (recipient) {
    return n.isEmpty ? l10n.claimCardPick : l10n.claimCardPickNamed(n);
  }
  return n.isEmpty ? l10n.shareCardPickForYou : l10n.shareCardPickForNamed(n);
}

/// The headline of [data] (see the file header); null on a money card
/// or without the figure.
ShareCardHeadlineText? shareCardHeadline(
        AppLocalizations l10n, ShareCardData data) =>
    switch (data) {
      MoneyCardData() => null,
      final PredictionCardData d => predictionHeadline(l10n, d),
      final InvestmentCardData d => investmentHeadline(l10n, d),
    };

/// The share message: the headline first, Sal's line (at [seed]) after
/// it, then [message] (the entry point's own text, with the link). A card
/// without a headline (money) leads with [message] and Sal follows.
String shareCardMessage(
    AppLocalizations l10n, ShareCardData data, int seed, String message) {
  final headline = shareCardHeadline(l10n, data)?.text;
  final line = shareCardLine(l10n, data, seed);
  return [
    headline ?? message,
    line,
    if (headline != null) message,
  ].join('\n');
}
