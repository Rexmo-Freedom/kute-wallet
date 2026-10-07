// The Predictions position cards read their events in one batch: N cards,
// one request (ceil(N / 100) past a hundred); events the feed already
// holds need none; a failed batch leaves the cards as they are until the
// next open; a batch's events count for a minute.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show
        PolymarketPosition,
        polymarketActivePositionsProvider,
        polymarketClaimablePositionsProvider;
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/polymarket/components/position_card.dart';
import 'package:kute/screens/portfolio/poly_position_events.dart';
import 'package:kute/theme/app_theme.dart';

PolymarketEvent _event(String slug, {bool game = false}) => PolymarketEvent(
      id: 'id-$slug',
      slug: slug,
      title: game ? '49ers vs. Broncos' : 'Event $slug',
      volume: 0,
      liquidity: 0,
      category: game ? 'sports' : '',
      conditionId: 'c-$slug',
      outcomes: const [],
      gameId: game ? 77 : null,
      gameStart: game ? DateTime(2030, 10, 5, 20, 30) : null,
      teams: game
          ? const [
              PolymarketTeam(
                  name: 'Broncos', abbreviation: 'den', ordering: 'home'),
              PolymarketTeam(
                  name: '49ers', abbreviation: 'sf', ordering: 'away'),
            ]
          : const [],
    );

/// A fake batch read: records each request's slugs; answers with a game
/// for every slug unless [fail] is set.
class _Gamma {
  final calls = <List<String>>[];
  bool fail = false;

  Future<List<PolymarketEvent>> call(List<String> slugs) async {
    calls.add(List.of(slugs));
    if (fail) throw Exception('offline');
    return [for (final s in slugs) _event(s, game: true)];
  }
}

class _Clock {
  DateTime now = DateTime(2030, 1, 1, 12);
  DateTime call() => now;
}

class _NoGames extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => const {};
  @override
  void connect() {}
}

