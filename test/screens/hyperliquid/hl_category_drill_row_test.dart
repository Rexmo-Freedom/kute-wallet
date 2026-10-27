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

    await pumpInvestments(tester, browseInvesting: true, overrides: [
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
    expect(tester.getSize(_pill('Tradfi')).height, greaterThanOrEqualTo(44));

    // Perps has no subcategories: it selects, the row stays.
    await _tap(tester, _pill('Perps'));
    await _settle(tester);
    expect(_selected(tester, 'Perps'), isTrue);
    expect(_back, findsNothing);
    expect(_pill('Trending'), findsOneWidget);

    // Tradfi drills in: "‹ Tradfi", then Stocks (selected) and Indices.
    await _tap(tester, _pill('Tradfi'));
    await _settle(tester);
    expect(_pill('Trending'), findsNothing);
    expect(_back, findsOneWidget);
    expect(tester.widget<KutePill>(_back).label, 'Tradfi');
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
    expect(_selected(tester, 'Tradfi'), isTrue);
    expect(container.read(hlBrowseSelectionProvider).tab, HlBrowseTab.tradfi);
    expect(container.read(hlBrowseSelectionProvider).sub, HlBrowseSub.all);

    // Tapped again, Tradfi drills in again on its first subcategory.
    await _tap(tester, _pill('Tradfi'));
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
      'the list is flat rows split by hairlines, under no heading that '
      'repeats the selected pill', (tester) async {
    await pumpInvestments(tester,
        browseInvesting: true,
        size: const Size(390, 2000),
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
      final dividers = _inBrowser(find.byType(Divider));
      expect(dividers, findsNWidgets(n - 1));
      for (var i = 0; i < n - 1; i++) {
        final line = tester.getRect(dividers.at(i));
        // Each hairline sits between two rows, inset to the rows' text.
        expect(line.top,
            moreOrLessEquals(tester.getRect(rows.at(i)).bottom, epsilon: 0.5));
        expect(line.bottom,
            moreOrLessEquals(tester.getRect(rows.at(i + 1)).top, epsilon: 0.5));
        expect(tester.widget<Divider>(dividers.at(i)).indent, greaterThan(0));
        expect(tester.widget<Divider>(dividers.at(i)).thickness, 0.5);
      }
      // Rows, not cards: no shadow behind a market.
      for (final box in tester.widgetList<DecoratedBox>(find.descendant(
          of: rows, matching: find.byType(DecoratedBox)))) {
        final d = box.decoration;
        if (d is BoxDecoration) {
          expect(d.boxShadow ?? const <BoxShadow>[], isEmpty);
        }
      }
    }

    await unmountInvestments(tester);
  });
}

