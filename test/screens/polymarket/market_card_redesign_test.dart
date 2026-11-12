// The Predictions list card redesign (founder, 12 November 2026, "do all
// 3"): A what's moving, B one tap to the slip, C a tiny chart, on the
// three card shapes (many outcomes, Yes/No, a game).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/game_chart_section.dart'
    show kGameSideColors;
import 'dart:async';

import 'package:kute/providers/polymarket_card_spark_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart'
    show HlLineSparkline;
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/services/polymarket/poly_card_spark_store.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/services/polymarket/polymarket_feed_cache.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/render_png.dart' show loadRenderFonts;

Future<void> _pump(WidgetTester tester, Widget card,
    {bool dark = false,
    double width = 390,
    double textScale = 1,
    List<Override> overrides = const []}) async {
  tester.view.physicalSize = Size(width, 932);
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
          fontFamily: 'Inter',
          brightness: dark ? Brightness.dark : Brightness.light,
          extensions: [
            dark ? AppColorsExtension.dark() : AppColorsExtension.light()
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [card]),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// The Jensen Huang event of the wireframe: six dated outcomes.
List<PolymarketOutcome> _dated({double? leaderMove}) => [
      PolymarketOutcome(
          name: 'December 31, 2027',
          price: 0.84,
          tokenId: 'd27',
          noTokenId: 'd27n',
          dayMove: leaderMove),
      const PolymarketOutcome(
          name: 'March 31, 2027',
          price: 0.825,
          tokenId: 'm27',
          noTokenId: 'm27n',
          dayMove: 0.2),
      const PolymarketOutcome(
          name: 'December 31, 2026',
          price: 0.775,
          tokenId: 'd26',
          noTokenId: 'd26n'),
      const PolymarketOutcome(
          name: 'June 30, 2026', price: 0.4, tokenId: 'j26', noTokenId: 'x'),
      const PolymarketOutcome(
          name: 'March 31, 2026', price: 0.2, tokenId: 'm26', noTokenId: 'y'),
      const PolymarketOutcome(
          name: 'January 31, 2026', price: 0.1, tokenId: 'a26', noTokenId: 'z'),
    ];

/// Arsenal v Chelsea, a three-way: each side its own Yes/No market.
const _threeWay = [
  PolymarketOutcome(
      name: 'Will Arsenal win?',
      price: 0.58,
      tokenId: 'ars',
      noTokenId: 'arsN',
      dayMove: 0.09),
  PolymarketOutcome(
      name: 'Draw (Arsenal vs Chelsea)',
      price: 0.21,
      tokenId: 'drw',
      noTokenId: 'drwN'),
  PolymarketOutcome(
      name: 'Will Chelsea win?',
      price: 0.21,
      tokenId: 'che',
      noTokenId: 'cheN',
      dayMove: -0.09),
];

/// A store whose history answers at once with a climbing week.
List<Override> _sparks() => [
      polyCardSparkStoreProvider.overrideWith((ref) {
        final store = PolyCardSparkStore(fetch: (token, interval) async {
          final now = DateTime.now();
          return [
            for (var i = 0; i < 40; i++)
              PolymarketPricePoint(
                  timestamp: now.subtract(Duration(hours: 4 * (40 - i))),
                  price: 0.3 + i * 0.01),
          ];
        });
        ref.onDispose(store.dispose);
        return store;
      }),
    ];

void main() {
  // The app's own face, so a row lays out as on a phone.
  setUpAll(loadRenderFonts);

  group('A · what is moving', () {
    testWidgets(
        'many outcomes: rows at 14 with the leader semibold, bars 6 tall, '
        "the leader's day move beside its percent, no meta line",
        (tester) async {
      await _pump(
        tester,
        MarketCard(
          title: 'Jensen Huang announced resignation or removal?',
          outcomes: _dated(leaderMove: 0.06),
          volume: 20.2e6,
          category: 'tech',
          endDate: DateTime(2027, 4, 30),
          // The event's largest mover is another outcome's: not shown.
          dayMove: 0.2,
        ),
        width: 393,
      );
      final c = AppColorsExtension.light();
      final leader = tester.widget<Text>(find.text('December 31, 2027'));
      expect(leader.style!.fontSize, moreOrLessEquals(14.sp));
      expect(leader.style!.fontWeight, FontWeight.w600);
      expect(leader.style!.color, c.textPrimary);
      final second = tester.widget<Text>(find.text('March 31, 2027'));
      expect(second.style!.fontWeight, FontWeight.w500);
      expect(second.style!.color, c.textSecondary);
      expect(tester.getSize(find.byType(PolyOutcomeChanceBar).first).height,
          6);
      // The leader's own move, never the event's largest one, compact
      // and in green right after its percent, on its row.
      final delta = find.text('▲6');
      expect(delta, findsOneWidget);
      expect(tester.widget<Text>(delta).style!.color, AppColors.marketUp);
      final pct = find.text('84%');
      expect(tester.getCenter(delta).dy,
          moreOrLessEquals(tester.getCenter(pct).dy, epsilon: 2));
      expect(tester.getTopLeft(delta).dx,
          greaterThanOrEqualTo(tester.getTopRight(pct).dx));
      expect(tester.getTopLeft(delta).dx - tester.getTopRight(pct).dx,
          lessThan(8));
      expect(find.text('▲20'), findsNothing);
      expect(find.textContaining('pts today'), findsNothing);
      // No meta line: no closing date, no volume.
      expect(find.textContaining('Closes'), findsNothing);
      expect(find.textContaining('Apr 2027'), findsNothing);
      expect(find.textContaining(r'$20.2M'), findsNothing);
      // The bars still end on one edge, the leader's row as the others.
      final bars = find.byType(PolyOutcomeChanceBar);
      final ends = [
        for (var i = 0; i < 3; i++) tester.getTopRight(bars.at(i)).dx,
      ];
      expect(ends[1], moreOrLessEquals(ends[0], epsilon: 0.5));
      expect(ends[2], moreOrLessEquals(ends[0], epsilon: 0.5));
    });

    testWidgets('many outcomes: a fall is red, under a point is quiet',
        (tester) async {
      await _pump(
        tester,
        MarketCard(
          title: 'Jensen Huang announced resignation or removal?',
          outcomes: _dated(leaderMove: -0.04),
          volume: 20.2e6,
          category: 'tech',
          endDate: DateTime(2027, 4, 30),
        ),
      );
      final delta = find.text('▼4');
      expect(delta, findsOneWidget);
      expect(tester.widget<Text>(delta).style!.color, AppColors.marketDown);

      await _pump(
        tester,
        MarketCard(
          title: 'Jensen Huang announced resignation or removal?',
          outcomes: _dated(leaderMove: 0.004),
          volume: 20.2e6,
          category: 'tech',
          endDate: DateTime(2027, 4, 30),
        ),
      );
      expect(find.textContaining('▲'), findsNothing);
      expect(find.textContaining('▼'), findsNothing);
    });

    testWidgets("Yes/No: the day's move under the gauge's number",
        (tester) async {
      await _pump(
        tester,
        MarketCard(
          title: 'Fed cuts rates in December?',
          outcomes: const [
            PolymarketOutcome(name: 'Yes', price: 0.62, tokenId: 'y'),
            PolymarketOutcome(name: 'No', price: 0.39, tokenId: 'n'),
          ],
          volume: 48.1e6,
          category: 'economy',
          endDate: DateTime(2026, 12, 10),
          dayMove: 0.04,
        ),
      );
      final move = find.text('▲ 4');
      expect(move, findsOneWidget);
      expect(tester.widget<Text>(move).style!.color, AppColors.marketUp);
      // Under the figure, centred on it.
      final figure = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'RollingFigure');
      expect(tester.getTopLeft(move).dy,
          greaterThan(tester.getBottomLeft(figure.first).dy - 1));
      expect(tester.getCenter(move).dx,
          moreOrLessEquals(tester.getCenter(figure.first).dx, epsilon: 1));
      // No meta line under the question.
      expect(find.textContaining('Dec 2026'), findsNothing);
      expect(find.textContaining(r'$48.1M'), findsNothing);
    });

    testWidgets('Yes/No: under a point the gauge stays quiet',
        (tester) async {
      await _pump(
        tester,
        const MarketCard(
          title: 'Fed cuts rates in December?',
          outcomes: [
            PolymarketOutcome(name: 'Yes', price: 0.62),
            PolymarketOutcome(name: 'No', price: 0.39),
          ],
          volume: 0,
          category: 'economy',
          dayMove: -0.009,
        ),
      );
      expect(find.textContaining('▲'), findsNothing);
      expect(find.textContaining('▼'), findsNothing);
    });

    testWidgets(
        'a game in play: live dot and clock lead, one split bar in the '
        "teams' colours with the draw grey, the leader's move beside its "
        'chance, no volume', (tester) async {
      await _pump(
        tester,
        const MarketCard(
          title: 'Arsenal vs Chelsea',
          outcomes: _threeWay,
          volume: 3.4e6,
          category: 'sports',
          liveGame: PolyLiveGame(
              score: '2-1', clock: "67'", period: '2H', firstIsHome: true),
        ),
      );
      final live = find.text("Live · 67'");
      expect(live, findsOneWidget);
      expect(tester.getTopLeft(live).dy,
          lessThan(tester.getTopLeft(find.text('Arsenal')).dy));
      // No volume on a list card, beside the clock or anywhere.
      expect(find.textContaining('3.4M'), findsNothing);
      // One split bar: Arsenal, the draw, Chelsea.
      final boxes = tester
          .widgetList<ColoredBox>(find.descendant(
              of: find.byType(MarketCard),
              matching: find.byType(ColoredBox)))
          .map((b) => b.color)
          .toList();
      expect(boxes, contains(kGameSideColors[0]));
      expect(boxes, contains(kGameSideColors[1]));
      // The leader's move beside its chance, on Arsenal's row.
      final delta = find.text('▲9');
      expect(delta, findsOneWidget);
      expect(tester.widget<Text>(delta).style!.color, AppColors.marketUp);
      expect(tester.getCenter(delta).dy,
          moreOrLessEquals(tester.getCenter(find.text('Arsenal')).dy,
              epsilon: 3));
      expect(find.textContaining('pts today'), findsNothing);
      // Chelsea's fall is not the leader's: not shown.
      expect(find.textContaining('▼'), findsNothing);
      // The pills say the draw; no footer repeats it.
      expect(find.text('Draw 21%'), findsNothing);
    });

    testWidgets('a game before kickoff keeps only its kickoff in the footer',
        (tester) async {
      await _pump(
        tester,
        MarketCard(
          title: 'Arsenal vs Chelsea',
          outcomes: _threeWay,
          volume: 3.4e6,
          category: 'sports',
          gameStart: DateTime(2030, 10, 5, 20, 30),
        ),
      );
      expect(find.textContaining('Live'), findsNothing);
      expect(find.text('5 Oct 20:30'), findsOneWidget);
      expect(find.text('▲9'), findsOneWidget);
      expect(find.textContaining('vol'), findsNothing);
      expect(find.textContaining('3.4M'), findsNothing);
    });

    testWidgets('a closed game with no pills keeps the draw in its footer',
        (tester) async {
      await _pump(
        tester,
        MarketCard(
          title: 'Arsenal vs Chelsea',
          outcomes: _threeWay,
          volume: 3.4e6,
          category: 'sports',
          closed: true,
          gameStart: DateTime(2030, 10, 5, 20, 30),
        ),
      );
      expect(find.textContaining('Draw 21%'), findsOneWidget);
    });

    testWidgets('no stream tag on a list card', (tester) async {
      await _pump(
        tester,
        const MarketCard(
          title: 'Arsenal vs Chelsea',
          outcomes: _threeWay,
          volume: 3.4e6,
          category: 'sports',
          liveGame: PolyLiveGame(
              score: '2-1', clock: "67'", period: '2H', firstIsHome: true),
        ),
      );
      expect(find.text('Live stream'), findsNothing);
      expect(find.text('Esports live'), findsNothing);
    });

    test("each outcome keeps its own day move from Gamma, and the feed's "
        'disk copy keeps it', () {
      final events = PolymarketModel().parseEventsRaw([
        {
          'id': '1',
          'slug': 'multi',
          'title': 'Who wins?',
          'markets': [
            {
              'id': 'a',
              'question': 'Will A win?',
              'groupItemTitle': 'A',
              'outcomes': '["Yes","No"]',
              'outcomePrices': '["0.6","0.4"]',
              'clobTokenIds': '["ta","tan"]',
              'oneDayPriceChange': 0.06,
              'active': true,
            },
            {
              'id': 'b',
              'question': 'Will B win?',
              'groupItemTitle': 'B',
              'outcomes': '["Yes","No"]',
              'outcomePrices': '["0.3","0.7"]',
              'clobTokenIds': '["tb","tbn"]',
              'oneDayPriceChange': -0.12,
              'active': true,
            },
          ],
        },
        {
          'id': '2',
          'slug': 'single',
          'title': 'Will it rain?',
          'markets': [
            {
              'id': 'r',
              'question': 'Will it rain?',
              'outcomes': '["Yes","No"]',
              'outcomePrices': '["0.3","0.7"]',
              'clobTokenIds': '["ry","rn"]',
              'oneDayPriceChange': 0.05,
              'active': true,
            },
          ],
        },
      ]);
      final multi = events.firstWhere((e) => e.slug == 'multi');
      final a = multi.outcomes.firstWhere((o) => o.name == 'A');
      final b = multi.outcomes.firstWhere((o) => o.name == 'B');
      expect(a.dayMove, 0.06);
      expect(b.dayMove, -0.12);
      // The event's own figure is still the largest move.
      expect(multi.oneDayPriceChange, -0.12);
      final single = events.firstWhere((e) => e.slug == 'single');
      expect(single.outcomes.map((o) => o.dayMove), [0.05, -0.05]);
      final back = PolymarketFeedCache.eventFromJson(
          PolymarketFeedCache.eventToJson(multi));
      expect(back.outcomes.map((o) => o.dayMove), [0.06, -0.12]);
    });
  });

  group('B · one tap to the slip', () {
    testWidgets(
        'many outcomes: one quiet Yes pill per row hands its outcome to the '
        'list; the rest of the card opens the market', (tester) async {
      final picks = <PolyCardPick>[];
      var opened = 0;
      final outcomes = _dated();
      await _pump(
        tester,
        MarketCard(
          title: 'Jensen Huang announced resignation or removal?',
          outcomes: outcomes,
          volume: 20.2e6,
          category: 'tech',
          endDate: DateTime(2027, 4, 30),
          onTap: () => opened++,
          onPickSide: picks.add,
        ),
      );
      final c = AppColorsExtension.light();
      for (final label in ['Yes 84¢', 'Yes 82.5¢', 'Yes 77.5¢']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.style!.color, AppColors.marketUp);
        final pill = tester.widget<Container>(find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first);
        expect((pill.decoration! as BoxDecoration).color, c.surfaceLight);
      }
      // One per row, on its row, and the pills line up.
      expect(find.byType(PolySidePill), findsNWidgets(3));
      expect(tester.getCenter(find.text('Yes 82.5¢')).dy,
          moreOrLessEquals(tester.getCenter(find.text('March 31, 2027')).dy,
              epsilon: 2));
      final rights = [
        for (final p in tester.widgetList(find.byType(PolySidePill)))
          tester.getTopRight(find.byWidget(p)).dx
      ];
      expect(rights.toSet(), hasLength(1));
      await tester.tap(find.text('Yes 82.5¢'));
      expect(picks.single.outcome, same(outcomes[1]));
      expect(opened, 0);
      await tester.tap(find.text('Jensen Huang announced resignation or removal?'));
      expect(opened, 1);
      expect(picks, hasLength(1));
    });

    testWidgets('Yes/No: two pills, full width and 36 tall, Yes and No',
        (tester) async {
      final picks = <PolyCardPick>[];
      await _pump(
        tester,
        MarketCard(
          title: 'Fed cuts rates in December?',
          outcomes: const [
            PolymarketOutcome(name: 'Yes', price: 0.62, tokenId: 'y'),
            PolymarketOutcome(name: 'No', price: 0.39, tokenId: 'n'),
          ],
          volume: 48.1e6,
          category: 'economy',
          endDate: DateTime(2026, 12, 10),
          onPickSide: picks.add,
        ),
      );
      final pills = find.byType(PolySidePill);
      expect(pills, findsNWidgets(2));
      final card = tester.getRect(find.byType(MarketCard));
      final yes = tester.getRect(pills.first), no = tester.getRect(pills.last);
      expect(yes.height, moreOrLessEquals(36.h, epsilon: 0.5));
      expect(yes.width, moreOrLessEquals(no.width, epsilon: 0.5));
      // Edge to edge inside the card's padding.
      expect(yes.left - card.left, moreOrLessEquals(16.w, epsilon: 0.5));
      expect(card.right - no.right, moreOrLessEquals(16.w, epsilon: 0.5));
      await tester.tap(find.text('No 39¢'));
      await tester.tap(find.text('Yes 62¢'));
      expect(picks.map((p) => p.side), ['no', 'yes']);
    });

    testWidgets('a game: three neutral pills, team · draw · team',
        (tester) async {
      final picks = <PolyCardPick>[];
      await _pump(
        tester,
        MarketCard(
          title: 'Arsenal vs Chelsea',
          outcomes: _threeWay,
          volume: 3.4e6,
          category: 'sports',
          liveGame: const PolyLiveGame(
              score: '2-1', clock: "67'", period: '2H', firstIsHome: true),
          onPickSide: picks.add,
        ),
      );
      final c = AppColorsExtension.light();
      final labels = ['Arsenal 58¢', 'Draw 21¢', 'Chelsea 21¢'];
      for (final l in labels) {
        expect(tester.widget<Text>(find.text(l)).style!.color, c.textPrimary);
      }
      final xs = [for (final l in labels) tester.getCenter(find.text(l)).dx];
      expect(xs, orderedEquals([...xs]..sort()));
      for (final l in labels.reversed) {
        await tester.tap(find.text(l));
      }
      expect(picks.map((p) => p.way), [2, 1, 0]);
    });

    testWidgets('a closed market or a finished game has no pills',
        (tester) async {
      await _pump(
        tester,
        Column(children: [
          MarketCard(
            title: 'Jensen Huang announced resignation or removal?',
            outcomes: _dated(),
            volume: 1,
            category: 'tech',
            closed: true,
            onPickSide: (_) {},
          ),
          const MarketCard(
            title: 'Fed cuts rates in December?',
            outcomes: [
              PolymarketOutcome(name: 'Yes', price: 0.62),
              PolymarketOutcome(name: 'No', price: 0.39),
            ],
            volume: 1,
            category: 'economy',
            ended: true,
          ),
          MarketCard(
            title: 'Arsenal vs Chelsea',
            outcomes: _threeWay,
            volume: 1,
            category: 'sports',
            liveGame:
                const PolyLiveGame(score: '2-1', firstIsHome: true, finished: true),
            onPickSide: (_) {},
          ),
        ]),
      );
      expect(find.byType(PolySidePill), findsNothing);
    });

    testWidgets("with no slip door (Home's read-only card) a pill is the "
        "card's own tap", (tester) async {
      var opened = 0;
      await _pump(
        tester,
        MarketCard(
          title: 'Fed cuts rates in December?',
          outcomes: const [
            PolymarketOutcome(name: 'Yes', price: 0.62),
            PolymarketOutcome(name: 'No', price: 0.39),
          ],
          volume: 1,
          category: 'economy',
          onTap: () => opened++,
        ),
      );
      await tester.tap(find.text('Yes 62¢'));
      expect(opened, 1);
    });
  });

  group('C · tiny chart', () {
    late List<(String, String)> asked;
    late DateTime kickoff;

    /// A history that answers at once: a week of points (the last two
    /// hours at a point a minute), climbing.
    List<Override> answering({Completer<void>? hold}) => [
          polyCardSparkStoreProvider.overrideWith((ref) {
            final store = PolyCardSparkStore(fetch: (token, interval) async {
              asked.add((token, interval));
              if (hold != null) await hold.future;
              final now = DateTime.now();
              return [
                for (var i = 0; i < 40; i++)
                  PolymarketPricePoint(
                      timestamp: now.subtract(Duration(hours: 4 * (40 - i))),
                      price: 0.3 + i * 0.01),
                for (var m = 120; m > 0; m -= 10)
                  PolymarketPricePoint(
                      timestamp: now.subtract(Duration(minutes: m)),
                      price: 0.5),
              ];
            });
            ref.onDispose(store.dispose);
            return store;
          }),
        ];

    setUp(() {
      asked = [];
      kickoff = DateTime.now().subtract(const Duration(minutes: 72));
    });

    Future<void> land(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
    }

    HlLineSparkline spark(WidgetTester tester) =>
        tester.widget<HlLineSparkline>(find.byType(HlLineSparkline));

    testWidgets(
        "many outcomes: the leader's 7-day line top right, in its chart "
        'colour, ending on its chance', (tester) async {
      await _pump(
        tester,
        MarketCard(
          title: 'Jensen Huang announced resignation or removal?',
          outcomes: _dated(),
          volume: 20.2e6,
          category: 'tech',
          endDate: DateTime(2027, 4, 30),
        ),
        overrides: answering(),
      );
      await land(tester);
      expect(asked, [('d27', '1w')]);
      final line = spark(tester);
      final bar = tester.widgetList<PolyOutcomeChanceBar>(
          find.byType(PolyOutcomeChanceBar)).first;
      expect(line.upColor, bar.color);
      expect(line.downColor, bar.color);
      expect(line.baseline, isFalse);
      expect(line.closes.last, 0.84);
      final card = tester.getRect(find.byType(MarketCard));
      final at = tester.getRect(find.byType(HlLineSparkline));
      expect(card.right - at.right, moreOrLessEquals(16.w, epsilon: 1));
      expect(at.bottom,
          lessThan(tester.getTopLeft(find.text('December 31, 2027')).dy));
    });

    testWidgets('Yes/No: the 7-day Yes line in the neutral ink over the '
        'answers', (tester) async {
      await _pump(
        tester,
        MarketCard(
          title: 'Fed cuts rates in December?',
          outcomes: const [
            PolymarketOutcome(name: 'Yes', price: 0.62, tokenId: 'y'),
            PolymarketOutcome(name: 'No', price: 0.39, tokenId: 'n'),
          ],
          volume: 48.1e6,
          category: 'economy',
          endDate: DateTime(2026, 12, 10),
          onPickSide: (_) {},
        ),
        overrides: answering(),
      );
      await land(tester);
      expect(asked, [('y', '1w')]);
      final line = spark(tester);
      expect(line.upColor, AppColorsExtension.light().textPrimary);
      expect(line.closes.last, 0.62);
      final at = tester.getRect(find.byType(HlLineSparkline));
      final pills = tester.getRect(find.byType(PolySidePill).first);
      expect(at.bottom, lessThanOrEqualTo(pills.top));
      expect(at.width, moreOrLessEquals(pills.width * 2 + 8.w, epsilon: 1));
    });

    testWidgets(
        "a game in play: the leader's win chance since kickoff in its team "
        'colour', (tester) async {
      await _pump(
        tester,
        MarketCard(
          title: 'Arsenal vs Chelsea',
          outcomes: _threeWay,
          volume: 3.4e6,
          category: 'sports',
          gameStart: kickoff,
          liveGame: const PolyLiveGame(
              score: '2-1', clock: "67'", period: '2H', firstIsHome: true),
        ),
        overrides: answering(),
      );
      await land(tester);
      expect(asked, [('ars', '6h')]);
      final line = spark(tester);
      expect(line.upColor, kGameSideColors[0]);
      // Only the points since kickoff (the last 72 minutes: 7 of the
      // fake's), then the chance shown.
      expect(line.closes, [...List.filled(7, 0.5), 0.58]);
    });

    testWidgets('a game before kickoff: the 7-day line of the likelier side',
        (tester) async {
      await _pump(
        tester,
        MarketCard(
          title: 'Broncos vs. 49ers',
          outcomes: const [
            PolymarketOutcome(name: 'Broncos', price: 0.36, tokenId: 'bro'),
            PolymarketOutcome(name: '49ers', price: 0.64, tokenId: 'nin'),
          ],
          volume: 6.2e6,
          category: 'sports',
          gameStart: DateTime(2030, 10, 5, 20, 30),
        ),
        overrides: answering(),
      );
      await land(tester);
      expect(asked, [('nin', '1w')]);
      expect(spark(tester).upColor, kGameSideColors[1]);
    });

    testWidgets('until the history lands the card is whole and draws no line',
        (tester) async {
      final hold = Completer<void>();
      await _pump(
        tester,
        MarketCard(
          title: 'Fed cuts rates in December?',
          outcomes: const [
            PolymarketOutcome(name: 'Yes', price: 0.62, tokenId: 'y'),
            PolymarketOutcome(name: 'No', price: 0.39, tokenId: 'n'),
          ],
          volume: 48.1e6,
          category: 'economy',
          endDate: DateTime(2026, 12, 10),
        ),
        overrides: answering(hold: hold),
      );
      final before = tester.getSize(find.byType(MarketCard));
      await land(tester);
      expect(asked, hasLength(1));
      expect(find.byType(HlLineSparkline), findsNothing);
      expect(find.text('Fed cuts rates in December?'), findsOneWidget);
      hold.complete();
      await land(tester);
      expect(find.byType(HlLineSparkline), findsOneWidget);
      // Its place was kept: the card does not jump when it lands.
      expect(tester.getSize(find.byType(MarketCard)), before);
    });

    testWidgets('a card scrolled away before its batch asks for nothing',
        (tester) async {
      final overrides = answering();
      MarketCard yesNo(String token) => MarketCard(
            title: 'Will $token happen?',
            outcomes: [
              PolymarketOutcome(name: 'Yes', price: 0.62, tokenId: token),
              const PolymarketOutcome(name: 'No', price: 0.39),
            ],
            volume: 1,
            category: 'economy',
          );
      await _pump(tester, yesNo('gone'), overrides: overrides);
      await tester.pump(const Duration(milliseconds: 100));
      // The list moved on (same session, same store): another card.
      await _pump(tester, yesNo('kept'), overrides: overrides);
      await tester.pump(const Duration(seconds: 1));
      expect(asked, [('kept', '1w')]);
    });
  });

  group('nothing cut', () {
    for (final dark in [false, true]) {
      testWidgets('at 320 pt and text ×1.5 (${dark ? 'dark' : 'light'})',
          (tester) async {
        final cards = [
          MarketCard(
            title: 'Jensen Huang announced resignation or removal?',
            outcomes: _dated(leaderMove: 0.06),
            volume: 20.2e6,
            category: 'tech',
            endDate: DateTime(2027, 4, 30),
          ),
          MarketCard(
            title: 'Fed cuts rates in December?',
            outcomes: const [
              PolymarketOutcome(name: 'Yes', price: 0.62, tokenId: 'y'),
              PolymarketOutcome(name: 'No', price: 0.39, tokenId: 'n'),
            ],
            volume: 48.1e6,
            category: 'economy',
            endDate: DateTime(2026, 12, 10),
            dayMove: 0.04,
          ),
          const MarketCard(
            title: 'Arsenal vs Chelsea',
            outcomes: _threeWay,
            volume: 3.4e6,
            category: 'sports',
            liveGame: PolyLiveGame(
                score: '2-1', clock: "67'", period: '2H', firstIsHome: true),
          ),
        ];
        await _pump(
          tester,
          Column(children: [
            for (final card in cards) ...[card, const SizedBox(height: 12)],
          ]),
          dark: dark,
          width: 320 * 1.0,
          textScale: 1.5,
          overrides: _sparks(),
        );
        // The tiny charts land too.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(find.byType(HlLineSparkline), findsNWidgets(3));
        expect(tester.takeException(), isNull);
        const titles = {
          'Jensen Huang announced resignation or removal?',
          'Fed cuts rates in December?',
        };
        final cut = <String>[];
        for (final e in find
            .descendant(
                of: find.byType(MarketCard),
                matching: find.byWidgetPredicate((w) => w is RichText))
            .evaluate()) {
          final p = e.renderObject! as RenderParagraph;
          final text = p.text.toPlainText();
          // A list title keeps its two-line cap (the market page writes
          // it whole); everything else is written whole.
          if (titles.contains(text)) continue;
          if (p.didExceedMaxLines) cut.add(text);
        }
        expect(cut, isEmpty, reason: 'cut: $cut');
      });
    }
  });
}
