// A look by eye at the Predictions list cards after the redesign (founder,
// 12 November 2026, "do all 3": A what's moving, B one tap to the slip, C
// a tiny chart; then the outcome rows as one grid with no row pills,
// "sizes are strange"), written only when asked:
//   FW183_RENDER=<dir> flutter test test/render/predictions_cards_render_test.dart
// The real Inter face, light and dark, 393 wide (an iPhone) and 320 at
// text ×1.5 (the tightest): many outcomes, a Yes/No market, a game in play
// and a game before kickoff, each with its 7-day (or since-kickoff) line
// already read (a fake history, no network).

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_card_spark_provider.dart';
import 'package:kute/services/polymarket/poly_card_spark_store.dart';
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/render_png.dart';

final _dir = Platform.environment['FW183_RENDER'];

/// The cards' histories, answered at once from a fake (no network).
List<Override> sparkOverrides() => [
      polyCardSparkStoreProvider.overrideWith((ref) {
        final ends = {
          'd27': 0.84,
          'fy': 0.62,
          'ars': 0.58,
          'nin': 0.64,
        };
        final store = PolyCardSparkStore(fetch: (token, interval) async {
          final end = ends[token] ?? 0.5;
          if (interval == PolyCardSparkStore.liveInterval) {
            // A match since kickoff, a point a minute.
            return walk(end, seed: token.hashCode, n: 72, step: 1);
          }
          return walk(end, seed: token.hashCode);
        });
        ref.onDispose(store.dispose);
        return store;
      }),
    ];

List<(String, Widget)> _cards() => [
      (
        'many_outcomes',
        MarketCard(
          title: 'Jensen Huang announced resignation or removal?',
          outcomes: const [
            PolymarketOutcome(
                name: 'December 31, 2027',
                price: 0.84,
                tokenId: 'd27',
                noTokenId: 'd27n',
                dayMove: 0.06),
            PolymarketOutcome(
                name: 'March 31, 2027',
                price: 0.825,
                tokenId: 'm27',
                noTokenId: 'm27n'),
            PolymarketOutcome(
                name: 'December 31, 2026',
                price: 0.775,
                tokenId: 'd26',
                noTokenId: 'd26n'),
            PolymarketOutcome(
                name: 'June 30, 2026', price: 0.4, tokenId: 'a', noTokenId: 'b'),
            PolymarketOutcome(
                name: 'March 31, 2026', price: 0.2, tokenId: 'c', noTokenId: 'd'),
            PolymarketOutcome(
                name: 'January 31, 2026',
                price: 0.1,
                tokenId: 'e',
                noTokenId: 'f'),
          ],
          volume: 20.2e6,
          category: 'tech',
          endDate: DateTime(2027, 4, 30),
          onTap: () {},
          onPickSide: (_) {},
        ),
      ),
      (
        'many_outcomes_long_names',
        MarketCard(
          title: 'Who will be NVIDIA CEO at the end of 2026?',
          outcomes: const [
            PolymarketOutcome(
                name: 'Jensen Huang (No Change)',
                price: 0.93,
                tokenId: 'jh',
                noTokenId: 'jhn'),
            PolymarketOutcome(
                name: 'Colette Kress', price: 0.03, tokenId: 'ck', noTokenId: 'x'),
            PolymarketOutcome(
                name: 'Jay Puri', price: 0.02, tokenId: 'jp', noTokenId: 'y'),
            PolymarketOutcome(
                name: 'Another person', price: 0.01, tokenId: 'ap', noTokenId: 'z'),
          ],
          volume: 3.1e6,
          category: 'tech',
          onTap: () {},
          onPickSide: (_) {},
        ),
      ),
      (
        'yes_no',
        MarketCard(
          title: 'Fed cuts rates in December?',
          outcomes: const [
            PolymarketOutcome(name: 'Yes', price: 0.62, tokenId: 'fy'),
            PolymarketOutcome(name: 'No', price: 0.39, tokenId: 'fn'),
          ],
          volume: 48.1e6,
          category: 'economy',
          endDate: DateTime(2026, 12, 10),
          dayMove: 0.04,
          onTap: () {},
          onPickSide: (_) {},
        ),
      ),
      (
        'game_live',
        MarketCard(
          title: 'Arsenal vs Chelsea',
          outcomes: const [
            PolymarketOutcome(
                name: 'Will Arsenal win?',
                price: 0.58,
                tokenId: 'ars',
                noTokenId: 'x1',
                dayMove: 0.09),
            PolymarketOutcome(
                name: 'Draw (Arsenal vs Chelsea)',
                price: 0.21,
                tokenId: 'drw',
                noTokenId: 'x2'),
            PolymarketOutcome(
                name: 'Will Chelsea win?',
                price: 0.21,
                tokenId: 'che',
                noTokenId: 'x3',
                dayMove: -0.09),
          ],
          volume: 3.4e6,
          category: 'sports',
          gameStart: DateTime.now().subtract(const Duration(minutes: 72)),
          liveGame: const PolyLiveGame(
              score: '2-1', clock: "67'", period: '2H', firstIsHome: true),
          onTap: () {},
          onPickSide: (_) {},
        ),
      ),
      (
        'game_upcoming',
        MarketCard(
          title: 'Broncos vs. 49ers',
          outcomes: const [
            PolymarketOutcome(
                name: 'Broncos', price: 0.36, tokenId: 'bro', dayMove: -0.03),
            PolymarketOutcome(
                name: '49ers', price: 0.64, tokenId: 'nin', dayMove: 0.03),
          ],
          volume: 6.2e6,
          category: 'sports',
          gameStart: DateTime(2030, 10, 5, 20, 30),
          onTap: () {},
          onPickSide: (_) {},
        ),
      ),
    ];

