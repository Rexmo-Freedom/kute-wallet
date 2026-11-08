// lib/screens/share/cards/share_card_data.dart
//
// WHAT A SHARE CARD SAYS (founder, 1 November 2026: "all shares, stocks,
// predictions and even sending bitcoin outside should have a card like
// the brag card"). Plain data, built by share_card_sources.dart from the
// providers the pages already read; a figure the providers do not have is
// null and the card leaves it out, never estimated.
//
//   * [MoneyCardData]: a send-to-anyone link with no pick (bitcoin or
//     dollars): "{Name}, I sent you" over the amount.
//   * [PredictionCardData]: a prediction market, with the pick sent on a
//     link ([PredictionCardData.picked]), as a dare when the sender
//     challenges the friend to take the other side
//     ([PredictionCardData.challenge]), or without (sharing the market:
//     the leading outcome, and on a market of named outcomes its chart,
//     [PredictionCardData.lines]: the market page's own lines, real
//     history).
//   * [InvestmentCardData]: an Investing market (a stock, an index, a
//     commodity, a coin), with the side and amount sent on a link or
//     without (sharing the market).
//   * [InviteCardData]: the Referral program's invite: the discount and
//     the sharer's code.
//   * [GoalCardData]: the Bitcoin home's level (goal_share.dart): the level
//     and its name, Sal's still for it, and no money at all.
//   * [ReceiptCardData]: a transaction's receipt (founder, 5 November
//     2026): what was sent, received, moved or bought, a prediction
//     placed, sold or lost, an Investing trade opened or closed
//     ([ReceiptCardKind]); built by the receipt itself (receipt_share.dart).
//
// [ShareCardAudience.recipient] is the same card as the claim screen's
// hero (claim_screen.dart): "{Name}, a friend sent you".

import 'dart:ui' show Color;

/// Who reads the card: the sharer's image, or the recipient's claim hero.
enum ShareCardAudience { sender, recipient }

/// A prediction market's topic, for the headline's template.
enum ShareCardTopic { politics, sports, crypto, economy, other }

sealed class ShareCardData {
  const ShareCardData({
    this.referralCode,
    this.recipient,
    this.audience = ShareCardAudience.sender,
  });

  /// The sharer's referral code (the footer chip); null without one.
  final String? referralCode;

  /// The recipient's first name, as typed on the link; null: unnamed.
  final String? recipient;

  final ShareCardAudience audience;

  /// The analytics `kind` and the PNG's name.
  String get kind;
}

/// The level on the Bitcoin home's Goals (founder, 8 November 2026: "we
/// should be able to share the goals"; goal_share.dart): what a level is
/// called and Sal's own still for it. NO MONEY, and nothing to work it out
/// from beyond the level itself: no balance, threshold, goal, percent or
/// currency, so the fields are only these. A share image shows a level, not
/// what someone holds.
class GoalCardData extends ShareCardData {
  const GoalCardData({
    required this.level,
    required this.name,
    required this.still,
    super.referralCode,
  });

  /// The level's number (past the twelfth name it keeps counting).
  final int level;

  /// The level's name, in the app's language ("Stacker").
  final String name;

  /// Sal's still for the level ([ShareCardFrame.still]).
  final String still;

  @override
  String get kind => 'goal';
}

/// A link sending money with no pick.
class MoneyCardData extends ShareCardData {
  const MoneyCardData({
    required this.bitcoin,
    required this.amount,
    this.amountSub,
    super.referralCode,
    super.recipient,
    super.audience,
  });

  /// Bitcoin (the orange card) or dollars (the green one).
  final bool bitcoin;

  /// The big figure: "₿12,000" or "$10.00".
  final String amount;

  /// The figure under it: the bitcoin's value in the person's currency
  /// ("$9.40"); null for dollars.
  final String? amountSub;

  @override
  String get kind => bitcoin ? 'send_bitcoin' : 'send_dollars';
}

/// The invite to Kute (founder, 8 November 2026: "share invite should have
/// a Sal on the share, like a card"): the discount a friend gets, over the
/// sharer's code in the footer. Never the sharer's rate or earnings.
class InviteCardData extends ShareCardData {
  const InviteCardData({this.discount, super.referralCode});

  /// What a friend gets off Kute fees ("20%"), from the backend's rules;
  /// null: the card invites without a figure.
  final String? discount;

  @override
  String get kind => 'invite';
}

/// One point of a market's line: its time (ms since the epoch) and the
/// outcome's chance then, 0–1.
typedef ShareCardChancePoint = ({int t, double p});

/// One outcome's line on a market card's chart (founder, 2 November 2026:
/// "on the entire market both graphs also … make the graphs clear", and
/// "the graph should actually be the graph from the market"): the line the
/// market page's chart draws for it, its real price history over the
/// range the page opens on, in the page's colour for it.
class ShareCardOutcomeLine {
  const ShareCardOutcomeLine({
    required this.name,
    required this.chance,
    required this.color,
    required this.points,
    this.draw = false,
  });

