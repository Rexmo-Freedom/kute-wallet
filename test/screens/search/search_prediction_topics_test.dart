// The search sheet under the Predictions scope: the topics row (All,
// Politics, Sports … Art) narrows the venue search to one category and
// says so to PostHog by slug; a query that names a category leads the
// results with that category; "Show more" reads the next venue page.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/screens/polymarket/components/poly_sport_icon.dart';
import 'package:kute/screens/search/components/search_rows.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/trade_notification_store.dart'
    show TradeNotification;
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart' show Fixed;

import '../usd/investments_harness.dart'
    show InvestmentsTestPolicy, kEarnOff;

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100000)}));
  @override
  Future<void> updateRates() async {}
}

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: true,
      wallets: [WalletConfig(id: 'spending', name: 'Spending')],
      activeWalletId: 'spending',
    );

PolymarketEvent _poly(String title) => PolymarketEvent(
      id: title,
      slug: title.toLowerCase().replaceAll(' ', '-'),
      title: title,
      volume: 1000,
      liquidity: 5000,
      category: 'sports',
      conditionId: 'c-$title',
      outcomes: const [
        PolymarketOutcome(name: 'Yes', price: 0.5),
        PolymarketOutcome(name: 'No', price: 0.5),
      ],
    );

/// The venue search, answered at once: two matches per query, a page
/// after; the queries and the Show more taps recorded.
class _Feed extends PolySearchFeed {
  static final queries = <PolySearchQuery>[];
  static var more = 0;

  @override
  PolySearchState build(PolySearchQuery arg) {
    if (arg.query.isEmpty) return const PolySearchState();
    queries.add(arg);
    return PolySearchState(
      events: [_poly('${arg.query} one'), _poly('${arg.query} two')],
      hasMore: true,
      pages: 1,
    );
  }

  @override
  Future<void> loadMore() async {
    more++;
    state = state.copyWith(hasMore: false, pages: 2);
  }
}

Future<ProviderContainer> _open(WidgetTester tester, String query) async {
  // A policy that offers every category (Sports and Politics included)
  // and the venue's browse, with no fetch and no timers.
  final policy = InvestmentsTestPolicy(kEarnOff, browsePredictions: true);
  tester.view.physicalSize = const Size(430, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      currencyProvider.overrideWith((_) => _Currency()),
      aiEnabledProvider.overrideWith((_) async => true),
      sportsLiveProvider.overrideWith(_Sports.new),
      tradeNotificationsProvider
          .overrideWith((_) => Stream.value(const <TradeNotification>[])),
      unifiedSearchResultsProvider
          .overrideWith((ref) async => UnifiedSearchResults.empty),
      polySearchFeedProvider.overrideWith(_Feed.new),
      globalHyperliquidResultsProvider
          .overrideWith((_) => const AsyncValue.data([])),
      hyperliquidAllMarketsProvider.overrideWith((_) => []),
      // The leagues, known without Gamma: LaLiga under Soccer.
      polySportsDirectoryProvider.overrideWith((_) async => const [
            {
              'sport': 'lal',
              'name': 'LaLiga',
              'image': null,
              'series': '10193',
              'tags': '1,780,100639,100350',
            },
          ]),
      polyLeagueRowsProvider
          .overrideWith((_) => Stream.value(const <Map<String, dynamic>>[])),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKuteSearch(context,
                  initialCategory: SearchCategory.predictions,
                  searchFirst: true,
                  source: 'predictions'),
              child: const Text('Open search'),
            ),
          ),
        ),
      ),
    ),
  ));
  final container =
      ProviderScope.containerOf(tester.element(find.text('Open search')));
  await tester.tap(find.text('Open search'));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await _settle(tester);
  return container;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

final _topics = find.byKey(const ValueKey('search-prediction-topics'));

List<String> _topicLabels(WidgetTester tester) => [
      for (final p in tester.widgetList<KutePill>(
          find.descendant(of: _topics, matching: find.byType(KutePill))))
        p.label,
    ];

Finder _topic(String label) => find.descendant(
    of: _topics, matching: find.widgetWithText(KutePill, label));

