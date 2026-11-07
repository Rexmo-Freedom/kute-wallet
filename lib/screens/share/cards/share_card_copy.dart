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
//     interesting to share"; 5 November 2026: "add many more variations"):
//     one short deadpan line per card, built from its figures, from a
//     pool of 12 to 20 per card and state ([shareCardEdges]): a send
//     ("Spend it wisely. Or don't.", bitcoin's and dollars' own), a pick
//     by its side's odds (the favourite "62% agree. Smart crowd.", the
//     underdog "47% says I'm early, not wrong.", "The crowd is 53%
//     wrong."), a WHOLE MARKET always neutral (founder, 5 November 2026:
//     "it makes no sense to pick a side": "Vance leads. Nothing's
//     settled.", "62% say Yes. Discuss.", "Odds don't play the match."),
//     the topic's ("Polls are opinions. This is money."), a stock by
//     today's change and side ("Up 3.4%. You're welcome.", "Down 3.4%.
//     Zoom out.", a short "Gravity is a strategy too."). A figure in a
//     line is one the card shows (the crowd's share is 100% less the
//     card's percent); a name only when short ([kShareEdgeNameMax]). The
//     preview picks a seed once on open. PG: it leaves the phone; no
//     profanity, no slurs, nothing about real people beyond the market's
//     own subject, never "bet", never a promise of profit. The share
//     message does not repeat it.
//   * THE CAPS LINE at the top of the card ([shareCardTopLine]): "For
//     Daniel", "Ana, a prediction for you", "Ana, an investment for you"
//     (founder, 7 November 2026: "make this more clear we are sending"),
//     the recipient's "Daniel, a friend sent you" over any gift, money or
//     pick, or the venue on a market shared without a link.
//   * A GIFT'S POSITION ([shareCardPosition]; share_card_gift.dart): what
//     was sent, under the amount: "Short Bitcoin", "Long Tesla" (the
//     language's own order, shareCardPositionInvest), "Yes · Lula to win"
//     on a race or a match (shareCardOutcomeToWin; never a draw), "Yes ·
//     25 bps cut" on any other named outcome, a yes/no pick "Yes".
//   * A CHALLENGE (founder, 4 November 2026: "I think Bitcoin will win,
//     wanna fight me?"; PredictionCardData.challenge): the caps line dares
//     ("Ana, I dare you", the recipient's "Ana, a friend dares you"), the
//     edgy line is a dare built from the sender's side ([challengeEdges]:
//     "I'm on Yes. Think I'm wrong? Take the other side.", "I say Gen.G.
//     Wanna fight me?", "Yes. Prove me wrong.", "Gen.G. Come at me.", 15
//     in all), and the two sides ([challengeSides]) are the sender's
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
import 'package:kute/screens/polymarket/components/poly_chart_tags.dart'
    show polyChartShortName;
import 'package:kute/screens/share/cards/receipt_card.dart'
    show receiptCardEdges, receiptCardTopLine;
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show hlListPriceDecimals;
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_gift.dart'
    show ShareCardPosition;
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

/// A name goes into an edgy line only up to this many characters: a
/// longer one ("Inácio Lula da Silva") would push the line past its two
/// lines, so the pool leaves those lines out.
const int kShareEdgeNameMax = 14;

/// A day this big (a fraction) gets the big-day lines, as it gets Sal's
/// big win (kShareCardBigChange, share_cards.dart).
const double _kEdgeBigChange = 0.10;

/// A change this small reads flat, as the card's colour reads it.
const double _kEdgeFlatChange = 0.0005;

bool _nameFits(String name) =>
    name.isNotEmpty && name.length <= kShareEdgeNameMax;

/// The edgy lines that may go on [data]'s card (see the file header),
/// built from its own figures: a stock's sign and change, a prediction's
/// chance, side and topic, a send's asset and amount.
List<String> shareCardEdges(AppLocalizations l10n, ShareCardData data) =>
    switch (data) {
      final MoneyCardData d => _moneyEdges(l10n, d),
      final PredictionCardData d when d.challenge => challengeEdges(l10n, d),
      final PredictionCardData d when d.picked => _pickEdges(l10n, d),
      final PredictionCardData d => _marketEdges(l10n, d),
      final InvestmentCardData d => _investmentEdges(l10n, d),
      final ReceiptCardData d => receiptCardEdges(l10n, d),
    };