Future<void> _render(WidgetTester tester,
    {required bool dark,
    required double width,
    required double scale,
    required String name,
    List<Widget>? only}) async {
  // A real phone's height: the card's .h sizes follow it.
  tester.view.physicalSize = Size(width, width < 350 ? 568 : 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey();
  await tester.pumpWidget(ProviderScope(
    overrides: sparkOverrides(),
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
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
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            backgroundColor: context.colors.background,
            body: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: double.infinity,
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: context.colors.background,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final card in only ?? [for (final c in _cards()) c.$2]) ...[
                          card,
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(tester.takeException(), isNull);
  await writeRenderPng(tester, key, '$_dir/$name.png');
}

/// A 7-day walk ending at [end], for the fake history.
List<PolymarketPricePoint> walk(double end,
    {int seed = 1, int n = 60, int step = 168}) {
  final r = math.Random(seed);
  final now = DateTime.now();
  final out = <PolymarketPricePoint>[];
  var p = (end - 0.08).clamp(0.02, 0.98);
  for (var i = 0; i < n; i++) {
    p = (p + (r.nextDouble() - 0.42) * 0.025).clamp(0.02, 0.98);
    out.add(PolymarketPricePoint(
        timestamp: now.subtract(Duration(minutes: (n - i) * step)), price: p));
  }
  // Shifted to end where the card's figure is.
  final shift = end - out.last.price;
  return [
    for (final x in out)
      PolymarketPricePoint(
          timestamp: x.timestamp,
          price: (x.price + shift).clamp(0.01, 0.99).toDouble()),
  ];
}

void main() {
  setUpAll(loadRenderFonts);
  final skip = _dir == null || _dir!.isEmpty;
  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('cards $theme 393', (tester) async {
      await _render(tester,
          dark: dark, width: 393, scale: 1, name: 'cards_${theme}_393');
    }, skip: skip);
    testWidgets('cards $theme 320 x1.5', (tester) async {
      await _render(tester,
          dark: dark, width: 320, scale: 1.5, name: 'cards_${theme}_320_x1.5');
    }, skip: skip);
  }
  for (final (name, card) in _cards()) {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('$name $theme', (tester) async {
        await _render(tester,
            dark: dark,
            width: 393,
            scale: 1,
            name: '${name}_$theme',
            only: [card]);
      }, skip: skip);
    }
  }
}