  /// The outcome's name as the market writes it (the card shortens it as
  /// the chart's tags do); '' for a match's draw ([draw]).
  final String name;

  /// Its chance now, 0–100: the line's end and its label.
  final double chance;

  /// The market page's colour for its line.
  final Color color;

  /// Its history, oldest first, the last point at [chance].
  final List<ShareCardChancePoint> points;

  /// A three-way match's draw (labelled in the card's language).
  final bool draw;
}

/// A prediction market (see the file header).
class PredictionCardData extends ShareCardData {
  const PredictionCardData({
    required this.question,
    required this.outcome,
    this.chance,
    this.binary = true,
    this.topic = ShareCardTopic.other,
    this.leading = true,
    this.opponent,
    this.opponentChance,
    this.outcomeImageUrl,
    this.opponentImageUrl,
    this.imageUrl,
    this.picked = false,
    this.challenge = false,
    this.amount,
    this.series,
    this.lines,
    super.referralCode,
    super.recipient,
    super.audience,
  });

  /// The market's question (the event title).
  final String question;

  /// The outcome the card is about: the pick sent, else the leading one.
  /// "Yes" / "No" on a binary market, else the candidate's name.
  final String outcome;

  /// [outcome]'s chance now, 0–100; null when not loaded.
  final double? chance;

  /// A yes/no market.
  final bool binary;

  final ShareCardTopic topic;

  /// Whether [outcome] is the market's favourite.
  final bool leading;

  /// The strongest other outcome (not a draw) on a multi-outcome market:
  /// "vs T1".
  final String? opponent;

  /// [opponent]'s own chance now, 0–100; null when unknown (a binary
  /// market's other side is 100 − [chance], see [otherChance]).
  final double? opponentChance;

  /// [outcome]'s and [opponent]'s own pictures (a team's crest, a
  /// candidate's portrait), for the odds bar's ends; null: none.
  final String? outcomeImageUrl;
  final String? opponentImageUrl;

  final String? imageUrl;

  /// Sent as a pick on a link (the pick pill, the amount, "Place it on
  /// Kute"); false: the market shared ("Make your call on Kute").
  final bool picked;

  /// A pick sent as a DARE (founder, 4 November 2026): the card shows both
  /// sides, [outcome] marked as the sender's, and dares the friend to take
  /// the other one ([otherChance], [opponent]). Only with [picked].
  final bool challenge;

  /// What was put on the pick, formatted ("$10"); null: none.
  final String? amount;

  /// [outcome]'s chance over the last week, 0–1; null when not loaded.
  final List<double>? series;

  /// The market's chart, most likely first, on a market of named outcomes
  /// shared without a pick: its top outcomes' real histories; null when
  /// not loaded (the card then shows the speedometer).
  final List<ShareCardOutcomeLine>? lines;

  /// The card draws the market's chart ([lines]) rather than the
  /// speedometer: the market shared, at least two lines read.
  bool get charted => !picked && (lines?.length ?? 0) >= 2;

  /// The other side's chance, 0–100: 100 − [chance] on a binary market,
  /// [opponentChance] on a named one; null when unknown.
  double? get otherChance {
    final c = chance;
    if (c == null) return null;
    return binary ? 100 - c.clamp(0, 100) : opponentChance;
  }

  /// The Yes side's chance of a binary market, 0–100.
  double? get yesChance {
    final c = chance;
    if (c == null || !binary) return null;
    return outcome.trim().toLowerCase() == 'no' ? 100 - c : c;
  }

  @override
  String get kind => picked
      ? (challenge ? 'send_challenge' : 'send_prediction')
      : 'prediction_market';
}

/// An Investing market (see the file header).
class InvestmentCardData extends ShareCardData {
  const InvestmentCardData({
    required this.title,
    this.ticker,
    this.coin,
    this.wireCoin,
    this.iconUrl,
    this.category = 'other',
    this.price,
    this.decimalCap,
    this.change,
    this.series,
    this.side,
    this.amount,
    super.referralCode,
    super.recipient,
    super.audience,
  });

  /// The market's display name ("Tesla", "Nasdaq 100", "Crude oil").
  final String title;

  /// The ticker under it ("TSLA"); null when it is the name.
  final String? ticker;

  /// The logo's sources (HlCoinIcon).
  final String? coin;
  final String? wireCoin;
  final String? iconUrl;

  /// `crypto|stocks|commodities|fx|indices|preipo|other`.
  final String category;

  /// The live price; null when not loaded.
  final double? price;
  final int? decimalCap;

  /// Today's change as a fraction (0.034 == +3.4%); null when unknown.
  final double? change;

  /// The last 30 daily closes; null when not loaded.
  final List<double>? series;

