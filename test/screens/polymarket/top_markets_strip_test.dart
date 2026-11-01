// The Top markets strip over the Predictions feed: which markets it
// features (the open Yes/No markets with the most volume in the day),
// what a card shows (the Investing card's treatment since the declutter:
// image, question, who leads large; no pills, no closing date), and where
// a tap goes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/polymarket/components/top_markets_strip.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

/// No live feed: the cards at the feed's own prices.
class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void registerCardTokens(List<String> tokens) {}
  @override
  void unregisterCardTokens(List<String> tokens) {}
}

PolymarketEvent _event(
  String id,
  String title, {
  required double volume,
  double volume24hr = 0,
  double yes = 0.5,
  List<PolymarketOutcome>? outcomes,
  bool ended = false,
  bool closed = false,
  DateTime? endDate,
}) =>
    PolymarketEvent(
      id: id,
      slug: id,
      title: title,
      volume: volume,
      volume24hr: volume24hr,
      liquidity: 0,
      category: 'politics',
      conditionId: id,
      ended: ended,
      closed: closed,
      endDate: endDate,
      outcomes: outcomes ??
          [
            PolymarketOutcome(name: 'Yes', price: yes, tokenId: '$id-yes'),
            PolymarketOutcome(name: 'No', price: 1 - yes, tokenId: '$id-no'),
          ],
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [livePriceProvider.overrideWith(_Prices.new)],
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
        home: Scaffold(body: Column(children: [child])),
      ),
    ),
  ));
  await tester.pump();
}

Finder _rolled(String text) => find.byWidgetPredicate(
    (w) => w is RollingNumberText && w.text == text,
    description: 'rolling figure "$text"');

void main() {
  group('polyTopMarkets', () {
    test('the open Yes/No markets by their day\'s volume, the lifetime '
        'volume when the feed has none, five at most', () {
      final events = [
        _event('a', 'A', volume: 100, volume24hr: 5),
        _event('b', 'B', volume: 1, volume24hr: 50),
        // No day volume: its lifetime volume stands in.
        _event('c', 'C', volume: 20),
        _event('d', 'D', volume: 500, volume24hr: 50),
        _event('e', 'E', volume: 1, volume24hr: 1),
        _event('f', 'F', volume: 1, volume24hr: 2),
        _event('g', 'G', volume: 1, volume24hr: 3),
      ];
      // Equal day volumes keep the feed's order (b before d).
      expect(polyTopMarkets(events).map((e) => e.id), ['b', 'd', 'c', 'a', 'g']);
      expect(polyTopMarkets(events, max: 2).map((e) => e.id), ['b', 'd']);
    });

    test('only plain Yes/No markets still open; fewer than two is no strip',
        () {
      final race = _event('race', 'Who wins?', volume: 1e9, outcomes: const [
        PolymarketOutcome(name: 'A', price: 0.6, tokenId: 'a', conditionId: 'a'),
        PolymarketOutcome(name: 'B', price: 0.3, tokenId: 'b', conditionId: 'b'),
        PolymarketOutcome(name: 'C', price: 0.1, tokenId: 'c', conditionId: 'c'),
      ]);
      final game = _event('game', 'Broncos vs. 49ers', volume: 1e9,
          outcomes: const [
            PolymarketOutcome(name: 'Broncos', price: 0.4),
            PolymarketOutcome(name: '49ers', price: 0.6),
          ]);
      final over = _event('over', 'Over', volume: 1e9, ended: true);
      final shut = _event('shut', 'Shut', volume: 1e9, closed: true);
      final a = _event('a', 'A', volume: 10);
      final b = _event('b', 'B', volume: 5);
      expect(polyTopMarkets([race, game, over, shut, a, b]).map((e) => e.id),
          ['a', 'b']);
      expect(polyTopMarkets([race, game, over, shut, a]), isEmpty);
      expect(polyTopMarkets([race, game, over, shut]), isEmpty);
    });
  });

  testWidgets('a card: the image, the question and who leads large; no '
      'pills, no closing date; the card opens the market', (tester) async {
    final opened = <String>[];
    final markets = [
      _event('fed', 'Fed cuts rates in December?',
          volume: 48.2e6, yes: 0.71, endDate: DateTime(2026, 12, 10)),
      _event('btc', 'Bitcoin above \$150K by December 31?',
          volume: 12.7e6, yes: 0.14, endDate: DateTime(2026, 12, 31)),
      _event('gpt', 'GPT-6 released before 2027?', volume: 5.6e6, yes: 0.27),
    ];
    await _pump(
      tester,
      PolyTopMarketsStrip(
        markets: markets,
        onOpen: (m) => opened.add(m.id),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(PolyTopMarketCard), findsNWidgets(3));
    expect(find.text('Fed cuts rates in December?'), findsOneWidget);
    expect(find.byType(PolyCardThumbnail), findsNWidgets(3));
    // Who leads, large: Yes at 71%; No at 86% where Yes is the longshot.
    expect(_rolled('Yes · 71%'), findsOneWidget);
    expect(_rolled('No · 86%'), findsOneWidget);
    final big = tester.widget<RollingNumberText>(_rolled('Yes · 71%'));
    expect(big.style.fontSize, moreOrLessEquals(22.sp, epsilon: 0.5));
    expect(big.style.fontWeight, FontWeight.w700);
    // Nothing else: no pills, no "chance" word, no closing date.
    expect(find.textContaining('¢'), findsNothing);
    expect(find.text('chance'), findsNothing);
    expect(find.textContaining('Closes'), findsNothing);

    // Two to a screen, the third peeking; about 150 tall, 10 apart.
    final cards = find.byType(PolyTopMarketCard);
    expect(tester.getTopLeft(cards.at(0)).dx, moreOrLessEquals(16.w, epsilon: 0.5));
    expect(tester.getSize(cards.at(0)).width,
        moreOrLessEquals((390 - 32.w - 10.w) / 2 - 14.w, epsilon: 0.5));
    expect(tester.getSize(cards.at(0)).height,
        greaterThanOrEqualTo(150.w - 0.5));
    expect(tester.getTopLeft(cards.at(1)).dx - tester.getTopRight(cards.at(0)).dx,
        moreOrLessEquals(10.w, epsilon: 0.5));
    expect(tester.getTopRight(cards.at(1)).dx, lessThan(390));
    // All cards as tall as each other.
    expect(tester.getSize(cards.at(1)).height, tester.getSize(cards.at(0)).height);

    // The card opens the market.
    await tester.tap(find.text('Fed cuts rates in December?'));
    expect(opened, ['fed']);

    // The strip scrolls sideways to the last card.
    expect(tester.getTopLeft(cards.at(2)).dx, greaterThan(tester.getTopRight(cards.at(1)).dx));
    await tester.drag(find.byType(PolyTopMarketsStrip), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopRight(cards.at(2)).dx, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing without markets', (tester) async {
    await _pump(
      tester,
      PolyTopMarketsStrip(
        markets: const [],
        onOpen: (_) {},
      ),
    );
    expect(find.byType(PolyTopMarketCard), findsNothing);
  });
}
