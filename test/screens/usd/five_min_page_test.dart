// PREDICTIONS › CRYPTO › 5 MIN, THE WHOLE PAGE (founder, 12 November 2026,
// the strip of rounds running off the card at "10:25 · No…": "text is cut
// here. Make it good this 5 min screen"). The Dollars home on Predictions ·
// 5 Min over a fake clock, fake Gamma reads and fake books
// (crypto_round_strip_card_test.dart's world): the live card with its strip
// of rounds, the one pair of buttons, and the other coins' rows.
//
//   * the strip is ONE ROW of three equal pills after the dots (Now, Next,
//     the one after), all on the card, none cut, none ellipsized, at 320 pt
//     and text ×1.5 as at 393 pt, light and dark; where the row is too
//     narrow the dots go first and the pills shrink together;
//   * a round without prices is the same pill, dimmed, with no words on it;
//   * nothing on the page is cut: the card's title, price and target, the
//     rows' names, prices, clocks and odds;
//   * every coin's logo is the same circle, at the card's own inset.
//
// The page is written as PNGs, light and dark, when asked:
//
//   FIVE_MIN_RENDER=<dir> flutter test test/screens/usd/five_min_page_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/polymarket/components/crypto_asset_logo.dart';
import 'package:kute/screens/polymarket/components/crypto_round_strip.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';

import '../../helpers/offline_venue_overrides.dart';
import '../../helpers/render_png.dart';
import '../polymarket/crypto_round_strip_card_test.dart' as card;
import 'investments_harness.dart';

final _renderOut = Platform.environment['FIVE_MIN_RENDER'] ?? '';
final _shot = GlobalKey();

AppLocalizations get _l10n => l10nForLanguage('en');

class _NoFeed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) =>
      const PolyFeedState(done: true, events: []);
}

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

/// The founder's screen: 2:16 left of the round in play, the next round
/// listed with no prices yet, the one after not listed, Up at 98.5%.
card.CardWorld _world() {
  final world = card.CardWorld()
    ..now = card.roundStart.add(const Duration(minutes: 2, seconds: 44))
    ..install();
  world.seedBook('cur-up', 0.98, 0.99);
  world.seedBook('cur-down', 0.01, 0.02);
  for (final coin in ['eth', 'sol', 'xrp']) {
    world.seedBook('cur-$coin-up', 0.98, 0.99);
    world.seedBook('cur-$coin-down', 0.01, 0.02);
  }
  return world;
}

/// The Dollars home on Predictions · 5 Min.
Future<ProviderContainer> _pumpPage(WidgetTester tester, card.CardWorld world,
    {required Size size, double textScale = 1, bool dark = false}) async {
  await pumpInvestments(
    tester,
    dark: dark,
    size: size,
    textScale: textScale,
    browsePredictions: true,
    overrides: [
      ...offlineVenueOverrides,
      polyBrowseFeedProvider.overrideWith(_NoFeed.new),
      sportsLiveProvider.overrideWith(_Sports.new),
      polyTopicSubsProvider
          .overrideWith((ref, pill) => Stream.value(const <PolySub>[])),
      polyTrendingThemesProvider
          .overrideWith((ref) => Stream.value(const <PolySub>[])),
      polyCryptoSubsProvider
          .overrideWith((ref) => Stream.value(polyCryptoSubsFromCounts(null))),
      cryptoPredictWindowsProvider.overrideWith((ref, asset) async => [5]),
      ...world.overrides(),
    ],
    child: RepaintBoundary(
        key: _shot, child: const Scaffold(body: UsdAccountScreen())),
  );
  final container = ProviderScope.containerOf(
      tester.element(find.byType(UsdAccountScreen)));
  container.read(polyBrowseSelectionProvider.notifier).state = container
      .read(polyBrowseSelectionProvider)
      .copyWith(pill: PolyPill.crypto)
      .copyWith(sub: '5m');
  container.read(investmentsTabProvider.notifier).state =
      InvestmentsTab.predictions;
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 31));
}

const _strip = ValueKey('crypto-round-strip');
const _cardKey = ValueKey('crypto-round-compact');
const _rows = ValueKey('crypto-more-rounds');

/// Every text painted under [root] that is cut: past its lines (an
/// ellipsis), clipped on one line, or set to ellipsise
/// (category_sheet_no_cut_test.dart's rule).
List<String> _cut(WidgetTester tester, Finder root) {
  final out = <String>[];
  for (final e in find
      .descendant(of: root, matching: find.byType(RichText))
      .evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    if (!p.attached || !p.hasSize) continue;
    final text = p.text.toPlainText();
    if (text.trim().isEmpty) continue;
    if (p.didExceedMaxLines) {
      out.add('"$text" exceeds its ${p.maxLines} line(s)');
      continue;
    }
    if ((p.maxLines == 1 || !p.softWrap) &&
        p.getMaxIntrinsicWidth(double.infinity) > p.size.width + 0.5) {
      out.add('"$text" clipped');
    }
  }
  for (final t in tester.widgetList<Text>(
      find.descendant(of: root, matching: find.byType(Text)))) {
    if (t.overflow == TextOverflow.ellipsis && t.maxLines != null) {
      out.add('"${t.data ?? t.textSpan?.toPlainText()}" is set to ellipsise');
    }
  }
  return out;
}

