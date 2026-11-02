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
      chance: 0.58,
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

/// A short in profit (an Investing position, +3.4%): a win.
BragPosition fakeBragWinningShort() => const BragPosition(
      title: 'ANTH',
      link: 'https://backend.kutewallet.com/m/investing/ANTH',
      referralCode: kBragTestCode,
      investing: true,
      side: 'Short',
      result: BragResult(usd: 7.77, text: r'+$7.77', percent: 3.4),
      coin: 'ANTH',
      entryText: '231.40',
      nowText: '223.53',
    );

/// A big win: the open positions' combined return is over 10%.
BragPortfolio fakeBragPortfolio(
        {String? code = kBragTestCode,
        String? gengImage,
        String? fedImage,
        List<double>? series}) =>
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
      returnPercent: 24.6,
      top: [
        const BragTopPosition(
            title: 'BTC',
            investing: true,
            coin: 'BTC',
            result: BragResult(usd: 92.1, text: r'+$92.10', percent: 18.4)),
        BragTopPosition(
            title: 'LoL Worlds 2026: Gen.G vs T1',
            side: 'Gen.G',
            imageUrl: gengImage,
            result:
                const BragResult(usd: 36.9, text: r'+$36.90', percent: 42.1)),
        BragTopPosition(
            title: 'Fed cuts rates in December?',
            side: 'Yes',
            imageUrl: fedImage,
            result: const BragResult(usd: 8.2, text: r'+$8.20', percent: 12.5)),
      ],
      series: series,
    );

/// The all-time P&L line of [fakeBragPortfolio] (made up, realistic):
/// a dip, then the climb to +$412.35.
const List<double> kFakeBragPortfolioSeries = [
  0,
  12.4,
  8.1,
  25.6,
  31.0,
  18.7,
  9.3,
  -14.2,
  -6.8,
  22.5,
  48.9,
  61.2,
  55.0,
  83.4,
  120.7,
  104.3,
  142.8,
  171.5,
  160.2,
  198.6,
  236.1,
  219.4,
  254.0,
  290.8,
  276.3,
  318.5,
  352.9,
  340.1,
  381.6,
  412.35,
];

/// A small win: +$7.57 on a 1.2% combined return.
BragPortfolio fakeBragSmallWinPortfolio() => const BragPortfolio(
      title: 'My portfolio',
      link: 'https://backend.kutewallet.com/m/investing',
      referralCode: kBragTestCode,
      slices: [
        BragSlice(part: BragSlicePart.investing, share: 0.30),
        BragSlice(part: BragSlicePart.predictions, share: 0.10),
        BragSlice(part: BragSlicePart.dollars, share: 0.60),
      ],
      allTime: BragResult(usd: 7.57, text: r'+$7.57'),
      returnPercent: 1.2,
      top: [
        BragTopPosition(
            title: 'ETH',
            investing: true,
            coin: 'ETH',
            result: BragResult(usd: 5.1, text: r'+$5.10', percent: 1.9)),
        BragTopPosition(
            title: 'Fed cuts rates in December?',
            side: 'Yes',
            result: BragResult(usd: 2.47, text: r'+$2.47', percent: 0.8)),
      ],
    );

/// A loss.
BragPortfolio fakeBragLosingPortfolio() => const BragPortfolio(
      title: 'My portfolio',
      link: 'https://backend.kutewallet.com/m/investing',
      referralCode: kBragTestCode,
      slices: [
        BragSlice(part: BragSlicePart.investing, share: 0.70),
        BragSlice(part: BragSlicePart.dollars, share: 0.30),
      ],
      allTime: BragResult(usd: -23.4, text: '−\$23.40'),
      returnPercent: -8.1,
      top: [
        BragTopPosition(
            title: 'SOL',
            investing: true,
            coin: 'SOL',
            result: BragResult(usd: 3.2, text: r'+$3.20', percent: 2.4)),
        BragTopPosition(
            title: 'ETH',
            investing: true,
            coin: 'ETH',
            result: BragResult(usd: -26.6, text: '−\$26.60', percent: -11.3)),
      ],
    );

/// Flat: nothing made, nothing lost.
BragPortfolio fakeBragFlatPortfolio() => const BragPortfolio(
      title: 'My portfolio',
      link: 'https://backend.kutewallet.com/m/investing',
      referralCode: kBragTestCode,
      slices: [
        BragSlice(part: BragSlicePart.predictions, share: 0.20),
        BragSlice(part: BragSlicePart.dollars, share: 0.80),
      ],
      allTime: BragResult(usd: 0, text: r'$0.00'),
      top: [
        BragTopPosition(
            title: 'Will it rain in London tomorrow?',
            side: 'No',
            result: BragResult(usd: 0, text: r'$0.00', percent: 0)),
      ],
    );
