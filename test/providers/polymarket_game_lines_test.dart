import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/services/sports_websocket_service.dart';

Map<String, dynamic> _market(String type, double? line, String q,
        List<String> names, List<String> prices,
        {int? delay}) =>
    {
      'id': q,
      'question': q,
      'sportsMarketType': type,
      'line': line,
      'outcomes': '["${names[0]}", "${names[1]}"]',
      'outcomePrices': '["${prices[0]}", "${prices[1]}"]',
      'clobTokenIds': '["${q}a", "${q}b"]',
      'conditionId': '0x$q',
      if (delay != null) 'secondsDelay': delay,
    };

void main() {
  // Shape of nfl-ind-was-2026-10-04 read with include_best_lines=true.
  final raw = <String, dynamic>{
    'bestLines': [
      {'id': '2305779', 'lineType': 'spreads-away', 'line': 4.5},
      {'id': '2305780', 'lineType': 'totals', 'line': 46.5},
      {'id': '2305784', 'lineType': 'first_half_totals', 'line': 22.5},
    ],
    'markets': [
      _market('moneyline', null, 'Colts vs. Commanders',
          ['Colts', 'Commanders'], ['0.655', '0.345'],
          delay: 1),
      _market('spreads', -3.5, 'Spread: Colts (-3.5)',
          ['Colts', 'Commanders'], ['0.545', '0.455']),
      _market('spreads', -4.5, 'Spread: Colts (-4.5)',
          ['Colts', 'Commanders'], ['0.495', '0.505']),
      _market('spreads', -4.5, 'Spread: Commanders (-4.5)',
          ['Commanders', 'Colts'], ['0.2', '0.8']),
      _market('totals', 45.5, 'Colts vs. Commanders: O/U 45.5',
          ['Over', 'Under'], ['0.535', '0.465']),
      _market('totals', 46.5, 'Colts vs. Commanders: O/U 46.5',
          ['Over', 'Under'], ['0.495', '0.505']),
      _market('first_half_totals', 22.5, '1H O/U 22.5', ['Over', 'Under'],
          ['0.5', '0.5']),
    ],
  };

  test('picks the moneyline and the bestLines spread and total', () {
    final lines = PolyGameLines.fromRawEvent(raw);
    expect(lines.moneyline!.sideA, 'Colts');
    expect(lines.spread!.question, 'Spread: Colts (-4.5)');
    expect(lines.spread!.lineText, '-4.5');
    expect(lines.total!.question, 'Colts vs. Commanders: O/U 46.5');
    expect(lines.secondsDelay, 1);
    final o = lines.spread!.toOutcome();
    expect(o.tokenId, 'Spread: Colts (-4.5)a');
    expect(o.noTokenId, 'Spread: Colts (-4.5)b');
  });

  // Shape of nfl-la-phi-2026-10-04 an hour after the final whistle: the
  // moneyline closed and settled, a second-half spread still open.
  test('a finished game keeps its closed moneyline for the chart, not as '
      'a row to bet on', () {
    final lines = PolyGameLines.fromRawEvent({
      'markets': [
        {
          ..._market('moneyline', null, 'Rams vs. Eagles', ['Rams', 'Eagles'],
              ['1', '0']),
          'closed': true,
        },
        _market('second_half_spreads', -6.5, '2H Spread: Rams (-6.5)',
            ['Rams', 'Eagles'], ['0.9475', '0.0525']),
      ],
    });
    expect(lines.moneyline, isNull);
    expect(lines.isEmpty, isTrue);
    expect(lines.winner?.sideA, 'Rams');
    expect(lines.winner?.tokenA, 'Rams vs. Eaglesa');
    expect(lines.winner?.tokenB, 'Rams vs. Eaglesb');
  });

  test('a game in play charts its open moneyline', () {
    final lines = PolyGameLines.fromRawEvent(raw);
    expect(lines.settledMoneyline, isNull);
    expect(lines.winner, same(lines.moneyline));
  });

  test('without bestLines the line closest to even is the main one', () {
    final lines = PolyGameLines.fromRawEvent({...raw, 'bestLines': null});
    expect(lines.spread!.question, 'Spread: Colts (-4.5)');
    expect(lines.total!.line, 46.5);
  });

  group('the lines laid out from the card\'s own event', () {
    PolymarketEvent cardEvent(Map<String, dynamic> e) =>
        PolymarketModel().parseEventsRaw([
          {
            'id': '1',
            'slug': 'nfl-ind-was-2026-10-04',
            'title': 'Colts vs. Commanders',
            'gameId': 19502,
            ...e,
          }
        ]).single;

    test('the same board as the read, before the read', () {
      final event = cardEvent(raw);
      final fromCard = PolyGameLines.fromEvent(event);
      final read = PolyGameLines.fromRawEvent({...raw, 'bestLines': null});
      for (final (a, b) in [
        (fromCard.moneyline, read.moneyline),
        (fromCard.spread, read.spread),
        (fromCard.total, read.total),
      ]) {
        expect(a, isNotNull);
        expect(a!.question, b!.question);
        expect(a.kind, b.kind);
        expect(a.line, b.line);
        expect(a.sideA, b.sideA);
        expect(a.sideB, b.sideB);
        expect(a.priceA, b.priceA);
        expect(a.priceB, b.priceB);
        expect(a.tokenA, b.tokenA);
        expect(a.tokenB, b.tokenB);
        expect(a.conditionId, b.conditionId);
        expect(a.gammaMarketId, b.gammaMarketId);
      }
      // Laid out, not read: no read time, no Over token.
      expect(fromCard.readAtMs, isNull);
      expect(identical(PolyGameLines.fromEvent(event), fromCard), isTrue);
    });

    test('a finished game\'s closed moneyline is still its winner', () {
      final event = cardEvent({
        'markets': [
          {
            ..._market('moneyline', null, 'Rams vs. Eagles',
                ['Rams', 'Eagles'], ['1', '0']),
            'closed': true,
          },
          _market('second_half_spreads', -6.5, '2H Spread: Rams (-6.5)',
              ['Rams', 'Eagles'], ['0.9475', '0.0525']),
        ],
      });
      final lines = PolyGameLines.fromEvent(event);
      expect(lines.moneyline, isNull);
      expect(lines.winner?.tokenA, 'Rams vs. Eaglesa');
    });

    test('an event with no sports types (a search result) has none', () {
      const event = PolymarketEvent(
        id: '1',
        slug: 's',
        title: 'A vs. B',
        volume: 0,
        liquidity: 0,
        category: 'sports',
        conditionId: '',
        outcomes: [PolymarketOutcome(name: 'A', price: 0.5, tokenId: 'a')],
      );
      expect(PolyGameLines.fromEvent(event).isEmpty, isTrue);
      expect(PolyGameLines.fromEvent(event).winner, isNull);
    });
  });

  test('the read carries the Over token of the most even traded total', () {
    final lines = PolyGameLines.fromRawEvent({
      'markets': [
        {
          ..._market('totals', 46.5, 'O/U 46.5', ['Over', 'Under'],
              ['0.495', '0.505']),
          'spread': 0.01,
        },
      ],
    }, readAtMs: 5);
    expect(lines.overToken, 'O/U 46.5a');
    expect(lines.readAtMs, 5);
  });

  group('PolyLiveGame', () {
    const event = PolymarketEvent(
      id: '1',
      slug: 'nfl-ind-was-2026-10-04',
      title: 'Colts vs. Commanders',
      volume: 0,
      liquidity: 0,
      category: 'sports',
      conditionId: '',
      outcomes: [],
      gameId: 19502,
      teams: [
        PolymarketTeam(name: 'Colts', abbreviation: 'ind', ordering: 'away'),
        PolymarketTeam(
            name: 'Commanders', abbreviation: 'was', ordering: 'home'),
      ],
    );

    test('takes score, clock and possession from the live feed', () {
      final ws = SportsMatchUpdate.fromJson({
        'gameId': 19502,
        'homeTeam': 'WAS',
        'awayTeam': 'IND',
        'score': '3-7',
        'period': 'Q2',
        'elapsed': '08:14',
        'turn': 'IND',
        'live': true,
        'ended': false,
      });
      final game = PolyLiveGame.of(event, ws)!;
      expect(game.score, '3-7');
      expect(game.clock, 'Q2 08:14');
      expect(game.hasBall('IND'), isTrue);
      expect(game.hasBall('WAS'), isFalse);
    });

    test('falls back to the Gamma seed and its teams', () {
      const seeded = PolymarketEvent(
        id: '1',
        slug: 's',
        title: 'Colts vs. Commanders',
        volume: 0,
        liquidity: 0,
        category: 'sports',
        conditionId: '',
        outcomes: [],
        score: '000-000|1-0|Bo3',
        period: '2/3',
        teams: [
          PolymarketTeam(name: 'LOUD', ordering: 'home'),
          PolymarketTeam(name: 'Global Esports', ordering: 'away'),
        ],
      );
      final game = PolyLiveGame.of(seeded, null)!;
      expect(game.score, '1-0');
      expect(game.home, 'LOUD');
      expect(game.clock, '2/3');
    });

    test('a not-started or finished period is never live', () {
      for (final period in ['NS', 'VFT', 'FT', 'CAN']) {
        final e = PolymarketEvent(
          id: '1',
          slug: 's',
          title: 'A vs B',
          volume: 0,
          liquidity: 0,
          category: 'sports',
          conditionId: '',
          outcomes: const [],
          score: '21-25',
          period: period,
        );
        expect(e.isInPlay, isFalse, reason: period);
        expect(PolyLiveGame.of(e, null), isNull, reason: period);
      }
    });
  });
}
