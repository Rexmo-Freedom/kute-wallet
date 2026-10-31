// The Sal sheet's home variant, flat (founder, 31 October 2026): the sheet
// at 96% with the keyboard down, the composer line pinned at the top under
// the handle (Sal at 28, the text at 20 sp, a hairline under it, no box,
// the send arrow only with text) and the content scrolling under it. No
// filter row anywhere: the scope chip ("All ⌄") at the line's end only
// with a query, opening the scope menu. Blocks flat on the sheet: 13 sp
// w600 titles 12 over 56 px rows 14 apart, 28 between blocks, nothing
// drawn between rows; "Moving now" a two-column grid of six flat rows;
// "Trending predictions" one-line rows with the chance gauge and the chance
// in 16 w600; "Recent" rows; no Investing block until there are results,
// whose Investing rows carry the 48 by 20 sparkline.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart'
    show HlLineSparkline;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/search/components/search_composer.dart';
import 'package:kute/screens/search/components/search_rows.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/services/search_recent_store.dart';
import 'package:kute/theme/app_theme.dart';

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

/// The trending feed, loaded: three events.
class _Feed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) =>
      PolyFeedState(events: _predictions, done: true);
}

PolymarketEvent _event(String title, double yes) => PolymarketEvent(
      id: title,
      slug: title.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '-'),
      title: title,
      volume: 1200000,
      liquidity: 50000,
      category: 'other',
      tags: const [],
      endDate: DateTime(2027, 2, 7),
      conditionId: 'c-$title',
      outcomes: [
        PolymarketOutcome(name: 'Yes', price: yes),
        PolymarketOutcome(name: 'No', price: 1 - yes),
      ],
    );

final _predictions = [
  _event(
      'Will Bitcoin hit \$150k by March, or will the market turn before the '
      'spring and leave it short of the mark?',
      0.62),
  _event('Fed decision in December?', 0.71),
  _event('Tesla to deliver 2M cars in 2026?', 0.44),
];

HlMarket _market(String coin, double px, double prev) => HlMarket(
      coin: coin,
      wireCoin: coin,
      assetId: coin.hashCode & 0xff,
      kind: HlMarketKind.perp,
      szDecimals: 4,
      maxLeverage: 10,
      onlyIsolated: false,
      markPx: px,
      midPx: px,
      prevDayPx: prev,
      dayNtlVlm: kHlLowLiquidityDayVolumeUsd * 20,
      category: 'crypto',
      iconUrl: null,
      unitAssetName: null,
    );

/// Eight liquid movers: the grid shows six.
final _universe = [
  _market('BTC', 121845, 119200),
  _market('ETH', 4410, 4120),
  _market('SOL', 198.4, 212.1),
  _market('DOGE', 0.241, 0.262),
  _market('HYPE', 48.2, 44.9),
  _market('XRP', 2.41, 2.52),
  _market('LINK', 18.2, 17.1),
  _market('AVAX', 31.4, 33.0),
];

const _tesla = HlMarketSearchResult(
    coin: 'TSLA',
    wireCoin: 'xyz:TSLA',
    kind: HlMarketKind.perp,
    isStock: true,
    name: 'Tesla',
    category: 'stocks',
    iconUrl: null,
    markPx: 438.21,
    dayChangePct: 0.0213,
    maxLeverage: 10);

const _screen = Size(430, 932);
final _navigator = GlobalKey<NavigatorState>();

