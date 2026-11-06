// Tapping the bar while it reads "Pick a market group" over the
// Investments category sheet (investments_category_sheet.dart; founder,
// 1 November 2026: "user has clicked, so show the market categories"):
// the Sal sheet opens with EVERY category of the venue under its
// composer, as the category grid's own cards in a two-column grid (the
// same 96 px card for both venues since 6 November 2026, an odd last one
// full width), the picked one in the white-pill style; never the generic
// arrow cards. A tap on a tile picks it and closes both sheets.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/advisor_context.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/usd/investments_category_sheet.dart';
import 'package:kute/screens/usd/usd_account_screen.dart' show InvestmentsTab;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import 'investments_harness.dart';

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

class _Advisor extends AdvisorSessionNotifier {
  @override
  AdvisorSessionState build() => const AdvisorSessionState();

  @override
  Future<void> ask(String query,
      {AdvisorContext? context,
      String input = 'typed',
      String? template,
      int? chipIndex,
      String? locale}) async {}
}

HlMarket _m(String coin, double mark, double prev, double vlm,
        {HlMarketKind kind = HlMarketKind.perp}) =>
    HlMarket(
        coin: coin,
        wireCoin: coin,
        assetId: coin.hashCode,
        kind: kind,
        szDecimals: 2,
        maxLeverage: 1,
        onlyIsolated: false,
        markPx: mark,
        midPx: mark,
        prevDayPx: prev,
        dayNtlVlm: vlm);

final _universe = [
  _m('BTC', 100, 98, 9e8),
  _m('ETH', 100, 95, 5e8),
  _m('SOL', 100, 104, 3e8),
  _m('HYPE', 100, 110, 2e8),
  _m('PURR', 1, 0.9, 1e6, kind: HlMarketKind.spot),
];

