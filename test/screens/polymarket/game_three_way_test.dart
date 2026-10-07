// Football matches with a draw, read from two real Gamma events
// (test/fixtures/polymarket_games/): "Sunderland AFC vs. Brighton & Hove
// Albion FC", whose second team runs to five words with its "&", and
// "Leeds United FC vs. Manchester United FC", whose two teams share
// "United FC". Each is three winner markets: team, "Draw (A vs. B)", team.
//
//   * both are games (the team header, the WINNER board of three);
//   * each side has a short name of its own ("Leeds" / "Man Utd", never
//     "United" twice) on the board, the chart's lines and the slip;
//   * the slip of a three-way match has three sides and opens on the one
//     tapped (the draw opens on Draw);
//   * the draw market alone reads Yes / No, never "Draw" / "FC)".

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/formatters/polymarket_side_labels.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/game_header.dart';
import 'package:kute/screens/polymarket/components/game_winner_lines.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/services/polymarket/live_game/game_sides.dart';
import 'package:kute/services/polymarket/market_card_shape.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_swap_orders.dart';

PolymarketEvent gameFixture(String name) => PolymarketModel().parseEventsRaw([
      jsonDecode(File('test/fixtures/polymarket_games/$name.json')
          .readAsStringSync()) as Map<String, dynamic>,
    ]).single;

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
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
}

class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(usdcBalance: 100);
}