/// Opens the home variant on a 430x932 phone (the design size, so .w and
/// .h are 1:1) with [recent] Recent entries, a loaded universe for "Moving
/// now" unless [movers] is false, and a sparkline store that answers with
/// three closes.
Future<void> _open(WidgetTester tester,
    {int recent = 2, bool movers = true}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SearchRecentStore.entries.value = [
    for (var i = 0; i < recent; i++)
      i.isEven
          ? SearchRecentEntry(
              kind: SearchRecentKind.investing, id: 'BTC', label: 'BTC $i')
          : SearchRecentEntry(
              kind: SearchRecentKind.query,
              id: 'fed rates $i',
              label: 'fed rates $i'),
  ];
  addTearDown(() => SearchRecentStore.entries.value = const []);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      aiEnabledProvider.overrideWith((_) async => true),
      sportsLiveProvider.overrideWith(_Sports.new),
      unifiedSearchResultsProvider
          .overrideWith((_) async => UnifiedSearchResults.empty),
      globalMarketResultsProvider
          .overrideWith((ref) => ref.watch(searchQueryProvider).isEmpty
              ? const AsyncValue.data([])
              : AsyncValue.data(
                  [GlobalMarketSearchResult(_predictions[2])])),
      globalHyperliquidResultsProvider
          .overrideWith((ref) => ref.watch(searchQueryProvider).isEmpty
              ? const AsyncValue.data([])
              : const AsyncValue.data([_tesla])),
      hyperliquidAllMarketsProvider.overrideWith((_) => []),
      hyperliquidBrowseUniverseProvider.overrideWith(
          (_) => AsyncValue.data(movers ? _universe : const <HlMarket>[])),
      hyperliquidSparklineStoreProvider.overrideWith((_) =>
          HlSparklineStore(fetch: (_) async => const [430.0, 441.0, 438.0])),
      polyBrowseFeedProvider.overrideWith(_Feed.new),
    ],
    child: ScreenUtilInit(
      designSize: _screen,
      builder: (_, __) => MaterialApp(
        navigatorKey: _navigator,
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKuteSearch(context, source: 'home'),
              child: const Text('Open search'),
            ),
          ),
        ),
      ),
    ),
  ));
  ProviderScope.containerOf(tester.element(find.text('Open search')))
      .read(selectedSearchCategoryProvider.notifier)
      .state = SearchCategory.all;
  await tester.tap(find.text('Open search'));
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  _navigator.currentState!.pop();
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 6));
  expect(tester.takeException(), isNull);
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Rect _sheet(WidgetTester tester) =>
    tester.getRect(find.byType(AppBottomSheetContainer).first);

final Finder _chip = find.byKey(const ValueKey('search-scope-chip'));

/// The send arrow's scale (0 without text, 1 with).
final Finder _sendScale = find
    .ancestor(
        of: find.byIcon(Icons.arrow_upward_rounded),
        matching: find.byType(AnimatedScale))
    .first;

