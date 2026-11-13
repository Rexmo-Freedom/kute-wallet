// PREDICTIONS › CRYPTO › 5 MIN, 15 MIN, 1 HOUR, 4 HOURS: ONE PAGE. The
// Dollars home on Predictions · a round length, over a fake clock, fake
// Gamma reads and fake books (crypto_next_round_card_test.dart's world):
// polymarket.com's own round page made for a phone (founder, 12 November
// 2026), the full BTC round card of that length, the lengths as pills, and
// the other coins' rows at that length.
//
//   * the card's buttons bet the round in play until its cutoff (two
//     minutes into a five-minute round, the last 3, 5 and 10 minutes of a
//     15-minute, hourly and four-hour one), then the next round; the line
//     over them names it ("Now · Ends in 04:00", "Next · Starts in 02:16");
//   * the rows' chips are each coin's round the roll would bet;
//   * a row opens its coin's round sheet at the page's length;
//   * the length pills switch the whole page;
//   * a longer length keeps the rest of its list under "More markets";
//   * nothing on the page is cut, at 320 pt and text ×1.5 as at 393 pt,
//     light and dark; at 393 pt the card, the lengths and the first coin's
//     row stand on one screen;
//   * every coin's logo is the same circle, at the card's own inset.
//
// The pages are written as PNGs, light and dark, when asked:
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
import 'package:kute/screens/polymarket/market_detail_sheet.dart'
    show FiveMinMarketDetailSheet;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';
import 'package:kute/services/tracking_service.dart';

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
/// it (past its cutoff: never offered); the next rounds as each test lists
/// them.
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

/// A page of [minutes] rounds [elapsed] into the round in play, every
/// coin's round in play quoted 41/42 and its next round listed and quoted.
card.CardWorld lengthWorld(int minutes, Duration elapsed) {
  final world = card.CardWorld()
    ..minutes = minutes
    ..install();
  final start = DateTime.fromMillisecondsSinceEpoch(
      polyRoundStartAt(card.roundStart, minutes) * 1000,
      isUtc: true);
  world.now = start.add(elapsed);
  world.seedBook('cur-up', 0.41, 0.42);
  world.seedBook('cur-down', 0.58, 0.59);
  for (final coin in ['eth', 'sol', 'xrp']) {
    world.seedBook('cur-$coin-up', 0.41, 0.42);
    world.seedBook('cur-$coin-down', 0.58, 0.59);
  }
  world.listNext(live: start);
  for (final coin in _coins) {
    world.listNext(live: start, coin: coin);
  }
  return world;
}