ProviderContainer _container(_Gamma gamma, _Clock clock,
    {Map<String, PolyFeedCachedEvent> feed = const {}}) {
  final c = ProviderContainer(overrides: [
    polyEventsBatchFetchProvider.overrideWithValue(gamma.call),
    polyEventsClockProvider.overrideWithValue(clock.call),
    polyFeedCacheLookupProvider.overrideWithValue((slug) => feed[slug]),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// Lets the batch's microtask and the fake read run.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<String> _slugs(int n) => [for (var i = 0; i < n; i++) 'slug-$i'];

PolymarketPosition _position(String slug) => PolymarketPosition(
      marketId: 'm-$slug',
      marketQuestion: 'Q $slug',
      outcome: 'Yes',
      size: 10,
      avgPrice: 0.5,
      currentPrice: 0.5,
      pnl: 0,
      pnlPercent: 0,
      isResolved: false,
      tokenId: 't-$slug',
      eventSlug: slug,
    );

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('15 positions: one request carrying every slug', () async {
    final gamma = _Gamma();
    final c = _container(gamma, _Clock());
    final slugs = _slugs(15);
    // As on the Portfolio: the screen asks for all, each card for its own.
    c.read(polyPositionEventsProvider.notifier).want(slugs, retry: true);
    for (final s in slugs) {
      c.listen(polyPositionEventProvider(s), (_, __) {});
    }
    await _settle();
    expect(gamma.calls, hasLength(1));
    expect(gamma.calls.single.toSet(), slugs.toSet());
    for (final s in slugs) {
      expect(c.read(polyPositionEventProvider(s))?.slug, s);
    }
  });

  test('the Portfolio prefetch: one request for every position', () async {
    final gamma = _Gamma();
    final c = ProviderContainer(overrides: [
      polyEventsBatchFetchProvider.overrideWithValue(gamma.call),
      polyFeedCacheLookupProvider.overrideWithValue((_) => null),
      polymarketActivePositionsProvider
          .overrideWith((_) => [for (final s in _slugs(14)) _position(s)]),
      polymarketClaimablePositionsProvider
          .overrideWith((_) => [_position('claim-me')]),
    ]);
    addTearDown(c.dispose);
    c.listen(polyPortfolioEventsPrefetchProvider, (_, __) {});
    await _settle();
    expect(gamma.calls, hasLength(1));
    expect(gamma.calls.single, hasLength(15));
  });

  test('past a hundred slugs: ceil(N / 100) requests', () async {
    final gamma = _Gamma();
    final c = _container(gamma, _Clock());
    c.read(polyPositionEventsProvider.notifier).want(_slugs(250));
    await _settle();
    expect(gamma.calls.map((s) => s.length), [100, 100, 50]);
    expect(c.read(polyPositionEventsProvider), hasLength(250));
  });

  test('events the feed holds are drawn at once and not asked for', () async {
    final gamma = _Gamma();
    final clock = _Clock();
    final c = _container(gamma, clock, feed: {
      // A market: its title and teams do not move, any snapshot will do.
      'market': (
        event: _event('market'),
        savedAt: clock.now.subtract(const Duration(days: 1))
      ),
      // A game the feed saw seconds ago.
      'fresh-game': (
        event: _event('fresh-game', game: true),
        savedAt: clock.now.subtract(const Duration(seconds: 20))
      ),
      // A game from yesterday's snapshot: drawn, but read again.
      'old-game': (
        event: _event('old-game', game: true),
        savedAt: clock.now.subtract(const Duration(days: 1))
      ),
    });
    for (final s in ['market', 'fresh-game', 'old-game', 'unknown']) {
      c.listen(polyPositionEventProvider(s), (_, __) {});
    }
    // Before any request lands, the feed's copies are already there.
    expect(c.read(polyPositionEventProvider('market'))?.slug, 'market');
    expect(c.read(polyPositionEventProvider('old-game'))?.slug, 'old-game');
    expect(c.read(polyPositionEventProvider('unknown')), isNull);
    await _settle();
    expect(gamma.calls, hasLength(1));
    expect(gamma.calls.single.toSet(), {'old-game', 'unknown'});
    expect(c.read(polyPositionEventProvider('unknown'))?.slug, 'unknown');
  });

  test('a failed batch is not asked again until the next open', () async {
    final gamma = _Gamma()..fail = true;
    final c = _container(gamma, _Clock());
    final notifier = c.read(polyPositionEventsProvider.notifier);
    final sub = c.listen(polyPositionEventProvider('a'), (_, __) {});
    await _settle();
    expect(gamma.calls, hasLength(1));
    expect(c.read(polyPositionEventProvider('a')), isNull);

    // A rebuild (a price tick) does not ask again.
    notifier.want(['a']);
    await _settle();
    expect(gamma.calls, hasLength(1));

    // The next open (the card mounting again) does, and the card updates.
    gamma.fail = false;
    sub.close();
    await _settle();
    c.listen(polyPositionEventProvider('a'), (_, __) {});
    await _settle();
    expect(gamma.calls, hasLength(2));
    expect(c.read(polyPositionEventProvider('a'))?.slug, 'a');
  });

  test('pull-to-refresh retries the failed slugs', () async {
    final gamma = _Gamma()..fail = true;
    final c = _container(gamma, _Clock());
    final notifier = c.read(polyPositionEventsProvider.notifier);
    notifier.want(['a', 'b'], retry: true);
    await _settle();
    gamma.fail = false;
    notifier.retry();
    await _settle();
    expect(gamma.calls, hasLength(2));
    expect(gamma.calls.last.toSet(), {'a', 'b'});
    expect(c.read(polyPositionEventsProvider).keys.toSet(), {'a', 'b'});
  });

  test('a batch counts for 60 s, then is read again', () async {
    final gamma = _Gamma();
    final clock = _Clock();
    final c = _container(gamma, clock);
    final notifier = c.read(polyPositionEventsProvider.notifier);
    notifier.want(['a', 'b'], retry: true);
    await _settle();
    expect(gamma.calls, hasLength(1));

    clock.now = clock.now.add(const Duration(seconds: 59));
    notifier.want(['a', 'b'], retry: true);
    await _settle();
    expect(gamma.calls, hasLength(1));

    clock.now = clock.now.add(const Duration(seconds: 2));
    notifier.want(['a', 'b'], retry: true);
    // Past the window the old events stay drawn until the new ones land.
    expect(c.read(polyPositionEventsProvider).keys.toSet(), {'a', 'b'});
    await _settle();
    expect(gamma.calls, hasLength(2));
  });

  testWidgets('cards draw their fallback, then the batch, in one request',
      (tester) async {
    tester.view.physicalSize = const Size(390, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gamma = _Gamma();
    final slugs = _slugs(15);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        polyEventsBatchFetchProvider.overrideWithValue(gamma.call),
        polyFeedCacheLookupProvider.overrideWithValue((_) => null),
        sportsLiveProvider.overrideWith(_NoGames.new),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            extensions: [AppColorsExtension.light()],
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(children: [
              for (final s in slugs)
                PolyPositionCard(
                  question: 'Q $s',
                  outcome: '49ers',
                  shares: 10,
                  avgPrice: 0.5,
                  value: 5,
                  pnl: 0,
                  eventSlug: s,
                ),
            ]),
          ),
        ),
      ),
    ));
    // First frame: the market's own title, no spinner.
    expect(find.text('Q slug-0'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump();
    await tester.pump();
    expect(gamma.calls, hasLength(1));
    // The batch landed: each card cross-fades to its game's team rows.
    await tester.pumpAndSettle();
    expect(find.text('Q slug-0'), findsNothing);
    expect(find.text('Broncos'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed batch leaves the cards as they were', (tester) async {
    final gamma = _Gamma()..fail = true;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        polyEventsBatchFetchProvider.overrideWithValue(gamma.call),
        polyFeedCacheLookupProvider.overrideWithValue((_) => null),
        sportsLiveProvider.overrideWith(_NoGames.new),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: PolyPositionCard(
              question: '49ers vs. Broncos',
              outcome: '49ers',
              shares: 10,
              avgPrice: 0.5,
              value: 5,
              pnl: 0,
              eventSlug: 'nfl-sf-den',
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(gamma.calls, hasLength(1));
    // The plain market shape: the title, no team rows.
    expect(find.text('49ers vs. Broncos'), findsOneWidget);
    expect(find.text('Broncos'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
