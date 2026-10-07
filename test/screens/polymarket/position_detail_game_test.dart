// The open-position screen of a Predictions bet reads like the market
// sheet of the same market: a game gets the sheet's team header with the
// score between the teams, each team its own colour on the chance bar
// (no price chart on this screen), and the position itself is plain rows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sats_pnl_provider.dart'
    show predictionUsdCostProvider;
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/polymarket/components/game_chart_section.dart';
import 'package:kute/screens/polymarket/components/game_header.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart'
    show MarketChart;
import 'package:kute/screens/polymarket/components/market_livestream_view.dart';
import 'package:kute/screens/polymarket/components/poly_market_stats.dart'
    show PolyRulesRow;
import 'package:kute/screens/polymarket/components/position_chance_bar.dart';
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/ask_sal_chip.dart';
import 'package:kute/screens/shared/kute_motion.dart' show ScorePulseText;
import 'package:kute/screens/shared/position_rows_card.dart';
import 'package:kute/theme/app_theme.dart';

/// The header's score ([ScorePulseText]: a goal pulses its number), found
/// by the score it shows.
Finder _score(String text) => find.byWidgetPredicate(
    (w) => w is ScorePulseText && w.text == text,
    description: 'score "$text"');

const _home = PolymarketTeam(name: 'Broncos', abbreviation: 'den', ordering: 'home');
const _away = PolymarketTeam(name: '49ers', abbreviation: 'sf', ordering: 'away');

PolymarketEvent _game({
  String title = '49ers vs. Broncos',
  List<PolymarketOutcome> outcomes = const [
    PolymarketOutcome(name: '49ers', price: 0.64, tokenId: 'sf'),
    PolymarketOutcome(name: 'Broncos', price: 0.36, tokenId: 'den'),
  ],
  String? score,
  String? period,
  bool ended = false,
  int? gameId = 77,
}) =>
    PolymarketEvent(
      id: 'e1',
      slug: 'nfl-sf-den',
      title: title,
      volume: 1000,
      liquidity: 1000,
      category: 'sports',
      conditionId: 'c1',
      outcomes: outcomes,
      gameId: gameId,
      score: score,
      period: period,
      ended: ended,
      teams: const [_home, _away],
    );

class _NoGames extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => const {};

  // No socket in a test.
  @override
  void connect() {}
}

class _NoTimeline extends PolyGameTimelineNotifier {
  @override
  PolyGameTimeline build(String arg) => PolyGameTimeline.empty;
}

/// No Hive in a test: nothing paid on record on the device, so the API's
/// average price is the basis.
class _NoCostBasis extends StateNotifier<Map<String, double>>
    implements PolymarketCostBasisNotifier {
  _NoCostBasis() : super(const {});
  @override
  Future<void> addCost(String tokenId, double paidUsdc) async {}
  @override
  Future<void> reset(String tokenId) async {}
  @override
  Future<void> scaleByRemaining(
      String tokenId, double fractionRemaining) async {}
  @override
  double? costFor(String tokenId) => null;
}

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
}

