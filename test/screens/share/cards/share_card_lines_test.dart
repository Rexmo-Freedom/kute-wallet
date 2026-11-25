// EVERY EDGY LINE, against representative cards (founder, 5 November
// 2026: "add many more variations of these texts"; "this is a general
// market share, it makes no sense to pick a side"): every pool of every
// card kind in each state (a send and its claim hero, a pick on the
// favourite, on the underdog and on a race's leader under half, a whole
// yes/no market, a race of named outcomes, a match, a dare, a stock up,
// down, flat, unknown and short, a brag win big, small and middling, a
// loss, flat, a won prediction, the P&L, every receipt), in all 23
// languages:
//
//   * each main state's pool holds 12 to 21 lines, the receipts' 10 or
//     more, a loading state (no change, no result) its few; never a line
//     twice;
//   * every figure in a line is one the card shows; the one figure
//     derived is the crowd's share on the other side of a pick (100% less
//     the card's percent, founder: "it's not wrong");
//   * a whole market's lines take no side: none of a pick's lines but the
//     topic's neutral ones;
//   * every line whole on its two lines at the card's width and type;
//   * no placeholder left, and the English never says "bet".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/balance_history.dart' show BalanceRange;
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/share/brag/brag_lines.dart';
import 'package:kute/screens/share/cards/share_card_copy.dart';
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';

import '../brag/brag_fixtures.dart';
import 'share_card_fixtures.dart';
import 'share_card_test_fonts.dart';

/// One card in one state: [data] a ShareCardData or a BragData; [min] the
/// fewest lines its pool may hold; [market] a whole market shared (every
/// line neutral).
class _Case {
  const _Case(this.name, this.data, {this.min = 12, this.market = false});

  final String name;
  final Object data;
  final int min;
  final bool market;
}

const _race = 'Republican Presidential Nominee 2028';
const _match = 'LoL Worlds 2026 Final: Gen.G vs T1';
const _btc = r'Will Bitcoin hit $150k by March 2026?';

ShareCardOutcomeLine _line(String name, double chance, int i) =>
    ShareCardOutcomeLine(
      name: name,
      chance: chance,
      color: i == 0 ? kShareTestSkyBlue : kShareTestPurple,
      points: fakeChanceLine([chance / 100 - 0.03, chance / 100]),
    );

