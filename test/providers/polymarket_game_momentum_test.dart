// A live game's momentum read (polyGameMomentumProvider):
//
//   * which side is home and the totals line are inputs, not part of the
//     key: a change neither builds a new read nor reads the sides' price
//     history again, and the strip never goes back to loading;
//   * the sides' history is drawn without waiting for the totals line,
//     whose recent history is merged in when its token lands;
//   * the pressure signal reads the game from the backend's timeline
//     answer before the live feed has said anything about it.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/polymarket_game_momentum_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/services/polymarket/live_game/game_momentum.dart';
import 'package:kute/services/polymarket/live_game/game_pressure.dart';
import 'package:kute/services/polymarket/live_game/game_timeline.dart';

class _NoGames extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => const {};
  @override
  void connect() {}
}

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
}

PolyGameTimeline _timeline = PolyGameTimeline.empty;

class _Timeline extends PolyGameTimelineNotifier {
  @override
  PolyGameTimeline build(String arg) => _timeline;
}

const _min = 60000;

void main() {
  late MomentumHistoryRead original;
  late Map<String, int> reads;
  late Map<String, Completer<List<OddsPoint>?>> pending;
  late Map<String, List<OddsPoint>> histories;
  late ProviderContainer container;

  setUp(() {
    original = momentumHistoryRead;
    reads = {};
    pending = {};
    histories = {};
    _timeline = PolyGameTimeline.empty;
    momentumHistoryRead = (token, {required startSec, required endSec}) {
      reads[token] = (reads[token] ?? 0) + 1;
      final hold = pending[token];
      if (hold != null) return hold.future;
      return Future.value(histories[token]);
    };
    container = ProviderContainer(overrides: [
      livePriceProvider.overrideWith(_Prices.new),
      sportsLiveProvider.overrideWith(_NoGames.new),
      polyGameTimelineProvider.overrideWith(_Timeline.new),
    ]);
  });

  tearDown(() {
    container.dispose();
    momentumHistoryRead = original;
  });

  /// A live game that kicked off [minutes] ago, the sides' price flat at
  /// 0.40 until six minutes ago and then climbing steadily: pressure for
  /// side A on a quiet game.
  PolyMomentumKey liveGame(int now, {int minutes = 40}) {
    final start = now - minutes * _min;
    List<OddsPoint> climb(bool flip) => [
          for (var t = start - 5 * _min; t <= now; t += _min)
            () {
              final m = (now - t) ~/ _min;
              final p = m >= 6 ? 0.400 : 0.400 + (6 - m) * 0.007;
              return (tMs: t, p: flip ? 1 - p : p);
            }(),
        ];
    histories['a'] = climb(false);
    histories['b'] = climb(true);
    return (
      gameId: '42',
      tokenA: 'a',
      tokenB: 'b',
      startMs: start,
      endMs: null,
      axisMs: 90 * _min,
    );
  }

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('new inputs never re-read the sides or show loading again', () async {
    final key = liveGame(DateTime.now().millisecondsSinceEpoch);
    final states = <PolyGameMomentum>[];
    final sub = container.listen(polyGameMomentumProvider(key),
        (_, next) => states.add(next),
        fireImmediately: true);
    final notifier = container.read(polyGameMomentumProvider(key).notifier);
    notifier.updateInputs(aIsHome: null, overToken: null);
    await settle();
    expect(reads, {'a': 1, 'b': 1});
    expect(states.last.loaded, isTrue);
    expect(states.last.strip.isEmpty, isFalse);

    // The side's home flag lands, then flips; the totals line lands, then
    // moves to another line after a goal.
    notifier.updateInputs(aIsHome: true, overToken: null);
    await settle();
    notifier.updateInputs(aIsHome: false, overToken: 'over-46.5');
    await settle();
    notifier.updateInputs(aIsHome: false, overToken: 'over-47.5');
    await settle();
    // The same inputs again (a rebuild): nothing.
    notifier.updateInputs(aIsHome: false, overToken: 'over-47.5');
    await settle();

    expect(identical(container.read(polyGameMomentumProvider(key).notifier),
        notifier), isTrue);
    expect(reads, {'a': 1, 'b': 1, 'over-46.5': 1, 'over-47.5': 1});
    final firstLoaded = states.indexWhere((s) => s.loaded);
    expect(states.skip(firstLoaded).every((s) => s.loaded), isTrue,
        reason: 'once drawn, the strip never goes back to loading');
    sub.close();
  });

  test('the sides are drawn before the totals line resolves', () async {
    final key = liveGame(DateTime.now().millisecondsSinceEpoch);
    pending['over'] = Completer();
    final sub = container.listen(polyGameMomentumProvider(key), (_, __) {});
    final notifier = container.read(polyGameMomentumProvider(key).notifier);
    // No Over token known yet: the sides' history is read at once.
    notifier.updateInputs(aIsHome: true, overToken: null);
    await settle();
    var state = container.read(polyGameMomentumProvider(key));
    expect(state.loaded, isTrue);
    expect(state.strip.isEmpty, isFalse);

    // The token lands; its read is slow and holds nothing up.
    notifier.updateInputs(aIsHome: true, overToken: 'over');
    await settle();
    state = container.read(polyGameMomentumProvider(key));
    expect(state.loaded, isTrue);
    expect(state.strip.isEmpty, isFalse);
    expect(reads['over'], 1);

    pending['over']!.complete(const []);
    await settle();
    expect(container.read(polyGameMomentumProvider(key)).loaded, isTrue);
    expect(reads, {'a': 1, 'b': 1, 'over': 1});
    sub.close();
  });

  test('pressure reads the backend\'s view of the game before the feed '
      'speaks', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = liveGame(now);

    Future<PressureSignal?> pressureWith(PolyGameTimeline timeline) async {
      _timeline = timeline;
      final c = ProviderContainer(overrides: [
        livePriceProvider.overrideWith(_Prices.new),
        sportsLiveProvider.overrideWith(_NoGames.new),
        polyGameTimelineProvider.overrideWith(_Timeline.new),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(polyGameMomentumProvider(key), (_, __) {});
      c
          .read(polyGameMomentumProvider(key).notifier)
          .updateInputs(aIsHome: true, overToken: null);
      await settle();
      final pressure = c.read(polyGameMomentumProvider(key)).pressure;
      sub.close();
      return pressure;
    }

    // The feed has not spoken and the backend has not answered: no label.
    expect(
        await pressureWith(PolyGameTimeline(knownSinceMs: now - 60 * _min)),
        isNull);

    // The backend's answer: the game in play, level, quiet for an hour.
    final seeded = gameFeedFromSnapshot(
        '42',
        const GameTimelineSnapshot(
          known: true,
          live: true,
          league: 'epl',
          home: 'Arsenal',
          away: 'Chelsea',
          score: '0-0',
          period: '2H',
          status: 'InProgress',
        ));
    final pressure = await pressureWith(PolyGameTimeline(
        knownSinceMs: now - 60 * _min, fromBackend: true, feed: seeded));
    expect(pressure, isNotNull);
    expect(pressure!.side, PressureSide.a);
  });
}