/// The Dollars home on Predictions · Crypto › [sub] (5 Min by default), or
/// on Predictions at [at].
Future<ProviderContainer> pumpPredictionsPage(
    WidgetTester tester, card.CardWorld world,
    {required Size size,
    double textScale = 1,
    bool dark = false,
    Locale? locale,
    String sub = '5m',
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
          .copyWith(sub: sub);
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

const roundCardKey = ValueKey('crypto-round-full');
const _rows = ValueKey('crypto-more-rounds');
const _lengths = ValueKey('crypto-round-lengths');
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

  /// The page's parts that must never cut a word.
  void expectNothingCut(WidgetTester tester) {
    expect(cutTexts(tester, find.byKey(roundCardKey)), isEmpty);
    expect(cutTexts(tester, find.byKey(_rows)), isEmpty);
    expect(cutTexts(tester, find.byKey(_lengths)), isEmpty);
  }

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets(
        'at 320 pt and text ×1.5 ($theme), 5 Min past its cutoff, no prices '
        'yet: the card says so over its disabled buttons, the rows\' chips '
        'dimmed, and nothing on the page is cut', (tester) async {
      final world = founderWorld();
      listAll(world, quoted: false);
      await pumpPredictionsPage(tester, world,
          size: const Size(320, 1700), textScale: 1.5, dark: dark);
      expect(find.byKey(roundCardKey), findsOneWidget);
      expect(card.lineOverButtons(tester),
          'Next · Starts in 02:16 · No prices yet');
      expect(card.buttonEnabled(tester, card.upPill), isFalse);
      expect(card.buttonEnabled(tester, card.downPill), isFalse);
      expect(find.textContaining('98.5%'), findsNothing,
          reason: 'the round in play past its cutoff is never offered');
      for (final asset in ['ETH', 'SOL', 'XRP']) {
        for (final up in [true, false]) {
          final chip = chipOf(tester, asset, up);
          expect(chip.opacity, lessThan(1), reason: asset);
          expect(chip.figure, isNull, reason: asset);
        }
      }
      expectNothingCut(tester);
      // The figures went onto two rows rather than be cut.
      expect(find.byKey(const ValueKey('crypto-round-figures-wrapped')),
          findsOneWidget);
      for (final asset in ['ETH', 'SOL', 'XRP']) {
        final row = tester.getRect(find.byKey(ValueKey('five-min-row-$asset')));
        final rows = tester.getRect(find.byKey(_rows));
        expect(row.left, greaterThanOrEqualTo(rows.left));
        expect(row.right, lessThanOrEqualTo(rows.right));
      }
      expect(tester.takeException(), isNull);
      await unmountPage(tester);
    });

    for (final (sub, minutes) in [('5m', 5), ('15m', 15), ('1h', 60)]) {
    testWidgets(
          'at 320 pt and text ×1.5 ($theme), $sub before its cutoff: the '
          'round in play bet, nothing cut', (tester) async {
        final world = lengthWorld(minutes, const Duration(minutes: 1));
      await pumpPredictionsPage(tester, world,
            size: const Size(320, 1700), textScale: 1.5, dark: dark, sub: sub);
        expect(card.lineOverButtons(tester), startsWith('Now · Ends in '));
      expect(card.buttonEnabled(tester, card.upPill), isTrue);
        expectNothingCut(tester);
      expect(tester.takeException(), isNull);
      await unmountPage(tester);
    });
  }
  }

  testWidgets(
      'at 393 pt, 5 Min past its cutoff: the card bets the next round on '
      'its odds, the rows\' chips are each coin\'s next round, nothing cut, '
      'every coin the same circle; the card, the lengths and the first row '
      'stand on one screen', (tester) async {
    final world = founderWorld();
    listAll(world, quoted: true);
    await pumpPredictionsPage(tester, world, size: const Size(393, 1100));
    expect(card.lineOverButtons(tester), 'Next · Starts in 02:16');
    expect(card.buttonEnabled(tester, card.upPill), isTrue);
    expect(find.byKey(const ValueKey('crypto-round-strip')), findsOneWidget);
    for (final asset in ['ETH', 'SOL', 'XRP']) {
      final up = chipOf(tester, asset, true);
      final down = chipOf(tester, asset, false);
      expect(up.opacity, 1, reason: asset);
      expect(up.figure, '50.5%', reason: '$asset: the next round\'s book');
      expect(down.figure, '49.5%', reason: asset);
    }
    expect(find.textContaining('98.5%'), findsNothing,
        reason: 'the round in play past its cutoff is never offered');
    // The figures on one row: price to beat, current price, time left.
    expect(find.byKey(const ValueKey('crypto-round-figures-wrapped')),
        findsNothing);
    expect(find.text(_l10n.btcPredictPriceToBeat), findsOneWidget);
    expect(find.text(_l10n.investingCurrentPrice), findsOneWidget);
    expect(find.text('▼ \$22.00'), findsOneWidget);
    expect(find.text('02:16'), findsWidgets);
    expect(find.text('BTC up or down · 5m'), findsOneWidget);
    expect(find.text('Ethereum up or down · 5m'), findsOneWidget);
    expectNothingCut(tester);
    // Every coin the same circle, the rows' under the card's.
    final logos = [
      for (final asset in ['BTC', 'ETH', 'SOL', 'XRP'])
        tester.getRect(find.byKey(ValueKey('crypto-asset-logo-$asset'))),
    ];
    for (final r in logos.skip(1)) {
      expect(r.width, closeTo(logos[1].width, 0.01));
      expect(r.height, closeTo(r.width, 0.01));
      expect(r.left, closeTo(logos.first.left, 0.5),
          reason: 'one left edge down the page');
    }
    expect(find.byType(CryptoAssetLogo), findsNWidgets(4));
    // One screen of a 393 × 852 phone under its top bar (64) and over its
    // dock (90): the card, the lengths and the first coin's row.
    final cardTop = tester.getRect(find.byKey(roundCardKey)).top;
    final firstRow =
        tester.getRect(find.byKey(const ValueKey('five-min-row-ETH')));
    expect(firstRow.bottom - cardTop, lessThanOrEqualTo(852 - 64 - 90));
    // The card's Up bets the next round, by name.
    final next = card.roundStart.add(const Duration(minutes: 5));
    expect(
        card.buttonSays(
            tester, card.upPill, '${card.windowName(next)}, Up 50.5%'),
        isTrue);
    expect(tester.takeException(), isNull);
    await unmountPage(tester);
  });

  testWidgets(
      '5 Min before its cutoff: the card and the rows bet the round in play',
      (tester) async {
    final world = lengthWorld(5, const Duration(minutes: 1));
    await pumpPredictionsPage(tester, world, size: const Size(393, 1100));
    expect(card.lineOverButtons(tester), 'Now · Ends in 04:00');
    expect(
        card.buttonSays(tester, card.upPill,
            '${card.windowName(card.roundStart)}, Up 41.5%'),
        isTrue);
    for (final asset in ['ETH', 'SOL', 'XRP']) {
      expect(chipOf(tester, asset, true).figure, '41.5%', reason: asset);
    }
    expect(tester.takeException(), isNull);
    await unmountPage(tester);
  });

  testWidgets(
      '1 Hour: the card, its rows and a row\'s sheet at an hour; the round '
      'in play bet until five minutes are left', (tester) async {
    final world = lengthWorld(60, const Duration(minutes: 2, seconds: 44));
    await pumpPredictionsPage(tester, world,
        size: const Size(393, 1100), sub: '1h');
    expect(find.text('BTC up or down · 1h'), findsOneWidget);
    expect(card.lineOverButtons(tester), 'Now · Ends in 0:57:16');
    expect(find.text('Ethereum up or down · 1h'), findsOneWidget);
    expect(chipOf(tester, 'ETH', true).figure, '41.5%');
    // The row opens Ethereum's round sheet at an hour, on its round in play.
    await tester.tap(find.byKey(const ValueKey('five-min-row-ETH')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final sheet = tester.widget<FiveMinMarketDetailSheet>(
        find.byType(FiveMinMarketDetailSheet));
    expect(sheet.minutes, 60);
    expect(
        find.descendant(
            of: find.byType(FiveMinMarketDetailSheet),
            matching: find.text('ETH up or down · 1h')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(FiveMinMarketDetailSheet),
            matching: find.text('Now · Ends in 0:57:16')),
        findsOneWidget);
    final sheetUp = find.descendant(
        of: find.byType(FiveMinMarketDetailSheet),
        matching: find.byKey(card.upPill));
    expect(sheetUp, findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountPage(tester);
  });

  testWidgets(
      'a row opens its coin\'s round sheet at the page\'s length, whose '
      'buttons bet that coin\'s round the roll stands on', (tester) async {
    final world = founderWorld();
    listAll(world, quoted: true);
    await pumpPredictionsPage(tester, world, size: const Size(393, 1100));
    await tester.tap(find.byKey(const ValueKey('five-min-row-ETH')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(FiveMinMarketDetailSheet), findsOneWidget);
    expect(
        tester
            .widget<FiveMinMarketDetailSheet>(
                find.byType(FiveMinMarketDetailSheet))
            .minutes,
        5);
    final sheetUp = find.descendant(
        of: find.byType(FiveMinMarketDetailSheet),
        matching: find.byKey(card.upPill));
    expect(
        find.descendant(
            of: find.byType(FiveMinMarketDetailSheet),
            matching: find.text('Next · Starts in 02:16')),
        findsOneWidget);
    expect(sheetUp, findsOneWidget);
    final next = card.roundStart.add(const Duration(minutes: 5));
    final ethName = card
        .windowName(next)
        .replaceFirst('BTC', 'ETH');
    expect(
        find.descendant(
            of: find.byType(FiveMinMarketDetailSheet),
            matching: find.byWidgetPredicate((w) =>
                w is Semantics &&
                (w.properties.label ?? '').startsWith('$ethName, Up'))),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountPage(tester);
  });

  testWidgets(
      'the length pills switch the whole page: 5 Min to 15 Min, the card '
      'and the rows at 15 minutes, the length change reported', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    final world = lengthWorld(5, const Duration(minutes: 1));
    final container =
        await pumpPredictionsPage(tester, world, size: const Size(393, 1100));
    expect(find.text('BTC up or down · 5m'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('crypto-round-length-15m')));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(container.read(polyBrowseSelectionProvider).sub, '15m');
    expect(find.text('BTC up or down · 15m'), findsOneWidget);
    expect(find.text('Ethereum up or down · 15m'), findsOneWidget);
    final changed = events.where((e) => e.$1 == 'crypto_window_changed');
    expect(changed.single.$2, {'minutes': 15, 'from_minutes': 5});
    expect(tester.takeException(), isNull);
    await unmountPage(tester);
  });

  testWidgets(
      '15 Min keeps the rest of its list under "More markets": the other '
      'coins\' rounds and the "above" markets, never the rounds already '
      'on the card and the rows', (tester) async {
    final start = card.roundStart;
    PolymarketEvent ev(String slug, String title) => PolymarketEvent(
          id: slug,
          slug: slug,
          title: title,
          volume: 1000,
          volume24hr: 1000,
          liquidity: 1000,
          category: 'crypto',
          endDate: start.add(const Duration(minutes: 15)),
          conditionId: '$slug-cond',
          outcomes: const [
            PolymarketOutcome(name: 'Up', price: 0.5, tokenId: 'u'),
            PolymarketOutcome(name: 'Down', price: 0.5, tokenId: 'd'),
          ],
        );
    final e = card.epoch(start);
    pageFeed = [
      ev('btc-updown-15m-$e', 'BTC round on the card'),
      ev('eth-updown-15m-$e', 'ETH round on the rows'),
      ev('doge-updown-15m-$e', 'Dogecoin Up or Down'),
      ev('bitcoin-above-on-november-8-2026-7am-et', 'Bitcoin above on 7AM'),
    ];
    addTearDown(() => pageFeed = const []);
    final world = lengthWorld(15, const Duration(minutes: 1));
    await pumpPredictionsPage(tester, world,
        size: const Size(393, 2400), sub: '15m');
    expect(find.byKey(const ValueKey('crypto-round-more-markets')),
        findsOneWidget);
    expect(find.textContaining('Dogecoin Up or Down'), findsWidgets);
    expect(find.textContaining('Bitcoin above on 7AM'), findsWidgets);
    expect(find.textContaining('BTC round on the card'), findsNothing);
    expect(find.textContaining('ETH round on the rows'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountPage(tester);
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('render: the round pages ($theme)', (tester) async {
      Future<void> shot(card.CardWorld world, String name,
          {String sub = '5m',
          Size size = const Size(393, 852),
          double textScale = 1}) async {
        await pumpPredictionsPage(tester, world,
            size: size, textScale: textScale, dark: dark, sub: sub);
        await writeViewPng(tester, '$_renderOut/${name}_$theme.png');
      await unmountPage(tester);
      }

      // 5 Min a minute in: the round in play bet.
      await shot(
          lengthWorld(5, const Duration(minutes: 1)), 'five_min_before_cutoff');
      // 5 Min past its cutoff: rolled to the next round.
      final rolled = founderWorld();
      listAll(rolled, quoted: true);
      await shot(rolled, 'five_min_after_roll');
      // The next round without prices yet.
      final unpriced = founderWorld();
      listAll(unpriced, quoted: false);
      await shot(unpriced, 'five_min_no_prices');
      // 15 Min and 1 Hour, the round in play bet.
      await shot(lengthWorld(15, const Duration(minutes: 4, seconds: 10)),
          'fifteen_min',
          sub: '15m');
      await shot(
          lengthWorld(60, const Duration(minutes: 22, seconds: 5)), 'one_hour',
          sub: '1h');
      // 1 Hour in its last five minutes: rolled.
      await shot(
          lengthWorld(60, const Duration(minutes: 56)), 'one_hour_after_roll',
          sub: '1h');
      // 320 pt, text ×1.5.
      await shot(lengthWorld(5, const Duration(minutes: 1)), 'five_min_320x1.5',
          size: const Size(320, 1500), textScale: 1.5);
      await shot(lengthWorld(60, const Duration(minutes: 22, seconds: 5)),
          'one_hour_320x1.5',
          sub: '1h', size: const Size(320, 1500), textScale: 1.5);
    }, skip: _renderOut.isEmpty);
  }
}