final List<_Case> _cases = [
  // Money.
  _Case('bitcoin send', fakeBitcoinCard()),
  _Case('dollars send', fakeDollarsCard()),
  _Case('bitcoin claim hero', fakeBitcoinCard().asRecipient()),
  _Case('dollars claim hero', fakeDollarsCard().asRecipient()),
  // A pick.
  const _Case(
      'pick: Yes, the favourite',
      PredictionCardData(
          question: _btc,
          outcome: 'Yes',
          chance: 62,
          topic: ShareCardTopic.crypto,
          picked: true,
          amount: r'$10')),
  _Case('pick: Yes, the underdog', fakeBinaryPick()),
  const _Case(
      'pick: No, the favourite, economics',
      PredictionCardData(
          question: kShareLongQuestion,
          outcome: 'No',
          chance: 71,
          topic: ShareCardTopic.economy,
          picked: true,
          amount: r'$25')),
  const _Case(
      'pick: Yes, no topic',
      PredictionCardData(
          question: 'Will it snow in London on Christmas Day?',
          outcome: 'Yes',
          chance: 18,
          leading: false,
          picked: true,
          amount: r'$5')),
  const _Case(
      'pick: a match underdog',
      PredictionCardData(
          question: _match,
          outcome: 'Gen.G',
          chance: 47,
          binary: false,
          topic: ShareCardTopic.sports,
          leading: false,
          opponent: 'T1',
          opponentChance: 53,
          picked: true,
          amount: r'$10')),
  const _Case(
      'pick: a match favourite',
      PredictionCardData(
          question: _match,
          outcome: 'T1',
          chance: 53,
          binary: false,
          topic: ShareCardTopic.sports,
          opponent: 'Gen.G',
          opponentChance: 47,
          picked: true,
          amount: r'$10')),
  const _Case(
      "pick: a race's leader under half",
      PredictionCardData(
          question: _race,
          outcome: 'J.D. Vance',
          chance: 34,
          binary: false,
          topic: ShareCardTopic.politics,
          opponent: 'Marco Rubio',
          opponentChance: 21,
          picked: true,
          amount: r'$10')),
  const _Case(
      'pick: a long name',
      PredictionCardData(
          question: 'Brazil presidential election 2026',
          outcome: 'Luiz Inácio Lula da Silva',
          chance: 41,
          binary: false,
          topic: ShareCardTopic.politics,
          opponent: 'Flávio Bolsonaro',
          opponentChance: 35,
          picked: true,
          amount: r'$10')),
  // A whole market, no pick.
  const _Case(
      'market: yes/no, Yes leads',
      PredictionCardData(
          question: _btc,
          outcome: 'Yes',
          chance: 62,
          topic: ShareCardTopic.crypto),
      market: true),
  const _Case(
      'market: yes/no, No leads',
      PredictionCardData(
          question: 'Will it snow in London on Christmas Day?',
          outcome: 'No',
          chance: 82),
      market: true),
  _Case(
      'market: the race, charted',
      PredictionCardData(
          question: _race,
          outcome: 'J.D. Vance',
          chance: 34,
          binary: false,
          topic: ShareCardTopic.politics,
          opponent: 'Marco Rubio',
          opponentChance: 21,
          lines: [
            _line('J.D. Vance', 34, 0),
            _line('Marco Rubio', 21, 1),
            _line('Ron DeSantis', 13, 1),
          ]),
      market: true),
  const _Case(
      'market: a race, a long leader name, not charted',
      PredictionCardData(
          question: 'Brazil presidential election 2026',
          outcome: 'Luiz Inácio Lula da Silva',
          chance: 41,
          binary: false,
          topic: ShareCardTopic.politics,
          opponent: 'Flávio Bolsonaro',
          opponentChance: 35),
      market: true),
  _Case('market: Brazil', fakePredictionMarket(), market: true),
  _Case('market: Michigan', fakeMichiganMarket(), market: true),
  _Case(
      'market: a match',
      PredictionCardData(
          question: _match,
          outcome: 'T1',
          chance: 53,
          binary: false,
          topic: ShareCardTopic.sports,
          opponent: 'Gen.G',
          opponentChance: 47,
          lines: [_line('T1', 53, 0), _line('Gen.G', 47, 1)]),
      market: true),
  // A dare.
  _Case('dare: Yes, the favourite', fakeChallenge()),
  _Case('dare: Yes, the underdog', fakeChallenge(chance: 38)),
  _Case('dare: a match underdog', fakeChallengeNamed()),
  // Investing.
  _Case('stock up, a long pick', fakeTeslaPick()),
  const _Case(
      'stock up 12%',
      InvestmentCardData(
          title: 'Nvidia', ticker: 'NVDA', price: 181.2, change: 0.124)),
  _Case('index down', fakeNasdaqMarket()),
  const _Case(
      'stock down 14%',
      InvestmentCardData(
          title: 'Coinbase', ticker: 'COIN', price: 212.4, change: -0.142)),
  const _Case(
      'stock flat',
      InvestmentCardData(
          title: 'Apple', ticker: 'AAPL', price: 228.5, change: 0.0002)),
  const _Case('no change known',
      InvestmentCardData(title: 'Crude oil', price: 102.5),
      min: 5),
  const _Case(
      'a short pick, up',
      InvestmentCardData(
          title: 'Tesla',
          ticker: 'TSLA',
          price: 242.1,
          change: 0.034,
          side: 'short',
          amount: r'$25')),
  const _Case(
      'a short pick, down',
      InvestmentCardData(
          title: 'Tesla',
          ticker: 'TSLA',
          price: 242.1,
          change: -0.034,
          side: 'short',
          amount: r'$25')),
  const _Case(
      'a short pick, flat',
      InvestmentCardData(
          title: 'Tesla',
          ticker: 'TSLA',
          price: 242.1,
          change: 0.0001,
          side: 'short',
          amount: r'$25')),
  // Brag.
  _Case('brag: a big win', fakeBragPosition()),
  const _Case(
      'brag: a win',
      BragPosition(
          title: 'Tesla',
          link: 'https://x.test',
          investing: true,
          side: 'Long',
          result: BragResult(usd: 12.4, text: r'+$12.40', percent: 5.1),
          entryText: r'$230.40',
          nowText: r'$242.10')),
  _Case('brag: a small win', fakeBragSmallWinPortfolio()),
  _Case('brag: a winning short', fakeBragWinningShort()),
  _Case('brag: a big win, portfolio', fakeBragPortfolio()),
  _Case('brag: a loss, portfolio', fakeBragLosingPortfolio()),
  _Case('brag: a loss, position', fakeBragLosingPosition()),
  _Case('brag: flat', fakeBragFlatPortfolio()),
  const _Case(
      'brag: no result yet',
      BragPortfolio(title: 'My portfolio', link: 'https://x.test'),
      min: 4),
  _Case('won: bought as the underdog', fakeBragWin()),
  const _Case(
      'won: bought as the favourite',
      BragWin(
          title: 'Fed cuts rates in December?',
          link: 'https://x.test',
          side: 'Yes',
          result: BragResult(usd: 4.1, text: r'+$4.10', percent: 25),
          paidText: r'$16.40',
          payoutText: r'$20.50',
          entryValue: 0.8,
          entryText: '80¢')),
  const _Case(
      'P&L up',
      BragPnl(
          title: 'My profits',
          link: 'https://x.test',
          range: BalanceRange.month,
          allTime: BragResult(usd: 128.4, text: r'+$128.40'))),
  const _Case(
      'P&L down',
      BragPnl(
          title: 'My profits',
          link: 'https://x.test',
          range: BalanceRange.week,
          allTime: BragResult(usd: -41.2, text: '−\$41.20'))),
  // Receipts.
  for (final MapEntry(key: name, value: data) in receiptCards.entries)
    _Case('receipt: $name', data, min: 10),
  const _Case(
      'receipt: cashed out, result unknown',
      ReceiptCardData(
          type: ReceiptCardKind.cashedOut,
          asset: ReceiptCardAsset.predictions,
          amount: r'$14.20',
          title: kShareReceiptMarket,
          side: 'No'),
      min: 6),
];

