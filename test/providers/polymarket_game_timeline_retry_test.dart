// A game's timeline read from the backend: a failed read is tried again
// at 5 s, 15 s and then every minute (never a minute and a half of no
// markers after one blip), an answer goes back to the live 20 s poll, and
// one read never waits longer than 4 s.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/services/polymarket/live_game/game_timeline.dart';

void main() {
  late GameTimelineFetch original;
  setUp(() => original = gameTimelineFetch);
  tearDown(() => gameTimelineFetch = original);

  test('the retry schedule is 5 s, 15 s, then a minute', () {
    expect(gameTimelineRetryDelay(1), const Duration(seconds: 5));
    expect(gameTimelineRetryDelay(2), const Duration(seconds: 15));
    expect(gameTimelineRetryDelay(3), const Duration(seconds: 60));
    expect(gameTimelineRetryDelay(9), const Duration(seconds: 60));
    expect(kGameTimelineFetchTimeout, const Duration(seconds: 4));
  });

  test('failed reads retry at 5 s, 15 s, 60 s, 60 s; an answer resets it', () {
    fakeAsync((async) {
      final calls = <Duration>[];
      var answer = false;
      gameTimelineFetch = (id) async {
        calls.add(async.elapsed);
        return answer
            ? const GameTimelineSnapshot(known: true, observedSinceMs: 1)
            : null;
      };
      final container = ProviderContainer();
      final sub = container.listen(polyGameTimelineProvider('42'), (_, __) {});
      async.flushMicrotasks();
      expect(calls, [Duration.zero]);

      async.elapse(const Duration(seconds: 5));
      expect(calls.last, const Duration(seconds: 5));
      async.elapse(const Duration(seconds: 15));
      expect(calls.last, const Duration(seconds: 20));
      async.elapse(const Duration(seconds: 60));
      expect(calls.last, const Duration(seconds: 80));
      async.elapse(const Duration(seconds: 60));
      expect(calls.last, const Duration(seconds: 140));
      expect(calls, hasLength(5));

      // The backend answers: back to the live poll, and the next failure
      // starts the schedule over.
      answer = true;
      async.elapse(const Duration(seconds: 60));
      expect(calls.last, const Duration(seconds: 200));
      expect(container.read(polyGameTimelineProvider('42')).fromBackend, true);
      answer = false;
      async.elapse(const Duration(seconds: 20));
      expect(calls.last, const Duration(seconds: 220));
      async.elapse(const Duration(seconds: 5));
      expect(calls.last, const Duration(seconds: 225));
      expect(calls, hasLength(8));

      sub.close();
      container.dispose();
      async.flushTimers();
    });
  });
}
