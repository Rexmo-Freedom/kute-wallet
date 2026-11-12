// Football pages the founder showed on 12 November 2026.
//
//   * "FK Shakhtar Donetsk vs. Fenerbahçe SK - Total Corners", the REAL
//     Gamma event (test/fixtures/polymarket_games/
//     ucl_shakhtar_fenerbahce_total_corners.json, read on 12 November): 18
//     markets that are FOUR ladders (Total Corners 7.5 … 13.5, 1st Half
//     Total Corners 3.5 … 5.5, each team's Corners 2.5 … 5.5), none of
//     them trading (5¢ bids, 99¢ asks, no trade). It read as a headline
//     "Fenerbahçe SK O/U 2.5 Corners 53%", five jagged lines and rows of
//     "OVER —". It now says once that it is not open yet: no chart, no
//     rows. The same event with books on some lines is a page of ladders:
//     a group picker "Total · 1st half · Shakhtar · Fenerbahçe", and for
//     the group picked one question with its line stepper, its own chart
//     and its two sides with prices.
//   * Two more real events for the shapes that exist: "Liversedge FC vs.
//     Ossett United FC - Total Corners" (adds 2nd Half, "Odd or Even?"
//     and "Team to Take First Corner"; every line last traded at 99¢:
//     decided, not offered) and "FK Dynamo Kyiv vs. FK Livyi Bereh - More
//     Markets" (spreads, goals O/U, halves, team totals, both teams to
//     score), which with its game behind it keeps the game board.
//   * "Sabah FK vs. FC Barcelona - Total Corners"
//     (ucl_sabah_barcelona_total_corners.json): one ladder alone.
//   * "FK Shakhtar Donetsk vs. Fenerbahçe SK" (ucl_shakhtar_fenerbahce.json):
//     its WINNER buttons read "Donetsk" / "SK" in a heavier blue and purple
//     than their chart lines. Now "Shakhtar" / "Draw" / "Fenerbahçe", each
//     button exactly its line's colour, lettered in the ink that reads on
//     it.
//
// Renders: --dart-define=LADDER_RENDER_OUT=<dir> writes the pages, light
// and dark, at 320 pt and text x1.5 (test/helpers/render_png.dart).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
import 'package:kute/screens/polymarket/components/game_chart_section.dart'
    show kGameSideColors;
import 'package:kute/screens/polymarket/components/game_header.dart'
    show polySportsTeams;
import 'package:kute/screens/polymarket/components/game_side_button.dart';
import 'package:kute/screens/polymarket/components/line_ladder.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart' show KutePill;
import 'package:kute/services/polymarket/live_game/game_sides.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/render_png.dart';
import '../../helpers/shell_bar_harness.dart';

const _renderOut = String.fromEnvironment('LADDER_RENDER_OUT');

Map<String, dynamic> _raw(String name) => jsonDecode(
        File('test/fixtures/polymarket_games/$name.json').readAsStringSync())
    as Map<String, dynamic>;

PolymarketEvent _parse(Map<String, dynamic> raw) =>
    PolymarketModel().parseEventsRaw([raw]).single;

PolymarketEvent _fixture(String name) => _parse(_raw(name));

const _corners = 'ucl_sabah_barcelona_total_corners';
const _shakhtar = 'ucl_shakhtar_fenerbahce';
const _shakhtarCorners = 'ucl_shakhtar_fenerbahce_total_corners';
const _liversedge = 'efa_liversedge_ossett_total_corners';
const _dynamo = 'ukr1_dynamo_livyi_more_markets';