Future<void> _pump(WidgetTester tester, Widget child,
    {List<Override> overrides = const [], double width = 390}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the match of an event', () {
    test('a sports "A vs B" is a match, in the title\'s order', () {
      final teams = polySportsTeams(_game(), const []);
      expect(teams?.teamA, '49ers');
      expect(teams?.teamB, 'Broncos');
    });

    test('a question that mentions a match is not one', () {
      expect(
          polySportsTeams(
              _game(title: 'Will the 49ers vs. Broncos game go to overtime?'),
              const []),
          isNull);
    });

    test('the score is written in the header\'s order, away side first', () {
      final event = _game(score: '7-3', period: 'Q2');
      final teams = polySportsTeams(event, const []);
      // The feed writes home (Broncos) first; the header names the 49ers
      // first.
      expect(
          polyLiveScoreText(event, null,
              sportsTeams: teams, teams: event.teams),
          '3 – 7');
    });

    test('a three-way market gives team, draw, team', () {
      final event = _game(
        title: 'Porto vs. Benfica',
        outcomes: const [
          PolymarketOutcome(name: 'Porto', price: 0.4, tokenId: 'a'),
          PolymarketOutcome(name: 'Draw', price: 0.3, tokenId: 'd'),
          PolymarketOutcome(name: 'Benfica', price: 0.3, tokenId: 'b'),
        ],
      );
      final wdl = polyWdlOutcomes(event, polySportsTeams(event, const []));
      expect(wdl?.teamA.tokenId, 'a');
      expect(wdl?.draw.tokenId, 'd');
      expect(wdl?.teamB.tokenId, 'b');
    });
  });

  group('the colour of the held line on a game', () {
    test('a team\'s own token takes a team colour, never up or down', () {
      final event = _game();
      final teams = polySportsTeams(event, const []);
      final a = gameLineColor(event, teams, null, 'sf');
      final b = gameLineColor(event, teams, null, 'den');
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a, isNot(b));
      for (final c in [a, b]) {
        expect(c, isNot(AppColors.marketUp));
        expect(c, isNot(AppColors.marketDown));
      }
      // The same colours the momentum graph and the board take.
      expect(gameSideColors(event.title, 'Broncos', '49ers'), (b, a));
    });

    test('the title\'s first team takes the first colour, whatever the '
        'odds or the market\'s own order', () {
      // The market lists the Broncos first and makes them the favourite;
      // the title names the 49ers first.
      final event = _game(outcomes: const [
        PolymarketOutcome(name: 'Broncos', price: 0.7, tokenId: 'den'),
        PolymarketOutcome(name: '49ers', price: 0.3, tokenId: 'sf'),
      ]);
      final teams = polySportsTeams(event, const []);
      expect(gameLineColor(event, teams, null, 'sf'), kGameSideColors[0]);
      expect(gameLineColor(event, teams, null, 'den'), kGameSideColors[1]);
    });

    test('a three-way market: team, team and the draw\'s third colour', () {
      final event = _game(
        title: 'Porto vs. Benfica',
        outcomes: const [
          PolymarketOutcome(name: 'Porto', price: 0.4, tokenId: 'a'),
          PolymarketOutcome(name: 'Draw', price: 0.3, tokenId: 'd'),
          PolymarketOutcome(name: 'Benfica', price: 0.3, tokenId: 'b'),
        ],
      );
      final teams = polySportsTeams(event, const []);
      expect(gameLineColor(event, teams, null, 'a'), kGameSideColors[0]);
      expect(gameLineColor(event, teams, null, 'b'), kGameSideColors[1]);
      expect(gameLineColor(event, teams, null, 'd'), kGameSideColors[2]);
    });

    test('a spread or a total keeps the chart\'s own colour', () {
      final event = _game();
      expect(
          gameLineColor(
              event, polySportsTeams(event, const []), null, 'over-45'),
          isNull);
    });

    test('an event that is not a game has no team colour', () {
      final event = _game(gameId: null);
      expect(
          gameLineColor(
              event, polySportsTeams(event, const []), null, 'sf'),
          isNull);
    });
  });

  testWidgets('the header of a game in play: score between the teams',
      (tester) async {
    await _pump(
      tester,
      const Scaffold(
        body: PolyGameTeamsHeader(
          teams: (teamA: '49ers', teamB: 'Broncos', imageA: null, imageB: null),
          live: true,
          scoreText: '3 – 7',
          statusText: 'Q2 10:28',
        ),
      ),
    );
    expect(find.text('49ers'), findsOneWidget);
    expect(find.text('Broncos'), findsOneWidget);
    expect(_score('3 – 7'), findsOneWidget);
    expect(find.text('Q2 10:28'), findsOneWidget);
    expect(find.text('vs'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('position rows: label left, figure right-aligned',
      (tester) async {
    await _pump(
      tester,
      const Scaffold(
        body: PositionRowsCard(rows: [
          PositionRow('Outcome', 'Yes'),
          PositionRow('Shares', '120.00'),
        ]),
      ),
      width: 320,
    );
    expect(tester.widget<Text>(find.text('120.00')).textAlign, TextAlign.right);
    expect(tester.getTopRight(find.text('120.00')).dx,
        greaterThan(tester.getTopRight(find.text('Shares')).dx));
    expect(tester.takeException(), isNull);
  });

  group('the open-position screen', () {
    const position = PolymarketPosition(
      marketId: 'c1',
      marketQuestion: '49ers vs. Broncos',
      outcome: '49ers',
      size: 120,
      avgPrice: 0.42,
      currentPrice: 0.5,
      pnl: 9.6,
      pnlPercent: 19,
      isResolved: false,
      eventSlug: 'nfl-sf-den',
    );

    List<Override> overrides(PolymarketEvent? event, {bool ai = false}) => [
          polymarketClaimablePositionsProvider.overrideWithValue(const []),
          polymarketActivePositionsProvider.overrideWithValue(const []),
          livePriceProvider.overrideWith(_Prices.new),
          sportsLiveProvider.overrideWith(_NoGames.new),
          polyGameTimelineProvider.overrideWith(_NoTimeline.new),
          aiEnabledProvider.overrideWith((ref) async => ai),
          polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
          predictionUsdCostProvider.overrideWith((ref, id) async => null),
          polymarketEventDetailsProvider('nfl-sf-den')
              .overrideWith((ref) async => event),
        ];

    testWidgets(
        'no Sal button in the header; Sal\'s question capsule under the '
        'value, grounded on the held market, never the holding',
        (tester) async {
      await _pump(
        tester,
        const PositionDetailSheet(position: position),
        overrides: overrides(_game(outcomes: const [
          PolymarketOutcome(
              name: '49ers',
              price: 0.64,
              tokenId: 'sf',
              conditionId: 'c1',
              gammaMarketId: '555'),
          PolymarketOutcome(
              name: 'Broncos',
              price: 0.36,
              tokenId: 'den',
              conditionId: 'c9',
              gammaMarketId: '556'),
        ]), ai: true),
      );
      expect(find.byType(AskSalChip), findsNothing);
      expect(find.byKey(const ValueKey('ask-sal-pill')), findsNothing);
      final row =
          tester.widget<SalQuestionCapsule>(find.byType(SalQuestionCapsule));
      expect(row.entry, 'position_capsule');
      expect(row.advisorContext.surface, 'polymarket_position_detail');
      expect(row.advisorContext.toRequestMarket, {
        'venue': 'polymarket',
        'id': 'nfl-sf-den',
        'submarketId': '555',
      });
      // Holding only ranks the questions, on the device; never sent.
      expect(row.chipSignals.holdsPosition, isTrue);
      expect(find.byKey(const ValueKey('sal-question-capsule')),
          findsOneWidget);
      expect(
          tester
              .getRect(find.byKey(const ValueKey('sal-question-capsule')))
              .top,
          greaterThan(tester.getRect(find.text('Current value')).bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a game in play: the sheet\'s header with the score, the '
        'position as rows, nothing written twice', (tester) async {
      await _pump(
        tester,
        const PositionDetailSheet(position: position),
        overrides: overrides(_game(score: '7-3', period: 'Q2')),
      );
      expect(find.byType(PolyGameTeamsHeader), findsOneWidget);
      expect(_score('3 – 7'), findsOneWidget);
      // The title is in the screen's header, once; the teams header under
      // it carries the score.
      expect(find.text('49ers vs. Broncos'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('poly-position-title')), findsOneWidget);
      // The side is one row, not a pill over the value.
      expect(find.text('Outcome'), findsOneWidget);
      expect(find.text('49ERS'), findsNothing);
      expect(find.text('Shares'), findsOneWidget);
      expect(find.text('120.00'), findsOneWidget);
      expect(find.text('Bought at'), findsOneWidget);
      expect(find.text('42¢'), findsOneWidget);
      expect(find.text('Invested'), findsOneWidget);
      expect(find.text('Sell'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a team\'s side: the chance bar in the team\'s colour, '
        'ticked at the price paid; no price chart', (tester) async {
      await _pump(
        tester,
        const PositionDetailSheet(
          position: PolymarketPosition(
            marketId: 'c1',
            marketQuestion: '49ers vs. Broncos',
            outcome: '49ers',
            size: 120,
            avgPrice: 0.42,
            currentPrice: 0.5,
            pnl: 9.6,
            pnlPercent: 19,
            isResolved: false,
            eventSlug: 'nfl-sf-den',
            tokenId: 'sf',
          ),
        ),
        overrides: overrides(_game()),
      );
      await tester.pump();
      expect(find.byType(MarketChart), findsNothing);
      final bar = tester
          .widget<PolyPositionChanceBar>(find.byType(PolyPositionChanceBar));
      expect(bar.spec.left, kGameSideColors[0]);
      expect(bar.spec.right, isNull);
      expect(bar.spec.value, closeTo(0.5, 1e-9));
      expect(bar.spec.tick, closeTo(0.42, 1e-9));
      expect(find.text('Bought · 42¢'), findsOneWidget);
      // Between the figures and the rows.
      expect(
          tester.getRect(find.byType(PolyPositionChanceBar)).bottom,
          lessThan(tester.getRect(find.text('Outcome')).top));
      // The live feed's subscribe debounce runs out.
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a Down side: the green and red split at Up\'s chance, the '
        'tick measured from the red end', (tester) async {
      await _pump(
        tester,
        const PositionDetailSheet(
          position: PolymarketPosition(
            marketId: 'c4',
            marketQuestion: 'Bitcoin Up or Down - 5 minutes',
            outcome: 'Down',
            size: 4.6,
            avgPrice: 0.54,
            currentPrice: 0.075,
            pnl: -2.13,
            pnlPercent: -86.1,
            isResolved: false,
            tokenId: 'down',
          ),
        ),
        overrides: overrides(null),
      );
      final bar = tester
          .widget<PolyPositionChanceBar>(find.byType(PolyPositionChanceBar));
      expect(bar.spec.left, AppColors.marketUp);
      expect(bar.spec.right, AppColors.marketDown);
      expect(bar.spec.value, closeTo(0.925, 1e-9));
      expect(bar.spec.tick, closeTo(0.46, 1e-6));
      expect(find.byType(MarketChart), findsNothing);
      // The live feed's subscribe debounce runs out.
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a market inside a game names its own question in the '
        'header, the teams under it', (tester) async {
      await _pump(
        tester,
        const PositionDetailSheet(
          position: PolymarketPosition(
            marketId: 'c2',
            marketQuestion: 'Spread: 49ers (-4.5)',
            outcome: 'Yes',
            size: 10,
            avgPrice: 0.5,
            currentPrice: 0.5,
            pnl: 0,
            pnlPercent: 0,
            isResolved: false,
            eventSlug: 'nfl-sf-den',
          ),
        ),
        overrides: overrides(_game()),
        width: 320,
      );
      expect(find.byType(PolyGameTeamsHeader), findsOneWidget);
      expect(find.text('vs'), findsOneWidget);
      expect(find.text('Spread: 49ers (-4.5)'), findsOneWidget);
      expect(
          tester
              .widget<Text>(find.descendant(
                  of: find.byKey(const ValueKey('poly-position-title')),
                  matching: find.byType(Text)))
              .data,
          'Spread: 49ers (-4.5)');
      expect(tester.takeException(), isNull);
    });

    testWidgets('closing conditions: one row opening the shared bottom '
        'sheet, never stacked on itself', (tester) async {
      const conditions = 'This market resolves to the team that wins.';
      final event = PolymarketEvent(
        id: 'e1',
        slug: 'nfl-sf-den',
        title: '49ers vs. Broncos',
        volume: 1000,
        liquidity: 1000,
        category: 'sports',
        conditionId: 'c1',
        description: conditions,
        outcomes: _game().outcomes,
        gameId: 77,
        teams: const [_home, _away],
      );
      await _pump(
        tester,
        const PositionDetailSheet(position: position),
        overrides: overrides(event),
      );
      // A row, not an expander: the text is not on the screen itself.
      final row = find.text('Closing Conditions');
      await tester.pump();
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(row, findsOneWidget);
      expect(find.text(conditions), findsNothing);
      // Two taps inside one frame (the row's handler called twice before
      // the sheet's route is built): one sheet.
      final onTap = tester
          .widget<PolyRulesRow>(find.ancestor(
              of: row, matching: find.byType(PolyRulesRow)))
          .onTap;
      onTap();
      onTap();
      await tester.pumpAndSettle();
      expect(find.byType(AppBottomSheetHeader), findsOneWidget);
      expect(find.text(conditions), findsOneWidget);
      // Closed with its own button, then opened again.
      await tester.tap(find.descendant(
          of: find.byType(AppBottomSheetHeader),
          matching: find.byIcon(Icons.close_rounded)));
      await tester.pumpAndSettle();
      expect(find.byType(AppBottomSheetHeader), findsNothing);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(AppBottomSheetHeader), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a game with a broadcast: Market / Livestream as on the '
        'market sheet, the player only once Livestream is picked',
        (tester) async {
      final event = PolymarketEvent(
        id: 'e1',
        slug: 'nfl-sf-den',
        title: '49ers vs. Broncos',
        volume: 1000,
        liquidity: 1000,
        category: 'sports',
        conditionId: 'c1',
        outcomes: _game().outcomes,
        gameId: 77,
        teams: const [_home, _away],
        streamUrl: 'https://www.twitch.tv/ESLCSb',
        isLive: true,
      );
      await _pump(
        tester,
        const PositionDetailSheet(position: position),
        overrides: overrides(event),
      );
      await tester.pump();
      expect(find.text('Market'), findsOneWidget);
      expect(find.text('Livestream'), findsOneWidget);
      // Nothing of the stream loads before it is picked.
      expect(find.byType(MarketLivestreamView), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no broadcast: no Market / Livestream pills', (tester) async {
      await _pump(
        tester,
        const PositionDetailSheet(position: position),
        overrides: overrides(_game()),
      );
      await tester.pump();
      expect(find.text('Livestream'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a market that is not a game: its title in the header, up '
        'to two lines',
        (tester) async {
      const title = 'Will the Fed cut interest rates by more than 25 basis '
          'points at its December meeting this year?';
      await _pump(
        tester,
        const PositionDetailSheet(
          position: PolymarketPosition(
            marketId: 'c3',
            marketQuestion: title,
            outcome: 'No',
            size: 10,
            avgPrice: 0.5,
            currentPrice: 0.4,
            pnl: -1,
            pnlPercent: -20,
            isResolved: false,
          ),
        ),
        overrides: overrides(null),
        width: 320,
      );
      expect(find.byType(PolyGameTeamsHeader), findsNothing);
      final text = tester.widget<Text>(find.text(title));
      // The header's shrink-to-fit title (FittedTitle) draws it.
      expect(
          find.ancestor(
              of: find.text(title),
              matching: find.byKey(const ValueKey('poly-position-title'))),
          findsOneWidget);
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });
  });
}
