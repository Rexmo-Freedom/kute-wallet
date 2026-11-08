// A CATEGORY PICK MOVES AS A PILL SWITCH (founder, 6 November 2026: "why
// are the animations here when clicking the buttons not the same as the
// ones from these buttons, as in going to the next page?").
//
//   * A tile presses on the app's own spring and scale, the pills' press.
//   * A pick springs the tile on, holds, the sheet closes, and once it has
//     cleared the page the pick is written: the picked pill's words morph
//     ("Investing · Filter" → "Investing · Perps") and the list switches
//     in (a fade and 24 px from the right on the sheet spring), never an
//     instant swap; the Dollars body moves the same way on a pill switch.
//   * The two sheets are one design: Predictions topics are Investing's
//     compact 60 px cards (founder, 7 November 2026: "cards here ae too
//     big"; the glyph at the left, the name and the numbers where a count
//     is at hand beside it, German included), every tile the app's soft
//     card,
//     Predictions' Trending carries its top markets' images and its
//     numbers, and an odd last card is full width (no orphan).
//   * Reduce Motion: everything at once.
//
// The sheets and a pick's frames are written as PNGs when asked:
//
//   CATEGORY_SHEET_FRAMES=<dir> flutter test test/screens/usd/category_pick_motion_test.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

// ignore: depend_on_referenced_packages
import 'package:file/file.dart' as fs;
// ignore: depend_on_referenced_packages
import 'package:file/local.dart' show LocalFileSystem;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_browse_labels.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show polyPillLabel;
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart'
    show PortfolioSection;
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/usd/investments_category_sheet.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/theme/kute_motion.dart';

import '../../helpers/offline_venue_overrides.dart';
import 'investments_harness.dart';

final _frames = Platform.environment['CATEGORY_SHEET_FRAMES'] ?? '';

AppLocalizations get _l10n => l10nForLanguage('en');

HlMarket _market(String coin,
        {String category = 'crypto',
        bool isHip3 = false,
        double vlm = 1e6,
        double prev = 99}) =>
    HlMarket(
      coin: coin,
      wireCoin: coin,
      assetId: 0,
      kind: HlMarketKind.perp,
      szDecimals: 2,
      maxLeverage: 20,
      onlyIsolated: false,
      markPx: 100,
      midPx: 100,
      prevDayPx: prev,
      dayNtlVlm: vlm,
      category: category,
      isHip3: isHip3,
      dex: isHip3 ? 'xyz' : '',
    );

final _universe = [
  _market('BTC', vlm: 9e9),
  _market('DOGE', vlm: 5e8, prev: 104),
  _market('ETH', vlm: 4e9, prev: 97),
  _market('SOL', vlm: 2e9, prev: 95),
  _market('XRP', vlm: 1e9),
  _market('NEAR', vlm: 3e8, prev: 108),
  _market('LINK', vlm: 2e8),
  _market('AVAX', vlm: 1e8),
  _market('xyz:AAPL', category: 'stocks', isHip3: true),
  _market('xyz:SPX', category: 'indices', isHip3: true),
];

/// The artwork the renders draw: the app's own logos for the Trending
/// markets' images (no network in a test).
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

/// Trending holds five markets with images and a day's volume; every
/// other list is empty and read (nothing goes to the network).
class _Feed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) {
    if (arg.pill != PolyPill.trending) return const PolyFeedState(done: true);
    return PolyFeedState(done: true, events: [
      for (var i = 0; i < 5; i++)
        PolymarketEvent(
          id: 't$i',
          slug: 't$i',
          title: 'Trending market $i',
          imageUrl: 'https://polymarket-upload.example/img-$i.png',
          volume: 9e7,
          volume24hr: 3e6 - i * 1e5,
          liquidity: 1e5,
          category: 'politics',
          conditionId: 't$i',
          outcomes: [
            PolymarketOutcome(name: 'Yes', price: 0.4),
            PolymarketOutcome(name: 'No', price: 0.6),
          ],
        ),
    ]);
  }
}

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