/// A send's lines: the money lines, then bitcoin's or dollars' own; the
/// card's amount where a line names it.
List<String> _moneyEdges(AppLocalizations l10n, MoneyCardData d) {
  final amount = d.amount.trim();
  return [
    l10n.shareEdgeMoneyWisely,
    l10n.shareEdgeMoneyFlex,
    if (d.bitcoin) l10n.shareEdgeMoneyBitcoin,
    l10n.shareEdgeMoneyNoStrings,
    l10n.shareEdgeMoneyMakeItText,
    l10n.shareEdgeMoneyLowBar,
    l10n.shareEdgeMoneyNoForms,
    l10n.shareEdgeMoneyActNatural,
    l10n.shareEdgeMoneyInAdvance,
    if (amount.isNotEmpty) l10n.shareEdgeMoneyNoQuestions(amount),
    l10n.shareEdgeMoneyNotALoan,
    l10n.shareEdgeMoneyAllAtOnce,
    l10n.shareEdgeMoneyGetUsed,
    l10n.shareEdgeMoneyLittleEgo,
    l10n.shareEdgeMoneyNoBank,
    if (d.bitcoin) ...[
      l10n.shareEdgeMoneyHandlePatience,
      l10n.shareEdgeMoneyStackResponsibly,
      l10n.shareEdgeMoneyNoLecture,
      l10n.shareEdgeMoneyTinySats,
    ] else ...[
      l10n.shareEdgeMoneySameDollars,
      l10n.shareEdgeMoneyNoEnvelope,
      l10n.shareEdgeMoneyNoExchange,
    ],
  ];
}

/// A prediction market's topic lines: neutral, so a pick and a market
/// shared whole both carry them.
List<String> _topicEdges(AppLocalizations l10n, ShareCardTopic topic) =>
    switch (topic) {
      ShareCardTopic.politics => [
          l10n.shareEdgePredictionPolitics,
          l10n.shareEdgeTopicDebates,
        ],
      ShareCardTopic.sports => [l10n.shareEdgeTopicCoach],
      ShareCardTopic.crypto => [l10n.shareEdgeTopicVolatility],
      ShareCardTopic.economy => [l10n.shareEdgeTopicMinutes],
      ShareCardTopic.other => const <String>[],
    };

/// A prediction PICKED and sent: the sender's own side. By the whole
/// percent the card shows: a FAVOURITE (half or more: "62% agree. Smart
/// crowd.", the market's leader "Backing the favourite."), an UNDERDOG
/// (under half and not the market's leader: "47% says I'm early, not
/// wrong.", "The crowd is 53% wrong.", everyone not on this side, from
/// the card's own percent), a leader under half (a crowded race) neither;
/// then the topic's lines.
List<String> _pickEdges(AppLocalizations l10n, PredictionCardData d) {
  final loc = l10n.localeName;
  final chance = d.chance?.clamp(0.0, 100.0);
  final shown = chance?.round();
  final c = chance == null ? null : shareCardChance(loc, chance);
  final side = shareCardOutcome(l10n, d.outcome);
  final sideFits = _nameFits(side);
  final amount = d.amount?.trim() ?? '';
  // A yes/no market's favourite is the side over half; a named market's
  // is its leader.
  final leads = d.binary ? (shown != null && shown >= 50) : d.leading;
  final favourite = shown != null && shown >= 50;
  final underdog = shown != null && shown < 50 && !leads;
  return [
    if (underdog) l10n.shareEdgePredictionEarly(c!),
    if (underdog)
      l10n.shareEdgePredictionCrowd(shareCardChance(loc, 100.0 - shown)),
    l10n.shareEdgePredictionDare,
    l10n.shareEdgePickScreenshot,
    l10n.shareEdgePickSaidFirst,
    if (sideFits) l10n.shareEdgePickFinalAnswer(side),
    l10n.shareEdgePickStrongOpinion,
    l10n.shareEdgePickDidReading,
    l10n.shareEdgePickToldYouSo,
    l10n.shareEdgePickConviction,
    if (amount.isNotEmpty) l10n.shareEdgePickNotFree,
    if (amount.isNotEmpty && sideFits)
      l10n.shareEdgePickAmountSays(amount, side),
    l10n.shareEdgePickLowDrama,
    l10n.shareEdgePickInsufferable,
    if (leads) ...[
      l10n.shareEdgePickRevolutionary,
      l10n.shareEdgePickWithOdds,
    ],
    if (favourite) ...[
      l10n.shareEdgePickSmartCrowd(c!),
      l10n.shareEdgePickSafePick,
    ],
    if (underdog) ...[
      l10n.shareEdgePickOnPurpose,
      l10n.shareEdgePickOnlySee(c!),
      l10n.shareEdgePickLongShot,
      l10n.shareEdgePickContrarian,
    ],
    ..._topicEdges(l10n, d.topic),
    if (d.topic == ShareCardTopic.sports && !d.binary && sideFits)
      l10n.shareEdgePredictionSports(side),
  ];
}