/// The three pills ahead, in order, by the world's clock.
List<Finder> _pills() => [
      for (final k in [0, 1, 2])
        find.byKey(CryptoRoundStrip.pillKey(card.epoch(
            card.roundStart.add(Duration(minutes: 5 * k))))),
    ];

/// The pills are one row of three equal pills, whole, on the card.
void _expectStripWhole(WidgetTester tester, {required String at}) {
  final strip = tester.getRect(find.byKey(_strip));
  final cardRect = tester.getRect(find.byKey(_cardKey));
  expect(strip.left, greaterThanOrEqualTo(cardRect.left), reason: at);
  expect(strip.right, lessThanOrEqualTo(cardRect.right), reason: at);
  expect(
      find.descendant(
          of: find.byKey(_strip), matching: find.byType(Scrollable)),
      findsNothing,
      reason: '$at: the strip never scrolls sideways');
  final rects = [for (final p in _pills()) tester.getRect(p)];
  expect(rects, hasLength(3));
  for (final (i, r) in rects.indexed) {
    expect(_pills()[i].hitTestable(), findsOneWidget,
        reason: '$at: pill $i can be seen and tapped');
    expect(r.left, greaterThanOrEqualTo(strip.left - 0.5), reason: '$at $i');
    expect(r.right, lessThanOrEqualTo(strip.right + 0.5), reason: '$at $i');
    expect(r.width, closeTo(rects.first.width, 0.5),
        reason: '$at: three equal pills');
    expect(r.center.dy, closeTo(rects.first.center.dy, 0.5),
        reason: '$at: one row');
    if (i > 0) {
      expect(r.left, greaterThan(rects[i - 1].right), reason: '$at: apart');
    }
  }
  final labels = [for (final p in _pills()) tester.widget<KutePill>(p).label];
  expect(labels[0], startsWith('Now · '), reason: at);
  expect(labels[1], 'Next · ${card.clockOf(card.roundStart.add(const Duration(minutes: 5)))}');
  expect(labels[2], card.clockOf(card.roundStart.add(const Duration(minutes: 10))));
  for (final p in _pills()) {
    expect(tester.widget<KutePill>(p).detail, isNull,
        reason: '$at: no words added to a pill');
  }
  // One scale for the three: a pill's own words never shrink alone.
  for (final p in _pills()) {
    for (final e in find
        .descendant(of: p, matching: find.byType(RichText))
        .evaluate()) {
      final para = e.renderObject! as RenderParagraph;
      expect(para.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(para.size.width + 0.5),
          reason: '$at: "${para.text.toPlainText()}" laid out whole');
    }
  }
  expect(_cut(tester, find.byKey(_strip)), isEmpty, reason: at);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRenderFonts();
  });
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(PolymarketLiveBooks.instance.reset);

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets(
        'at 320 pt and text ×1.5 ($theme): the strip is three whole pills on '
        'the card, the dots gone first, and nothing on the page is cut',
        (tester) async {
      final world = _world()..listNext();
      // Listed, with no real prices yet: the founder's "No prices yet".
      world.quotes
        ..remove('next-up')
        ..remove('next-down');
      PolymarketLiveBooks.instance.reset();
      world.install();
      world.requote();
      await _pumpPage(tester, world,
          size: const Size(320, 1500), textScale: 1.5, dark: dark);
      expect(find.byKey(_cardKey), findsOneWidget);
      _expectStripWhole(tester, at: '320 ×1.5 $theme');
      // Too narrow for the dots and the pills: the dots go, and the pills
      // shrink as one row.
      expect(
          find.descendant(
              of: find.byKey(_strip),
              matching: find.byKey(const ValueKey('crypto-round-past-dots'))),
          findsNothing);
      card.expectUnpriced(
          tester, card.epoch(card.roundStart.add(const Duration(minutes: 5))));
      card.expectUnpriced(
          tester, card.epoch(card.roundStart.add(const Duration(minutes: 10))));
      // The whole page: the card and the other coins' rows.
      expect(_cut(tester, find.byKey(_cardKey)), isEmpty);
      expect(_cut(tester, find.byKey(_rows)), isEmpty);
      // The target went under the price rather than be cut beside it.
      final price = tester.getRect(find.descendant(
          of: find.byKey(_cardKey), matching: find.text('▼ \$22.00')));
      final target =
          tester.getRect(find.byKey(const ValueKey('crypto-round-target')));
      expect(target.top, greaterThanOrEqualTo(price.bottom - 1));
      // The rows wrapped: the odds under the name, whole.
      expect(find.byKey(const ValueKey('five-min-row-wrapped')),
          findsNWidgets(3));
      for (final asset in ['ETH', 'SOL', 'XRP']) {
        final row = tester.getRect(find.byKey(ValueKey('five-min-row-$asset')));
        final rows = tester.getRect(find.byKey(_rows));
        expect(row.left, greaterThanOrEqualTo(rows.left));
        expect(row.right, lessThanOrEqualTo(rows.right));
      }
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

  testWidgets(
      'at 393 pt: the dots, then three equal pills across the card; the '
      'price row on one line with the target at the right; every coin the '
      'same circle under the card\'s own', (tester) async {
    final world = _world()..listNext();
    await _pumpPage(tester, world, size: const Size(393, 1100));
    _expectStripWhole(tester, at: '393');
    final strip = tester.getRect(find.byKey(_strip));
    final dots = tester.getRect(find.descendant(
        of: find.byKey(_strip),
        matching: find.byKey(const ValueKey('crypto-round-past-dots'))));
    final pills = [for (final p in _pills()) tester.getRect(p)];
    expect(dots.left, closeTo(strip.left, 0.5));
    expect(pills.first.left, greaterThan(dots.right));
    expect(pills.last.right, closeTo(strip.right, 0.5),
        reason: 'the pills take the rest of the row');
    expect(find.byKey(const ValueKey('crypto-round-strip-fitted')),
        findsNothing,
        reason: 'room for all: nothing shrinks');
    // Next has real prices: a pill at full strength; the one after none.
    final next = card.epoch(card.roundStart.add(const Duration(minutes: 5)));
    expect(
        find.ancestor(
            of: find.byKey(CryptoRoundStrip.pillKey(next)),
            matching: find.descendant(
                of: find.byKey(_strip), matching: find.byType(Opacity))),
        findsNothing);
    card.expectUnpriced(
        tester, card.epoch(card.roundStart.add(const Duration(minutes: 10))));
    // The picked pill wears the pill's chrome, the others its quiet fill.
    for (final p in _pills()) {
      expect(tester.widget<KutePill>(p).restingFill, isNotNull);
    }
    // One line: the price, its move, the target at the card's right inset.
    final target =
        tester.getRect(find.byKey(const ValueKey('crypto-round-target')));
    final move = tester.getRect(find.descendant(
        of: find.byKey(_cardKey), matching: find.text('▼ \$22.00')));
    expect(target.left, greaterThan(move.right));
    expect(target.right, closeTo(strip.right, 0.5));
    expect(find.text(_l10n.predictTargetPrice('\$75,987')), findsOneWidget);
    // The rows: one line each, nothing wrapped, nothing cut.
    expect(find.byKey(const ValueKey('five-min-row-wrapped')), findsNothing);
    expect(_cut(tester, find.byKey(_cardKey)), isEmpty);
    expect(_cut(tester, find.byKey(_rows)), isEmpty);
    // Every coin the same circle, the rows' under the card's.
    final logos = [
      for (final asset in ['BTC', 'ETH', 'SOL', 'XRP'])
        tester.getRect(find.byKey(ValueKey('crypto-asset-logo-$asset'))),
    ];
    for (final r in logos) {
      expect(r.width, closeTo(logos.first.width, 0.01));
      expect(r.height, closeTo(r.width, 0.01));
      expect(r.left, closeTo(logos.first.left, 0.5),
          reason: 'one left edge down the page');
    }
    expect(find.byType(CryptoAssetLogo), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('render: the 5 Min page at 393 pt ($theme)', (tester) async {
      // The founder's screen: the next round listed with no prices yet.
      final world = _world()..listNext();
      world.quotes
        ..remove('next-up')
        ..remove('next-down');
      PolymarketLiveBooks.instance.reset();
      world.install();
      world.requote();
      await _pumpPage(tester, world, size: const Size(393, 852), dark: dark);
      await writeRenderPng(
          tester, _shot, '$_renderOut/five_min_page_$theme.png');
      // A tap on the dimmed pill: the line over the buttons says why.
      await tester.tap(_pills()[1]);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await writeRenderPng(tester, _shot,
          '$_renderOut/five_min_page_no_prices_tapped_$theme.png');
      await _unmount(tester);
      await _pumpPage(tester, world,
          size: const Size(320, 1100), textScale: 1.5, dark: dark);
      await writeRenderPng(
          tester, _shot, '$_renderOut/five_min_page_320x1.5_$theme.png');
      await _unmount(tester);
      // The next rounds with real prices: partway through this one the
      // buttons have rolled to the next, named on the line over them.
      final priced = _world()
        ..listNext()
        ..listLater();
      await _pumpPage(tester, priced, size: const Size(393, 852), dark: dark);
      await writeRenderPng(
          tester, _shot, '$_renderOut/five_min_page_next_priced_$theme.png');
      await _unmount(tester);
    }, skip: _renderOut.isEmpty);
  }
}
