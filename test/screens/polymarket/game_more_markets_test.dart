// A game's "More markets" on its sheet (game_more_markets.dart), from real
// Gamma events (test/fixtures/polymarket_games/):
//
//   * the period chips come from the markets: All · Match · Game 1 …
//     Game 5 on a LoL best-of-five, All · Match · 1st half · 2nd half on a
//     football match, none on a game with one period;
//   * a period lists its lines by kind, each one short label ("24.5",
//     "GL -1.5"), never the league, the teams or "Over/Under";
//   * both sides of a line are buttons, and each opens the slip on its own
//     side (the market's Yes or No token), named as the line names it;
//   * lines not trading yet and settled lines fold away at the foot;
//   * the board's Over / Under tiles are the same button, a step up.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
import 'package:kute/screens/polymarket/components/game_more_markets.dart';
import 'package:kute/screens/polymarket/components/game_side_button.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/polymarket/live_game/game_line_rows.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/shell_bar_harness.dart';

PolymarketEvent moreMarketsFixture(String name) =>
    PolymarketModel().parseEventsRaw([
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
  final Map<String, double> seed;
  _Prices([this.seed = const {}]);
  @override
  LivePriceState build() => LivePriceState(prices: seed);
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  void tick(String token, double p) => state = state.copyWithPrice(token, p);
}

class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(usdcBalance: 100);
}