/// The real Shakhtar corners event with books on some of its lines (the
/// real one has none): Total Corners 7.5 … 11.5, Fenerbahçe's 2.5 … 4.5
/// and one 1st Half line; Shakhtar's own ladder stays without a price.
Map<String, dynamic> _shakhtarCornersWithBooks() {
  final raw = _raw(_shakhtarCorners);
  const books = <String, (double, double, double)>{
    ': O/U 7.5 Total Corners': (0.76, 0.80, 400),
    ': O/U 8.5 Total Corners': (0.60, 0.64, 400),
    ': O/U 9.5 Total Corners': (0.47, 0.50, 400),
    ': O/U 10.5 Total Corners': (0.33, 0.37, 400),
    ': O/U 11.5 Total Corners': (0.20, 0.24, 400),
    ': Fenerbahçe SK O/U 2.5 Corners': (0.80, 0.84, 50),
    ': Fenerbahçe SK O/U 3.5 Corners': (0.58, 0.62, 50),
    ': Fenerbahçe SK O/U 4.5 Corners': (0.36, 0.40, 50),
    ': 1st Half O/U 4.5 Total Corners': (0.44, 0.48, 20),
  };
  for (final m in (raw['markets'] as List).cast<Map<String, dynamic>>()) {
    final q = m['question'] as String;
    for (final e in books.entries) {
      if (!q.endsWith(e.key)) continue;
      final (bid, ask, volume) = e.value;
      final mid = (bid + ask) / 2;
      m['bestBid'] = bid;
      m['bestAsk'] = ask;
      m['spread'] = ask - bid;
      m['volumeNum'] = volume;
      m['outcomePrices'] =
          jsonEncode([mid.toStringAsFixed(3), (1 - mid).toStringAsFixed(3)]);
    }
  }
  return raw;
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

List<Override> _overrides() => [
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
          PolyGameLines.fromEvent(_fixture(slug.contains('sha')
              ? _shakhtar
              : slug.contains('dyn')
                  ? _dynamo
                  : _corners))),
      polymarketActivePositionsProvider.overrideWithValue(const []),
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      aiEnabledProvider.overrideWith((ref) async => false),
    ];

final _shot = GlobalKey();