/// A WHOLE MARKET shared, no pick (founder, 5 November 2026: "this is a
/// general market share, it makes no sense to pick a side"): every line
/// NEUTRAL, about the question, never that the sharer is on a side or
/// that the crowd or the leader is wrong. A yes/no market ("62% say Yes.
/// Discuss."), a race of named outcomes with its chart ("Vance leads.
/// Nothing's settled.", "34% isn't a coronation."; the leader by the
/// chart's own short name, the chance the card shows), a match ("Odds
/// don't play the match."); then the topic's lines.
List<String> _marketEdges(AppLocalizations l10n, PredictionCardData d) {
  final loc = l10n.localeName;
  final chance = d.chance?.clamp(0.0, 100.0);
  final c = chance == null ? null : shareCardChance(loc, chance);
  final side = shareCardOutcome(l10n, d.outcome);
  final leader = polyChartShortName(d.outcome);
  final draw =
      const {'draw', 'tie', 'empate'}.contains(d.outcome.trim().toLowerCase());
  final leaderFits = !draw && _nameFits(leader);
  return [
    l10n.shareEdgeMarketPickOrWatch,
    l10n.shareEdgeMarketHasOdds,
    l10n.shareEdgeMarketUntilResolves,
    l10n.shareEdgeMarketGroupChat,
    l10n.shareEdgeMarketHotTakes,
    l10n.shareEdgeMarketJustMarket,
    l10n.shareEdgeMarketOddsMove,
    l10n.shareEdgeMarketYourCall,
    l10n.shareEdgeMarketDiscuss,
    l10n.shareEdgeMarketWhereLand,
    if (d.binary) ...[
      if (c != null) l10n.shareEdgeMarketSayDiscuss(c, side),
      l10n.shareEdgeMarketHarder,
      l10n.shareEdgeMarketTwoAnswers,
      if (c != null) l10n.shareEdgeMarketNotGuarantee(c),
      l10n.shareEdgeMarketFeelings,
      if (chance != null && chance.round() >= 50) l10n.shareEdgeMarketLikely,
    ] else if (d.topic == ShareCardTopic.sports) ...[
      if (leaderFits) l10n.shareEdgeMarketLeads(leader),
      l10n.shareEdgeMarketUpsets,
      l10n.shareEdgeMarketGameDecides,
      l10n.shareEdgeMarketOddsDontPlay,
      l10n.shareEdgeMarketScoreboard,
      l10n.shareEdgeMarketNotSureThing,
    ] else ...[
      if (leaderFits) l10n.shareEdgeMarketLeads(leader),
      if (c != null) l10n.shareEdgeMarketCoronation(c),
      if (leaderFits) l10n.shareEdgeMarketHistoryWait(leader),
      l10n.shareEdgeMarketAskTomorrow,
      l10n.shareEdgeMarketCrowdedField,
      if (leaderFits && c != null) l10n.shareEdgeMarketStayTuned(leader, c),
      l10n.shareEdgeMarketLeadingNotWinning,
      l10n.shareEdgeMarketNotSureThing,
    ],
    ..._topicEdges(l10n, d.topic),
  ];
}