/// Everything the market sheet and the slip read, answered locally.
List<Override> gameOverrides() => [
      settingsProvider.overrideWith((ref) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
          ))),
      polymarketTradingProvider.overrideWith(_Trading.new),
      swapOrdersProvider.overrideWith((ref) => FakeSwapOrders()),
      livePriceProvider.overrideWith(_Prices.new),
      polymarketOpenOrdersProvider
          .overrideWith((ref) => Stream.value(const [])),
      sportsLiveProvider.overrideWith(_NoGames.new),
      polyGameTimelineProvider.overrideWith(_NoTimeline.new),
      polyGameLinesProvider.overrideWith((ref, slug) async =>
          PolyGameLines.fromEvent(gameFixture(slug.contains('sun')
              ? 'sunderland_brighton'
              : 'leeds_man_united'))),
      polymarketActivePositionsProvider.overrideWithValue(const []),
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      aiEnabledProvider.overrideWith((ref) async => false),
    ];

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('reading the match', () {
    test('a team of five words with an "&" is still a team', () {
      expect(polyLooksLikeTeamName('Brighton & Hove Albion FC'), isTrue);
      expect(titleTeams('Sunderland AFC vs. Brighton & Hove Albion FC'),
          ('Sunderland AFC', 'Brighton & Hove Albion FC'));
      // A question that mentions a match is still not one.
      expect(
          polyLooksLikeTeamName('What will the announcers say during Scotland'),
          isFalse);
      final sun = gameFixture('sunderland_brighton');
      expect(sun.looksLikeMatchup, isTrue);
      final teams = polySportsTeams(sun, const []);
      expect(teams?.teamA, 'Sunderland AFC');
      expect(teams?.teamB, 'Brighton & Hove Albion FC');
    });

    test('the three winner markets are read by structure', () {
      for (final (name, a, b) in [
        ('sunderland_brighton', 'Sunderland AFC', 'Brighton & Hove Albion FC'),
        ('leeds_man_united', 'Leeds United FC', 'Manchester United FC'),
      ]) {
        final event = gameFixture(name);
        final wdl = polyWdlOutcomes(event, polySportsTeams(event, const []));
        expect(wdl, isNotNull, reason: name);
        expect(wdl!.teamA.name, a);
        expect(wdl.teamB.name, b);
        expect(wdl.draw.name, startsWith('Draw ('));
        // The list card reads the same three.
        final card = polyCardGame(event.title, event.outcomes);
        expect(card?.draw, wdl.draw.price);
        expect(card?.outcomeA.tokenId, wdl.teamA.tokenId);
      }
    });

    test('the side order follows the names, not the feed', () {
      expect(
          gameThreeWaySides('Leeds United FC', 'Manchester United FC', [
            'Manchester United FC',
            'Draw (Leeds United FC vs. Manchester United FC)',
            'Leeds United FC',
          ]),
          (a: 2, draw: 1, b: 0));
      // Two outcomes that name no side of the title are not a match.
      expect(gameThreeWaySides('Leeds', 'Chelsea', ['Over', 'Tie', 'Under']),
          isNull);
    });
  });

  group('short names', () {
    test('Gamma\'s own short names, unique within the match', () {
      final leeds = gameFixture('leeds_man_united');
      expect(
          gameShortSideNames('Leeds United FC', 'Manchester United FC',
              teams: leeds.teams),
          ('Leeds', 'Man Utd'));
      final sun = gameFixture('sunderland_brighton');
      expect(
          gameShortSideNames('Sunderland AFC', 'Brighton & Hove Albion FC',
              teams: sun.teams),
          ('Sunderland', 'Brighton'));
    });

    test('without the teams: no club tag, never the same word twice', () {
      expect(gameShortSideNames('Leeds United FC', 'Manchester United FC'),
          ('Leeds United', 'Manchester'));
      expect(gameShortSideNames('Sunderland AFC', 'Brighton & Hove Albion FC'),
          ('Sunderland', 'Brighton'));
      expect(gameShortSideNames('Manchester United FC', 'Manchester City FC'),
          ('United', 'City'));
      // Franchises and players keep their nickname / surname.
      expect(gameShortSideNames('Los Angeles Lakers', 'Golden State Warriors'),
          ('Lakers', 'Warriors'));
      expect(gameShortSideNames('Chiefs', 'Raiders'), ('Chiefs', 'Raiders'));
    });

    test('the chart\'s lines carry them', () {
      final leeds = gameFixture('leeds_man_united');
      final lines = polyGameWinnerLines(
        event: leeds,
        sportsTeams: polySportsTeams(leeds, const []),
        lines: null,
        drawLabel: 'Draw',
      );
      expect([for (final l in lines) l.label], ['Leeds', 'Draw', 'Man Utd']);
    });
  });

  test('the draw market alone reads Yes / No', () {
    expect(
        polymarketSideLabels(
            'Draw (Sunderland AFC vs. Brighton & Hove Albion FC)'),
        (pos: 'YES', neg: 'NO'));
    // A moneyline between two teams keeps its teams.
    expect(polymarketSideLabels('Lakers vs. Warriors'),
        (pos: 'Lakers', neg: 'Warriors'));
  });

  Future<void> pumpSheet(WidgetTester tester, PolymarketEvent event) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: gameOverrides(),
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
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
      'Sunderland vs Brighton is a game, and its Draw opens the '
      'three-way slip on Draw', (tester) async {
    await http.runWithClient(() async {
      final event = gameFixture('sunderland_brighton');
      await pumpSheet(tester, event);
      expect(find.text('WINNER'), findsOneWidget);
      // The board's three sides, by their short names.
      expect(find.text('Sunderland'), findsWidgets);
      expect(find.text('Brighton'), findsWidgets);
      // The generic list's draw row is gone with its "FC)" label.
      expect(find.textContaining('FC)'), findsNothing);

      final draw = find.text('Draw').hitTestable();
      expect(draw, findsWidgets);
      await tester.tap(draw.first);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final slip = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
      expect(slip.outcomeLabels, ['Sunderland', 'Draw', 'Brighton']);
      expect(slip.initialOutcomeIndex, 1);
      expect(slip.marketQuestion, event.title);
      expect([
        for (final o in slip.outcomes) o.tokenId
      ], [
        for (final o in [
          event.outcomes.firstWhere((o) => o.name == 'Sunderland AFC'),
          event.outcomes.firstWhere((o) => o.name.startsWith('Draw')),
          event.outcomes.firstWhere((o) => o.name.startsWith('Brighton')),
        ])
          o.tokenId,
      ]);
      // Each side buys its own Yes: no side has a No to flip to.
      expect(slip.outcomes.any((o) => o.hasYesNo), isFalse);
      // Every side is tinted by its line.
      expect(slip.outcomeColors?.every((c) => c != null), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      // The slip's venue note is written a moment later.
      await tester.pump(const Duration(seconds: 3));
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets('the three-way slip names its sides and buys the one picked',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final event = gameFixture('leeds_man_united');
    final wdl = polyWdlOutcomes(event, polySportsTeams(event, const []))!;
    await tester.pumpWidget(ProviderScope(
      overrides: gameOverrides(),
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: BetSlipSheet(
                marketQuestion: event.title,
                outcomes: [
                  for (final o in [wdl.teamA, wdl.draw, wdl.teamB])
                    PolymarketOutcome(
                        name: o.name, price: o.price, tokenId: o.tokenId),
                ],
                outcomeLabels: const ['Leeds', 'Draw', 'Man Utd'],
                initialOutcomeIndex: 2,
                initialAmountUsd: 10,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Leeds'), findsOneWidget);
    expect(find.text('Draw'), findsOneWidget);
    expect(find.text('Man Utd'), findsOneWidget);
    expect(find.text('United'), findsNothing);
    expect(find.textContaining('on Man Utd'), findsOneWidget);
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    expect(find.textContaining('on Draw'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
