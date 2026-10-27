// Predictions browses with ONE row of boxed category pills (owner
// decision 2026-10-13). Finance has subcategories: a tap swaps the row for
// "‹ Finance" and All · Daily · …, All selected; the back pill brings the
// categories back with Finance still on screen at its default list, and
// says so to PostHog. A category with none (New) selects and the row
// stays.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show PolyDrillRow;
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/tracking_service.dart';

import '../../helpers/offline_venue_overrides.dart';
import '../usd/investments_harness.dart';

/// Every list empty and read: nothing goes to the network.
class _EmptyFeed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) => const PolyFeedState(done: true);
}

Finder _inBrowser(Finder f) =>
    find.descendant(of: find.byType(PolymarketScreen), matching: f);

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
      'Finance drills in to its back pill and subcategories; back restores '
      'the categories at Finance\'s default list; New stays put',
      (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);

    await pumpInvestments(tester, browsePredictions: true, overrides: [
      polyBrowseFeedProvider.overrideWith(_EmptyFeed.new),
    ]);
    final l10n =
        AppLocalizations.of(tester.element(find.byType(KutePillTabs).first));
    await tapAndPump(tester, investmentsPill(l10n.predictions));
    final container = ProviderScope.containerOf(
        tester.element(find.byType(PolymarketScreen)));

    final row = _inBrowser(find.byType(PolyDrillRow));
    expect(row, findsOneWidget);
    final rowSize = tester.getSize(row);
    expect(_selected(tester, 'Trending'), isTrue);
    expect(_back, findsNothing);

    // New has no subcategories: it selects, the row stays.
    await _tap(tester, _pill('New'));
    await _settle(tester);
    expect(_selected(tester, 'New'), isTrue);
    expect(_back, findsNothing);
    expect(_pill('More ›'), findsOneWidget);

    // Finance drills in: "‹ Finance", then All (selected), Daily …
    await _tap(tester, _pill('Finance'));
    await _settle(tester);
    expect(_pill('Trending'), findsNothing);
    expect(_pill('More ›'), findsNothing);
    expect(_back, findsOneWidget);
    expect(tester.widget<KutePill>(_back).label, 'Finance');
    expect(_selected(tester, 'All'), isTrue);
    expect(_selected(tester, 'Daily'), isFalse);
    expect(tester.getSize(row), rowSize);

    await _tap(tester, _pill('Daily'));
    await _settle(tester);
    expect(_selected(tester, 'Daily'), isTrue);
    expect(container.read(polyBrowseSelectionProvider).sub, 'daily');

    // Back: the categories, Finance still selected, at its default list.
    await _tap(tester, _back);
    await _settle(tester);
    expect(_back, findsNothing);
    expect(_selected(tester, 'Finance'), isTrue);
    expect(container.read(polyBrowseSelectionProvider).pill, PolyPill.finance);
    expect(container.read(polyBrowseSelectionProvider).sub, 'all');

    expect(
        events.where((e) => e.$1 == 'category_pill_tapped').map((e) => e.$2), [
      {'section': 'new'},
      {'section': 'finance'},
      {'section': 'finance', 'subcategory': 'daily'},
    ]);
    expect(
        events
            .where((e) => e.$1 == 'category_row_back_tapped')
            .map((e) => e.$2),
        [
          {'surface': 'predictions', 'parent': 'finance'},
        ]);

    await unmountInvestments(tester);
    // The BTC price feed lets its socket go 30 s after the last listener.
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets(
      'the list is flat markets split by hairlines, under no heading that '
      'repeats the selected pill; "Crypto markets" stays as a small label',
      (tester) async {
    await pumpInvestments(tester,
        browsePredictions: true,
        size: const Size(390, 2400),
        overrides: [
          polyBrowseFeedProvider.overrideWith(_ThreeMarkets.new),
          ...offlineVenueOverrides,
        ]);
    final l10n =
        AppLocalizations.of(tester.element(find.byType(KutePillTabs).first));
    await tapAndPump(tester, investmentsPill(l10n.predictions));

    for (final pill in ['Trending', 'New']) {
      if (pill != 'Trending') {
        await _tap(tester, _pill(pill));
        await _settle(tester);
      }
      expect(_selected(tester, pill), isTrue);
      // The pill names the list: its label is written once, on the pill.
      expect(_inBrowser(find.text(pill)), findsOneWidget);
      expect(find.descendant(of: _pill(pill), matching: find.text(pill)),
          findsOneWidget);

      final cards = _inBrowser(find.byType(MarketCard));
      expect(cards, findsNWidgets(3));
      final dividers = find.descendant(
          of: find.ancestor(of: cards.first, matching: find.byType(SliverList)),
          matching: find.byType(Divider));
      expect(dividers, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final line = tester.getRect(dividers.at(i));
        expect(line.top,
            moreOrLessEquals(tester.getRect(cards.at(i)).bottom, epsilon: 0.5));
        expect(line.bottom,
            moreOrLessEquals(tester.getRect(cards.at(i + 1)).top, epsilon: 0.5));
        expect(tester.widget<Divider>(dividers.at(i)).indent, greaterThan(0));
      }
      for (final box in tester.widgetList<DecoratedBox>(find.descendant(
          of: cards, matching: find.byType(DecoratedBox)))) {
        final d = box.decoration;
        if (d is BoxDecoration) {
          expect(d.boxShadow ?? const <BoxShadow>[], isEmpty);
        }
      }

      // The 5-minute group keeps its label on Trending only, in the
      // quiet section-label style, not as a big heading.
      final crypto = _inBrowser(find.text(l10n.predictionsCryptoMarkets));
      if (pill == 'Trending') {
        expect(crypto, findsOneWidget);
        final style = tester.widget<Text>(crypto).style!;
        final colors = tester.element(crypto).colors;
        expect(style.color, colors.textSecondary);
        expect(style.fontWeight, FontWeight.w600);
        expect(style.fontSize!, lessThan(16));
      } else {
        expect(crypto, findsNothing);
      }
    }

    await unmountInvestments(tester);
    await tester.pump(const Duration(seconds: 31));
  });
}

/// Three open Yes/No markets in every list.
class _ThreeMarkets extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) => PolyFeedState(done: true, events: [
        for (final (id, title) in [
          ('fed', 'Fed cuts in December?'),
          ('btc', 'Bitcoin above 150k?'),
          ('rain', 'Rain in London tomorrow?'),
        ])
          PolymarketEvent(
            id: id,
            slug: id,
            title: title,
            volume: 1e6,
            liquidity: 1e5,
            category: 'finance',
            conditionId: id,
            outcomes: const [
              PolymarketOutcome(name: 'Yes', price: 0.4),
              PolymarketOutcome(name: 'No', price: 0.6),
            ],
          ),
      ]);
}

