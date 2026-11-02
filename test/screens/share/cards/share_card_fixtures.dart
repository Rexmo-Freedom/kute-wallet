// Fake share cards for the tests and the on-demand renders: every figure
// here is made up for the test (realistic, not live), none is computed.

import 'dart:ui' show Color;

import 'package:kute/screens/share/cards/share_card_data.dart';

const String kShareTestCode = 'JOAO42';

MoneyCardData fakeBitcoinCard({String? name = 'Daniel'}) => MoneyCardData(
      bitcoin: true,
      amount: '₿12,000',
      amountSub: r'$9.40',
      recipient: name,
      referralCode: kShareTestCode,
    );

MoneyCardData fakeDollarsCard({String? name = 'Ana'}) => MoneyCardData(
      bitcoin: false,
      amount: r'$10.00',
      recipient: name,
      referralCode: kShareTestCode,
    );

const List<double> _gengSeries = [
  0.39,
  0.41,
  0.40,
  0.42,
  0.44,
  0.43,
  0.45,
  0.44,
  0.46,
  0.45,
  0.47,
  0.47,
];

PredictionCardData fakePredictionPick(
        {String? name = 'Ana',
        String question = 'LoL Worlds 2026 Final: Gen.G vs T1'}) =>
    PredictionCardData(
      question: question,
      outcome: 'Gen.G',
      chance: 47,
      binary: false,
      topic: ShareCardTopic.sports,
      leading: true,
      opponent: 'T1',
      opponentChance: 53,
      picked: true,
      amount: r'$10',
      series: _gengSeries,
      recipient: name,
      referralCode: kShareTestCode,
    );

/// The market page's first two line colours (kPolyOutcomeColors).
const Color kShareTestSkyBlue = Color(0xFF4FC3F7);
const Color kShareTestPurple = Color(0xFFCE93D8);

/// A fixture's line: [values] spread evenly over the month to 2 November
/// 2026 (made up for the tests, as every figure here).
List<ShareCardChancePoint> fakeChanceLine(List<double> values) {
  const end = 1793577600000; // 2026-11-02 00:00 UTC
  const month = 30 * 24 * 3600 * 1000;
  return [
    for (var i = 0; i < values.length; i++)
      (t: end - month + (month * i / (values.length - 1)).round(), p: values[i]),
  ];
}

/// "Brazil presidential election 2026", shared as a market: Lula da Silva
/// ahead of Flávio Bolsonaro, the two lines the market page draws.
PredictionCardData fakePredictionMarket({bool chart = true}) =>
    PredictionCardData(
      question: 'Brazil presidential election 2026',
      outcome: 'Lula',
      chance: 41,
      binary: false,
      topic: ShareCardTopic.politics,
      leading: true,
      opponent: 'Flávio Bolsonaro',
      opponentChance: 35,
      series: const [
        0.36,
        0.37,
        0.36,
        0.38,
        0.39,
        0.38,
        0.40,
        0.39,
        0.41,
        0.40,
        0.41,
      ],
      lines: !chart
          ? null
          : [
              ShareCardOutcomeLine(
                name: 'Luiz Inácio Lula da Silva',
                chance: 41,
                color: kShareTestSkyBlue,
                points: fakeChanceLine(const [
                  0.330, 0.332, 0.335, 0.333, 0.340, 0.346, 0.344, 0.350,
                  0.356, 0.361, 0.358, 0.366, 0.372, 0.380, 0.377, 0.385,
                  0.392, 0.398, 0.402, 0.399, 0.405, 0.412, 0.408, 0.410,
                ]),
              ),
              ShareCardOutcomeLine(
                name: 'Flávio Bolsonaro',
                chance: 35,
                color: kShareTestPurple,
                points: fakeChanceLine(const [
                  0.392, 0.395, 0.401, 0.404, 0.398, 0.390, 0.384, 0.380,
                  0.376, 0.371, 0.368, 0.364, 0.360, 0.355, 0.357, 0.352,
                  0.349, 0.351, 0.347, 0.344, 0.348, 0.352, 0.350, 0.350,
                ]),
              ),
            ],
      referralCode: kShareTestCode,
    );

/// A 92-character market question, the longest the cards are checked at.
const String kShareLongQuestion = 'Will the Federal Reserve cut interest '
    'rates by 50 basis points at its December 2026 meeting?';

/// A binary pick on a long question ("Yes", 23%).
PredictionCardData fakeBinaryPick(
        {String question = 'Will Bitcoin hit \$150k by March 2026?'}) =>
    PredictionCardData(
      question: question,
      outcome: 'Yes',
      chance: 23,
      topic: ShareCardTopic.crypto,
      leading: false,
      picked: true,
      amount: r'$10',
      recipient: 'Ana',
      referralCode: kShareTestCode,
    );

