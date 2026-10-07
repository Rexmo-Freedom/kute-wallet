// A game's timeline: change detection on the live feed, merging the
// backend's list with the local one, and the chart markers per sport.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/live_game/game_score.dart';
import 'package:kute/services/polymarket/live_game/game_timeline.dart';
import 'package:kute/services/polymarket/live_game/local_game_events.dart';
import 'package:kute/services/sports_websocket_service.dart';

GameEvent ev(int t, String before, String after,
        {String pb = '2H',
        String p = '2H',
        String elapsed = '',
        bool ended = false,
        bool approx = false,
        bool local = false}) =>
    GameEvent(
      tMs: t,
      scoreBefore: before,
      score: after,
      periodBefore: pb,
      period: p,
      elapsed: elapsed,
      ended: ended,
      approx: approx,
      local: local,
    );

void main() {
  group('GameChangeDetector', () {
    test('first sighting and a moving clock make no event', () {
      final d = GameChangeDetector();
      expect(
          d.observe(
              id: 'g', score: '1-0', period: '1H', elapsed: '44', ended: false, nowMs: 1),
          isNull);
      expect(
          d.observe(
              id: 'g', score: '1-0', period: '1H', elapsed: '45', ended: false, nowMs: 2),
          isNull);
    });

    test('score, period, status and the end are changes', () {
      final d = GameChangeDetector();
      d.observe(id: 'g', score: '1-0', period: '1H', status: 'InProgress', ended: false, nowMs: 1);
      final ht = d.observe(
          id: 'g', score: '1-0', period: 'HT', status: 'Break', ended: false, nowMs: 2)!;
      expect((ht.periodBefore, ht.period, ht.scoreChanged), ('1H', 'HT', false));
      d.observe(id: 'g', score: '1-0', period: '2H', status: 'InProgress', ended: false, nowMs: 3);
      final goal = d.observe(
          id: 'g', score: '1-1', period: '2H', elapsed: '47', status: 'inprogress', ended: false, nowMs: 4)!;
      expect((goal.scoreBefore, goal.score, goal.elapsed), ('1-0', '1-1', '47'));
      expect(goal.local, isTrue);
      expect(goal.approx, isFalse);
      final end = d.observe(id: 'g', score: '1-1', period: '2H', ended: true, nowMs: 5)!;
      expect(end.ended, isTrue);
    });

    test('a missing field keeps the last value; a learned one is no change',
        () {
      final d = GameChangeDetector();
      d.observe(id: 'g', status: 'Scheduled', ended: false, nowMs: 1);
      expect(
          d.observe(id: 'g', score: '0-0', period: 'Q1', ended: false, nowMs: 2),
          isNull);
      expect(d.observe(id: 'g', period: 'Q1', ended: false, nowMs: 3), isNull);
      final td = d.observe(id: 'g', score: '6-0', ended: false, nowMs: 4)!;
      expect((td.scoreBefore, td.score, td.period), ('0-0', '6-0', 'Q1'));
    });

    test('a change first seen on a new connection is approximate', () {
      final d = GameChangeDetector();
      d.observe(id: 'g', score: '0-0', period: '1H', ended: false, nowMs: 1, epoch: 1);
      final e = d.observe(
          id: 'g', score: '2-0', period: '1H', ended: false, nowMs: 2, epoch: 2)!;
      expect(e.approx, isTrue);
      final next = d.observe(
          id: 'g', score: '3-0', period: '1H', ended: false, nowMs: 3, epoch: 2)!;
      expect(next.approx, isFalse);
    });

    test('bounded number of games', () {
      final d = GameChangeDetector(maxGames: 2);
      d.observe(id: 'a', score: '0-0', ended: false, nowMs: 1);
      d.observe(id: 'b', score: '0-0', ended: false, nowMs: 2);
      d.observe(id: 'c', score: '0-0', ended: false, nowMs: 3);
      // 'a' was forgotten: its next update is a first sighting again.
      expect(d.observe(id: 'a', score: '1-0', ended: false, nowMs: 4), isNull);
    });
  });

  group('PolyLocalGameEvents', () {
    SportsMatchUpdate update(Map<String, dynamic> json) =>
        SportsMatchUpdate.fromJson(json);

    test('keeps changes per game and announces them', () async {
      final store = PolyLocalGameEvents();
      final seen = <LocalGameChange>[];
      final sub = store.changes.listen(seen.add);
      store.observe(
          update({'gameId': 19505, 'score': '21-20', 'period': 'Q4', 'live': true}),
          epoch: 1, nowMs: 1000);
      store.observe(
          update({'gameId': 19505, 'score': '21-26', 'period': 'Q4', 'elapsed': '4:27', 'live': true}),
          epoch: 1, nowMs: 2000);
      await Future<void>.delayed(Duration.zero);
      expect(store.eventsFor('19505').single.score, '21-26');
      expect(store.firstSeenMs('19505'), 1000);
      expect(seen.single.gameId, '19505');
      expect(store.eventsFor('nope'), isEmpty);
      await sub.cancel();
    });

    test('cricket is keyed by its metadata id, and its flapping cancels out',
        () {
      final store = PolyLocalGameEvents();
      final live = {'metadataGameId': 'id2703680375016640', 'score': '0-0', 'period': 'Live'};
      final scheduled = {'metadataGameId': 'id2703680375016640', 'score': '0-0', 'period': 'Scheduled'};
      for (var i = 0; i < 20; i++) {
        store.observe(update(i.isEven ? live : scheduled),
            epoch: 1, nowMs: 1000 + i * 7000);
      }
      expect(store.eventsFor('id2703680375016640').length, lessThanOrEqualTo(1));
    });

    test('caps the events kept per game', () {
      final store = PolyLocalGameEvents(maxEventsPerGame: 5);
      for (var i = 0; i < 20; i++) {
        store.observe(update({'gameId': 1, 'score': '$i-0', 'period': 'Q1'}),
            epoch: 1, nowMs: 1000 + i * 60000);
      }
      final events = store.eventsFor('1');
      expect(events.length, 5);
      expect(events.last.score, '19-0');
    });
  });

  group('GameTimelineSnapshot.fromJson', () {
    test('reads the backend body', () {
      final s = GameTimelineSnapshot.fromJson({
        'game_id': '19505',
        'known': true,
        'league': 'nfl',
        'observed_since': 1000,
        'ended': false,
        'truncated': false,
        'events': [
          {'t': 3000, 'kind': 'period', 'score_before': '21-26', 'score': '21-26', 'period_before': 'Q4', 'period': 'FT', 'ended': true},
          {'t': 2000, 'kind': 'score', 'score_before': '21-20', 'score': '21-26', 'period_before': 'Q4', 'period': 'Q4', 'elapsed': '4:27', 'approx': true},
          {'bad': 1},
        ],
      })!;
      expect(s.known, isTrue);
      expect(s.league, 'nfl');
      expect(s.observedSinceMs, 1000);
      expect(s.events.map((e) => e.tMs), [2000, 3000]);
      expect(s.events.first.approx, isTrue);
      expect(s.events.first.local, isFalse);
      expect(s.events.last.ended, isTrue);
    });

    test('an unknown game and a wrong shape', () {
      final s = GameTimelineSnapshot.fromJson(
          {'game_id': '1', 'known': false, 'events': []})!;
      expect(s.known, isFalse);
      expect(s.events, isEmpty);
      expect(GameTimelineSnapshot.fromJson({'error': 'x'}), isNull);
      expect(GameTimelineSnapshot.fromJson('nope'), isNull);
    });
  });

  group('mergeGameEvents', () {
    test('the same change seen by both is kept once', () {
      final merged = mergeGameEvents(
        [ev(100000, '0-0', '1-0')],
        [ev(101500, '0-0', '1-0', local: true)],
      );
      expect(merged.length, 1);
      expect(merged.single.local, isFalse);
    });

    test('an exact local sighting replaces an approximate backend one', () {
      final merged = mergeGameEvents(
        [ev(160000, '0-0', '1-0', approx: true)],
        [ev(100000, '0-0', '1-0', local: true)],
      );
      expect(merged.single.tMs, 100000);
      expect(merged.single.approx, isFalse);
    });

    test('local events the backend never saw are kept, in order', () {
      final merged = mergeGameEvents(
        [ev(500000, '1-0', '2-0')],
        [
          ev(100000, '0-0', '1-0', local: true), // before the backend started
          ev(900000, '2-0', '2-1', local: true), // newer than its last read
        ],
      );
      expect(merged.map((e) => e.score), ['1-0', '2-0', '2-1']);
    });

    test('a late approximate local jump the backend covered is dropped', () {
      // The phone was away while the score went 0-0 > 1-0 > 2-0.
      final merged = mergeGameEvents(
        [ev(100000, '0-0', '1-0'), ev(400000, '1-0', '2-0')],
        [ev(900000, '0-0', '2-0', approx: true, local: true)],
      );
      expect(merged.map((e) => e.score), ['1-0', '2-0']);
    });

    test('the same score change far apart is two changes (a correction)', () {
      final merged = mergeGameEvents(
        [ev(100000, '0-0', '1-0')],
        [ev(100000 + kGameEventSameWindowMs + 1, '0-0', '1-0', local: true)],
      );
      expect(merged.length, 2);
    });

    test('with no backend the local list is the timeline', () {
      final local = [ev(1, '0-0', '1-0', local: true)];
      expect(mergeGameEvents(const [], local).single.score, '1-0');
      expect(mergeGameEvents(const [], const []), isEmpty);
    });
  });

  test('gameEventReverts', () {
    final a = ev(1000, '0-0', '0-0', pb: 'Live', p: 'Scheduled');
    expect(gameEventReverts(a, ev(8000, '0-0', '0-0', pb: 'Scheduled', p: 'Live')),
        isTrue);
    expect(
        gameEventReverts(
            a, ev(1000 + kGameEventFlapWindowMs + 1, '0-0', '0-0', pb: 'Scheduled', p: 'Live')),
        isFalse);
    expect(gameEventReverts(a, ev(8000, '0-0', '1-0', pb: 'Scheduled', p: 'Live')),
        isFalse);
  });

  group('gameMarkersFrom', () {
    test('soccer: goals with the minute, half-time, full time', () {
      final markers = gameMarkersFrom([
        ev(1, '0-0', '1-0', pb: '1H', p: '1H', elapsed: '38'),
        ev(2, '1-0', '1-0', pb: '1H', p: 'HT'),
        ev(3, '1-0', '1-0', pb: 'HT', p: '2H'),
        ev(4, '1-0', '1-1', elapsed: '47'),
        ev(5, '1-1', '1-0', elapsed: '49'), // VAR
        ev(6, '1-0', '1-0', pb: '2H', p: 'FT', ended: true),
      ], GameSport.soccer);
      expect(markers.map((m) => m.kind), [
        GameMarkerKind.goal,
        GameMarkerKind.period,
        GameMarkerKind.period,
        GameMarkerKind.goal,
        GameMarkerKind.correction,
        GameMarkerKind.finalScore,
      ]);
      expect((markers[0].side, markers[0].clock, markers[0].scoreText),
          (1, "38'", '1–0'));
      expect(markers[3].side, -1);
      expect(markers[1].period, 'HT');
      expect(markers.last.scoreText, '1–0');
    });

    test('NFL: touchdown, field goal, anything else is a score', () {
      final markers = gameMarkersFrom([
        ev(1, '0-0', '7-0', pb: 'Q1', p: 'Q1', elapsed: '9:12'),
        ev(2, '7-0', '7-3', pb: 'Q1', p: 'Q1', elapsed: '3:01'),
        ev(3, '7-3', '7-9', pb: 'Q2', p: 'Q2', elapsed: '4:27'),
        ev(4, '7-9', '7-10', pb: 'Q2', p: 'Q2'),
        ev(5, '7-10', '9-10', pb: 'Q2', p: 'Q2'),
        ev(6, '9-10', '9-10', pb: 'Q2', p: 'Q3'),
      ], GameSport.americanFootball);
      expect(markers.map((m) => m.kind), [
        GameMarkerKind.touchdown,
        GameMarkerKind.fieldGoal,
        GameMarkerKind.touchdown,
        GameMarkerKind.score,
        GameMarkerKind.score,
        GameMarkerKind.period,
      ]);
      expect(markers[0].clock, 'Q1 9:12');
      expect(markers[2].side, -1);
      expect(markers[2].scoreText, '7–9');
    });

    test('basketball: only the periods and the end', () {
      final markers = gameMarkersFrom([
        ev(1, '77-80', '77-82', pb: 'Q4', p: 'Q4'),
        ev(2, '77-82', '79-82', pb: 'Q4', p: 'Q4'),
        ev(3, '79-82', '79-82', pb: 'Q3', p: 'Q4'),
        ev(4, '79-82', '81-82', pb: 'Q4', p: 'Q4', ended: true),
      ], GameSport.basketball);
      expect(markers.map((m) => m.kind),
          [GameMarkerKind.period, GameMarkerKind.finalScore]);
    });

    test('tennis: a marker per set won, not per game', () {
      final markers = gameMarkersFrom([
        ev(1, '5-3', '6-3', pb: 'S1', p: 'S1'),
        ev(2, '6-3', '6-3, 0-0', pb: 'S1', p: 'S2'),
        ev(3, '6-3, 0-0', '6-3, 0-1', pb: 'S2', p: 'S2'),
        ev(4, '6-3, 5-6', '6-3, 5-7', pb: 'S2', p: 'S2'),
      ], GameSport.tennis);
      expect(markers.map((m) => (m.kind, m.number, m.side, m.scoreText)), [
        (GameMarkerKind.setWon, 1, 1, '6–3'),
        (GameMarkerKind.period, null, 0, ''),
        (GameMarkerKind.setWon, 2, -1, '5–7'),
      ]);
    });

    test('esports: a map won, the next map starting, never a round', () {
      final markers = gameMarkersFrom([
        ev(1, '12-9|0-0|Bo3', '13-9|0-0|Bo3', pb: '1/3', p: '1/3'),
        ev(2, '13-9|0-0|Bo3', '000-000|1-0|Bo3', pb: '1/3', p: '1/3'),
        ev(3, '000-000|1-0|Bo3', '000-000|1-0|Bo3', pb: '1/3', p: '2/3'),
        ev(4, '5-13|1-0|Bo3', '000-000|1-1|Bo3', pb: '2/3', p: '3/3'),
        ev(5, '13-2|1-1|Bo3', '000-000|2-1|Bo3', pb: '3/3', p: '3/3', ended: true),
      ], GameSport.esports);
      expect(markers.map((m) => (m.kind, m.number, m.side, m.scoreText)), [
        (GameMarkerKind.mapWon, 1, 1, '1–0'),
        (GameMarkerKind.mapStart, 2, 0, ''),
        (GameMarkerKind.mapWon, 2, -1, '1–1'),
        (GameMarkerKind.finalScore, null, 0, '2–1'),
      ]);
    });

    test('cricket: nothing but the end', () {
      final markers = gameMarkersFrom([
        ev(1, '4-162', '0-31', pb: 'Live', p: 'Live'),
        ev(2, '0-31', '0-31', pb: 'Live', p: 'Scheduled'),
        ev(3, '0-31', '133-218', pb: 'Live', p: 'FT', ended: true),
      ], GameSport.cricket);
      expect(markers.map((m) => m.kind), [GameMarkerKind.finalScore]);
    });

    test('an approximate event keeps its flag; unknown sports mark low scores',
        () {
      final markers = gameMarkersFrom([
        ev(1, '0-0', '1-0', pb: 'P1', p: 'P1', approx: true),
        ev(2, '40-40', '42-40', pb: 'P1', p: 'P1'),
      ], GameSport.other);
      expect(markers.single.kind, GameMarkerKind.score);
      expect(markers.single.approx, isTrue);
    });
  });

  test('gameClockText', () {
    expect(gameClockText(GameSport.soccer, '2H', '47'), "47'");
    expect(gameClockText(GameSport.soccer, '2H', '90+3'), "90+3'");
    expect(gameClockText(GameSport.americanFootball, 'Q4', '4:27'), 'Q4 4:27');
    expect(gameClockText(GameSport.tennis, 'S2', ''), '');
  });
}