/// An Investing card's lines by today's change: up ("Up 3.4%. You're
/// welcome.", a big day "Double digits. I'll allow it."), down ("Down
/// 3.4%. Zoom out."), flat ("Sideways is a direction."), unknown (lines
/// that claim no direction); a SHORT pick has its own ("Gravity is a
/// strategy too."), never the buying ones. Then the lines for any day.
List<String> _investmentEdges(AppLocalizations l10n, InvestmentCardData d) {
  final loc = l10n.localeName;
  final change = d.change;
  final known = change != null && change.isFinite;
  final flat = known && change.abs() < _kEdgeFlatChange;
  final up = known && change >= _kEdgeFlatChange;
  final down = known && change <= -_kEdgeFlatChange;
  final big = known && change.abs() >= _kEdgeBigChange;
  final ch = known && !flat ? shareCardChangeAbs(loc, change) : '';
  final name = d.title.trim();
  final nameFits = _nameFits(name);
  final any = [
    l10n.shareEdgeStockJustChart,
    l10n.shareEdgeStockFeelings,
    if (nameFits) l10n.shareEdgeStockHeardOfIt(name),
  ];
  if (d.side == 'short') {
    return [
      l10n.shareEdgeStockShortUnbothered,
      l10n.shareEdgeStockNotEverythingUp,
      l10n.shareEdgeStockGravity,
      l10n.shareEdgeStockShortHype,
      l10n.shareEdgeStockShortContrarian,
      l10n.shareEdgeStockFlipSide,
      if (down) ...[
        l10n.shareEdgeStockAsPlanned(ch),
        l10n.shareEdgeStockAsIntended,
        l10n.shareEdgeStockBadDay,
      ],
      if (up) ...[
        l10n.shareEdgeStockICanWait,
        l10n.shareEdgePatience,
        l10n.shareEdgeStockAsIntended,
      ],
      if (flat) ...[
        l10n.shareEdgePatience,
        l10n.shareEdgeStockSideways,
        l10n.shareEdgeStockRiveting,
      ],
      ...any,
    ];
  }
  if (up) {
    return [
      l10n.shareEdgeStockEarly,
      l10n.shareEdgeStockWelcome(ch),
      l10n.shareEdgeStockToldYou(d.title),
      l10n.shareEdgeStockActNormal,
      l10n.shareEdgeStockJustChange(ch),
      l10n.shareEdgeStockIKnew,
      l10n.shareEdgeStockTomorrow,
      if (nameFits) l10n.shareEdgeStockGreenLooks(name),
      l10n.shareEdgeStockEgoSteady,
      l10n.shareEdgeStockDontClap,
      if (big) ...[
        l10n.shareEdgeStockDoubleDigits,
        l10n.shareEdgeStockCheckShorts(ch),
      ],
      ...any,
    ];
  }
  if (down) {
    return [
      l10n.shareEdgeStockDiscount,
      l10n.shareEdgeStockPanic,
      l10n.shareEdgeStockCalmAsEver,
      l10n.shareEdgeStockZoomOut(ch),
      l10n.shareEdgeStockPanicOptional,
      l10n.shareEdgeStockCharacterArc(ch),
      l10n.shareEdgeStockPlotTwist,
      l10n.shareEdgeStockStillHere,
      l10n.shareEdgeStockAsIntended,
      l10n.shareEdgeStockBadDay,
      if (big) l10n.shareEdgeStockDeepBreaths(ch),
      ...any,
    ];
  }
  if (flat) {
    return [
      l10n.shareEdgeStockEarly,
      l10n.shareEdgePatience,
      l10n.shareEdgeStockRiveting,
      l10n.shareEdgeStockBoringUnderrated,
      l10n.shareEdgeStockSideways,
      l10n.shareEdgeStockSuspicious,
      l10n.shareEdgeStockNap,
      l10n.shareEdgeStockPaintDry,
      l10n.shareEdgeStockUnchanged,
      ...any,
    ];
  }
  // Today's change unknown: nothing that names a direction.
  return [l10n.shareEdgeStockEarly, l10n.shareEdgePatience, ...any];
}

