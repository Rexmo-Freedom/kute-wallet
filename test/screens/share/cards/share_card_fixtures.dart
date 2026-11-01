// Fake share cards for the tests and the on-demand renders: every figure
// here is made up for the test (realistic, not live), none is computed.

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
  0.39, 0.41, 0.40, 0.42, 0.44, 0.43, 0.45, 0.44, 0.46, 0.45, 0.47, 0.47,
];

PredictionCardData fakePredictionPick({String? name = 'Ana'}) =>
    PredictionCardData(
      question: 'LoL Worlds 2026 Final: Gen.G vs T1',
      outcome: 'Gen.G',
      chance: 47,
      binary: false,
      topic: ShareCardTopic.sports,
      leading: true,
      opponent: 'T1',
      picked: true,
      amount: r'$10',
      series: _gengSeries,
      recipient: name,
      referralCode: kShareTestCode,
    );

PredictionCardData fakePredictionMarket() => const PredictionCardData(
      question: 'Brazil presidential election 2026',
      outcome: 'Lula',
      chance: 41,
      binary: false,
      topic: ShareCardTopic.politics,
      leading: true,
      series: [
        0.36, 0.37, 0.36, 0.38, 0.39, 0.38, 0.40, 0.39, 0.41, 0.40, 0.41,
      ],
      referralCode: kShareTestCode,
    );

const List<double> _teslaSeries = [
  221.4, 224.0, 219.8, 226.3, 229.1, 227.5, 231.2, 228.0, 233.9, 236.4,
  232.1, 230.5, 235.8, 238.2, 236.0, 239.7, 241.3, 237.9, 240.2, 243.8,
  239.6, 236.9, 238.4, 241.0, 237.2, 233.1, 235.6, 238.9, 234.2, 242.1,
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
        21950, 21890, 21920, 21810, 21760, 21840, 21700, 21650, 21720, 21600,
        21680, 21590, 21520, 21610, 21560, 21490, 21530, 21470, 21550, 21610,
        21580, 21500, 21440, 21520, 21470, 21390, 21450, 21510, 21460, 21483.5,
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