Future<void> _pump(WidgetTester tester, PolymarketEvent event,
    {double width = 320, double textScale = 1.5, bool dark = false}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  installShellBar();
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(),
    child: RepaintBoundary(
      key: _shot,
      child: shellBarApp(
        dark: dark,
        wrap: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: MarketDetailSheet(event: event),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// No text on screen is cut: no paragraph past its lines, none past the
/// view's edges.
void _expectNothingCut(WidgetTester tester, double width) {
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    if (!p.attached || !p.hasSize) continue;
    final text = p.text.toPlainText();
    expect(p.didExceedMaxLines, isFalse, reason: text);
    final r =
        MatrixUtils.transformRect(p.getTransformTo(null), Offset.zero & p.size);
    if (r.top > 1100 || r.bottom < 0) continue;
    // A pill row scrolls sideways: its far pills are a swipe away.
    if (find
        .ancestor(of: find.byWidget(e.widget), matching: find.byType(KutePill))
        .evaluate()
        .isNotEmpty) {
      continue;
    }
    expect(r.left, greaterThanOrEqualTo(-0.5), reason: text);
    expect(r.right, lessThanOrEqualTo(width + 0.5), reason: text);
  }
}

Future<void> _settleAway(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  PolyLineLadder single(String name) =>
      polyLadderBoard(_fixture(name))!.groups.single;

  List<String> labels(PolymarketEvent event) {
    final board = polyLadderBoard(event)!;
    final teams = polySportsTeams(event, const [])!;
    final short =
        gameShortSideNames(teams.teamA, teams.teamB, teams: event.teams);
    return polyLadderGroupLabels(
      board.groups,
      teamA: teams.teamA,
      teamB: teams.teamB,
      shortA: short.$1,
      shortB: short.$2,
      total: 'Total',
      firstHalf: '1st half',
      secondHalf: '2nd half',
      spread: 'Spread',
    );
  }

  group('reading ladders', () {
    test('one ladder: the Sabah corners event, six lines, Over / Under', () {
      final board = polyLadderBoard(_fixture(_corners))!;
      expect(board.others, isEmpty);
      final ladder = board.groups.single;
      expect([for (final l in ladder.lines) l.lineText],
          ['7.5', '8.5', '9.5', '10.5', '11.5', '12.5']);
      expect(ladder.overUnder, isTrue);
      expect(ladder.stem, 'Total Corners');
      // The fixture is the header's, never the question's.
      expect(ladder.lines[1].question, 'O/U 8.5 Total Corners');
    });

    test('only a line with a real price is offered; it opens nearest 50%', () {
      final ladder = single(_corners);
      final shown = polyLadderShownLines(ladder, const {}, const {});
      // 12.5: a book wider than 10¢ that never traded.
      expect([for (final l in shown) l.lineText],
          ['7.5', '8.5', '9.5', '10.5', '11.5']);
      expect(shown[polyLadderDefaultIndex(shown, const {}, const {})].lineText,
          '8.5');
      // A live price moves the default: 9.5 at 49% is now nearest.
      final live = {ladder.lines[2].outcome.tokenId!: 0.49};
      final again = polyLadderShownLines(ladder, live, const {});
      expect(
          again[polyLadderDefaultIndex(again, live, const {})].lineText, '9.5');
      // A line already decided is not offered either.
      final decided = {ladder.lines[0].outcome.tokenId!: 0.995};
      expect([
        for (final l in polyLadderShownLines(ladder, decided, const {}))
          l.lineText
      ], [
        '8.5',
        '9.5',
        '10.5',
        '11.5'
      ]);
      // With no line trading the group offers none.
      final none = {for (final l in ladder.lines) l.outcome.tokenId!};
      expect(polyLadderShownLines(ladder, const {}, none), isEmpty);
      expect(polyLadderDefaultGroup([ladder], const {}, none), isNull);
    });

    test('the real Shakhtar corners event is four ladders, none trading', () {
      final event = _fixture(_shakhtarCorners);
      final board = polyLadderBoard(event)!;
      expect(board.others, isEmpty);
      expect([
        for (final g in board.groups) g.stem
      ], [
        'Total Corners',
        '1st Half Total Corners',
        'FK Shakhtar Donetsk Corners',
        'Fenerbahçe SK Corners',
      ]);
      expect([
        for (final g in board.groups) [for (final l in g.lines) l.lineText]
      ], [
        ['7.5', '8.5', '9.5', '10.5', '11.5', '12.5', '13.5'],
        ['3.5', '4.5', '5.5'],
        ['2.5', '3.5', '4.5', '5.5'],
        ['2.5', '3.5', '4.5', '5.5'],
      ]);
      expect(board.groups.every((g) => g.overUnder), isTrue);
      expect(labels(event), ['Total', '1st half', 'Shakhtar', 'Fenerbahçe']);
      // 5¢ bids and 99¢ asks, never traded: nothing to offer.
      for (final g in board.groups) {
        expect(polyLadderShownLines(g, const {}, const {}), isEmpty);
      }
      expect(polyLadderDefaultGroup(board.groups, const {}, const {}), isNull);
    });

    test('with books it opens on the group with the most volume', () {
      final event = _parse(_shakhtarCornersWithBooks());
      final board = polyLadderBoard(event)!;
      expect(polyLadderDefaultGroup(board.groups, const {}, const {}), 0);
      expect([
        for (final g in board.groups)
          [
            for (final l in polyLadderShownLines(g, const {}, const {}))
              l.lineText
          ]
      ], [
        ['7.5', '8.5', '9.5', '10.5', '11.5'],
        ['4.5'],
        <String>[],
        ['2.5', '3.5', '4.5'],
      ]);
      // A tie keeps the earlier group; a busier one takes over.
      final fen = board.groups[3];
      final live = {
        for (final g in board.groups.take(2))
          for (final l in g.lines) l.outcome.tokenId!,
      };
      expect(polyLadderDefaultGroup(board.groups, const {}, live), 3);
      expect(fen.volume, 150);
    });

    test(
        'the real Liversedge corners event: five ladders and two markets '
        'of their own, every line decided', () {
      final event = _fixture(_liversedge);
      final board = polyLadderBoard(event)!;
      expect(labels(event), [
        'Total',
        '1st half',
        '2nd half',
        'Liversedge',
        'Ossett',
      ]);
      expect([for (final o in board.others) o.marketLine?.kind],
          ['soccer_game_corners_odd_even', 'soccer_first_corner']);
      // Wide books whose one trade was at 99¢: decided, never "Over 99%".
      expect(polyLadderDefaultGroup(board.groups, const {}, const {}), isNull);
    });

    test('the real More Markets event: spreads, goals, halves, team totals',
        () {
      final event = _fixture(_dynamo);
      final board = polyLadderBoard(event)!;
      expect(labels(event), [
        'Spread Dynamo Kyiv',
        'Spread Livyi Bereh',
        'Total',
        '1st half',
        'Dynamo Kyiv',
        'Livyi Bereh',
        'Dynamo Kyiv 1st half',
        'Livyi Bereh 1st half',
        '2nd half',
        'Dynamo Kyiv 2nd half',
        'Livyi Bereh 2nd half',
      ]);
      expect([for (final l in board.groups[0].lines) l.lineText],
          ['-2.5', '-1.5']);
      expect(board.groups[0].spread, isTrue);
      expect(board.groups[0].overUnder, isFalse);
      expect([for (final l in board.groups[2].lines) l.lineText],
          ['0.5', '1.5', '2.5', '3.5', '4.5', '5.5']);
      // Both teams to score (and its halves) are no line of a ladder.
      expect([
        for (final o in board.others) o.marketLine?.kind
      ], [
        'both_teams_to_score',
        'both_teams_to_score_first_half',
        'both_teams_to_score_second_half',
      ]);
    });

    test('two groups that would read alike write what they count', () {
      PolyLineLadder g(String stem) => PolyLineLadder(
          key: stem,
          stem: stem,
          kind: '',
          lines: const [],
          sideA: 'Over',
          sideB: 'Under');
      expect(
          polyLadderGroupLabels(
            [g('Total Corners'), g('Total Cards'), g('1st Half Total Cards')],
            total: 'Total',
            firstHalf: '1st half',
            secondHalf: '2nd half',
            spread: 'Spread',
          ),
          ['Total Corners', 'Total Cards', '1st half']);
    });

    test('other football pages are not pages of ladders', () {
      for (final name in [
        _shakhtar,
        'ukr1_dynamo_livyi_first_to_score',
        'leeds_man_united',
        'sunderland_brighton',
        'cs2_inox_honved_bo3',
        'dota_yes_gl_bo3',
        'lol_dk_blg_bo5',
        'tennis_fils_fritz',
      ]) {
        expect(polyLadderBoard(_fixture(name)), isNull, reason: name);
      }
    });

    test('a ladder outside sports keeps its list', () {
      PolymarketOutcome o(String name, int i) => PolymarketOutcome(
            name: name,
            question: 'Will inflation be above $name in 2026?',
            price: 0.4,
            tokenId: 't$i',
            noTokenId: 'n$i',
          );
      final cpi = PolymarketEvent(
        id: '1',
        slug: 'cpi',
        title: 'Inflation in 2026?',
        volume: 1,
        liquidity: 1,
        category: 'economy',
        conditionId: 'c',
        outcomes: [o('2.5%', 1), o('3.5%', 2), o('4.5%', 3)],
      );
      expect(polyLadderBoard(cpi), isNull);
    });
  });

  group('short names and colours of a three-way match', () {
    test('Shakhtar and Fenerbahçe, never "Donetsk" and "SK"', () {
      final event = _fixture(_shakhtar);
      expect(
          gameShortSideNames('FK Shakhtar Donetsk', 'Fenerbahçe SK',
              teams: event.teams),
          ('Shakhtar', 'Fenerbahçe'));
      expect(gameShortSideNames('FK Shakhtar Donetsk', 'Fenerbahçe SK'),
          ('Shakhtar', 'Fenerbahçe'));
      expect(
          gameShortSideNames('AC Milan', 'SL Benfica'), ('Milan', 'Benfica'));
      // The names that read well before still do.
      expect(gameShortSideNames('Leeds United FC', 'Manchester United FC'),
          ('Leeds United', 'Manchester'));
    });

    testWidgets('a side button is exactly its line\'s colour, dark ink',
        (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
                theme: ThemeData(extensions: [AppColorsExtension.light()]),
                home: Row(children: [
                  for (final color in kGameSideColors)
                    Expanded(
                      child: PolyGameSideButton(
                        label: 'Side',
                        pctText: '36.5%',
                        lineColor: color,
                        onTap: () {},
                      ),
                    ),
                ]),
              )));
      final boxes = tester
          .widgetList<Container>(find.descendant(
              of: find.byType(PolyGameSideButton),
              matching: find.byType(Container)))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .toList();
      expect(boxes, kGameSideColors);
      for (final t in tester.widgetList<Text>(find.text('Side'))) {
        expect(t.style!.color, Colors.black);
      }
    });
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets(
        'the corners page is one question with a line stepper '
        '($mode, 320 pt, text x1.5)', (tester) async {
      await http.runWithClient(() async {
        if (_renderOut.isNotEmpty) await tester.runAsync(loadRenderFonts);
        final event = _fixture(_corners);
        await _pump(tester, event, dark: dark);

        // The stepper, on 8.5: the line nearest 50%.
        expect(find.byKey(const ValueKey('ladder-stepper')), findsOneWidget);
        final stepper =
            tester.widget<PolyLineStepper>(find.byType(PolyLineStepper));
        expect(stepper.lines, ['7.5', '8.5', '9.5', '10.5', '11.5']);
        expect(stepper.lines[stepper.selected], '8.5');

        // The headline: the line's question, no fixture, and Over's chance.
        expect(find.text('O/U 8.5 Total Corners'), findsOneWidget);
        expect(find.textContaining('Sabah FK vs. FC Barcelona:'), findsNothing);
        expect(find.byKey(const ValueKey('ladder-hero')), findsOneWidget);

        // Both sides, with their prices; no "—" and no "OVER" rows.
        final a = find.byKey(const ValueKey('ladder-side-a'));
        final b = find.byKey(const ValueKey('ladder-side-b'));
        expect(find.descendant(of: a, matching: find.text('Over 8.5')),
            findsOneWidget);
        String pct(Finder f) => tester.widget<PolyGameSideButton>(f).pctText;
        expect(pct(a), '53.5%');
        expect(find.descendant(of: b, matching: find.text('Under 8.5')),
            findsOneWidget);
        expect(pct(b), '46.5%');
        expect(find.text('—'), findsNothing);
        expect(find.textContaining('OVER'), findsNothing);
        expect(
            tester.widget<PolyGameSideButton>(a).lineColor, kGameSideColors[0]);
        expect(
            tester.widget<PolyGameSideButton>(b).lineColor, kGameSideColors[1]);

        // The chart: the line's two sides, tagged apart, in the buttons'
        // colours.
        final chart = tester.widget<MarketChart>(find.byType(MarketChart));
        expect(
            [for (final l in chart.lines!) l.label], ['Over 8.5', 'Under 8.5']);
        expect([for (final l in chart.lines!) l.color],
            [kGameSideColors[0], kGameSideColors[1]]);
        final line = single(_corners).lines[1].outcome;
        expect([for (final l in chart.lines!) l.tokenId],
            [line.tokenId, line.noTokenId]);

        _expectNothingCut(tester, 320);
        expect(tester.takeException(), isNull);
        if (_renderOut.isNotEmpty) {
          await writeRenderPng(
              tester, _shot, '$_renderOut/corners_ladder_$mode.png');
        }

        // The chevron steps to 9.5: its question, its chart, its prices.
        await tester.tap(find.byKey(const ValueKey('line-stepper-next')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('O/U 9.5 Total Corners'), findsOneWidget);
        expect(find.descendant(of: a, matching: find.text('Over 9.5')),
            findsOneWidget);
        expect(pct(a), '40%');
        expect(pct(b), '60%');
        expect([
          for (final l
              in tester.widget<MarketChart>(find.byType(MarketChart)).lines!)
            l.label
        ], [
          'Over 9.5',
          'Under 9.5'
        ]);
        _expectNothingCut(tester, 320);

        // A side opens the slip on it, its sides named as the buttons.
        await tester.tap(b);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final slip = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
        expect(slip.initialOutcomeIndex, 1);
        expect(slip.sideLabelPos, 'Over 9.5');
        expect(slip.sideLabelNeg, 'Under 9.5');
        final nine = single(_corners).lines[2].outcome;
        expect([for (final o in slip.outcomes) o.tokenId],
            [nine.tokenId, nine.noTokenId]);
        await _settleAway(tester);
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });

    testWidgets(
        'the real Shakhtar corners page, nothing trading: it says so '
        'once, no chart, no rows ($mode, 320 pt, text x1.5)', (tester) async {
      await http.runWithClient(() async {
        if (_renderOut.isNotEmpty) await tester.runAsync(loadRenderFonts);
        await _pump(tester, _fixture(_shakhtarCorners), dark: dark);
        expect(find.text('Not open yet'), findsOneWidget);
        expect(find.text('No prices yet'), findsOneWidget);
        // Never the five jagged lines, the "OVER —" rows or a headline
        // nobody traded.
        expect(find.byType(MarketChart), findsNothing);
        expect(find.text('—'), findsNothing);
        expect(find.textContaining('OVER'), findsNothing);
        expect(find.textContaining('O/U'), findsNothing);
        expect(find.textContaining('53%'), findsNothing);
        expect(find.byType(PolyGameSideButton), findsNothing);
        expect(find.byType(PolyLineStepper), findsNothing);
        expect(find.byKey(const ValueKey('ladder-group-chips')), findsNothing);
        _expectNothingCut(tester, 320);
        expect(tester.takeException(), isNull);
        if (_renderOut.isNotEmpty) {
          await writeRenderPng(tester, _shot,
              '$_renderOut/shakhtar_corners_real_not_open_$mode.png');
        }
        await _settleAway(tester);
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });

    testWidgets(
        'the Shakhtar corners page with books: a group picker and '
        'one question at a time ($mode, 320 pt, text x1.5)', (tester) async {
      await http.runWithClient(() async {
        if (_renderOut.isNotEmpty) await tester.runAsync(loadRenderFonts);
        final event = _parse(_shakhtarCornersWithBooks());
        final board = polyLadderBoard(event)!;
        await _pump(tester, event, dark: dark);

        List<String> pills() => [
              for (final p in tester.widgetList<KutePill>(find.descendant(
                  of: find.byKey(const ValueKey('ladder-group-chips')),
                  matching: find.byType(KutePill, skipOffstage: false),
                  skipOffstage: false)))
                p.label
            ];
        KutePill pill(String label) => tester.widget<KutePill>(
            find.widgetWithText(KutePill, label, skipOffstage: false).first);
        PolyLineStepper stepper() =>
            tester.widget<PolyLineStepper>(find.byType(PolyLineStepper));
        PolyGameSideButton side(String s) => tester
            .widget<PolyGameSideButton>(find.byKey(ValueKey('ladder-side-$s')));
        MarketChart chart() =>
            tester.widget<MarketChart>(find.byType(MarketChart));
        Future<void> pick(String name) async {
          pill(name).onTap();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(milliseconds: 300));
        }

        // The picker, on Total: the group with the most volume.
        expect(pills(), ['Total', '1st half', 'Shakhtar', 'Fenerbahçe']);
        expect(pill('Total').selected, isTrue);
        // Its ladder: only the lines with a price, opened nearest 50%.
        expect(stepper().lines, ['7.5', '8.5', '9.5', '10.5', '11.5']);
        expect(stepper().lines[stepper().selected], '9.5');
        expect(find.text('O/U 9.5 Total Corners'), findsOneWidget);
        expect((side('a').label, side('a').pctText), ('Over 9.5', '48.5%'));
        expect((side('b').label, side('b').pctText), ('Under 9.5', '51.5%'));
        // One line's chart: Over and Under, never the event's five.
        expect([for (final l in chart().lines!) l.label],
            ['Over 9.5', 'Under 9.5']);
        expect(find.text('—'), findsNothing);
        expect(find.textContaining('OVER'), findsNothing);
        expect(find.text('Not open yet'), findsNothing);
        _expectNothingCut(tester, 320);
        expect(tester.takeException(), isNull);
        if (_renderOut.isNotEmpty) {
          await writeRenderPng(
              tester, _shot, '$_renderOut/shakhtar_corners_total_$mode.png');
        }

        // Fenerbahçe's corners: its own lines, question, chart and prices.
        await pick('Fenerbahçe');
        expect(pill('Fenerbahçe').selected, isTrue);
        expect(stepper().lines, ['2.5', '3.5', '4.5']);
        expect(stepper().lines[stepper().selected], '3.5');
        expect(find.text('Fenerbahçe SK O/U 3.5 Corners'), findsOneWidget);
        expect((side('a').label, side('a').pctText), ('Over 3.5', '60%'));
        expect((side('b').label, side('b').pctText), ('Under 3.5', '40%'));
        final fen = board.groups[3].lines[1].outcome;
        expect([for (final l in chart().lines!) l.tokenId],
            [fen.tokenId, fen.noTokenId]);
        _expectNothingCut(tester, 320);
        if (_renderOut.isNotEmpty) {
          await writeRenderPng(tester, _shot,
              '$_renderOut/shakhtar_corners_fenerbahce_$mode.png');
        }

        // A group of one line with a price: no stepper, its two sides.
        await pick('1st half');
        expect(find.byType(PolyLineStepper), findsNothing);
        expect(find.text('1st Half O/U 4.5 Total Corners'), findsOneWidget);
        expect((side('a').label, side('a').pctText), ('Over 4.5', '46%'));

        // Shakhtar's ladder has no price on any line: it says so, with no
        // chart, stepper or sides; the picker stays.
        await pick('Shakhtar');
        expect(find.text('Not open yet'), findsOneWidget);
        expect(find.byType(MarketChart), findsNothing);
        expect(find.byType(PolyLineStepper), findsNothing);
        expect(find.byType(PolyGameSideButton), findsNothing);
        expect(find.text('—'), findsNothing);
        expect(pills().length, 4);
        _expectNothingCut(tester, 320);
        expect(tester.takeException(), isNull);
        if (_renderOut.isNotEmpty) {
          await writeRenderPng(tester, _shot,
              '$_renderOut/shakhtar_corners_shakhtar_not_open_$mode.png');
        }

        // Back on Total, the line stepped to is kept per group.
        await pick('Total');
        await tester.tap(find.byKey(const ValueKey('line-stepper-next')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('O/U 10.5 Total Corners'), findsOneWidget);
        await pick('Fenerbahçe');
        expect(stepper().lines[stepper().selected], '3.5');
        await pick('Total');
        expect(stepper().lines[stepper().selected], '10.5');
        await _settleAway(tester);
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });

    testWidgets(
        'More Markets: with its game it keeps the game board; '
        'without one it is a page of ladders ($mode)', (tester) async {
      await http.runWithClient(() async {
        await _pump(tester, _fixture(_dynamo), dark: dark, textScale: 1);
        // The game's own board (Spread, Total) and "More markets".
        expect(find.byKey(const ValueKey('ladder-group-chips')), findsNothing);
        expect(find.text('SPREAD'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _settleAway(tester);

        // The same markets with no game behind them.
        final raw = _raw(_dynamo)..remove('gameId');
        await _pump(tester, _parse(raw), dark: dark, textScale: 1);
        expect(
            find.byKey(const ValueKey('ladder-group-chips')), findsOneWidget);
        // It opens on the goals total (the most volume), whose one line
        // with a price is 1.5 (last traded at 28¢): no stepper.
        expect(
            tester
                .widget<KutePill>(find.widgetWithText(KutePill, 'Total').first)
                .selected,
            isTrue);
        expect(find.byType(PolyLineStepper), findsNothing);
        final a = tester.widget<PolyGameSideButton>(
            find.byKey(const ValueKey('ladder-side-a')));
        expect((a.label, a.pctText), ('Over 1.5', '28%'));
        // Both teams to score is no line: a row of its own, with its price.
        expect(find.text('Both Teams to Score'), findsOneWidget);
        // Its halves have no price: not listed, never "—".
        expect(find.text('Both Teams to Score in First Half'), findsNothing);
        expect(find.text('—'), findsNothing);
        expect(tester.takeException(), isNull);
        await _settleAway(tester);
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });

    testWidgets(
        'the 1X2 page: short names, buttons in their lines\' colours '
        '($mode, 320 pt, text x1.5)', (tester) async {
      await http.runWithClient(() async {
        if (_renderOut.isNotEmpty) await tester.runAsync(loadRenderFonts);
        final event = _fixture(_shakhtar);
        await _pump(tester, event, dark: dark);
        expect(find.text('WINNER'), findsOneWidget);
        // Not a ladder: no stepper.
        expect(find.byType(PolyLineStepper), findsNothing);
        final buttons = tester
            .widgetList<PolyGameSideButton>(find.byType(PolyGameSideButton))
            .toList();
        expect([for (final b in buttons.take(3)) b.label],
            ['Shakhtar', 'Draw', 'Fenerbahçe']);
        expect(find.text('SK'), findsNothing);
        expect(find.text('Donetsk'), findsNothing);
        // Each button is its chart line's colour.
        final chart = tester.widget<MarketChart>(find.byType(MarketChart));
        expect([for (final b in buttons.take(3)) b.lineColor],
            [for (final l in chart.lines!) l.color]);
        expect([for (final l in chart.lines!) l.label],
            ['Shakhtar', 'Draw', 'Fenerbahçe']);
        _expectNothingCut(tester, 320);
        expect(tester.takeException(), isNull);
        if (_renderOut.isNotEmpty) {
          await writeRenderPng(
              tester, _shot, '$_renderOut/shakhtar_1x2_$mode.png');
        }
        await _settleAway(tester);
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });
  }
}
