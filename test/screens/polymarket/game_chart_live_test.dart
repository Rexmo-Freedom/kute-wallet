// A live game's chart section, opened before Polymarket's sports feed has
// said anything about the game:
//
//   * the backend's timeline answer makes it a live game at once (teams,
//     score, period), so the momentum strip is there from the start;
//   * the strip does not wait for the totals line: it is drawn from the
//     sides' history and takes the Over token when it lands;
//   * neither the token landing nor the feed naming home and away builds
//     a new momentum read;
//   * the kickoff comes from the timeline answer's start time, so the
//     feed's own start time (the same one) arriving later keeps the read.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/providers/polymarket_game_momentum_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/polymarket/components/game_chart_section.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/polymarket/components/momentum_strip.dart';
import 'package:kute/services/polymarket/live_game/game_momentum.dart';
import 'package:kute/services/polymarket/live_game/game_timeline.dart';
import 'package:kute/theme/app_theme.dart';

const _min = 60000;

class _Games extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => const {};
  @override
  void connect() {}
  void push(SportsMatchUpdate u) => state = {'game:${u.gameId}': u};
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

int _builds = 0;
final _keys = <PolyMomentumKey>[];
final _inputs = <(bool?, String?)>[];

/// A momentum read that counts how often it is built and what inputs the
/// strip hands it.
class _Momentum extends PolyGameMomentumNotifier {
  @override
  PolyGameMomentum build(PolyMomentumKey arg) {
    _builds++;
    _keys.add(arg);
    return PolyGameMomentum(
      strip: buildMomentum(
        a: [
          for (var i = 0; i <= 60; i++)
            (tMs: i * _min, p: 0.5 + ((i % 7) - 3) / 50),
        ],
        startMs: 0,
        endMs: 60 * _min,
      ),
      loaded: true,
    );
  }

  @override
  void updateInputs({required bool? aIsHome, required String? overToken}) {
    if (_inputs.isEmpty || _inputs.last != (aIsHome, overToken)) {
      _inputs.add((aIsHome, overToken));
    }
  }
}

void main() {
  setUp(() {
    _builds = 0;
    _keys.clear();
    _inputs.clear();
  });

  testWidgets('the strip is up before the feed speaks and the totals line '
      'lands, and stays the same read', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now().millisecondsSinceEpoch;
    // Kicked off 50 minutes ago; the backend first saw it 70 minutes ago.
    final kickoff = now - 50 * _min;
    // The backend's answer: Arsenal at home, in the second half. Gamma's
    // event has no score or period yet.
    _timeline = PolyGameTimeline(
      knownSinceMs: now - 70 * _min,
      fromBackend: true,
      feed: gameFeedFromSnapshot(
          '42',
          GameTimelineSnapshot(
            known: true,
            live: true,
            league: 'epl',
            home: 'Arsenal',
            away: 'Chelsea',
            score: '1-0',
            period: '2H',
            status: 'InProgress',
            startTimeMs: kickoff,
          )),
    );
    const event = PolymarketEvent(
      id: '1',
      slug: 'epl-ars-che',
      title: 'Arsenal vs. Chelsea',
      volume: 0,
      liquidity: 0,
      category: 'sports',
      conditionId: '',
      outcomes: [],
      gameId: 42,
    );
    expect(event.isInPlay, isFalse);

    final over = Completer<String?>();
    final container = ProviderContainer(overrides: [
      livePriceProvider.overrideWith(_Prices.new),
      sportsLiveProvider.overrideWith(_Games.new),
      polyGameTimelineProvider.overrideWith(_Timeline.new),
      polyGameLinesProvider
          .overrideWith((ref, slug) => Completer<PolyGameLines>().future),
      polyGameOverTokenProvider.overrideWith((ref, slug) => over.future),
      polyGameMomentumProvider.overrideWith(_Momentum.new),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: PolyGameChartSection(
              event: event,
              chart: MarketChart(),
              teamA: 'Arsenal',
              teamB: 'Chelsea',
              winTokenA: 'a',
              winTokenB: 'b',
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    // Live from the backend's answer, with its sides: Arsenal (A) at home.
    // No Over token yet, and the strip is already there.
    expect(find.byType(PolyMomentumStrip), findsOneWidget);
    expect(_builds, 1);
    expect(_keys.single.startMs, kickoff,
        reason: 'the kickoff is the timeline answer\'s start time');
    expect(_inputs.last, (true, null));

    // The totals line lands: handed over, no new read.
    over.complete('over-2.5');
    await tester.pump();
    await tester.pump();
    expect(_inputs.last, (true, 'over-2.5'));
    expect(_builds, 1);

    // The feed speaks and has the sides the other way round: A is away
    // now. Still the same read.
    (container.read(sportsLiveProvider.notifier) as _Games).push(
        SportsMatchUpdate(
      slug: 'epl-che-ars',
      gameId: 42,
      live: true,
      ended: false,
      homeTeam: 'Chelsea',
      awayTeam: 'Arsenal',
      score: '0-1',
      period: '2H',
      leagueAbbreviation: 'epl',
      // The same kickoff, as the feed writes it.
      gameStartTime: DateTime.fromMillisecondsSinceEpoch(kickoff).toUtc(),
      updatedAt: DateTime.now(),
    ));
    await tester.pump();
    expect(_inputs.last, (false, 'over-2.5'));
    expect(_builds, 1, reason: 'the feed\'s start time keeps the key');
    expect(find.byType(PolyMomentumStrip), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