List<String> _pool(AppLocalizations l10n, Object data) => switch (data) {
      final ShareCardData d => shareCardEdges(l10n, d),
      final BragData d => bragEdges(l10n, d),
      _ => throw ArgumentError(data),
    };

/// What [data]'s card writes that may hold a figure, as the card writes it
/// (share_cards.dart, receipt_card.dart, brag_card.dart).
List<String> _figures(AppLocalizations l10n, Object data) {
  final loc = l10n.localeName;
  String pct(double c) => shareCardChance(loc, c);
  switch (data) {
    case final MoneyCardData d:
      return [d.amount, if (d.amountSub != null) d.amountSub!];
    case final PredictionCardData d when d.challenge:
      final sides = challengeSides(l10n, d);
      return [
        d.question,
        if (sides.mine.chance != null) sides.mine.chance!,
        if (sides.theirs.chance != null) sides.theirs.chance!,
        if (d.amount != null) d.amount!,
      ];
    case final PredictionCardData d:
      return [
        d.question,
        if (d.charted)
          for (final l in d.lines!) pct(l.chance)
        else if (d.chance != null)
          pct(d.chance!),
        if (d.picked && d.amount != null) d.amount!,
      ];
    case final InvestmentCardData d:
      return [
        d.title,
        if (d.ticker != null) d.ticker!,
        if (d.price != null)
          shareCardPrice(loc, d.price!, decimalCap: d.decimalCap),
        if (d.change != null) shareCardChangeSigned(loc, d.change!),
        if (d.amount != null) d.amount!,
      ];
    case final ReceiptCardData d:
      return [
        for (final s in [
          d.amount,
          d.bitcoin,
          d.result,
          d.price,
          d.size,
          d.title,
          d.ticker,
        ])
          if (s != null) s,
        if (d.chance != null) pct(d.chance! * 100),
      ];
    case final BragWin d:
      return [
        d.title,
        d.result.text,
        d.paidText,
        d.payoutText,
        if (d.entryText != null) d.entryText!,
      ];
    case final BragPosition d:
      return [
        d.title,
        d.result.text,
        if (d.entryText != null) d.entryText!,
        if (d.nowText != null) d.nowText!,
      ];
    case final BragPortfolio d:
      return [
        if (d.allTime != null) d.allTime!.text,
        for (final t in d.top) t.result.text,
      ];
  }
  throw ArgumentError(data);
}

