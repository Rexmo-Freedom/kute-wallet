// Sports as polymarket.com/sports reads: Soccer drills one level further
// into its leagues ("‹ Soccer", All, LaLiga …), a sport or a league shows
// all of its markets in one list (founder, 9 November 2026: "Why are we
// separating games and props? Get rid of this props thing"): its games by
// day under Live, Today, Tomorrow and the date, then the markets that are
// not a match under "Futures"; no Games | Props switch. The league row's
// back pill brings the sports back with Soccer still on screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/tracking_service.dart';

import '../../helpers/offline_venue_overrides.dart';
import '../usd/investments_harness.dart';

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);

PolymarketEvent _game(String id, String series, DateTime kickoff,
        {String? score, String? period, double volume = 100}) =>
    PolymarketEvent(
      id: id,
      slug: id,
      title: '${id.toUpperCase()} Home vs. $id Away',
      volume: volume,
      volume24hr: volume,
      liquidity: 1e5,
      category: 'sports',
      conditionId: id,
      outcomes: [
        PolymarketOutcome(name: '${id.toUpperCase()} Home', price: 0.5),
        PolymarketOutcome(name: '$id Away', price: 0.5),
      ],
      teams: [
        PolymarketTeam(name: '${id.toUpperCase()} Home'),
        PolymarketTeam(name: '$id Away'),
      ],
      gameId: id.hashCode,
      startTime: kickoff,
      seriesId: series,
      score: score,
      period: period,
      tags: const ['sports', 'games', 'soccer'],
    );

PolymarketEvent _prop(String id, String title) => PolymarketEvent(
      id: id,
      slug: id,
      title: title,
      volume: 50,
      liquidity: 1e5,
      category: 'sports',
      conditionId: id,
      outcomes: const [
        PolymarketOutcome(name: 'Yes', price: 0.3),
        PolymarketOutcome(name: 'No', price: 0.7),
      ],
      tags: const ['sports', 'soccer'],
    );

/// LaLiga (10193) and the Premier League (10188) carry soccer's tag; NFL
/// is pinned on the Sports row.
const _directory = <Map<String, dynamic>>[
  {
    'sport': 'lal',
    'name': 'LaLiga',
    'image': null,
    'series': '10193',
    'tags': '1,780,100639,100350',
  },
  {
    'sport': 'epl',
    'name': 'Premier League',
    'image': null,
    'series': '10188',
    'tags': '1,82,306,100639,100350',
  },
  {
    'sport': 'nfl',
    'name': 'NFL',
    'image': null,
    'series': '12185',
    'tags': '1,450,100639',
  },
];

final _soccer = [
  // LaLiga is the most traded league here: the site's order still has the
  // Premier League first.
  _game('lal1', '10193', DateTime(_today.year, _today.month, _today.day, 23, 59),
      volume: 900),
  _game('epl1', '10188', _today.add(const Duration(days: 1, hours: 12)),
      volume: 100),
  _game('lal2', '10193', _today.add(const Duration(days: 5, hours: 12)),
      volume: 800),
  _game('epl2', '10188', _today.add(const Duration(days: 1, hours: 20)),
      volume: 50, score: '1-0', period: '2H'),
  _prop('golden-boot', 'Who wins the Golden Boot?'),
];

/// The sport's list, a league's list (LaLiga alone), every other list empty.
class _SoccerFeed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) {
    if (arg.pill != PolyPill.sports) return const PolyFeedState(done: true);
    return switch (arg.sub) {
      'soccer' => PolyFeedState(done: true, events: _soccer),
      'series:10193' => PolyFeedState(
          done: true, events: _soccer.where((e) => e.seriesId == '10193').toList()),
      _ => const PolyFeedState(done: true),
    };
  }
}

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

Finder _inBrowser(Finder f) =>
    find.descendant(of: find.byType(PolymarketScreen), matching: f);

/// A chip of the row by its label (never the back pill, which carries the
/// row's name too).
Finder _pill(String label) => _inBrowser(find.byWidgetPredicate((w) =>
    w is KutePill &&
    w.label == label &&
    w.key != const ValueKey('kute-back-pill')));

final _back = _inBrowser(find.byKey(const ValueKey('kute-back-pill')));

bool _selected(WidgetTester tester, String label) =>
    tester.widget<KutePill>(_pill(label)).selected;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The 22 sp day headings on screen, top to bottom.
