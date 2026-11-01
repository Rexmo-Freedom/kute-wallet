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
//     link ([PredictionCardData.picked]) or without (sharing the market:
//     the leading outcome).
//   * [InvestmentCardData]: an Investing market (a stock, an index, a
//     commodity, a coin), with the side and amount sent on a link or
//     without (sharing the market).
//
// [ShareCardAudience.recipient] is the same card as the claim screen's
// hero (claim_screen.dart): "{Name}, a friend sent you".

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
    this.imageUrl,
    this.picked = false,
    this.amount,
    this.series,
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

  final String? imageUrl;

  /// Sent as a pick on a link (the pick pill, the amount, "Place it on
  /// Kute"); false: the market shared ("Make your call on Kute").
  final bool picked;

  /// What was put on the pick, formatted ("$10"); null: none.
  final String? amount;

  /// [outcome]'s chance over the last week, 0–1; null when not loaded.
  final List<double>? series;

  /// The Yes side's chance of a binary market, 0–100.
  double? get yesChance {
    final c = chance;
    if (c == null || !binary) return null;
    return outcome.trim().toLowerCase() == 'no' ? 100 - c : c;
  }

  @override
  String get kind => picked ? 'send_prediction' : 'prediction_market';
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
