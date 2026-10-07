// A football match's Exact Score as a score list: the score alone on each
// row, sections by result, most likely first, "Any other score" last, the
// rest folded behind "Show N more", and no "37.5%" for an empty book.
// Run on a real Gamma event (exact_score_fixture.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/polymarket/components/exact_score_list.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/theme/app_theme.dart';

import 'exact_score_fixture.dart';

class _NoStars extends PolyWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _NoGames extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => const {};
  @override
  void connect() {}
}

class _NoTimeline extends PolyGameTimelineNotifier {
  @override
  PolyGameTimeline build(String arg) => PolyGameTimeline.empty;
}

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState(live: true);
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void acquire() {}
  @override
  void release() {}
  void tick(String token, double p) => state = state.copyWithPrice(token, p);
  void wide(String token) => state = state.copyWithUnpriced({token});
}

PolymarketEvent exactScoreEvent() =>
    PolymarketModel().parseEventsRaw([exactScoreEventRaw()]).single;

PolymarketOutcome _o(String name, double price, {bool unpriced = false}) =>
    PolymarketOutcome(
        name: name, price: price, tokenId: name, unpriced: unpriced);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('reading a score', () {
    test('home goals first, whatever the team names', () {
      expect(polyParseExactScore('Tottenham Hotspur FC 4 - 5 Coventry City FC'),
          (home: 4, away: 5));
      expect(polyParseExactScore('Schalke 04 2 - 1 Bayer 04 Leverkusen'),
          (home: 2, away: 1));
      expect(polyParseExactScore('Exact Score: Spurs 0 - 0 Coventry?'),
          (home: 0, away: 0));
      expect(polyParseExactScore('Any Other Score'), isNull);
      expect(polyParseExactScore('O/U 2.5'), isNull);
    });

    test('the catch-all', () {
      expect(polyIsAnyOtherScore('Any Other Score'), isTrue);
      expect(polyIsAnyOtherScore('Exact Score: Any Other Score?'), isTrue);
      expect(polyIsAnyOtherScore('Tottenham 1 - 0 Coventry'), isFalse);
    });

    test('an Exact Score event, by its type or by its title', () {
      expect(polyIsExactScoreList(exactScoreEvent().outcomes), isTrue);
      final untyped = [
        _o('A 1 - 0 B', 0.1),
        _o('A 0 - 0 B', 0.1),
        _o('Any Other Score', 0.1),
      ];
      expect(polyIsExactScoreList(untyped, title: 'A vs. B - Exact Score'),
          isTrue);
      expect(polyIsExactScoreList(untyped, title: 'A vs. B'), isFalse);
      expect(
          polyIsExactScoreList([_o('Yes', 0.5), _o('No', 0.5), _o('x', 0)],
              title: 'Exact Score'),
          isFalse);
    });
  });

  group('the layout', () {
    test('sections by result, most likely first, the catch-all last', () {
      final rows = [
        _o('Any Other Score', 0.30),
        _o('A 0 - 1 B', 0.08),
        _o('A 1 - 1 B', 0.12),
        _o('A 2 - 0 B', 0.09),
        _o('A 1 - 0 B', 0.11),
        _o('A 0 - 0 B', 0.10),
        _o('A 0 - 2 B', 0.05),
      ];
      final l = polyExactScoreSections(rows, (o) => o.price);
      expect(l.headed, isTrue);
      expect(l.hidden, 0);
      expect([
        for (final s in l.sections) s.group
      ], [
        PolyScoreGroup.home,
        PolyScoreGroup.draw,
        PolyScoreGroup.away,
        PolyScoreGroup.other,
      ]);
      expect([for (final o in l.sections[0].rows) o.name],
          ['A 1 - 0 B', 'A 2 - 0 B']);
      expect([for (final o in l.sections[1].rows) o.name],
          ['A 1 - 1 B', 'A 0 - 0 B']);
      expect([for (final o in l.sections[2].rows) o.name],
          ['A 0 - 1 B', 'A 0 - 2 B']);
      // Pinned last though it is the most likely row.
      expect(l.sections.last.rows.single.name, 'Any Other Score');
    });

    test('a short list has no headings', () {
      final l = polyExactScoreSections(
          [_o('A 1 - 0 B', 0.5), _o('A 0 - 0 B', 0.3), _o('A 0 - 1 B', 0.2)],
          (o) => o.price);
      expect(l.headed, isFalse);
      expect([for (final o in l.sections.single.rows) o.name],
          ['A 1 - 0 B', 'A 0 - 0 B', 'A 0 - 1 B']);
    });

    test('no chance to show sorts last and stays folded', () {
      final event = exactScoreEvent();
      double? chance(PolymarketOutcome o) => o.unpriced ? null : o.price;
      final l = polyExactScoreSections(event.outcomes, chance);
      final shown = [
        for (final s in l.sections)
          if (s.group != PolyScoreGroup.other) ...s.rows
      ];
      // The eight most likely of the nine priced scores.
      expect(shown.length, 8);
      expect(shown.every((o) => !o.unpriced), isTrue);
      expect(l.hidden, 36 - 8);
      expect(shown.first.name, 'Tottenham Hotspur FC 2 - 0 Coventry City FC');
      expect(l.sections.last.rows.single.name, 'Any Other Score');

      final open =
          polyExactScoreSections(event.outcomes, chance, expanded: true);
      expect(open.hidden, 0);
      final away =
          open.sections.firstWhere((s) => s.group == PolyScoreGroup.away).rows;
      // Priced first (2–5 at 4%), the "—" rows after it.
      expect(away.first.name, 'Tottenham Hotspur FC 2 - 5 Coventry City FC');
      expect(away.skip(1).every((o) => o.unpriced), isTrue);
    });

    test('a fold never hides a single row', () {
      final rows = [
        for (var i = 0; i < 9; i++) _o('A $i - 0 B', 0.5 - i * 0.01),
      ];
      expect(polyExactScoreSections(rows, (o) => o.price).hidden, 0);
    });
  });

  group('a game sub-market\'s row name', () {
    const title = 'Tottenham Hotspur FC vs. Coventry City FC - More Markets';
    test('drops the fixture the header already names', () {
      expect(
          polyStripEventPrefix(
              'Tottenham Hotspur FC vs. Coventry City FC: O/U 2.5', title),
          'O/U 2.5');
      expect(
          polyStripEventPrefix(
              'Tottenham Hotspur FC vs. Coventry City FC: Tottenham '
              'Hotspur FC O/U 1.5',
              title),
          'Tottenham Hotspur FC O/U 1.5');
      expect(
          polyStripEventPrefix(
              'tottenham hotspur fc vs. coventry city fc: Both Teams to Score',
              'Tottenham Hotspur FC vs. Coventry City FC'),
          'Both Teams to Score');
    });

    test('keeps any other name whole', () {
      expect(polyStripEventPrefix('Spread: Tottenham Hotspur FC (-1.5)', title),
          'Spread: Tottenham Hotspur FC (-1.5)');
      expect(polyStripEventPrefix('Draw', title), 'Draw');
      expect(
          polyStripEventPrefix(
              'Tottenham Hotspur FC vs. Coventry City FC', title),
          'Tottenham Hotspur FC vs. Coventry City FC');
    });
  });

  Future<_Prices> pumpSheet(WidgetTester tester, PolymarketEvent event) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prices = _Prices();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        livePriceProvider.overrideWith(() => prices),
        sportsLiveProvider.overrideWith(_NoGames.new),
        polyGameTimelineProvider.overrideWith(_NoTimeline.new),
        polyGameLinesProvider
            .overrideWith((ref, slug) async => PolyGameLines.empty),
        polymarketActivePositionsProvider.overrideWithValue(const []),
        polymarketClaimablePositionsProvider.overrideWithValue(const []),
        aiEnabledProvider.overrideWith((ref) async => false),
        polyWatchlistProvider.overrideWith(_NoStars.new),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MarketDetailSheet(event: event),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return prices;
  }

  Finder figure(String token, String text) => find.byWidgetPredicate(
      (w) => w is RollingFigure && w.identity == token && w.text == text);

  testWidgets(
      'the sheet lists scores, not fixtures, and opens a score as '
      'today', (tester) async {
    await http.runWithClient(() async {
      final event = exactScoreEvent();
      final prices = await pumpSheet(tester, event);
      expect(find.byType(PolyExactScoreList), findsOneWidget);
      // No row repeats the fixture.
      expect(find.textContaining('Coventry City FC 2'), findsNothing);
      expect(find.text('TOTTENHAM HOTSPUR FC'), findsOneWidget);
      expect(find.text('DRAW'), findsOneWidget);
      expect(find.text('OTHER'), findsOneWidget);
      expect(find.text('TOT'), findsOneWidget);
      expect(find.text('COV'), findsOneWidget);
      // 2–0 (es5) leads at 10%; 0–5 (es15, an ask alone at 74¢) is
      // folded, never 37%.
      expect(figure('es5y', '10%'), findsOneWidget);
      expect(figure('es15y', '37%'), findsNothing);
      expect(figure('es36y', '1%'), findsOneWidget);
      expect(find.text('Show 28 more'), findsOneWidget);

      await tester.tap(find.text('Show 28 more'));
      await tester.pump();
      expect(find.text('Show 28 more'), findsNothing);
      await tester.scrollUntilVisible(figure('es15y', '—'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(figure('es15y', '—'), findsOneWidget);

      // The feed: a trade gives a "—" row its price; a book gone wide
      // takes a price away.
      prices.tick('es15y', 0.02);
      await tester.pump(const Duration(seconds: 1));
      expect(figure('es15y', '2%'), findsOneWidget);
      prices.wide('es5y');
      await tester.pump(const Duration(seconds: 1));
      expect(figure('es5y', '10%'), findsNothing);

      // A row opens that score's own Yes / No sheet, as the plain list did.
      await tester.scrollUntilVisible(find.text('Any Other Score'), -200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Any Other Score'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final opened = tester
          .widgetList<MarketDetailSheet>(find.byType(MarketDetailSheet))
          .map((w) => w.event)
          .where((e) => e.isSyntheticBinary)
          .single;
      expect(opened.title, 'Any Other Score');
      expect(opened.outcomes.first.tokenId, 'es36y');
      expect(opened.outcomes.last.tokenId, 'es36n');
      // Opening records the market for analytics on a short timer.
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });
}
