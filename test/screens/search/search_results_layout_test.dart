// How results sit on the search sheet: the tabs' own market cards, the
// named market first, four per group under All with a "See all" that
// switches the filter, and skeletons holding a group's place while its
// markets load.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/theme/app_theme.dart';

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

HlMarketSearchResult _hl(String coin) => HlMarketSearchResult(
      coin: coin,
      wireCoin: coin,
      kind: HlMarketKind.perp,
      isStock: false,
      name: null,
      category: 'crypto',
      iconUrl: null,
      markPx: 10,
      dayChangePct: 0.01,
      maxLeverage: 10,
    );

// The venue answers in its own order; the exact ticker is fifth.
final _hits = [
  for (final c in ['WBTC', 'BTCDOM', 'UBTC', 'XBTC', 'BTC', 'TBTC']) _hl(c),
];

Future<ProviderContainer> _open(WidgetTester tester,
    {required AsyncValue<List<HlMarketSearchResult>> hl}) async {
  tester.view.physicalSize = const Size(430, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      aiEnabledProvider.overrideWith((_) async => true),
      sportsLiveProvider.overrideWith(_Sports.new),
      unifiedSearchResultsProvider
          .overrideWith((_) async => UnifiedSearchResults.empty),
      globalMarketResultsProvider
          .overrideWith((_) => const AsyncValue.data([])),
      globalHyperliquidResultsProvider.overrideWith(
          (ref) => ref.watch(searchQueryProvider).isEmpty
              ? const AsyncValue.data([])
              : hl),
      hyperliquidAllMarketsProvider.overrideWith((_) => []),
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
              onPressed: () => showKuteSearch(context, source: 'home'),
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
  await tester.enterText(find.byType(TextField), 'btc');
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
      () async => expect(await AdvisorInputGuard.isSafe('bitcoin'), isTrue));
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  testWidgets('the named market leads, four per group with See all',
      (tester) async {
    final container = await _open(tester, hl: AsyncValue.data(_hits));
    final cards = tester.widgetList<HlMarketCard>(find.byType(HlMarketCard));
    // Investing's own card, the exact ticker first, four under All.
    expect([for (final c in cards) c.market.coin],
        ['BTC', 'BTCDOM', 'WBTC', 'UBTC']);
    expect(find.text('Investing'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);

    await tester.tap(find.text('See all'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(container.read(selectedSearchCategoryProvider),
        SearchCategory.perpetuals);
    expect(find.byType(HlMarketCard), findsNWidgets(6));
    expect(find.text('See all'), findsNothing);
    await _close(tester);
  });

  testWidgets('a loading group holds its place with skeletons, no spinner',
      (tester) async {
    await _open(tester, hl: const AsyncValue.loading());
    expect(find.byType(SkeletonCard), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Searching markets…'), findsNothing);
    expect(find.byType(HlMarketCard), findsNothing);
    await _close(tester);
  });
}
