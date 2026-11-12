// "5 MINUTE MARKETS" BESIDE TRENDING (founder, 12 November 2026). The top
// of the Predictions category sheet is one row of two cards: Trending, at
// half the width, and to its right "5 minute markets", the same card. Both
// keep all of their text at any width and text size (a name wraps, the
// numbers wrap or give way, nothing is cut or shrunk), and they are as tall
// as each other. A tap on "5 minute markets" closes the sheet and opens
// Predictions › Crypto › 5 Min on its five-minute rounds
// (five_min_page_test.dart for the page itself), reported as a pick of
// Crypto's 5 Min row from this card.
//
// The sheet's top is written as PNGs, light and dark, when asked:
//
//   FIVE_MIN_RENDER=<dir> flutter test \
//     test/screens/usd/category_sheet_five_minute_test.dart

import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:file/file.dart' as fs;
// ignore: depend_on_referenced_packages
import 'package:file/local.dart' show LocalFileSystem;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/poly_sport_icon.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';

import '../../helpers/render_png.dart';
import 'five_min_page_test.dart' as page;
import 'investments_harness.dart';

final _renderOut = Platform.environment['FIVE_MIN_RENDER'] ?? '';

AppLocalizations _l10nOf(String code) => l10nForLanguage(code);

/// The artwork Trending's stack draws: the app's own logos (no network in
/// a test), as category_pick_motion_test.dart's renders.
class _LocalArtwork implements BaseCacheManager {
  static const _byWord = {
    'img-0': 'lib/assets/bitcoin-logo.png',
    'img-1': 'lib/assets/arbitrum-logo.png',
    'img-2': 'lib/assets/kute_icon.png',
  };

