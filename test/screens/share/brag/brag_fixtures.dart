// Fake brag cards for the tests and the on-demand renders: every figure
// here is made up for the test, none is computed.

import 'package:kute/screens/share/brag/brag_data.dart';

const String kBragTestCode = 'JOAO42';

BragPosition fakeBragPosition({String? code = kBragTestCode}) => BragPosition(
      title: 'LoL Worlds 2026: Gen.G vs T1',
      link: 'https://backend.kutewallet.com/m/predictions/lol-worlds-geng-t1',
      referralCode: code,
      investing: false,
      side: 'Gen.G',
      result: const BragResult(usd: 36.9, text: r'+$36.90', percent: 42.1),
      entryText: '41%',
      nowText: '58%',
      series: const [
        0.41,
        0.40,
        0.43,
        0.42,
        0.45,
        0.47,
        0.46,
        0.50,
        0.49,
        0.53,
        0.55,
        0.54,
        0.58,
      ],
      entryValue: 0.41,
    );

BragPosition fakeBragLosingPosition() => const BragPosition(
      title: 'ETH',
      link: 'https://backend.kutewallet.com/m/investing/ETH',
      referralCode: kBragTestCode,
      investing: true,
      side: 'Long',
      result: BragResult(usd: -12.4, text: '−\$12.40', percent: -6.2),
      coin: 'ETH',
      entryText: '3,812.40',
      nowText: '3,576.10',
    );

BragPortfolio fakeBragPortfolio({String? code = kBragTestCode}) =>
    BragPortfolio(
      title: 'My portfolio',
      link: 'https://backend.kutewallet.com/m/investing',
      referralCode: code,
      slices: const [
        BragSlice(part: BragSlicePart.investing, share: 0.58),
        BragSlice(part: BragSlicePart.predictions, share: 0.27),
        BragSlice(part: BragSlicePart.dollars, share: 0.15),
      ],
      allTime: const BragResult(usd: 412.35, text: r'+$412.35'),
      month: const BragResult(usd: 86.1, text: r'+$86.10'),
      top: const [
        BragTopPosition(
            title: 'BTC',
            result: BragResult(usd: 92.1, text: r'+$92.10', percent: 18.4)),
        BragTopPosition(
            title: 'LoL Worlds 2026: Gen.G vs T1',
            side: 'Gen.G',
            result: BragResult(usd: 36.9, text: r'+$36.90', percent: 42.1)),
        BragTopPosition(
            title: 'Fed cuts rates in December?',
            side: 'Yes',
            result: BragResult(usd: 8.2, text: r'+$8.20', percent: 12.5)),
      ],
    );