  /// `long` | `short` when sent as a pick on a link; null: shared.
  final String? side;

  /// What was put on it, formatted ("$10"); null: none.
  final String? amount;

  bool get picked => side != null;

  @override
  String get kind => picked ? 'send_investment' : 'investment_market';
}

/// What a transaction's receipt shares (founder, 5 November 2026: "All
/// these transactions, next to View on the blockchain, should have the
/// share and a special share card"). One card per kind of receipt, drawn
/// in the family's frame (receipt_card.dart):
enum ReceiptCardKind {
  /// Money out to someone: "SENT".
  sent,

  /// Money in: "RECEIVED".
  received,

  /// Money in that has not landed yet: "ON ITS WAY".
  incoming,

  /// Between the person's own accounts: "MOVED", "Dollars → Bitcoin".
  moved,

  /// A purchase: "BOUGHT · BITCOIN".
  bought,

  /// A sale of bitcoin: "SOLD · BITCOIN".
  sold,

  /// A prediction placed: "I'M ON YES", the speedometer at the entry.
  predicted,

  /// A prediction sold: "CASHED OUT", the result huge.
  cashedOut,

  /// A prediction lost: "NOT THIS TIME", dry, never sad.
  lost,

  /// A payout with no won card (no cost to measure it from): "PAID OUT".
  paidOut,

  /// An Investing trade opened (or a token bought): side, ticker, entry,
  /// size.
  opened,

  /// An Investing trade closed (or a token sold): the result huge.
  closed,
}

/// The money a receipt's card is about: its colour.
enum ReceiptCardAsset { bitcoin, dollars, predictions, investing }

/// A receipt's card (see [ReceiptCardKind]). Every figure is formatted by
/// the receipt that built it, as its own hero and tiles show it; what the
/// receipt does not have is null and the card leaves it out. Never an
/// address, a transaction id or any other identifier.
class ReceiptCardData extends ShareCardData {
  const ReceiptCardData({
    required this.type,
    required this.asset,
    this.amount,
    this.bitcoin,
    this.from,
    this.to,
    this.what,
    this.title,
    this.ticker,
    this.side,
    this.imageUrl,
    this.coin,
    this.wireCoin,
    this.iconUrl,
    this.category,
    this.chance,
    this.result,
    this.pnl,
    this.price,
    this.size,
    this.spot = false,
    this.link,
    super.referralCode,
  });

  final ReceiptCardKind type;
  final ReceiptCardAsset asset;

  /// The money figure: what was sent, received, moved or paid ("$9.40",
  /// the bitcoin's value in the person's currency), a prediction's
  /// stake, a sale's proceeds or a payout, a trade's size in money.
  final String? amount;

  /// The bitcoin that moved ("₿12,000"): under the money as "in bitcoin",
  /// or the figure itself without the money.
  final String? bitcoin;

  /// A move's two accounts ("Dollars", "Bitcoin").
  final String? from;
  final String? to;

  /// What was bought or sold ("Bitcoin").
  final String? what;

  /// The market: a prediction's question, an Investing market's name.
  final String? title;

  /// An Investing market's ticker ("TSLA"), when it is not the name.
  final String? ticker;

  /// The side: a prediction's outcome ("Yes", "Gen.G"); an Investing
  /// trade's `long` | `short`.
  final String? side;

  /// The logo's sources: a prediction's picture; an Investing market's
  /// coin (HlCoinIcon).
  final String? imageUrl;
  final String? coin;
  final String? wireCoin;
  final String? iconUrl;
  final String? category;

  /// A prediction's chance when placed (the price paid), 0–1.
  final double? chance;

  /// The result, signed and formatted ("+$4.20", "−$10.00"): the big
  /// number of a sale, a loss, a payout, a closed trade.
  final String? result;

  /// [result] in dollars: the card's colour and Sal's mood.
  final double? pnl;

  /// An Investing trade's price ("$242.10"): the entry, or the exit.
  final String? price;

  /// An Investing trade's size in its units ("2.5 TSLA").
  final String? size;

  /// A token bought or sold (spot), not a position opened or closed.
  final bool spot;

  /// The market's link for the share message; null: the app's invite.
  final String? link;

  /// A prediction card, the market's picture and question at its top.
  bool get prediction => switch (type) {
        ReceiptCardKind.predicted ||
        ReceiptCardKind.cashedOut ||
        ReceiptCardKind.lost ||
        ReceiptCardKind.paidOut =>
          true,
        _ => false,
      };

  /// An Investing trade's card.
  bool get trade =>
      type == ReceiptCardKind.opened || type == ReceiptCardKind.closed;

  @override
  String get kind => 'receipt_${switch (type) {
        ReceiptCardKind.cashedOut => 'cashed_out',
        ReceiptCardKind.paidOut => 'paid_out',
        _ => type.name,
      }}';
}
