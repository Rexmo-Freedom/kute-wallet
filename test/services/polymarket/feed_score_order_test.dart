// Each number of a score goes to its own team. Polymarket's feed writes a
// score as one string and names the home and away teams beside it; which
// number comes first is the league's (feed_score_order.dart). The games
// below are real: the feed message and the Gamma event as read on
// 2026-10-04 and 05, with the score ESPN's scoreboard gave at the same
// moment.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/game_header.dart';
import 'package:kute/services/polymarket/live_game/feed_score_order.dart';
import 'package:kute/services/polymarket/live_game/game_score.dart';
import 'package:kute/services/polymarket/live_game/game_sides.dart';
import 'package:kute/services/polymarket/live_game/game_timeline.dart';
import 'package:kute/services/polymarket/market_card_shape.dart';
import 'package:kute/services/sports_websocket_service.dart';

typedef _Game = ({
  String league,
  String slug,
  String title,
  // Gamma teams as (name, abbreviation, ordering).
  List<(String, String, String)> teams,
  // The feed's own homeTeam, awayTeam and score.
  String feedHome,
  String feedAway,
  String feedScore,
  // What the header must read, in the title's order, and what ESPN had.
  String header,
  String espn,
});

const List<_Game> _games = [
  (
    league: 'nfl',
    slug: 'nfl-den-sf-2026-10-04',
    title: 'Broncos vs. 49ers',
    teams: [('Denver Broncos', 'den', 'away'), ('San Francisco 49ers', 'sf', 'home')],
    feedHome: 'SF',
    feedAway: 'DEN',
    feedScore: '6-17',
    header: '6 – 17',
    espn: 'DEN 6 @ SF 17',
  ),
  (
    league: 'nfl',
    slug: 'nfl-kc-lv-2026-10-04',
    title: 'Chiefs vs. Raiders',
    teams: [('Kansas City Chiefs', 'kc', 'away'), ('Las Vegas Raiders', 'lv', 'home')],
    feedHome: 'LV',
    feedAway: 'KC',
    feedScore: '17-19',
    header: '17 – 19',
    espn: 'KC 17 @ LV 19',
  ),
  (
    league: 'nfl',
    slug: 'nfl-la-phi-2026-10-04',
    title: 'Rams vs. Eagles',
    teams: [('Los Angeles Rams', 'la', 'away'), ('Philadelphia Eagles', 'phi', 'home')],
    feedHome: 'PHI',
    feedAway: 'LA',
    feedScore: '24-20',
    header: '24 – 20',
    espn: 'LAR 24 @ PHI 20 (final)',
  ),
  (
    league: 'mlb',
    slug: 'mlb-sd-mil-2026-10-04',
    title: 'San Diego Padres vs. Milwaukee Brewers',
    teams: [('San Diego Padres', 'sd', 'away'), ('Milwaukee Brewers', 'mil', 'home')],
    feedHome: 'MIL',
    feedAway: 'SD',
    feedScore: '3-2',
    header: '3 – 2',
    espn: 'SD 3 @ MIL 2',
  ),
  (
    league: 'nhl',
    slug: 'nhl-utah-nyr-2026-10-04',
    title: 'Utah vs. Rangers',
    teams: [('Utah', 'utah', 'away'), ('New York Rangers', 'nyr', 'home')],
    feedHome: 'NYR',
    feedAway: 'UTA',
    feedScore: '0-1',
    header: '0 – 1',
    espn: 'UTA 0 @ NYR 1',
  ),
  (
    league: 'nba',
    slug: 'nba-gs-lac-2026-10-04',
    title: 'Warriors vs. Clippers',
    teams: [('Golden State Warriors', 'gs', 'away'), ('Los Angeles Clippers', 'lac', 'home')],
    feedHome: 'LAC',
    feedAway: 'GS',
    feedScore: '38-47',
    header: '38 – 47',
    espn: 'GS 38 @ LAC 47',
  ),
  (
    league: 'arg',
    slug: 'arg-aaj-tig-2026-10-03',
    title: 'AA Argentinos Juniors vs. CA Tigre',
    teams: [('AA Argentinos Juniors', 'aaj', 'home'), ('CA Tigre', 'tig', 'away')],
    feedHome: 'AA Argentinos Juniors',
    feedAway: 'CA Tigre',
    feedScore: '2-1',
    header: '2 – 1',
    espn: 'ARGJ 2, TIG 1 (home first)',
  ),
  (
    league: 'conl',
    slug: 'conl-pur-cay-2026-10-04',
    title: 'Puerto Rico vs. Cayman Islands',
    teams: [('Puerto Rico', 'pur', 'home'), ('Cayman Islands', 'cay', 'away')],
    feedHome: 'Puerto Rico',
    feedAway: 'Cayman Islands',
    feedScore: '1-0',
    header: '1 – 0',
    espn: 'PUR 1, CAY 0 (home first)',
  ),
];

Map<String, dynamic> _feed(_Game g) => {
      'gameId': 1,
      'leagueAbbreviation': g.league,
      'homeTeam': g.feedHome,
      'awayTeam': g.feedAway,
      'status': 'InProgress',
      'score': g.feedScore,
      'period': 'Q4',
      'live': true,
      'ended': false,
    };