/// Everything the sheet and the slip read for [event], answered locally;
/// [prices] seeds the live feed.
List<Override> moreMarketsOverrides(PolymarketEvent event,
        {Map<String, double> prices = const {}}) =>
    [
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
      livePriceProvider.overrideWith(() => _Prices(prices)),
      polymarketOpenOrdersProvider
          .overrideWith((ref) => Stream.value(const [])),
      sportsLiveProvider.overrideWith(_NoGames.new),
      polyGameTimelineProvider.overrideWith(_NoTimeline.new),
      polyGameLinesProvider
          .overrideWith((ref, slug) async => PolyGameLines.fromEvent(event)),
      polymarketActivePositionsProvider.overrideWithValue(const []),
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      aiEnabledProvider.overrideWith((ref) async => false),
    ];

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpSheet(WidgetTester tester, PolymarketEvent event,
      {Map<String, double> prices = const {}}) async {
    tester.view.physicalSize = const Size(430, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    installShellBar();
    await tester.pumpWidget(ProviderScope(
      overrides: moreMarketsOverrides(event, prices: prices),
      child: shellBarApp(
        // The phone's proportions at this height, so .h scales as .w does.
        designSize: const Size(430, 5000),
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        home: MarketDetailSheet(event: event),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder chips() => find.descendant(
      of: find.byKey(const ValueKey('game-period-chips')),
      matching: find.byType(KutePill));

  List<String> chipLabels(WidgetTester tester) =>
      [for (final p in tester.widgetList<KutePill>(chips())) p.label];

  Future<void> tapChip(WidgetTester tester, String label) async {
    final chip = find.descendant(
        of: find.byKey(const ValueKey('game-period-chips')),
        matching: find.widgetWithText(KutePill, label));
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// [finder] inside "More markets" (the board above has its own WINNER).
  Finder inMore(Finder finder) =>
      find.descendant(of: find.byType(PolyGameMoreMarkets), matching: finder);

  /// The line titled [title].
  Finder line(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('game-line-')));

  /// The two button labels of the line titled [title].
  List<String> sidesOf(WidgetTester tester, String title) {
    final tile = line(title);
    return [
      for (final b in tester.widgetList<PolyGameSideButton>(
          find.descendant(of: tile, matching: find.byType(PolyGameSideButton))))
        b.label,
    ];
  }

  Future<void> closeSlip(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // The slip's venue note is written a moment later.
    await tester.pump(const Duration(seconds: 3));
  }

  Future<void> offline(Future<void> Function() body) => http.runWithClient(
      body, () => MockClient((_) async => http.Response('{}', 404)));

  testWidgets('LoL BO5: the period chips, the lines of a game by kind',
      (tester) async {
    await offline(() async {
      final event = moreMarketsFixture('lol_dk_blg_bo5');
      await pumpSheet(tester, event);
      expect(find.text('More markets'), findsOneWidget);
      expect(chipLabels(tester),
          ['All', 'Match', 'Game 1', 'Game 2', 'Game 3', 'Game 4', 'Game 5']);

      await tapChip(tester, 'Game 1');
      // Winner alone: its kind is its label, no heading. Two kill lines
      // under their heading, the line alone; the duration alone, by its
      // kind. No league, no teams, no "Over/Under", no "?".
      expect(find.text('Winner'), findsOneWidget);
      expect(sidesOf(tester, 'Winner'), ['DK', 'BLG']);
      expect(find.text('TOTAL KILLS'), findsOneWidget);
      expect(find.text('24.5'), findsOneWidget);
      expect(find.text('27.5'), findsOneWidget);
      expect(sidesOf(tester, '24.5'), ['Over', 'Under']);
      expect(find.text('Duration · 32:30'), findsOneWidget);
      expect(find.textContaining('Over/Under'), findsNothing);
      expect(inMore(find.textContaining('LoL:')), findsNothing);
      expect(inMore(find.textContaining('?')), findsNothing);
      // Its five yes / no questions have never traded: folded away.
      expect(find.text('Not trading yet · 5'), findsOneWidget);
      expect(find.text('Both Teams Slay Baron Nashor'), findsNothing);
      await tester.tap(find.text('Not trading yet · 5'));
      await tester.pump();
      expect(find.text('Both Teams Slay Baron Nashor'), findsOneWidget);
      expect(sidesOf(tester, 'Both Teams Slay Baron Nashor'), ['Yes', 'No']);
      // No price yet: a dash, never "50%".
      final quiet = tester
          .widgetList<PolyGameSideButton>(find.descendant(
              of: line('Both Teams Slay Baron Nashor'),
              matching: find.byType(PolyGameSideButton)))
          .toList();
      expect(quiet.map((b) => b.pctText), ['—', '—']);
      expect(quiet.every((b) => b.muted), isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
      'All: the period in front of each line, a kind\'s first four '
      'and "Show N more"', (tester) async {
    await offline(() async {
      final event = moreMarketsFixture('lol_dk_blg_bo5');
      await pumpSheet(tester, event);
      // The four game winners under one heading, by game.
      expect(inMore(find.text('WINNER')), findsOneWidget);
      for (final g in ['Game 1', 'Game 2', 'Game 3', 'Game 4']) {
        expect(find.text(g), findsWidgets);
      }
      expect(sidesOf(tester, 'Game 3').length, 2);
      // Eight kill lines: four, then "Show 4 more".
      expect(find.text('TOTAL KILLS'), findsOneWidget);
      expect(find.text('Game 1 · 24.5'), findsOneWidget);
      expect(find.text('Show 4 more'), findsWidgets);
      // The series' handicap by Polymarket's own short names.
      expect(inMore(find.text('HANDICAP')), findsOneWidget);
      expect(sidesOf(tester, 'DK -1.5'), ['DK -1.5', 'BLG +1.5']);
      expect(sidesOf(tester, 'BLG -1.5'), ['BLG -1.5', 'DK +1.5']);
      // The kind chips: more than eight lines of several kinds.
      expect(find.byKey(const ValueKey('game-type-chips')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
      'Dota BO3: a side opens the slip on that side, named as the '
      'line names it', (tester) async {
    await offline(() async {
      final event = moreMarketsFixture('dota_yes_gl_bo3');
      await pumpSheet(tester, event);
      expect(
          chipLabels(tester), ['All', 'Match', 'Game 1', 'Game 2', 'Game 3']);
      await tapChip(tester, 'Game 2');
      expect(sidesOf(tester, 'Winner'), ['YS', 'GL']);
      final market = event.outcomes.firstWhere((o) =>
          o.marketLine?.question ==
          'Dota 2: Yellow Submarine vs GamerLegion - Game 2 Winner');

      // GamerLegion, the second side: the market's No token.
      final row = line('Winner');
      await tester.tap(find
          .descendant(of: row, matching: find.byType(PolyGameSideButton))
          .last);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final slip = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
      expect(slip.initialOutcomeIndex, 1);
      expect([for (final o in slip.outcomes) o.tokenId],
          [market.tokenId, market.noTokenId]);
      expect(slip.sideLabelPos, 'Yellow Submarine');
      expect(slip.sideLabelNeg, 'GamerLegion');
      // The market's own question, as its page's slip had it.
      expect(slip.marketQuestion, market.name);
      await closeSlip(tester);
    });
  });

  testWidgets('the first side of a handicap opens on the Yes token',
      (tester) async {
    await offline(() async {
      final event = moreMarketsFixture('dota_yes_gl_bo3');
      await pumpSheet(tester, event);
      await tapChip(tester, 'Match');
      // The series handicap alone in its period: its kind in its label.
      expect(find.text('Handicap · GL -1.5'), findsOneWidget);
      final row = line('Handicap · GL -1.5');
      await tester.tap(find
          .descendant(of: row, matching: find.byType(PolyGameSideButton))
          .first);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final slip = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
      final market = event.outcomes.firstWhere((o) =>
          o.marketLine?.question ==
          'Game Handicap: GL (-1.5) vs Yellow Submarine (+1.5)');
      expect(slip.initialOutcomeIndex, 0);
      expect(slip.outcomes.first.tokenId, market.tokenId);
      expect((slip.sideLabelPos, slip.sideLabelNeg), ('GL -1.5', 'YS +1.5'));
      await closeSlip(tester);
    });
  });

  testWidgets('an Over / Under line opens on Over or Under with its line',
      (tester) async {
    await offline(() async {
      final event = moreMarketsFixture('lol_dk_blg_bo5');
      await pumpSheet(tester, event);
      await tapChip(tester, 'Game 4');
      final row = line('24.5');
      await tester.tap(find
          .descendant(of: row, matching: find.byType(PolyGameSideButton))
          .last);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final slip = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
      final market = event.outcomes.firstWhere((o) =>
          o.marketLine?.question == 'Total Kills Over/Under 24.5 in Game 4?');
      expect(slip.initialOutcomeIndex, 1);
      expect(slip.outcomes.last.tokenId, market.noTokenId);
      expect(
          (slip.sideLabelPos, slip.sideLabelNeg), ('Over 24.5', 'Under 24.5'));
      expect(slip.marketQuestion, 'Total Kills Over/Under 24.5 in Game 4?');
      await closeSlip(tester);
    });
  });

  testWidgets('CS2: decided lines fold into "Settled" at the foot',
      (tester) async {
    await offline(() async {
      final event = moreMarketsFixture('cs2_inox_honved_bo3');
      await pumpSheet(tester, event);
      expect(chipLabels(tester), ['All', 'Match', 'Map 1', 'Map 2', 'Map 3']);
      await tapChip(tester, 'Map 1');
      // Map 1's winner went to Honvéd (INOX at <1%): settled, folded.
      expect(find.text('Winner'), findsNothing);
      expect(find.text('Settled · 1'), findsOneWidget);
      await tester.tap(find.text('Settled · 1'));
      await tester.pump();
      expect(find.text('Winner'), findsOneWidget);
      expect(
          tester
              .widgetList<PolyGameSideButton>(find.descendant(
                  of: line('Winner'),
                  matching: find.byType(PolyGameSideButton)))
              .map((b) => (b.label, b.pctText, b.muted)),
          [('INOX', '<1%', true), ('Honvéd', '>99%', true)]);
      // Its round lines never traded.
      expect(find.textContaining('Not trading yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a line that settles on the live feed moves to "Settled"',
      (tester) async {
    await offline(() async {
      final event = moreMarketsFixture('dota_yes_gl_bo3');
      final market = event.outcomes.firstWhere((o) =>
          o.marketLine?.question ==
          'Dota 2: Yellow Submarine vs GamerLegion - Game 1 Winner');
      await pumpSheet(tester, event);
      await tapChip(tester, 'Game 1');
      expect(find.text('Winner'), findsOneWidget);
      expect(find.textContaining('Settled'), findsNothing);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(MarketDetailSheet)));
      (container.read(livePriceProvider.notifier) as _Prices)
          .tick(market.tokenId!, 0.004);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Winner'), findsNothing);
      expect(find.text('Settled · 1'), findsOneWidget);
    });
  });

  testWidgets(
      'football More Markets: Match, 1st half, 2nd half; the board\'s '
      'Over / Under tiles are the lines\' button', (tester) async {
    await offline(() async {
      final event = moreMarketsFixture('arsenal_hull_more_markets');
      await pumpSheet(tester, event);
      expect(chipLabels(tester), ['All', 'Match', '1st half', '2nd half']);
      // The board's total: the same button, the board's size.
      final board = tester
          .widgetList<PolyGameSideButton>(find.byType(PolyGameSideButton))
          .where((b) => !b.dense && b.label.startsWith('Over '));
      expect(board, isNotEmpty);
      await tapChip(tester, '1st half');
      // One handicap trades in the half: its kind in its label. Four goal
      // lines under their heading.
      expect(sidesOf(tester, 'Handicap · Arsenal -1.5'),
          ['Arsenal -1.5', 'Hull City +1.5']);
      expect(inMore(find.text('OVER-UNDER')), findsOneWidget);
      expect(sidesOf(tester, '1.5'), ['Over', 'Under']);
      expect(find.text('Team totals · Arsenal 1.5'), findsOneWidget);
      expect(find.text('Both Teams to Score'), findsOneWidget);
      expect(inMore(find.textContaining('Arsenal FC vs.')), findsNothing);
      expect(inMore(find.textContaining('1st Half')), findsNothing);
      // The books nobody has traded fold away.
      expect(find.textContaining('Not trading yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  /// A US game read from Gamma: [markets] as (type, line, question,
  /// sides, first price).
  PolymarketEvent usGame(String title,
          List<(String, double?, String, List<String>, double)> markets) =>
      PolymarketModel().parseEventsRaw([
        {
          'id': '1',
          'slug': 'nba-mia-gsw-2026-11-05',
          'title': title,
          'gameId': 20024065,
          'tags': [
            {'slug': 'sports'},
          ],
          'teams': [
            {'name': 'Heat', 'abbreviation': 'mia', 'ordering': 'away'},
            {'name': 'Warriors', 'abbreviation': 'gsw', 'ordering': 'home'},
          ],
          'markets': [
            for (final (i, (type, line, q, sides, p)) in markets.indexed)
              {
                'id': 'm$i',
                'question': q,
                'sportsMarketType': type,
                'line': line,
                'outcomes': '["${sides[0]}", "${sides[1]}"]',
                'outcomePrices': '["$p", "${(1 - p).toStringAsFixed(3)}"]',
                'clobTokenIds': '["m${i}a", "m${i}b"]',
                'conditionId': '0xm$i',
              },
          ],
        }
      ]).single;

  testWidgets('a game in quarters: "Full game", the halves, the quarters',
      (tester) async {
    await offline(() async {
      final event = usGame('Heat vs. Warriors', [
        ('moneyline', null, 'Heat vs. Warriors', ['Heat', 'Warriors'], 0.285),
        (
          'spreads',
          -4.5,
          'Spread: Warriors (-4.5)',
          ['Warriors', 'Heat'],
          0.59
        ),
        (
          'spreads',
          -6.5,
          'Spread: Warriors (-6.5)',
          ['Warriors', 'Heat'],
          0.45
        ),
        (
          'totals',
          235.5,
          'Heat vs. Warriors: O/U 235.5',
          ['Over', 'Under'],
          0.495
        ),
        (
          'first_half_moneyline',
          null,
          'Heat vs. Warriors: 1H Moneyline',
          ['Heat', 'Warriors'],
          0.345
        ),
        (
          'first_half_totals',
          119.5,
          'Heat vs. Warriors: 1H O/U 119.5',
          ['Over', 'Under'],
          0.57
        ),
        (
          'q1_spreads',
          -1.5,
          '1Q Spread: Warriors (-1.5)',
          ['Warriors', 'Heat'],
          0.52
        ),
        (
          'q3_totals',
          58.5,
          'Heat vs. Warriors: 3Q O/U 58.5',
          ['Over', 'Under'],
          0.47
        ),
      ]);
      await pumpSheet(tester, event);
      expect(chipLabels(tester), ['All', 'Full game', '1st half', 'Q1', 'Q3']);
      await tapChip(tester, '1st half');
      expect(sidesOf(tester, 'Winner'), ['Heat', 'Warriors']);
      expect(sidesOf(tester, 'Over-Under · 119.5'), ['Over', 'Under']);
      await tapChip(tester, 'Q1');
      expect(sidesOf(tester, 'Handicap · Warriors -1.5'),
          ['Warriors -1.5', 'Heat +1.5']);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a game of one period has no period chips', (tester) async {
    await offline(() async {
      final event = usGame('Heat vs. Warriors', [
        ('moneyline', null, 'Heat vs. Warriors', ['Heat', 'Warriors'], 0.285),
        (
          'spreads',
          -4.5,
          'Spread: Warriors (-4.5)',
          ['Warriors', 'Heat'],
          0.59
        ),
        (
          'spreads',
          -6.5,
          'Spread: Warriors (-6.5)',
          ['Warriors', 'Heat'],
          0.45
        ),
        (
          'totals',
          235.5,
          'Heat vs. Warriors: O/U 235.5',
          ['Over', 'Under'],
          0.495
        ),
        (
          'totals',
          239.5,
          'Heat vs. Warriors: O/U 239.5',
          ['Over', 'Under'],
          0.41
        ),
      ]);
      await pumpSheet(tester, event);
      expect(find.text('More markets'), findsOneWidget);
      expect(find.byKey(const ValueKey('game-period-chips')), findsNothing);
      expect(find.byKey(const ValueKey('game-type-chips')), findsNothing);
      // The two lines the board does not show (it has the most even:
      // Warriors -6.5, 235.5), each with its kind.
      expect(sidesOf(tester, 'Handicap · Warriors -4.5'),
          ['Warriors -4.5', 'Heat +4.5']);
      expect(sidesOf(tester, 'Over-Under · 239.5'), ['Over', 'Under']);
    });
  });

  test('a line\'s status: open, not trading yet, settled', () {
    PolymarketOutcome o(double p,
            {bool unpriced = false, bool closed = false}) =>
        PolymarketOutcome(
          name: 'x',
          price: p,
          tokenId: 't',
          noTokenId: 'n',
          unpriced: unpriced,
          marketLine: PolymarketMarketLine(
              kind: 'totals', question: 'x', closed: closed),
        );
    expect(gameLineStatus(const {}, const {}, o(0.42)), GameLineStatus.open);
    expect(gameLineStatus(const {}, const {}, o(0.42, unpriced: true)),
        GameLineStatus.notTrading);
    // Gamma's untouched 50/50, with no live price.
    expect(
        gameLineStatus(const {}, const {}, o(0.5)), GameLineStatus.notTrading);
    expect(gameLineStatus(const {'t': 0.5}, const {}, o(0.5)),
        GameLineStatus.open);
    expect(
        gameLineStatus(const {}, const {}, o(0.995)), GameLineStatus.settled);
    expect(
        gameLineStatus(const {}, const {}, o(0.004)), GameLineStatus.settled);
    expect(gameLineStatus(const {}, const {}, o(0.6, closed: true)),
        GameLineStatus.settled);
    // The live feed's word wins: a wide, untraded book has no price.
    expect(gameLineStatus(const {}, const {'t'}, o(0.42)),
        GameLineStatus.notTrading);
    // 99% is still open; past it, settled.
    expect(gameLineStatus(const {'t': 0.99}, const {}, o(0.42)),
        GameLineStatus.open);
  });

  test('period and kind names', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    String name(GamePeriod p, {bool fullGame = false}) =>
        gamePeriodName(l10n, p, fullGame: fullGame);
    expect(name(GamePeriod.whole), 'Match');
    // A sport played in quarters or innings calls it the full game.
    expect(name(GamePeriod.whole, fullGame: true), 'Full game');
    expect(name(const GamePeriod(GamePeriodUnit.game, 2)), 'Game 2');
    expect(name(const GamePeriod(GamePeriodUnit.map, 1)), 'Map 1');
    expect(name(const GamePeriod(GamePeriodUnit.set, 3)), 'Set 3');
    expect(name(const GamePeriod(GamePeriodUnit.half, 2)), '2nd half');
    expect(name(const GamePeriod(GamePeriodUnit.quarter, 3)), 'Q3');
    expect(name(const GamePeriod(GamePeriodUnit.period, 2)), 'Period 2');
    expect(gameLineTypeName(l10n, GameLineType.kills), 'Total kills');
    expect(gameLineTypeName(l10n, GameLineType.handicap), 'Handicap');
    expect(gameLineTypeName(l10n, GameLineType.other), 'Other predictions');
  });
}