List<String> _rowTitles(WidgetTester tester) => [
      for (final r
          in tester.widgetList<SearchListRow>(find.byType(SearchListRow)))
        r.title,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
      () async => expect(await AdvisorInputGuard.isSafe('madrid'), isTrue));
  late List<(String, Map<String, Object>?)> events;
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
    _Feed.queries.clear();
    _Feed.more = 0;
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() => TrackingService.debugTrackObserver = null);

  testWidgets(
      'the topics row: All first, then the site\'s topics; a pick scopes '
      'the venue search by tag slug and is reported by slug', (tester) async {
    final container = await _open(tester, 'madrid');
    expect(_topics, findsOneWidget);
    expect(_topicLabels(tester), [
      'All', 'Politics', 'Sports', 'Crypto', 'Esports', 'Finance',
      'Geopolitics', 'Tech', 'Elections', 'Culture', 'Economy', 'Weather',
      'Mentions', 'Art', //
    ]);
    expect(tester.widget<KutePill>(_topic('All')).selected, isTrue);
    expect(_Feed.queries.last, (query: 'madrid', tag: null));
    expect(_rowTitles(tester), ['madrid one', 'madrid two']);

    await tester.ensureVisible(_topic('Sports'));
    await tester.tap(_topic('Sports'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);
    expect(container.read(searchPredictionsTopicProvider), PolyPill.sports);
    expect(tester.widget<KutePill>(_topic('Sports')).selected, isTrue);
    expect(tester.widget<KutePill>(_topic('All')).selected, isFalse);
    // The venue search ran again, scoped to Sports' tag.
    expect(_Feed.queries.last, (query: 'madrid', tag: 'sports'));
    expect(events.where((e) => e.$1 == 'search_category_changed').last.$2,
        {'category': 'sports', 'source': 'topic'});
    // Nothing typed ever leaves the device.
    for (final (_, params) in events) {
      expect('${params ?? {}}', isNot(contains('madrid')));
    }

    // Back to All: everything again.
    await tester.ensureVisible(_topic('All'));
    await tester.tap(_topic('All'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);
    expect(container.read(searchPredictionsTopicProvider), isNull);
    expect(_Feed.queries.last, (query: 'madrid', tag: null));
    expect(events.where((e) => e.$1 == 'search_category_changed').last.$2,
        {'category': 'predictions', 'source': 'topic'});
    await _close(tester);
  });

  testWidgets('"Show more" reads the next venue page, then is gone',
      (tester) async {
    await _open(tester, 'madrid');
    final more = find.byKey(const ValueKey('search-show-more'));
    expect(more, findsOneWidget);
    expect(find.text('Show more'), findsOneWidget);
    // After the rows, the last row of the group.
    expect(tester.getTopLeft(more).dy,
        greaterThan(tester.getTopLeft(find.text('madrid two')).dy));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await _settle(tester);
    expect(_Feed.more, 1);
    expect(more, findsNothing);
    await _close(tester);
  });

  testWidgets(
      'a query that names a category leads the results with it: "soccer" '
      'is Sports › Soccer, "art" is Art, "laliga" the league', (tester) async {
    await _open(tester, 'soccer');
    expect(_rowTitles(tester), ['Soccer', 'soccer one', 'soccer two']);
    final row = tester.widget<SearchListRow>(find.byType(SearchListRow).first);
    expect(row.subtitle, 'Predictions · Sports');
    expect(find.byKey(const ValueKey('poly-category-sports/soccer')),
        findsOneWidget);
    // The sport's own icon, not the Sports topic's trophy.
    expect(
        tester
            .widget<PolySportIcon>(find.descendant(
                of: find.byKey(const ValueKey('poly-category-sports/soccer')),
                matching: find.byType(PolySportIcon)))
            .sub
            .key,
        'soccer');

    await tester.enterText(find.byType(TextField), 'art');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);
    expect(_rowTitles(tester).first, 'Art');
    expect(tester.widget<SearchListRow>(find.byType(SearchListRow).first).subtitle,
        'Predictions');

    await tester.enterText(find.byType(TextField), 'laliga');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);
    expect(_rowTitles(tester).first, 'LaLiga');
    expect(find.byKey(const ValueKey('poly-category-sports/series:10193')),
        findsOneWidget);
    expect(
        tester
            .widget<PolySportIcon>(find.descendant(
                of: find.byKey(
                    const ValueKey('poly-category-sports/series:10193')),
                matching: find.byType(PolySportIcon)))
            .sub
            .key,
        'series:10193');

    // A query that names no category: the markets alone.
    await tester.enterText(find.byType(TextField), 'madrid');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);
    expect(_rowTitles(tester), ['madrid one', 'madrid two']);
    await _close(tester);
  });

  testWidgets('tapping the category opens the browse on it', (tester) async {
    final container = await _open(tester, 'soccer');
    await tester.tap(find.text('Soccer'));
    await _settle(tester);
    final selection = container.read(polyBrowseSelectionProvider);
    expect(selection.pill, PolyPill.sports);
    expect(selection.sub, 'soccer');
    expect(events.where((e) => e.$1 == 'search_result_tapped').last.$2,
        containsPair('result_type', 'category'));
    expect(events.where((e) => e.$1 == 'category_pill_tapped').last.$2,
        {'section': 'sports', 'subcategory': 'soccer', 'source': 'search'});
    // The sheet closed.
    expect(find.byType(TextField), findsNothing);
    await _close(tester);
  });
}
