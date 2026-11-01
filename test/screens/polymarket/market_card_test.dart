// The Predictions list card: a game (a row per team), and since the
// declutter (founder, 1 November 2026) a single Yes/No market or an event
// with many outcomes as ONE row: the image, the question, one quiet line
// of who leads. No gauge, pills, bars, meta line or "+N more".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, MarketCard card) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [card]),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// A live figure on the card: it rolls its digits ([RollingNumberText]),
/// so it is found by the figure it shows, not as one Text.
Finder _rolled(String text) => find.byWidgetPredicate(
    (w) => w is RollingNumberText && w.text == text,
    description: 'rolling figure "$text"');

/// A score on the card ([ScorePulseText]: its numbers pulse on a goal).
Finder _score(String text) => find.byWidgetPredicate(
    (w) => w is ScorePulseText && w.text == text,
    description: 'score "$text"');

const _teams = [
  PolymarketOutcome(name: 'Broncos', price: 0.36),
  PolymarketOutcome(name: '49ers', price: 0.64),
];

void main() {
  testWidgets('a game before kickoff: a row per team with its win chance',
      (tester) async {
    var taps = 0;
    await _pump(
      tester,
      MarketCard(
        title: 'Broncos vs. 49ers',
        outcomes: _teams,
        volume: 6200000,
        category: 'sports',
        gameStart: DateTime(2030, 10, 5, 20, 30),
        onTap: () => taps++,
      ),
    );
    expect(find.text('Broncos'), findsOneWidget);
    expect(find.text('49ers'), findsOneWidget);
    expect(_rolled('36%'), findsOneWidget);
    expect(_rolled('64%'), findsOneWidget);
    // The teams are the rows: the title is not written again.
    expect(find.text('Broncos vs. 49ers'), findsNothing);
    expect(find.textContaining('outcomes'), findsNothing);
    expect(find.text('5 Oct 20:30'), findsOneWidget);
    expect(find.textContaining('6.2M vol'), findsOneWidget);

    // The likelier side reads in the primary colour, the other quieter.
    final c = AppColorsExtension.light();
    expect(tester.widget<Text>(find.text('49ers')).style!.color,
        c.textPrimary);
    expect(tester.widget<Text>(find.text('Broncos')).style!.color,
        c.textSecondary);

    await tester.tap(find.byType(MarketCard));
    expect(taps, 1);
  });

  testWidgets('a game in play: each score on its team\'s row, clock below',
      (tester) async {
    await _pump(
      tester,
      const MarketCard(
        title: 'Broncos vs. 49ers',
        outcomes: _teams,
        volume: 1000,
        category: 'sports',
        liveGame: PolyLiveGame(
          score: '3-0',
          clock: 'Q2 10:28',
          period: 'Q2',
          firstIsHome: false,
        ),
      ),
    );
    // Home first in the feed, away first in the title: Broncos 0, 49ers 3.
    final broncos = tester.getCenter(find.text('Broncos')).dy;
    expect(tester.getCenter(_score('0')).dy, closeTo(broncos, 4));
    expect(tester.getCenter(_score('3')).dy,
        closeTo(tester.getCenter(find.text('49ers')).dy, 4));
    // Both scores end on the same edge.
    expect(tester.getTopRight(_score('0')).dx,
        tester.getTopRight(_score('3')).dx);
    expect(find.text('Q2 10:28'), findsOneWidget);
    expect(_rolled('36%'), findsOneWidget);
  });

  testWidgets('a finished three-way game says Final and keeps the draw',
      (tester) async {
    await _pump(
      tester,
      const MarketCard(
        title: 'Arsenal vs Chelsea',
        outcomes: [
          PolymarketOutcome(
              name: 'Will Arsenal win?', price: 0.52, noTokenId: 'a'),
          PolymarketOutcome(
              name: 'Draw (Arsenal vs Chelsea)', price: 0.27, noTokenId: 'd'),
          PolymarketOutcome(
              name: 'Will Chelsea win?', price: 0.21, noTokenId: 'b'),
        ],
        volume: 0,
        category: 'sports',
        liveGame: PolyLiveGame(score: '2-1', firstIsHome: true, finished: true),
      ),
    );
    expect(find.text('Arsenal'), findsOneWidget);
    expect(find.text('Chelsea'), findsOneWidget);
    expect(find.text('Final · Draw 27%'), findsOneWidget);
  });

  testWidgets('a Yes/No market: one row, the question and who leads',
      (tester) async {
    var taps = 0;
    await _pump(
      tester,
      MarketCard(
        title: 'Will it rain in Lisbon?',
        outcomes: const [
          PolymarketOutcome(name: 'Yes', price: 0.24),
          PolymarketOutcome(name: 'No', price: 0.76),
        ],
        volume: 1500,
        category: 'weather',
        endDate: DateTime(2030, 12, 31),
        onTap: () => taps++,
      ),
    );
    expect(find.text('Will it rain in Lisbon?'), findsOneWidget);
    // The likelier side and its chance, one quiet line.
    final line = find.byKey(const ValueKey('poly-row-leader'));
    expect(tester.widget<Text>(line).data, 'No · 76%');
    final c = AppColorsExtension.light();
    expect(tester.widget<Text>(line).style?.color, c.textSecondary);
    // Nothing else: no gauge figure, no pills, no meta line.
    expect(_rolled('24%'), findsNothing);
    expect(find.textContaining('¢'), findsNothing);
    expect(find.textContaining('Closes'), findsNothing);
    expect(find.textContaining(r'$1.5K'), findsNothing);
    expect(find.byType(CustomPaint, skipOffstage: false).evaluate().where(
        (e) => (e.widget as CustomPaint).painter != null), isEmpty);
    // One row, 64 px at least (the test font wraps this question to two
    // lines).
    expect(tester.getSize(find.byType(MarketCard)).height,
        greaterThanOrEqualTo(kPolyRowHeight.w - 0.5));
    // The whole row taps through.
    await tester.tap(find.text('Will it rain in Lisbon?'));
    expect(taps, 1);
  });

  testWidgets('Yes leads when it is likelier; a longshot reads <1%',
      (tester) async {
    await _pump(
      tester,
      const MarketCard(
        title: 'Will it rain in Lisbon?',
        outcomes: [
          PolymarketOutcome(name: 'Yes', price: 0.99),
          PolymarketOutcome(name: 'No', price: 0.01),
        ],
        volume: 0,
        category: 'weather',
      ),
    );
    expect(find.text('Yes · 99%'), findsOneWidget);
    expect(
        polyRowLeaderLine(lookupAppLocalizations(const Locale('en')), const [
          PolymarketOutcome(name: 'Yes', price: 0.997),
          PolymarketOutcome(name: 'No', price: 0.003),
        ]),
        'Yes · >99%');
  });

  testWidgets('a long question takes two lines at most', (tester) async {
    await _pump(
      tester,
      const MarketCard(
        title: 'Will the European Central Bank cut its deposit rate by '
            'fifty basis points or more at its December meeting this year?',
        outcomes: [
          PolymarketOutcome(name: 'Yes', price: 0.3),
          PolymarketOutcome(name: 'No', price: 0.7),
        ],
        volume: 0,
        category: 'economy',
      ),
    );
    final title = tester.widget<Text>(find.textContaining('European'));
    expect(title.maxLines, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('many outcomes: the question and the top outcome leading, '
      'no bars and no "+N more"', (tester) async {
    await _pump(
      tester,
      const MarketCard(
        title: 'World Cup winner',
        outcomes: [
          PolymarketOutcome(name: 'Portugal', price: 0.16, noTokenId: 'p'),
          PolymarketOutcome(name: 'Spain', price: 0.84, noTokenId: 's'),
          PolymarketOutcome(name: 'France', price: 0.05, noTokenId: 'f'),
          PolymarketOutcome(name: 'Brazil', price: 0.02, noTokenId: 'b'),
        ],
        volume: 0,
        category: 'sports',
      ),
    );
    expect(find.text('World Cup winner'), findsOneWidget);
    expect(find.text('Spain leads · 84%'), findsOneWidget);
    expect(find.text('Portugal'), findsNothing);
    expect(find.text('16%'), findsNothing);
    expect(find.text('+1 more'), findsNothing);
    expect(find.textContaining('outcomes'), findsNothing);
    expect(tester.getSize(find.byType(MarketCard)).height,
        moreOrLessEquals(kPolyRowHeight.w, epsilon: 1));
  });

  testWidgets(
      'in a group a market has no card of its own and keeps its ink; alone '
      'it is the card', (tester) async {
    MarketCard yesNo({required bool inGroup}) => MarketCard(
          title: 'Will it rain?',
          outcomes: const [
            PolymarketOutcome(name: 'Yes', price: 0.4),
            PolymarketOutcome(name: 'No', price: 0.6),
          ],
          volume: 1000,
          category: 'weather',
          onTap: () {},
          inGroup: inGroup,
        );
    final block = find.byType(MarketCard);
    bool hasCard() {
      final card = AppDecorations.card(tester.element(block));
      return tester
          .widgetList<Container>(
              find.descendant(of: block, matching: find.byType(Container)))
          .any((c) => c.decoration == card);
    }

    await _pump(tester, yesNo(inGroup: false));
    expect(hasCard(), isTrue);
    await _pump(tester, yesNo(inGroup: true));
    expect(hasCard(), isFalse);
    final ink = find.descendant(of: block, matching: find.byType(InkWell));
    expect(tester.getSize(ink.first), tester.getSize(block));
    // The title starts where the group's hairline does (the test frame
    // adds its own 16 side padding).
    expect(
        tester.getTopLeft(find.text('Will it rain?')).dx -
            tester.getTopLeft(block).dx,
        moreOrLessEquals(polyGroupRowIndent(), epsilon: 0.5));
  });

  test('a market and an event with many outcomes are grouped; a game is '
      'not', () {
    const yesNo = [
      PolymarketOutcome(name: 'Yes', price: 0.4),
      PolymarketOutcome(name: 'No', price: 0.6),
    ];
    expect(polyCardGroups('Will it rain?', yesNo), isTrue);
    expect(polyCardGroups('Broncos vs. 49ers', _teams), isFalse);
    expect(
        polyCardGroups('Who wins?', const [
          PolymarketOutcome(
              name: 'A', price: 0.5, conditionId: 'a', tokenId: 'a'),
          PolymarketOutcome(
              name: 'B', price: 0.3, conditionId: 'b', tokenId: 'b'),
          PolymarketOutcome(
              name: 'C', price: 0.2, conditionId: 'c', tokenId: 'c'),
        ]),
        isTrue);
  });
}