/// No hairline anywhere in the sheet: nothing half a pixel tall.
Finder get _hairlines => find.descendant(
    of: find.byType(UnifiedSearchSurface),
    matching: find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxHeight == 0.5));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => expect(await AdvisorInputGuard.isSafe('tesla'), isTrue));
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  testWidgets(
      'home variant: the sheet at 96%, keyboard down, the composer line at '
      'the top and pinned while the list scrolls, no filter row',
      (tester) async {
    await _open(tester, recent: 6);
    // The keyboard stays down until the field is tapped.
    expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isFalse);
    // No scope chip, no pill row on the empty home.
    expect(_chip, findsNothing);
    expect(find.text('All'), findsNothing);
    // The sheet stands at 96% of the screen.
    final sheet = _sheet(tester);
    expect(sheet.bottom, _screen.height);
    expect(sheet.height,
        moreOrLessEquals(_screen.height * kSearchSheetFraction, epsilon: 0.5));
    // The composer line: under the handle row, in the gutters, 56 tall,
    // nothing but a hairline under it; the text at 20 sp.
    final composer = tester.getRect(find.byType(KuteSearchComposer));
    expect(composer.top,
        moreOrLessEquals(sheet.top + kSearchSheetHandleRow, epsilon: 0.5));
    expect(composer.left, moreOrLessEquals(kSearchSheetGutter, epsilon: 0.5));
    expect(composer.right,
        moreOrLessEquals(_screen.width - kSearchSheetGutter, epsilon: 0.5));
    expect(composer.height, KuteSearchComposer.height);
    final line = tester.widget<Container>(find
        .descendant(
            of: find.byType(KuteSearchComposer), matching: find.byType(Container))
        .first);
    final decoration = line.decoration! as BoxDecoration;
    expect(decoration.color, isNull);
    expect(decoration.borderRadius, isNull);
    expect(decoration.boxShadow, isNull);
    expect((decoration.border! as Border).bottom.width, 0.5);
    expect((decoration.border! as Border).top, BorderSide.none);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.style?.fontSize, 20);
    expect(field.decoration?.hintStyle?.fontSize, 20);
    // The send arrow is away without text.
    expect(tester.widget<AnimatedScale>(_sendScale).scale, 0);
    // The content starts under the line and scrolls under it: the line
    // does not move.
    final recent = find.byKey(const ValueKey('search-home-recent'));
    final before = tester.getRect(recent);
    expect(before.top, greaterThan(composer.bottom));
    await tester.drag(recent, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(KuteSearchComposer)), composer);
    expect(tester.getRect(recent).top, lessThan(before.top - 100));
    await _close(tester);
  });

  testWidgets(
      'typing: the send arrow and the scope chip appear; the chip opens the '
      'scope menu, a pick narrows the results and renames the chip',
      (tester) async {
    await _open(tester);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(UnifiedSearchSurface)));
    await _type(tester, 'tesla');
    expect(tester.widget<AnimatedScale>(_sendScale).scale, 1);
    expect(_chip, findsOneWidget);
    expect(
        tester
            .widget<Text>(find.descendant(of: _chip, matching: find.byType(Text)))
            .data,
        'All');
    // The chip sits on the composer line, at its right.
    final composer = tester.getRect(find.byType(KuteSearchComposer));
    final chip = tester.getRect(_chip);
    expect(chip.top, greaterThan(composer.top));
    expect(chip.bottom, lessThan(composer.bottom));
    expect(chip.right, greaterThan(composer.right - 80));
    // The results: Predictions and Investing (flat, the Investing row with
    // its 48 by 20 sparkline), no Investing block before this.
    expect(find.text('Tesla to deliver 2M cars in 2026?'), findsOneWidget);
    final investing = find.byType(SearchInvestingRow);
    expect(investing, findsOneWidget);
    final spark = tester.widget<HlLineSparkline>(
        find.descendant(of: investing, matching: find.byType(HlLineSparkline)));
    expect(spark.width, 48);
    expect(spark.height, 20);
    expect(spark.closes.length, greaterThanOrEqualTo(2));
    expect(_hairlines, findsNothing);
    // The menu: the four scopes, All checked.
    await tester.tap(_chip);
    await tester.pumpAndSettle();
    final tiles =
        tester.widgetList<AppBottomSheetListTile>(find.byType(AppBottomSheetListTile));
    expect([for (final t in tiles) t.title],
        ['All', 'Predictions', 'Investing', 'Transactions']);
    expect([for (final t in tiles) t.isSelected], [true, false, false, false]);
    await tester.tap(find.descendant(
        of: find.byType(AppBottomSheetListTile),
        matching: find.text('Predictions')));
    await tester.pumpAndSettle();
    expect(container.read(selectedSearchCategoryProvider),
        SearchCategory.predictions);
    expect(find.byType(AppBottomSheetListTile), findsNothing);
    expect(
        tester
            .widget<Text>(find.descendant(of: _chip, matching: find.byType(Text)))
            .data,
        'Predictions');
    expect(find.byType(SearchInvestingRow), findsNothing);
    await _close(tester);
  });

  testWidgets(
      'the blocks: flat 56 px rows 14 apart, 28 between blocks, 13 sp w600 '
      'titles 12 over the rows, Moving now a two-column grid of six',
      (tester) async {
    await _open(tester);
    expect(_hairlines, findsNothing);
    // Three blocks, no Investing block on the empty state.
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Moving now'), findsOneWidget);
    expect(find.text('Trending predictions'), findsOneWidget);
    expect(find.text('Investing'), findsNothing);
    expect(find.byType(SearchBlockHeader), findsNWidgets(3));

    // Recent: 56 px rows, 14 apart, titles 16 w500.
    final recent = find.byKey(const ValueKey('search-home-recent'));
    final recentRows =
        find.descendant(of: recent, matching: find.byType(SearchListRow));
    expect(recentRows, findsNWidgets(2));
    final r0 = tester.getRect(recentRows.at(0));
    final r1 = tester.getRect(recentRows.at(1));
    expect(r0.height, moreOrLessEquals(56, epsilon: 0.5));
    expect(r1.top - r0.bottom, moreOrLessEquals(14, epsilon: 0.5));
    final title = tester.widget<Text>(find.text('BTC 0'));
    expect(title.style?.fontSize, 16);
    expect(title.style?.fontWeight, FontWeight.w500);

    // Moving now: six flat rows in two columns, 12 between the columns,
    // 14 between the grid's rows, logos at 36, the move in 16 w600.
    final grid = find.byKey(const ValueKey('search-home-moving'));
    final movers = find.byType(SearchMoverRow);
    expect(movers, findsNWidgets(6));
    final m0 = tester.getRect(movers.at(0));
    final m1 = tester.getRect(movers.at(1));
    final m2 = tester.getRect(movers.at(2));
    expect(m0.top, m1.top);
    expect(m0.height, moreOrLessEquals(56, epsilon: 0.5));
    expect(m1.left - m0.right, moreOrLessEquals(kSearchGridGap, epsilon: 0.5));
    expect(m0.left, moreOrLessEquals(kSearchSheetGutter, epsilon: 0.5));
    expect(m1.right,
        moreOrLessEquals(_screen.width - kSearchSheetGutter, epsilon: 0.5));
    expect(m2.top - m0.bottom, moreOrLessEquals(14, epsilon: 0.5));
    expect(
        tester
            .widget<HlCoinIcon>(
                find.descendant(of: movers.first, matching: find.byType(HlCoinIcon)))
            .size,
        36);
    final move = tester.widget<Text>(find.descendant(
        of: movers.first, matching: find.textContaining(RegExp(r'^[+−]\d'))));
    expect(move.style?.fontSize, 16);
    expect(move.style?.fontWeight, FontWeight.w600);

    // Trending: one-line 56 px rows 14 apart, the gauge and the chance in
    // 16 w600 at the right gutter.
    final trending = find.byKey(const ValueKey('search-home-trending'));
    final rows = find.descendant(of: trending, matching: find.byType(SearchPredictionRow));
    expect(rows, findsNWidgets(3));
    final t0 = tester.getRect(rows.at(0));
    final t1 = tester.getRect(rows.at(1));
    expect(t0.height, moreOrLessEquals(56, epsilon: 0.5));
    expect(t1.top - t0.bottom, moreOrLessEquals(14, epsilon: 0.5));
    expect(find.descendant(of: trending, matching: find.byType(SearchChanceGauge)),
        findsNWidgets(3));
    final long = tester.widget<Text>(find.descendant(
        of: rows.at(0), matching: find.textContaining('Will Bitcoin hit')));
    expect(long.maxLines, 1);
    expect(long.overflow, TextOverflow.ellipsis);
    final chance = tester.widget<Text>(find.text('62%'));
    expect(chance.style?.fontSize, 16);
    expect(chance.style?.fontWeight, FontWeight.w600);
    expect(tester.getRect(find.text('62%')).right,
        moreOrLessEquals(_screen.width - kSearchSheetGutter, epsilon: 0.5));

    // Titles: 13 sp w600 textPrimary, 12 over the rows; 28 between blocks.
    final header = tester.widget<Text>(find.text('Trending predictions'));
    expect(header.style?.fontSize, 13);
    expect(header.style?.fontWeight, FontWeight.w600);
    expect(header.style?.color, AppColorsExtension.light().textPrimary);
    expect(
        tester.getRect(trending).top -
            tester.getRect(find.text('Trending predictions')).bottom,
        moreOrLessEquals(12, epsilon: 0.5));
    expect(tester.getRect(grid).top - tester.getRect(find.text('Moving now')).bottom,
        moreOrLessEquals(12, epsilon: 0.5));
    final headers = find.byType(SearchBlockHeader);
    expect(tester.getRect(headers.at(1)).top - tester.getRect(recent).bottom,
        moreOrLessEquals(28, epsilon: 0.5));
    expect(tester.getRect(headers.at(2)).top - tester.getRect(grid).bottom,
        moreOrLessEquals(28, epsilon: 0.5));
    await _close(tester);
  });

  testWidgets('without recents or movers only Trending shows, still flat',
      (tester) async {
    await _open(tester, recent: 0, movers: false);
    expect(find.text('Recent'), findsNothing);
    expect(find.text('Moving now'), findsNothing);
    expect(find.text('Trending predictions'), findsOneWidget);
    expect(find.byType(SearchPredictionRow), findsNWidgets(3));
    expect(_hairlines, findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });
}
