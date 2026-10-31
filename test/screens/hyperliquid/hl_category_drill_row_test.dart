// Investing browses with ONE row of boxed category pills (owner decision
// 2026-10-13). Tradfi and Crypto have subcategories: a tap swaps the row
// for "‹ Tradfi" and Stocks · Indices …, the first selected; the back pill
// brings the categories back with Tradfi still on screen at its default
// list, and says so to PostHog. A category with none (Trending, Perps)
// selects and the row stays.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/shared/animations/premium_group_container.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show PolyDrillRow;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/tracking_service.dart';

import '../usd/investments_harness.dart';

HlMarket _market(String coin,
        {String category = 'crypto', bool isHip3 = false, double vlm = 1e6}) =>
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
      prevDayPx: 99,
      dayNtlVlm: vlm,
      category: category,
      isHip3: isHip3,
      dex: isHip3 ? 'xyz' : '',
    );

final _universe = [
  _market('BTC', vlm: 9e9),
  _market('DOGE', vlm: 5e8),
  _market('xyz:AAPL', category: 'stocks', isHip3: true),
  _market('xyz:SPX', category: 'indices', isHip3: true),
];

Finder _inBrowser(Finder f) =>
    find.descendant(of: find.byType(HyperliquidScreen), matching: f);

Finder _pill(String label) => _inBrowser(find.widgetWithText(KutePill, label));

final _back = _inBrowser(find.byKey(const ValueKey('kute-back-pill')));

bool _selected(WidgetTester tester, String label) =>
    tester.widget<KutePill>(_pill(label)).selected;

/// Brings [f] into view (the row side-scrolls) and taps it.
Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'Tradfi drills in to its back pill and subcategories; back restores '
      'the categories at Tradfi\'s default list; Trending stays put',
      (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);

    // The drill row is the venue screen's own (a Ledger's Investing
    // tab); inside Investments the page's pill carries the category.
    await pumpInvestments(tester,
        browseInvesting: true,
        child: const Scaffold(body: HyperliquidScreen()),
        overrides: [
          hyperliquidBrowseUniverseProvider
              .overrideWithValue(AsyncValue.data(_universe)),
          hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
        ]);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(HyperliquidScreen)));

    final row = _inBrowser(find.byType(PolyDrillRow));
    expect(row, findsOneWidget);
    final rowSize = tester.getSize(row);
    expect(_selected(tester, 'Trending'), isTrue);
    expect(_back, findsNothing);
    expect(_pill('Stocks'), findsNothing);

    // Every pill on the row is the boxed chip with a 44 pt hit target.
    expect(tester.getSize(_pill('Traditional')).height, greaterThanOrEqualTo(44));

    // Perps has no subcategories: it selects, the row stays.
    await _tap(tester, _pill('Perps'));
    await _settle(tester);
    expect(_selected(tester, 'Perps'), isTrue);
    expect(_back, findsNothing);
    expect(_pill('Trending'), findsOneWidget);

    // Tradfi drills in: "‹ Tradfi", then Stocks (selected) and Indices.
    await _tap(tester, _pill('Traditional'));
    await _settle(tester);
    expect(_pill('Trending'), findsNothing);
    expect(_back, findsOneWidget);
    expect(tester.widget<KutePill>(_back).label, 'Traditional');
    expect(tester.widget<KutePill>(_back).icon, Icons.chevron_left_rounded);
    expect(_selected(tester, 'Stocks'), isTrue);
    expect(_selected(tester, 'Indices'), isFalse);
    expect(tester.getSize(row), rowSize);

    await _tap(tester, _pill('Indices'));
    await _settle(tester);
    expect(_selected(tester, 'Indices'), isTrue);
    expect(container.read(hlBrowseSelectionProvider).sub, HlBrowseSub.indices);

    // Back: the categories, Tradfi still selected, at its default list.
    await _tap(tester, _back);
    await _settle(tester);
    expect(_back, findsNothing);
    expect(_selected(tester, 'Traditional'), isTrue);
    expect(container.read(hlBrowseSelectionProvider).tab, HlBrowseTab.tradfi);
    expect(container.read(hlBrowseSelectionProvider).sub, HlBrowseSub.all);

    // Tapped again, Tradfi drills in again on its first subcategory.
    await _tap(tester, _pill('Traditional'));
    await _settle(tester);
    expect(_back, findsOneWidget);
    expect(_selected(tester, 'Stocks'), isTrue);

    final names = events.map((e) => e.$1).toList();
    expect(
        events.where((e) => e.$1 == 'hl_category_pill_tapped').map((e) => e.$2),
        [
          {'section': 'perps'},
          {'section': 'tradfi'},
          {'section': 'tradfi', 'subcategory': 'indices'},
        ]);
    expect(names.where((n) => n == 'category_row_back_tapped'), hasLength(1));
    expect(events.firstWhere((e) => e.$1 == 'category_row_back_tapped').$2,
        {'surface': 'investing', 'parent': 'tradfi'});

    await unmountInvestments(tester);
  });

  testWidgets(
      'the list sits under no title, in one grouped card like Home\'s '
      'Activity', (tester) async {
    await pumpInvestments(tester,
        browseInvesting: true,
        size: const Size(390, 2000),
        child: const Scaffold(body: HyperliquidScreen()),
        overrides: [
          hyperliquidBrowseUniverseProvider
              .overrideWithValue(AsyncValue.data(_universe)),
          hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
        ]);

    for (final pill in ['Trending', 'Perps']) {
      if (pill != 'Trending') {
        await _tap(tester, _pill(pill));
        await _settle(tester);
      }
      expect(_selected(tester, pill), isTrue);
      // The pill names the list: its label is written once, on the pill.
      expect(_inBrowser(find.text(pill)), findsOneWidget);
      expect(
          find.descendant(of: _pill(pill), matching: find.text(pill)),
          findsOneWidget);

      final rows = _inBrowser(find.byType(HlMarketCard));
      final n = rows.evaluate().length;
      expect(n, greaterThan(1));
      // The list comes straight under the pills.
      final pills = _inBrowser(find.byType(PolyDrillRow));
      expect(tester.getRect(rows.first).top - tester.getRect(pills).bottom,
          lessThan(20));

      // ONE grouped card, Home Activity's, holds every row: no card per
      // market, Home's inset hairline between rows.
      final group = _inBrowser(find.byType(DecoratedSliver));
      expect(group, findsOneWidget);
      final context = tester.element(rows.first);
      expect(tester.widget<DecoratedSliver>(group).decoration,
          PremiumGroupContainer.decorationOf(context));
      expect(find.descendant(of: group, matching: find.byType(HlMarketCard)),
          findsNWidgets(n));
      for (final row in tester.widgetList<HlMarketCard>(rows)) {
        expect(row.inGroup, isTrue);
      }
      // Investing rows draw no hairline between them (the rows' own
      // padding separates them, as Robinhood / Public do): the rows abut.
      expect(find.descendant(of: group, matching: find.byType(Divider)),
          findsNothing);
      for (var i = 0; i < n - 1; i++) {
        expect(tester.getRect(rows.at(i + 1)).top,
            moreOrLessEquals(tester.getRect(rows.at(i)).bottom, epsilon: 0.5));
      }
      // The press ink of the first and last rows is clipped to the card's
      // corners.
      for (final row in [rows.first, rows.last]) {
        expect(find.ancestor(of: row, matching: find.byType(ClipRRect)),
            findsWidgets);
      }
    }

    await unmountInvestments(tester);
  });
}

