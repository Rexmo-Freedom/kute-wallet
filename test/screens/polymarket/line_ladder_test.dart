// Football pages the founder showed on 12 November 2026:
//
//   * "Sabah FK vs. FC Barcelona - Total Corners" (test/fixtures/
//     polymarket_games/ucl_sabah_barcelona_total_corners.json): six markets
//     "O/U 7.5 … 12.5 Total Corners", outcomes Over / Under. It read as six
//     rows of "OVER —", each in another colour, under a chart whose tags
//     all said "Total Corners". It is a LINE LADDER now: one question, a
//     line stepper opening on the line nearest 50%, the line's own chart
//     (Over and Under, tagged "Over 8.5" / "Under 8.5") and its two sides
//     as buttons with their prices. 12.5 has a book wider than 10¢ that
//     never traded: no price, so it is not offered.
//   * "FK Shakhtar Donetsk vs. Fenerbahçe SK" (ucl_shakhtar_fenerbahce.json):
//     its WINNER buttons read "Donetsk" / "SK" in a heavier blue and purple
//     than their chart lines. Now "Shakhtar" / "Draw" / "Fenerbahçe", each
//     button exactly its line's colour, lettered in the ink that reads on
//     it.
//
// Renders: --dart-define=LADDER_RENDER_OUT=<dir> writes both pages, light
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
import 'package:kute/screens/polymarket/components/game_side_button.dart';
import 'package:kute/screens/polymarket/components/line_ladder.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/services/polymarket/live_game/game_sides.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/render_png.dart';
import '../../helpers/shell_bar_harness.dart';

const _renderOut = String.fromEnvironment('LADDER_RENDER_OUT');

PolymarketEvent _fixture(String name) => PolymarketModel().parseEventsRaw([
      jsonDecode(File('test/fixtures/polymarket_games/$name.json')
          .readAsStringSync()) as Map<String, dynamic>,
    ]).single;

const _corners = 'ucl_sabah_barcelona_total_corners';
const _shakhtar = 'ucl_shakhtar_fenerbahce';

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
          PolyGameLines.fromEvent(
              _fixture(slug.contains('sha') ? _shakhtar : _corners))),
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

  group('reading a ladder', () {
    test('the corners event is one question at six lines, Over / Under', () {
      final ladder = polyLineLadder(_fixture(_corners));
      expect(ladder, isNotNull);
      expect([for (final l in ladder!.lines) l.lineText],
          ['7.5', '8.5', '9.5', '10.5', '11.5', '12.5']);
      expect(ladder.overUnder, isTrue);
      // The fixture is the header's, never the question's.
      expect(ladder.lines[1].question, 'O/U 8.5 Total Corners');
    });

    test('a line nobody trades is not offered; it opens nearest 50%', () {
      final ladder = polyLineLadder(_fixture(_corners))!;
      final shown = polyLadderShownLines(ladder, const {}, const {});
      expect([for (final l in shown) l.lineText],
          ['7.5', '8.5', '9.5', '10.5', '11.5']);
      expect(shown[polyLadderDefaultIndex(shown, const {}, const {})].lineText,
          '8.5');
      // A live price moves the default: 9.5 at 49% is now nearest.
      final live = {ladder.lines[2].outcome.tokenId!: 0.49};
      final again = polyLadderShownLines(ladder, live, const {});
      expect(
          again[polyLadderDefaultIndex(again, live, const {})].lineText, '9.5');
      // With no line trading every unsettled line stays.
      final none = {for (final l in ladder.lines) l.outcome.tokenId!};
      expect(polyLadderShownLines(ladder, const {}, none).length, 6);
    });

    test('other football pages are not ladders', () {
      for (final name in [
        _shakhtar,
        'leeds_man_united',
        'sunderland_brighton',
        'arsenal_hull_more_markets',
        'cs2_inox_honved_bo3',
        'dota_yes_gl_bo3',
        'lol_dk_blg_bo5',
        'tennis_fils_fritz',
      ]) {
        expect(polyLineLadder(_fixture(name)), isNull, reason: name);
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
      expect(polyLineLadder(cpi), isNull);
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
        final line = polyLineLadder(event)!.lines[1].outcome;
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
        final nine = polyLineLadder(event)!.lines[2].outcome;
        expect([for (final o in slip.outcomes) o.tokenId],
            [nine.tokenId, nine.noTokenId]);
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