/// The one figure a line may derive: the crowd on the other side of a
/// pick, 100% less the card's whole percent.
List<String> _derived(AppLocalizations l10n, Object data) {
  final loc = l10n.localeName;
  return switch (data) {
    PredictionCardData(:final chance?, picked: true) => [
        shareCardChance(loc, 100.0 - chance.clamp(0.0, 100.0).round())
      ],
    ReceiptCardData(:final chance?) => [
        shareCardChance(loc, 100.0 - (chance * 100).round())
      ],
    _ => const <String>[],
  };
}

final _number = RegExp(r'\d+(?:[.,  ]\d+)*');

Set<String> _numbers(Iterable<String> texts) =>
    {for (final t in texts) ..._number.allMatches(t).map((m) => m.group(0)!)};

/// [data] as a pick, to find a market's side-taking lines.
PredictionCardData _asPick(PredictionCardData d) => PredictionCardData(
      question: d.question,
      outcome: d.outcome,
      chance: d.chance,
      binary: d.binary,
      topic: d.topic,
      leading: d.leading,
      opponent: d.opponent,
      opponentChance: d.opponentChance,
      picked: true,
      amount: r'$10',
    );

void main() {
  final locales = AppLocalizations.supportedLocales;

  test('every pool holds its lines, each once, in every language', () {
    for (final locale in locales) {
      final l10n = lookupAppLocalizations(locale);
      final en = locale.languageCode == 'en';
      for (final c in _cases) {
        final pool = _pool(l10n, c.data);
        expect(pool.length, greaterThanOrEqualTo(c.min),
            reason: '$locale ${c.name}');
        expect(pool.length, lessThanOrEqualTo(21), reason: '$locale ${c.name}');
        expect(pool.toSet(), hasLength(pool.length),
            reason: '$locale ${c.name}: a line twice in $pool');
        expect(pool.length, _pool(lookupAppLocalizations(const Locale('en')),
                c.data).length,
            reason: '$locale ${c.name}: the same pool as in English');
        for (final line in pool) {
          expect(line.trim(), isNotEmpty, reason: '$locale ${c.name}');
          expect(line, isNot(contains('{')), reason: '$locale: $line');
          if (en) {
            expect(
                RegExp(r'\bbet(s|ting)?\b', caseSensitive: false)
                    .hasMatch(line),
                isFalse,
                reason: line);
          }
        }
      }
    }
  });

  test(
      'a line names only a figure the card shows (the crowd on the other '
      'side the one derived), in every language', () {
    for (final locale in locales) {
      final l10n = lookupAppLocalizations(locale);
      for (final c in _cases) {
        final allowed = _numbers(
            [..._figures(l10n, c.data), ..._derived(l10n, c.data)]);
        for (final line in _pool(l10n, c.data)) {
          for (final n in _numbers([line])) {
            expect(allowed, contains(n),
                reason: '$locale ${c.name}: "$line" names $n, the card '
                    'shows $allowed');
          }
        }
      }
    }
  });

  test(
      'the multi-outcome market from the founder\'s screenshot: about the '
      'race, never "The crowd is 66% wrong."', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final race = _cases.firstWhere((c) => c.name == 'market: the race, charted');
    final pool = _pool(l10n, race.data);
    expect(pool, contains("J.D. Vance leads. Nothing's settled."));
    expect(pool, contains("34% isn't a coronation."));
    expect(pool, contains('The chart says J.D. Vance. History says wait.'));
    expect(pool.where((l) => l.contains('66')), isEmpty);
    expect(pool.where((l) => l.contains('wrong')), isEmpty);
    // A pick on the underdog keeps the crowd, from the card's own 47%.
    final dog = _cases.firstWhere((c) => c.name == 'pick: a match underdog');
    expect(_pool(l10n, dog.data),
        containsAll(["47% says I'm early, not wrong.", 'The crowd is 53% wrong.']));
    // A favourite is never "early", the crowd never "wrong".
    final fav = _cases.firstWhere((c) => c.name == 'pick: a match favourite');
    expect(_pool(l10n, fav.data).where((l) => l.contains('wrong')), isEmpty);
    expect(_pool(l10n, fav.data), contains('53% agree. Smart crowd.'));
    // A leader under half is neither.
    final lead =
        _cases.firstWhere((c) => c.name == "pick: a race's leader under half");
    expect(_pool(l10n, lead.data),
        containsAll(['Backing the favourite. Revolutionary.']));
    expect(_pool(l10n, lead.data).where((l) => l.contains('wrong')), isEmpty);
    expect(_pool(l10n, lead.data).where((l) => l.contains('Smart crowd')),
        isEmpty);
    // A long name stays out of the lines.
    final long = _cases.firstWhere(
        (c) => c.name == 'market: a race, a long leader name, not charted');
    expect(_pool(l10n, long.data).where((l) => l.contains('Lula')), isEmpty);
  });

  test("a whole market's lines take no side: none of a pick's but the "
      "topic's neutral ones, in every language", () {
    for (final locale in locales) {
      final l10n = lookupAppLocalizations(locale);
      final neutral = {
        l10n.shareEdgePredictionPolitics,
        l10n.shareEdgeTopicDebates,
        l10n.shareEdgeTopicCoach,
        l10n.shareEdgeTopicVolatility,
        l10n.shareEdgeTopicMinutes,
      };
      for (final c in _cases.where((c) => c.market)) {
        final d = c.data as PredictionCardData;
        final market = _pool(l10n, d).toSet();
        final pick = _pool(l10n, _asPick(d)).toSet();
        expect(market.intersection(pick).difference(neutral), isEmpty,
            reason: '$locale ${c.name}');
        expect(market, isNot(contains(l10n.shareEdgePredictionDare)));
      }
    }
  });

  testWidgets(
      'every line whole on two lines at the card\'s width and type, in all '
      '23 languages', (tester) async {
    await tester.runAsync(loadShareCardFonts);
    // The edgy line's own style and width (ShareCardFrame).
    final style = shareCardText(kShareCardLineSize, FontWeight.w700,
        const Color(0xFF000000),
        spacing: -0.5, height: 1.12);
    final width = kShareCardSize.width - 2 * kShareCardPadding;
    final cut = <String>[];
    for (final locale in locales) {
      final l10n = lookupAppLocalizations(locale);
      final seen = <String>{};
      for (final c in _cases) {
        for (final line in _pool(l10n, c.data)) {
          if (!seen.add(line)) continue;
          final tp = TextPainter(
            text: TextSpan(text: line, style: style),
            textDirection: TextDirection.ltr,
            maxLines: 2,
          )..layout(maxWidth: width);
          if (tp.didExceedMaxLines) cut.add('$locale ${c.name}: $line');
          tp.dispose();
        }
      }
    }
    expect(cut, isEmpty, reason: cut.join('\n'));
  });
}