  @override
  Future<fs.File> getSingleFile(String url,
      {String key = '', Map<String, String> headers = const {}}) async {
    for (final e in _byWord.entries) {
      if (url.contains(e.key)) return const LocalFileSystem().file(e.value);
    }
    throw const HttpException('no local artwork');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Five markets with images and $30M traded today: the founder's
/// "Most active · $30M vol today".
final _trending = [
  for (var i = 0; i < 5; i++)
    PolymarketEvent(
      id: 't$i',
      slug: 't$i',
      title: 'Trending market $i',
      imageUrl: 'https://polymarket-upload.example/img-$i.png',
      volume: 9e7,
      volume24hr: 6e6,
      liquidity: 1e5,
      category: 'politics',
      conditionId: 't$i',
      outcomes: const [
        PolymarketOutcome(name: 'Yes', price: 0.4),
        PolymarketOutcome(name: 'No', price: 0.6),
      ],
    ),
];

Finder get _sheet => find.byType(AppBottomSheetContainer);
Finder _tile(String key) => find.byKey(ValueKey('category-tile-$key'));
Finder get _trendingTile => _tile(PolyPill.trending.key);
Finder get _fiveMinute => _tile('five-minute');
const _pair = ValueKey('category-top-pair');

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The Dollars home on Predictions (Trending), its category sheet open.
Future<ProviderContainer> _openSheet(WidgetTester tester,
    {required Size size,
    double textScale = 1,
    bool dark = false,
    String language = 'en'}) async {
  final world = page.founderWorld()..listNext();
  final container = await page.pumpPredictionsPage(tester, world,
      size: size,
      textScale: textScale,
      dark: dark,
      locale: Locale(language),
      at: const PolyBrowseSelection());
  // The sheet: the picked pill again.
  await tapAndPump(tester, investmentsPill(_l10nOf(language).predictions));
  await _frames(tester);
  expect(_sheet, findsOneWidget);
  return container;
}

/// The card's own box (its margin under it left out).
Rect _card(WidgetTester tester, Finder tile) => tester.getRect(
    find.descendant(of: tile, matching: find.byType(DecoratedBox)).first);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRenderFonts();
  });
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    PolyCrestImage.debugCacheManager = _LocalArtwork();
    page.pageFeed = _trending;
  });
  tearDown(() {
    PolyCrestImage.debugCacheManager = null;
    page.pageFeed = const [];
    PolymarketLiveBooks.instance.reset();
  });

  testWidgets(
      'the top row: Trending and "5 minute markets", half the width each, '
      'equal heights, the same card, the 5 Min row\'s glyph, no chevron',
      (tester) async {
    await _openSheet(tester, size: const Size(393, 1500));
    expect(find.byKey(_pair), findsOneWidget);
    expect(find.descendant(of: find.byKey(_pair), matching: _trendingTile),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(_pair), matching: _fiveMinute),
        findsOneWidget);
    final trending = _card(tester, _trendingTile);
    final five = _card(tester, _fiveMinute);
    // One row: Trending at the sheet's left gutter (the topics' own), the
    // card to its right, 8 apart, to the right gutter, half the width each.
    final topics = [
      for (final p in PolyPill.values)
        if (p != PolyPill.trending && _tile(p.key).evaluate().isNotEmpty)
          _card(tester, _tile(p.key)),
    ];
    expect(topics.length, greaterThan(2));
    expect(trending.left, closeTo(topics[0].left, 0.5));
    expect(five.left, closeTo(topics[1].left, 0.5));
    expect(five.right, closeTo(topics[1].right, 0.5));
    expect(five.left - trending.right, closeTo(8, 0.5));
    expect(five.width, closeTo(trending.width, 0.5));
    expect(five.top, closeTo(trending.top, 0.5));
    expect(five.height, closeTo(trending.height, 0.5), reason: 'equal heights');
    expect(trending.height, greaterThanOrEqualTo(64));
    // The same card: the same decoration on both.
    BoxDecoration deco(Finder tile) => tester
        .widget<AnimatedContainer>(
            find.descendant(of: tile, matching: find.byType(AnimatedContainer)))
        .decoration! as BoxDecoration;
    expect(deco(_fiveMinute).color, deco(_trendingTile).color);
    expect(deco(_fiveMinute).borderRadius, deco(_trendingTile).borderRadius);
    expect(deco(_fiveMinute).boxShadow, deco(_trendingTile).boxShadow);
    expect((deco(_trendingTile).border! as Border).top.width, 1.5,
        reason: 'Trending is the page: ringed');
    expect(
        (deco(_fiveMinute).border as Border?)?.top.width ?? 0, lessThan(1.5));
    // Its words: the name, and the lengths under it.
    final l10n = _l10nOf('en');
    expect(
        find.descendant(
            of: _fiveMinute,
            matching: find.text(l10n.categoryFiveMinuteMarkets)),
        findsOneWidget);
    expect(l10n.categoryFiveMinuteMarkets, '5 minute markets');
    // Crypto › 5 Min's own glyph, on the card's square.
    final icon = tester.widget<PolySubIcon>(
        find.descendant(of: _fiveMinute, matching: find.byType(PolySubIcon)));
    expect(icon.pill, PolyPill.crypto);
    expect(icon.sub.key, '5m');
    // Trending: its stack, "Most active" and the day's volume, all of it.
    expect(
        find.descendant(
            of: _trendingTile, matching: find.byType(PolyCrestImage)),
        findsWidgets);
    expect(
        find.descendant(
            of: _trendingTile,
            matching: find.textContaining(l10n.categoryStatMostActive,
                findRichText: true)),
        findsOneWidget);
    expect(
        find.descendant(
            of: _trendingTile,
            matching: find.textContaining(r'$30M', findRichText: true)),
        findsOneWidget);
    // Two cards in a row: no chevron (the lone card's).
    expect(find.byKey(const ValueKey('category-tile-chevron')), findsNothing);
    // The topics start under the row.
    expect(tester.getRect(find.text(l10n.categoryGroupTopics)).top,
        greaterThan(trending.bottom));
    expect(page.cutTexts(tester, find.byKey(_pair)), isEmpty);
    expect(tester.takeException(), isNull);
    await page.unmountPage(tester);
  });

  for (final dark in [false, true]) {
    for (final language in ['en', 'de', 'pt']) {
      final theme = dark ? 'dark' : 'light';
      testWidgets(
          'at 320 pt and text ×1.5 in $language ($theme): both cards keep '
          'every word, nothing cut or shrunk, equal heights', (tester) async {
        await _openSheet(tester,
            size: const Size(320, 1700),
            textScale: 1.5,
            dark: dark,
            language: language);
        final trending = _card(tester, _trendingTile);
        final five = _card(tester, _fiveMinute);
        expect(five.height, closeTo(trending.height, 0.5));
        expect(five.width, closeTo(trending.width, 0.5));
        expect(five.top, closeTo(trending.top, 0.5));
        expect(five.left, greaterThan(trending.right));
        expect(five.right, lessThan(tester.getRect(_sheet).right));
        expect(page.cutTexts(tester, find.byKey(_pair)), isEmpty);
        // Every text inside its card, at the size the person reads at.
        for (final tile in [_trendingTile, _fiveMinute]) {
          final box = _card(tester, tile);
          for (final e in find
              .descendant(of: tile, matching: find.byType(RichText))
              .evaluate()) {
            final r = tester.getRect(find.byWidget(e.widget));
            expect(r.left, greaterThanOrEqualTo(box.left), reason: language);
            expect(r.right, lessThanOrEqualTo(box.right + 0.5),
                reason: language);
            expect(r.top, greaterThanOrEqualTo(box.top), reason: language);
            expect(r.bottom, lessThanOrEqualTo(box.bottom + 0.5),
                reason: language);
          }
          expect(
              find.descendant(
                  of: find.descendant(
                      of: tile, matching: find.byType(FittedBox)),
                  matching: find.byType(RichText)),
              findsNothing,
              reason: 'wrapped, never shrunk');
        }
        expect(
            find.descendant(
                of: _fiveMinute,
                matching:
                    find.text(_l10nOf(language).categoryFiveMinuteMarkets)),
            findsOneWidget);
        expect(
            find.descendant(
                of: _trendingTile,
                matching: find.text(_l10nOf(language).polyPillTrending)),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await page.unmountPage(tester);
      });
    }
  }

  testWidgets(
      'a tap on "5 minute markets": the sheet closes and the page is '
      'Predictions › Crypto › 5 Min, on its five-minute rounds',
      (tester) async {
    final events = recordEvents();
    final container = await _openSheet(tester, size: const Size(393, 1500));
    // The page's chips were last left on 15 minutes.
    container.read(cryptoPredictWindowProvider.notifier).state = 15;
    expect(find.byKey(page.roundCardKey), findsNothing,
        reason: 'the rounds\' card never stands on the Trending list');
    await tester.tap(_fiveMinute);
    await tester.pump();
    // The pick springs on: the card's ring.
    final ring = (tester
            .widget<AnimatedContainer>(find.descendant(
                of: _fiveMinute, matching: find.byType(AnimatedContainer)))
            .decoration! as BoxDecoration)
        .border! as Border;
    expect(ring.top.width, 1.5);
    await _frames(tester, 12);
    expect(_sheet, findsNothing, reason: 'the sheet closed');
    final sel = container.read(polyBrowseSelectionProvider);
    expect(sel.pill, PolyPill.crypto);
    expect(sel.sub, '5m');
    expect(container.read(cryptoPredictWindowProvider), 5);
    expect(events.where((e) => e.$1 == 'category_pill_tapped').single.$2, {
      'section': 'crypto',
      'subcategory': '5m',
      'surface': 'five_minute_card',
    });
    // The page in A: the live card, betting the next round (no strip of
    // rounds), and the other coins' rows.
    expect(find.byKey(page.roundCardKey), findsOneWidget);
    expect(find.text('BTC up or down · 5m'), findsOneWidget);
    expect(find.byKey(const ValueKey('crypto-round-next')), findsOneWidget);
    expect(find.byKey(const ValueKey('crypto-round-strip')), findsNothing);
    expect(find.byKey(const ValueKey('crypto-more-rounds')), findsOneWidget);
    final l10n = _l10nOf('en');
    expect(
        find.byWidgetPredicate((w) =>
            w is KutePill &&
            w.label == l10n.predictions &&
            w.detail == l10n.polySub5m),
        findsOneWidget,
        reason: 'the pill reads "Predictions · 5 Min"');
    // Opened again there, the card is the one ringed.
    await tapAndPump(tester, investmentsPill(l10n.predictions));
    await _frames(tester);
    final again = (tester
            .widget<AnimatedContainer>(find.descendant(
                of: _fiveMinute, matching: find.byType(AnimatedContainer)))
            .decoration! as BoxDecoration)
        .border! as Border;
    expect(again.top.width, 1.5);
    expect(tester.takeException(), isNull);
    await page.unmountPage(tester);
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('render: the sheet\'s top at 393 pt ($theme)', (tester) async {
      // The artwork's file reads and decodes run on real time.
      Future<void> artwork() async {
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 120)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await _openSheet(tester, size: const Size(393, 852), dark: dark);
      await artwork();
      await writeViewPng(tester, '$_renderOut/category_sheet_top_$theme.png');
      await page.unmountPage(tester);
      await _openSheet(tester,
          size: const Size(320, 1100), textScale: 1.5, dark: dark);
      await artwork();
      await writeViewPng(
          tester, '$_renderOut/category_sheet_top_320x1.5_$theme.png');
      await page.unmountPage(tester);
    }, skip: _renderOut.isEmpty);
  }
}