/// The event as Gamma sends it: only the fields the score reads.
Map<String, dynamic> _gamma(_Game g, {bool withTeams = true}) => {
      'id': '1',
      'slug': g.slug,
      'title': g.title,
      'gameId': 1,
      'live': true,
      'score': g.feedScore,
      'period': 'Q4',
      'markets': <Map<String, dynamic>>[],
      if (withTeams)
        'teams': [
          for (final t in g.teams)
            <String, dynamic>{
              'name': t.$1,
              'abbreviation': t.$2,
              'ordering': t.$3,
              'league': g.league,
            },
        ],
    };

PolymarketEvent _event(_Game g, {bool withTeams = true}) =>
    PolymarketModel().parseEventsRaw([_gamma(g, withTeams: withTeams)]).single;

/// The header's two teams: the title's, in its order.
PolySportsTeams _header(_Game g) {
  final t = titleTeams(g.title)!;
  return (teamA: t.$1, teamB: t.$2, imageA: null, imageB: null);
}

void main() {
  group('which side a league\'s first number is', () {
    test('the North American leagues are away first, the rest home first',
        () {
      for (final league in ['nfl', 'nba', 'mlb', 'nhl', 'NFL', ' cfb ']) {
        expect(feedScoreIsAwayFirst(league), isTrue, reason: league);
      }
      for (final league in ['epl', 'arg', 'conl', 'lol', 'cs2', 'atp', null, '']) {
        expect(feedScoreIsAwayFirst(league), isFalse, reason: '$league');
      }
    });

    test('a score is turned home first pair by pair, and left alone '
        'otherwise', () {
      expect(feedScoreHomeFirst('6-17', league: 'nfl'), '17-6');
      expect(feedScoreHomeFirst('6 - 17', league: 'nfl'), '17 - 6');
      expect(feedScoreHomeFirst('2-1', league: 'epl'), '2-1');
      expect(feedScoreHomeFirst('6-3, 2-1', league: 'atp'), '6-3, 2-1');
      expect(feedScoreHomeFirst('000-000|2-1|Bo5', league: 'lol'),
          '000-000|2-1|Bo5');
      expect(feedScoreHomeFirst('182/4', league: 'nfl'), '182/4');
      expect(feedScoreHomeFirst(null, league: 'nfl'), isNull);
    });

    test('the league of a slug', () {
      expect(leagueOfEventSlug('nfl-den-sf-2026-10-04'), 'nfl');
      expect(leagueOfEventSlug('conl-pur-cay-2026-10-04-more-markets'),
          'conl');
      expect(leagueOfEventSlug(''), isNull);
    });
  });

  for (final g in _games) {
    group('${g.league} ${g.title} (${g.espn})', () {
      // ESPN's two numbers, away then home or home then away as the
      // header's title has them.
      final first = int.parse(g.header.split(' – ')[0]);
      final second = int.parse(g.header.split(' – ')[1]);
      final firstIsHome = g.teams.first.$3 == 'home';
      final home = firstIsHome ? first : second;
      final away = firstIsHome ? second : first;

      test('the live feed: each number under its own team', () {
        final ws = SportsMatchUpdate.fromJson(_feed(g));
        // Home first inside the app, whatever the league's order.
        final score = GameScore.parse(ws.score, GameSport.other);
        expect(score.home, home);
        expect(score.away, away);
        final event = _event(g);
        expect(
          polyLiveScoreText(event, ws,
              sportsTeams: _header(g),
              teams: event.teams),
          g.header,
        );
      });

      test('Gamma\'s own score before the feed ticks, with and without '
          'its teams', () {
        final event = _event(g);
        expect(
          polyLiveScoreText(event, null,
              sportsTeams: _header(g),
              teams: event.teams),
          g.header,
        );
        // A card: the title's first team gets the header's first number.
        final card = polyCardScore(event.score!, firstIsHome: firstIsHome);
        expect(card?.a, first);
        expect(card?.b, second);
        // Opened from search the event has no teams: the feed's names say
        // which side the title's first team is.
        final bare = _event(g, withTeams: false);
        final ws = SportsMatchUpdate.fromJson(_feed(g));
        expect(GameScore.parse(bare.score, GameSport.other).home, home);
        expect(bare.teams, isEmpty);
        expect(ws.score, bare.score);
      });

      test('the backend\'s timeline: the same change as the phone saw it',
          () {
        final snapshot = GameTimelineSnapshot.fromJson({
          'game_id': '1',
          'known': true,
          'league': g.league,
          'home': g.feedHome,
          'away': g.feedAway,
          'score': g.feedScore,
          'events': [
            {
              't': 1791146958437,
              'kind': 'score',
              'score_before': '0-0',
              'score': g.feedScore,
              'period_before': 'Q1',
              'period': 'Q1',
            },
          ],
        })!;
        final ws = SportsMatchUpdate.fromJson(_feed(g));
        expect(snapshot.score, ws.score);
        expect(snapshot.events.single.score, ws.score);
        final after = GameScore.parse(snapshot.events.single.score, GameSport.other);
        expect(after.home, home);
        expect(after.away, away);
      });
    });
  }
}
