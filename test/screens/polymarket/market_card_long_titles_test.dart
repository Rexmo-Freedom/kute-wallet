// The Predictions list card writes real titles whole on a narrow phone:
// the ten longest questions among Gamma's most traded live markets and
// the day's biggest movers (read 2026-10-04) and a 160-character one, at
// 375 pt wide, in the app's own font. No ellipsis, no overflow.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/theme/app_theme.dart';

const _longest = [
  'Will Flávio Bolsonaro win between 45% and 48% of the valid vote in the first round of the 2026 Brazilian presidential election?',
  'Will Augusto Cury finish in third place in the first round of the 2026 Brazilian presidential election?',
  'Will any presidential candidate win outright in the first round of the Brazil election?',
  'Brazil Presidential Election First Round: Flávio Bolsonaro Vote Share? (Higher Strikes)',
  'LoL: Shopify Rebellion vs JD Gaming (BO3) - Demacia Cup Global Invitational Group Stage',
  'Counter-Strike: Galorys vs Turma do Pagode (BO3) - CCT South America Series 6 Playoffs',
  'LoL: GAM Esports vs Team Vitality (BO3) - Demacia Cup Global Invitational Group Stage',
  'Shanghai Rolex Masters, Qualification: Alexander Shevchenko vs Yoshihito Nishioka',
  'LoL: Movistar KOI Fénix vs UCAM Esports Club (BO5) - EMEA Masters Knockout Stage',
  'Counter-Strike: Aurora Gaming vs BetBoom Team (BO3) - ESL Pro League Group Stage',
  // Longer than anything live: 160 characters.
  'Will the candidate who finishes second in the first round of the 2026 Brazilian presidential election go on to win the second round by more than five points??',
];

Future<void> _pump(WidgetTester tester, List<Widget> cards) async {
  tester.view.physicalSize = const Size(375, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            // The feed's own side padding.
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Column(children: cards),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// Whether the text [text] is drawn cut (an ellipsis).
bool _cut(WidgetTester tester, String text) => tester
    .renderObject<RenderParagraph>(find.text(text))
    .didExceedMaxLines;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Bold.ttf'));
    await loader.load();
  });

  testWidgets('a Yes/No card writes a long question whole', (tester) async {
    await _pump(tester, [
      for (final q in _longest)
        MarketCard(
          title: q,
          outcomes: const [
            PolymarketOutcome(name: 'Yes', price: 0.95),
            PolymarketOutcome(name: 'No', price: 0.05),
          ],
          volume: 2500000,
          category: 'politics',
          endDate: DateTime(2026, 10, 5),
          dayMove: 0.70,
        ),
    ]);
    expect(tester.takeException(), isNull);
    for (final q in _longest) {
      expect(_cut(tester, q), isFalse, reason: q);
    }
    // The footer is whole too.
    expect(find.text('Oct 5, 2026'), findsNWidgets(_longest.length));
    for (final e in find.text('+70 today').evaluate()) {
      expect((e.renderObject! as RenderParagraph).didExceedMaxLines, isFalse);
    }
  });

  testWidgets('a many-outcomes card writes a long title whole, and outcome '
      'names on up to two lines', (tester) async {
    const first = 'Luiz Inácio Lula da Silva and Flávio Bolsonaro';
    await _pump(tester, [
      for (final q in _longest)
        MarketCard(
          title: q,
          outcomes: const [
            PolymarketOutcome(name: first, price: 0.84, noTokenId: 'a'),
            PolymarketOutcome(name: 'Other', price: 0.1, noTokenId: 'b'),
            PolymarketOutcome(name: 'Nobody', price: 0.06, noTokenId: 'c'),
          ],
          volume: 56800,
          category: 'politics',
        ),
    ]);
    expect(tester.takeException(), isNull);
    for (final q in _longest) {
      expect(_cut(tester, q), isFalse, reason: q);
    }
    for (final e in find.text(first).evaluate()) {
      expect((e.renderObject! as RenderParagraph).didExceedMaxLines, isFalse);
    }
  });

  testWidgets('a footer that cannot hold both sides drops the year',
      (tester) async {
    await _pump(tester, [
      MarketCard(
        title: 'Arsenal vs Chelsea',
        outcomes: const [
          PolymarketOutcome(name: 'Yes', price: 0.5),
          PolymarketOutcome(name: 'No', price: 0.5),
        ],
        // Measured in the card's own face, it takes this much to run
        // out of room at 375 pt.
        volume: 123456789012345,
        category: 'sports',
        startDate: DateTime(2031, 9, 28),
        siblingMarketCount: 1110,
      ),
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text('Starts Sep 28'), findsOneWidget);
    expect(_cut(tester, 'Starts Sep 28'), isFalse);
    expect(find.textContaining('vol'), findsOneWidget);
  });

  testWidgets('a long team name takes a second line before it is abbreviated',
      (tester) async {
    await _pump(tester, [
      const MarketCard(
        title: 'Oklahoma City Thunder Blue vs Minnesota Timberwolves',
        outcomes: [
          PolymarketOutcome(name: 'Oklahoma City Thunder Blue', price: 0.36),
          PolymarketOutcome(name: 'Minnesota Timberwolves', price: 0.64),
        ],
        teams: [
          PolymarketTeam(
              name: 'Oklahoma City Thunder Blue',
              abbreviation: 'okc',
              ordering: 'home'),
          PolymarketTeam(
              name: 'Minnesota Timberwolves',
              abbreviation: 'min',
              ordering: 'away'),
        ],
        volume: 6200000,
        category: 'sports',
        liveGame: PolyLiveGame(
            score: '101-99', clock: 'Q4 02:39', period: 'Q4', firstIsHome: true),
      ),
    ]);
    expect(tester.takeException(), isNull);
    // Each name is written whole, on two lines when one cannot hold it:
    // not abbreviated, not cut.
    for (final (name, abbr) in [
      ('Oklahoma City Thunder Blue', 'OKC'),
      ('Minnesota Timberwolves', 'MIN'),
    ]) {
      expect(find.text(name), findsOneWidget);
      expect(find.text(abbr), findsNothing);
      expect(_cut(tester, name), isFalse);
    }
  });

  testWidgets('a team name: one line, then two, then its abbreviation',
      (tester) async {
    const name = 'Oklahoma City Thunder Blue';
    const style = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
    Widget boxed(double width) => SizedBox(
          key: ValueKey(width),
          width: width,
          child: const PolyCardTeamName(name: name, short: 'OKC', style: style),
        );
    await _pump(tester, [boxed(320), boxed(170), boxed(40)]);
    expect(tester.takeException(), isNull);
    Finder inBox(double width, String text) => find.descendant(
        of: find.byKey(ValueKey(width)), matching: find.text(text));
    // Room for it: one line.
    final oneLine = tester.getSize(inBox(320, name)).height;
    // Too narrow for one line: whole on two, not abbreviated.
    expect(inBox(170, name), findsOneWidget);
    expect(tester.getSize(inBox(170, name)).height, greaterThan(oneLine));
    expect(
        tester
            .renderObject<RenderParagraph>(inBox(170, name))
            .didExceedMaxLines,
        isFalse);
    // Too narrow for two lines: the abbreviation.
    expect(inBox(40, name), findsNothing);
    expect(inBox(40, 'OKC'), findsOneWidget);
  });
}