/// The dares on a challenge card (see the file header), built from the
/// sender's side; on an underdog side (under half, not the market's
/// leader) also "The crowd is 53% wrong.", the other side's share from
/// the card's own percent.
List<String> challengeEdges(AppLocalizations l10n, PredictionCardData d) {
  final side = shareCardOutcome(l10n, d.outcome);
  final shown = d.chance?.clamp(0.0, 100.0).round();
  final leads = d.binary ? (shown != null && shown >= 50) : d.leading;
  final underdog = shown != null && shown < 50 && !leads;
  return [
    l10n.challengeEdgeWrong(side),
    l10n.challengeEdgeFight(side),
    l10n.challengeEdgeProve(side),
    l10n.challengeEdgeMove(side),
    l10n.challengeEdgeComeAtMe(side),
    l10n.challengeEdgeOnNotice(side),
    l10n.challengeEdgeTalkCheap(side),
    l10n.challengeEdgeScared(side),
    l10n.challengeEdgeKnowBetter(side),
    l10n.challengeEdgeTurnWrong(side),
    l10n.challengeEdgeNotSorry(side),
    l10n.challengeEdgeAllYours(side),
    l10n.challengeEdgeConvince(side),
    l10n.challengeEdgeSeeYou(side),
    l10n.challengeEdgeReceipts(side),
    if (underdog)
      l10n.shareEdgePredictionCrowd(
          shareCardChance(l10n.localeName, 100.0 - shown)),
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
      chance:
          theirs == null || other == '?' ? null : shareCardChance(loc, theirs),
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
  // A pick sent is a gift: the recipient's hero reads as money's, "Daniel,
  // a friend sent you" over the amount and the position.
  if (recipient) {
    return n.isEmpty
        ? l10n.claimCardFromFriend
        : l10n.claimCardFromFriendNamed(n);
  }
  // A prediction says it is one (founder, 5 November 2026: "more clear we
  // are sending the prediction"); an investment too (7 November 2026).
  if (data is PredictionCardData) {
    return n.isEmpty
        ? l10n.shareCardPredictionForYou
        : l10n.shareCardPredictionForNamed(n);
  }
  return n.isEmpty
      ? l10n.shareCardInvestmentForYou
      : l10n.shareCardInvestmentForNamed(n);
}

/// The draws a match names (never "to win").
const Set<String> _kDraws = {'draw', 'tie', 'empate'};

/// A gift's position (see the file header): the side word split out, so
/// the card draws it in its colour; null on anything but a pick sent (a
/// dare draws both sides instead).
ShareCardPosition? shareCardPosition(
    AppLocalizations l10n, ShareCardData data) {
  switch (data) {
    case final InvestmentCardData d when d.picked:
      final up = d.side != 'short';
      final side = up ? l10n.longLabel : l10n.shortLabel;
      // The language's own order, the side found by a mark in its place.
      const mark = '\u0001';
      final full = l10n.shareCardPositionInvest(mark, d.title.trim());
      final at = full.indexOf(mark);
      if (at < 0) return (before: '', side: side, after: ' ${d.title}', up: up);
      return (
        before: full.substring(0, at),
        side: side,
        after: full.substring(at + mark.length),
        up: up,
      );
    case final PredictionCardData d when d.picked && !d.challenge:
      final label = d.outcome.trim();
      final lower = label.toLowerCase();
      if (d.binary || lower == 'yes' || lower == 'no') {
        return (
          before: '',
          side: shareCardOutcome(l10n, label),
          after: '',
          up: lower != 'no',
        );
      }
      // A named outcome is sent on its Yes: "Yes · Lula to win".
      final race = d.topic == ShareCardTopic.politics ||
          d.topic == ShareCardTopic.sports;
      final subject = race && !_kDraws.contains(lower)
          ? l10n.shareCardOutcomeToWin(label)
          : label;
      return (
        before: '',
        side: l10n.shareCardOutcomeYes,
        after: ' · $subject',
        up: true,
      );
    default:
      return null;
  }
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
