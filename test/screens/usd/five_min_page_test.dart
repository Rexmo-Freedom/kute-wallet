// PREDICTIONS › CRYPTO › 5 MIN, THE WHOLE PAGE. The Dollars home on
// Predictions · 5 Min over a fake clock, fake Gamma reads and fake books
// (crypto_next_round_card_test.dart's world): the live card and the other
// coins' rows, which bet ONLY on each coin's NEXT round (founder, 12
// November 2026; late in a round one side is ~98%).
//
//   * the card keeps the round in play on show and says the bet is on the
//     next round ("Next · Starts in 02:16"); no strip of rounds;
//   * the next round without prices: the buttons disabled, "No prices
//     yet" on the line; the rows' chips dimmed with no figure; never the
//     round in play's 98.5%; with prices: enabled, the next round's odds;
//   * a row opens its coin's round sheet, whose buttons bet that coin's
//     next round (the slip itself: crypto_next_round_card_test.dart);
//   * nothing on the page is cut, at 320 pt and text ×1.5 as at 393 pt,
//     light and dark: the card's title, line, price and target, the rows'
//     names, prices, clocks and chips; the past rounds' dots stand in the
//     header only where the title still fits beside them;
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
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/polymarket/components/crypto_asset_logo.dart';
import 'package:kute/screens/shared/market_pair_button.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart'
    show FiveMinMarketDetailSheet;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';

import '../../helpers/offline_venue_overrides.dart';
import '../../helpers/render_png.dart';
import '../polymarket/crypto_next_round_card_test.dart' as card;
import 'investments_harness.dart';

final _renderOut = Platform.environment['FIVE_MIN_RENDER'] ?? '';

/// The page, for a render.
final pageShot = GlobalKey();

AppLocalizations get _l10n => l10nForLanguage('en');

/// What every Predictions list holds (none by default): a test of the
/// category sheet gives Trending its markets.
List<PolymarketEvent> pageFeed = const [];

class _Feed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) =>
      PolyFeedState(done: true, events: pageFeed);
}

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

/// The founder's screen: 2:16 left of the round in play, Up at 98.5% on
/// it (never offered); the next rounds as each test lists them.
card.CardWorld founderWorld() {
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

/// The Dollars home on Predictions · 5 Min, or on Predictions at [at].
Future<ProviderContainer> pumpPredictionsPage(
    WidgetTester tester, card.CardWorld world,
    {required Size size,
    double textScale = 1,
    bool dark = false,
    Locale? locale,
    PolyBrowseSelection? at}) async {
  await pumpInvestments(
    tester,
    dark: dark,
    size: size,
    textScale: textScale,
    locale: locale,
    browsePredictions: true,
    overrides: [
      ...offlineVenueOverrides,
      polyBrowseFeedProvider.overrideWith(_Feed.new),
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
        key: pageShot, child: const Scaffold(body: UsdAccountScreen())),
  );
  final container =
      ProviderScope.containerOf(tester.element(find.byType(UsdAccountScreen)));
  container.read(polyBrowseSelectionProvider.notifier).state = at ??
      container
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

Future<void> unmountPage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 31));
}

const roundCardKey = ValueKey('crypto-round-compact');
const _rows = ValueKey('crypto-more-rounds');
const _coins = ['eth', 'sol', 'xrp'];