List<String> _headings(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(_inBrowser(find.byWidgetPredicate(
          (w) => w is Text && w.style?.fontWeight == FontWeight.w800))))
        t.data!,
    ];

List<String> _cards(WidgetTester tester) => [
      for (final c
          in tester.widgetList<MarketCard>(_inBrowser(find.byType(MarketCard))))
        c.title,
    ];

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'Soccer drills into its leagues; games by day under their headings, '
      'the other markets after them in the same list; a league narrows; '
      'back brings the sports', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);

    await pumpInvestments(tester,
        browsePredictions: true,
        size: const Size(390, 2400),
        child: const Scaffold(body: PolymarketScreen()),
        overrides: [
          polyBrowseFeedProvider.overrideWith(_SoccerFeed.new),
          polySportsDirectoryProvider.overrideWith((_) async => _directory),
          polyLeagueRowsProvider
              .overrideWith((_) => Stream.value(const <Map<String, dynamic>>[])),
          polySportGroupLogosProvider
              .overrideWith((_) => Stream.value(const <String, String>{})),
          sportsLiveProvider.overrideWith(_Sports.new),
          ...offlineVenueOverrides,
        ]);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(PolymarketScreen)));
    // The directory lands.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    // Sports: Live, Futures, the pinned NFL, then the site's sports.
    await _tap(tester, _pill('Sports'));
    expect(tester.widget<KutePill>(_back).label, 'Sports');
    expect(_selected(tester, 'Live'), isTrue);
    expect(_pill('NFL'), findsOneWidget);
    expect(_pill('Soccer'), findsOneWidget);

    // Soccer: the row drills into its leagues, Soccer's own list on screen.
    await _tap(tester, _pill('Soccer'));
    expect(tester.widget<KutePill>(_back).label, 'Soccer');
    expect(_selected(tester, 'All'), isTrue);
    expect(container.read(polyBrowseSelectionProvider).sub, 'soccer');
    // The leagues in the site's order, whatever trades most in the list.
    expect(_pill('LaLiga'), findsOneWidget);
    expect(_pill('Premier League'), findsOneWidget);
    expect(_pill('Tennis'), findsNothing);
    final laliga = tester.getTopLeft(_pill('LaLiga'));
    expect(laliga.dx, greaterThan(tester.getTopLeft(_pill('Premier League')).dx));

    // One list, no Games | Props switch: the matches by day, then the
    // markets that are not a match under the Sports row's "Futures".
    expect(find.byType(KutePillTabs), findsNothing);
    expect(find.text('Props'), findsNothing);
    final far = _today.add(const Duration(days: 5));
    expect(_headings(tester), [
      'Live',
      'Today',
      'Tomorrow',
      DateFormat.MMMEd('en').format(far),
      'Futures',
    ]);
    expect(_cards(tester), [
      'EPL2 Home vs. epl2 Away',
      'LAL1 Home vs. lal1 Away',
      'EPL1 Home vs. epl1 Away',
      'LAL2 Home vs. lal2 Away',
      'Who wins the Golden Boot?',
    ]);

    // A league: its own list.
    await _tap(tester, _pill('LaLiga'));
    expect(container.read(polyBrowseSelectionProvider).sub, 'series:10193');
    expect(_selected(tester, 'LaLiga'), isTrue);
    expect(tester.widget<KutePill>(_back).label, 'Soccer');
    expect(_cards(tester),
        ['LAL1 Home vs. lal1 Away', 'LAL2 Home vs. lal2 Away']);
    expect(_headings(tester),
        ['Today', DateFormat.MMMEd('en').format(far)]);

    // Back: the sports, Soccer still on screen at its own list.
    await _tap(tester, _back);
    expect(tester.widget<KutePill>(_back).label, 'Sports');
    expect(_selected(tester, 'Soccer'), isTrue);
    expect(container.read(polyBrowseSelectionProvider).sub, 'soccer');
    expect(events.where((e) => e.$1 == 'category_row_back_tapped').last.$2, {
      'surface': 'predictions',
      'parent': 'sports',
      'subcategory': 'soccer',
    });
    expect(
        events.where((e) => e.$1 == 'category_pill_tapped').map((e) => e.$2),
        containsAll([
          {'section': 'sports'},
          {'section': 'sports', 'subcategory': 'soccer'},
          {'section': 'sports', 'subcategory': 'lal'},
        ]));

    await unmountInvestments(tester);
    await tester.pump(const Duration(seconds: 31));
  });
}
