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
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/services/polymarket/polymarket_feed_cache.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget card,
    {bool dark = false,
    double width = 390,
    double textScale = 1,
    List<Override> overrides = const []}) async {
  tester.view.physicalSize = Size(width, 1200);
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

void main() {
  group('A · what is moving', () {
    testWidgets(
        'many outcomes: rows at 14 with the leader semibold, bars 6 tall, '
        "and the leader's day move on the meta line", (tester) async {
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
      // The leader's own move, never the event's largest one.
      final meta = find.text(r'Closes Apr 2027 · $20.2M · ▲ 6 pts today');
      expect(meta, findsOneWidget);
      final span = (tester.widget<Text>(meta).textSpan! as TextSpan)
          .children!
          .last as TextSpan;
      expect(span.text, '▲ 6 pts today');
      expect(span.style!.color, AppColors.marketUp);
      expect(find.textContaining('20 pts'), findsNothing);
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
      final meta = find.textContaining('▼ 4 pts today');
      expect(meta, findsOneWidget);
      final span = (tester.widget<Text>(meta).textSpan! as TextSpan)
          .children!
          .last as TextSpan;
      expect(span.style!.color, AppColors.marketDown);

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
      expect(find.textContaining('pts today'), findsNothing);
      expect(find.text(r'Closes Apr 2027 · $20.2M'), findsOneWidget);
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
      // The meta line stays as it was.
      expect(find.text(r'Closes Dec 2026 · $48.1M'), findsOneWidget);
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
        "teams' colours with the draw grey, the leader's move in the footer",
        (tester) async {
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
      // The volume moved up beside the clock.
      expect(
          tester.getCenter(find.textContaining('3.4M')).dy,
          moreOrLessEquals(tester.getCenter(live).dy, epsilon: 2));
      // One split bar: Arsenal, the draw, Chelsea.
      final boxes = tester
          .widgetList<ColoredBox>(find.descendant(
              of: find.byType(MarketCard),
              matching: find.byType(ColoredBox)))
          .map((b) => b.color)
          .toList();
      expect(boxes, contains(kGameSideColors[0]));
      expect(boxes, contains(kGameSideColors[1]));
      final footer = find.text('Draw 21% · Arsenal ▲ 9 pts today');
      expect(footer, findsOneWidget);
      final span = (tester.widget<Text>(footer).textSpan! as TextSpan)
          .children!
          .last as TextSpan;
      expect(span.style!.color, AppColors.marketUp);
      // The bar sits between the teams and the footer.
      expect(tester.getTopLeft(footer).dy,
          greaterThan(tester.getBottomLeft(find.text('Chelsea')).dy));
    });

    testWidgets('a game before kickoff keeps its kickoff in the footer',
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
      expect(find.text('5 Oct 20:30 · Draw 21% · Arsenal ▲ 9 pts today'),
          findsOneWidget);
      expect(find.textContaining('3.4M vol'), findsOneWidget);
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
        );
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
