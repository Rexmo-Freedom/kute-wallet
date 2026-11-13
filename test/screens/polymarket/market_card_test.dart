// The Predictions list card in its three shapes: a game, a single Yes/No
// market, an event with many outcomes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart'
    show polymarketCentsLabel;
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/polymarket/components/outcome_leading.dart'
    show kPolyOutcomeColors, polyChartedOutcomes;
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, MarketCard card,
    {bool dark = false}) async {
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
          brightness: dark ? Brightness.dark : Brightness.light,
          extensions: [
            dark ? AppColorsExtension.dark() : AppColorsExtension.light()
          ],
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
    // The kickoff stays (nothing else says when it is played); no
    // volume on a list card.
    expect(find.text('5 Oct 20:30'), findsOneWidget);
    expect(find.textContaining('6.2M'), findsNothing);

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
    // In play the card leads with the live dot and the clock.
    expect(find.text('Live · Q2 10:28'), findsOneWidget);
    expect(
        tester.getTopLeft(find.text('Live · Q2 10:28')).dy,
        lessThan(broncos));
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

  testWidgets('a Yes/No market: the Yes chance and the day\'s move',
      (tester) async {
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
        dayMove: 0.06,
      ),
    );
    expect(find.text('Will it rain in Lisbon?'), findsOneWidget);
    expect(_rolled('24%'), findsOneWidget);
    expect(_rolled('76%'), findsNothing);
    // No meta line (no closing date, no volume), and the two side pills.
    expect(find.textContaining('today'), findsNothing);
    expect(find.textContaining('2030'), findsNothing);
    expect(find.textContaining(r'$1.5K'), findsNothing);
    expect(find.text('Yes ${polymarketCentsLabel(0.24)}'), findsOneWidget);
    expect(find.text('No ${polymarketCentsLabel(0.76)}'), findsOneWidget);
    // The pills are quiet: the side's market colour as ink on the
    // neutral surface, no solid green / red block and no tint.
    final c = AppColorsExtension.light();
    final yes = tester.widget<Text>(find.text('Yes ${polymarketCentsLabel(0.24)}'));
    final no = tester.widget<Text>(find.text('No ${polymarketCentsLabel(0.76)}'));
    expect(yes.style?.color, AppColors.marketUp);
    expect(no.style?.color, AppColors.marketDown);
    expect(yes.style?.fontWeight, FontWeight.w600);
    final yesPill = tester.widget<Container>(find.ancestor(
        of: find.text('Yes ${polymarketCentsLabel(0.24)}'),
        matching: find.byType(Container)).first);
    final noPill = tester.widget<Container>(find.ancestor(
        of: find.text('No ${polymarketCentsLabel(0.76)}'),
        matching: find.byType(Container)).first);
    expect((yesPill.decoration as BoxDecoration).color, c.surfaceLight);
    expect((noPill.decoration as BoxDecoration).color, c.surfaceLight);
    // The two answers are the card's base: full width, 36 tall.
    expect(tester.getSize(find.byWidget(yesPill)).height,
        moreOrLessEquals(36.h, epsilon: 0.5));
    // Both pills sit on one line and share it.
    expect(tester.getTopLeft(find.byWidget(yesPill)).dy,
        tester.getTopLeft(find.byWidget(noPill)).dy);
    expect(tester.getSize(find.byWidget(yesPill)).width,
        moreOrLessEquals(tester.getSize(find.byWidget(noPill)).width,
            epsilon: 0.5));
    // The day's move under the gauge's number, not on the meta line.
    expect(find.text('▲ 6'), findsOneWidget);
  });

  testWidgets('a flat or unknown day shows no move', (tester) async {
    await _pump(
      tester,
      const MarketCard(
        title: 'Will it rain in Lisbon?',
        outcomes: [
          PolymarketOutcome(name: 'Yes', price: 0.003),
          PolymarketOutcome(name: 'No', price: 0.997),
        ],
        volume: 0,
        category: 'weather',
        dayMove: 0.001,
      ),
    );
    expect(_rolled('<1%'), findsOneWidget);
    expect(find.textContaining('today'), findsNothing);
  });

  testWidgets('many outcomes: the three most likely, each with its chance '
      'bar, and how many more', (tester) async {
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
    expect(find.text('Spain'), findsOneWidget);
    expect(find.text('84%'), findsOneWidget);
    expect(find.text('Portugal'), findsOneWidget);
    expect(find.text('16%'), findsOneWidget);
    expect(find.text('France'), findsOneWidget);
    expect(find.text('5%'), findsOneWidget);
    expect(find.text('Brazil'), findsNothing);
    expect(find.text('+1 more'), findsOneWidget);
    expect(find.textContaining('outcomes'), findsNothing);
    // A thin bar per row, filled to the outcome's chance, in order.
    final bars = tester
        .widgetList<PolyOutcomeChanceBar>(find.byType(PolyOutcomeChanceBar))
        .map((b) => b.fraction)
        .toList();
    expect(bars, [0.84, 0.16, 0.05]);
    expect(tester.getSize(find.byType(PolyOutcomeChanceBar).first).height, 6);
    // No token, so no line on the chart: the neutral fill.
    expect(
        tester
            .widgetList<PolyOutcomeChanceBar>(find.byType(PolyOutcomeChanceBar))
            .map((b) => b.color),
        [null, null, null]);
    // The figures end on one edge, so the bars do too.
    expect(tester.getTopRight(find.text('84%')).dx,
        tester.getTopRight(find.text('5%')).dx);
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

  test('only a plain Yes/No market is grouped', () {
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
        isFalse);
  });
  for (final dark in [false, true]) {
    testWidgets(
        'many outcomes (${dark ? 'dark' : 'light'}): each bar in its '
        "outcome's chart line colour, in the chart's order", (tester) async {
      const outcomes = [
        PolymarketOutcome(name: 'No change', price: 0.029, tokenId: 'n'),
        PolymarketOutcome(name: '25 bps increase', price: 0.855, tokenId: 'a'),
        PolymarketOutcome(name: '50+ bps increase', price: 0.118, tokenId: 'b'),
        PolymarketOutcome(name: '25 bps decrease', price: 0.004, tokenId: 'd'),
      ];
      await _pump(
        tester,
        const MarketCard(
          title: 'Fed Decision in December?',
          outcomes: outcomes,
          volume: 0,
          category: 'economy',
        ),
        dark: dark,
      );
      final c = dark ? AppColorsExtension.dark() : AppColorsExtension.light();
      final barFinder = find.byType(PolyOutcomeChanceBar);
      final bars = tester.widgetList<PolyOutcomeChanceBar>(barFinder).toList();
      expect(bars.map((b) => b.fraction), [0.855, 0.118, 0.029]);
      // What each bar paints: the track, then the fill over it.
      List<Color> painted(int i) => tester
          .widgetList<ColoredBox>(find.descendant(
              of: barFinder.at(i), matching: find.byType(ColoredBox)))
          .map((b) => b.color)
          .toList();
      final fills = [for (var i = 0; i < bars.length; i++) painted(i).last];
      // The palette in order, three different colours.
      expect(fills, kPolyOutcomeColors.take(3).toList());
      expect(fills.toSet(), hasLength(3));
      // The chart's own colour for the same outcome, rank for rank.
      final chart = polyChartedOutcomes(outcomes, kPolyOutcomeColors);
      expect(chart.take(3).map((l) => l.outcome.name),
          ['25 bps increase', '50+ bps increase', 'No change']);
      expect(fills, chart.take(3).map((l) => l.color).toList());
      // The track, the text and the figures are as they were.
      for (var i = 0; i < bars.length; i++) {
        expect(painted(i).first, c.border);
      }
      expect(tester.getSize(barFinder.first).height, 6);
      final name = tester.widget<Text>(find.text('25 bps increase'));
      expect(name.style?.color, c.textPrimary);
      final second = tester.widget<Text>(find.text('50+ bps increase'));
      expect(second.style?.color, c.textSecondary);
      expect(
          tester.widget<Text>(find.text('85.5%')).style?.color, c.textPrimary);
      expect(find.text('+1 more'), findsOneWidget);
    });
  }

  testWidgets('a Yes/No market draws no outcome bars', (tester) async {
    await _pump(
      tester,
      const MarketCard(
        title: 'Will it rain?',
        outcomes: [
          PolymarketOutcome(name: 'Yes', price: 0.4, tokenId: 'y'),
          PolymarketOutcome(name: 'No', price: 0.6, tokenId: 'n'),
        ],
        volume: 0,
        category: 'weather',
      ),
    );
    expect(find.byType(PolyOutcomeChanceBar), findsNothing);
  });
}