/// "Michigan Senate Election Winner": the party market, Democratic ahead.
PredictionCardData fakeMichiganMarket({bool chart = true}) =>
    PredictionCardData(
      question: 'Michigan Senate Election Winner',
      outcome: 'Democratic',
      chance: 58,
      binary: false,
      topic: ShareCardTopic.politics,
      leading: true,
      opponent: 'Republican',
      opponentChance: 42,
      lines: !chart
          ? null
          : [
              ShareCardOutcomeLine(
                name: 'Democratic',
                chance: 58,
                color: kShareTestSkyBlue,
                points: fakeChanceLine(const [
                  0.612, 0.615, 0.608, 0.604, 0.598, 0.601, 0.594, 0.588,
                  0.583, 0.579, 0.572, 0.568, 0.574, 0.578, 0.583, 0.579,
                  0.576, 0.580,
                ]),
              ),
              ShareCardOutcomeLine(
                name: 'Republican',
                chance: 42,
                color: kShareTestPurple,
                points: fakeChanceLine(const [
                  0.388, 0.385, 0.392, 0.396, 0.402, 0.399, 0.406, 0.412,
                  0.417, 0.421, 0.428, 0.432, 0.426, 0.422, 0.417, 0.421,
                  0.424, 0.420,
                ]),
              ),
            ],
      referralCode: kShareTestCode,
    );

const List<double> _teslaSeries = [
  221.4,
  224.0,
  219.8,
  226.3,
  229.1,
  227.5,
  231.2,
  228.0,
  233.9,
  236.4,
  232.1,
  230.5,
  235.8,
  238.2,
  236.0,
  239.7,
  241.3,
  237.9,
  240.2,
  243.8,
  239.6,
  236.9,
  238.4,
  241.0,
  237.2,
  233.1,
  235.6,
  238.9,
  234.2,
  242.1,
];

InvestmentCardData fakeTeslaPick({String? name = 'Ana'}) => InvestmentCardData(
      title: 'Tesla',
      ticker: 'TSLA',
      coin: 'TSLA',
      wireCoin: 'xyz:TSLA',
      category: 'stocks',
      price: 242.1,
      change: 0.034,
      series: _teslaSeries,
      side: 'long',
      amount: r'$25',
      recipient: name,
      referralCode: kShareTestCode,
    );

InvestmentCardData fakeNasdaqMarket() => const InvestmentCardData(
      title: 'Nasdaq 100',
      ticker: 'XYZ100',
      coin: 'XYZ100',
      wireCoin: 'xyz:XYZ100',
      category: 'indices',
      price: 21483.5,
      change: -0.0062,
      series: [
        21950,
        21890,
        21920,
        21810,
        21760,
        21840,
        21700,
        21650,
        21720,
        21600,
        21680,
        21590,
        21520,
        21610,
        21560,
        21490,
        21530,
        21470,
        21550,
        21610,
        21580,
        21500,
        21440,
        21520,
        21470,
        21390,
        21450,
        21510,
        21460,
        21483.5,
      ],
      referralCode: kShareTestCode,
    );

InvestmentCardData fakeOilMarket() => const InvestmentCardData(
      title: 'Crude oil',
      ticker: 'CL',
      coin: 'CL',
      wireCoin: 'xyz:CL',
      category: 'commodities',
      price: 102.5,
      change: 0.012,
      referralCode: kShareTestCode,
    );

extension ShareCardRecipientCopy on ShareCardData {
  /// The same card as the recipient's claim hero.
  ShareCardData asRecipient() => switch (this) {
        final MoneyCardData d => MoneyCardData(
            bitcoin: d.bitcoin,
            amount: d.amount,
            amountSub: d.amountSub,
            recipient: d.recipient,
            audience: ShareCardAudience.recipient),
        final PredictionCardData d => PredictionCardData(
            question: d.question,
            outcome: d.outcome,
            chance: d.chance,
            binary: d.binary,
            topic: d.topic,
            opponent: d.opponent,
            opponentChance: d.opponentChance,
            outcomeImageUrl: d.outcomeImageUrl,
            opponentImageUrl: d.opponentImageUrl,
            imageUrl: d.imageUrl,
            picked: true,
            amount: d.amount,
            series: d.series,
            recipient: d.recipient,
            audience: ShareCardAudience.recipient),
        final InvestmentCardData d => InvestmentCardData(
            title: d.title,
            ticker: d.ticker,
            coin: d.coin,
            wireCoin: d.wireCoin,
            iconUrl: d.iconUrl,
            category: d.category,
            price: d.price,
            decimalCap: d.decimalCap,
            change: d.change,
            series: d.series,
            side: d.side,
            amount: d.amount,
            recipient: d.recipient,
            audience: ShareCardAudience.recipient),
      };
}
