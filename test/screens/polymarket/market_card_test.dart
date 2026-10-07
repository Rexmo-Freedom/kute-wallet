// The Predictions list card in its three shapes: a game, a single Yes/No
// market, an event with many outcomes.

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
    expect(find.text('+6 today'), findsOneWidget);
    expect(tester.widget<Text>(find.text('+6 today')).style!.color,
        AppColors.marketUp);
    expect(find.text('Dec 31, 2030'), findsOneWidget);
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

  testWidgets('many outcomes: the two most likely and how many more',
      (tester) async {
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
    expect(find.text('France'), findsNothing);
    expect(find.text('+2 more'), findsOneWidget);
    expect(find.textContaining('outcomes'), findsNothing);
  });
}
