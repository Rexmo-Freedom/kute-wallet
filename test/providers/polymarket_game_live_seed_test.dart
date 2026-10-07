// Before Polymarket's sports feed says anything about a game (its first
// message can take twenty seconds), the game's teams, score, period and
// live state come from the backend's timeline answer; once the feed has
// spoken, the feed wins.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/services/polymarket/live_game/game_timeline.dart';
import 'package:kute/services/sports_websocket_service.dart';

void main() {
  late GameTimelineFetch original;
  setUp(() => original = gameTimelineFetch);
  tearDown(() => gameTimelineFetch = original);

  // The backend's body for an NFL game in play (the feed writes the
  // North American leagues away first).
  final body = {
    'game_id': '42',
    'known': true,
    'league': 'nfl',
    'home': 'Chiefs',
    'away': 'Bills',
    'score': '7-14',
    'period': 'Q2',
    'elapsed': '4:27',
    'status': 'InProgress',
    'live': true,
    'ended': false,
    'observed_since': 1000,
    'updated_at': 5000,
    'start_time': 1791400000000,
    'truncated': false,
    'events': <Object>[],
  };

  test('the timeline answer carries the game as the feed would', () {
    final s = GameTimelineSnapshot.fromJson(body)!;
    expect(s.home, 'Chiefs');
    expect(s.away, 'Bills');
    expect(s.score, '14-7', reason: 'home first');
    expect(s.period, 'Q2');
    expect(s.elapsed, '4:27');
    expect(s.status, 'InProgress');
    expect(s.live, isTrue);
    expect(s.updatedAtMs, 5000);
    expect(s.startTimeMs, 1791400000000);
    expect(
        GameTimelineSnapshot.fromJson({...body}..remove('start_time'))!
            .startTimeMs,
        isNull,
        reason: 'omitted while unknown');
  });

  test('a game the backend does not know seeds nothing', () {
    expect(
        gameFeedFromSnapshot(
            '42', const GameTimelineSnapshot(known: false, live: true)),
        isNull);
    expect(PolyGameTimeline.empty.liveOr(null), isNull);
  });

  test('the timeline answer is the live state until the feed speaks', () {
    fakeAsync((async) {
      gameTimelineFetch = (id) async => GameTimelineSnapshot.fromJson(body);
      final container = ProviderContainer();
      final sub = container.listen(polyGameTimelineProvider('42'), (_, __) {});
      async.flushMicrotasks();

      final timeline = container.read(polyGameTimelineProvider('42'));
      final seeded = timeline.liveOr(null)!;
      expect(seeded.isInPlay, isTrue);
      expect(seeded.homeTeam, 'Chiefs');
      expect(seeded.awayTeam, 'Bills');
      expect(seeded.score, '14-7');
      expect(seeded.period, 'Q2');
      expect(seeded.leagueAbbreviation, 'nfl');
      expect(seeded.gameId, 42);
      expect(seeded.gameStartTime?.millisecondsSinceEpoch, 1791400000000);

      // The feed's own word wins once it has one.
      final ws = SportsMatchUpdate(
        slug: 'nfl-buf-kc',
        gameId: 42,
        live: true,
        ended: false,
        homeTeam: 'Chiefs',
        awayTeam: 'Bills',
        score: '21-7',
        period: 'Q3',
        updatedAt: DateTime(2026),
      );
      expect(identical(timeline.liveOr(ws), ws), isTrue);

      sub.close();
      container.dispose();
      async.flushTimers();
    });
  });

  test('cricket keeps its metadata id', () {
    final seeded = gameFeedFromSnapshot(
        'id2705074469517978', const GameTimelineSnapshot(known: true))!;
    expect(seeded.gameId, isNull);
    expect(seeded.metadataGameId, 'id2705074469517978');
  });
}