/// The page under the sheets: a button opening [tab]'s categories. A
/// sheet under 60% of the screen hides the bar (app_bottom_sheet.dart):
/// the five test markets make a short Investing sheet, so its test runs
/// on a shorter screen.
Future<void> _pump(WidgetTester tester, InvestmentsTab tab,
    {Size size = const Size(390, 844)}) async {
  await pumpInvestments(
    tester,
    size: size,
    overrides: [
      advisorSessionProvider.overrideWith(_Advisor.new),
      sportsLiveProvider.overrideWith(_Sports.new),
      unifiedSearchResultsProvider
          .overrideWith((_) async => UnifiedSearchResults.empty),
      globalMarketResultsProvider
          .overrideWith((_) => const AsyncValue.data([])),
      globalHyperliquidResultsProvider
          .overrideWith((_) => const AsyncValue.data([])),
      hyperliquidAllMarketsProvider.overrideWith((_) => []),
      hyperliquidBrowseUniverseProvider
          .overrideWith((_) => AsyncValue.data(_universe)),
    ],
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
  await tapAndPump(tester, find.text('Open categories'));
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

/// What tapping the bar does (kute_shell_bar.dart, openKuteBarSheet): the
/// Sal sheet with the top context, its home under the composer.
Future<KuteBarContext> _tapBar(WidgetTester tester) async {
  final ctx = kuteBarTop(_container(tester).read(kuteBarContextProvider))!;
  expect(ctx.label, 'Pick a market group');
  // ignore: discarded_futures
  showKuteSearch(
    tester.element(find.byType(Scaffold).first),
    initialCategory: ctx.category,
    searchFirst: true,
    searchHint: ctx.searchHint,
    source: ctx.source,
    barContext: ctx,
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return ctx;
}

final _grid = find.byKey(const ValueKey('sal-category-grid'));

Finder _salTile(String key) => find.byKey(ValueKey('sal-category-tile-$key'));

BoxDecoration _box(WidgetTester tester, Finder tile) => tester
    .widget<AnimatedContainer>(
        find.descendant(of: tile, matching: find.byType(AnimatedContainer)))
    .decoration! as BoxDecoration;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'Predictions: every topic as the grid\'s own glyph tiles, two columns, '
      'Trending picked; no generic cards; a tap picks and closes both sheets',
      (tester) async {
    final events = recordEvents();
    await _pump(tester, InvestmentsTab.predictions);
    final ctx = await _tapBar(tester);
    expect(ctx.actions, isEmpty, reason: 'no recommended rows any more');
    expect(ctx.sheetHome, isNotNull);

    // The grid under the composer: every topic on offer, each with
    // Polymarket's own glyph and its name, in two columns of Investing's
    // 96 px cards.
    expect(_grid, findsOneWidget);
    final policy = _container(tester).read(runtimeCapabilitiesProvider);
    final offered = [
      for (final p in PolyPill.values)
        if (p != PolyPill.watchlist && polyPillOffered(p, policy)) p,
    ];
    expect(offered.length, greaterThan(6));
    for (final p in offered.take(4)) {
      expect(_salTile(p.key), findsOneWidget, reason: p.key);
      expect(
          find.descendant(
              of: _salTile(p.key),
              matching: find.byKey(ValueKey('category-tile-icon-${p.key}'))),
          findsOneWidget,
          reason: '${p.key} glyph');
    }
    final first = tester.getRect(_salTile(offered[0].key));
    final second = tester.getRect(_salTile(offered[1].key));
    expect(second.top, first.top, reason: 'two columns');
    expect(second.left, greaterThan(first.right));
    expect(first.height, 96);
    expect(tester.getRect(_salTile(offered[2].key)).left, first.left);

    // The picked one in the white-pill style, the others flat.
    final light = AppColorsExtension.light();
    expect(_box(tester, _salTile(PolyPill.trending.key)).color, Colors.white);
    expect(_box(tester, _salTile(PolyPill.trending.key)).border!.top.color,
        light.border);
    expect(_box(tester, _salTile(PolyPill.politics.key)).color,
        light.surfaceLight);

    // Never the generic arrow cards.
    expect(find.byKey(const ValueKey('context-actions-card')), findsNothing);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);

    // A tap picks it and both sheets close.
    await tester.ensureVisible(_salTile(PolyPill.politics.key));
    await tester.tap(_salTile(PolyPill.politics.key));
    await tester.pump();
    expect(_box(tester, _salTile(PolyPill.politics.key)).color, Colors.white,
        reason: 'the pick springs on before the sheets go');
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_grid, findsNothing);
    expect(find.byKey(ValueKey('category-tile-${PolyPill.politics.key}')),
        findsNothing,
        reason: 'the category sheet closed too');
    expect(find.text('Open categories'), findsOneWidget);
    expect(_container(tester).read(polyBrowseSelectionProvider).pill,
        PolyPill.politics);
    expect(events.where((e) => e.$1 == 'category_pill_tapped').single.$2,
        {'section': PolyPill.politics.key});
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'Investing: every category as the grid\'s logo-stack tiles; a tap '
      'picks and closes both sheets', (tester) async {
    await _pump(tester, InvestmentsTab.investing, size: const Size(390, 520));
    await _tapBar(tester);
    expect(_grid, findsOneWidget);
    expect(_salTile(HlBrowseTab.trending.key), findsOneWidget);
    expect(_salTile(HlBrowseTab.perps.key), findsOneWidget);
    expect(_salTile(HlBrowseTab.spot.key), findsOneWidget);
    expect(tester.getSize(_salTile(HlBrowseTab.trending.key)).height, 96);
    expect(_box(tester, _salTile(HlBrowseTab.trending.key)).color,
        Colors.white);
    expect(find.byKey(const ValueKey('context-actions-card')), findsNothing);

    await tester.ensureVisible(_salTile(HlBrowseTab.spot.key));
    await tester.tap(_salTile(HlBrowseTab.spot.key));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_grid, findsNothing);
    expect(find.text('Open categories'), findsOneWidget);
    expect(find.byKey(ValueKey('category-tile-${HlBrowseTab.spot.key}')),
        findsNothing);
    final sel = _container(tester).read(hlBrowseSelectionProvider);
    expect(sel.tab, HlBrowseTab.spot);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });
}