/// The offline Predictions lists, Crypto's site count for All (48).
List<Override> _predictionsOverrides() => [
      ...offlineVenueOverrides,
      polyBrowseFeedProvider.overrideWith(_Feed.new),
      sportsLiveProvider.overrideWith(_Sports.new),
      polyTopicSubsProvider
          .overrideWith((ref, pill) => Stream.value(const <PolySub>[])),
      polyCryptoSubsProvider.overrideWith((ref) => Stream.value(const [
            PolySub('all', count: 48),
            PolySub('5m', count: 6),
            PolySub('daily', count: 12),
          ])),
    ];

List<Override> _investingOverrides([List<HlMarket>? universe]) => [
      hyperliquidBrowseUniverseProvider
          .overrideWithValue(AsyncValue.data(universe ?? _universe)),
      hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
    ];

/// The Dollars page under the shell's Material, as on a phone (the pills'
/// words in the theme's Inter, so the picked pill keeps its context).
const Widget _page = Scaffold(body: UsdAccountScreen());

Future<void> _frames8(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The sheet of [tab] over a plain page (a button opening it).
Future<void> _openSheet(WidgetTester tester, InvestmentsTab tab,
    {required List<Override> overrides,
    bool browse = false,
    bool dark = false,
    Locale? locale,
    Size size = const Size(390, 844)}) async {
  await pumpInvestments(
    tester,
    dark: dark,
    locale: locale,
    size: size,
    browseInvesting: browse,
    browsePredictions: browse,
    overrides: overrides,
    child: Scaffold(
      body: Consumer(
        builder: (context, ref, _) => Center(
          child: TextButton(
            onPressed: () => showInvestmentsCategorySheet(context, ref, tab),
            child: const Text('Open categories'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open categories'));
  await _frames8(tester);
}

Finder _tile(String key) => find.byKey(ValueKey('category-tile-$key'));

/// The words box of the Dollars switch's picked pill, by what they say.
Finder _words(String text) => find.descendant(
    of: find.byType(KutePillTabs).first, matching: find.text(text));

Finder _inBrowser(Finder f) =>
    find.descendant(of: find.byType(HyperliquidScreen), matching: f);

RenderKuteSliverShift _listShift(WidgetTester tester) =>
    tester.renderObject<RenderKuteSliverShift>(
        _inBrowser(find.byType(KuteSliverShift)));

double _listOpacity(WidgetTester tester) => tester
    .widget<SliverFadeTransition>(
        _inBrowser(find.byType(SliverFadeTransition)).first)
    .opacity
    .value;

/// The Dollars body's switch ([SelectionFade]): its opacity and shift.
(double, double) _body(WidgetTester tester) {
  final fade = find.byType(SelectionFade);
  final opacity = tester
      .widget<FadeTransition>(
          find.descendant(of: fade, matching: find.byType(FadeTransition)).first)
      .opacity
      .value;
  final shift = tester
      .widget<Transform>(
          find.descendant(of: fade, matching: find.byType(Transform)).first)
      .transform
      .getTranslation()
      .x;
  return (opacity, shift);
}

Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
}

/// The whole screen (the page and the sheet over it) as a PNG.
Future<void> _shot(WidgetTester tester, String name) async {
  if (_frames.isEmpty) return;
  // The artwork's file reads and decodes run on real time: let them land
  // (pump() moves no clock, so a pick's frames keep their times).
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump();
  }
  // The cards' soft shadows drawn as on a phone (flutter_test paints
  // them flat), then flat again for the binding's check.
  debugDisableShadows = false;
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_frames).createSync(recursive: true);
    File('$_frames/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
  await tester.pump();
}

/// The shipped languages, German's long words first.
const _kLanguages = [
  'en',
  'de',
  'bg',
  'cs',
  'da',
  'el',
  'es',
  'et',
  'fi',
  'fr',
  'hr',
  'hu',
  'it',
  'ja',
  'lt',
  'lv',
  'nl',
  'pl',
  'pt',
  'ro',
  'sk',
  'sl',
  'sv'
];

/// The compact card's least height (investments_category_sheet.dart).
abstract final class _Compact {
  static const double height = 60;
}

/// The universe with three stocks, so the traditional group's card carries
/// its full three-logo stack beside "Stocks and shares".
final _kThreeStocks = [
  ..._universe,
  _market('xyz:TSLA', category: 'stocks', isHip3: true, prev: 97),
  _market('xyz:NVDA', category: 'stocks', isHip3: true, prev: 103),
];

/// Esports' live subcategories, the founder's two and longer.
const _kLongEsports = [
  PolySub('all'),
  PolySub('mlbb', label: 'Mobile Legends: Bang Bang'),
  PolySub('sc', label: 'StarCraft: Brood War'),
  PolySub('cs2', label: 'CS2'),
  PolySub('long',
      label: 'The Extraordinarily Long International Championship Series '
          'Grand Finals Presented By Somebody'),
  PolySub('word', label: 'Supercalifragilisticexpialidociousleague'),
  PolySub('dota', label: 'Dota 2'),
];

String _hlName(AppLocalizations l10n, HlBrowseTab t) =>
    t == HlBrowseTab.watchlist
        ? l10n.polyPillWatchlist
        : t.localizedLabel(l10n);

/// Every card of [keys] whole: at least the compact height, its words
/// inside it (a name in [names] never cut short), and the cards that
/// share a row equally tall.
void _expectCardsWhole(WidgetTester tester, List<String> keys,
    {Map<String, String> names = const {}, required String reason}) {
  Rect cardOf(String key) => tester.getRect(find
      .descendant(of: _tile(key), matching: find.byType(AnimatedContainer))
      .first);
  final rects = <String, Rect>{};
  for (final key in keys) {
    final card = cardOf(key);
    rects[key] = card;
    expect(card.height, greaterThanOrEqualTo(_Compact.height - 0.01),
        reason: '$reason $key');
    for (final words in tester.renderObjectList<RenderParagraph>(
        find.descendant(of: _tile(key), matching: find.byType(RichText)))) {
      final box = MatrixUtils.transformRect(
          words.getTransformTo(null), Offset.zero & words.size);
      expect(box.top, greaterThanOrEqualTo(card.top - 0.01),
          reason: '$reason $key: its words inside the card');
      expect(box.bottom, lessThanOrEqualTo(card.bottom + 0.01),
          reason: '$reason $key: its words inside the card');
      expect(box.right, lessThanOrEqualTo(card.right + 0.01),
          reason: '$reason $key: its words inside the card');
    }
    final name = names[key];
    if (name != null) {
      final text = find.descendant(of: _tile(key), matching: find.text(name));
      expect(text, findsOneWidget, reason: '$reason $key');
      expect(
          tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse,
          reason: '$reason $key: the name whole');
    }
  }
  for (final a in rects.entries) {
    for (final b in rects.entries) {
      if ((a.value.top - b.value.top).abs() < 0.5) {
        expect(a.value.height, closeTo(b.value.height, 0.01),
            reason: '$reason ${a.key} / ${b.key}: one row, one height');
      }
    }
  }
}

/// The sheet's gutters are equal: the content as far from the sheet's left
/// edge as from its right ([key]'s row is checked against the screen,
/// the sheet spanning it).
void _expectSymmetricGutters(WidgetTester tester, String key) {
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  final rows = [
    for (final e in find.byType(AnimatedContainer).evaluate())
      tester.getRect(find.byWidget(e.widget)),
  ];
  final left = rows.map((r) => r.left).reduce(math.min);
  final right = rows.map((r) => r.right).reduce(math.max);
  expect(left, greaterThan(0));
  expect(screen.width - right, closeTo(left, 0.5),
      reason: 'the same gutter on both sides');
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Inter, as on a phone: the picked pill's context fits the switch.
    await _loadInter();
  });
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    PolyCrestImage.debugCacheManager = _frames.isEmpty ? null : _LocalArtwork();
  });
  tearDown(() => PolyCrestImage.debugCacheManager = null);

  testWidgets(
      'a pill switch: the Dollars body comes in from the pill\'s side, a fade '
      'and 24 px on the sheet spring, never an instant swap', (tester) async {
    await pumpInvestments(tester,
        browseInvesting: true,
        overrides: _investingOverrides(),
        child: _page);
    // The page opens on Investing, at rest (founder, 7 November 2026).
    expect(_body(tester), (1.0, 0.0));

    // Investing → Activity (to the left): from the left.
    await tester.tap(investmentsPill(_l10n.activity));
    await tester.pump();
    expect(_body(tester), (0.0, -KuteMotion.switchSlide));
    await _frames8(tester);
    expect(_body(tester).$1, 1);
    expect(_body(tester).$2, closeTo(0, 0.01));

    // Activity → Investing (to the right): from the right.
    await tester.tap(investmentsPill(_l10n.trading));
    await tester.pump();
    expect(_body(tester), (0.0, KuteMotion.switchSlide));
    await tester.pump(const Duration(milliseconds: 60));
    final (opacity, shift) = _body(tester);
    expect(opacity, inExclusiveRange(0, 1));
    expect(shift, inExclusiveRange(0, KuteMotion.switchSlide));
    await _frames8(tester);
    expect(_body(tester).$1, 1);
    expect(_body(tester).$2, closeTo(0, 0.01));
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'a category pick: the tile presses as the pills do, springs on, the '
      'sheet closes, then the pill\'s words morph and the list switches in '
      'as on a pill switch', (tester) async {
    final events = recordEvents();
    await pumpInvestments(tester,
        browseInvesting: true,
        overrides: _investingOverrides(),
        child: _page);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(UsdAccountScreen)));
    // The page opens on Investing (founder, 7 November 2026).
    expect(container.read(investmentsTabProvider), InvestmentsTab.investing);
    await _frames8(tester);
    final filter = '${_l10n.trading} · ${_l10n.categoryFilterPrompt}';
    final perps =
        '${_l10n.trading} · ${HlBrowseTab.perps.localizedLabel(_l10n)}';
    expect(_words(filter), findsOneWidget);
    // At rest on the list: nothing shifted.
    expect(_listShift(tester).dx, 0);
    expect(_listOpacity(tester), 1);

    // The sheet: the picked pill again.
    await tapAndPump(tester, investmentsPill(_l10n.trading));
    await _frames8(tester);
    final tile = _tile(HlBrowseTab.perps.key);
    expect(tile, findsOneWidget);

    // THE PRESS: the app's press, the very scale and spring the pills use.
    KutePressable pressableOf(Finder f) => tester.widget<KutePressable>(
        find.descendant(of: f, matching: find.byType(KutePressable)).first);
    expect(pressableOf(tile).scale, KuteMotion.pressScale);
    final pillPress = tester.widget<KutePressable>(find
        .descendant(
            of: find.byType(KutePillTabs).first,
            matching: find.byType(KutePressable))
        .first);
    expect(pressableOf(tile).scale, pillPress.scale);
    AnimatedScale scaleOf(Finder f) => tester.widget<AnimatedScale>(find
        .descendant(
            of: find.descendant(of: f, matching: find.byType(KutePressable)).first,
            matching: find.byType(AnimatedScale))
        .first);
    final press = await tester.startGesture(tester.getCenter(tile));
    await tester.pump(KuteMotion.pressInDuration);
    expect(scaleOf(tile).scale, KuteMotion.pressScale);
    await press.cancel();
    await tester.pump();
    expect(scaleOf(tile).scale, 1.0);
    expect(scaleOf(tile).curve, KuteMotion.press, reason: 'back on the spring');
    await tester.pump(KuteMotion.pressDuration);

    // THE PICK: springs on at once, the sheet holds it 140 ms.
    await tester.tap(tile);
    await tester.pump();
    final box = tester
        .widget<AnimatedContainer>(
            find.descendant(of: tile, matching: find.byType(AnimatedContainer)))
        .decoration! as BoxDecoration;
    expect((box.border! as Border).top.width, 1.5,
        reason: 'the pick springs on: the CTA ring');
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(hlBrowseSelectionProvider).tab,
        HlBrowseTab.trending, reason: 'held, not yet written');
    // The sheet closes; the pick waits until it has cleared the page.
    await tester.pump(const Duration(milliseconds: 60));
    expect(container.read(hlBrowseSelectionProvider).tab,
        HlBrowseTab.trending, reason: 'the sheet is still in the way');
    expect(_words(filter), findsOneWidget);
    await tester.pump(kCategoryPickWriteDelay + const Duration(milliseconds: 20));
    expect(container.read(hlBrowseSelectionProvider).tab, HlBrowseTab.perps);
    expect(events.where((e) => e.$1 == 'hl_category_pill_tapped').single.$2,
        {'section': HlBrowseTab.perps.key});

    // THE SWITCH, as a pill switch: the list from the right with a fade,
    // the words morphing (both on screen), never an instant swap.
    await tester.pump(const Duration(milliseconds: 60));
    expect(_listShift(tester).dx,
        inExclusiveRange(0, KuteMotion.switchSlide));
    expect(_listOpacity(tester), inExclusiveRange(0, 1));
    expect(_words(filter), findsOneWidget, reason: 'the old words fading');
    expect(_words(perps), findsOneWidget, reason: 'the new words coming');
    // The Dollars body itself stays: the list moves, as it does for a pill.
    expect(_body(tester), (1.0, 0.0));

    await _frames8(tester);
    expect(_listShift(tester).dx, closeTo(0, 0.01));
    expect(_listOpacity(tester), 1);
    expect(_words(filter), findsNothing);
    expect(_words(perps), findsOneWidget);
    expect(_tile(HlBrowseTab.perps.key), findsNothing, reason: 'closed');
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'Reduce Motion: a pick is written as the sheet goes, the words and the '
      'list at rest at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpInvestments(tester,
        browseInvesting: true,
        overrides: _investingOverrides(),
        child: _page);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(UsdAccountScreen)));
    // The page opens on Investing (founder, 7 November 2026), at rest.
    expect(container.read(investmentsTabProvider), InvestmentsTab.investing);
    expect(_body(tester), (1.0, 0.0));
    await tapAndPump(tester, investmentsPill(_l10n.trading));
    await tester.tap(_tile(HlBrowseTab.perps.key));
    await tester.pump();
    await tester.pump();
    expect(container.read(hlBrowseSelectionProvider).tab, HlBrowseTab.perps);
    expect(_listShift(tester).dx, 0);
    expect(_listOpacity(tester), 1);
    expect(
        _words('${_l10n.trading} · ${HlBrowseTab.perps.localizedLabel(_l10n)}'),
        findsOneWidget);
    expect(_words('${_l10n.trading} · ${_l10n.categoryFilterPrompt}'),
        findsNothing);
    await _frames8(tester);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'the Predictions sheet is the Investing sheet: Trending with its '
      'markets\' images stacked and its numbers, every topic a compact card '
      'with its glyph, numbers where a count is at hand, no orphan',
      (tester) async {
    await _openSheet(tester, InvestmentsTab.predictions,
        overrides: _predictionsOverrides(), browse: true);

    // Trending, beside Instant: three images stacked, "Most active · $X vol
    // today", never the bare dot.
    final trending = _tile(PolyPill.trending.key);
    expect(tester.getSize(trending).height, greaterThanOrEqualTo(64));
    expect(find.descendant(of: trending, matching: find.byType(PolyCrestImage)),
        findsNWidgets(3));
    // Each on a soft tinted disc while it loads (Investing's letter discs),
    // never a blank ring.
    for (final crest in tester.widgetList<PolyCrestImage>(
        find.descendant(of: trending, matching: find.byType(PolyCrestImage)))) {
      final disc = tester.widget<DecoratedBox>(find
          .ancestor(
              of: find.byWidget(crest), matching: find.byType(DecoratedBox))
          .first);
      final color = (disc.decoration as BoxDecoration).color;
      expect(color, isNotNull);
      expect(color!.a, inExclusiveRange(0, 1));
      expect(crest.label, isNotNull, reason: 'initials if it fails');
    }
    expect(
        find.descendant(
            of: trending,
            matching: find.textContaining(_l10n.categoryStatMostActive,
                findRichText: true)),
        findsOneWidget);
    expect(
        find.descendant(
            of: trending,
            matching: find.textContaining('vol today', findRichText: true)),
        findsOneWidget);

    // The topics: compact cards, two columns, Polymarket's glyph each at
    // the left of the name, a little shorter than the Trending row.
    final politics = _tile(PolyPill.politics.key);
    final card = find.descendant(
        of: politics, matching: find.byType(AnimatedContainer));
    expect(tester.getSize(card).height, 60);
    expect(tester.getSize(card).height,
        lessThan(tester.getSize(trending).height));
    final glyph = find.descendant(
        of: politics,
        matching: find.byKey(const ValueKey('category-tile-icon-politics')));
    final name = find.descendant(
        of: politics, matching: find.text(_l10n.polyPillPolitics));
    expect(tester.getCenter(glyph).dy, closeTo(tester.getCenter(name).dy, 1),
        reason: 'the glyph and the name on one row');
    expect(tester.getRect(glyph).right, lessThan(tester.getRect(name).left));
    expect(
        find.descendant(
            of: politics,
            matching: find.byKey(const ValueKey('category-tile-icon-politics'))),
        findsOneWidget);
    // Crypto's site count for All is at hand: "48 markets".
    expect(
        find.descendant(
            of: _tile(PolyPill.crypto.key),
            matching: find.textContaining(_l10n.categoryStatMarkets(48),
                findRichText: true)),
        findsOneWidget);
    // A topic with no count at hand carries its glyph and name alone.
    expect(
        find.descendant(
            of: politics,
            matching: find.textContaining('market', findRichText: true)),
        findsNothing);

    // Every topic in pairs, an odd last one full width as the wide row.
    final keys = [
      for (final p in PolyPill.values)
        if (p != PolyPill.trending &&
            p != PolyPill.instant &&
            p != PolyPill.watchlist &&
            _tile(p.key).evaluate().isNotEmpty)
          p.key,
    ];
    expect(keys.length, greaterThan(6));
    // Trending is one of the two square cards on top, half the width.
    final width = tester.getSize(trending).width * 2 + 8;
    for (final (i, key) in keys.indexed) {
      final rect = tester.getRect(find
          .descendant(of: _tile(key), matching: find.byType(AnimatedContainer)));
      final lone = keys.length.isOdd && i == keys.length - 1;
      if (lone) {
        expect(rect.width, closeTo(width, 0.5), reason: '$key: no orphan');
        expect(rect.height, closeTo(64, 0.01), reason: '$key: the wide row');
      } else {
        expect(rect.width, lessThan(width / 2), reason: key);
        expect(rect.height, 60, reason: key);
      }
    }
    await _shot(tester, 'predictions_sheet_light');
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  // THE CARDS NEVER OVERFLOW (founder, 7 November 2026: "Stocks and
  // shares" beside its three logos, "Mobile Legends: Bang Bang" and
  // "StarCraft: Brood War" in Esports overflowed the fixed card by 2 px).
  // Every grid is checked on the real sheet, the real cards with their
  // logo stacks, in every shipped language at 375 and 402 pt: nothing
  // overflows, every name whole inside its card, the two cards of a row
  // equally tall. Names that are live data (Polymarket's subcategories)
  // are checked with long synthetic ones at larger text sizes too.
  for (final width in [375.0, 402.0]) {
    for (final lang in _kLanguages) {
      testWidgets(
          'the cards fit at ${width.toInt()} pt in $lang, Investing '
          'and Predictions', (tester) async {
        final l10n = l10nForLanguage(lang);
        await _openSheet(tester, InvestmentsTab.investing,
            overrides: _investingOverrides(_kThreeStocks),
            browse: true,
            locale: Locale(lang),
            size: Size(width, 1800));
        expect(tester.takeException(), isNull, reason: 'Investing $lang');
        final groups = [
          for (final t in HlBrowseTab.values)
            if (_tile(t.key).evaluate().isNotEmpty) t,
        ];
        expect(groups.length, greaterThan(2));
        // The traditional group carries its three logos.
        expect(
            find.descendant(
                of: _tile(HlBrowseTab.tradfi.key),
                matching: find.byType(HlCoinIcon)),
            findsNWidgets(3));
        _expectCardsWhole(tester, [for (final t in groups) t.key],
            names: {for (final t in groups) t.key: _hlName(l10n, t)},
            reason: 'Investing $lang ${width.toInt()}');
        await unmountInvestments(tester);

        await _openSheet(tester, InvestmentsTab.predictions,
            overrides: _predictionsOverrides(),
            browse: true,
            locale: Locale(lang),
            size: Size(width, 1800));
        expect(tester.takeException(), isNull, reason: 'Predictions $lang');
        final topics = [
          for (final p in PolyPill.values)
            if (_tile(p.key).evaluate().isNotEmpty) p,
        ];
        expect(topics.length, greaterThan(6));
        _expectCardsWhole(tester, [for (final p in topics) p.key],
            names: {
              for (final p in topics)
                p.key: p == PolyPill.watchlist
                    ? l10n.polyPillWatchlist
                    : polyPillLabel(l10n, p),
            },
            reason: 'Predictions $lang ${width.toInt()}');
        _expectSymmetricGutters(tester, topics.first.key);
        expect(tester.takeException(), isNull);
        await unmountInvestments(tester);
      });
    }
  }

  for (final scale in [1.0, 1.3, 1.6]) {
    for (final width in [375.0, 402.0]) {
      testWidgets(
          'live subcategory names of any length grow their card, '
          'never overflow: Esports at ${width.toInt()} pt, text x$scale',
          (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _openSheet(tester, InvestmentsTab.predictions,
            overrides: [
              ..._predictionsOverrides(),
              polyEsportsSubsProvider
                  .overrideWith((ref) => Stream.value(_kLongEsports)),
            ],
            browse: true,
            size: Size(width, 2400));
        await tester.ensureVisible(_tile(PolyPill.esports.key));
        await tester.pump();
        await tester.tap(_tile(PolyPill.esports.key));
        await _frames8(tester);
        final keys = [
          for (final sub in _kLongEsports)
            if (sub.key != 'all' && _tile(sub.key).evaluate().isNotEmpty)
              sub.key,
        ];
        expect(keys, hasLength(_kLongEsports.length - 1));
        _expectCardsWhole(tester, keys,
            reason: 'Esports ${width.toInt()} x$scale');
        // At the default size the founder's names run onto their second
        // line, inside the card (checked above), never cut short. Larger
        // text, or a name longer than two lines can hold, ends in an
        // ellipsis on the second line: the card grows, it never overflows.
        for (final name in [
          if (scale == 1.0) ...[
            'Mobile Legends: Bang Bang',
            'StarCraft: Brood War',
          ],
        ]) {
          final words = tester.renderObject<RenderParagraph>(find.text(name));
          final lines = {
            for (final box in words.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: name.length)))
              box.top.round(),
          };
          expect(lines, hasLength(2), reason: name);
          expect(words.didExceedMaxLines, isFalse, reason: name);
        }
        _expectSymmetricGutters(tester, 'mlbb');
        expect(tester.takeException(), isNull);
        await unmountInvestments(tester);
      });
    }
  }

  testWidgets(
      'the Investing sheet and the Portfolio section at text x1.6: the '
      'cards grow, never overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _openSheet(tester, InvestmentsTab.investing,
        overrides: _investingOverrides(_kThreeStocks),
        browse: true,
        size: const Size(402, 1800));
    final groups = [
      for (final t in HlBrowseTab.values)
        if (_tile(t.key).evaluate().isNotEmpty) t.key,
    ];
    _expectCardsWhole(tester, groups, reason: 'Investing x1.6');
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);

    // The Portfolio section's three cards: two over one, at x1.6 too.
    await _openSheet(tester, InvestmentsTab.positions,
        overrides: const [], size: const Size(375, 1800));
    final cards = [
      for (final section in PortfolioSection.values)
        tester.getRect(find
            .ancestor(
                of: find.text(portfolioSectionLabel(_l10n, section)),
                matching: find.byType(AnimatedContainer))
            .first),
    ];
    expect(cards[0].height, greaterThanOrEqualTo(_Compact.height));
    expect(cards[1].height, closeTo(cards[0].height, 0.01),
        reason: 'one row, one height');
    expect(cards[2].top, greaterThan(cards[0].bottom));
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('no orphan: three Portfolio sections are two cards over one row',
      (tester) async {
    await _openSheet(tester, InvestmentsTab.positions, overrides: const []);
    Rect cardOf(PortfolioSection s) => tester.getRect(find
        .ancestor(
            of: find.text(portfolioSectionLabel(_l10n, s)),
            matching: find.byType(AnimatedContainer))
        .first);
    final cards = [for (final s in PortfolioSection.values) cardOf(s)];
    expect(cards, hasLength(3));
    // Two squares side by side…
    expect(cards[1].top, cards[0].top);
    expect(cards[1].left, greaterThan(cards[0].right));
    expect(cards[0].height, 60);
    // …and the third across the whole width under them, as the wide row.
    expect(cards[2].top, greaterThan(cards[0].bottom));
    expect(cards[2].left, closeTo(cards[0].left, 0.5));
    expect(cards[2].right, closeTo(cards[1].right, 0.5));
    expect(cards[2].height, closeTo(64, 0.01));
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('renders: both sheets, light and dark, and a pick\'s frames',
      (tester) async {
    if (_frames.isEmpty) return;
    for (final dark in [false, true]) {
      final suffix = dark ? 'dark' : 'light';
      await _openSheet(tester, InvestmentsTab.investing,
          overrides: _investingOverrides(), browse: true, dark: dark);
      await _shot(tester, 'investing_sheet_$suffix');
      await unmountInvestments(tester);
      await _openSheet(tester, InvestmentsTab.predictions,
          overrides: _predictionsOverrides(), browse: true, dark: dark);
      await _shot(tester, 'predictions_sheet_$suffix');
      await unmountInvestments(tester);
      // German, the long words, on a 375 pt phone.
      await _openSheet(tester, InvestmentsTab.predictions,
          overrides: _predictionsOverrides(),
          browse: true,
          dark: dark,
          locale: const Locale('de'),
          size: const Size(375, 812));
      await _shot(tester, 'predictions_sheet_de_$suffix');
      await unmountInvestments(tester);
      // The founder's phone (402 pt): "Stocks and shares" beside its three
      // logos on two lines, its row grown to it; Esports' long live names.
      await _openSheet(tester, InvestmentsTab.investing,
          overrides: _investingOverrides(_kThreeStocks),
          browse: true,
          dark: dark,
          size: const Size(402, 874));
      await _shot(tester, 'investing_sheet_402_$suffix');
      await unmountInvestments(tester);
      await _openSheet(tester, InvestmentsTab.predictions,
          overrides: [
            ..._predictionsOverrides(),
            polyEsportsSubsProvider
                .overrideWith((ref) => Stream.value(_kLongEsports)),
          ],
          browse: true,
          dark: dark,
          size: const Size(402, 874));
      await tester.ensureVisible(_tile(PolyPill.esports.key));
      await tester.pump();
      await tester.tap(_tile(PolyPill.esports.key));
      await _frames8(tester);
      await _shot(tester, 'esports_sheet_402_$suffix');
      await unmountInvestments(tester);
    }
    // A pick on the Dollars page, frame by frame.
    await pumpInvestments(tester,
        browseInvesting: true,
        overrides: _investingOverrides(),
        child: _page);
    await tapAndPump(tester, investmentsPill(_l10n.trading));
    await _frames8(tester);
    await tapAndPump(tester, investmentsPill(_l10n.trading));
    await _frames8(tester);
    await tester.tap(_tile(HlBrowseTab.perps.key));
    var t = 0;
    for (final step in [0, 60, 100, 60, 60, 60, 80, 120, 200]) {
      await tester.pump(Duration(milliseconds: step));
      t += step;
      await _shot(tester, 'pick_${t.toString().padLeft(4, '0')}ms');
    }
    await unmountInvestments(tester);
  });
}
