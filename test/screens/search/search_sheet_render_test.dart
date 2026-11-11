// On demand: renders the Sal sheet's three states into PNGs for a look by
// eye: the home variant empty (Recent, Moving now, Trending predictions
// over the composer), the home variant with results ("tesla" under All),
// and the context variant (a market page's preview card and action rows).
// Light and dark. The app's own fonts; market images are not fetched, so
// every crest falls back to its mark.
//
//   flutter test test/screens/search/search_sheet_render_test.dart \
//     --dart-define=SEARCH_SHEET_RENDER_OUT=/tmp/kute_sal_sheet
//
// Without the define the file does nothing.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/kute_share_actions.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/search_recent_store.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';

const _out = String.fromEnvironment('SEARCH_SHEET_RENDER_OUT');
final _shotKey = GlobalKey();

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
      PolyFeedState(events: _predictions.take(3).toList(), done: true);
}

PolymarketEvent _event(String title,
        {required List<PolymarketOutcome> outcomes}) =>
    PolymarketEvent(
      id: title,
      slug: title.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '-'),
      title: title,
      volume: 1200000,
      liquidity: 50000,
      category: 'other',
      tags: const [],
      endDate: DateTime(2027, 2, 7),
      conditionId: 'c-$title',
      outcomes: outcomes,
    );

final _predictions = [
  _event('Will Bitcoin hit \$150k by March?', outcomes: const [
    PolymarketOutcome(name: 'Yes', price: 0.62),
    PolymarketOutcome(name: 'No', price: 0.38),
  ]),
  _event('Fed decision in December?', outcomes: const [
    PolymarketOutcome(name: 'No change', price: 0.71),
    PolymarketOutcome(name: '25 bps decrease', price: 0.24),
  ]),
  _event('Tesla to deliver 2M cars in 2026?', outcomes: const [
    PolymarketOutcome(name: 'Yes', price: 0.44),
    PolymarketOutcome(name: 'No', price: 0.56),
  ]),
];

HlMarket _market(String coin, double px, double prev,
        {String cat = 'crypto'}) =>
    HlMarket(
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
      category: cat,
      iconUrl: null,
      unitAssetName: null,
    );

final _universe = [
  _market('BTC', 121845, 119200),
  _market('ETH', 4410, 4120),
  _market('SOL', 198.4, 212.1),
  _market('TSLA', 438.21, 429.1, cat: 'stocks'),
  _market('NVDA', 191.2, 182.7, cat: 'stocks'),
  _market('GLD', 3871.4, 3855.3, cat: 'commodities'),
  _market('DOGE', 0.241, 0.262),
  _market('HYPE', 48.2, 44.9),
];

const _investing = [
  HlMarketSearchResult(
      coin: 'TSLA',
      wireCoin: 'xyz:TSLA',
      kind: HlMarketKind.perp,
      isStock: true,
      name: 'Tesla',
      category: 'stocks',
      iconUrl: null,
      markPx: 438.21,
      dayChangePct: 0.0213,
      maxLeverage: 10),
  HlMarketSearchResult(
      coin: 'TSLA',
      wireCoin: '@182',
      kind: HlMarketKind.spot,
      isStock: true,
      name: 'Tesla',
      category: 'stocks',
      iconUrl: null,
      markPx: 437.95,
      dayChangePct: 0.0198),
];

Future<void> _render(
  WidgetTester tester, {
  required String name,
  required bool dark,
  required bool results,
  required bool context,
}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  OpenOnce.reset();
  SearchRecentStore.entries.value = const [
    SearchRecentEntry(
        kind: SearchRecentKind.investing, id: 'BTC', label: 'BTC'),
    SearchRecentEntry(
        kind: SearchRecentKind.query, id: 'fed rates', label: 'fed rates'),
  ];
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      aiEnabledProvider.overrideWith((_) async => true),
      sportsLiveProvider.overrideWith(_Sports.new),
      unifiedSearchResultsProvider
          .overrideWith((_) async => UnifiedSearchResults.empty),
      globalMarketResultsProvider
          .overrideWith((ref) => ref.watch(searchQueryProvider).isEmpty
              ? const AsyncValue.data([])
              : AsyncValue.data([
                  GlobalMarketSearchResult(_predictions[2]),
                  GlobalMarketSearchResult(_predictions[0]),
                ])),
      globalHyperliquidResultsProvider.overrideWith((ref) =>
          ref.watch(searchQueryProvider).isEmpty
              ? const AsyncValue.data([])
              : const AsyncValue.data(_investing)),
      hyperliquidAllMarketsProvider.overrideWith((_) => _universe),
      hyperliquidBrowseUniverseProvider
          .overrideWith((_) => AsyncValue.data(_universe)),
      polyBrowseFeedProvider.overrideWith(_Feed.new),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            RepaintBoundary(key: _shotKey, child: child),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => showKuteSearch(
                  ctx,
                  initialCategory:
                      context ? SearchCategory.predictions : SearchCategory.all,
                  searchFirst: true,
                  source: context ? 'predictions' : 'home',
                  barContext: context
                      ? KuteMarketBarContext(
                          label: 'Share with your friends',
                          clip: 'share',
                          preview: const KuteBarPreview(
                              title: 'Will Bitcoin hit \$150k by March?',
                              line: 'Yes 62%'),
                          category: SearchCategory.predictions,
                          actions: [
                            KuteMarketBarAction(
                              label: 'Share the market',
                              sublabel: 'A link they can open, with your code',
                              icon: Icons.ios_share_rounded,
                              onTap: (_) {},
                            ),
                            KuteMarketBarAction(
                              label: 'Send this prediction',
                              sublabel: 'They get your pick, ready to place',
                              salClip: 'share',
                              onTap: (_) {},
                            ),
                          ],
                        )
                      : null,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  if (results) {
    await tester.enterText(find.byType(TextField), 'tesla');
    await tester.pump(const Duration(milliseconds: 200));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
  for (Object? e = tester.takeException();
      e != null;
      e = tester.takeException()) {
    final text = '$e'.split('\n').first;
    if (!text.contains('MissingPlugin') && !text.contains('HTTP')) {
      // ignore: avoid_print
      print('RENDER problem: $text');
    }
  }
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  // ignore: avoid_print
  print('RENDER wrote $name.png');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  // Moving now lists only markets with a logo of their own: the movers'
  // logos are known.
  setUp(() {
    for (final m in _universe) {
      HlIconAvailability.debugSeed(m);
    }
  });
  tearDown(HlIconPrefetch.debugReset);
  if (_out.isEmpty) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    Directory(_out).createSync(recursive: true);
    expect(await AdvisorInputGuard.isSafe('tesla'), isTrue);
  });
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('home empty $mode', (tester) async {
      await _render(tester,
          name: 'home_empty_$mode', dark: dark, results: false, context: false);
    });
    testWidgets('home results $mode', (tester) async {
      await _render(tester,
          name: 'home_results_$mode',
          dark: dark,
          results: true,
          context: false);
    });
    testWidgets('context $mode', (tester) async {
      await _render(tester,
          name: 'context_$mode', dark: dark, results: false, context: true);
    });
  }
}