/// Every text painted under [root] that is cut: past its lines (an
/// ellipsis), clipped on one line, or set to ellipsise
/// (category_sheet_no_cut_test.dart's rule).
List<String> cutTexts(WidgetTester tester, Finder root) {
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

/// Every coin's next round listed; [quoted] gives each real prices.
void listAll(card.CardWorld world, {required bool quoted}) {
  world.listNext(quoted: quoted);
  for (final coin in _coins) {
    world.listNext(coin: coin, quoted: quoted);
  }
}

/// A row's chip: its opacity and the figure on it, if any.
({double opacity, String? figure}) chipOf(
    WidgetTester tester, String asset, bool up) {
  final key = ValueKey('five-min-chip-$asset-${up ? 'up' : 'down'}');
  final chip = tester.widget<Opacity>(find.byKey(key));
  final figures = find.descendant(
      of: find.byKey(key), matching: find.byType(RollingNumberText));
  return (
    opacity: chip.opacity,
    figure: figures.evaluate().isEmpty
        ? null
        : tester.widget<RollingNumberText>(figures).text,
  );
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
        'at 320 pt and text ×1.5 ($theme): no prices yet, the card says so '
        'over its disabled buttons, the rows\' chips dimmed, and nothing on '
        'the page is cut', (tester) async {
      final world = founderWorld();
      listAll(world, quoted: false);
      await pumpPredictionsPage(tester, world,
          size: const Size(320, 1500), textScale: 1.5, dark: dark);
      expect(find.byKey(roundCardKey), findsOneWidget);
      expect(find.byKey(const ValueKey('crypto-round-strip')), findsNothing);
      expect(card.lineOverButtons(tester),
          'Next · Starts in 02:16 · No prices yet');
      expect(card.buttonEnabled(tester, card.upPill), isFalse);
      expect(card.buttonEnabled(tester, card.downPill), isFalse);
      expect(
          find.descendant(
              of: find.byKey(roundCardKey),
              matching: find.textContaining('%')),
          findsNothing,
          reason: 'never the round in play\'s 98.5%');
      for (final asset in ['ETH', 'SOL', 'XRP']) {
        for (final up in [true, false]) {
          final chip = chipOf(tester, asset, up);
          expect(chip.opacity, lessThan(1), reason: asset);
          expect(chip.figure, isNull, reason: asset);
        }
      }
      // The whole page: the card and the other coins' rows.
      expect(cutTexts(tester, find.byKey(roundCardKey)), isEmpty);
      expect(cutTexts(tester, find.byKey(_rows)), isEmpty);
      // The line over the buttons is laid out whole, on the card.
      final line =
          tester.getRect(find.byKey(const ValueKey('crypto-round-next')));
      final cardRect = tester.getRect(find.byKey(roundCardKey));
      expect(line.left, greaterThanOrEqualTo(cardRect.left));
      expect(line.right, lessThanOrEqualTo(cardRect.right));
      // Too narrow for the dots beside the title: they go first.
      expect(find.byKey(const ValueKey('crypto-round-past-dots')),
          findsNothing);
      // The target went under the price rather than be cut beside it.
      final price = tester.getRect(find.descendant(
          of: find.byKey(roundCardKey), matching: find.text('▼ \$22.00')));
      final target =
          tester.getRect(find.byKey(const ValueKey('crypto-round-target')));
      expect(target.top, greaterThanOrEqualTo(price.bottom - 1));
      // The rows wrapped: the chips under the name, whole.
      expect(
          find.byKey(const ValueKey('five-min-row-wrapped')), findsNWidgets(3));
      for (final asset in ['ETH', 'SOL', 'XRP']) {
        final row = tester.getRect(find.byKey(ValueKey('five-min-row-$asset')));
        final rows = tester.getRect(find.byKey(_rows));
        expect(row.left, greaterThanOrEqualTo(rows.left));
        expect(row.right, lessThanOrEqualTo(rows.right));
      }
      expect(tester.takeException(), isNull);
      await unmountPage(tester);
    });

    testWidgets(
        'at 320 pt and text ×1.5 ($theme), with prices: the buttons enabled '
        'on the next round\'s odds, nothing cut', (tester) async {
      final world = founderWorld();
      listAll(world, quoted: true);
      await pumpPredictionsPage(tester, world,
          size: const Size(320, 1500), textScale: 1.5, dark: dark);
      expect(card.lineOverButtons(tester), 'Next · Starts in 02:16');
      expect(card.buttonEnabled(tester, card.upPill), isTrue);
      expect(cutTexts(tester, find.byKey(roundCardKey)), isEmpty);
      expect(cutTexts(tester, find.byKey(_rows)), isEmpty);
      expect(tester.takeException(), isNull);
      await unmountPage(tester);
    });
  }

  testWidgets(
      'at 393 pt: the card bets the next round on its odds, the rows\' chips '
      'are each coin\'s next round, the dots in the header, nothing cut, '
      'every coin the same circle', (tester) async {
    final world = founderWorld();
    listAll(world, quoted: true);
    await pumpPredictionsPage(tester, world, size: const Size(393, 1100));
    expect(card.lineOverButtons(tester), 'Next · Starts in 02:16');
    expect(card.buttonEnabled(tester, card.upPill), isTrue);
    expect(find.byKey(const ValueKey('crypto-round-strip')), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(roundCardKey),
            matching: find.byKey(const ValueKey('crypto-round-past-dots'))),
        findsOneWidget);
    for (final asset in ['ETH', 'SOL', 'XRP']) {
      final up = chipOf(tester, asset, true);
      final down = chipOf(tester, asset, false);
      expect(up.opacity, 1, reason: asset);
      expect(up.figure, '50.5%', reason: '$asset: the next round\'s book');
      expect(down.figure, '49.5%', reason: asset);
    }
    expect(find.textContaining('98.5%'), findsNothing,
        reason: 'the round in play is never offered');
    // One line: the price, its move, the target at the card's right inset.
    final target =
        tester.getRect(find.byKey(const ValueKey('crypto-round-target')));
    final move = tester.getRect(find.descendant(
        of: find.byKey(roundCardKey), matching: find.text('▼ \$22.00')));
    expect(target.left, greaterThan(move.right));
    expect(find.text(_l10n.predictTargetPrice('\$75,987')), findsOneWidget);
    // The rows: one line each, nothing wrapped, nothing cut.
    expect(find.byKey(const ValueKey('five-min-row-wrapped')), findsNothing);
    expect(cutTexts(tester, find.byKey(roundCardKey)), isEmpty);
    expect(cutTexts(tester, find.byKey(_rows)), isEmpty);
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
    // The card's Up bets the next round, by name (the slip itself:
    // crypto_next_round_card_test.dart).
    final next = card.roundStart.add(const Duration(minutes: 5));
    expect(
        card.buttonSays(
            tester, card.upPill, '${card.windowName(next)}, Up 50.5%'),
        isTrue);
    expect(tester.takeException(), isNull);
    await unmountPage(tester);
  });

  testWidgets(
      'a row opens its coin\'s round sheet, whose buttons bet that coin\'s '
      'next round', (tester) async {
    final world = founderWorld();
    listAll(world, quoted: true);
    await pumpPredictionsPage(tester, world, size: const Size(393, 1100));
    await tester.tap(find.byKey(const ValueKey('five-min-row-ETH')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(FiveMinMarketDetailSheet), findsOneWidget);
    final sheetUp = find.descendant(
        of: find.byType(FiveMinMarketDetailSheet),
        matching: find.byKey(card.upPill));
    expect(
        find.descendant(
            of: find.byType(FiveMinMarketDetailSheet),
            matching: find.text('Next · Starts in 02:16')),
        findsOneWidget);
    // Its Up: enabled on ETH's next round, by name, never the one in play.
    expect(tester.widget<MarketPairButton>(sheetUp).enabled, isTrue);
    final next = card.roundStart.add(const Duration(minutes: 5));
    final ethName = card
        .windowName(next)
        .replaceFirst('BTC', 'ETH');
    expect(
        find.ancestor(
            of: sheetUp,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == ethName)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountPage(tester);
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('render: the 5 Min page ($theme)', (tester) async {
      // The founder's screen with the next rounds priced.
      final priced = founderWorld();
      listAll(priced, quoted: true);
      await pumpPredictionsPage(tester, priced,
          size: const Size(393, 852), dark: dark);
      await writeViewPng(tester, '$_renderOut/five_min_page_$theme.png');
      await unmountPage(tester);
      // The next rounds listed without prices yet: disabled.
      final unpriced = founderWorld();
      listAll(unpriced, quoted: false);
      await pumpPredictionsPage(tester, unpriced,
          size: const Size(393, 852), dark: dark);
      await writeViewPng(
          tester, '$_renderOut/five_min_page_no_prices_$theme.png');
      await unmountPage(tester);
      // 320 pt, text ×1.5, priced and not.
      final small = founderWorld();
      listAll(small, quoted: true);
      await pumpPredictionsPage(tester, small,
          size: const Size(320, 1100), textScale: 1.5, dark: dark);
      await writeViewPng(
          tester, '$_renderOut/five_min_page_320x1.5_$theme.png');
      await unmountPage(tester);
      final smallUnpriced = founderWorld();
      listAll(smallUnpriced, quoted: false);
      await pumpPredictionsPage(tester, smallUnpriced,
          size: const Size(320, 1100), textScale: 1.5, dark: dark);
      await writeViewPng(tester,
          '$_renderOut/five_min_page_320x1.5_no_prices_$theme.png');
      await unmountPage(tester);
    }, skip: _renderOut.isEmpty);
  }
}
